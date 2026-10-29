import { Env } from './types';
import { FirestoreClient } from './firestore';

export interface FcmNotificationPayload {
  token: string;
  title: string;
  body: string;
  data?: Record<string, string>;
  channelId?: string;
}

export class FcmClient {
  private projectId: string;
  private firestoreClient: FirestoreClient;

  constructor(env: Env, firestoreClient: FirestoreClient) {
    this.projectId = env.FIREBASE_PROJECT_ID;
    this.firestoreClient = firestoreClient;
  }

  async sendNotification(
    payload: FcmNotificationPayload
  ): Promise<{ success: boolean; error?: string; messageId?: string }> {
    try {
      const accessToken = await this.firestoreClient.getAccessToken();
      const url = `https://fcm.googleapis.com/v1/projects/${this.projectId}/messages:send`;

      const requestBody = {
        message: {
          token: payload.token,
          notification: {
            title: payload.title,
            body: payload.body,
          },
          data: payload.data || {},
          android: {
            priority: 'HIGH',
            notification: {
              channel_id: payload.channelId || 'cash_reminder_channel',
              sound: 'default',
              default_vibrate_timings: true,
              notification_priority: 'PRIORITY_MAX',
            },
          },
        },
      };

      const res = await fetch(url, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(requestBody),
      });

      if (!res.ok) {
        const errText = await res.text();
        console.error(`FCM v1 send failed (${res.status}):`, errText);
        return { success: false, error: errText };
      }

      const result = (await res.json()) as { name?: string };
      return { success: true, messageId: result.name };
    } catch (e: any) {
      console.error('Error in FcmClient.sendNotification:', e);
      return { success: false, error: e?.message || String(e) };
    }
  }

  // Helper untuk memproses pengingat tunai bagi semua user yang jadwalnya cocok
  async processCashReminders(): Promise<{ sentCount: number; errors: string[] }> {
    const errors: string[] = [];
    let sentCount = 0;

    try {
      const users = await this.firestoreClient.getAllDocuments('users');
      const now = new Date();

      for (const user of users) {
        const u = user.data;
        const fcmToken = u.fcm_token;
        const isEnabled = u.cash_reminder_enabled !== false; // default true jika belum diset
        const targetHour = typeof u.cash_reminder_hour === 'number' ? u.cash_reminder_hour : 20;
        const targetMinute = typeof u.cash_reminder_minute === 'number' ? u.cash_reminder_minute : 30;
        const offsetMinutes = typeof u.timezone_offset === 'number' ? u.timezone_offset : 420; // default WIB (+7 jam)

        if (!fcmToken || !isEnabled) continue;

        // Hitung waktu saat ini dalam timezone lokal user
        const userLocalNow = new Date(now.getTime() + offsetMinutes * 60 * 1000);
        const userHour = userLocalNow.getUTCHours();
        const userMinute = userLocalNow.getUTCMinutes();
        const todayDateStr = userLocalNow.toISOString().split('T')[0];

        // Cek apakah sudah pernah dikirim hari ini
        if (u.last_cash_reminder_sent_date === todayDateStr) continue;

        // Cron jalan berkala tiap 15 menit (menit 0, 15, 30, 45).
        // Trigger HANYA jika waktu sekarang telah mencapai target, dan belum lewat 1 interval cron (0 <= diff < 15 menit).
        // Jangan pernah kirim sebelum waktu target tiba!
        const currentTotalMinutes = userHour * 60 + userMinute;
        const targetTotalMinutes = targetHour * 60 + targetMinute;
        const diff = currentTotalMinutes - targetTotalMinutes;

        if (diff >= 0 && diff < 15) {
          const res = await this.sendNotification({
            token: fcmToken,
            title: 'Pengingat Pengeluaran Tunai 💵',
            body: 'Ada transaksi tunai atau jajan hari ini yang belum dicatat di aplikasi?',
            channelId: 'cash_reminder_channel',
            data: {
              type: 'CASH_REMINDER',
              click_action: 'FLUTTER_NOTIFICATION_CLICK',
            },
          });

          if (res.success) {
            sentCount++;
            // Update Firestore agar tidak terkirim dua kali di hari yang sama
            await this.firestoreClient.setDocument('users', user.id, {
              ...u,
              last_cash_reminder_sent_date: todayDateStr,
              last_cash_reminder_sent_at: new Date().toISOString(),
            });
            console.log(`[FCM] Cash reminder sent successfully to user ${user.id} at ${userHour}:${userMinute}`);
          } else {
            errors.push(`User ${user.id}: ${res.error}`);
          }
        }
      }
    } catch (err: any) {
      errors.push(`Process reminders error: ${err?.message || String(err)}`);
    }

    return { sentCount, errors };
  }

  // Helper untuk memproses pengingat jatuh tempo utang / tagihan rutin via FCM
  async processDebtDueReminders(): Promise<{ sentCount: number; errors: string[] }> {
    const errors: string[] = [];
    let sentCount = 0;

    try {
      const users = await this.firestoreClient.getAllDocuments('users');
      const now = new Date();

      for (const user of users) {
        const u = user.data;
        const fcmToken = u.fcm_token;
        const isEnabled = u.due_date_alert_enabled !== false;
        const offsetHours = typeof u.due_date_offset_hours === 'number' ? u.due_date_offset_hours : 24;
        const offsetMinutes = typeof u.timezone_offset === 'number' ? u.timezone_offset : 420;

        if (!fcmToken || !isEnabled) continue;

        const userLocalNow = new Date(now.getTime() + offsetMinutes * 60 * 1000);
        const debts = await this.firestoreClient.queryCollection('debts', 'user_id', 'EQUAL', user.id);

        for (const debtDoc of debts) {
          const debt = debtDoc.data;
          const isPaid = debt.is_paid === true;
          const isRecurring = debt.is_recurring === true;
          const recurringDay = typeof debt.recurring_day === 'number' ? debt.recurring_day : null;
          const dueDateStr = debt.due_date ? String(debt.due_date) : null;

          // Jika bukan berulang dan sudah lunas, lewati
          if (!isRecurring && isPaid) continue;

          // Hitung nextDueDate
          let nextDue: Date | null = null;
          if (isRecurring && recurringDay !== null) {
            const year = userLocalNow.getUTCFullYear();
            const month = userLocalNow.getUTCMonth(); // 0-based
            const lastDayThisMonth = new Date(Date.UTC(year, month + 1, 0)).getUTCDate();
            const targetDayThisMonth = Math.min(Math.max(1, recurringDay), lastDayThisMonth);
            const dueThisMonth = new Date(Date.UTC(year, month, targetDayThisMonth, 23, 59, 59));

            if (dueThisMonth.getTime() > userLocalNow.getTime() && !isPaid) {
              nextDue = dueThisMonth;
            } else {
              const nextMonth = month === 11 ? 0 : month + 1;
              const nextYear = month === 11 ? year + 1 : year;
              const lastDayNextMonth = new Date(Date.UTC(nextYear, nextMonth + 1, 0)).getUTCDate();
              const targetDayNextMonth = Math.min(Math.max(1, recurringDay), lastDayNextMonth);
              nextDue = new Date(Date.UTC(nextYear, nextMonth, targetDayNextMonth, 23, 59, 59));
            }
          } else if (dueDateStr) {
            const parsed = new Date(dueDateStr);
            if (!isNaN(parsed.getTime())) {
              if (parsed.getUTCHours() === 0 && parsed.getUTCMinutes() === 0) {
                nextDue = new Date(Date.UTC(parsed.getUTCFullYear(), parsed.getUTCMonth(), parsed.getUTCDate(), 23, 59, 59));
              } else {
                nextDue = parsed;
              }
            }
          }

          if (!nextDue) continue;

          // Waktu trigger pengingat = nextDue - offsetHours
          const alertTime = new Date(nextDue.getTime() - offsetHours * 3600 * 1000);
          const nextDueCycleKey = nextDue.toISOString().split('T')[0];

          // Trigger jika waktu saat ini sudah mencapai alertTime dan belum lewat 24 jam setelah jatuh tempo
          if (
            userLocalNow.getTime() >= alertTime.getTime() &&
            userLocalNow.getTime() <= nextDue.getTime() + 24 * 3600 * 1000
          ) {
            // Cek apakah untuk siklus ini sudah pernah dikirimkan
            if (debt.last_due_reminder_sent_cycle === nextDueCycleKey) {
              continue;
            }

            const person = debt.person_name || 'Tagihan';
            const amount = debt.remaining_amount || debt.amount || 0;
            const isBorrowed = debt.type === 'borrowed';
            const typeLabel = isBorrowed ? 'Bayar Utang' : 'Tagih Piutang';
            const formattedAmount = `Rp ${Number(amount).toLocaleString('id-ID')}`;

            const diffMs = nextDue.getTime() - userLocalNow.getTime();
            const diffHours = Math.round(diffMs / (3600 * 1000));
            let dueLabel = '';
            if (diffHours <= 0) {
              dueLabel = 'hari ini (Segera)';
            } else if (diffHours < 24) {
              dueLabel = `${diffHours} jam lagi`;
            } else {
              const days = Math.ceil(diffHours / 24);
              dueLabel = `${days} hari lagi`;
            }

            const res = await this.sendNotification({
              token: fcmToken,
              title: `⏰ Pengingat Jatuh Tempo: ${typeLabel}`,
              body: `${typeLabel} kepada ${person} sebesar ${formattedAmount} jatuh tempo ${dueLabel}.`,
              channelId: 'due_date_channel',
              data: {
                type: 'DUE_DATE_REMINDER',
                debtId: debtDoc.id,
                click_action: 'FLUTTER_NOTIFICATION_CLICK',
              },
            });

            if (res.success) {
              sentCount++;
              // Simpan last_due_reminder_sent_cycle agar tidak dikirim berulang kali pada siklus yang sama
              await this.firestoreClient.setDocument('debts', debtDoc.id, {
                ...debt,
                last_due_reminder_sent_cycle: nextDueCycleKey,
                last_due_reminder_sent_at: new Date().toISOString(),
              });
              console.log(`[FCM] Due date reminder sent for debt ${debtDoc.id} to user ${user.id}`);
            } else {
              errors.push(`Debt ${debtDoc.id}: ${res.error}`);
            }
          }
        }
      }
    } catch (err: any) {
      errors.push(`Process debt reminders error: ${err?.message || String(err)}`);
    }

    return { sentCount, errors };
  }

  // Helper untuk memproses pengingat transaksi rutin (recurring_transactions) via FCM
  async processRecurringReminders(): Promise<{ sentCount: number; errors: string[] }> {
    const errors: string[] = [];
    let sentCount = 0;

    try {
      const users = await this.firestoreClient.getAllDocuments('users');
      const now = new Date();

      for (const user of users) {
        const u = user.data;
        const fcmToken = u.fcm_token;
        const isEnabled = u.recurring_alert_enabled !== false;
        const offsetHours = typeof u.recurring_offset_hours === 'number' ? u.recurring_offset_hours : 24;
        const offsetMinutes = typeof u.timezone_offset === 'number' ? u.timezone_offset : 420;

        if (!fcmToken || !isEnabled) continue;

        const userLocalNow = new Date(now.getTime() + offsetMinutes * 60 * 1000);
        const recurringList = await this.firestoreClient.queryCollection(
          'recurring_transactions',
          'user_id',
          'EQUAL',
          user.id
        );

        for (const rDoc of recurringList) {
          const r = rDoc.data;
          const isActive = r.is_active !== false;
          if (!isActive) continue;

          const nextDueStr = r.next_due_date ? String(r.next_due_date) : null;
          if (!nextDueStr) continue;

          const nextDue = new Date(nextDueStr);
          if (isNaN(nextDue.getTime())) continue;

          // Waktu trigger pengingat = nextDue - offsetHours
          const alertTime = new Date(nextDue.getTime() - offsetHours * 3600 * 1000);
          const nextDueCycleKey = nextDue.toISOString().split('T')[0];

          // Trigger jika waktu saat ini berada di antara alertTime dan nextDue (+24 jam batas toleransi)
          if (
            userLocalNow.getTime() >= alertTime.getTime() &&
            userLocalNow.getTime() <= nextDue.getTime() + 24 * 3600 * 1000
          ) {
            // Cek apakah untuk siklus ini sudah pernah dikirim
            if (r.last_reminder_sent_cycle === nextDueCycleKey) {
              continue;
            }

            const name = r.name || r.title || 'Transaksi Rutin';
            const amount = r.amount || 0;
            const typeLabel = r.type === 'income' ? 'Pemasukan Rutin' : 'Pengeluaran Rutin';
            const formattedAmount = `Rp ${Number(amount).toLocaleString('id-ID')}`;

            const diffMs = nextDue.getTime() - userLocalNow.getTime();
            const diffHours = Math.round(diffMs / (3600 * 1000));
            let dueLabel = '';
            if (diffHours <= 0) {
              dueLabel = 'hari ini (Segera)';
            } else if (diffHours < 24) {
              dueLabel = `${diffHours} jam lagi`;
            } else {
              const days = Math.ceil(diffHours / 24);
              dueLabel = `${days} hari lagi`;
            }

            const res = await this.sendNotification({
              token: fcmToken,
              title: `🔄 Pengingat Transaksi Rutin: ${name}`,
              body: `${typeLabel} "${name}" sebesar ${formattedAmount} jatuh tempo ${dueLabel}.`,
              channelId: 'recurring_channel',
              data: {
                type: 'RECURRING_REMINDER',
                recurringId: rDoc.id,
                click_action: 'FLUTTER_NOTIFICATION_CLICK',
              },
            });

            if (res.success) {
              sentCount++;
              // Simpan last_reminder_sent_cycle agar tidak dikirim dobel dalam 1 siklus
              await this.firestoreClient.setDocument('recurring_transactions', rDoc.id, {
                ...r,
                last_reminder_sent_cycle: nextDueCycleKey,
                last_reminder_sent_at: new Date().toISOString(),
              });
              console.log(`[FCM] Recurring reminder sent for ${rDoc.id} to user ${user.id}`);
            } else {
              errors.push(`Recurring ${rDoc.id}: ${res.error}`);
            }
          }
        }
      }
    } catch (err: any) {
      errors.push(`Process recurring reminders error: ${err?.message || String(err)}`);
    }

    return { sentCount, errors };
  }

}

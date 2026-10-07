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

      // Hitung waktu saat ini dalam WIB (UTC+7)
      const wibHour = (now.getUTCHours() + 7) % 24;
      const wibMinute = now.getUTCMinutes();
      const todayDateStr = new Date(now.getTime() + 7 * 3600 * 1000)
        .toISOString()
        .split('T')[0];

      for (const user of users) {
        const u = user.data;
        const fcmToken = u.fcm_token;
        const isEnabled = u.cash_reminder_enabled !== false; // default true jika belum diset
        const targetHour = typeof u.cash_reminder_hour === 'number' ? u.cash_reminder_hour : 22;
        const targetMinute = typeof u.cash_reminder_minute === 'number' ? u.cash_reminder_minute : 0;
        const lastSentDate = u.last_cash_reminder_sent_date;

        if (!fcmToken || !isEnabled) continue;

        // Cek apakah sudah pernah dikirim hari ini
        if (lastSentDate === todayDateStr) continue;

        // Cocokkan jam dan toleransi menit (dalam interval cron 15 menit)
        const isHourMatch = wibHour === targetHour;
        const isMinuteMatch = Math.abs(wibMinute - targetMinute) <= 15;

        if (isHourMatch && isMinuteMatch) {
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
            console.log(`[FCM] Cash reminder sent successfully to user ${user.id}`);
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
}

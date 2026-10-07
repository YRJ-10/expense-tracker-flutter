import { Env } from './types';
import { FirestoreClient } from './firestore';
import { GmailClient } from './gmail';
import { ParserRegistry, parseWithGeminiFallback } from './parsers';
import { FcmClient } from './fcm';

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;

    // CORS Headers
    const corsHeaders = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    };

    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders });
    }

    try {
      // Helper untuk validasi API Secret Bearer Token
      const isAuthorized = (): boolean => {
        const authHeader = request.headers.get('Authorization') || '';
        const token = authHeader.replace(/^Bearer\s+/i, '').trim();
        const validToken = env.WORKER_AUTH_TOKEN;
        return !!validToken && token.length > 0 && token === validToken;
      };

      // 0. Security Guard: Gembok semua endpoint /api/* dengan Bearer Auth
      if (path.startsWith('/api/')) {
        if (!isAuthorized()) {
          return new Response(
            JSON.stringify({ error: 'Unauthorized: Akses ditolak. Kunci otentikasi tidak valid.' }),
            { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
          );
        }
      }

      // 1. Health Check
      if (path === '/' || path === '/health') {
        return new Response(
          JSON.stringify({
            status: 'ok',
            service: 'Expense Tracker Gmail Sync Backend',
            time: new Date().toISOString(),
          }),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      // 2. OAuth Login: Memulai proses otorisasi Gmail
      if (path === '/auth/login') {
        const userId = url.searchParams.get('userId') || 'default_user';
        const redirectUri = `${url.origin}/auth/callback`;
        const googleAuthUrl = new URL('https://accounts.google.com/o/oauth2/v2/auth');
        googleAuthUrl.searchParams.set('client_id', env.GOOGLE_CLIENT_ID);
        googleAuthUrl.searchParams.set('redirect_uri', redirectUri);
        googleAuthUrl.searchParams.set('response_type', 'code');
        googleAuthUrl.searchParams.set('scope', 'https://www.googleapis.com/auth/gmail.readonly https://www.googleapis.com/auth/userinfo.email');
        googleAuthUrl.searchParams.set('access_type', 'offline');
        googleAuthUrl.searchParams.set('prompt', 'consent');
        googleAuthUrl.searchParams.set('state', userId);

        return Response.redirect(googleAuthUrl.toString(), 302);
      }

      // 3. OAuth Callback: Menerima code dari Google
      if (path === '/auth/callback') {
        const code = url.searchParams.get('code');
        const userId = url.searchParams.get('state');
        const error = url.searchParams.get('error');

        if (error || !code || !userId) {
          return new Response(`<h1>Gagal Menghubungkan Gmail</h1><p>${error || 'Kode otorisasi tidak ditemukan.'}</p>`, {
            headers: { 'Content-Type': 'text/html; charset=utf-8' },
            status: 400,
          });
        }

        const redirectUri = `${url.origin}/auth/callback`;
        const tokenRes = await fetch('https://oauth2.googleapis.com/token', {
          method: 'POST',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
          body: new URLSearchParams({
            code,
            client_id: env.GOOGLE_CLIENT_ID,
            client_secret: env.GOOGLE_CLIENT_SECRET,
            redirect_uri: redirectUri,
            grant_type: 'authorization_code',
          }),
        });

        if (!tokenRes.ok) {
          const errText = await tokenRes.text();
          return new Response(`<h1>Gagal Menukarkan Token Google</h1><p>${errText}</p>`, {
            headers: { 'Content-Type': 'text/html; charset=utf-8' },
            status: 500,
          });
        }

        const tokenData = (await tokenRes.json()) as any;
        const refreshToken = tokenData.refresh_token;

        // Ambil info email pengguna
        let userEmail = 'Unknown';
        if (tokenData.access_token) {
          const userRes = await fetch('https://www.googleapis.com/oauth2/v2/userinfo', {
            headers: { Authorization: `Bearer ${tokenData.access_token}` },
          });
          if (userRes.ok) {
            const userData = (await userRes.json()) as any;
            userEmail = userData.email || userEmail;
          }
        }

        // Simpan token ke Firestore
        const firestore = new FirestoreClient(env);
        await firestore.setDocument('gmail_integrations', userId, {
          user_id: userId,
          email: userEmail,
          refresh_token: refreshToken,
          is_active: true,
          connected_at: new Date().toISOString(),
          last_synced_at: null,
          last_status: 'Connected',
        });

        const successHtml = `
          <!DOCTYPE html>
          <html>
          <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>Koneksi Berhasil</title>
            <style>
              body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; display: flex; align-items: center; justify-content: center; min-height: 100vh; margin: 0; background-color: #f8fafc; }
              .card { background: white; padding: 32px; border-radius: 16px; box-shadow: 0 10px 25px rgba(0,0,0,0.05); text-align: center; max-width: 400px; width: 90%; }
              .icon { font-size: 48px; color: #10b981; margin-bottom: 16px; }
              h2 { margin: 0 0 8px; color: #1e293b; }
              p { color: #64748b; font-size: 14px; line-height: 1.5; margin: 0 0 24px; }
              .email { font-weight: 600; color: #0f172a; }
              .btn { display: inline-block; background: #2563eb; color: white; padding: 10px 20px; border-radius: 8px; text-decoration: none; font-weight: 500; font-size: 14px; }
            </style>
          </head>
          <body>
            <div class="card">
              <div class="icon">✓</div>
              <h2>Gmail Terhubung!</h2>
              <p>Email <span class="email">${userEmail}</span> berhasil dikoneksikan ke Expense Tracker.</p>
              <p>Silakan tutup halaman ini dan kembali ke aplikasi untuk memulai sinkronisasi transaksi.</p>
            </div>
          </body>
          </html>
        `;

        return new Response(successHtml, {
          headers: { 'Content-Type': 'text/html; charset=utf-8' },
        });
      }

      // 4. API Sync: Trigger sinkronisasi email dan update transaksi
      if (path === '/api/sync' && request.method === 'POST') {
        const body = (await request.json()) as { userId: string };
        const userId = body.userId;
        if (!userId) {
          return new Response(JSON.stringify({ error: 'userId is required' }), {
            status: 400,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          });
        }

        const firestore = new FirestoreClient(env);
        const integration = await firestore.getDocument('gmail_integrations', userId);

        if (!integration || !integration.refresh_token) {
          return new Response(
            JSON.stringify({
              error: 'Gmail belum terhubung. Silakan lakukan integrasi Gmail terlebih dahulu.',
              connected: false,
            }),
            { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
          );
        }

        const gmail = new GmailClient(env);
        const accessToken = await gmail.refreshAccessToken(integration.refresh_token);

        // Cari email notifikasi dari Mandiri / bank lainnya yang terjadi setelah saldo awal dibuat
        const wallets = await firestore.queryCollection('wallets', 'user_id', 'EQUAL', userId);
        let afterDateFilter = '';
        if (wallets.length > 0) {
          let earliestDate: Date | null = null;
          for (const w of wallets) {
            if (w.data.created_at) {
              const d = new Date(w.data.created_at);
              if (!earliestDate || d < earliestDate) earliestDate = d;
            }
          }
          if (earliestDate) {
            // Mundurkan 1 hari untuk toleransi timezone
            const tolerDate = new Date(earliestDate.getTime() - 24 * 60 * 60 * 1000);
            const y = tolerDate.getFullYear();
            const m = String(tolerDate.getMonth() + 1).padStart(2, '0');
            const d = String(tolerDate.getDate()).padStart(2, '0');
            afterDateFilter = ` after:${y}/${m}/${d}`;
          }
        }

        // Hardcode server-side: hanya email transaksi resmi Livin' by Mandiri
        const searchQuery = `from:noreply.livin@bankmandiri.co.id${afterDateFilter}`;
        const messageIds = await gmail.listBankMessages(accessToken, searchQuery);
        const parserRegistry = new ParserRegistry();

        let newCount = 0;
        const insertedTransactions: any[] = [];

        for (const msgId of messageIds) {
          const msg = await gmail.getMessage(accessToken, msgId);
          if (!msg) continue;

          let parsed = parserRegistry.parseEmail(msgId, msg.from, msg.subject, msg.body);
          if (!parsed && env.GEMINI_API_KEY) {
            // Layer 2: Fallback ke Gemini AI jika regex tidak mengenali layout email
            parsed = await parseWithGeminiFallback(msgId, msg.from, msg.subject, msg.body, env.GEMINI_API_KEY);
          }

          if (parsed) {
            const saved = await firestore.saveParsedTransaction(userId, parsed);
            if (saved) {
              newCount++;
              insertedTransactions.push(parsed);
            }
          }
        }

        const nowIso = new Date().toISOString();
        await firestore.setDocument('gmail_integrations', userId, {
          ...integration,
          last_synced_at: nowIso,
          last_status: 'success',
          last_synced_count: newCount,
        });

        // Catat log sinkronisasi
        const logId = `log_${Date.now()}`;
        await firestore.setDocument('sync_logs', logId, {
          id: logId,
          user_id: userId,
          synced_at: nowIso,
          status: 'success',
          processed_emails: messageIds.length,
          new_transactions: newCount,
        });

        return new Response(
          JSON.stringify({
            success: true,
            totalScanned: messageIds.length,
            newTransactionsCount: newCount,
            transactions: insertedTransactions,
            lastSyncedAt: nowIso,
          }),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      // 5. API Status: Cek status integrasi Gmail
      if (path === '/api/status' && request.method === 'GET') {
        const userId = url.searchParams.get('userId');
        if (!userId) {
          return new Response(JSON.stringify({ error: 'userId is required' }), {
            status: 400,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          });
        }

        const firestore = new FirestoreClient(env);
        const integration = await firestore.getDocument('gmail_integrations', userId);

        if (!integration) {
          return new Response(
            JSON.stringify({
              isConnected: false,
            }),
            { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
          );
        }

        return new Response(
          JSON.stringify({
            isConnected: !!integration.is_active,
            email: integration.email,
            lastSyncedAt: integration.last_synced_at,
            lastStatus: integration.last_status,
            lastCount: integration.last_synced_count || 0,
          }),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      // 6. API Reconcile: Rekonsiliasi saldo aktual vs saldo aplikasi
      if (path === '/api/reconcile' && request.method === 'POST') {
        const { userId, walletId, actualBalance, note } = (await request.json()) as any;
        if (!userId || !walletId || actualBalance === undefined) {
          return new Response(JSON.stringify({ error: 'userId, walletId, and actualBalance required' }), {
            status: 400,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          });
        }

        const firestore = new FirestoreClient(env);
        const wallet = await firestore.getDocument('wallets', walletId);
        if (!wallet) {
          return new Response(JSON.stringify({ error: 'Wallet not found' }), {
            status: 404,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          });
        }

        // Ownership Check: Pastikan wallet yang direkonsiliasi adalah milik userId pemanggil
        if (wallet.user_id !== userId) {
          return new Response(JSON.stringify({ error: 'Forbidden: Rekening bukan milik user ini' }), {
            status: 403,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          });
        }

        const appBalance = (wallet.balance as number) || 0;
        const diff = actualBalance - appBalance;

        // Jika ada selisih, buat transaksi adjustment
        if (Math.abs(diff) > 0.01) {
          const adjTxId = `adj_${Date.now()}`;
          const isIncome = diff > 0;
          await firestore.setDocument('transactions', adjTxId, {
            id: adjTxId,
            user_id: userId,
            wallet_id: walletId,
            amount: Math.abs(diff),
            type: isIncome ? 'income' : 'expense',
            category: 'Penyesuaian',
            description: note || `Penyesuaian Saldo Rekonsiliasi (Selisih: ${diff > 0 ? '+' : ''}${diff})`,
            transaction_date: new Date().toISOString(),
            created_at: new Date().toISOString(),
            is_reconciliation: true,
            source: 'MANUAL_RECONCILIATION',
          });
        }

        // Update saldo wallet
        await firestore.setDocument('wallets', walletId, {
          ...wallet,
          balance: actualBalance,
          last_reconciled_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        });

        return new Response(
          JSON.stringify({
            success: true,
            previousBalance: appBalance,
            actualBalance: actualBalance,
            difference: diff,
          }),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      // 6. API Scan Receipt via Gemini Flash AI (Gemini 3.8 Flash)
      if (path === '/api/scan-receipt' && request.method === 'POST') {
        if (!env.GEMINI_API_KEY) {
          return new Response(JSON.stringify({ error: 'GEMINI_API_KEY belum dikonfigurasi di server.' }), {
            status: 500,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          });
        }

        const body = (await request.json()) as { imageBase64: string; mimeType?: string };
        if (!body.imageBase64) {
          return new Response(JSON.stringify({ error: 'imageBase64 wajib disertakan.' }), {
            status: 400,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          });
        }

        const mimeType = body.mimeType || 'image/jpeg';
        const cleanBase64 = body.imageBase64.replace(/^data:image\/[a-z]+;base64,/, '');

        const promptText = `Kamu adalah asisten keuangan cerdas. Ekstrak informasi dari struk/kuitansi/nota belanja ini ke dalam format JSON murni tanpa markdown/backticks.
Field yang wajib diekstrak:
- merchant: Nama toko/restoran/penyedia jasa (contoh: 'Indomaret', 'Kopi Kenangan', 'SPBU Pertamina', dll)
- amount: Total nominal pembayaran akhir (angka positif bulat tanpa simbol Rp atau titik desimal, e.g. 52000)
- date: Tanggal transaksi dalam format ISO YYYY-MM-DD (jika tahun tidak tertera, gunakan tahun ${new Date().getFullYear()})
- category: Kategori paling cocok dari pilihan berikut: ['Makanan & Minuman', 'Belanja', 'Transportasi', 'Tagihan', 'Hiburan', 'Kesehatan', 'Pendidikan', 'Lainnya']
- items_summary: Ringkasan singkat 2-5 item yang dibeli (contoh: 'Kopi Susu, Roti Tawar')

Format output WAJIB JSON persis seperti ini:
{
  "merchant": "...",
  "amount": 0,
  "date": "YYYY-MM-DD",
  "category": "...",
  "items_summary": "..."
}`;

        const payload = {
          contents: [
            {
              role: 'user',
              parts: [
                {
                  inlineData: {
                    mimeType: mimeType,
                    data: cleanBase64,
                  },
                },
                {
                  text: promptText,
                },
              ],
            },
          ],
          generationConfig: {
            temperature: 0.1,
            responseMimeType: 'application/json',
          },
        };

        // Waterfall fallback: Dari model tertinggi (3.8 Flash) bertahap ke Flash-Lite (kuota 500/hari)
        const candidateModels = [
          'gemini-3.8-flash',
          'gemini-3.5-flash-lite',
          'gemini-3.1-flash-lite',
          'gemini-2.5-flash',
        ];

        let geminiData: any = null;
        let lastErrorText = '';

        for (const model of candidateModels) {
          try {
            const res = await fetch(
              `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${env.GEMINI_API_KEY}`,
              {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(payload),
              }
            );

            if (res.ok) {
              geminiData = await res.json();
              break;
            } else {
              lastErrorText = await res.text();
              console.warn(`Model ${model} gagal (${res.status}): ${lastErrorText}. Mencoba model cadangan...`);
            }
          } catch (e: any) {
            lastErrorText = e.message;
            console.warn(`Model ${model} error: ${e.message}. Mencoba model cadangan...`);
          }
        }

        if (!geminiData) {
          throw new Error(`Semua model Gemini gagal: ${lastErrorText}`);
        }

        const rawText = geminiData?.candidates?.[0]?.content?.parts?.[0]?.text;
        if (!rawText) {
          throw new Error('Gagal mengekstrak data dari gambar struk.');
        }

        let parsedJson;
        try {
          parsedJson = JSON.parse(rawText);
        } catch (_) {
          const cleaned = rawText.replace(/```json/g, '').replace(/```/g, '').trim();
          parsedJson = JSON.parse(cleaned);
        }

        return new Response(
          JSON.stringify({
            success: true,
            data: parsedJson,
          }),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      // 9. Simpan FCM Token & Preferensi Pengingat User
      if (path === '/api/notifications/save-fcm-token' && request.method === 'POST') {
        const body = (await request.json()) as any;
        const { userId, fcmToken, cashReminderEnabled, cashReminderHour, cashReminderMinute, timezoneOffset } = body;

        if (!userId || !fcmToken) {
          return new Response(
            JSON.stringify({ error: 'userId dan fcmToken wajib diisi.' }),
            { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
          );
        }

        const firestore = new FirestoreClient(env);
        const existing = (await firestore.getDocument('users', userId)) || {};

        await firestore.setDocument('users', userId, {
          ...existing,
          fcm_token: fcmToken,
          fcm_token_updated_at: new Date().toISOString(),
          cash_reminder_enabled: cashReminderEnabled !== undefined ? cashReminderEnabled : existing.cash_reminder_enabled ?? true,
          cash_reminder_hour: cashReminderHour !== undefined ? cashReminderHour : existing.cash_reminder_hour ?? 22,
          cash_reminder_minute: cashReminderMinute !== undefined ? cashReminderMinute : existing.cash_reminder_minute ?? 0,
          timezone_offset: timezoneOffset !== undefined ? timezoneOffset : existing.timezone_offset ?? 420,
        });

        return new Response(
          JSON.stringify({ success: true, message: 'FCM Token dan jadwal pengingat berhasil disimpan.' }),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      // 10. Tes Pengiriman FCM Langsung ke HP
      if (path === '/api/notifications/test-fcm' && request.method === 'POST') {
        const body = (await request.json()) as any;
        const { token, userId, title, body: msgBody } = body;

        let targetToken = token;
        const firestore = new FirestoreClient(env);

        if (!targetToken && userId) {
          const userDoc = await firestore.getDocument('users', userId);
          targetToken = userDoc?.fcm_token;
        }

        if (!targetToken) {
          return new Response(
            JSON.stringify({ error: 'Token FCM tidak ditemukan untuk user ini.' }),
            { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
          );
        }

        const fcm = new FcmClient(env, firestore);
        const res = await fcm.sendNotification({
          token: targetToken,
          title: title || '🔔 Tes FCM Expense Tracker Berhasil!',
          body: msgBody || 'Notifikasi cloud berhasil terkirim dan diterima langsung di HP Anda.',
          channelId: 'cash_reminder_channel',
          data: {
            type: 'TEST_NOTIFICATION',
            timestamp: new Date().toISOString(),
          },
        });

        return new Response(
          JSON.stringify(res),
          { status: res.success ? 200 : 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      // 11. Trigger Manual Pengecekan Pengingat Tunai
      if (path === '/api/notifications/trigger-reminders' && request.method === 'POST') {
        const firestore = new FirestoreClient(env);
        const fcm = new FcmClient(env, firestore);
        const res = await fcm.processCashReminders();

        return new Response(
          JSON.stringify({ success: true, ...res }),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      return new Response('Not Found', { status: 404 });
    } catch (err: any) {
      console.error('Worker request error:', err);
      return new Response(
        JSON.stringify({
          error: err.message || 'Internal Server Error',
        }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }
  },

  // Handler Otomatis Cron Triggers Cloudflare Workers (Jalan Berkala)
  async scheduled(event: any, env: Env, ctx: any): Promise<void> {
    const firestore = new FirestoreClient(env);
    const fcm = new FcmClient(env, firestore);
    const res = await fcm.processCashReminders();
    console.log(`[CRON] Processed cash reminders: sent ${res.sentCount}, errors: ${res.errors.length}`);
  },
};

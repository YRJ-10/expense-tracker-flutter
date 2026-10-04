import { Env } from './types';
import { FirestoreClient } from './firestore';
import { GmailClient } from './gmail';
import { ParserRegistry } from './parsers';

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
        const body = (await request.json()) as { userId: string; query?: string };
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

        // Cari email notifikasi dari Mandiri / bank lainnya
        const messageIds = await gmail.listBankMessages(accessToken, body.query || 'from:bankmandiri.co.id');
        const parserRegistry = new ParserRegistry();

        let newCount = 0;
        const insertedTransactions: any[] = [];

        for (const msgId of messageIds) {
          const msg = await gmail.getMessage(accessToken, msgId);
          if (!msg) continue;

          const parsed = parserRegistry.parseEmail(msgId, msg.from, msg.subject, msg.body);
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
};

import { Env } from './types';
import { FirestoreClient } from './firestore';
import { GmailClient } from './gmail';
import { ParserRegistry, parseWithGeminiFallback } from './parsers';
import { FcmClient } from './fcm';

// In-memory cache untuk JWKS Google & Token yang sudah diverifikasi
let cachedJwks: { keys: any[]; expiresAt: number } | null = null;
const verifiedTokenCache = new Map<string, { uid: string; expMs: number }>();

function base64UrlDecode(str: string): string {
  let base64 = str.replace(/-/g, '+').replace(/_/g, '/');
  while (base64.length % 4) {
    base64 += '=';
  }
  return atob(base64);
}

function base64UrlToUint8Array(str: string): Uint8Array {
  const binary = base64UrlDecode(str);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

async function getGoogleJwks(): Promise<any[]> {
  const now = Date.now();
  if (cachedJwks && cachedJwks.expiresAt > now) {
    return cachedJwks.keys;
  }
  try {
    const res = await fetch('https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com');
    if (res.ok) {
      const data = (await res.json()) as any;
      if (Array.isArray(data.keys)) {
        cachedJwks = { keys: data.keys, expiresAt: now + 3600 * 1000 };
        return data.keys;
      }
    }
  } catch (e) {
    console.error('Error fetching Google JWKS:', e);
  }
  return cachedJwks ? cachedJwks.keys : [];
}

async function verifyFirebaseIdToken(
  token: string,
  projectId: string
): Promise<{ valid: boolean; uid?: string; error?: string }> {
  try {
    const now = Date.now();
    const cached = verifiedTokenCache.get(token);
    if (cached && cached.expMs > now) {
      return { valid: true, uid: cached.uid };
    }

    const parts = token.split('.');
    if (parts.length !== 3) {
      return { valid: false, error: 'Format token bukan JWT' };
    }

    const [headerB64, payloadB64, sigB64] = parts;
    const header = JSON.parse(base64UrlDecode(headerB64));
    const payload = JSON.parse(base64UrlDecode(payloadB64));

    const expMs = (Number(payload.exp) || 0) * 1000;
    if (expMs <= now) {
      return { valid: false, error: 'Firebase ID Token kedaluwarsa' };
    }

    const expectedIss = `https://securetoken.google.com/${projectId}`;
    if (payload.iss !== expectedIss) {
      return { valid: false, error: 'Issuer token tidak valid' };
    }

    if (payload.aud !== projectId) {
      return { valid: false, error: 'Audience token tidak sesuai' };
    }

    if (!payload.sub || typeof payload.sub !== 'string') {
      return { valid: false, error: 'Subject (UID) tidak valid' };
    }

    // Verifikasi Signature via Google JWKS
    const jwks = await getGoogleJwks();
    const matchingKey = jwks.find((k: any) => k.kid === header.kid);
    if (!matchingKey) {
      return { valid: false, error: 'Public key Google tidak ditemukan' };
    }

    const cryptoKey = await crypto.subtle.importKey(
      'jwk',
      matchingKey,
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
      false,
      ['verify']
    );

    const dataToVerify = new TextEncoder().encode(`${headerB64}.${payloadB64}`);
    const signatureBytes = base64UrlToUint8Array(sigB64);

    const isSigValid = await crypto.subtle.verify(
      'RSASSA-PKCS1-v1_5',
      cryptoKey,
      signatureBytes,
      dataToVerify
    );

    if (!isSigValid) {
      return { valid: false, error: 'Signature kriptografi token tidak valid' };
    }

    const cacheDuration = Math.min(5 * 60 * 1000, Math.max(0, expMs - now));
    verifiedTokenCache.set(token, { uid: payload.sub, expMs: now + cacheDuration });

    return { valid: true, uid: payload.sub };
  } catch (err: any) {
    return { valid: false, error: `Validasi gagal: ${err.message}` };
  }
}

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
      // 0. Security Guard: Gembok semua endpoint /api/* dengan Firebase ID Token
      let authUserUid = '';
      if (path.startsWith('/api/')) {
        const authHeader = request.headers.get('Authorization') || '';
        const token = authHeader.replace(/^Bearer\s+/i, '').trim();

        if (!token) {
          return new Response(
            JSON.stringify({ error: 'Unauthorized: Header Authorization tidak ditemukan.' }),
            { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
          );
        }

        const auth = await verifyFirebaseIdToken(token, env.FIREBASE_PROJECT_ID);
        if (!auth.valid || !auth.uid) {
          return new Response(
            JSON.stringify({ error: `Unauthorized: ${auth.error || 'Akses ditolak.'}` }),
            { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
          );
        }
        authUserUid = auth.uid;
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
        const body = (await request.json()) as { userId?: string };
        const requestedUserId = body.userId;
        if (requestedUserId && requestedUserId !== authUserUid) {
          return new Response(JSON.stringify({ error: 'Forbidden: Tidak diizinkan mengakses data user lain.' }), {
            status: 403,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          });
        }
        const userId = authUserUid;

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

        // EARLY DEDUPLICATION: Kumpulkan semua message_id yang sudah pernah diproses
        const existingTx = await firestore.queryCollection('transactions', 'user_id', 'EQUAL', userId);
        const processedMsgIds = new Set<string>();

        // 1. Dari transaksi yang sudah tersimpan di Firestore
        for (const t of existingTx) {
          if (t.data.message_id) {
            processedMsgIds.add(t.data.message_id);
          }
        }

        // 2. Dari daftar processed_message_ids pada integration (jika ada)
        if (Array.isArray(integration.processed_message_ids)) {
          for (const id of integration.processed_message_ids) {
            processedMsgIds.add(id);
          }
        }

        // Saring hanya messageId yang benar-benar BARU
        const newMessageIds = messageIds.filter((id) => !processedMsgIds.has(id));

        // JIKA TIDAK ADA EMAIL BARU: SELESAI SEKETIKA (0 KUOTA AI, 0 DETIK)
        if (newMessageIds.length === 0) {
          const nowIso = new Date().toISOString();
          await firestore.setDocument('gmail_integrations', userId, {
            ...integration,
            last_synced_at: nowIso,
            last_status: 'success',
            last_synced_count: 0,
          });

          return new Response(
            JSON.stringify({
              success: true,
              totalScanned: messageIds.length,
              newTransactionsCount: 0,
              transactions: [],
              lastSyncedAt: nowIso,
            }),
            { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
          );
        }

        // JIKA ADA EMAIL BARU: HANYA PROSES EMAIL YANG BARU TERSEBUT
        let newCount = 0;
        const insertedTransactions: any[] = [];

        for (const msgId of newMessageIds) {
          const msg = await gmail.getMessage(accessToken, msgId);
          if (!msg) continue;

          let parsed: ParsedTransaction | null = null;

          // 1. Prioritas Utama (AI-First): Gemini dengan Waterfall Fallback (3.8 -> 3.5 -> 3.1 -> 2.5)
          if (env.GEMINI_API_KEY) {
            parsed = await parseWithGeminiFallback(msgId, msg.from, msg.subject, msg.body, env.GEMINI_API_KEY);
          }

          // 2. Jaring Pengaman (Fallback): Regex Parser jika AI tidak mengembalikan hasil
          if (!parsed) {
            parsed = parserRegistry.parseEmail(msgId, msg.from, msg.subject, msg.body);
          }

          if (parsed) {
            const saved = await firestore.saveParsedTransaction(userId, parsed);
            if (saved) {
              newCount++;
              insertedTransactions.push(parsed);
            }
          }

          processedMsgIds.add(msgId);
        }

        const nowIso = new Date().toISOString();
        await firestore.setDocument('gmail_integrations', userId, {
          ...integration,
          last_synced_at: nowIso,
          last_status: 'success',
          last_synced_count: newCount,
          processed_message_ids: Array.from(processedMsgIds).slice(-300),
        });

        // Catat log sinkronisasi
        const logId = `log_${Date.now()}`;
        await firestore.setDocument('sync_logs', logId, {
          id: logId,
          user_id: userId,
          synced_at: nowIso,
          status: 'success',
          processed_emails: newMessageIds.length,
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
        const queryUserId = url.searchParams.get('userId');
        if (queryUserId && queryUserId !== authUserUid) {
          return new Response(JSON.stringify({ error: 'Forbidden: Tidak diizinkan mengakses data user lain.' }), {
            status: 403,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          });
        }
        const userId = authUserUid;

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
        const { userId: bodyUserId, walletId, actualBalance, note } = (await request.json()) as any;
        if (bodyUserId && bodyUserId !== authUserUid) {
          return new Response(JSON.stringify({ error: 'Forbidden: Tidak diizinkan mengakses data user lain.' }), {
            status: 403,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          });
        }
        const userId = authUserUid;
        if (!walletId || actualBalance === undefined) {
          return new Response(JSON.stringify({ error: 'walletId and actualBalance required' }), {
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
        const { userId: bodyUserId, fcmToken, cashReminderEnabled, cashReminderHour, cashReminderMinute, timezoneOffset } = body;
        if (bodyUserId && bodyUserId !== authUserUid) {
          return new Response(JSON.stringify({ error: 'Forbidden: Tidak diizinkan mengakses data user lain.' }), {
            status: 403,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          });
        }
        const userId = authUserUid;

        if (!fcmToken) {
          return new Response(
            JSON.stringify({ error: 'fcmToken wajib diisi.' }),
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

import { ParsedTransaction } from '../types';

export async function parseWithGeminiFallback(
  messageId: string,
  from: string,
  subject: string,
  htmlOrText: string,
  apiKey: string
): Promise<ParsedTransaction | null> {
  // Bersihkan HTML tag berlebih namun pertahankan baris agar teks tabel tetap terbaca terstruktur
  const cleanedBody = htmlOrText
    .replace(/<style[^>]*>[\s\S]*?<\/style>/gi, '')
    .replace(/<script[^>]*>[\s\S]*?<\/script>/gi, '')
    .replace(/<br\s*[\/]?>/gi, '\n')
    .replace(/<\/p>/gi, '\n')
    .replace(/<\/tr>/gi, '\n')
    .replace(/<\/td>/gi, ' | ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/[^\S\r\n]+/g, ' ')
    .replace(/\n\s*\n+/g, '\n')
    .trim()
    .slice(0, 4500);

  const prompt = `Anda adalah parser email transaksi Bank Mandiri (Livin'). Ekstrak data transaksi dari email menjadi SATU objek JSON valid.

ATURAN EKSTRAKSI:

1. VALIDITAS (valid):
   Kembalikan {"valid": false} jika email adalah: transaksi gagal/dibatalkan/ditolak, promo/penawaran marketing, notifikasi OTP/keamanan, atau informasi non-transaksi finansial.

2. ARAH DANA (type):
   * "expense" = Uang keluar (Transfer keluar, QRIS, Top Up e-Wallet, Pembayaran tagihan, Pembelian, Tarik tunai, Debit).
   * "income"  = Uang masuk (Transfer masuk, Gaji, Cashback/Refund ke rekening).

3. NOMINAL TRANSAKSI (amount):
   Kembalikan SATU angka murni (number, tanpa titik/koma/Rp) yang merupakan total dana yang memotong/menambah rekening:
   
   * PRIORITAS 1 (Jika ada rincian yang memuat kata "TOTAL"):
     Wajib ambil angka pada baris Total tersebut.
     Persamaan kata: "Total Transaksi", "Total Debet", "Total Pembayaran", "Total Tagihan", "Total Biaya", "Jumlah Total", "Total".
   
   * PRIORITAS 2 (Jika TIDAK ADA baris Total sama sekali):
     Ambil angka pada baris nominal utama transaksi.
     Persamaan kata: "Nominal Top-up", "Nominal Transaksi", "Nominal Pembayaran", "Nominal Transfer", "Nominal", "Jumlah Transaksi", "Nilai Transaksi", "Jumlah Pembayaran".
   
   * PERHATIAN / LARANGAN:
     Jangan pernah mengambil angka "Sisa Saldo", "Saldo Akhir", "Saldo Rekening", atau "Saldo Setelah Transaksi".

4. TANGGAL (date):
   Waktu transaksi dalam format ISO 8601 timezone WIB (+07:00), contoh: "2026-11-04T14:30:00+07:00". Jika jam tidak ada, default jam 12:00:00+07:00.

5. DESKRIPSI (description):
   Deskripsi singkat manusiawi:
   * Top Up: "Top Up [Nama e-Wallet, misal ShopeePay / DANA / GoPay / OVO]"
   * QRIS: "QRIS [Nama Merchant]"
   * Transfer: "Transfer ke [Nama Penerima / Bank]"
   * Tagihan: "Pembayaran [Nama Biller, misal PLN / BPJS / Tagihan]"
   * Pemasukan: "Transfer Masuk dari [Nama Pengirim]"

6. KATEGORI (category):
   * Expense: "Top Up & E-Wallet", "Makanan", "Transportasi", "Belanja", "Tagihan", "Transfer", "Lainnya"
   * Income : "Transfer Masuk", "Gaji", "Investasi", "Lainnya"

7. REKENING (account_number):
   4 digit terakhir rekening sumber (misal "0182"). Jika tidak ada, isi "MANDIRI".

8. NO REFERENSI (reference_id):
   Nomor referensi / No. Resi transaksi jika tertera, atau null jika tidak ada.

Subjek Email: ${subject}
Isi Email:
${cleanedBody}

OUTPUT JSON:
Jika valid:
{
  "valid": true,
  "type": "expense" | "income",
  "amount": <number>,
  "date": "<ISO_8601>",
  "description": "<string>",
  "category": "<string>",
  "account_number": "<string>",
  "reference_id": "<string atau null>"
}

Jika tidak valid:
{
  "valid": false
}`;

  // Waterfall fallback: Dari model tertinggi bertahap ke Flash-Lite
  const candidateModels = [
    'gemini-3.5-flash-lite',
    'gemini-3.1-flash-lite',
    'gemini-2.5-flash-lite',
    'gemini-2.5-flash',
  ];

  let geminiData: any = null;

  for (const model of candidateModels) {
    try {
      const res = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            contents: [{ parts: [{ text: prompt }] }],
            generationConfig: {
              temperature: 0.1,
              responseMimeType: 'application/json',
            },
          }),
        }
      );

      if (res.ok) {
        geminiData = await res.json();
        break;
      } else {
        const errText = await res.text();
        console.warn(`[Gemini Email Parser] Model ${model} gagal (${res.status}): ${errText}. Mencoba model cadangan...`);
      }
    } catch (e: any) {
      console.warn(`[Gemini Email Parser] Model ${model} error: ${e.message}. Mencoba model cadangan...`);
    }
  }

  if (!geminiData) {
    console.error('[Gemini Email Parser] Semua model Gemini gagal merespons.');
    return null;
  }

  try {
    const rawText = geminiData.candidates?.[0]?.content?.parts?.[0]?.text;
    if (!rawText) return null;

    let data: any;
    try {
      data = JSON.parse(rawText);
    } catch (_) {
      const cleaned = rawText.replace(/```json/g, '').replace(/```/g, '').trim();
      data = JSON.parse(cleaned);
    }

    if (!data.valid || typeof data.amount !== 'number' || data.amount <= 0) {
      return null;
    }

    return {
      bank: 'MANDIRI',
      accountNumber: data.account_number || data.accountNumber || 'MANDIRI',
      type: data.type === 'income' ? 'income' : 'expense',
      amount: data.amount,
      date: data.date || new Date().toISOString(),
      description: data.description || 'Transaksi Mandiri',
      category: data.category || (data.type === 'income' ? 'Transfer Masuk' : 'Lainnya'),
      referenceId: data.reference_id || data.referenceId || `AI-${messageId}`,
      messageId,
    };
  } catch (e) {
    console.error('[Gemini Email Parser] Error parsing response JSON:', e);
    return null;
  }
}

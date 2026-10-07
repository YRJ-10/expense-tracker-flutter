import { ParsedTransaction } from '../types';

export async function parseWithGeminiFallback(
  messageId: string,
  from: string,
  subject: string,
  htmlOrText: string,
  apiKey: string
): Promise<ParsedTransaction | null> {
  // Bersihkan HTML tag berlebih namun pertahankan spasi agar teks tabel tetap terbaca
  const cleanedBody = htmlOrText
    .replace(/<style[^>]*>[\s\S]*?<\/style>/gi, '')
    .replace(/<script[^>]*>[\s\S]*?<\/script>/gi, '')
    .replace(/<br\s*[\/]?>/gi, '\n')
    .replace(/<\/p>/gi, '\n')
    .replace(/<\/tr>/gi, '\n')
    .replace(/<\/td>/gi, ' | ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 4500);

  const prompt = `Anda adalah parser transaksi keuangan khusus email Bank Mandiri (Livin'). Tugas Anda membaca isi email notifikasi transaksi dan mengubahnya menjadi SATU objek JSON yang valid.

PRINSIP UTAMA:
* Gunakan HANYA informasi yang terdapat dalam email.
* Jangan mengarang nominal, tanggal, nama, rekening, reference ID, atau detail transaksi.
* Jika suatu field tidak tersedia, gunakan null.
* Fokus pada PERUBAHAN SALDO REKENING sebagai dasar menentukan income atau expense.

LANGKAH ANALISIS:

1. TENTUKAN STATUS VALIDITAS
   Kembalikan {"valid": false} jika email merupakan:
   * Transaksi GAGAL / Ditolak / Dibatalkan / Kadaluarsa / Saldo Tidak Cukup.
   * Email promo, penawaran marketing, survei, atau pengumuman.
   * Notifikasi keamanan, OTP, reset password, atau aktivasi akun.
   * Informasi non-transaksi finansial.

2. TENTUKAN ARAH DANA (type)
   * "expense" = Uang keluar / berkurang dari rekening pengguna (Transfer ke orang lain, Pembayaran QRIS, Pembayaran Tagihan, Top Up e-Wallet, Beli Pulsa, Debit, Tarik Tunai).
   * "income"  = Uang masuk / bertambah ke rekening pengguna (Menerima transfer dari orang lain, Gaji, Cashback masuk saldo, Refund masuk rekening).

3. TENTUKAN AMOUNT & BIAYA ADMIN (amount & admin_fee)
   * "amount" harus merupakan TOTAL NILAI RIIL yang memotong/menambah saldo rekening.
   * Jika ada "Nominal Transaksi" DAN "Biaya Transaksi / Biaya Admin":
     - Jika email sudah mencantumkan "Total Transaksi / Total Debet", prioritaskan angka total tersebut (JANGAN dijumlahkan lagi agar tidak double counting).
     - Jika email HANYA mencantumkan Nominal dan Biaya secara terpisah tanpa baris Total, jumlahkan keduanya menjadi "amount".
   * Cantumkan nominal biaya tersebut pada field "admin_fee" (gunakan 0 jika tidak ada biaya).
   * Nilai saldo setelah transaksi BUKAN amount.

4. TENTUKAN TANGGAL (date)
   * Gunakan waktu transaksi pada struk email dan konversikan ke format ISO 8601 dengan timezone WIB (+07:00).
   * Contoh: "2026-10-07T11:20:00+07:00". Jika jam tidak ada, gunakan default jam 12:00:00+07:00.

5. TENTUKAN DESKRIPSI (description)
   * Buat deskripsi yang singkat, spesifik, dan manusiawi.
   * Transfer: "Transfer ke [Nama Penerima] ([Bank jika ada])"
   * QRIS: "QRIS di [Nama Merchant]"
   * Top Up: "Top Up [Nama E-Wallet / No]"
   * Tagihan: "Pembayaran [Nama Biller/PLN/BPJS/dll]"
   * Pemasukan: "Transfer Masuk dari [Nama Pengirim]"

6. TENTUKAN KATEGORI (category)
   Pilih salah satu kategori baku berikut yang paling relevan:
   * Untuk expense: "Makanan", "Transportasi", "Belanja", "Tagihan", "Top Up & E-Wallet", "Transfer", "Kartu Kredit", "Lainnya"
   * Untuk income : "Transfer Masuk", "Gaji", "Investasi", "Lainnya"

7. REKENING SUMBER (account_number)
   * Ambil 4 digit terakhir dari Rekening Sumber / Sumber Dana pengirim jika tersedia (misal "0182"). Jika tidak ada, gunakan "MANDIRI".

8. REFERENCE ID (reference_id)
   * Ambil nomor referensi transaksi / no resi / STAN resmi yang tertera.

Subjek Email: ${subject}
Isi Email:
${cleanedBody}

OUTPUT JSON:
Untuk transaksi valid:
{
  "valid": true,
  "type": "expense" | "income",
  "amount": <number>,
  "admin_fee": <number>,
  "date": "<ISO_8601>",
  "description": "<string>",
  "category": "<string>",
  "account_number": "<string>",
  "reference_id": "<string atau null>"
}

Untuk bukan transaksi valid:
{
  "valid": false
}`;

  // Waterfall fallback: Dari model tertinggi (3.8 Flash) bertahap ke Flash-Lite
  const candidateModels = [
    'gemini-3.8-flash',
    'gemini-3.5-flash-lite',
    'gemini-3.1-flash-lite',
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

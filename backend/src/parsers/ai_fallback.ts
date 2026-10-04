import { ParsedTransaction } from '../types';

export async function parseWithGeminiFallback(
  messageId: string,
  from: string,
  subject: string,
  htmlOrText: string,
  apiKey: string
): Promise<ParsedTransaction | null> {
  try {
    const prompt = `Anda adalah parser email transaksi Bank Mandiri (Livin').
Tugas Anda adalah membaca email transaksi perbankan dan mengekstrak data JSON.
Jika transaksi GAGAL, DIBATALKAN, atau BUKAN TRANSAKSI FINANSIAL, return {"valid": false}.

Format output JSON:
{
  "valid": true,
  "type": "expense" | "income",
  "amount": number (hanya angka, misal 50000),
  "date": "YYYY-MM-DDTHH:mm:ss+07:00",
  "description": string (misal: "Transfer ke BUDI", "Top Up GoPay", "QRIS di Indomaret"),
  "category": "Makanan" | "Belanja" | "Tagihan" | "Transfer" | "Top Up & E-Wallet" | "Kartu Kredit" | "Pemasukan" | "Lainnya",
  "accountNumber": string (misal: "0182" atau "MANDIRI"),
  "referenceId": string
}

Subjek: ${subject}
Isi Email:
${htmlOrText.replace(/<[^>]+>/g, ' ').slice(0, 3500)}`;

    const res = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=${apiKey}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: { responseMimeType: 'application/json' },
      }),
    });

    if (!res.ok) return null;
    const json: any = await res.json();
    const text = json.candidates?.[0]?.content?.parts?.[0]?.text;
    if (!text) return null;

    const data = JSON.parse(text);
    if (!data.valid || !data.amount || data.amount <= 0) {
      return null;
    }

    return {
      bank: 'MANDIRI',
      accountNumber: data.accountNumber || 'MANDIRI',
      type: data.type === 'income' ? 'income' : 'expense',
      amount: data.amount,
      date: data.date || new Date().toISOString(),
      description: data.description || 'Transaksi Mandiri',
      category: data.category || (data.type === 'income' ? 'Pemasukan' : 'Lainnya'),
      referenceId: data.referenceId || `AI-${messageId}`,
      messageId,
    };
  } catch (e) {
    console.error('Gemini fallback parsing error:', e);
    return null;
  }
}

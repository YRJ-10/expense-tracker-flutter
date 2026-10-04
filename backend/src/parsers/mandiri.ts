import { BankEmailParser, ParsedTransaction } from '../types';

export class MandiriLivinParser implements BankEmailParser {
  bankName = 'MANDIRI';

  canHandle(from: string, subject: string, body: string): boolean {
    const isFromMandiri = from.toLowerCase().includes('bankmandiri.co.id') || 
                          from.toLowerCase().includes('livin');
    const isMandiriSubject = subject.toLowerCase().includes('livin') || 
                            subject.toLowerCase().includes('pembayaran') || 
                            subject.toLowerCase().includes('transfer') ||
                            subject.toLowerCase().includes('mandiri');
    return isFromMandiri || (isMandiriSubject && body.toLowerCase().includes('bank mandiri'));
  }

  parse(messageId: string, from: string, subject: string, htmlOrText: string): ParsedTransaction | null {
    try {
      const isIncome = /transfer masuk|dana masuk|penerimaan transfer|kredit/i.test(subject) ||
                      /dana masuk|transfer masuk/i.test(htmlOrText);
      const type: 'expense' | 'income' = isIncome ? 'income' : 'expense';

      // 1. Ekstraksi Nominal Transaksi (e.g., Rp 30.500,00 atau Rp. 30.500)
      const amountRegex = /(?:Nominal Transaksi|Nominal|Jumlah|Total)[\s\S]*?Rp\s*([\d\.,]+)/i;
      const amountMatch = htmlOrText.match(amountRegex);
      if (!amountMatch) {
        return null; // Bukan email transaksi finansial bernominal
      }

      let amountStr = amountMatch[1].trim();
      // Format Indonesia: 30.500,00 -> buang titik ribuan, ganti koma desimal ke titik
      if (amountStr.includes(',') && amountStr.includes('.')) {
        amountStr = amountStr.replace(/\./g, '').replace(',', '.');
      } else if (amountStr.includes('.')) {
        // Misal 30.500 tanpa koma
        amountStr = amountStr.replace(/\./g, '');
      } else if (amountStr.includes(',')) {
        amountStr = amountStr.replace(',', '.');
      }
      const amount = parseFloat(amountStr);
      if (isNaN(amount) || amount <= 0) return null;

      // 2. Ekstraksi Nomor Referensi
      const refRegex = /No\.?\s*Referensi[\s\S]*?(?:<td[^>]*>|:)\s*([0-9a-zA-Z]+)/i;
      const refMatch = htmlOrText.match(refRegex);
      const referenceId = refMatch ? refMatch[1].trim() : `MDR-${messageId}`;

      // 3. Ekstraksi Penerima / Merchant / Keterangan
      let description = 'Transaksi Mandiri';
      const receiverRegex = /Penerima[\s\S]*?<h4[^>]*>\s*([^<]+)\s*<\/h4>/i;
      const receiverMatch = htmlOrText.match(receiverRegex);
      if (receiverMatch) {
        description = receiverMatch[1].trim();
      } else {
        const altReceiverRegex = /(?:Penerima|Tujuan|Merchant)[\s:]+([A-Za-z0-9\s\.\-_]{3,40})/i;
        const altMatch = htmlOrText.match(altReceiverRegex);
        if (altMatch) {
          description = altMatch[1].trim();
        }
      }

      // 4. Ekstraksi Nomor Rekening Sumber Dana (e.g., ****0182)
      let accountNumber = 'MANDIRI';
      const accRegex = /(?:Sumber Dana|No\.?\s*Rekening)[\s\S]*?\*{2,4}(\d{4})/i;
      const accMatch = htmlOrText.match(accRegex);
      if (accMatch) {
        accountNumber = accMatch[1]; // misal "0182"
      }

      // 5. Ekstraksi Tanggal & Jam
      // Tanggal: 26 Sep 2026, Jam: 11:43:34 WIB
      let transactionDate = new Date().toISOString();
      const dateRegex = /Tanggal[\s\S]*?(?:<td[^>]*>|:)\s*(\d{1,2}\s+[A-Za-z]{3,4}\s+\d{4})/i;
      const timeRegex = /Jam[\s\S]*?(?:<td[^>]*>|:)\s*(\d{2}:\d{2}(?::\d{2})?)/i;

      const dateMatch = htmlOrText.match(dateRegex);
      const timeMatch = htmlOrText.match(timeRegex);

      if (dateMatch) {
        const parsedIso = this.parseIndonesianDateTime(dateMatch[1], timeMatch ? timeMatch[1] : '00:00:00');
        if (parsedIso) {
          transactionDate = parsedIso;
        }
      }

      // Kategori Default
      let category = type === 'income' ? 'Pemasukan' : 'Lainnya';
      const lowerDesc = description.toLowerCase();
      if (/shopee|tokopedia|lazada|blibli|tiktok|grab|gojek|gofood|shopeepay/i.test(lowerDesc)) {
        category = 'Belanja';
      } else if (/makan|resto|cafe|kopi|bakso|food/i.test(lowerDesc)) {
        category = 'Makanan';
      } else if (/pln|listrik|pdam|indihome|pulsa|telkom/i.test(lowerDesc)) {
        category = 'Tagihan';
      }

      return {
        bank: this.bankName,
        accountNumber,
        type,
        amount,
        date: transactionDate,
        description,
        category,
        referenceId,
        messageId,
      };
    } catch (e) {
      console.error('Error parsing Mandiri email:', e);
      return null;
    }
  }

  private parseIndonesianDateTime(dateStr: string, timeStr: string): string | null {
    // dateStr: "26 Sep 2026", timeStr: "11:43:34"
    const months: Record<string, string> = {
      jan: '01', feb: '02', mar: '03', apr: '04', mei: '05', may: '05',
      jun: '06', jul: '07', agu: '08', ags: '08', aug: '08', sep: '09',
      okt: '10', oct: '10', nov: '11', des: '12', dec: '12'
    };

    const parts = dateStr.trim().split(/\s+/);
    if (parts.length >= 3) {
      const day = parts[0].padStart(2, '0');
      const monthKey = parts[1].toLowerCase().slice(0, 3);
      const month = months[monthKey] || '01';
      const year = parts[2];
      
      const cleanTime = timeStr.replace(/wib|wita|wit/gi, '').trim();
      const timeParts = cleanTime.split(':');
      const hour = (timeParts[0] || '00').padStart(2, '0');
      const min = (timeParts[1] || '00').padStart(2, '0');
      const sec = (timeParts[2] || '00').padStart(2, '0');

      // Waktu Indonesia Barat (WIB) adalah UTC+7
      return `${year}-${month}-${day}T${hour}:${min}:${sec}+07:00`;
    }
    return null;
  }
}

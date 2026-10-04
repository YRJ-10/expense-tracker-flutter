import { BankEmailParser, ParsedTransaction } from '../types';

export class MandiriLivinParser implements BankEmailParser {
  bankName = 'MANDIRI';

  canHandle(from: string, subject: string, body: string): boolean {
    const fromLower = from.toLowerCase();
    const subjLower = subject.toLowerCase();
    const bodyLower = body.toLowerCase();

    const isFromMandiri = fromLower.includes('bankmandiri.co.id') || fromLower.includes('livin');
    const isMandiriKeyword = subjLower.includes('livin') || 
                            subjLower.includes('pembayaran') || 
                            subjLower.includes('pembelian') || 
                            subjLower.includes('top up') || 
                            subjLower.includes('transfer') ||
                            subjLower.includes('mandiri');

    return isFromMandiri || (isMandiriKeyword && bodyLower.includes('bank mandiri'));
  }

  parse(messageId: string, from: string, subject: string, htmlOrText: string): ParsedTransaction | null {
    try {
      const subjectClean = subject.toLowerCase();

      // =========================================================================
      // 0. JANGKAR FILTER KEAMANAN: TOLAK TRANSAKSI GAGAL / BATAL / EXPIRED
      // =========================================================================
      const isFailed = /gagal|failed|dibatalkan|cancelled|ditolak|rejected|expired|kadaluarsa|tidak\s+berhasil/i.test(subjectClean) ||
                       /(?:status\s+transaksi|status)[\s\S]*?(?:gagal|failed|ditolak|dibatalkan|kadaluarsa)/i.test(htmlOrText);
      if (isFailed) {
        return null; // Abaikan! Jangan masukkan transaksi gagal ke pembukuan
      }

      // =========================================================================
      // 1. JANGKAR TIPE: PEMASUKAN vs PENGELUARAN
      // =========================================================================
      const isIncome = /transfer masuk|dana masuk|penerimaan transfer|kredit|cr\b|dana diterima|uang masuk/i.test(subjectClean) ||
                       /(?:transfer masuk|dana masuk|penerimaan transfer|dana diterima|uang masuk)/i.test(htmlOrText) ||
                       /(?:nama\s+pengirim|rekening\s+pengirim|dari\s+rekening)[\s\S]*?(?:<td[^>]*>|<h4[^>]*>|:)/i.test(htmlOrText);
      const type: 'expense' | 'income' = isIncome ? 'income' : 'expense';

      // =========================================================================
      // 2. JANGKAR NOMINAL: KAMUS SINONIM LENGKAP
      // =========================================================================
      const amountRegex = /(?:Nominal\s+Transaksi|Nominal\s+Pembayaran|Nominal\s+Transfer|Nominal\s+Top\s*Up|Nominal|Jumlah\s+Transaksi|Jumlah\s+Pembayaran|Jumlah\s+Transfer|Jumlah|Total\s+Transaksi|Total\s+Pembayaran|Total\s+Tagihan|Total|Nilai\s+Transaksi|Nilai\s+Pembayaran)[\s\S]*?(?:Rp\.?|IDR)?\s*([\d\.,]+)/i;
      let amountMatch = htmlOrText.match(amountRegex);
      
      // Fallback: Jika template berubah, cari pola nominal uang standar Indonesia
      if (!amountMatch) {
        amountMatch = htmlOrText.match(/(?:Rp\.?|IDR)\s*([\d]{1,3}(?:\.[\d]{3})+(?:,[\d]{2})?)/i);
      }
      if (!amountMatch) {
        return null; // Tidak ada nominal uang yang valid
      }

      let amountStr = amountMatch[1].trim();
      // Format Indonesia: 30.500,00 -> buang titik ribuan, ganti koma desimal ke titik
      if (amountStr.includes(',') && amountStr.includes('.')) {
        amountStr = amountStr.replace(/\./g, '').replace(',', '.');
      } else if (amountStr.includes('.')) {
        amountStr = amountStr.replace(/\./g, '');
      } else if (amountStr.includes(',')) {
        amountStr = amountStr.replace(',', '.');
      }
      const amount = parseFloat(amountStr);
      if (isNaN(amount) || amount <= 0) return null;

      // =========================================================================
      // 3. JANGKAR NOMOR REFERENSI
      // =========================================================================
      const refRegex = /(?:No\.?\s*Referensi|Nomor\s*Referensi|Ref\.?\s*No|ID\s*Transaksi)[\s\S]*?(?:<td[^>]*>|<h4[^>]*>|:)\s*([0-9a-zA-Z]+)/i;
      const refMatch = htmlOrText.match(refRegex);
      const referenceId = refMatch ? refMatch[1].trim() : `MDR-${messageId}`;

      // =========================================================================
      // 4. JANGKAR DESKRIPSI & PIHAK TERKAIT (PENERIMA / TUJUAN / MERCHANT / PENGIRIM)
      // =========================================================================
      let description = type === 'income' ? 'Transfer Masuk' : 'Transaksi Mandiri';

      if (type === 'income') {
        const senderRegex = /(?:Nama\s+Pengirim|Pengirim|Dari\s+Rekening|Dari)[\s\S]*?(?:<td[^>]*>|<h4[^>]*>|:)\s*([A-Za-z0-9\s\.\-_]{3,40})/i;
        const senderMatch = htmlOrText.match(senderRegex);
        if (senderMatch) {
          description = `Dari ${senderMatch[1].trim()}`;
        }
      } else {
        // Ekstraksi Pihak Tujuan / Penerima / Merchant
        const receiverRegex = /(?:Nama\s+Penerima|Penerima|Rekening\s+Tujuan|Tujuan\s+Transfer|Tujuan|Merchant|Nama\s+Merchant|Penyedia\s+Jasa|Nama\s+Produk|Institusi|Kepada)[\s\S]*?(?:<td[^>]*>|<h4[^>]*>|:)\s*([A-Za-z0-9\s\.\-_]{3,40})/i;
        const receiverMatch = htmlOrText.match(receiverRegex);

        // Ekstraksi Bank Tujuan jika ada (misal: BCA, BRI, BNI)
        const bankRegex = /(?:Bank\s+Tujuan|Nama\s+Bank)[\s\S]*?(?:<td[^>]*>|<h4[^>]*>|:)\s*([A-Za-z0-9\s]{2,20})/i;
        const bankMatch = htmlOrText.match(bankRegex);
        const targetBank = bankMatch ? bankMatch[1].trim() : '';

        const isTransfer = /transfer/i.test(subjectClean) || /transfer/i.test(htmlOrText);
        const isTopUp = /top\s*up|isi\s*ulang|e-money|emoney/i.test(subjectClean) || /top\s*up|e-money|emoney/i.test(htmlOrText);
        const isQRIS = /qris/i.test(subjectClean) || /qris/i.test(htmlOrText);

        if (receiverMatch) {
          const party = receiverMatch[1].trim();
          if (isTransfer) {
            description = targetBank ? `Transfer ke ${party} (${targetBank})` : `Transfer ke ${party}`;
          } else if (isTopUp) {
            description = `Top Up ${party}`;
          } else if (isQRIS) {
            description = `QRIS di ${party}`;
          } else {
            description = party;
          }
        } else {
          // Fallback cerdas berdasarkan jenis transaksi
          if (isTransfer) {
            description = targetBank ? `Transfer Keluar (${targetBank})` : 'Transfer Keluar';
          } else if (isTopUp) {
            description = /e-money|emoney/i.test(subjectClean) ? 'Top Up e-Money' : 'Top Up E-Wallet';
          } else if (isQRIS) {
            description = 'Pembayaran QRIS';
          }
        }
      }

      // =========================================================================
      // 5. JANGKAR NOMOR REKENING / SUMBER DANA
      // =========================================================================
      let accountNumber = 'MANDIRI';
      const accRegex = /(?:Sumber\s+Dana|No\.?\s*Rekening|Rekening\s+Sumber|Dari\s+Rekening)[\s\S]*?\*{2,4}(\d{4})/i;
      const accMatch = htmlOrText.match(accRegex);
      if (accMatch) {
        accountNumber = accMatch[1]; // misal "0182"
      }

      // =========================================================================
      // 6. JANGKAR TANGGAL & JAM
      // =========================================================================
      let transactionDate = new Date().toISOString();
      const dateRegex = /(?:Tanggal\s+Transaksi|Tanggal)[\s\S]*?(?:<td[^>]*>|<h4[^>]*>|:)\s*(\d{1,2}\s+[A-Za-z]{3,4}\s+\d{4})/i;
      const timeRegex = /(?:Waktu\s+Transaksi|Jam|Pukul)[\s\S]*?(?:<td[^>]*>|<h4[^>]*>|:)\s*(\d{2}:\d{2}(?::\d{2})?)/i;

      const dateMatch = htmlOrText.match(dateRegex);
      const timeMatch = htmlOrText.match(timeRegex);

      if (dateMatch) {
        const parsedIso = this.parseIndonesianDateTime(dateMatch[1], timeMatch ? timeMatch[1] : '00:00:00');
        if (parsedIso) {
          transactionDate = parsedIso;
        }
      }

      // =========================================================================
      // 7. PENENTUAN KATEGORI OTOMATIS
      // =========================================================================
      let category = type === 'income' ? 'Pemasukan' : 'Lainnya';
      const lowerDesc = description.toLowerCase();
      const lowerBody = htmlOrText.toLowerCase();

      if (type === 'income') {
        category = 'Pemasukan';
      } else if (/kartu kredit|credit card|pembayaran cc|mandiri cc|tagihan cc/i.test(lowerDesc) ||
                 /kartu kredit|credit card|tagihan kartu kredit/i.test(lowerBody)) {
        category = 'Kartu Kredit';
        if (description === 'Transaksi Mandiri' || description.toLowerCase().includes('pembayaran')) {
          description = 'Pembayaran Kartu Kredit';
        }
      } else if (/top up|e-money|emoney|gopay|ovo|dana|linkaja|shopeepay/i.test(lowerDesc) ||
                 /top up|e-money|emoney/i.test(lowerBody) ||
                 /top up/i.test(subjectClean)) {
        category = 'Top Up & E-Wallet';
      } else if (/transfer|bi-fast|online transfer/i.test(subjectClean) || /transfer ke/i.test(lowerDesc)) {
        category = 'Transfer';
      } else if (/shopee|tokopedia|lazada|blibli|tiktok|indomaret|alfamart/i.test(lowerDesc)) {
        category = 'Belanja';
      } else if (/makan|resto|cafe|kopi|bakso|food|grabfood|gofood|kfc|mcdonald/i.test(lowerDesc)) {
        category = 'Makanan';
      } else if (/pln|listrik|pdam|indihome|pulsa|telkom|bpjs|pajak/i.test(lowerDesc)) {
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

      return `${year}-${month}-${day}T${hour}:${min}:${sec}+07:00`;
    }
    return null;
  }
}

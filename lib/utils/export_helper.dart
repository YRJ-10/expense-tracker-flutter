import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
import 'package:open_filex/open_filex.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';

class ExportHelper {
  static Future<void> exportToCSV(List<Map<String, dynamic>> transactions) async {
    try {
      // Create CSV header
      List<List<dynamic>> csvData = [
        ['Tanggal', 'Kategori', 'Tipe', 'Jumlah', 'Catatan']
      ];

      // Add data rows
      for (var t in transactions) {
        final categoryName = t['categories']?['name'] ?? 'Lainnya';
        final typeStr = t['type'] == 'income' ? 'Pemasukan' : 'Pengeluaran';
        
        csvData.add([
          t['date'],
          categoryName,
          typeStr,
          t['amount'],
          t['note'] ?? ''
        ]);
      }

      String csv = const ListToCsvConverter(fieldDelimiter: ';', textDelimiter: '"').convert(csvData);

      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/laporan_keuangan_${DateTime.now().millisecondsSinceEpoch}.csv';
      final file = File(path);
      await file.writeAsString(csv);

      // Open the file
      await OpenFilex.open(path);
      
    } catch (e) {
      print('Error exporting CSV: $e');
    }
  }

  static Future<void> exportToPDF(List<Map<String, dynamic>> transactions) async {
    try {
      final pdf = pw.Document();
      
      // Calculate totals
      double totalIncome = 0;
      double totalExpense = 0;
      for (var t in transactions) {
        final amount = (t['amount'] as num).toDouble();
        if (t['type'] == 'income') {
          totalIncome += amount;
        } else {
          totalExpense += amount;
        }
      }
      
      final formatCurrency = NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0);

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (context) => [
            pw.Header(
              level: 0,
              child: pw.Text('Laporan Keuangan', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
            ),
            pw.SizedBox(height: 10),
            pw.Text('Tanggal Cetak: ${DateFormat('dd MMM yyyy HH:mm').format(DateTime.now())}'),
            pw.SizedBox(height: 20),
            
            // Summary BOX
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Total Pemasukan:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      pw.Text(formatCurrency.format(totalIncome), style: const pw.TextStyle(color: PdfColors.green)),
                    ]
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Total Pengeluaran:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      pw.Text(formatCurrency.format(totalExpense), style: const pw.TextStyle(color: PdfColors.red)),
                    ]
                  ),
                ]
              )
            ),
            pw.SizedBox(height: 20),
            
            // Table
            pw.TableHelper.fromTextArray(
              context: context,
              headers: ['Tanggal', 'Kategori', 'Tipe', 'Jumlah', 'Catatan'],
              data: transactions.map((t) {
                final cName = t['categories']?['name'] ?? 'Lainnya';
                final type = t['type'] == 'income' ? 'Masuk' : 'Keluar';
                return [
                  t['date'],
                  cName,
                  type,
                  formatCurrency.format(t['amount']),
                  t['note'] ?? '-'
                ];
              }).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
              rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300))),
            ),
          ],
        )
      );

      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/laporan_pdf_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File(path);
      await file.writeAsBytes(await pdf.save());

      await OpenFilex.open(path);
    } catch (e) {
      print('Error exporting PDF: $e');
    }
  }
}

import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
import 'package:open_filex/open_filex.dart';

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

      String csv = const ListToCsvConverter().convert(csvData);

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
}

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:expense_tracker_flutter/data/services/gmail_sync_service.dart';

class ScannedReceiptResult {
  final String merchant;
  final double amount;
  final String date;
  final String category;
  final String itemsSummary;

  ScannedReceiptResult({
    required this.merchant,
    required this.amount,
    required this.date,
    required this.category,
    required this.itemsSummary,
  });

  factory ScannedReceiptResult.fromJson(Map<String, dynamic> json) {
    final rawAmount = json['amount'];
    double parsedAmount = 0.0;
    if (rawAmount is num) {
      parsedAmount = rawAmount.toDouble();
    } else if (rawAmount is String) {
      final cleaned = rawAmount.replaceAll(RegExp(r'[^0-9.]'), '');
      parsedAmount = double.tryParse(cleaned) ?? 0.0;
    }

    return ScannedReceiptResult(
      merchant: json['merchant']?.toString() ?? 'Toko/Merchant',
      amount: parsedAmount,
      date: json['date']?.toString() ?? DateTime.now().toIso8601String().split('T')[0],
      category: json['category']?.toString() ?? 'Lainnya',
      itemsSummary: json['items_summary']?.toString() ?? '',
    );
  }
}

class ReceiptScannerService {
  static final ImagePicker _picker = ImagePicker();

  /// Ambil foto struk dari Kamera
  static Future<ScannedReceiptResult?> scanFromCamera() async {
    final photo = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
    if (photo == null) return null;
    return await _uploadAndAnalyze(photo);
  }

  /// Ambil gambar struk dari Galeri
  static Future<ScannedReceiptResult?> scanFromGallery() async {
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
    if (image == null) return null;
    return await _uploadAndAnalyze(image);
  }

  /// Kirim foto ke endpoint Cloudflare Worker Gemini AI
  static Future<ScannedReceiptResult?> _uploadAndAnalyze(XFile file) async {
    try {
      final bytes = await file.readAsBytes();
      final base64Image = base64Encode(bytes);

      // Tentukan mime type
      String mimeType = 'image/jpeg';
      if (file.name.toLowerCase().endsWith('.png')) {
        mimeType = 'image/png';
      } else if (file.name.toLowerCase().endsWith('.webp')) {
        mimeType = 'image/webp';
      }

      final res = await http.post(
        Uri.parse('${GmailSyncService.baseUrl}/api/scan-receipt'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${GmailSyncService.apiToken}',
        },
        body: jsonEncode({
          'imageBase64': base64Image,
          'mimeType': mimeType,
        }),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['data'] != null) {
          return ScannedReceiptResult.fromJson(data['data']);
        }
        throw Exception('Format data struk dari AI tidak sesuai.');
      } else {
        String errorMsg = 'Gagal memproses struk.';
        try {
          final err = jsonDecode(res.body);
          if (err is Map && err['error'] != null) {
            errorMsg = err['error'].toString();
          }
        } catch (_) {
          errorMsg = 'Layanan server sedang mengalami kendala (Status ${res.statusCode}).';
        }
        throw Exception(errorMsg);
      }
    } catch (e) {
      rethrow;
    }
    return null;
  }
}

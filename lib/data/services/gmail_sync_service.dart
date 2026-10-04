import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class GmailSyncResult {
  final bool success;
  final int totalScanned;
  final int newTransactionsCount;
  final String? lastSyncedAt;
  final String? error;

  GmailSyncResult({
    required this.success,
    this.totalScanned = 0,
    this.newTransactionsCount = 0,
    this.lastSyncedAt,
    this.error,
  });
}

class GmailSyncStatus {
  final bool isConnected;
  final String? email;
  final String? lastSyncedAt;
  final String? lastStatus;
  final int lastCount;

  GmailSyncStatus({
    required this.isConnected,
    this.email,
    this.lastSyncedAt,
    this.lastStatus,
    this.lastCount = 0,
  });
}

class GmailSyncService {
  static const String baseUrl = 'https://YOUR-WORKER-SUBDOMAIN.workers.dev';
  static const String apiToken = 'YOUR_WORKER_AUTH_TOKEN';

  // 1. Buka halaman otorisasi OAuth Gmail
  static Future<bool> connectGmail(String userId) async {
    final uri = Uri.parse('$baseUrl/auth/login?userId=$userId');
    try {
      final success = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (success) return true;
    } catch (_) {}

    try {
      final success = await launchUrl(uri, mode: LaunchMode.platformDefault);
      if (success) return true;
    } catch (_) {}

    try {
      return await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    } catch (_) {
      return false;
    }
  }

  // 2. Ambil status integrasi saat ini
  static Future<GmailSyncStatus> getStatus(String userId) async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/api/status?userId=$userId'),
        headers: {
          'Authorization': 'Bearer $apiToken',
        },
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return GmailSyncStatus(
          isConnected: data['isConnected'] == true,
          email: data['email'],
          lastSyncedAt: data['lastSyncedAt'],
          lastStatus: data['lastStatus'],
          lastCount: data['lastCount'] ?? 0,
        );
      }
    } catch (e) {
      // ignore / return not connected
    }
    return GmailSyncStatus(isConnected: false);
  }

  // 3. Trigger proses sinkronisasi email transaksi bank
  static Future<GmailSyncResult> triggerSync(String userId, {String? query}) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/sync'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiToken',
        },
        body: jsonEncode({
          'userId': userId,
        }),
      );

      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['success'] == true) {
        return GmailSyncResult(
          success: true,
          totalScanned: data['totalScanned'] ?? 0,
          newTransactionsCount: data['newTransactionsCount'] ?? 0,
          lastSyncedAt: data['lastSyncedAt'],
        );
      } else {
        return GmailSyncResult(
          success: false,
          error: data['error'] ?? 'Gagal melakukan sinkronisasi.',
        );
      }
    } catch (e) {
      return GmailSyncResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  // 4. Rekonsiliasi saldo aktual dengan saldo aplikasi
  static Future<bool> reconcileBalance({
    required String userId,
    required String walletId,
    required double actualBalance,
    String? note,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/reconcile'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiToken',
        },
        body: jsonEncode({
          'userId': userId,
          'walletId': walletId,
          'actualBalance': actualBalance,
          'note': note,
        }),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['success'] == true;
      }
    } catch (e) {
      // handle error
    }
    return false;
  }
}

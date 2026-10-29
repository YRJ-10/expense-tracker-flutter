import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:expense_tracker_flutter/config/app_config.dart';

class GmailSyncResult {
  final bool success;
  final int totalScanned;
  final int newTransactionsCount;
  final String? lastSyncedAt;
  final String? error;
  final bool isExpired;

  GmailSyncResult({
    required this.success,
    this.totalScanned = 0,
    this.newTransactionsCount = 0,
    this.lastSyncedAt,
    this.error,
    this.isExpired = false,
  });
}

class GmailSyncStatus {
  final bool isConnected;
  final bool isExpired;
  final String? email;
  final String? lastSyncedAt;
  final String? lastStatus;
  final int lastCount;

  GmailSyncStatus({
    required this.isConnected,
    this.isExpired = false,
    this.email,
    this.lastSyncedAt,
    this.lastStatus,
    this.lastCount = 0,
  });
}

class GmailSyncService {
  static const String baseUrl = AppConfig.backendUrl;
  static Future<String> get apiToken async => await AppConfig.getAuthToken();

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
      final token = await apiToken;
      final res = await http.get(
        Uri.parse('$baseUrl/api/status?userId=$userId'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final isExp = data['isExpired'] == true ||
            data['lastStatus'] == 'auth_expired' ||
            data['lastStatus'] == 'expired';
        return GmailSyncStatus(
          isConnected: !isExp && data['isConnected'] == true,
          isExpired: isExp,
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
      final token = await apiToken;
      final res = await http.post(
        Uri.parse('$baseUrl/api/sync'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'userId': userId,
        }),
      );

      final data = jsonDecode(res.body);
      final isExp = res.statusCode == 401 ||
          data['auth_expired'] == true ||
          (data['error']
                  ?.toString()
                  .toLowerCase()
                  .contains('invalid_grant') ??
              false) ||
          (data['error']
                  ?.toString()
                  .toLowerCase()
                  .contains('kedaluwarsa') ??
              false) ||
          (data['error']
                  ?.toString()
                  .toLowerCase()
                  .contains('expired') ??
              false);

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
          isExpired: isExp,
          error: data['error'] ?? 'Gagal melakukan sinkronisasi.',
        );
      }
    } catch (e) {
      final errStr = e.toString().toLowerCase();
      final isExp = errStr.contains('invalid_grant') ||
          errStr.contains('kedaluwarsa') ||
          errStr.contains('expired');
      return GmailSyncResult(
        success: false,
        isExpired: isExp,
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
      final token = await apiToken;
      final res = await http.post(
        Uri.parse('$baseUrl/api/reconcile'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
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

  // 5. Putuskan integrasi akun Gmail
  static Future<bool> disconnectGmail(String userId) async {
    try {
      final token = await apiToken;
      final res = await http.post(
        Uri.parse('$baseUrl/api/disconnect'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'userId': userId,
        }),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['success'] == true;
      }
    } catch (_) {}
    return false;
  }
}

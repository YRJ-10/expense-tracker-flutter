import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:expense_tracker_flutter/config/app_config.dart';
import 'package:expense_tracker_flutter/data/services/firestore_service.dart';
import 'package:expense_tracker_flutter/data/services/notification_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('[FCM Background] Message received: ${message.messageId}');
}

class FcmService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotif =
      FlutterLocalNotificationsPlugin();

  static String? _fcmToken;
  static String? get currentToken => _fcmToken;

  /// Inisialisasi Firebase Cloud Messaging
  static Future<void> initialize() async {
    try {
      // 1. Minta Izin Notifikasi (Android 13+ & iOS)
      final settings = await _messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      debugPrint('[FCM] Permission status: ${settings.authorizationStatus}');

      // 2. Ambil FCM Token
      _fcmToken = await _messaging.getToken();
      debugPrint('[FCM] Device Token: $_fcmToken');

      if (_fcmToken != null) {
        await syncTokenAndPreferences();
      }

      // 3. Listener jika Token berubah/refresh
      _messaging.onTokenRefresh.listen((newToken) {
        _fcmToken = newToken;
        debugPrint('[FCM] Token refreshed: $newToken');
        syncTokenAndPreferences();
      });

      // 4. Foreground Message Handler (Saat aplikasi sedang dibuka)
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('[FCM Foreground] Got message: ${message.notification?.title}');
        final notif = message.notification;
        if (notif != null) {
          final type = message.data['type'];
          String channelId = 'cash_reminder_channel';
          String channelName = 'Pengingat Transaksi Tunai';

          if (type == 'DUE_DATE_REMINDER') {
            channelId = 'due_date_channel';
            channelName = 'Pengingat Jatuh Tempo';
          } else if (type == 'RECURRING_REMINDER') {
            channelId = 'recurring_channel';
            channelName = 'Pengingat Transaksi Rutin';
          }

          _showForegroundNotification(
            title: notif.title ?? 'Pengingat Transaksi 💵',
            body: notif.body ?? '',
            channelId: channelId,
            channelName: channelName,
          );
        }
      });
    } catch (e) {
      debugPrint('[FCM] Initialization error: $e');
    }
  }

  /// Tampilkan banner notifikasi jika pesan FCM tiba saat aplikasi sedang dibuka
  static Future<void> _showForegroundNotification({
    required String title,
    required String body,
    String channelId = 'cash_reminder_channel',
    String channelName = 'Pengingat Transaksi Tunai',
  }) async {
    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: 'Pengingat via Firebase Cloud Messaging',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );

    await _localNotif.show(
      DateTime.now().millisecond,
      title,
      body,
      NotificationDetails(android: androidDetails),
    );
  }

  /// Sinkronkan Token FCM dan semua preferensi notifikasi ke Firestore & Backend Worker
  static Future<void> syncTokenAndPreferences({
    bool? enabled,
    int? hour,
    int? minute,
    bool? dueDateAlertEnabled,
    int? dueDateOffsetHours,
    int? budgetThreshold,
    bool? recurringAlertEnabled,
    int? recurringOffsetHours,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _fcmToken == null) return;

    final isReminderEnabled =
        enabled ?? await NotificationService.isCashReminderEnabled();
    final reminderTime = await NotificationService.getCashReminderTime();
    final remHour = hour ?? reminderTime.hour;
    final remMin = minute ?? reminderTime.minute;
    final isDueEnabled =
        dueDateAlertEnabled ?? await NotificationService.isDueDateAlertEnabled();
    final dueHours =
        dueDateOffsetHours ?? await NotificationService.getDueDateOffsetHours();
    final budgetLimit =
        budgetThreshold ?? await NotificationService.getBudgetAlertThreshold();
    final isRecEnabled =
        recurringAlertEnabled ?? await NotificationService.isRecurringAlertEnabled();
    final recHours =
        recurringOffsetHours ?? await NotificationService.getRecurringOffsetHours();
    final timezoneOffset = DateTime.now().timeZoneOffset.inMinutes;

    final payload = {
      'fcm_token': _fcmToken,
      'fcm_token_updated_at': DateTime.now().toIso8601String(),
      'cash_reminder_enabled': isReminderEnabled,
      'cash_reminder_hour': remHour,
      'cash_reminder_minute': remMin,
      'timezone_offset': timezoneOffset,
      'due_date_alert_enabled': isDueEnabled,
      'due_date_offset_hours': dueHours,
      'budget_alert_threshold': budgetLimit,
      'recurring_alert_enabled': isRecEnabled,
      'recurring_offset_hours': recHours,
    };

    // 1. Simpan ke Firestore
    try {
      await FirestoreService.saveProfile(user.uid, payload);
    } catch (e) {
      debugPrint('[FCM] Error saving to Firestore: $e');
    }

    // 2. Daftarkan juga ke Backend Worker Endpoint
    try {
      final token = await AppConfig.getAuthToken();
      final url = Uri.parse('${AppConfig.backendUrl}/api/notifications/save-fcm-token');
      await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'userId': user.uid,
          'fcmToken': _fcmToken,
          'cashReminderEnabled': isReminderEnabled,
          'cashReminderHour': remHour,
          'cashReminderMinute': remMin,
          'timezoneOffset': timezoneOffset,
          'dueDateAlertEnabled': isDueEnabled,
          'dueDateOffsetHours': dueHours,
          'budgetAlertThreshold': budgetLimit,
          'recurringAlertEnabled': isRecEnabled,
          'recurringOffsetHours': recHours,
        }),
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('[FCM] Error syncing token to Worker backend: $e');
    }
  }

  /// Uji kirim notifikasi push FCM langsung ke HP ini melalui Backend Cloudflare Worker
  static Future<Map<String, dynamic>> testPushNotification() async {
    final user = FirebaseAuth.instance.currentUser;
    if (_fcmToken == null && user == null) {
      return {'success': false, 'error': 'FCM Token belum tersedia.'};
    }

    try {
      final token = await AppConfig.getAuthToken();
      final url = Uri.parse('${AppConfig.backendUrl}/api/notifications/test-fcm');
      final res = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'token': _fcmToken,
          'userId': user?.uid,
          'title': '🔔 Tes FCM Push Berhasil!',
          'body': 'Notifikasi push cloud dari Cloudflare Worker berhasil tembus ke HP Anda!',
        }),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return data;
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }
}

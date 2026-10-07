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
          _showForegroundNotification(
            title: notif.title ?? 'Pengingat Tunai 💵',
            body: notif.body ?? 'Ada transaksi tunai hari ini yang belum dicatat?',
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
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'cash_reminder_channel',
      'Pengingat Transaksi Tunai',
      channelDescription: 'Pengingat pencatatan transaksi via Firebase Cloud Messaging',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );

    await _localNotif.show(
      DateTime.now().millisecond,
      title,
      body,
      const NotificationDetails(android: androidDetails),
    );
  }

  /// Sinkronkan Token FCM dan preferensi jam pengingat ke Firestore & Backend Worker
  static Future<void> syncTokenAndPreferences({
    bool? enabled,
    int? hour,
    int? minute,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _fcmToken == null) return;

    final isReminderEnabled = enabled ?? await NotificationService.isCashReminderEnabled();
    final reminderTime = await NotificationService.getCashReminderTime();
    final remHour = hour ?? reminderTime.hour;
    final remMin = minute ?? reminderTime.minute;
    final timezoneOffset = DateTime.now().timeZoneOffset.inMinutes;

    // 1. Simpan ke Firestore
    try {
      await FirestoreService.saveProfile(user.uid, {
        'fcm_token': _fcmToken,
        'fcm_token_updated_at': DateTime.now().toIso8601String(),
        'cash_reminder_enabled': isReminderEnabled,
        'cash_reminder_hour': remHour,
        'cash_reminder_minute': remMin,
        'timezone_offset': timezoneOffset,
      });
    } catch (e) {
      debugPrint('[FCM] Error saving to Firestore: $e');
    }

    // 2. Daftarkan juga ke Backend Worker Endpoint
    try {
      final url = Uri.parse('${AppConfig.backendUrl}/api/notifications/save-fcm-token');
      await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${AppConfig.workerAuthToken}',
        },
        body: jsonEncode({
          'userId': user.uid,
          'fcmToken': _fcmToken,
          'cashReminderEnabled': isReminderEnabled,
          'cashReminderHour': remHour,
          'cashReminderMinute': remMin,
          'timezoneOffset': timezoneOffset,
        }),
      );
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
      final url = Uri.parse('${AppConfig.backendUrl}/api/notifications/test-fcm');
      final res = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${AppConfig.workerAuthToken}',
        },
        body: jsonEncode({
          'userId': user?.uid,
          'token': _fcmToken,
          'title': '🔔 Tes FCM Push Berhasil!',
          'body': 'Notifikasi push cloud dari Cloudflare Worker berhasil tembus ke HP Anda!',
        }),
      );

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return data;
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }
}

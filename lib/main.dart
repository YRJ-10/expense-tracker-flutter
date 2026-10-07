import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'firebase_options.dart';
import 'package:expense_tracker_flutter/data/services/notification_service.dart';
import 'package:expense_tracker_flutter/data/services/fcm_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  await initializeDateFormatting('id_ID');

  // Langsung tampilkan UI agar tidak tertahan dan frame pertama langsung muncul
  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );

  // Inisialisasi notifikasi berjalan di background tanpa menghalangi tampilan awal
  NotificationService.initialize().catchError((e) {
    debugPrint('Notification init error: $e');
  });
  FcmService.initialize().catchError((e) {
    debugPrint('FCM init error: $e');
  });
}

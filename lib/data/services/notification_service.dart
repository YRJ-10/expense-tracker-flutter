import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const String _keyCashReminder = 'notif_cash_reminder_enabled';
  static const String _keyCashReminderHour = 'notif_cash_reminder_hour';
  static const String _keyCashReminderMinute = 'notif_cash_reminder_minute';

  static const String _keyBudgetAlert = 'notif_budget_alert_enabled';
  static const String _keyBudgetAlertThreshold = 'notif_budget_alert_threshold';

  static const String _keyDueDateAlert = 'notif_due_date_alert_enabled';
  static const String _keyDueDateOffsetHours = 'notif_due_date_offset_hours';

  static bool _isInitialized = false;

  /// Inisialisasi plugin notifikasi & timezone
  static Future<void> initialize() async {
    if (_isInitialized) return;

    tz.initializeTimeZones();
    try {
      final timezoneInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timezoneInfo.identifier));
    } catch (e) {
      debugPrint('Notification timezone init failed: $e');
    }

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _notificationsPlugin.initialize(initSettings);

    // Minta izin notifikasi dan izin exact alarm di Android
    final androidPlatform =
        _notificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlatform?.requestNotificationsPermission();
    await androidPlatform?.requestExactAlarmsPermission();

    _isInitialized = true;

    // Batalkan alarm lokal ID 1001 agar pengingat sepenuhnya ditangani FCM Cloud
    await cancelNotification(1001);
  }

  // --- PREFERENSI NOTIFIKASI PENGINGAT TUNAI ---
  static Future<bool> isCashReminderEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyCashReminder) ?? true;
  }

  static Future<void> setCashReminderEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyCashReminder, enabled);
    await cancelNotification(1001);
  }

  static Future<TimeOfDay> getCashReminderTime() async {
    final prefs = await SharedPreferences.getInstance();
    final hour = prefs.getInt(_keyCashReminderHour) ?? 20;
    final minute = prefs.getInt(_keyCashReminderMinute) ?? 30;
    return TimeOfDay(hour: hour, minute: minute);
  }

  static Future<void> setCashReminderTime(TimeOfDay time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyCashReminderHour, time.hour);
    await prefs.setInt(_keyCashReminderMinute, time.minute);
    await cancelNotification(1001);
  }

  // --- PREFERENSI NOTIFIKASI ANGGARAN ---
  static Future<bool> isBudgetAlertEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyBudgetAlert) ?? true;
  }

  static Future<void> setBudgetAlertEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBudgetAlert, enabled);
  }

  static Future<int> getBudgetAlertThreshold() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyBudgetAlertThreshold) ?? 80;
  }

  static Future<void> setBudgetAlertThreshold(int threshold) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyBudgetAlertThreshold, threshold);
  }

  // --- PREFERENSI NOTIFIKASI JATUH TEMPO ---
  static Future<bool> isDueDateAlertEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyDueDateAlert) ?? true;
  }

  static Future<void> setDueDateAlertEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDueDateAlert, enabled);
  }

  /// Offset waktu pengingat jatuh tempo dalam satuan jam (default: 24 jam / H-1)
  static Future<int> getDueDateOffsetHours() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyDueDateOffsetHours) ?? 24;
  }

  static Future<void> setDueDateOffsetHours(int hours) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyDueDateOffsetHours, hours);
  }

  static String getDueDateOffsetLabel(int hours) {
    switch (hours) {
      case 72:
        return 'H-3 Hari (72 Jam)';
      case 48:
        return 'H-2 Hari (48 Jam)';
      case 24:
        return 'H-1 Hari (24 Jam)';
      case 12:
        return 'H-12 Jam';
      case 6:
        return 'H-6 Jam';
      case 3:
        return 'H-3 Jam';
      case 0:
        return 'Hari H (0 Jam)';
      default:
        return '$hours Jam Sebelum';
    }
  }

  /// Menghitung tanggal jatuh tempo terdekat (baik utang tunggal maupun utang berulang bulanan)
  static DateTime? calculateNextDueDate({
    required bool isRecurring,
    int? recurringDay,
    String? dueDateStr,
    bool isPaid = false,
  }) {
    final now = DateTime.now();

    if (isRecurring && recurringDay != null) {
      // Tagihan rutin bulanan (misal kartu kredit / cicilan)
      final lastDayThisMonth = DateTime(now.year, now.month + 1, 0).day;
      final targetDayThisMonth = recurringDay.clamp(1, lastDayThisMonth);
      final dueThisMonth =
          DateTime(now.year, now.month, targetDayThisMonth, 23, 59, 59);

      // Jika jatuh tempo bulan ini belum lewat dan belum lunas
      if (dueThisMonth.isAfter(now) && !isPaid) {
        return dueThisMonth;
      }

      // Jika sudah lewat atau sudah lunas bulan ini, targetkan bulan depan (rollover)
      final nextMonth = now.month == 12 ? 1 : now.month + 1;
      final nextYear = now.month == 12 ? now.year + 1 : now.year;
      final lastDayNextMonth = DateTime(nextYear, nextMonth + 1, 0).day;
      final targetDayNextMonth = recurringDay.clamp(1, lastDayNextMonth);
      return DateTime(nextYear, nextMonth, targetDayNextMonth, 23, 59, 59);
    }

    if (dueDateStr != null) {
      final parsed = DateTime.tryParse(dueDateStr);
      if (parsed != null) {
        // Jika hanya tanggal tanpa jam, jadikan 23:59:59
        if (parsed.hour == 0 && parsed.minute == 0) {
          return DateTime(parsed.year, parsed.month, parsed.day, 23, 59, 59);
        }
        return parsed;
      }
    }

    return null;
  }

  // --- PENGINGAT TRANSAKSI TUNAI (HARIAN CUSTOM JAM & MENIT) ---
  // Pengingat harian kini sepenuhnya ditangani via FCM Cloud. Fungsi ini memastikan alarm lokal lama dibatalkan.
  static Future<void> scheduleDailyCashReminder() async {
    await cancelNotification(1001);
  }

  static Future<void> _scheduleNotificationSafe({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    required NotificationDetails details,
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    try {
      await _notificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        scheduledDate,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: matchDateTimeComponents,
      );
    } catch (e) {
      debugPrint('Exact notification schedule failed for $id: $e');
      try {
        await _notificationsPlugin.zonedSchedule(
          id,
          title,
          body,
          scheduledDate,
          details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: matchDateTimeComponents,
        );
      } catch (fallbackError) {
        debugPrint(
            'Inexact notification schedule failed for $id: $fallbackError');
      }
    }
  }

  static Future<void> scheduleCashReminderTestInTwoMinutes() async {
    const androidDetails = AndroidNotificationDetails(
      'cash_reminder_channel',
      'Pengingat Transaksi Tunai',
      channelDescription:
          'Mengingatkan untuk mencatat pengeluaran tunai setiap malam',
      importance: Importance.high,
      priority: Priority.high,
    );

    final scheduledDate =
        tz.TZDateTime.now(tz.local).add(const Duration(minutes: 2));
    await _scheduleNotificationSafe(
      id: 1002,
      title: 'Tes Pengingat Transaksi Tunai',
      body: 'Ini tes jalur yang sama dengan pengingat tunai harian.',
      scheduledDate: scheduledDate,
      details: const NotificationDetails(android: androidDetails),
    );
  }

  static Future<Map<String, dynamic>> getDiagnostics() async {
    final pending = await _notificationsPlugin.pendingNotificationRequests();
    final androidPlatform =
        _notificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    bool? exactAllowed;
    try {
      exactAllowed = await androidPlatform?.canScheduleExactNotifications();
    } catch (e) {
      debugPrint('Exact alarm diagnostic failed: $e');
    }

    String timezoneName = tz.local.name;
    try {
      final timezoneInfo = await FlutterTimezone.getLocalTimezone();
      timezoneName = timezoneInfo.identifier;
    } catch (e) {
      debugPrint('Timezone diagnostic failed: $e');
    }

    final reminderTime = await getCashReminderTime();
    final now = tz.TZDateTime.now(tz.local);
    var nextCashReminder = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      reminderTime.hour,
      reminderTime.minute,
    );
    if (nextCashReminder.isBefore(now)) {
      nextCashReminder = nextCashReminder.add(const Duration(days: 1));
    }

    return {
      'timezone': timezoneName,
      'localNow': now.toString(),
      'cashReminderEnabled': await isCashReminderEnabled(),
      'cashReminderTime':
          '${reminderTime.hour.toString().padLeft(2, '0')}:${reminderTime.minute.toString().padLeft(2, '0')}',
      'nextCashReminder': nextCashReminder.toString(),
      'exactAlarmAllowed': exactAllowed,
      'pendingCount': pending.length,
      'pending': pending
          .map((p) => {
                'id': p.id,
                'title': p.title ?? '',
                'body': p.body ?? '',
              })
          .toList(),
    };
  }

  // --- PERINGATAN ANGGARAN (BUDGET WARNING / OVERBUDGET) ---
  static Future<void> showBudgetWarning({
    required String category,
    required double spent,
    required double limit,
    required double percentage,
  }) async {
    if (!await isBudgetAlertEnabled()) return;

    final currencyFmt =
        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final spentStr = currencyFmt.format(spent);
    final limitStr = currencyFmt.format(limit);

    final bool isOver = percentage >= 100;
    final title = isOver
        ? '⚠️ Peringatan Overbudget: $category'
        : '⚡ Mendekati Batas: $category';
    final body = isOver
        ? 'Pengeluaran sudah mencapai $spentStr, melebihi limit anggaran $limitStr!'
        : 'Pengeluaran kategori $category sudah mencapai ${percentage.toStringAsFixed(0)}% dari limit $limitStr ($spentStr).';

    const androidDetails = AndroidNotificationDetails(
      'budget_alert_channel',
      'Peringatan Anggaran',
      channelDescription:
          'Pemberitahuan ketika pengeluaran mendekati atau melebihi batas anggaran',
      importance: Importance.high,
      priority: Priority.high,
    );

    await _notificationsPlugin.show(
      category.hashCode,
      title,
      body,
      const NotificationDetails(android: androidDetails),
    );
  }

  // --- PENGINGAT JATUH TEMPO UTANG & TAGIHAN ---
  static Future<void> showDueDateAlert({
    required String title,
    required String personOrName,
    required double amount,
    required String dueDate,
  }) async {
    if (!await isDueDateAlertEnabled()) return;

    final currencyFmt =
        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final amountStr = currencyFmt.format(amount);

    const androidDetails = AndroidNotificationDetails(
      'due_date_channel',
      'Pengingat Jatuh Tempo',
      channelDescription:
          'Pengingat untuk utang/piutang dan tagihan jatuh tempo',
      importance: Importance.high,
      priority: Priority.high,
    );

    await _notificationsPlugin.show(
      personOrName.hashCode,
      '⏰ Jatuh Tempo: $title',
      'Tagihan/Utang $personOrName sebesar $amountStr jatuh tempo pada $dueDate.',
      const NotificationDetails(android: androidDetails),
    );
  }

  /// Mengirim notifikasi pengujian (langsung atau berjadwal hitungan detik)
  static Future<void> showTestNotification({int delaySeconds = 0}) async {
    const androidDetails = AndroidNotificationDetails(
      'test_channel',
      'Uji Coba Notifikasi',
      channelDescription: 'Saluran pengujian sistem notifikasi aplikasi',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );

    if (delaySeconds <= 0) {
      await _notificationsPlugin.show(
        9999,
        '🔔 Tes Notifikasi Berhasil!',
        'Sistem notifikasi lokal Expense Tracker aktif dan bekerja dengan normal di HP Anda.',
        const NotificationDetails(android: androidDetails),
      );
    } else {
      final scheduledDate =
          tz.TZDateTime.now(tz.local).add(Duration(seconds: delaySeconds));
      await _scheduleNotificationSafe(
        id: 9999,
        title: '⏰ Uji Notifikasi ($delaySeconds Detik)',
        body:
            'Alarm pengingat berjangka waktu berhasil diterima tepat pada waktunya!',
        scheduledDate: scheduledDate,
        details: const NotificationDetails(android: androidDetails),
      );
    }
  }

  static Future<void> cancelNotification(int id) async {
    await _notificationsPlugin.cancel(id);
  }
}

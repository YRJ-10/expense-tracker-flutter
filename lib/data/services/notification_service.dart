import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:intl/intl.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const String _keyCashReminder = 'notif_cash_reminder_enabled';
  static const String _keyBudgetAlert = 'notif_budget_alert_enabled';
  static const String _keyDueDateAlert = 'notif_due_date_alert_enabled';

  static bool _isInitialized = false;

  /// Inisialisasi plugin notifikasi & timezone
  static Future<void> initialize() async {
    if (_isInitialized) return;

    tz.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _notificationsPlugin.initialize(initSettings);

    // Minta izin notifikasi di Android 13+
    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _isInitialized = true;

    // Jadwalkan pengingat harian jika aktif
    if (await isCashReminderEnabled()) {
      await scheduleDailyCashReminder();
    }
  }

  // --- PREFERENSI NOTIFIKASI ---
  static Future<bool> isCashReminderEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyCashReminder) ?? true;
  }

  static Future<void> setCashReminderEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyCashReminder, enabled);
    if (enabled) {
      await scheduleDailyCashReminder();
    } else {
      await cancelNotification(1001); // ID untuk pengingat tunai
    }
  }

  static Future<bool> isBudgetAlertEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyBudgetAlert) ?? true;
  }

  static Future<void> setBudgetAlertEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBudgetAlert, enabled);
  }

  static Future<bool> isDueDateAlertEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyDueDateAlert) ?? true;
  }

  static Future<void> setDueDateAlertEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDueDateAlert, enabled);
  }

  // --- PENGINGAT TRANSAKSI TUNAI (HARIAN JAM 20:30) ---
  static Future<void> scheduleDailyCashReminder() async {
    try {
      const androidDetails = AndroidNotificationDetails(
        'cash_reminder_channel',
        'Pengingat Transaksi Tunai',
        channelDescription: 'Mengingatkan untuk mencatat pengeluaran tunai setiap malam',
        importance: Importance.high,
        priority: Priority.high,
      );

      final now = tz.TZDateTime.now(tz.local);
      var scheduledDate = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        20,
        30, // Jam 20:30 malam
      );

      if (scheduledDate.isBefore(now)) {
        scheduledDate = scheduledDate.add(const Duration(days: 1));
      }

      await _notificationsPlugin.zonedSchedule(
        1001,
        'Pengingat Pengeluaran Tunai 💵',
        'Ada transaksi tunai atau jajan hari ini yang belum dicatat di aplikasi?',
        scheduledDate,
        const NotificationDetails(android: androidDetails),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (_) {}
  }

  // --- PERINGATAN ANGGARAN (BUDGET WARNING / OVERBUDGET) ---
  static Future<void> showBudgetWarning({
    required String category,
    required double spent,
    required double limit,
    required double percentage,
  }) async {
    if (!await isBudgetAlertEnabled()) return;

    final currencyFmt = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final spentStr = currencyFmt.format(spent);
    final limitStr = currencyFmt.format(limit);

    final bool isOver = percentage >= 100;
    final title = isOver ? '⚠️ Peringatan Overbudget: $category' : '⚡ Mendekati Batas: $category';
    final body = isOver
        ? 'Pengeluaran sudah mencapai $spentStr, melebihi limit anggaran $limitStr!'
        : 'Pengeluaran kategori $category sudah mencapai ${percentage.toStringAsFixed(0)}% dari limit $limitStr ($spentStr).';

    const androidDetails = AndroidNotificationDetails(
      'budget_alert_channel',
      'Peringatan Anggaran',
      channelDescription: 'Pemberitahuan ketika pengeluaran mendekati atau melebihi batas anggaran',
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

    final currencyFmt = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final amountStr = currencyFmt.format(amount);

    const androidDetails = AndroidNotificationDetails(
      'due_date_channel',
      'Pengingat Jatuh Tempo',
      channelDescription: 'Pengingat untuk utang/piutang dan tagihan jatuh tempo',
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

  static Future<void> cancelNotification(int id) async {
    await _notificationsPlugin.cancel(id);
  }
}

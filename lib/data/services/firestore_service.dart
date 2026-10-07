import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:expense_tracker_flutter/data/services/notification_service.dart';

class FirestoreService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static User? get currentUser => _auth.currentUser;
  static String? get currentUserId => _auth.currentUser?.uid;

  // Stream Auth State
  static Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ------------------ PROFILES ------------------
  static Future<Map<String, dynamic>?> getProfile(String userId) async {
    final doc = await _db.collection('profiles').doc(userId).get();
    if (doc.exists) {
      final data = doc.data()!;
      data['id'] = doc.id;
      return data;
    }
    return null;
  }

  static Future<void> saveProfile(
      String userId, Map<String, dynamic> data) async {
    await _db
        .collection('profiles')
        .doc(userId)
        .set(data, SetOptions(merge: true));
  }

  // ------------------ WALLETS ------------------
  static Future<List<Map<String, dynamic>>> getWallets(String userId) async {
    final snap = await _db
        .collection('wallets')
        .where('user_id', isEqualTo: userId)
        .get();
    return snap.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return data;
    }).toList();
  }

  static Future<String> addWallet(Map<String, dynamic> data) async {
    final docRef = _db.collection('wallets').doc();
    final id = docRef.id;
    data['id'] = id;
    data['created_at'] = DateTime.now().toIso8601String();
    await docRef.set(data);
    return id;
  }

  static Future<void> updateWallet(
      String walletId, Map<String, dynamic> data) async {
    data['updated_at'] = DateTime.now().toIso8601String();
    await _db
        .collection('wallets')
        .doc(walletId)
        .set(data, SetOptions(merge: true));
  }

  static Future<void> deleteWallet(String walletId) async {
    await _db.collection('wallets').doc(walletId).delete();
  }

  // ------------------ TRANSACTIONS ------------------
  static Future<List<Map<String, dynamic>>> getTransactions(
      String userId) async {
    final snap = await _db
        .collection('transactions')
        .where('user_id', isEqualTo: userId)
        .get();
    final list = snap.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return data;
    }).toList();
    // Sort descending by date
    list.sort((a, b) {
      final dateA =
          DateTime.tryParse(a['transaction_date']?.toString() ?? '') ??
              DateTime(1970);
      final dateB =
          DateTime.tryParse(b['transaction_date']?.toString() ?? '') ??
              DateTime(1970);
      return dateB.compareTo(dateA);
    });
    return list;
  }

  static Future<TransactionPage> getTransactionPage({
    required String userId,
    required DateTime startDate,
    required DateTime endDate,
    int limit = 50,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async {
    var query = _db
        .collection('transactions')
        .where('user_id', isEqualTo: userId)
        .where('transaction_date',
            isGreaterThanOrEqualTo: startDate.toIso8601String())
        .where('transaction_date',
            isLessThanOrEqualTo: endDate.toIso8601String())
        .orderBy('transaction_date', descending: true)
        .limit(limit);

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    final snap = await query.get();
    final items = snap.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return data;
    }).toList();

    return TransactionPage(
      items: items,
      lastDocument: snap.docs.isNotEmpty ? snap.docs.last : startAfter,
      hasMore: snap.docs.length == limit,
    );
  }

  static Future<String> addTransaction(Map<String, dynamic> data) async {
    final docRef = _db.collection('transactions').doc();
    final id = docRef.id;
    data['id'] = id;
    data['created_at'] = DateTime.now().toIso8601String();
    await docRef.set(data);

    // Update wallet balance
    final walletId = data['wallet_id'];
    final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
    final type = data['type'];

    if (walletId != null && walletId.toString().isNotEmpty) {
      final walletDoc = await _db.collection('wallets').doc(walletId).get();
      if (walletDoc.exists) {
        final currentBal =
            (walletDoc.data()?['balance'] as num?)?.toDouble() ?? 0.0;
        final newBal =
            type == 'income' ? (currentBal + amount) : (currentBal - amount);
        await _db
            .collection('wallets')
            .doc(walletId)
            .update({'balance': newBal});
      }
    }

    // Peringatan otomatis jika pengeluaran mendekati atau melebihi limit anggaran
    if (type == 'expense') {
      final userId = data['user_id']?.toString() ?? currentUserId;
      final category = data['category']?.toString();
      final categoryId = data['category_id']?.toString();
      if (userId != null && category != null) {
        checkBudgetLimit(userId, category, categoryId: categoryId);
      }
    }

    return id;
  }

  static Future<void> deleteTransaction(String transactionId) async {
    final txDoc = await _db.collection('transactions').doc(transactionId).get();
    if (txDoc.exists) {
      final data = txDoc.data()!;
      final walletId = data['wallet_id'];
      final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
      final type = data['type'];

      // Revert wallet balance
      if (walletId != null) {
        final walletDoc = await _db.collection('wallets').doc(walletId).get();
        if (walletDoc.exists) {
          final currentBal =
              (walletDoc.data()?['balance'] as num?)?.toDouble() ?? 0.0;
          final newBal =
              type == 'income' ? (currentBal - amount) : (currentBal + amount);
          await _db
              .collection('wallets')
              .doc(walletId)
              .update({'balance': newBal});
        }
      }
      await _db.collection('transactions').doc(transactionId).delete();
    }
  }

  static Future<void> updateTransaction(
      String transactionId, Map<String, dynamic> data) async {
    await _db
        .collection('transactions')
        .doc(transactionId)
        .set(data, SetOptions(merge: true));
  }

  // ------------------ BUDGETS ------------------
  static Future<List<Map<String, dynamic>>> getBudgets(String userId) async {
    final snap = await _db
        .collection('budgets')
        .where('user_id', isEqualTo: userId)
        .get();
    return snap.docs.map((doc) {
      final d = doc.data();
      d['id'] = doc.id;
      return d;
    }).toList();
  }

  static Future<void> addBudget(Map<String, dynamic> data) async {
    final docRef = _db.collection('budgets').doc();
    data['id'] = docRef.id;
    data['created_at'] = DateTime.now().toIso8601String();
    await docRef.set(data);
  }

  static Future<void> updateBudget(
      String budgetId, Map<String, dynamic> data) async {
    await _db
        .collection('budgets')
        .doc(budgetId)
        .set(data, SetOptions(merge: true));
  }

  static Future<void> deleteBudget(String budgetId) async {
    await _db.collection('budgets').doc(budgetId).delete();
  }

  // ------------------ FINANCIAL GOALS ------------------
  static Future<List<Map<String, dynamic>>> getGoals(String userId) async {
    final snap = await _db
        .collection('financial_goals')
        .where('user_id', isEqualTo: userId)
        .get();
    return snap.docs.map((doc) {
      final d = doc.data();
      d['id'] = doc.id;
      return d;
    }).toList();
  }

  static Future<void> addGoal(Map<String, dynamic> data) async {
    final docRef = _db.collection('financial_goals').doc();
    data['id'] = docRef.id;
    data['created_at'] = DateTime.now().toIso8601String();
    await docRef.set(data);
  }

  static Future<void> updateGoal(
      String goalId, Map<String, dynamic> data) async {
    await _db
        .collection('financial_goals')
        .doc(goalId)
        .set(data, SetOptions(merge: true));
  }

  static Future<void> deleteGoal(String goalId) async {
    await _db.collection('financial_goals').doc(goalId).delete();
  }

  static Future<void> contributeToGoal({
    required String goalId,
    required String userId,
    required double amount,
    required String walletId,
    required String goalName,
    String? note,
  }) async {
    final goalDoc = await _db.collection('financial_goals').doc(goalId).get();
    if (!goalDoc.exists) return;

    final currentAmount =
        (goalDoc.data()?['current_amount'] as num?)?.toDouble() ?? 0.0;
    final newAmount = currentAmount + amount;

    await _db.collection('financial_goals').doc(goalId).set({
      'current_amount': newAmount,
      'last_contribution_date': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));

    final desc = (note != null && note.trim().isNotEmpty)
        ? note.trim()
        : 'Nabung Target: $goalName';

    await addTransaction({
      'user_id': userId,
      'wallet_id': walletId,
      'amount': amount,
      'type': 'expense',
      'category': 'Tabungan Target',
      'category_id': 'cat_savings',
      'note': desc,
      'description': desc,
      'goal_id': goalId,
      'date': DateTime.now().toIso8601String().split('T')[0],
      'transaction_date': DateTime.now().toIso8601String(),
      'source': 'GOAL_CONTRIBUTION',
    });
  }

  static Future<void> withdrawFromGoal({
    required String goalId,
    required String userId,
    required double amount,
    required String walletId,
    required String goalName,
    String? note,
  }) async {
    final goalDoc = await _db.collection('financial_goals').doc(goalId).get();
    if (!goalDoc.exists) return;

    final currentAmount =
        (goalDoc.data()?['current_amount'] as num?)?.toDouble() ?? 0.0;
    final newAmount = (currentAmount - amount).clamp(0.0, double.infinity);

    await _db.collection('financial_goals').doc(goalId).set({
      'current_amount': newAmount,
      'last_withdrawal_date': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));

    final desc = (note != null && note.trim().isNotEmpty)
        ? note.trim()
        : 'Pencairan Target: $goalName';

    await addTransaction({
      'user_id': userId,
      'wallet_id': walletId,
      'amount': amount,
      'type': 'income',
      'category': 'Cairkan Tabungan',
      'category_id': 'cat_savings_withdraw',
      'note': desc,
      'description': desc,
      'goal_id': goalId,
      'date': DateTime.now().toIso8601String().split('T')[0],
      'transaction_date': DateTime.now().toIso8601String(),
      'source': 'GOAL_WITHDRAWAL',
    });
  }

  // ------------------ DEBTS ------------------
  static Future<List<Map<String, dynamic>>> getDebts(String userId) async {
    final snap =
        await _db.collection('debts').where('user_id', isEqualTo: userId).get();
    return snap.docs.map((doc) {
      final d = doc.data();
      d['id'] = doc.id;
      return d;
    }).toList();
  }

  static Future<void> addDebt(Map<String, dynamic> data) async {
    final docRef = _db.collection('debts').doc();
    data['id'] = docRef.id;
    data['created_at'] = DateTime.now().toIso8601String();
    if (!data.containsKey('remaining_amount')) {
      data['remaining_amount'] = data['amount'];
    }
    if (!data.containsKey('paid_amount')) {
      data['paid_amount'] = 0.0;
    }
    await docRef.set(data);
  }

  static Future<void> updateDebt(
      String debtId, Map<String, dynamic> data) async {
    await _db
        .collection('debts')
        .doc(debtId)
        .set(data, SetOptions(merge: true));
  }

  static Future<void> payDebt({
    required String debtId,
    required String userId,
    required double paymentAmount,
    required String? walletId,
    required String personName,
    required String debtType,
    String? note,
  }) async {
    final debtDoc = await _db.collection('debts').doc(debtId).get();
    if (!debtDoc.exists) return;

    final debtData = debtDoc.data()!;
    final double originalTotal =
        (debtData['amount'] as num?)?.toDouble() ?? 0.0;
    final double currentRemaining =
        (debtData['remaining_amount'] as num?)?.toDouble() ??
            (debtData['is_paid'] == true ? 0.0 : originalTotal);
    final double currentPaid =
        (debtData['paid_amount'] as num?)?.toDouble() ?? 0.0;

    final double newRemaining =
        (currentRemaining - paymentAmount).clamp(0.0, double.infinity);
    final double newPaid = currentPaid + paymentAmount;
    final bool isPaid = newRemaining <= 0;

    await _db.collection('debts').doc(debtId).set({
      'remaining_amount': newRemaining,
      'paid_amount': newPaid,
      'is_paid': isPaid,
      'last_payment_date': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));

    final bool isBorrowed = debtType == 'borrowed';
    final txType = isBorrowed ? 'expense' : 'income';
    final desc = (note != null && note.trim().isNotEmpty)
        ? note.trim()
        : (isBorrowed
            ? 'Bayar Cicilan: $personName'
            : 'Penerimaan Piutang: $personName');

    await addTransaction({
      'user_id': userId,
      'wallet_id': walletId,
      'amount': paymentAmount,
      'type': txType,
      'category': isBorrowed ? 'Bayar Utang' : 'Piutang',
      'category_id': isBorrowed ? 'cat_debt_pay' : 'cat_debt_rec',
      'note': desc,
      'description': desc,
      'debt_id': debtId,
      'date': DateTime.now().toIso8601String().split('T')[0],
      'transaction_date': DateTime.now().toIso8601String(),
      'source': 'MANUAL_DEBT_PAYMENT',
    });
  }

  static Future<void> deleteDebt(String debtId) async {
    await _db.collection('debts').doc(debtId).delete();
  }

  // ------------------ RECURRING TRANSACTIONS ------------------
  static Future<List<Map<String, dynamic>>> getRecurringTransactions(
      String userId) async {
    final snap = await _db
        .collection('recurring_transactions')
        .where('user_id', isEqualTo: userId)
        .get();
    final list = snap.docs.map((doc) {
      final d = doc.data();
      d['id'] = doc.id;
      return d;
    }).toList();
    list.sort((a, b) {
      final bool aActive = a['is_active'] ?? true;
      final bool bActive = b['is_active'] ?? true;
      if (aActive != bActive) return aActive ? -1 : 1;
      final aDue = a['next_due_date']?.toString() ?? '';
      final bDue = b['next_due_date']?.toString() ?? '';
      return aDue.compareTo(bDue);
    });
    return list;
  }

  static Future<void> addRecurring(Map<String, dynamic> data) async {
    final docRef = _db.collection('recurring_transactions').doc();
    data['id'] = docRef.id;
    data['created_at'] = DateTime.now().toIso8601String();
    await docRef.set(data);
  }

  static Future<void> updateRecurring(
      String id, Map<String, dynamic> data) async {
    data['updated_at'] = DateTime.now().toIso8601String();
    await _db
        .collection('recurring_transactions')
        .doc(id)
        .set(data, SetOptions(merge: true));
  }

  static Future<void> deleteRecurring(String id) async {
    await _db.collection('recurring_transactions').doc(id).delete();
  }

  static DateTime calculateNextDueDate({
    required String frequency,
    required DateTime fromDate,
    int? dayOfMonth,
  }) {
    switch (frequency.toLowerCase()) {
      case 'daily':
      case 'harian':
        return fromDate.add(const Duration(days: 1));
      case 'weekly':
      case 'mingguan':
        return fromDate.add(const Duration(days: 7));
      case 'yearly':
      case 'tahunan':
        int targetDay = dayOfMonth ?? fromDate.day;
        int targetMonth = fromDate.month;
        int targetYear = fromDate.year + 1;
        final maxDays = DateTime(targetYear, targetMonth + 1, 0).day;
        if (targetDay > maxDays) targetDay = maxDays;
        return DateTime(targetYear, targetMonth, targetDay, fromDate.hour, fromDate.minute);
      case 'monthly':
      case 'bulanan':
      default:
        int targetDay = dayOfMonth ?? fromDate.day;
        int nextMonth = fromDate.month + 1;
        int year = fromDate.year;
        if (nextMonth > 12) {
          year += 1;
          nextMonth = 1;
        }
        final maxDays = DateTime(year, nextMonth + 1, 0).day;
        if (targetDay > maxDays) targetDay = maxDays;
        return DateTime(year, nextMonth, targetDay, fromDate.hour, fromDate.minute);
    }
  }

  static Future<bool> executeRecurringTransaction({
    required String recurringId,
    required String userId,
    DateTime? executionDate,
    bool isManualTrigger = false,
  }) async {
    final doc =
        await _db.collection('recurring_transactions').doc(recurringId).get();
    if (!doc.exists) return false;
    final data = doc.data()!;
    final double amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
    final String type = data['type'] ?? 'expense';
    final String name = data['name'] ?? data['title'] ?? 'Transaksi Rutin';
    final String? walletId = data['wallet_id'];
    final String category =
        data['category'] ?? (type == 'expense' ? 'Tagihan' : 'Gaji');
    final String? categoryId = data['category_id'];
    final String frequency = data['frequency'] ?? 'monthly';
    final int? dayOfMonth = data['day_of_month'] as int?;

    final now = executionDate ?? DateTime.now();

    // 1. Add transaction
    await addTransaction({
      'user_id': userId,
      'wallet_id': walletId,
      'amount': amount,
      'type': type,
      'category': category,
      'category_id': categoryId,
      'note': 'Transaksi Rutin: $name',
      'description': name,
      'date': now.toIso8601String().split('T')[0],
      'transaction_date': now.toIso8601String(),
      'source': isManualTrigger ? 'MANUAL_RECURRING' : 'AUTO_RECURRING',
      'recurring_id': recurringId,
    });

    // 2. Advance next_due_date
    DateTime currentNextDue =
        DateTime.tryParse(data['next_due_date']?.toString() ?? '') ?? now;
    DateTime nextDue = calculateNextDueDate(
      frequency: frequency,
      fromDate: currentNextDue,
      dayOfMonth: dayOfMonth,
    );
    while (nextDue.isBefore(DateTime(now.year, now.month, now.day + 1))) {
      nextDue = calculateNextDueDate(
        frequency: frequency,
        fromDate: nextDue,
        dayOfMonth: dayOfMonth,
      );
    }

    // 3. Update recurring record
    await _db.collection('recurring_transactions').doc(recurringId).set({
      'next_due_date': nextDue.toIso8601String(),
      'last_executed_at': now.toIso8601String(),
    }, SetOptions(merge: true));

    return true;
  }

  static Future<List<String>> processDueRecurringTransactions(
      String userId) async {
    final recurringList = await getRecurringTransactions(userId);
    final now = DateTime.now();
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final List<String> executedNames = [];

    for (final r in recurringList) {
      if (r['is_active'] == false) continue;
      if (r['auto_record'] != true) continue;

      final nextDueStr = r['next_due_date']?.toString();
      if (nextDueStr == null) continue;
      final nextDue = DateTime.tryParse(nextDueStr);
      if (nextDue == null) continue;

      if (nextDue.isBefore(todayEnd) || nextDue.isAtSameMomentAs(todayEnd)) {
        final id = r['id']?.toString();
        if (id != null) {
          final success = await executeRecurringTransaction(
            recurringId: id,
            userId: userId,
            executionDate: now,
            isManualTrigger: false,
          );
          if (success) {
            executedNames.add(r['name'] ?? r['title'] ?? 'Transaksi Rutin');
          }
        }
      }
    }

    return executedNames;
  }

  // ------------------ BUDGET & DUE DATE ALERTS ------------------
  static Future<void> checkBudgetLimit(String userId, String categoryName,
      {String? categoryId}) async {
    try {
      final budgets = await getBudgets(userId);
      final budget = budgets.firstWhere(
        (b) =>
            (b['category']?.toString().toLowerCase() ==
                categoryName.toLowerCase()) ||
            (b['category_name']?.toString().toLowerCase() ==
                categoryName.toLowerCase()) ||
            (b['custom_category_name']?.toString().toLowerCase() ==
                categoryName.toLowerCase()) ||
            (categoryId != null &&
                b['category_id']?.toString() == categoryId &&
                (b['custom_category_name'] == null ||
                    b['custom_category_name'].toString().isEmpty)),
        orElse: () => {},
      );
      if (budget.isEmpty) return;

      final limit = (budget['limit_amount'] as num?)?.toDouble() ??
          (budget['amount'] as num?)?.toDouble() ??
          0.0;
      if (limit <= 0) return;

      final now = DateTime.now();
      final txs = await getTransactions(userId);
      double spentThisMonth = 0.0;
      for (final tx in txs) {
        if (tx['type'] == 'expense' &&
            (tx['category']?.toString().toLowerCase() ==
                    categoryName.toLowerCase() ||
                (categoryId != null &&
                    tx['category_id']?.toString() == categoryId))) {
          final dStr = tx['transaction_date'] ?? tx['date'];
          if (dStr != null) {
            final d = DateTime.tryParse(dStr.toString());
            if (d != null && d.year == now.year && d.month == now.month) {
              spentThisMonth += (tx['amount'] as num?)?.toDouble() ?? 0.0;
            }
          }
        }
      }

      final percentage = (spentThisMonth / limit) * 100;
      final threshold = await NotificationService.getBudgetAlertThreshold();
      if (percentage >= threshold) {
        await NotificationService.showBudgetWarning(
          category: categoryName,
          spent: spentThisMonth,
          limit: limit,
          percentage: percentage,
        );
      }
    } catch (e) {
      // ignore: avoid_print
      print('checkBudgetLimit failed: $e');
    }
  }

  static Future<void> checkUpcomingDueDates(String userId) async {
    try {
      final debts = await getDebts(userId);
      final now = DateTime.now();
      final offsetHours = await NotificationService.getDueDateOffsetHours();

      for (final debt in debts) {
        final isPaid = debt['is_paid'] == true;
        final isRecurring = debt['is_recurring'] == true;
        final recurringDay = (debt['recurring_day'] as num?)?.toInt();
        final dueStr = debt['due_date']?.toString();

        // Hitung target due date berikutnya
        final targetDueDate = NotificationService.calculateNextDueDate(
          isRecurring: isRecurring,
          recurringDay: recurringDay,
          dueDateStr: dueStr,
          isPaid: isPaid,
        );

        if (targetDueDate == null) continue;

        // Jika bukan utang berulang dan sudah lunas, lewati
        if (!isRecurring && isPaid) continue;

        // Hitung selisih jam
        final diffHours = targetDueDate.difference(now).inHours;

        // Cek apakah masuk dalam jendela alert sesuai offset preferensi
        bool shouldAlert = false;
        if (offsetHours == 0) {
          shouldAlert = diffHours >= 0 && diffHours <= 24;
        } else {
          shouldAlert = diffHours >= 0 && diffHours <= offsetHours;
        }

        if (shouldAlert) {
          final person = debt['person_name']?.toString() ?? 'Seseorang';
          final amount = (debt['remaining_amount'] as num?)?.toDouble() ??
              ((debt['amount'] as num?)?.toDouble() ?? 0.0);
          final isBorrowed = debt['type'] == 'borrowed';

          String dueLabel;
          if (diffHours <= 0) {
            dueLabel = 'Hari ini (Segera)';
          } else if (diffHours < 24) {
            dueLabel = '$diffHours jam lagi';
          } else if (diffHours < 48) {
            dueLabel = 'Besok (~$diffHours jam lagi)';
          } else {
            final days = (diffHours / 24).ceil();
            dueLabel = '$days hari lagi';
          }

          await NotificationService.showDueDateAlert(
            title: isBorrowed ? 'Bayar Utang' : 'Tagih Piutang',
            personOrName: person,
            amount: amount,
            dueDate: dueLabel,
          );
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('checkUpcomingDueDates failed: $e');
    }
  }
}

class TransactionPage {
  final List<Map<String, dynamic>> items;
  final DocumentSnapshot<Map<String, dynamic>>? lastDocument;
  final bool hasMore;

  const TransactionPage({
    required this.items,
    required this.lastDocument,
    required this.hasMore,
  });
}

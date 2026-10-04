import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

  static Future<void> saveProfile(String userId, Map<String, dynamic> data) async {
    await _db.collection('profiles').doc(userId).set(data, SetOptions(merge: true));
  }

  // ------------------ WALLETS ------------------
  static Future<List<Map<String, dynamic>>> getWallets(String userId) async {
    final snap = await _db.collection('wallets').where('user_id', isEqualTo: userId).get();
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

  static Future<void> updateWallet(String walletId, Map<String, dynamic> data) async {
    data['updated_at'] = DateTime.now().toIso8601String();
    await _db.collection('wallets').doc(walletId).set(data, SetOptions(merge: true));
  }

  static Future<void> deleteWallet(String walletId) async {
    await _db.collection('wallets').doc(walletId).delete();
  }

  // ------------------ TRANSACTIONS ------------------
  static Future<List<Map<String, dynamic>>> getTransactions(String userId) async {
    final snap = await _db.collection('transactions').where('user_id', isEqualTo: userId).get();
    final list = snap.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return data;
    }).toList();
    // Sort descending by date
    list.sort((a, b) {
      final dateA = DateTime.tryParse(a['transaction_date']?.toString() ?? '') ?? DateTime(1970);
      final dateB = DateTime.tryParse(b['transaction_date']?.toString() ?? '') ?? DateTime(1970);
      return dateB.compareTo(dateA);
    });
    return list;
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
        final currentBal = (walletDoc.data()?['balance'] as num?)?.toDouble() ?? 0.0;
        final newBal = type == 'income' ? (currentBal + amount) : (currentBal - amount);
        await _db.collection('wallets').doc(walletId).update({'balance': newBal});
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
          final currentBal = (walletDoc.data()?['balance'] as num?)?.toDouble() ?? 0.0;
          final newBal = type == 'income' ? (currentBal - amount) : (currentBal + amount);
          await _db.collection('wallets').doc(walletId).update({'balance': newBal});
        }
      }
      await _db.collection('transactions').doc(transactionId).delete();
    }
  }

  static Future<void> updateTransaction(String transactionId, Map<String, dynamic> data) async {
    await _db.collection('transactions').doc(transactionId).set(data, SetOptions(merge: true));
  }

  // ------------------ BUDGETS ------------------
  static Future<List<Map<String, dynamic>>> getBudgets(String userId) async {
    final snap = await _db.collection('budgets').where('user_id', isEqualTo: userId).get();
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

  static Future<void> updateBudget(String budgetId, Map<String, dynamic> data) async {
    await _db.collection('budgets').doc(budgetId).set(data, SetOptions(merge: true));
  }

  static Future<void> deleteBudget(String budgetId) async {
    await _db.collection('budgets').doc(budgetId).delete();
  }

  // ------------------ FINANCIAL GOALS ------------------
  static Future<List<Map<String, dynamic>>> getGoals(String userId) async {
    final snap = await _db.collection('financial_goals').where('user_id', isEqualTo: userId).get();
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

  static Future<void> updateGoal(String goalId, Map<String, dynamic> data) async {
    await _db.collection('financial_goals').doc(goalId).set(data, SetOptions(merge: true));
  }

  static Future<void> deleteGoal(String goalId) async {
    await _db.collection('financial_goals').doc(goalId).delete();
  }

  // ------------------ DEBTS ------------------
  static Future<List<Map<String, dynamic>>> getDebts(String userId) async {
    final snap = await _db.collection('debts').where('user_id', isEqualTo: userId).get();
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
    await docRef.set(data);
  }

  static Future<void> updateDebt(String debtId, Map<String, dynamic> data) async {
    await _db.collection('debts').doc(debtId).set(data, SetOptions(merge: true));
  }

  static Future<void> deleteDebt(String debtId) async {
    await _db.collection('debts').doc(debtId).delete();
  }

  // ------------------ RECURRING TRANSACTIONS ------------------
  static Future<List<Map<String, dynamic>>> getRecurringTransactions(String userId) async {
    final snap = await _db.collection('recurring_transactions').where('user_id', isEqualTo: userId).get();
    return snap.docs.map((doc) {
      final d = doc.data();
      d['id'] = doc.id;
      return d;
    }).toList();
  }

  static Future<void> addRecurring(Map<String, dynamic> data) async {
    final docRef = _db.collection('recurring_transactions').doc();
    data['id'] = docRef.id;
    data['created_at'] = DateTime.now().toIso8601String();
    await docRef.set(data);
  }

  static Future<void> updateRecurring(String id, Map<String, dynamic> data) async {
    await _db.collection('recurring_transactions').doc(id).set(data, SetOptions(merge: true));
  }

  static Future<void> deleteRecurring(String id) async {
    await _db.collection('recurring_transactions').doc(id).delete();
  }
}

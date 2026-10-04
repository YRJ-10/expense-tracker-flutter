import 'package:flutter/material.dart';
import 'package:expense_tracker_flutter/data/services/firestore_service.dart';
import 'package:expense_tracker_flutter/data/services/gmail_sync_service.dart';
import 'package:expense_tracker_flutter/presentation/screens/wallet/wallet_screen.dart';
import 'package:expense_tracker_flutter/presentation/screens/budget/budget_screen.dart';
import 'package:expense_tracker_flutter/presentation/screens/goals/goals_screen.dart';
import 'package:expense_tracker_flutter/presentation/screens/debt/debt_screen.dart';

class DashboardScreen extends StatefulWidget {
  final VoidCallback? onNavigateToHistory;
  const DashboardScreen({super.key, this.onNavigateToHistory});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _userName = '';
  double _totalBalance = 0;
  double _bankBalance = 0;
  double _cashBalance = 0;
  double _monthlyIncome = 0;
  double _monthlyExpense = 0;
  List<Map<String, dynamic>> _recentTransactions = [];
  bool _isLoading = true;
  DateTime _selectedDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  GmailSyncStatus _syncStatus = GmailSyncStatus(isConnected: false);
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final userId = FirestoreService.currentUserId;
    if (userId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      // Load profile
      final profile = await FirestoreService.getProfile(userId);
      final allT = await FirestoreService.getTransactions(userId);
      final wallets = await FirestoreService.getWallets(userId);
      final syncStatus = await GmailSyncService.getStatus(userId);

      double tBalance = 0;
      double bBalance = 0;
      double cBalance = 0;

      // Add all wallet balances
      for (var w in wallets) {
        final bal = (w['balance'] as num?)?.toDouble() ?? 0.0;
        tBalance += bal;
        final bankName = (w['bank_name'] ?? '').toString().toUpperCase();
        if (bankName == 'CASH') {
          cBalance += bal;
        } else {
          bBalance += bal;
        }
      }

      // If no wallets yet, sum directly from transactions
      if (wallets.isEmpty) {
        for (var t in allT) {
          final amt = (t['amount'] as num?)?.toDouble() ?? 0.0;
          if (t['type'] == 'income') {
            tBalance += amt;
          } else {
            tBalance -= amt;
          }
        }
        bBalance = tBalance;
      }

      // Filter monthly transactions
      final startOfMonth = DateTime(_selectedDate.year, _selectedDate.month, 1);
      final endOfMonth = DateTime(_selectedDate.year, _selectedDate.month + 1, 0, 23, 59, 59);

      final monthlyT = allT.where((t) {
        final rawDate = t['transaction_date'] ?? t['date'];
        if (rawDate == null) return false;
        final date = DateTime.tryParse(rawDate.toString());
        if (date == null) return false;
        return date.isAfter(startOfMonth.subtract(const Duration(seconds: 1))) &&
            date.isBefore(endOfMonth.add(const Duration(seconds: 1)));
      }).toList();

      double mIncome = 0;
      double mExpense = 0;
      for (var t in monthlyT) {
        final amt = (t['amount'] as num?)?.toDouble() ?? 0.0;
        if (t['type'] == 'income') {
          mIncome += amt;
        } else {
          mExpense += amt;
        }
      }

      final recent = allT.take(5).toList();

      if (!mounted) return;
      setState(() {
        _userName = profile?['full_name'] ?? 'Pengguna';
        _totalBalance = tBalance;
        _bankBalance = bBalance;
        _cashBalance = cBalance;
        _monthlyIncome = mIncome;
        _monthlyExpense = mExpense;
        _recentTransactions = List<Map<String, dynamic>>.from(recent);
        _syncStatus = syncStatus;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _quickSync() async {
    final userId = FirestoreService.currentUserId;
    if (userId == null) return;

    if (!_syncStatus.isConnected) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen()));
      _loadData();
      return;
    }

    setState(() => _isSyncing = true);
    final res = await GmailSyncService.triggerSync(userId);
    if (mounted) {
      setState(() => _isSyncing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.success
              ? 'Sync Berhasil: +${res.newTransactionsCount} transaksi baru'
              : 'Sync Gagal: ${res.error}'),
          backgroundColor: res.success ? Colors.green : Colors.red,
        ),
      );
      _loadData();
    }
  }

  String _formatCurrency(double amount) {
    return 'Rp ${amount.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';
  }

  void _changeMonth(int increment) {
    setState(() {
      _selectedDate = DateTime(_selectedDate.year, _selectedDate.month + increment, 1);
      _isLoading = true;
    });
    _loadData();
  }

  String _getMonthName(DateTime date) {
    const monthNames = ['', 'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'];
    return '${monthNames[date.month]} ${date.year}';
  }

  Widget _buildFeatureBtn(BuildContext context, IconData icon, String label, Widget screen) {
    return GestureDetector(
      onTap: () async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
        _loadData();
      },
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: Icon(icon, color: const Color(0xFF6C63FF), size: 28),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F1A),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Halo, $_userName 👋',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Ringkasan keuanganmu',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Sinkronisasi Gmail Mandiri',
            onPressed: _isSyncing ? null : _quickSync,
            icon: _isSyncing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6C63FF)))
                : Icon(
                    Icons.sync,
                    color: _syncStatus.isConnected ? Colors.greenAccent : Colors.white60,
                  ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF)))
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Balance Card
                    InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen()));
                        _loadData();
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF6C63FF), Color(0xFF9C95FF)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF6C63FF).withOpacity(0.3),
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      'Total Saldo (Kas & Bank)',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.85),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(Icons.chevron_right, size: 16, color: Colors.white.withOpacity(0.7)),
                                  ],
                                ),
                                if (_syncStatus.isConnected)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: const [
                                        Icon(Icons.check_circle, size: 12, color: Colors.greenAccent),
                                        SizedBox(width: 4),
                                        Text('Mandiri Sync', style: TextStyle(color: Colors.white, fontSize: 11)),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _formatCurrency(_totalBalance),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 30,
                                fontWeight: FontWeight.bold,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 16),
                            // Breakdown: Rekening Bank vs Kas Brankas
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.18),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.15),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(Icons.account_balance, size: 16, color: Colors.white),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Rekening Bank',
                                                style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                _formatCurrency(_bankBalance),
                                                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    width: 1,
                                    height: 32,
                                    color: Colors.white.withOpacity(0.2),
                                    margin: const EdgeInsets.symmetric(horizontal: 8),
                                  ),
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.15),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(Icons.payments, size: 16, color: Colors.white),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Kas Fisik / Brankas',
                                                style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                _formatCurrency(_cashBalance),
                                                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Month Navigation
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left, color: Colors.white),
                          onPressed: () => _changeMonth(-1),
                        ),
                        Text(
                          _getMonthName(_selectedDate),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right, color: Colors.white),
                          onPressed: () => _changeMonth(1),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Monthly Cashflow Summary Card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A2E),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.arrow_downward, color: Colors.greenAccent, size: 16),
                                    const SizedBox(width: 4),
                                    Text('Pemasukan', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _formatCurrency(_monthlyIncome),
                                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                          Container(width: 1, height: 40, color: Colors.white.withOpacity(0.1)),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(left: 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.arrow_upward, color: Colors.redAccent, size: 16),
                                      const SizedBox(width: 4),
                                      Text('Pengeluaran', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12)),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatCurrency(_monthlyExpense),
                                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Quick Actions / Features
                    const Text(
                      'Fitur Keuangan',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildFeatureBtn(context, Icons.account_balance_wallet, 'Dompet', const WalletScreen()),
                        _buildFeatureBtn(context, Icons.account_balance, 'Anggaran', const BudgetScreen()),
                        _buildFeatureBtn(context, Icons.flag, 'Target', const GoalsScreen()),
                        _buildFeatureBtn(context, Icons.handshake, 'Utang', const DebtScreen()),
                      ],
                    ),
                    const SizedBox(height: 32),

                    // Recent Transactions
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Transaksi Terakhir',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        if (widget.onNavigateToHistory != null)
                          TextButton(
                            onPressed: widget.onNavigateToHistory,
                            child: const Text('Lihat Semua', style: TextStyle(color: Color(0xFF6C63FF))),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (_recentTransactions.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A2E),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Center(
                          child: Text(
                            'Belum ada transaksi di bulan ini.',
                            style: TextStyle(color: Colors.white.withOpacity(0.5)),
                          ),
                        ),
                      )
                    else
                      ..._recentTransactions.map((tx) {
                        final bool isIncome = tx['type'] == 'income';
                        final double amt = (tx['amount'] as num?)?.toDouble() ?? 0.0;
                        final String desc = tx['description'] ?? tx['note'] ?? tx['category'] ?? 'Transaksi';
                        final String? bank = tx['bank_name'];
                        final bool isAutoSynced = tx['is_auto_synced'] == true;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1A2E),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: (isIncome ? Colors.green : Colors.red).withOpacity(0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isIncome ? Icons.arrow_downward : Icons.arrow_upward,
                                  color: isIncome ? Colors.greenAccent : Colors.redAccent,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      desc,
                                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Text(
                                          tx['category'] ?? 'Umum',
                                          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                                        ),
                                        if (isAutoSynced) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF6C63FF).withOpacity(0.25),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              bank ?? 'Mandiri Auto',
                                              style: const TextStyle(color: Color(0xFF9C95FF), fontSize: 10, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '${isIncome ? '+' : '-'}${_formatCurrency(amt)}',
                                style: TextStyle(
                                  color: isIncome ? Colors.greenAccent : Colors.redAccent,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
    );
  }
}
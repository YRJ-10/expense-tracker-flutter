import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
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
  final _supabase = Supabase.instance.client;
  String _userName = '';
  double _totalBalance = 0;
  double _monthlyIncome = 0;
  double _monthlyExpense = 0;
  List<Map<String, dynamic>> _recentTransactions = [];
  bool _isLoading = true;
  DateTime _selectedDate = DateTime(DateTime.now().year, DateTime.now().month, 1);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final userId = _supabase.auth.currentUser!.id;

    // Load profile
    final profile = await _supabase
        .from('profiles')
        .select()
        .eq('id', userId)
        .single();

    final allT = await _supabase.from('transactions').select().eq('user_id', userId);
    
    double tBalance = 0;
    for (var t in allT) {
      final amt = (t['amount'] as num).toDouble();
      if (t['type'] == 'income') {
        tBalance += amt;
      } else {
        tBalance -= amt;
      }
    }

    final startDateString = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final endDateString = DateFormat('yyyy-MM-dd').format(DateTime(_selectedDate.year, _selectedDate.month + 1, 0));

    final monthlyT = await _supabase
        .from('transactions')
        .select('*, categories(name, icon, color)')
        .eq('user_id', userId)
        .gte('date', startDateString)
        .lte('date', endDateString)
        .order('date', ascending: false);

    double mIncome = 0;
    double mExpense = 0;
    for (var t in monthlyT) {
      final amt = (t['amount'] as num).toDouble();
      if (t['type'] == 'income') {
        mIncome += amt;
      } else {
        mExpense += amt;
      }
    }

    final recent = monthlyT.take(5).toList();

    if (!mounted) return;
    setState(() {
      _userName = profile['full_name'] ?? 'User';
      _totalBalance = tBalance;
      _monthlyIncome = mIncome;
      _monthlyExpense = mExpense;
      _recentTransactions = List<Map<String, dynamic>>.from(recent);
      _isLoading = false;
    });
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

  Future<void> _logout() async {
    await _supabase.auth.signOut();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
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
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: _logout,
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
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6C63FF), Color(0xFF9C95FF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total Saldo',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _formatCurrency(_totalBalance),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

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
              const SizedBox(height: 32),

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
                  _buildFeatureBtn(context, Icons.handshake, 'Hutang', const DebtScreen()),
                ],
              ),
              const SizedBox(height: 32),

              // Transaksi Terbaru
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Transaksi Terbaru',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton(
                    onPressed: () => widget.onNavigateToHistory?.call(),
                    child: const Text('Lihat Semua', style: TextStyle(color: Color(0xFF6C63FF))),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              _recentTransactions.isEmpty
                  ? Center(
                child: Column(
                  children: [
                    const SizedBox(height: 32),
                    Icon(Icons.receipt_long, size: 60, color: Colors.white.withOpacity(0.2)),
                    const SizedBox(height: 16),
                    Text(
                      'Belum ada transaksi',
                      style: TextStyle(color: Colors.white.withOpacity(0.4)),
                    ),
                  ],
                ),
              )
                  : ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _recentTransactions.length,
                itemBuilder: (context, index) {
                  final t = _recentTransactions[index];
                  final isIncome = t['type'] == 'income';
                  final category = t['categories'];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A2E),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F0F1A),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            category != null ? category['icon'] : '📦',
                            style: const TextStyle(fontSize: 20),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                category != null ? category['name'] : 'Lainnya',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                              ),
                              Text(
                                t['note'] ?? '',
                                style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${isIncome ? '+' : '-'} ${_formatCurrency(t['amount'].toDouble())}',
                          style: TextStyle(
                            color: isIncome ? Colors.greenAccent : Colors.redAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),

    );
  }

  Widget _buildFeatureBtn(BuildContext context, IconData icon, String label, Widget screen) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => screen)),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: const Color(0xFF6C63FF), size: 28),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }
}
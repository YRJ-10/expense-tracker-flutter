import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _transactions = [];
  bool _isLoading = true;
  String _filterType = 'all';

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    setState(() => _isLoading = true);
    final userId = _supabase.auth.currentUser!.id;

    var query = _supabase
        .from('transactions')
        .select('*, categories(name, icon, color)')
        .eq('user_id', userId)
        .order('date', ascending: false);

    final transactions = await query;

    setState(() {
      _transactions = List<Map<String, dynamic>>.from(transactions);
      _isLoading = false;
    });
  }

  List<Map<String, dynamic>> get _filteredTransactions {
    if (_filterType == 'all') return _transactions;
    return _transactions.where((t) => t['type'] == _filterType).toList();
  }

  String _formatCurrency(double amount) {
    return 'Rp ${amount.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';
  }

  Future<void> _deleteTransaction(String id) async {
    await _supabase.from('transactions').delete().eq('id', id);
    _loadTransactions();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F1A),
        elevation: 0,
        title: const Text('Riwayat Transaksi', style: TextStyle(color: Colors.white)),
      ),
      body: Column(
        children: [
          // Filter
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(
              children: [
                _filterChip('Semua', 'all'),
                const SizedBox(width: 8),
                _filterChip('Pengeluaran', 'expense'),
                const SizedBox(width: 8),
                _filterChip('Pemasukan', 'income'),
              ],
            ),
          ),

          // List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF)))
                : _filteredTransactions.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.receipt_long, size: 60, color: Colors.white.withOpacity(0.2)),
                  const SizedBox(height: 16),
                  Text('Belum ada transaksi', style: TextStyle(color: Colors.white.withOpacity(0.4))),
                ],
              ),
            )
                : RefreshIndicator(
              onRefresh: _loadTransactions,
              child: ListView.builder(
                padding: const EdgeInsets.all(24),
                itemCount: _filteredTransactions.length,
                itemBuilder: (context, index) {
                  final t = _filteredTransactions[index];
                  final isIncome = t['type'] == 'income';
                  final category = t['categories'];
                  return Dismissible(
                    key: Key(t['id']),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    onDismissed: (_) => _deleteTransaction(t['id']),
                    child: Container(
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
                                Text(
                                  '${t['date']}',
                                  style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11),
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
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final isSelected = _filterType == value;
    return GestureDetector(
      onTap: () => setState(() => _filterType = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6C63FF) : const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
      ),
    );
  }
}
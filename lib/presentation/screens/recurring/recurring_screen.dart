import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RecurringScreen extends StatefulWidget {
  const RecurringScreen({super.key});

  @override
  State<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends State<RecurringScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _recurringList = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRecurring();
  }

  Future<void> _loadRecurring() async {
    setState(() => _isLoading = true);
    final userId = _supabase.auth.currentUser!.id;
    try {
      final recurring = await _supabase
          .from('recurring_transactions')
          .select('*, categories(*)')
          .eq('user_id', userId)
          .order('next_run', ascending: true);
      
      setState(() {
        _recurringList = List<Map<String, dynamic>>.from(recurring);
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatCurrency(double amount) {
    return 'Rp ${amount.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        title: const Text('Transaksi Rutin', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF0F0F1A),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF)))
          : ListView.builder(
              padding: const EdgeInsets.all(24),
              itemCount: _recurringList.length + 1,
              itemBuilder: (context, index) {
                if (index == _recurringList.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: ElevatedButton.icon(
                      onPressed: () {
                         // TODO: Implement Add Recurring
                         ScaffoldMessenger.of(context).showSnackBar(
                           const SnackBar(content: Text('Comming Soon!'))
                         );
                      },
                      icon: const Icon(Icons.add, color: Colors.white),
                      label: const Text('Buat Jadwal Baru', style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1A1A2E),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  );
                }
                final r = _recurringList[index];
                final category = r['categories'];
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
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6C63FF).withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Text(category?['icon'] ?? '🔄', style: const TextStyle(fontSize: 24)),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(category?['name'] ?? r['note'] ?? 'Rutin', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text('Siklus: ${r['frequency']}', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
                            Text('Berikutnya: ${r['next_run']}', style: const TextStyle(color: Colors.greenAccent, fontSize: 12)),
                          ],
                        ),
                      ),
                      Text(_formatCurrency((r['amount'] as num).toDouble()), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

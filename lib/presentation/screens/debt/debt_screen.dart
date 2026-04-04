import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:expense_tracker_flutter/utils/formatters.dart';

class DebtScreen extends StatefulWidget {
  const DebtScreen({super.key});

  @override
  State<DebtScreen> createState() => _DebtScreenState();
}

class _DebtScreenState extends State<DebtScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _debts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDebts();
  }

  Future<void> _loadDebts() async {
    setState(() => _isLoading = true);
    final userId = _supabase.auth.currentUser!.id;
    try {
      final debts = await _supabase
          .from('debts')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      
      setState(() {
        _debts = List<Map<String, dynamic>>.from(debts);
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showAddDebtModal() {
    final nameController = TextEditingController();
    final amountController = TextEditingController();
    String type = 'borrowed'; // or 'lent'

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 24,
                right: 24,
                top: 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Catat Utang/Piutang', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('Utang', style: TextStyle(color: Colors.white, fontSize: 14)),
                          value: 'borrowed',
                          groupValue: type,
                          activeColor: const Color(0xFF6C63FF),
                          onChanged: (val) => setStateModal(() => type = val!),
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('Piutang', style: TextStyle(color: Colors.white, fontSize: 14)),
                          value: 'lent',
                          groupValue: type,
                          activeColor: const Color(0xFF6C63FF),
                          onChanged: (val) => setStateModal(() => type = val!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Nama Orang',
                      labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                      filled: true,
                      fillColor: const Color(0xFF0F0F1A),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: false),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      ThousandsSeparatorInputFormatter(),
                    ],
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Jumlah (Rp)',
                      labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                      filled: true,
                      fillColor: const Color(0xFF0F0F1A),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        if (nameController.text.isNotEmpty && amountController.text.isNotEmpty) {
                          final userId = _supabase.auth.currentUser!.id;
                          try {
                            await _supabase.from('debts').insert({
                              'user_id': userId,
                              'person_name': nameController.text,
                              'amount': double.tryParse(amountController.text.replaceAll('.', '')) ?? 0,
                              'type': type,
                            });
                            if (context.mounted) Navigator.pop(context);
                            _loadDebts();
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Simpan Gagal: $e'), backgroundColor: Colors.red),
                              );
                            }
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6C63FF),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Simpan Data', style: TextStyle(color: Colors.white)),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            );
          }
        );
      },
    );
  }

  Future<void> _markAsPaid(String id) async {
    await _supabase.from('debts').update({'is_paid': true}).eq('id', id);
    _loadDebts();
  }

  String _formatCurrency(double amount) {
    return 'Rp ${amount.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        title: const Text('Utang & Piutang', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF0F0F1A),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF)))
          : ListView.builder(
              padding: const EdgeInsets.all(24),
              itemCount: _debts.length + 1,
              itemBuilder: (context, index) {
                if (index == _debts.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: ElevatedButton.icon(
                      onPressed: _showAddDebtModal,
                      icon: const Icon(Icons.add, color: Colors.white),
                      label: const Text('Catat Baru', style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1A1A2E),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  );
                }
                final debt = _debts[index];
                final isPaid = debt['is_paid'] == true;
                final isBorrowed = debt['type'] == 'borrowed';
                
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
                          color: isBorrowed ? Colors.redAccent.withOpacity(0.2) : Colors.greenAccent.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isBorrowed ? Icons.arrow_downward : Icons.arrow_upward,
                          color: isBorrowed ? Colors.redAccent : Colors.greenAccent,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(debt['person_name'], style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, decoration: isPaid ? TextDecoration.lineThrough : null)),
                            const SizedBox(height: 4),
                            Text(isBorrowed ? 'Saya Berutang' : 'Saya Mengutangi', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(_formatCurrency((debt['amount'] as num).toDouble()), style: TextStyle(color: isPaid ? Colors.grey : Colors.white, fontWeight: FontWeight.bold)),
                          if (!isPaid)
                            TextButton(
                              onPressed: () => _markAsPaid(debt['id']),
                              child: const Text('Tandai Lunas', style: TextStyle(color: Color(0xFF6C63FF), fontSize: 12)),
                            )
                          else
                            const Padding(
                              padding: EdgeInsets.only(top: 8.0),
                              child: Text('LUNAS', style: TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                            ),
                        ],
                      )
                    ],
                  ),
                );
              },
            ),
    );
  }
}

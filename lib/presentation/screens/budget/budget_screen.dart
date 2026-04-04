import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:expense_tracker_flutter/utils/formatters.dart';

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _budgets = [];
  bool _isLoading = true;
  DateTime _currentMonth = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadBudgets();
  }

  Future<void> _loadBudgets() async {
    setState(() => _isLoading = true);
    final userId = _supabase.auth.currentUser!.id;
    final monthYear = DateFormat('yyyy-MM').format(_currentMonth);

    try {
      final budgets = await _supabase
          .from('budgets')
          .select('*, categories(*)')
          .eq('user_id', userId)
          .eq('month_year', monthYear);
      
      setState(() {
        _budgets = List<Map<String, dynamic>>.from(budgets);
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showAddBudgetModal() async {
    final categoriesResponse = await _supabase.from('categories').select().or('type.eq.expense,type.eq.both');
    final categories = List<Map<String, dynamic>>.from(categoriesResponse);
    String? selectedCategoryId;
    final limitController = TextEditingController();

    if (!mounted) return;
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
                  const Text('Buat Anggaran Bulanan', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    dropdownColor: const Color(0xFF0F0F1A),
                    value: selectedCategoryId,
                    items: categories.map((c) {
                      return DropdownMenuItem<String>(
                        value: c['id'],
                        child: Text('${c['icon']} ${c['name']}', style: const TextStyle(color: Colors.white)),
                      );
                    }).toList(),
                    onChanged: (val) => setStateModal(() => selectedCategoryId = val),
                    decoration: InputDecoration(
                      labelText: 'Pilih Kategori',
                      labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                      filled: true,
                      fillColor: const Color(0xFF0F0F1A),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: limitController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: false),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      ThousandsSeparatorInputFormatter(),
                    ],
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Batas Anggaran (Rp)',
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
                        if (selectedCategoryId != null && limitController.text.isNotEmpty) {
                          final userId = _supabase.auth.currentUser!.id;
                          final monthYear = DateFormat('yyyy-MM').format(_currentMonth);
                          try {
                            await _supabase.from('budgets').upsert({
                              'user_id': userId,
                              'category_id': selectedCategoryId,
                              'limit_amount': double.tryParse(limitController.text.replaceAll('.', '')) ?? 0,
                              'month_year': monthYear,
                            });
                            if (context.mounted) Navigator.pop(context);
                            _loadBudgets();
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
                      child: const Text('Simpan Anggaran', style: TextStyle(color: Colors.white)),
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

  String _formatCurrency(double amount) {
    return 'Rp ${amount.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        title: const Text('Anggaran (Budget)', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF0F0F1A),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF)))
          : ListView.builder(
              padding: const EdgeInsets.all(24),
              itemCount: _budgets.length + 1,
              itemBuilder: (context, index) {
                if (index == _budgets.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: ElevatedButton.icon(
                      onPressed: _showAddBudgetModal,
                      icon: const Icon(Icons.add, color: Colors.white),
                      label: const Text('Tambah Anggaran', style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1A1A2E),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  );
                }
                final budget = _budgets[index];
                final category = budget['categories'];
                final limit = (budget['limit_amount'] as num).toDouble();
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(category['icon'], style: const TextStyle(fontSize: 20)),
                          const SizedBox(width: 8),
                          Text(category['name'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                          const Spacer(),
                          Text(_formatCurrency(limit), style: const TextStyle(color: Colors.white70)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: 0.5, // Dummy value, should calculate actual usage from transactions
                        backgroundColor: Colors.white.withOpacity(0.1),
                        color: const Color(0xFF6C63FF),
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      const SizedBox(height: 8),
                      Text('50% terpakai dari anggaran', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

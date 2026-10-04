import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:expense_tracker_flutter/data/services/firestore_service.dart';
import 'package:expense_tracker_flutter/utils/formatters.dart';

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  List<Map<String, dynamic>> _budgets = [];
  List<Map<String, dynamic>> _expenseTransactions = [];
  bool _isLoading = true;
  DateTime _currentMonth = DateTime.now();

  final List<Map<String, String>> _categories = [
    {'id': 'cat_food', 'name': 'Makanan', 'icon': '🍔'},
    {'id': 'cat_transport', 'name': 'Transportasi', 'icon': '🚗'},
    {'id': 'cat_shopping', 'name': 'Belanja', 'icon': '🛍️'},
    {'id': 'cat_bills', 'name': 'Tagihan', 'icon': '💡'},
    {'id': 'cat_entertainment', 'name': 'Hiburan', 'icon': '🎬'},
    {'id': 'cat_health', 'name': 'Kesehatan', 'icon': '💊'},
    {'id': 'cat_other_exp', 'name': 'Lainnya', 'icon': '📦'},
  ];

  @override
  void initState() {
    super.initState();
    _loadBudgets();
  }

  Future<void> _loadBudgets() async {
    setState(() => _isLoading = true);
    final userId = FirestoreService.currentUserId;
    if (userId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final monthYear = DateFormat('yyyy-MM').format(_currentMonth);

    try {
      final allBudgets = await FirestoreService.getBudgets(userId);
      final monthBudgets = allBudgets.where((b) => b['month_year'] == monthYear).toList();

      final allT = await FirestoreService.getTransactions(userId);
      final startOfMonth = DateTime(_currentMonth.year, _currentMonth.month, 1);
      final endOfMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 0, 23, 59, 59);

      final expenses = allT.where((t) {
        if (t['type'] != 'expense') return false;
        final rawDate = t['transaction_date'] ?? t['date'];
        if (rawDate == null) return false;
        final d = DateTime.tryParse(rawDate.toString());
        if (d == null) return false;
        return d.isAfter(startOfMonth.subtract(const Duration(seconds: 1))) &&
            d.isBefore(endOfMonth.add(const Duration(seconds: 1)));
      }).toList();

      if (mounted) {
        setState(() {
          _budgets = monthBudgets;
          _expenseTransactions = expenses;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showAddBudgetModal() {
    String selectedCategoryId = _categories.first['id']!;
    final limitController = TextEditingController();

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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
                    items: _categories.map((c) {
                      return DropdownMenuItem<String>(
                        value: c['id'],
                        child: Text('${c['icon']} ${c['name']}', style: const TextStyle(color: Colors.white)),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setStateModal(() => selectedCategoryId = val);
                    },
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
                        if (limitController.text.isNotEmpty) {
                          final userId = FirestoreService.currentUserId;
                          if (userId == null) return;
                          final monthYear = DateFormat('yyyy-MM').format(_currentMonth);
                          final cat = _categories.firstWhere((c) => c['id'] == selectedCategoryId);

                          await FirestoreService.addBudget({
                            'user_id': userId,
                            'category_id': selectedCategoryId,
                            'category_name': cat['name'],
                            'category_icon': cat['icon'],
                            'limit_amount': double.tryParse(limitController.text.replaceAll('.', '')) ?? 0,
                            'month_year': monthYear,
                          });
                          if (context.mounted) Navigator.pop(context);
                          _loadBudgets();
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
          },
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
                final String catName = budget['category_name'] ?? 'Lainnya';
                final String catIcon = budget['category_icon'] ?? '📦';
                final limit = (budget['limit_amount'] as num?)?.toDouble() ?? 0.0;

                double usedAmount = 0;
                for (var t in _expenseTransactions) {
                  if (t['category_id'] == budget['category_id'] || t['category'] == catName) {
                    usedAmount += (t['amount'] as num?)?.toDouble() ?? 0.0;
                  }
                }

                double ratio = limit > 0 ? usedAmount / limit : 0;
                final bool isOverBudget = ratio > 1.0;
                if (ratio > 1.0) ratio = 1.0;

                return Dismissible(
                  key: Key(budget['id'] ?? '$index'),
                  direction: DismissDirection.endToStart,
                  onDismissed: (_) {
                    if (budget['id'] != null) FirestoreService.deleteBudget(budget['id']);
                  },
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(16)),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A2E),
                      borderRadius: BorderRadius.circular(16),
                      border: isOverBudget ? Border.all(color: Colors.redAccent, width: 1.5) : null,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(catIcon, style: const TextStyle(fontSize: 20)),
                            const SizedBox(width: 8),
                            Text(catName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                            const Spacer(),
                            Text(_formatCurrency(limit), style: const TextStyle(color: Colors.white70)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        LinearProgressIndicator(
                          value: ratio,
                          backgroundColor: Colors.white.withOpacity(0.1),
                          color: isOverBudget ? Colors.redAccent : const Color(0xFF6C63FF),
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('${_formatCurrency(usedAmount)} terpakai',
                                style: TextStyle(color: isOverBudget ? Colors.redAccent : Colors.white.withOpacity(0.5), fontSize: 12)),
                            Text('${(ratio * 100).toStringAsFixed(1)}%',
                                style: TextStyle(
                                    color: isOverBudget ? Colors.redAccent : Colors.white.withOpacity(0.5),
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

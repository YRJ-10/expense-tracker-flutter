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
  DateTime _currentMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);

  final List<Map<String, String>> _categories = [
    {'id': 'cat_food', 'name': 'Makanan', 'icon': '🍔'},
    {'id': 'cat_transport', 'name': 'Transportasi', 'icon': '🚗'},
    {'id': 'cat_shopping', 'name': 'Belanja', 'icon': '🛍️'},
    {'id': 'cat_bills', 'name': 'Tagihan', 'icon': '💡'},
    {'id': 'cat_entertainment', 'name': 'Hiburan', 'icon': '🎬'},
    {'id': 'cat_health', 'name': 'Kesehatan', 'icon': '💊'},
    {'id': 'cat_education', 'name': 'Pendidikan', 'icon': '📚'},
    {'id': 'cat_invest', 'name': 'Investasi', 'icon': '📈'},
    {'id': 'cat_other_exp', 'name': 'Lainnya', 'icon': '📦'},
  ];

  static const List<String> _monthNames = [
    'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
    'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
  ];

  @override
  void initState() {
    super.initState();
    _loadBudgets();
  }

  String _getMonthLabel(DateTime date) {
    return '${_monthNames[date.month - 1]} ${date.year}';
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

  void _changeMonth(int delta) {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + delta, 1);
    });
    _loadBudgets();
  }

  void _resetToCurrentMonth() {
    final now = DateTime.now();
    setState(() {
      _currentMonth = DateTime(now.year, now.month, 1);
    });
    _loadBudgets();
  }

  Future<void> _copyFromPreviousMonth() async {
    final userId = FirestoreService.currentUserId;
    if (userId == null) return;

    final prevMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1);
    final prevMonthYear = DateFormat('yyyy-MM').format(prevMonth);
    final currMonthYear = DateFormat('yyyy-MM').format(_currentMonth);

    final allBudgets = await FirestoreService.getBudgets(userId);
    final prevBudgets = allBudgets.where((b) => b['month_year'] == prevMonthYear).toList();

    if (prevBudgets.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Tidak ada anggaran di bulan ${_getMonthLabel(prevMonth)} untuk disalin.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Salin Anggaran Bulan Lalu?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'Ditemukan ${prevBudgets.length} pos anggaran di bulan ${_getMonthLabel(prevMonth)}. Salin ke bulan ${_getMonthLabel(_currentMonth)}?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6C63FF)),
            child: const Text('Salin Sekarang', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    int count = 0;
    for (final b in prevBudgets) {
      // Periksa apakah kategori sudah ada di bulan sekarang
      final alreadyExists = _budgets.any((curr) {
        if (curr['category_id'] == 'cat_other_exp' && b['category_id'] == 'cat_other_exp') {
          final currName = (curr['custom_category_name'] ?? curr['category_name'] ?? '').toString().toLowerCase();
          final bName = (b['custom_category_name'] ?? b['category_name'] ?? '').toString().toLowerCase();
          return currName == bName;
        }
        return curr['category_id'] == b['category_id'];
      });
      if (!alreadyExists) {
        await FirestoreService.addBudget({
          'user_id': userId,
          'category_id': b['category_id'],
          'category_name': b['category_name'],
          'custom_category_name': b['custom_category_name'],
          'category_icon': b['category_icon'],
          'limit_amount': b['limit_amount'],
          'month_year': currMonthYear,
        });
        count++;
      }
    }

    await _loadBudgets();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Berhasil menyalin $count anggaran dari bulan lalu.'),
          backgroundColor: const Color(0xFF00E676),
        ),
      );
    }
  }

  Future<bool> _confirmDeleteBudget(String id, String catName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Hapus Anggaran?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'Apakah Anda yakin ingin menghapus pos anggaran "$catName"?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Hapus', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirestoreService.deleteBudget(id);
      _loadBudgets();
      return true;
    }
    return false;
  }

  void _showAddOrEditBudgetModal({Map<String, dynamic>? existingBudget}) {
    final isEditing = existingBudget != null;
    String selectedCategoryId = existingBudget != null
        ? (existingBudget['category_id'] ?? _categories.first['id']!)
        : _categories.first['id']!;

    final limitController = TextEditingController(
      text: isEditing
          ? ((existingBudget['limit_amount'] as num?)?.toInt().toString().replaceAllMapped(
                RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                (m) => '${m[1]}.',
              ) ?? '')
          : '',
    );

    final customCategoryController = TextEditingController(
      text: isEditing
          ? (existingBudget['custom_category_name'] ??
              (existingBudget['category_name'] != 'Lainnya' &&
                      existingBudget['category_id'] == 'cat_other_exp'
                  ? existingBudget['category_name']
                  : ''))
          : '',
    );

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
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                left: 24,
                right: 24,
                top: 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isEditing ? 'Edit Batas Anggaran' : 'Buat Anggaran Baru',
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        if (isEditing)
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                            onPressed: () async {
                              final deleted = await _confirmDeleteBudget(
                                existingBudget['id'],
                                existingBudget['category_name'] ?? 'Kategori',
                              );
                              if (deleted && context.mounted) {
                                Navigator.pop(context);
                              }
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (!isEditing) ...[
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
                      if (selectedCategoryId == 'cat_other_exp') ...[
                        const SizedBox(height: 14),
                        TextField(
                          controller: customCategoryController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Deskripsi Kategori Lainnya',
                            hintText: 'mis. Hobi, Liburan, Skincare, Renovasi',
                            labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                            hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                            prefixIcon: const Icon(Icons.edit_note, color: Color(0xFF6C63FF)),
                            filled: true,
                            fillColor: const Color(0xFF0F0F1A),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F0F1A),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Text(existingBudget['category_icon'] ?? '📦', style: const TextStyle(fontSize: 20)),
                            const SizedBox(width: 12),
                            Text(
                              existingBudget['category_name'] ?? 'Kategori',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ],
                        ),
                      ),
                      if (existingBudget['category_id'] == 'cat_other_exp') ...[
                        const SizedBox(height: 14),
                        TextField(
                          controller: customCategoryController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Deskripsi Kategori Lainnya',
                            hintText: 'mis. Hobi, Liburan, Skincare, Renovasi',
                            labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                            hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                            prefixIcon: const Icon(Icons.edit_note, color: Color(0xFF6C63FF)),
                            filled: true,
                            fillColor: const Color(0xFF0F0F1A),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                    ],
                    TextField(
                      controller: limitController,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(decimal: false),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        ThousandsSeparatorInputFormatter(),
                      ],
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        labelText: 'Batas Maksimal Anggaran (Rp)',
                        prefixText: 'Rp ',
                        prefixStyle: const TextStyle(color: Color(0xFF6C63FF), fontWeight: FontWeight.bold),
                        labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                        filled: true,
                        fillColor: const Color(0xFF0F0F1A),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Presets
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [500000, 1000000, 2000000, 3000000, 5000000].map((val) {
                          final valStr = val.toString().replaceAllMapped(
                                RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                                (m) => '${m[1]}.',
                              );
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ActionChip(
                              backgroundColor: const Color(0xFF0F0F1A),
                              label: Text('Rp $valStr', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                              onPressed: () {
                                setStateModal(() {
                                  limitController.text = valStr;
                                });
                              },
                            ),
                          );
                        }).toList(),
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
                            final cat = _categories.firstWhere(
                              (c) => c['id'] == selectedCategoryId,
                              orElse: () => _categories.first,
                            );
                            final amount = double.tryParse(limitController.text.replaceAll('.', '')) ?? 0;
                            final isOther = selectedCategoryId == 'cat_other_exp';
                            final customDesc = customCategoryController.text.trim();
                            final finalCatName = (isOther && customDesc.isNotEmpty)
                                ? customDesc
                                : cat['name']!;

                            if (isEditing) {
                              final Map<String, dynamic> updateData = {
                                'limit_amount': amount,
                              };
                              if (existingBudget['category_id'] == 'cat_other_exp') {
                                updateData['category_name'] = finalCatName;
                                updateData['custom_category_name'] = customDesc;
                              }
                              await FirestoreService.updateBudget(existingBudget['id'], updateData);
                            } else {
                              // Check if category already has budget for this month
                              final existing = _budgets.where((b) {
                                if (selectedCategoryId == 'cat_other_exp') {
                                  final existingName = (b['category_name'] ?? '').toString().toLowerCase();
                                  final existingCustom = (b['custom_category_name'] ?? '').toString().toLowerCase();
                                  final target = finalCatName.toLowerCase();
                                  return b['category_id'] == 'cat_other_exp' &&
                                      (existingName == target || existingCustom == target);
                                }
                                return b['category_id'] == selectedCategoryId;
                              }).toList();

                              if (existing.isNotEmpty) {
                                await FirestoreService.updateBudget(existing.first['id'], {
                                  'limit_amount': amount,
                                  'category_name': finalCatName,
                                  'custom_category_name': customDesc,
                                });
                              } else {
                                await FirestoreService.addBudget({
                                  'user_id': userId,
                                  'category_id': selectedCategoryId,
                                  'category_name': finalCatName,
                                  'custom_category_name': customDesc,
                                  'category_icon': cat['icon'],
                                  'limit_amount': amount,
                                  'month_year': monthYear,
                                });
                              }
                            }

                            if (context.mounted) Navigator.pop(context);
                            _loadBudgets();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6C63FF),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(
                          isEditing ? 'Simpan Perubahan' : 'Buat Anggaran',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _formatCurrency(double amount) {
    final isNegative = amount < 0;
    final absAmount = amount.abs();
    final formatted = absAmount.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]}.',
        );
    return isNegative ? '-Rp $formatted' : 'Rp $formatted';
  }

  bool _transactionMatchesBudget(Map<String, dynamic> t, Map<String, dynamic> b) {
    final bCatId = b['category_id']?.toString() ?? '';
    final bCatName = (b['category_name']?.toString() ?? '').toLowerCase();
    final bCustom = (b['custom_category_name']?.toString() ?? '').toLowerCase();

    final tCatId = t['category_id']?.toString() ?? '';
    final tCat = (t['category']?.toString() ?? '').toLowerCase();
    final tNote = (t['note']?.toString() ?? '').toLowerCase();
    final tDesc = (t['description']?.toString() ?? '').toLowerCase();

    // If it's a custom 'Lainnya' budget with a specific name/description (e.g. "Hobi" or "Renovasi")
    if (bCatId == 'cat_other_exp' && (bCustom.isNotEmpty || (bCatName.isNotEmpty && bCatName != 'lainnya'))) {
      final target = bCustom.isNotEmpty ? bCustom : bCatName;
      return tCat == target || tNote == target || tDesc == target ||
             tNote.contains(target) || tDesc.contains(target);
    }

    if (bCatId.isNotEmpty && tCatId.isNotEmpty && bCatId == tCatId) {
      return true;
    }

    return tCat == bCatName;
  }

  Widget _buildOverviewHero({
    required double totalLimit,
    required double totalUsed,
    required double remaining,
    required double totalRatio,
    required bool isThisMonth,
    required bool isPastMonth,
    required int remainingDays,
    required double dailyQuota,
  }) {
    final bool isOver = remaining < 0;
    Color statusColor;
    if (isOver) {
      statusColor = const Color(0xFFFF5252);
    } else if (totalRatio >= 0.75) {
      statusColor = const Color(0xFFFFB020);
    } else {
      statusColor = const Color(0xFF00E676);
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1E1E38),
            isOver ? const Color(0xFF381A22) : const Color(0xFF16162A),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isOver ? Colors.redAccent.withOpacity(0.5) : const Color(0xFF6C63FF).withOpacity(0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (isOver ? Colors.redAccent : const Color(0xFF6C63FF)).withOpacity(0.12),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'RINGKASAN ANGGARAN',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor.withOpacity(0.5)),
                ),
                child: Text(
                  isOver
                      ? 'Overbudget'
                      : totalRatio >= 0.75
                          ? 'Waspada'
                          : 'Aman',
                  style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sisa Kuota Anggaran',
                      style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatCurrency(remaining),
                      style: TextStyle(
                        color: isOver ? const Color(0xFFFF5252) : Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Plafon Total',
                    style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
                  ),
                  Text(
                    _formatCurrency(totalLimit),
                    style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Terpakai: ${_formatCurrency(totalUsed)}',
                    style: TextStyle(
                      color: isOver ? const Color(0xFFFF5252) : Colors.white.withOpacity(0.6),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: totalLimit > 0 ? (totalRatio > 1.0 ? 1.0 : totalRatio) : 0,
              backgroundColor: Colors.white.withOpacity(0.08),
              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 14),
          // Daily Safe-to-Spend Box
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF0F0F1A).withOpacity(0.7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  isOver
                      ? Icons.warning_amber_rounded
                      : isThisMonth
                          ? Icons.savings_outlined
                          : Icons.calendar_today_outlined,
                  color: isOver ? const Color(0xFFFF5252) : const Color(0xFF6C63FF),
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isOver
                            ? 'Batas Anggaran Terlampaui!'
                            : isThisMonth
                                ? 'Batas Belanja Aman Harian'
                                : isPastMonth
                                    ? 'Realisasi Akhir Bulan'
                                    : 'Estimasi Anggaran Harian',
                        style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 11),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isOver
                            ? 'Anda melebihi anggaran sebesar ${_formatCurrency(remaining.abs())}'
                            : isThisMonth
                                ? '${_formatCurrency(dailyQuota)} / hari (sisa $remainingDays hari)'
                                : isPastMonth
                                    ? 'Terpakai ${(totalRatio * 100).toStringAsFixed(1)}% dari plafon'
                                    : '${_formatCurrency(dailyQuota)} / hari untuk bulan ini',
                        style: TextStyle(
                          color: isOver ? const Color(0xFFFF5252) : Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isThisMonth = _currentMonth.year == now.year && _currentMonth.month == now.month;
    final isPastMonth = _currentMonth.year < now.year ||
        (_currentMonth.year == now.year && _currentMonth.month < now.month);

    final daysInMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 0).day;
    final remainingDays = isThisMonth ? (daysInMonth - now.day + 1) : daysInMonth;

    final totalLimit = _budgets.fold<double>(
      0.0,
      (sum, b) => sum + ((b['limit_amount'] as num?)?.toDouble() ?? 0.0),
    );

    double totalUsed = 0.0;
    for (var b in _budgets) {
      for (var t in _expenseTransactions) {
        if (_transactionMatchesBudget(t, b)) {
          totalUsed += (t['amount'] as num?)?.toDouble() ?? 0.0;
        }
      }
    }

    final remaining = totalLimit - totalUsed;
    final totalRatio = totalLimit > 0 ? (totalUsed / totalLimit) : 0.0;
    double dailyQuota = 0.0;
    if (isThisMonth) {
      dailyQuota = remaining > 0 ? (remaining / remainingDays) : 0.0;
    } else if (!isPastMonth) {
      dailyQuota = totalLimit > 0 ? (totalLimit / daysInMonth) : 0.0;
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        title: const Text('Anggaran (Budget)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0F0F1A),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_rounded, color: Colors.white70),
            tooltip: 'Salin dari Bulan Lalu',
            onPressed: _copyFromPreviousMonth,
          ),
          IconButton(
            icon: const Icon(Icons.add, color: Color(0xFF6C63FF)),
            tooltip: 'Tambah Anggaran',
            onPressed: () => _showAddOrEditBudgetModal(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF)))
          : Column(
              children: [
                // Month Selector Bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: const Color(0xFF141426),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left, color: Colors.white),
                        onPressed: () => _changeMonth(-1),
                      ),
                      GestureDetector(
                        onTap: isThisMonth ? null : _resetToCurrentMonth,
                        child: Row(
                          children: [
                            Text(
                              _getMonthLabel(_currentMonth),
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            if (!isThisMonth) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF6C63FF).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text(
                                  'Bulan Ini',
                                  style: TextStyle(color: Color(0xFF6C63FF), fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right, color: Colors.white),
                        onPressed: () => _changeMonth(1),
                      ),
                    ],
                  ),
                ),

                // Main Content
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 32),
                    children: [
                      _buildOverviewHero(
                        totalLimit: totalLimit,
                        totalUsed: totalUsed,
                        remaining: remaining,
                        totalRatio: totalRatio,
                        isThisMonth: isThisMonth,
                        isPastMonth: isPastMonth,
                        remainingDays: remainingDays,
                        dailyQuota: dailyQuota,
                      ),

                      // Section Title
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Pos Kategori (${_budgets.length})',
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            if (_budgets.isEmpty)
                              TextButton.icon(
                                onPressed: _copyFromPreviousMonth,
                                icon: const Icon(Icons.copy, size: 14, color: Color(0xFF6C63FF)),
                                label: const Text('Salin Bulan Lalu', style: TextStyle(color: Color(0xFF6C63FF), fontSize: 13)),
                              ),
                          ],
                        ),
                      ),

                      if (_budgets.isEmpty)
                        Container(
                          margin: const EdgeInsets.all(24),
                          padding: const EdgeInsets.all(28),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1A2E),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withOpacity(0.05)),
                          ),
                          child: Column(
                            children: [
                              const Icon(Icons.account_balance_wallet_outlined, size: 48, color: Colors.white38),
                              const SizedBox(height: 12),
                              Text(
                                'Belum Ada Anggaran untuk ${_getMonthLabel(_currentMonth)}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Buat batas belanja baru atau salin anggaran dari bulan sebelumnya.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
                              ),
                              const SizedBox(height: 20),
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: _copyFromPreviousMonth,
                                    icon: const Icon(Icons.copy, size: 16, color: Colors.white70),
                                    label: const Text('Salin Bulan Lalu', style: TextStyle(color: Colors.white70)),
                                    style: OutlinedButton.styleFrom(
                                      side: BorderSide(color: Colors.white.withOpacity(0.2)),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  ),
                                  ElevatedButton.icon(
                                    onPressed: () => _showAddOrEditBudgetModal(),
                                    icon: const Icon(Icons.add, size: 16, color: Colors.white),
                                    label: const Text('Buat Baru', style: TextStyle(color: Colors.white)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF6C63FF),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        )
                      else
                        ..._budgets.map((budget) {
                          final String catName = budget['category_name'] ?? 'Lainnya';
                          final String catIcon = budget['category_icon'] ?? '📦';
                          final limit = (budget['limit_amount'] as num?)?.toDouble() ?? 0.0;

                          double usedAmount = 0;
                          for (var t in _expenseTransactions) {
                            if (_transactionMatchesBudget(t, budget)) {
                              usedAmount += (t['amount'] as num?)?.toDouble() ?? 0.0;
                            }
                          }

                          final ratio = limit > 0 ? (usedAmount / limit) : 0.0;
                          final bool isOver = usedAmount > limit;
                          final double catRemaining = limit - usedAmount;

                          Color catColor;
                          if (isOver) {
                            catColor = const Color(0xFFFF5252);
                          } else if (ratio >= 0.75) {
                            catColor = const Color(0xFFFFB020);
                          } else {
                            catColor = const Color(0xFF00E676);
                          }

                          return Dismissible(
                            key: Key(budget['id'] ?? catName),
                            direction: DismissDirection.endToStart,
                            confirmDismiss: (_) => _confirmDeleteBudget(budget['id'] ?? '', catName),
                            background: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(16)),
                              child: const Icon(Icons.delete, color: Colors.white),
                            ),
                            child: InkWell(
                              onTap: () => _showAddOrEditBudgetModal(existingBudget: budget),
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1A1A2E),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isOver
                                        ? const Color(0xFFFF5252).withOpacity(0.6)
                                        : Colors.white.withOpacity(0.06),
                                    width: isOver ? 1.5 : 1,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF0F0F1A),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Text(catIcon, style: const TextStyle(fontSize: 22)),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Flexible(
                                                    child: Text(
                                                      catName,
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 16,
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  if (budget['category_id'] == 'cat_other_exp') ...[
                                                    const SizedBox(width: 8),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFF6C63FF).withOpacity(0.18),
                                                        borderRadius: BorderRadius.circular(6),
                                                        border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.35)),
                                                      ),
                                                      child: const Text('Lainnya', style: TextStyle(color: Color(0xFF9C95FF), fontSize: 10, fontWeight: FontWeight.bold)),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'Plafon: ${_formatCurrency(limit)}',
                                                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              isOver
                                                  ? '+${_formatCurrency(usedAmount - limit)}'
                                                  : _formatCurrency(catRemaining),
                                              style: TextStyle(
                                                color: catColor,
                                                fontSize: 15,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            Text(
                                              isOver ? 'Jebol (Over)' : 'Tersisa',
                                              style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 14),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: ratio > 1.0 ? 1.0 : ratio,
                                        backgroundColor: Colors.white.withOpacity(0.08),
                                        valueColor: AlwaysStoppedAnimation<Color>(catColor),
                                        minHeight: 6,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          '${_formatCurrency(usedAmount)} terpakai',
                                          style: TextStyle(
                                            color: isOver ? const Color(0xFFFF5252) : Colors.white.withOpacity(0.5),
                                            fontSize: 12,
                                          ),
                                        ),
                                        Text(
                                          '${(ratio * 100).toStringAsFixed(1)}%',
                                          style: TextStyle(
                                            color: catColor,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),

                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: OutlinedButton.icon(
                          onPressed: () => _showAddOrEditBudgetModal(),
                          icon: const Icon(Icons.add, color: Color(0xFF6C63FF)),
                          label: const Text('Tambah Pos Anggaran Lainnya', style: TextStyle(color: Colors.white)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFF6C63FF)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

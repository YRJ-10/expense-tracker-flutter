import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:expense_tracker_flutter/data/services/firestore_service.dart';
import 'package:expense_tracker_flutter/utils/formatters.dart';

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  List<Map<String, dynamic>> _goals = [];
  List<Map<String, dynamic>> _wallets = [];
  bool _isLoading = true;

  final List<String> _icons = ['🎯', '🏖️', '🚗', '🏠', '💍', '💻', '💰', '🎓', '🏥', '📦'];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final userId = FirestoreService.currentUserId;
    if (userId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      final goals = await FirestoreService.getGoals(userId);
      final wallets = await FirestoreService.getWallets(userId);
      if (mounted) {
        setState(() {
          _goals = goals;
          _wallets = wallets;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
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

  Future<bool> _confirmDeleteGoal(String id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Hapus Target Menabung?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'Apakah Anda yakin ingin menghapus target "$name"?\n\nCatatan: Saldo rekening fisik/bank Anda tidak akan terhapus.',
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
      await FirestoreService.deleteGoal(id);
      _loadData();
      return true;
    }
    return false;
  }

  void _showAddOrEditGoalModal({Map<String, dynamic>? existingGoal}) {
    final isEditing = existingGoal != null;
    final nameController = TextEditingController(text: existingGoal?['name'] ?? '');
    final targetController = TextEditingController(
      text: existingGoal != null
          ? ((existingGoal['target_amount'] as num?)?.toInt().toString().replaceAllMapped(
                RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                (m) => '${m[1]}.',
              ) ?? '')
          : '',
    );

    String selectedIcon = existingGoal?['icon'] ?? '🎯';
    DateTime? selectedDate = existingGoal?['target_date'] != null
        ? DateTime.tryParse(existingGoal!['target_date'].toString())
        : null;

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
                          isEditing ? 'Edit Target Menabung' : 'Buat Target Baru',
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        if (isEditing)
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                            onPressed: () async {
                              final deleted = await _confirmDeleteGoal(
                                existingGoal['id'],
                                existingGoal['name'] ?? 'Target',
                              );
                              if (deleted && context.mounted) {
                                Navigator.pop(context);
                              }
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Icon Picker Row
                    const Text('Pilih Ikon Target:', style: TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 48,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _icons.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, idx) {
                          final icon = _icons[idx];
                          final isSelected = icon == selectedIcon;
                          return GestureDetector(
                            onTap: () => setStateModal(() => selectedIcon = icon),
                            child: Container(
                              width: 48,
                              height: 48,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFF6C63FF).withOpacity(0.3) : const Color(0xFF0F0F1A),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected ? const Color(0xFF6C63FF) : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              child: Text(icon, style: const TextStyle(fontSize: 22)),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Nama Target (Misal: Liburan ke Jepang, DP Rumah)',
                        labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                        filled: true,
                        fillColor: const Color(0xFF0F0F1A),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: targetController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: false),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        ThousandsSeparatorInputFormatter(),
                      ],
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Target Nominal Uang (Rp)',
                        prefixText: 'Rp ',
                        prefixStyle: const TextStyle(color: Color(0xFF6C63FF), fontWeight: FontWeight.bold),
                        labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                        filled: true,
                        fillColor: const Color(0xFF0F0F1A),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Target Date Picker
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate ?? DateTime.now().add(const Duration(days: 180)),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 365 * 15)),
                          builder: (context, child) {
                            return Theme(
                              data: Theme.of(context).copyWith(
                                colorScheme: const ColorScheme.dark(
                                  primary: Color(0xFF6C63FF),
                                  onPrimary: Colors.white,
                                  surface: Color(0xFF1A1A2E),
                                  onSurface: Colors.white,
                                ),
                              ),
                              child: child!,
                            );
                          },
                        );
                        if (picked != null) {
                          setStateModal(() => selectedDate = picked);
                        }
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F0F1A),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.event_outlined, color: Color(0xFF6C63FF), size: 20),
                                const SizedBox(width: 12),
                                Text(
                                  selectedDate != null
                                      ? 'Target Selesai: ${DateFormat('dd MMMM yyyy').format(selectedDate!)}'
                                      : 'Pilih Tenggat Waktu (Opsional)',
                                  style: TextStyle(
                                    color: selectedDate != null ? Colors.white : Colors.white.withOpacity(0.5),
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                            if (selectedDate != null)
                              GestureDetector(
                                onTap: () => setStateModal(() => selectedDate = null),
                                child: const Icon(Icons.close, color: Colors.white38, size: 18),
                              )
                            else
                              const Icon(Icons.chevron_right, color: Colors.white38),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          if (nameController.text.trim().isNotEmpty && targetController.text.isNotEmpty) {
                            final userId = FirestoreService.currentUserId;
                            if (userId == null) return;
                            final targetAmount = double.tryParse(targetController.text.replaceAll('.', '')) ?? 0;

                            final data = {
                              'name': nameController.text.trim(),
                              'target_amount': targetAmount,
                              'icon': selectedIcon,
                              'target_date': selectedDate?.toIso8601String(),
                            };

                            if (isEditing) {
                              await FirestoreService.updateGoal(existingGoal['id'], data);
                            } else {
                              data['user_id'] = userId;
                              data['current_amount'] = 0.0;
                              await FirestoreService.addGoal(data);
                            }

                            if (context.mounted) Navigator.pop(context);
                            _loadData();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6C63FF),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(
                          isEditing ? 'Simpan Perubahan' : 'Mulai Target Menabung',
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

  void _showDepositModal(Map<String, dynamic> goal) {
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    String? selectedWalletId = _wallets.isNotEmpty ? _wallets.first['id'] : null;
    bool deductWallet = true;

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
                      children: [
                        Text(goal['icon'] ?? '🎯', style: const TextStyle(fontSize: 24)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Nabung untuk: ${goal['name']}',
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: amountController,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(decimal: false),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        ThousandsSeparatorInputFormatter(),
                      ],
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        labelText: 'Nominal yang Disetor (Rp)',
                        prefixText: 'Rp ',
                        prefixStyle: const TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold),
                        labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                        filled: true,
                        fillColor: const Color(0xFF0F0F1A),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Presets
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [100000, 500000, 1000000, 2000000, 5000000].map((val) {
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
                                  amountController.text = valStr;
                                });
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Wallet Selector
                    if (_wallets.isNotEmpty) ...[
                      DropdownButtonFormField<String>(
                        dropdownColor: const Color(0xFF0F0F1A),
                        value: selectedWalletId,
                        items: _wallets.map((w) {
                          final bal = (w['balance'] as num?)?.toDouble() ?? 0.0;
                          final isCash = w['type'] == 'cash' || w['bank_name'] == 'CASH';
                          final label = isCash ? '💵 ${w['name']}' : '🏦 ${w['name']}';
                          return DropdownMenuItem<String>(
                            value: w['id'],
                            child: Text(
                              '$label (${_formatCurrency(bal)})',
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setStateModal(() => selectedWalletId = val);
                        },
                        decoration: InputDecoration(
                          labelText: 'Pilih Sumber Dana (Dompet)',
                          labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                          filled: true,
                          fillColor: const Color(0xFF0F0F1A),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    // Switch deduct wallet
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F0F1A),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Potong Saldo Dompet',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                Text(
                                  deductWallet
                                      ? 'Saldo rekening terpilih akan berkurang riil.'
                                      : 'Hanya mencatat tabungan tanpa mengurangi saldo dompet.',
                                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: deductWallet,
                            activeColor: const Color(0xFF00E676),
                            onChanged: (v) => setStateModal(() => deductWallet = v),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: noteController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Catatan (Opsional)',
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
                          if (amountController.text.isNotEmpty) {
                            final userId = FirestoreService.currentUserId;
                            if (userId == null) return;
                            final amount = double.tryParse(amountController.text.replaceAll('.', '')) ?? 0;
                            if (amount <= 0) return;

                            if (deductWallet && selectedWalletId != null) {
                              await FirestoreService.contributeToGoal(
                                goalId: goal['id'],
                                userId: userId,
                                amount: amount,
                                walletId: selectedWalletId!,
                                goalName: goal['name'] ?? 'Target',
                                note: noteController.text.trim().isNotEmpty ? noteController.text.trim() : null,
                              );
                            } else {
                              final current = (goal['current_amount'] as num?)?.toDouble() ?? 0.0;
                              await FirestoreService.updateGoal(goal['id'], {
                                'current_amount': current + amount,
                                'last_contribution_date': DateTime.now().toIso8601String(),
                              });
                            }

                            if (context.mounted) Navigator.pop(context);
                            _loadData();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00E676),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text(
                          'Setor Tabungan',
                          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16),
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

  void _showWithdrawModal(Map<String, dynamic> goal) {
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    String? selectedWalletId = _wallets.isNotEmpty ? _wallets.first['id'] : null;
    final currentAmount = (goal['current_amount'] as num?)?.toDouble() ?? 0.0;

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
                      children: [
                        const Icon(Icons.outbox_rounded, color: Colors.orangeAccent),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Cairkan Tabungan: ${goal['name']}',
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tersedia untuk dicairkan: ${_formatCurrency(currentAmount)}',
                      style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: amountController,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(decimal: false),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        ThousandsSeparatorInputFormatter(),
                      ],
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        labelText: 'Nominal Pencairan (Rp)',
                        prefixText: 'Rp ',
                        prefixStyle: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold),
                        labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                        filled: true,
                        fillColor: const Color(0xFF0F0F1A),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Quick Action: Cairkan Semua
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          amountController.text = currentAmount.toInt().toString().replaceAllMapped(
                                RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                                (m) => '${m[1]}.',
                              );
                        },
                        child: const Text('Cairkan Semua (100%)', style: TextStyle(color: Color(0xFF6C63FF))),
                      ),
                    ),
                    if (_wallets.isNotEmpty) ...[
                      DropdownButtonFormField<String>(
                        dropdownColor: const Color(0xFF0F0F1A),
                        value: selectedWalletId,
                        items: _wallets.map((w) {
                          final bal = (w['balance'] as num?)?.toDouble() ?? 0.0;
                          final isCash = w['type'] == 'cash' || w['bank_name'] == 'CASH';
                          final label = isCash ? '💵 ${w['name']}' : '🏦 ${w['name']}';
                          return DropdownMenuItem<String>(
                            value: w['id'],
                            child: Text(
                              'Masuk ke: $label (${_formatCurrency(bal)})',
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setStateModal(() => selectedWalletId = val);
                        },
                        decoration: InputDecoration(
                          labelText: 'Rekening/Dompet Penerima',
                          labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                          filled: true,
                          fillColor: const Color(0xFF0F0F1A),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextField(
                      controller: noteController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Keperluan Pencairan (Opsional)',
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
                          if (amountController.text.isNotEmpty && selectedWalletId != null) {
                            final userId = FirestoreService.currentUserId;
                            if (userId == null) return;
                            final amount = double.tryParse(amountController.text.replaceAll('.', '')) ?? 0;
                            if (amount <= 0 || amount > currentAmount) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Nominal pencairan tidak valid atau melebihi saldo tabungan.'),
                                  backgroundColor: Colors.redAccent,
                                ),
                              );
                              return;
                            }

                            await FirestoreService.withdrawFromGoal(
                              goalId: goal['id'],
                              userId: userId,
                              amount: amount,
                              walletId: selectedWalletId!,
                              goalName: goal['name'] ?? 'Target',
                              note: noteController.text.trim().isNotEmpty ? noteController.text.trim() : null,
                            );

                            if (context.mounted) Navigator.pop(context);
                            _loadData();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orangeAccent,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text(
                          'Konfirmasi Pencairan',
                          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16),
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

  void _showManualAdjustmentModal(Map<String, dynamic> goal) {
    final currentAmount = (goal['current_amount'] as num?)?.toDouble() ?? 0.0;
    final editController = TextEditingController(
      text: currentAmount.toInt().toString().replaceAllMapped(
            RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
            (m) => '${m[1]}.',
          ),
    );

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            left: 24,
            right: 24,
            top: 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Koreksi Manual Saldo Target',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Ubah angka tabungan secara langsung tanpa memotong atau menambah saldo dompet (sebagai fallback).',
                style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 12),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: editController,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: false),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  ThousandsSeparatorInputFormatter(),
                ],
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  labelText: 'Saldo Terkumpul Saat Ini (Rp)',
                  prefixText: 'Rp ',
                  prefixStyle: const TextStyle(color: Color(0xFF6C63FF), fontWeight: FontWeight.bold),
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
                    if (editController.text.isNotEmpty) {
                      final newAmount = double.tryParse(editController.text.replaceAll('.', '')) ?? 0;
                      await FirestoreService.updateGoal(goal['id'], {
                        'current_amount': newAmount,
                      });
                      if (context.mounted) Navigator.pop(context);
                      _loadData();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C63FF),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Simpan Koreksi', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOverviewHero({
    required double totalTarget,
    required double totalSaved,
    required double totalRemaining,
    required double overallRatio,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E1E38), Color(0xFF121226)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6C63FF).withOpacity(0.12),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'AKUMULASI TARGET',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E676).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF00E676).withOpacity(0.5)),
                ),
                child: Text(
                  '${(overallRatio * 100).toStringAsFixed(1)}% Terkumpul',
                  style: const TextStyle(color: Color(0xFF00E676), fontSize: 11, fontWeight: FontWeight.bold),
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
                      'Total Dana Terkumpul',
                      style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatCurrency(totalSaved),
                      style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Total Target', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11)),
                  Text(
                    _formatCurrency(totalTarget),
                    style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Sisa: ${_formatCurrency(totalRemaining)}',
                    style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: overallRatio > 1.0 ? 1.0 : overallRatio,
              backgroundColor: Colors.white.withOpacity(0.08),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00E676)),
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalTarget = _goals.fold<double>(
      0.0,
      (sum, g) => sum + ((g['target_amount'] as num?)?.toDouble() ?? 0.0),
    );
    final totalSaved = _goals.fold<double>(
      0.0,
      (sum, g) => sum + ((g['current_amount'] as num?)?.toDouble() ?? 0.0),
    );
    final totalRemaining = (totalTarget - totalSaved).clamp(0.0, double.infinity);
    final overallRatio = totalTarget > 0 ? (totalSaved / totalTarget) : 0.0;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        title: const Text('Target Menabung (Goals)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0F0F1A),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Color(0xFF6C63FF)),
            tooltip: 'Tambah Target',
            onPressed: () => _showAddOrEditGoalModal(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF)))
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                _buildOverviewHero(
                  totalTarget: totalTarget,
                  totalSaved: totalSaved,
                  totalRemaining: totalRemaining,
                  overallRatio: overallRatio,
                ),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Daftar Target (${_goals.length})',
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      TextButton.icon(
                        onPressed: () => _showAddOrEditGoalModal(),
                        icon: const Icon(Icons.add_circle_outline, size: 16, color: Color(0xFF6C63FF)),
                        label: const Text('Target Baru', style: TextStyle(color: Color(0xFF6C63FF), fontSize: 13)),
                      ),
                    ],
                  ),
                ),

                if (_goals.isEmpty)
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
                        const Icon(Icons.flag_circle_outlined, size: 48, color: Colors.white38),
                        const SizedBox(height: 12),
                        const Text(
                          'Belum Ada Target Menabung',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tentukan impian finansial Anda (misal: Liburan, DP Rumah, atau Gadget Impian) dan sisihkan dana berkala.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: () => _showAddOrEditGoalModal(),
                          icon: const Icon(Icons.add, size: 18, color: Colors.white),
                          label: const Text('Buat Target Pertama', style: TextStyle(color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6C63FF),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ..._goals.map((goal) {
                    final target = (goal['target_amount'] as num?)?.toDouble() ?? 1.0;
                    final current = (goal['current_amount'] as num?)?.toDouble() ?? 0.0;
                    final remaining = (target - current).clamp(0.0, double.infinity);
                    final percentage = (current / target).clamp(0.0, 1.0);
                    final isCompleted = current >= target;

                    // Deadline & Monthly calculation
                    DateTime? targetDate;
                    if (goal['target_date'] != null) {
                      targetDate = DateTime.tryParse(goal['target_date'].toString());
                    }

                    String deadlineText = '';
                    String monthlyNeedText = '';
                    if (targetDate != null) {
                      final now = DateTime.now();
                      final totalMonthsRemaining = (targetDate.year - now.year) * 12 + targetDate.month - now.month;

                      if (isCompleted) {
                        deadlineText = '🎉 Target Telah Tercapai!';
                      } else if (targetDate.isBefore(now)) {
                        deadlineText = '⚠️ Tenggat Waktu Lewat: ${DateFormat('dd MMM yyyy').format(targetDate)}';
                      } else {
                        deadlineText = 'Tenggat: ${DateFormat('MMM yyyy').format(targetDate)} ($totalMonthsRemaining bln lagi)';
                        final effectiveMonths = totalMonthsRemaining < 1 ? 1 : totalMonthsRemaining;
                        final monthlyNeed = remaining / effectiveMonths;
                        monthlyNeedText = 'Nabung: ${_formatCurrency(monthlyNeed)} / bln';
                      }
                    }

                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A2E),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isCompleted
                              ? const Color(0xFF00E676).withOpacity(0.4)
                              : Colors.white.withOpacity(0.06),
                          width: isCompleted ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F0F1A),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(goal['icon'] ?? '🎯', style: const TextStyle(fontSize: 24)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      goal['name'] ?? '',
                                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                                    if (deadlineText.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        deadlineText,
                                        style: TextStyle(
                                          color: isCompleted
                                              ? const Color(0xFF00E676)
                                              : Colors.white.withOpacity(0.55),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert, color: Colors.white54),
                                color: const Color(0xFF141426),
                                onSelected: (val) {
                                  if (val == 'edit') {
                                    _showAddOrEditGoalModal(existingGoal: goal);
                                  } else if (val == 'adjust') {
                                    _showManualAdjustmentModal(goal);
                                  } else if (val == 'delete') {
                                    if (goal['id'] != null) {
                                      _confirmDeleteGoal(goal['id'], goal['name'] ?? 'Target');
                                    }
                                  }
                                },
                                itemBuilder: (ctx) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Row(
                                      children: [
                                        Icon(Icons.edit, color: Colors.white70, size: 18),
                                        SizedBox(width: 8),
                                        Text('Edit Target', style: TextStyle(color: Colors.white)),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'adjust',
                                    child: Row(
                                      children: [
                                        Icon(Icons.tune, color: Color(0xFF6C63FF), size: 18),
                                        SizedBox(width: 8),
                                        Text('Koreksi Saldo Manual', style: TextStyle(color: Colors.white)),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete, color: Colors.redAccent, size: 18),
                                        SizedBox(width: 8),
                                        Text('Hapus Target', style: TextStyle(color: Colors.redAccent)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          // Amounts Row
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Terkumpul', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11)),
                                  Text(
                                    _formatCurrency(current),
                                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    isCompleted ? 'Target Lunas' : 'Sisa Kekurangan',
                                    style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
                                  ),
                                  Text(
                                    isCompleted ? _formatCurrency(target) : _formatCurrency(remaining),
                                    style: TextStyle(
                                      color: isCompleted ? const Color(0xFF00E676) : Colors.white70,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          // Progress Bar
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: percentage,
                              backgroundColor: Colors.white.withOpacity(0.08),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                isCompleted ? const Color(0xFF00E676) : const Color(0xFF6C63FF),
                              ),
                              minHeight: 8,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${(percentage * 100).toStringAsFixed(1)}% Terkumpul',
                                style: TextStyle(
                                  color: isCompleted ? const Color(0xFF00E676) : Colors.white.withOpacity(0.5),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (monthlyNeedText.isNotEmpty && !isCompleted)
                                Text(
                                  monthlyNeedText,
                                  style: const TextStyle(
                                    color: Color(0xFF6C63FF),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Action Buttons
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: ElevatedButton.icon(
                                  onPressed: () => _showDepositModal(goal),
                                  icon: const Icon(Icons.add_circle_outline, size: 18, color: Colors.black),
                                  label: const Text('Nabung', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF00E676),
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                              ),
                              if (current > 0) ...[
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 2,
                                  child: OutlinedButton.icon(
                                    onPressed: () => _showWithdrawModal(goal),
                                    icon: const Icon(Icons.outbox, size: 16, color: Colors.orangeAccent),
                                    label: const Text('Cairkan', style: TextStyle(color: Colors.orangeAccent, fontSize: 13)),
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(color: Colors.orangeAccent),
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}

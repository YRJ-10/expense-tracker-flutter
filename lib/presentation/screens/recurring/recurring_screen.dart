import 'package:flutter/material.dart';
import 'package:expense_tracker_flutter/data/services/firestore_service.dart';
import 'package:expense_tracker_flutter/utils/formatters.dart';

class RecurringScreen extends StatefulWidget {
  const RecurringScreen({super.key});

  @override
  State<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends State<RecurringScreen> {
  List<Map<String, dynamic>> _recurringList = [];
  List<Map<String, dynamic>> _wallets = [];
  bool _isLoading = true;
  String _filterType = 'all'; // 'all', 'expense', 'income'

  final List<Map<String, dynamic>> _expenseCategories = [
    {'id': 'cat_bills', 'name': 'Tagihan', 'icon': '💡'},
    {'id': 'cat_food', 'name': 'Makanan', 'icon': '🍔'},
    {'id': 'cat_transport', 'name': 'Transportasi', 'icon': '🚗'},
    {'id': 'cat_shopping', 'name': 'Belanja', 'icon': '🛍️'},
    {'id': 'cat_entertainment', 'name': 'Hiburan', 'icon': '🎬'},
    {'id': 'cat_health', 'name': 'Kesehatan', 'icon': '💊'},
    {'id': 'cat_other_exp', 'name': 'Lainnya', 'icon': '📦'},
  ];

  final List<Map<String, dynamic>> _incomeCategories = [
    {'id': 'cat_salary', 'name': 'Gaji', 'icon': '💰'},
    {'id': 'cat_bonus', 'name': 'Bonus', 'icon': '🎁'},
    {'id': 'cat_investment', 'name': 'Investasi', 'icon': '📈'},
    {'id': 'cat_transfer_in', 'name': 'Transfer Masuk', 'icon': '📥'},
    {'id': 'cat_other_inc', 'name': 'Lainnya', 'icon': '📦'},
  ];

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
      // 1. Process any due recurring transactions first
      final executed =
          await FirestoreService.processDueRecurringTransactions(userId);
      if (executed.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Auto-catat: ${executed.length} transaksi rutin berhasil dicatat (${executed.join(', ')})'),
            backgroundColor: const Color(0xFF6C63FF),
            duration: const Duration(seconds: 4),
          ),
        );
      }

      // 2. Fetch recurring transactions & wallets
      final recurring = await FirestoreService.getRecurringTransactions(userId);
      final wallets = await FirestoreService.getWallets(userId);

      if (mounted) {
        setState(() {
          _recurringList = recurring;
          _wallets = wallets;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatCurrency(double amount) {
    return 'Rp ${amount.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';
  }

  String _formatDate(DateTime date) {
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agu',
      'Sep',
      'Okt',
      'Nov',
      'Des'
    ];
    return '${date.day} ${months[date.month]} ${date.year}';
  }

  String _getMonthShort(int month) {
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agu',
      'Sep',
      'Okt',
      'Nov',
      'Des'
    ];
    return months[month];
  }

  String _formatFrequency(Map<String, dynamic> r) {
    final freq = (r['frequency'] ?? 'monthly').toString().toLowerCase();
    switch (freq) {
      case 'daily':
      case 'harian':
        return 'Setiap Hari';
      case 'weekly':
      case 'mingguan':
        final dow = (r['day_of_week'] as num?)?.toInt() ?? 1;
        const days = [
          '',
          'Senin',
          'Selasa',
          'Rabu',
          'Kamis',
          'Jumat',
          'Sabtu',
          'Minggu'
        ];
        final dayName = (dow >= 1 && dow <= 7) ? days[dow] : 'Senin';
        return 'Tiap $dayName';
      case 'yearly':
      case 'tahunan':
        final nextDue =
            DateTime.tryParse(r['next_due_date']?.toString() ?? '');
        if (nextDue != null) {
          return 'Tahunan (${nextDue.day} ${_getMonthShort(nextDue.month)})';
        }
        return 'Tahunan';
      case 'monthly':
      case 'bulanan':
      default:
        final dom = (r['day_of_month'] as num?)?.toInt() ??
            (DateTime.tryParse(r['next_due_date']?.toString() ?? '')?.day ?? 1);
        return 'Tiap tgl $dom';
    }
  }

  Map<String, dynamic> _getDueDateStatus(String? nextDueStr) {
    if (nextDueStr == null) {
      return {
        'text': 'Belum dijadwalkan',
        'color': Colors.white54,
        'isDue': false
      };
    }
    final nextDue = DateTime.tryParse(nextDueStr);
    if (nextDue == null) {
      return {
        'text': 'Belum dijadwalkan',
        'color': Colors.white54,
        'isDue': false
      };
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(nextDue.year, nextDue.month, nextDue.day);
    final diff = target.difference(today).inDays;

    if (diff < 0) {
      return {
        'text': 'Lewat jatuh tempo (${_formatDate(nextDue)})',
        'color': Colors.redAccent,
        'isDue': true,
      };
    } else if (diff == 0) {
      return {
        'text': 'Jatuh tempo Hari Ini!',
        'color': Colors.orangeAccent,
        'isDue': true,
      };
    } else if (diff == 1) {
      return {
        'text': 'Besok (${_formatDate(nextDue)})',
        'color': Colors.amberAccent,
        'isDue': false,
      };
    } else {
      return {
        'text': 'Berikutnya: ${_formatDate(nextDue)} ($diff hari lagi)',
        'color': Colors.cyanAccent,
        'isDue': false,
      };
    }
  }

  String _getWalletName(String? walletId) {
    if (walletId == null || walletId.isEmpty) return 'Dompet Utama';
    final match = _wallets.firstWhere(
      (w) => w['id'] == walletId,
      orElse: () => {},
    );
    return match['name'] ?? match['bank_name'] ?? 'Dompet';
  }

  // ------------------ TOGGLE ACTIVE / PAUSE ------------------
  Future<void> _toggleActive(Map<String, dynamic> r) async {
    final bool current = r['is_active'] ?? true;
    final bool updated = !current;
    final id = r['id'];
    if (id == null) return;

    try {
      await FirestoreService.updateRecurring(id, {'is_active': updated});
      setState(() {
        r['is_active'] = updated;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(updated
                ? 'Jadwal rutin diaktifkan kembali'
                : 'Jadwal rutin dijeda sementara'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {}
  }

  // ------------------ MANUAL EXECUTION ------------------
  Future<void> _executeNow(Map<String, dynamic> r) async {
    final id = r['id'];
    final userId = FirestoreService.currentUserId;
    if (id == null || userId == null) return;

    final name = r['name'] ?? r['title'] ?? 'Transaksi Rutin';
    final double amt = (r['amount'] as num?)?.toDouble() ?? 0.0;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Catat Transaksi Sekarang?',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'Transaksi "$name" sebesar ${_formatCurrency(amt)} akan langsung dicatat ke mutasi dan saldo dompet akan diperbarui.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C63FF),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Ya, Catat Sekarang',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        final success = await FirestoreService.executeRecurringTransaction(
          recurringId: id,
          userId: userId,
          isManualTrigger: true,
        );
        if (success) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    'Berhasil mencatat transaksi "$name" sebesar ${_formatCurrency(amt)}!'),
                backgroundColor: Colors.green,
              ),
            );
          }
          await _loadData();
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal mencatat transaksi: $e')),
          );
        }
      }
    }
  }

  // ------------------ DELETE RECURRING ------------------
  Future<void> _deleteRecurring(String id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hapus Transaksi Rutin?',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'Jadwal rutin "$name" akan dihapus. Transaksi yang sudah tercatat sebelumnya tidak akan hilang.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Hapus', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FirestoreService.deleteRecurring(id);
        _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Jadwal rutin "$name" dihapus')),
          );
        }
      } catch (_) {}
    }
  }

  // ------------------ MODAL TAMBAH / EDIT ------------------
  void _showRecurringForm([Map<String, dynamic>? initialItem]) {
    final isEditing = initialItem != null;
    final nameCtrl = TextEditingController(
        text: initialItem?['name'] ?? initialItem?['title'] ?? '');
    final double initialAmt =
        (initialItem?['amount'] as num?)?.toDouble() ?? 0.0;
    final amountCtrl = TextEditingController(
      text: initialAmt > 0
          ? initialAmt.toStringAsFixed(0).replaceAllMapped(
              RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')
          : '',
    );
    String type = initialItem?['type'] ?? 'expense';
    String frequency = initialItem?['frequency'] ?? 'monthly';
    int dayOfMonth = (initialItem?['day_of_month'] as num?)?.toInt() ?? 25;
    int dayOfWeek = (initialItem?['day_of_week'] as num?)?.toInt() ?? 1;
    DateTime nextDueDate = DateTime.tryParse(
            initialItem?['next_due_date']?.toString() ?? '') ??
        DateTime.now();
    bool autoRecord = initialItem?['auto_record'] ?? true;
    String? selectedWalletId = initialItem?['wallet_id'] ??
        (_wallets.isNotEmpty ? _wallets.first['id'] : null);
    String selectedCategory = initialItem?['category'] ??
        (type == 'expense' ? 'Tagihan' : 'Gaji');
    String selectedCategoryId = initialItem?['category_id'] ??
        (type == 'expense' ? 'cat_bills' : 'cat_salary');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final categories =
                type == 'expense' ? _expenseCategories : _incomeCategories;

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 20,
                right: 20,
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
                          isEditing
                              ? 'Ubah Transaksi Rutin'
                              : 'Tambah Transaksi Rutin',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white54),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Type Selector (Pengeluaran vs Pemasukan)
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setModalState(() {
                                type = 'expense';
                                selectedCategory = 'Tagihan';
                                selectedCategoryId = 'cat_bills';
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: type == 'expense'
                                    ? Colors.redAccent.withOpacity(0.2)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: type == 'expense'
                                      ? Colors.redAccent
                                      : Colors.white24,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  'Pengeluaran',
                                  style: TextStyle(
                                    color: type == 'expense'
                                        ? Colors.redAccent
                                        : Colors.white70,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setModalState(() {
                                type = 'income';
                                selectedCategory = 'Gaji';
                                selectedCategoryId = 'cat_salary';
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: type == 'income'
                                    ? Colors.greenAccent.withOpacity(0.2)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: type == 'income'
                                      ? Colors.greenAccent
                                      : Colors.white24,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  'Pemasukan',
                                  style: TextStyle(
                                    color: type == 'income'
                                        ? Colors.greenAccent
                                        : Colors.white70,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Nama Jadwal
                    TextField(
                      controller: nameCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Nama Transaksi Rutin',
                        hintText: type == 'expense'
                            ? 'mis. WiFi Indihome, Netflix, BPJS'
                            : 'mis. Gaji Bulanan, Dividen',
                        labelStyle: const TextStyle(color: Colors.white70),
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                        prefixIcon: const Icon(Icons.edit_note,
                            color: Color(0xFF6C63FF)),
                        filled: true,
                        fillColor: const Color(0xFF0F0F1A),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Nominal
                    TextField(
                      controller: amountCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [ThousandsSeparatorInputFormatter()],
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        labelText: 'Nominal',
                        prefixText: 'Rp ',
                        prefixStyle: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold),
                        labelStyle: const TextStyle(color: Colors.white70),
                        filled: true,
                        fillColor: const Color(0xFF0F0F1A),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Kategori Dropdown
                    DropdownButtonFormField<String>(
                      initialValue: categories.any((c) => c['id'] == selectedCategoryId)
                          ? selectedCategoryId
                          : categories.first['id'] as String,
                      dropdownColor: const Color(0xFF1A1A2E),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Kategori',
                        labelStyle: const TextStyle(color: Colors.white70),
                        prefixIcon: const Icon(Icons.category,
                            color: Color(0xFF6C63FF)),
                        filled: true,
                        fillColor: const Color(0xFF0F0F1A),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      items: categories.map((c) {
                        return DropdownMenuItem<String>(
                          value: c['id'] as String,
                          child: Text('${c['icon']} ${c['name']}'),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setModalState(() {
                            selectedCategoryId = val;
                            final match = categories.firstWhere(
                                (c) => c['id'] == val,
                                orElse: () => categories.first);
                            selectedCategory = match['name'] as String;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 14),

                    // Dompet Pemotong / Penerima
                    if (_wallets.isNotEmpty)
                      DropdownButtonFormField<String>(
                        initialValue: _wallets.any((w) => w['id'] == selectedWalletId)
                            ? selectedWalletId
                            : _wallets.first['id'] as String,
                        dropdownColor: const Color(0xFF1A1A2E),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: type == 'expense'
                              ? 'Dompet Pemotong Saldo'
                              : 'Dompet Penerima',
                          labelStyle: const TextStyle(color: Colors.white70),
                          prefixIcon: const Icon(Icons.account_balance_wallet,
                              color: Color(0xFF6C63FF)),
                          filled: true,
                          fillColor: const Color(0xFF0F0F1A),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        items: _wallets.map((w) {
                          return DropdownMenuItem<String>(
                            value: w['id'] as String,
                            child: Text(
                                '${w['name'] ?? w['bank_name'] ?? 'Dompet'} (${_formatCurrency((w['balance'] as num?)?.toDouble() ?? 0)})'),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setModalState(() => selectedWalletId = val);
                          }
                        },
                      ),
                    const SizedBox(height: 14),

                    // Siklus Frekuensi
                    DropdownButtonFormField<String>(
                      initialValue: frequency,
                      dropdownColor: const Color(0xFF1A1A2E),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Siklus Perulangan',
                        labelStyle: const TextStyle(color: Colors.white70),
                        prefixIcon: const Icon(Icons.autorenew,
                            color: Color(0xFF6C63FF)),
                        filled: true,
                        fillColor: const Color(0xFF0F0F1A),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: 'monthly', child: Text('Bulanan (Tiap Tanggal Tertentu)')),
                        DropdownMenuItem(
                            value: 'weekly', child: Text('Mingguan (Tiap Hari Tertentu)')),
                        DropdownMenuItem(
                            value: 'daily', child: Text('Harian (Setiap Hari)')),
                        DropdownMenuItem(
                            value: 'yearly', child: Text('Tahunan (Setiap Tahun)')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setModalState(() => frequency = val);
                        }
                      },
                    ),
                    const SizedBox(height: 14),

                    // Opsi Tambahan sesuai Frekuensi
                    if (frequency == 'monthly') ...[
                      Row(
                        children: [
                          const Icon(Icons.calendar_today,
                              color: Color(0xFF6C63FF), size: 20),
                          const SizedBox(width: 12),
                          const Text('Tanggal Eksekusi Bulanan:',
                              style: TextStyle(color: Colors.white70)),
                          const Spacer(),
                          DropdownButton<int>(
                            value: dayOfMonth,
                            dropdownColor: const Color(0xFF1A1A2E),
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                            items: List.generate(31, (i) => i + 1).map((d) {
                              return DropdownMenuItem<int>(
                                value: d,
                                child: Text('Tgl $d'),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setModalState(() {
                                  dayOfMonth = val;
                                  // Update nextDueDate to this day
                                  final now = DateTime.now();
                                  int targetYear = now.year;
                                  int targetMonth = now.month;
                                  if (now.day > val) {
                                    targetMonth++;
                                    if (targetMonth > 12) {
                                      targetMonth = 1;
                                      targetYear++;
                                    }
                                  }
                                  final maxD =
                                      DateTime(targetYear, targetMonth + 1, 0)
                                          .day;
                                  nextDueDate = DateTime(
                                      targetYear,
                                      targetMonth,
                                      val > maxD ? maxD : val);
                                });
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                    ] else if (frequency == 'weekly') ...[
                      Row(
                        children: [
                          const Icon(Icons.view_week,
                              color: Color(0xFF6C63FF), size: 20),
                          const SizedBox(width: 12),
                          const Text('Hari Eksekusi Mingguan:',
                              style: TextStyle(color: Colors.white70)),
                          const Spacer(),
                          DropdownButton<int>(
                            value: dayOfWeek,
                            dropdownColor: const Color(0xFF1A1A2E),
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                            items: const [
                              DropdownMenuItem(value: 1, child: Text('Senin')),
                              DropdownMenuItem(value: 2, child: Text('Selasa')),
                              DropdownMenuItem(value: 3, child: Text('Rabu')),
                              DropdownMenuItem(value: 4, child: Text('Kamis')),
                              DropdownMenuItem(value: 5, child: Text('Jumat')),
                              DropdownMenuItem(value: 6, child: Text('Sabtu')),
                              DropdownMenuItem(value: 7, child: Text('Minggu')),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setModalState(() => dayOfWeek = val);
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                    ],

                    // Tanggal Jatuh Tempo Berikutnya Picker
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: nextDueDate,
                          firstDate: DateTime.now().subtract(const Duration(days: 30)),
                          lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                          builder: (context, child) {
                            return Theme(
                              data: ThemeData.dark().copyWith(
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
                          setModalState(() => nextDueDate = picked);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F0F1A),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.event,
                                    color: Color(0xFF6C63FF), size: 20),
                                const SizedBox(width: 12),
                                Text(
                                  'Jatuh Tempo Pertama: ${_formatDate(nextDueDate)}',
                                  style: const TextStyle(color: Colors.white70),
                                ),
                              ],
                            ),
                            const Icon(Icons.edit,
                                color: Colors.white38, size: 16),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Toggle Auto-Record
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F0F1A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: autoRecord
                              ? Colors.greenAccent.withOpacity(0.3)
                              : Colors.white10,
                        ),
                      ),
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Eksekusi Otomatis (Auto-Record)',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          autoRecord
                              ? 'Sistem otomatis mencatat ke mutasi & memotong saldo saat jatuh tempo tiba.'
                              : 'Hanya beri pengingat. Anda yang klik konfirmasi "Catat Sekarang".',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.5), fontSize: 12),
                        ),
                        value: autoRecord,
                        activeThumbColor: const Color(0xFF6C63FF),
                        onChanged: (val) =>
                            setModalState(() => autoRecord = val),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Save Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          final name = nameCtrl.text.trim();
                          final cleanAmtStr =
                              amountCtrl.text.replaceAll('.', '').trim();
                          final double amt =
                              double.tryParse(cleanAmtStr) ?? 0.0;

                          if (name.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'Harap masukkan nama transaksi rutin')),
                            );
                            return;
                          }
                          if (amt <= 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Nominal harus lebih dari 0')),
                            );
                            return;
                          }

                          final userId = FirestoreService.currentUserId;
                          if (userId == null) return;

                          // Icon lookup
                          final catMatch = categories.firstWhere(
                              (c) => c['id'] == selectedCategoryId,
                              orElse: () => {'icon': '🔄'});
                          final icon = catMatch['icon'] ?? '🔄';

                          final Map<String, dynamic> data = {
                            'user_id': userId,
                            'name': name,
                            'amount': amt,
                            'type': type,
                            'category': selectedCategory,
                            'category_id': selectedCategoryId,
                            'wallet_id': selectedWalletId,
                            'frequency': frequency,
                            'day_of_month': dayOfMonth,
                            'day_of_week': dayOfWeek,
                            'next_due_date': nextDueDate.toIso8601String(),
                            'auto_record': autoRecord,
                            'is_active': initialItem?['is_active'] ?? true,
                            'icon': icon,
                          };

                          Navigator.pop(ctx);
                          setState(() => _isLoading = true);

                          if (isEditing) {
                            await FirestoreService.updateRecurring(
                                initialItem['id'], data);
                          } else {
                            data['start_date'] =
                                DateTime.now().toIso8601String();
                            await FirestoreService.addRecurring(data);
                          }

                          await _loadData();

                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(isEditing
                                    ? 'Transaksi rutin "$name" diperbarui'
                                    : 'Transaksi rutin "$name" berhasil ditambahkan!'),
                                backgroundColor: const Color(0xFF6C63FF),
                              ),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6C63FF),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          isEditing ? 'Simpan Perubahan' : 'Buat Jadwal Rutin',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Filter list
    final filtered = _recurringList.where((r) {
      if (_filterType == 'all') return true;
      return (r['type'] ?? 'expense') == _filterType;
    }).toList();

    // Summary calculation
    double monthlyTotalExpense = 0;
    double monthlyTotalIncome = 0;
    int activeExpenseCount = 0;
    int activeIncomeCount = 0;

    for (var r in _recurringList) {
      if (r['is_active'] == false) continue;
      final double amt = (r['amount'] as num?)?.toDouble() ?? 0.0;
      final type = r['type'] ?? 'expense';
      final freq = (r['frequency'] ?? 'monthly').toString().toLowerCase();

      // Normalize to monthly estimation
      double normalized = amt;
      if (freq == 'daily' || freq == 'harian') {
        normalized = amt * 30;
      } else if (freq == 'weekly' || freq == 'mingguan') {
        normalized = amt * 4.3;
      } else if (freq == 'yearly' || freq == 'tahunan') {
        normalized = amt / 12;
      }

      if (type == 'income') {
        monthlyTotalIncome += normalized;
        activeIncomeCount++;
      } else {
        monthlyTotalExpense += normalized;
        activeExpenseCount++;
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        title: const Text('Transaksi Rutin',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0F0F1A),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: _loadData,
            tooltip: 'Segarkan data',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showRecurringForm(),
        backgroundColor: const Color(0xFF6C63FF),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Tambah Rutin',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF6C63FF)))
          : RefreshIndicator(
              color: const Color(0xFF6C63FF),
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 90),
                children: [
                  // ---------------- RINGKASAN BEBAN BULANAN ----------------
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2A2254), Color(0xFF1A1A2E)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: const Color(0xFF6C63FF).withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6C63FF).withOpacity(0.25),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.repeat,
                                  color: Color(0xFF6C63FF), size: 18),
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'Estimasi Beban Rutin / Bulan',
                              style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: const [
                                      Icon(Icons.arrow_upward,
                                          size: 14, color: Colors.redAccent),
                                      SizedBox(width: 4),
                                      Text('Pengeluaran Tetap',
                                          style: TextStyle(
                                              color: Colors.white60,
                                              fontSize: 11)),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatCurrency(monthlyTotalExpense),
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold),
                                  ),
                                  Text('$activeExpenseCount jadwal aktif',
                                      style: TextStyle(
                                          color: Colors.white.withOpacity(0.4),
                                          fontSize: 11)),
                                ],
                              ),
                            ),
                            Container(
                                width: 1,
                                height: 40,
                                color: Colors.white.withOpacity(0.1)),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(left: 16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: const [
                                        Icon(Icons.arrow_downward,
                                            size: 14,
                                            color: Colors.greenAccent),
                                        SizedBox(width: 4),
                                        Text('Pemasukan Tetap',
                                            style: TextStyle(
                                                color: Colors.white60,
                                                fontSize: 11)),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _formatCurrency(monthlyTotalIncome),
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    Text('$activeIncomeCount jadwal aktif',
                                      style: TextStyle(
                                          color: Colors.white.withOpacity(0.4),
                                          fontSize: 11)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ---------------- FILTER TABS ----------------
                  Row(
                    children: [
                      _buildFilterChip('all', 'Semua (${_recurringList.length})'),
                      const SizedBox(width: 8),
                      _buildFilterChip('expense', 'Pengeluaran'),
                      const SizedBox(width: 8),
                      _buildFilterChip('income', 'Pemasukan'),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ---------------- DAFTAR JADWAL ----------------
                  if (filtered.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 48, horizontal: 24),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A2E),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.autorenew,
                              size: 56, color: Colors.white.withOpacity(0.2)),
                          const SizedBox(height: 16),
                          const Text(
                            'Belum Ada Jadwal Rutin',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tambahkan tagihan WiFi, langganan Netflix, kos, atau gaji bulanan agar keuangan Anda terpantau otomatis.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 13),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            onPressed: () => _showRecurringForm(),
                            icon: const Icon(Icons.add, color: Colors.white),
                            label: const Text('Buat Jadwal Baru',
                                style: TextStyle(color: Colors.white)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6C63FF),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ...filtered.map((r) => _buildRecurringCard(r)),
                ],
              ),
            ),
    );
  }

  Widget _buildFilterChip(String value, String label) {
    final bool isSelected = _filterType == value;
    return GestureDetector(
      onTap: () => setState(() => _filterType = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF6C63FF)
              : const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF6C63FF)
                : Colors.white.withOpacity(0.1),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white70,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildRecurringCard(Map<String, dynamic> r) {
    final bool isIncome = r['type'] == 'income';
    final double amt = (r['amount'] as num?)?.toDouble() ?? 0.0;
    final String name = r['name'] ?? r['title'] ?? 'Rutin';
    final String category = r['category'] ?? (isIncome ? 'Gaji' : 'Tagihan');
    final String walletName = _getWalletName(r['wallet_id']);
    final bool isActive = r['is_active'] ?? true;
    final bool autoRecord = r['auto_record'] ?? true;
    final String nextDueStr = r['next_due_date']?.toString() ?? '';
    final dueStatus = _getDueDateStatus(nextDueStr);
    final String frequencyLabel = _formatFrequency(r);

    return Opacity(
      opacity: isActive ? 1.0 : 0.6,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: dueStatus['isDue'] == true && isActive
                ? Colors.orangeAccent.withOpacity(0.5)
                : Colors.white.withOpacity(0.06),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Icon, Title & Amount
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: (isIncome ? Colors.greenAccent : const Color(0xFF6C63FF))
                        .withOpacity(0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    r['icon'] ?? (isIncome ? '💰' : '💡'),
                    style: const TextStyle(fontSize: 22),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$category • $walletName',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.5), fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatCurrency(amt),
                      style: TextStyle(
                        color: isIncome ? Colors.greenAccent : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      frequencyLabel,
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.4), fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(color: Colors.white10, height: 1),
            const SizedBox(height: 10),

            // Middle Row: Due Date Status Badge & Auto/Manual Mode Badge
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.alarm, size: 14, color: dueStatus['color'] as Color),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          dueStatus['text'] as String,
                          style: TextStyle(
                            color: dueStatus['color'] as Color,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: autoRecord
                        ? Colors.green.withOpacity(0.2)
                        : Colors.blue.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        autoRecord ? Icons.sync : Icons.notifications_none,
                        size: 11,
                        color: autoRecord ? Colors.greenAccent : Colors.lightBlueAccent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        autoRecord ? 'Auto-Record' : 'Pengingat',
                        style: TextStyle(
                          color: autoRecord ? Colors.greenAccent : Colors.lightBlueAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Bottom Action Row: Catat Sekarang button, Active Switch & Menu
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Quick Trigger Button
                ElevatedButton.icon(
                  onPressed: () => _executeNow(r),
                  icon: const Icon(Icons.flash_on, size: 14, color: Colors.white),
                  label: const Text('Catat Sekarang',
                      style: TextStyle(color: Colors.white, fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C63FF),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Active / Pause Switch
                    Transform.scale(
                      scale: 0.8,
                      child: Switch(
                        value: isActive,
                        activeColor: const Color(0xFF6C63FF),
                        onChanged: (_) => _toggleActive(r),
                      ),
                    ),
                    // More options (Edit / Delete)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert,
                          color: Colors.white54, size: 20),
                      color: const Color(0xFF2A2A40),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      onSelected: (val) {
                        if (val == 'edit') {
                          _showRecurringForm(r);
                        } else if (val == 'delete') {
                          _deleteRecurring(r['id'], name);
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit, size: 16, color: Colors.white70),
                              SizedBox(width: 10),
                              Text('Ubah Jadwal',
                                  style: TextStyle(color: Colors.white)),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete,
                                  size: 16, color: Colors.redAccent),
                              SizedBox(width: 10),
                              Text('Hapus',
                                  style: TextStyle(color: Colors.redAccent)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

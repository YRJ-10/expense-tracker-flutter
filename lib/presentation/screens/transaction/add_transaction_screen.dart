import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:expense_tracker_flutter/data/services/firestore_service.dart';
import 'package:expense_tracker_flutter/data/services/receipt_scanner_service.dart';

class _ThousandsSeparatorInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;
    final number = int.tryParse(newValue.text.replaceAll('.', ''));
    if (number == null) return oldValue;
    final formatted = number.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
    return newValue.copyWith(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class AddTransactionScreen extends StatefulWidget {
  const AddTransactionScreen({super.key});

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  final _customCategoryController = TextEditingController();
  String _type = 'expense';
  String? _selectedCategoryId;
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;
  bool _isScanningReceipt = false;

  String? _selectedWalletId;
  List<Map<String, dynamic>> _wallets = [];

  final List<Map<String, dynamic>> _defaultExpenseCategories = [
    {'id': 'cat_food', 'name': 'Makanan', 'icon': '🍔', 'type': 'expense'},
    {'id': 'cat_transport', 'name': 'Transportasi', 'icon': '🚗', 'type': 'expense'},
    {'id': 'cat_shopping', 'name': 'Belanja', 'icon': '🛍️', 'type': 'expense'},
    {'id': 'cat_bills', 'name': 'Tagihan', 'icon': '💡', 'type': 'expense'},
    {'id': 'cat_entertainment', 'name': 'Hiburan', 'icon': '🎬', 'type': 'expense'},
    {'id': 'cat_health', 'name': 'Kesehatan', 'icon': '💊', 'type': 'expense'},
    {'id': 'cat_adj', 'name': 'Penyesuaian Manual', 'icon': '⚖️', 'type': 'expense'},
    {'id': 'cat_other_exp', 'name': 'Lainnya', 'icon': '📦', 'type': 'expense'},
  ];

  final List<Map<String, dynamic>> _defaultIncomeCategories = [
    {'id': 'cat_salary', 'name': 'Gaji', 'icon': '💰', 'type': 'income'},
    {'id': 'cat_bonus', 'name': 'Bonus', 'icon': '🎁', 'type': 'income'},
    {'id': 'cat_investment', 'name': 'Investasi', 'icon': '📈', 'type': 'income'},
    {'id': 'cat_transfer_in', 'name': 'Transfer Masuk', 'icon': '📥', 'type': 'income'},
    {'id': 'cat_adj_inc', 'name': 'Penyesuaian Manual', 'icon': '⚖️', 'type': 'income'},
    {'id': 'cat_other_inc', 'name': 'Lainnya', 'icon': '📦', 'type': 'income'},
  ];

  @override
  void initState() {
    super.initState();
    _selectedCategoryId = _defaultExpenseCategories.first['id'];
    _loadWallets();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    _customCategoryController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _currentCategories {
    return _type == 'expense' ? _defaultExpenseCategories : _defaultIncomeCategories;
  }

  bool get _isOtherCategorySelected {
    final cat = _currentCategories.firstWhere(
      (c) => c['id'] == _selectedCategoryId,
      orElse: () => {},
    );
    return cat['name'] == 'Lainnya';
  }

  Future<void> _loadWallets() async {
    final userId = FirestoreService.currentUserId;
    if (userId == null) return;
    try {
      final wallets = await FirestoreService.getWallets(userId);
      if (mounted) {
        setState(() {
          _wallets = wallets;
          if (_wallets.isNotEmpty) {
            _selectedWalletId = _wallets.first['id'];
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(primary: Color(0xFF6C63FF)),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _saveTransaction() async {
    if (_amountController.text.isEmpty || _selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Isi jumlah dan pilih kategori!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final userId = FirestoreService.currentUserId;
      if (userId == null) return;

      final amount = double.parse(_amountController.text.replaceAll('.', ''));
      final category = _currentCategories.firstWhere(
        (c) => c['id'] == _selectedCategoryId,
        orElse: () => {'name': 'Lainnya'},
      );

      final isOther = category['name'] == 'Lainnya';
      final customName = _customCategoryController.text.trim();
      final categoryName = (isOther && customName.isNotEmpty)
          ? customName
          : (category['name'] as String);

      final dateStr = _selectedDate.toIso8601String().split('T')[0];
      final note = _noteController.text.trim();

      await FirestoreService.addTransaction({
        'user_id': userId,
        'wallet_id': _selectedWalletId,
        'amount': amount,
        'type': _type,
        'category': categoryName,
        'category_id': _selectedCategoryId,
        'note': note,
        'description': note.isNotEmpty ? note : categoryName,
        'date': dateStr,
        'transaction_date': _selectedDate.toIso8601String(),
        'source': 'MANUAL_ENTRY',
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Transaksi berhasil disimpan!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showScanReceiptOptions() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.auto_awesome, color: Color(0xFF6C63FF), size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Scan Struk dengan Gemini AI',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'AI akan membaca nominal, tanggal, nama toko, dan kategori secara otomatis.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
                ),
                const SizedBox(height: 24),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C63FF).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.camera_alt, color: Color(0xFF6C63FF)),
                  ),
                  title: const Text('Foto Struk (Kamera)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: const Text('Ambil foto struk belanja sekarang', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                  onTap: () {
                    Navigator.pop(context);
                    _scanReceipt(true);
                  },
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C63FF).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.photo_library, color: Color(0xFF6C63FF)),
                  ),
                  title: const Text('Pilih dari Galeri', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: const Text('Pilih foto struk atau screenshot', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                  onTap: () {
                    Navigator.pop(context);
                    _scanReceipt(false);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _scanReceipt(bool fromCamera) async {
    setState(() => _isScanningReceipt = true);

    try {
      final result = fromCamera
          ? await ReceiptScannerService.scanFromCamera()
          : await ReceiptScannerService.scanFromGallery();

      if (!mounted) return;

      if (result != null) {
        final amountInt = result.amount.toInt();
        final formattedAmount = NumberFormat.currency(
          locale: 'id_ID',
          symbol: '',
          decimalDigits: 0,
        ).format(amountInt).trim();

        _amountController.text = formattedAmount;
        _type = 'expense';

        final desc = result.itemsSummary.isNotEmpty
            ? '${result.merchant} (${result.itemsSummary})'
            : result.merchant;
        _noteController.text = desc;

        final parsedDate = DateTime.tryParse(result.date);
        if (parsedDate != null) {
          _selectedDate = parsedDate;
        }

        // Cocokkan kategori pengeluaran
        final lower = result.category.toLowerCase();
        bool matched = false;
        for (final cat in _defaultExpenseCategories) {
          final catName = (cat['name'] as String).toLowerCase();
          if (catName != 'lainnya' && (catName.contains(lower) || lower.contains(catName))) {
            _selectedCategoryId = cat['id'];
            _customCategoryController.clear();
            matched = true;
            break;
          }
        }
        if (!matched) {
          _selectedCategoryId = 'cat_other_exp';
          if (result.category.isNotEmpty && lower != 'lainnya') {
            _customCategoryController.text = result.category;
          }
        }

        setState(() {});

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Struk ${result.merchant} (Rp $formattedAmount) berhasil diekstrak AI!'),
                ),
              ],
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal scan struk: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isScanningReceipt = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F1A),
        elevation: 0,
        title: const Text('Tambah Transaksi', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.document_scanner_outlined, color: Color(0xFF6C63FF)),
            tooltip: 'Scan Struk AI',
            onPressed: _isLoading || _isScanningReceipt ? null : _showScanReceiptOptions,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Banner AI Scan Struk
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF6C63FF).withValues(alpha: 0.18),
                    const Color(0xFF1A1A2E),
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFF6C63FF).withValues(alpha: 0.35),
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _isLoading || _isScanningReceipt ? null : _showScanReceiptOptions,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6C63FF).withValues(alpha: 0.25),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.auto_awesome, color: Color(0xFF6C63FF), size: 20),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Scan Struk Otomatis (Gemini AI)',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Foto nota/kuitansi untuk mengisi form otomatis',
                                style: TextStyle(color: Colors.white54, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        if (_isScanningReceipt)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6C63FF)),
                          )
                        else
                          const Icon(Icons.camera_alt_outlined, color: Color(0xFF6C63FF), size: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _type = 'expense';
                          _selectedCategoryId = _defaultExpenseCategories.first['id'];
                          _customCategoryController.clear();
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _type == 'expense' ? const Color(0xFF6C63FF) : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'Pengeluaran',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _type = 'income';
                          _selectedCategoryId = _defaultIncomeCategories.first['id'];
                          _customCategoryController.clear();
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _type == 'income' ? const Color(0xFF6C63FF) : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'Pemasukan',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: false),
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                _ThousandsSeparatorInputFormatter(),
              ],
              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                labelText: 'Jumlah',
                labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                prefixText: 'Rp ',
                prefixStyle: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                filled: true,
                fillColor: const Color(0xFF1A1A2E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 24),

            if (_wallets.isNotEmpty) ...[
              Text(
                _type == 'expense' ? 'Keluarkan dari Dompet / Rekening' : 'Simpan ke Dompet / Rekening',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                dropdownColor: const Color(0xFF0F0F1A),
                value: _selectedWalletId,
                items: _wallets.map((w) {
                  return DropdownMenuItem<String>(
                    value: w['id'],
                    child: Text('${w['icon'] ?? '🏦'} ${w['name']}', style: const TextStyle(color: Colors.white)),
                  );
                }).toList(),
                onChanged: (val) => setState(() => _selectedWalletId = val),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFF1A1A2E),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 24),
            ],

            const Text('Kategori', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              dropdownColor: const Color(0xFF1A1A2E),
              value: _selectedCategoryId,
              icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white70),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.category_outlined, color: Color(0xFF6C63FF)),
                filled: true,
                fillColor: const Color(0xFF1A1A2E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              items: _currentCategories.map((cat) {
                return DropdownMenuItem<String>(
                  value: cat['id'] as String,
                  child: Row(
                    children: [
                      Text(cat['icon'] as String, style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 10),
                      Text(cat['name'] as String, style: const TextStyle(color: Colors.white)),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (val) {
                setState(() {
                  _selectedCategoryId = val;
                  if (!_isOtherCategorySelected) {
                    _customCategoryController.clear();
                  }
                });
              },
            ),
            if (_isOtherCategorySelected) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _customCategoryController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Sebutkan Kategori Lainnya',
                  hintText: 'Misal: Donasi, Hobi, Beli Buku, dll.',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                  labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                  prefixIcon: const Icon(Icons.edit_note, color: Color(0xFF6C63FF)),
                  filled: true,
                  fillColor: const Color(0xFF1A1A2E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: const Color(0xFF6C63FF).withValues(alpha: 0.4)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF6C63FF), width: 1.5),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),

            GestureDetector(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A2E),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today, color: Color(0xFF6C63FF)),
                    const SizedBox(width: 12),
                    Text(
                      '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            TextField(
              controller: _noteController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Catatan / Merchant (opsional)',
                hintText: 'Misal: Shopee, Kopi Kenangan, Transfer',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.2)),
                labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                prefixIcon: const Icon(Icons.note_outlined, color: Color(0xFF6C63FF)),
                filled: true,
                fillColor: const Color(0xFF1A1A2E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _saveTransaction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'Simpan Transaksi',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
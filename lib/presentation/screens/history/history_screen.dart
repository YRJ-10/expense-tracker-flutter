import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:expense_tracker_flutter/data/services/firestore_service.dart';
import 'package:expense_tracker_flutter/utils/export_helper.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _transactions = [];
  bool _isLoading = true;
  String _filterType = 'all';
  DateTime _selectedDate = DateTime(DateTime.now().year, DateTime.now().month, 1);

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    setState(() => _isLoading = true);
    final userId = FirestoreService.currentUserId;
    if (userId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final all = await FirestoreService.getTransactions(userId);
      final startOfMonth = DateTime(_selectedDate.year, _selectedDate.month, 1);
      final endOfMonth = DateTime(_selectedDate.year, _selectedDate.month + 1, 0, 23, 59, 59);

      final filtered = all.where((t) {
        final rawDate = t['transaction_date'] ?? t['date'];
        if (rawDate == null) return false;
        final date = DateTime.tryParse(rawDate.toString());
        if (date == null) return false;
        return date.isAfter(startOfMonth.subtract(const Duration(seconds: 1))) &&
            date.isBefore(endOfMonth.add(const Duration(seconds: 1)));
      }).toList();

      if (mounted) {
        setState(() {
          _transactions = filtered;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredTransactions {
    if (_filterType == 'all') return _transactions;
    return _transactions.where((t) => t['type'] == _filterType).toList();
  }

  String _formatCurrency(double amount) {
    return 'Rp ${amount.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';
  }

  Future<void> _deleteTransaction(String id) async {
    await FirestoreService.deleteTransaction(id);
    _loadTransactions();
  }

  void _showEditTransactionModal(Map<String, dynamic> t) {
    final descController = TextEditingController(text: t['description'] ?? t['note'] ?? '');
    final noteController = TextEditingController(text: t['note'] ?? '');
    String selectedCategory = t['category'] ?? 'Lainnya';
    final double amount = (t['amount'] as num?)?.toDouble() ?? 0.0;
    final bool isIncome = t['type'] == 'income';
    final bool isAutoSynced = t['is_auto_synced'] == true;
    final String? bank = t['bank_name'];

    final List<String> categories = isIncome
        ? ['Gaji', 'Bonus', 'Investasi', 'Transfer Masuk', 'Penyesuaian Manual', 'Lainnya']
        : ['Makanan', 'Transportasi', 'Belanja', 'Tagihan', 'Kartu Kredit / Utang', 'Hiburan', 'Kesehatan', 'Penyesuaian Manual', 'Lainnya'];

    if (!categories.contains(selectedCategory)) {
      categories.insert(0, selectedCategory);
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
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
                        const Text('Detail & Edit Transaksi', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white54),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F0F1A),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                isIncome ? Icons.arrow_downward : Icons.arrow_upward,
                                color: isIncome ? Colors.greenAccent : Colors.redAccent,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                isIncome ? 'Pemasukan' : 'Pengeluaran',
                                style: const TextStyle(color: Colors.white70, fontSize: 13),
                              ),
                              if (isAutoSynced) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF6C63FF).withOpacity(0.25),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    bank ?? 'Mandiri Auto',
                                    style: const TextStyle(color: Color(0xFF9C95FF), fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          Text(
                            '${isIncome ? '+' : '-'}${_formatCurrency(amount)}',
                            style: TextStyle(
                              color: isIncome ? Colors.greenAccent : Colors.redAccent,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: descController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Keterangan / Merchant',
                        labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                        filled: true,
                        fillColor: const Color(0xFF0F0F1A),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text('Kategori', style: TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      dropdownColor: const Color(0xFF0F0F1A),
                      value: selectedCategory,
                      items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(color: Colors.white)))).toList(),
                      onChanged: (val) => setModalState(() => selectedCategory = val ?? selectedCategory),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF0F0F1A),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: noteController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Catatan Tambahan (Opsional)',
                        labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                        filled: true,
                        fillColor: const Color(0xFF0F0F1A),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: () async {
                            Navigator.pop(context);
                            _deleteTransaction(t['id']);
                          },
                          icon: const Icon(Icons.delete, size: 16, color: Colors.redAccent),
                          label: const Text('Hapus', style: TextStyle(color: Colors.redAccent)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.redAccent),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              final newDesc = descController.text.trim();
                              final newNote = noteController.text.trim();
                              await FirestoreService.updateTransaction(t['id'], {
                                'description': newDesc.isNotEmpty ? newDesc : t['description'],
                                'category': selectedCategory,
                                'note': newNote,
                              });
                              if (context.mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Perubahan transaksi disimpan!'), backgroundColor: Colors.green),
                                );
                                _loadTransactions();
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6C63FF),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text('Simpan Perubahan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
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

  void _changeMonth(int increment) {
    setState(() {
      _selectedDate = DateTime(_selectedDate.year, _selectedDate.month + increment, 1);
    });
    _loadTransactions();
  }

  String _getMonthName(DateTime date) {
    const monthNames = ['', 'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'];
    return '${monthNames[date.month]} ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F1A),
        elevation: 0,
        title: const Text('Riwayat Transaksi', style: TextStyle(color: Colors.white)),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.download, color: Colors.white),
            color: const Color(0xFF1A1A2E),
            onSelected: (val) {
              if (val == 'csv') {
                ExportHelper.exportToCSV(_transactions);
              } else if (val == 'pdf') {
                ExportHelper.exportToPDF(_transactions);
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'csv', child: Text('Ekspor ke CSV', style: TextStyle(color: Colors.white))),
              const PopupMenuItem(value: 'pdf', child: Text('Ekspor ke PDF', style: TextStyle(color: Colors.white))),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Month Navigation
          Container(
            color: const Color(0xFF1A1A2E),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, color: Colors.white),
                  onPressed: () => _changeMonth(-1),
                ),
                Text(
                  _getMonthName(_selectedDate),
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, color: Colors.white),
                  onPressed: () => _changeMonth(1),
                ),
              ],
            ),
          ),
          // Filter
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
                            Text('Belum ada transaksi di bulan ini', style: TextStyle(color: Colors.white.withOpacity(0.4))),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadTransactions,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          itemCount: _filteredTransactions.length,
                          itemBuilder: (context, index) {
                            final t = _filteredTransactions[index];
                            final isIncome = t['type'] == 'income';
                            final double amount = (t['amount'] as num?)?.toDouble() ?? 0.0;
                            final String categoryName = t['category'] ?? 'Lainnya';
                            final bool isAutoSynced = t['is_auto_synced'] == true;
                            final bool isRecon = t['is_reconciliation'] == true;
                            final String? bank = t['bank_name'];
                            final String desc = t['description'] ?? t['note'] ?? categoryName;
                            final String rawDate = t['transaction_date'] ?? t['date'] ?? '';
                            final String displayDate = rawDate.isNotEmpty
                                ? DateFormat('dd MMM yyyy, HH:mm').format(DateTime.tryParse(rawDate) ?? DateTime.now())
                                : '';

                            return Dismissible(
                              key: Key(t['id'] ?? '$index'),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.delete, color: Colors.white),
                              ),
                              onDismissed: (_) => _deleteTransaction(t['id']),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () => _showEditTransactionModal(t),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1A1A2E),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: isAutoSynced
                                          ? const Color(0xFF6C63FF).withOpacity(0.3)
                                          : Colors.white.withOpacity(0.05),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: (isIncome ? Colors.green : Colors.red).withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Icon(
                                          isIncome ? Icons.arrow_downward : Icons.arrow_upward,
                                          color: isIncome ? Colors.greenAccent : Colors.redAccent,
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              desc,
                                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
                                            ),
                                            const SizedBox(height: 3),
                                            Row(
                                              children: [
                                                Text(
                                                  categoryName,
                                                  style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12),
                                                ),
                                                if (isAutoSynced) ...[
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFF6C63FF).withOpacity(0.25),
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                      bank ?? 'Auto Sync',
                                                      style: const TextStyle(color: Color(0xFF9C95FF), fontSize: 10, fontWeight: FontWeight.bold),
                                                    ),
                                                  ),
                                                ],
                                                if (isRecon) ...[
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                                    decoration: BoxDecoration(
                                                      color: Colors.blue.withOpacity(0.25),
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: const Text(
                                                      'Rekonsiliasi',
                                                      style: TextStyle(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.bold),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                            if (displayDate.isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(top: 2),
                                                child: Text(
                                                  displayDate,
                                                  style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        '${isIncome ? '+' : '-'}${_formatCurrency(amount)}',
                                        style: TextStyle(
                                          color: isIncome ? Colors.greenAccent : Colors.redAccent,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ],
                                  ),
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
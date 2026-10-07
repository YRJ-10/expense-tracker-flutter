import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:expense_tracker_flutter/data/services/firestore_service.dart';
import 'package:expense_tracker_flutter/utils/export_helper.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  static const int _pageSize = 50;
  List<Map<String, dynamic>> _transactions = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  String _filterType = 'all';
  DateTime _selectedDate =
      DateTime(DateTime.now().year, DateTime.now().month, 1);
  DocumentSnapshot<Map<String, dynamic>>? _lastDocument;
  bool _isSelectionMode = false;
  final Set<String> _selectedTransactionIds = {};

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  Future<void> _loadTransactions({bool loadMore = false}) async {
    if (loadMore && (!_hasMore || _isLoadingMore)) return;

    if (loadMore) {
      setState(() => _isLoadingMore = true);
    } else {
      setState(() {
        _isLoading = true;
        _transactions = [];
        _lastDocument = null;
        _hasMore = false;
        _selectedTransactionIds.clear();
      });
    }

    final userId = FirestoreService.currentUserId;
    if (userId == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
      return;
    }

    try {
      final startOfMonth = DateTime(_selectedDate.year, _selectedDate.month, 1);
      final endOfMonth =
          DateTime(_selectedDate.year, _selectedDate.month + 1, 0, 23, 59, 59);
      final page = await FirestoreService.getTransactionPage(
        userId: userId,
        startDate: startOfMonth,
        endDate: endOfMonth,
        limit: _pageSize,
        startAfter: loadMore ? _lastDocument : null,
      );

      if (mounted) {
        setState(() {
          _transactions =
              loadMore ? [..._transactions, ...page.items] : page.items;
          _lastDocument = page.lastDocument;
          _hasMore = page.hasMore;
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memuat riwayat: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filteredTransactions {
    if (_filterType == 'all') return _transactions;
    return _transactions.where((t) => t['type'] == _filterType).toList();
  }

  String _formatCurrency(double amount) {
    return 'Rp ${amount.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';
  }

  Future<bool> _confirmDeleteTransaction(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Hapus Transaksi?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text(
          'Apakah Anda yakin ingin menghapus transaksi ini?\n\nSaldo dompet terkait akan disesuaikan kembali secara otomatis.',
          style: TextStyle(color: Colors.white70),
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
      await FirestoreService.deleteTransaction(id);
      _loadTransactions();
      return true;
    }
    return false;
  }

  void _showEditTransactionModal(Map<String, dynamic> t) {
    final descController =
        TextEditingController(text: t['description'] ?? t['note'] ?? '');
    final noteController = TextEditingController(text: t['note'] ?? '');
    String selectedCategory = t['category'] ?? 'Lainnya';
    final double amount = (t['amount'] as num?)?.toDouble() ?? 0.0;
    final bool isIncome = t['type'] == 'income';
    final bool isAutoSynced = t['is_auto_synced'] == true;
    final String? bank = t['bank_name'];

    final List<String> categories = isIncome
        ? [
            'Gaji',
            'Bonus',
            'Investasi',
            'Transfer Masuk',
            'Penyesuaian Manual',
            'Lainnya'
          ]
        : [
            'Makanan',
            'Transportasi',
            'Belanja',
            'Tagihan',
            'Kartu Kredit / Utang',
            'Hiburan',
            'Kesehatan',
            'Penyesuaian Manual',
            'Lainnya'
          ];

    if (!categories.contains(selectedCategory)) {
      categories.insert(0, selectedCategory);
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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
                        const Text('Detail & Edit Transaksi',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold)),
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
                                isIncome
                                    ? Icons.arrow_downward
                                    : Icons.arrow_upward,
                                color: isIncome
                                    ? Colors.greenAccent
                                    : Colors.redAccent,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                isIncome ? 'Pemasukan' : 'Pengeluaran',
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 13),
                              ),
                              if (isAutoSynced) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF6C63FF)
                                        .withOpacity(0.25),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    bank ?? 'Mandiri Auto',
                                    style: const TextStyle(
                                        color: Color(0xFF9C95FF),
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          Text(
                            '${isIncome ? '+' : '-'}${_formatCurrency(amount)}',
                            style: TextStyle(
                              color: isIncome
                                  ? Colors.greenAccent
                                  : Colors.redAccent,
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
                        labelStyle:
                            TextStyle(color: Colors.white.withOpacity(0.5)),
                        filled: true,
                        fillColor: const Color(0xFF0F0F1A),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text('Kategori',
                        style: TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      dropdownColor: const Color(0xFF0F0F1A),
                      value: selectedCategory,
                      items: categories
                          .map((c) => DropdownMenuItem(
                              value: c,
                              child: Text(c,
                                  style: const TextStyle(color: Colors.white))))
                          .toList(),
                      onChanged: (val) => setModalState(
                          () => selectedCategory = val ?? selectedCategory),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF0F0F1A),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: noteController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Catatan Tambahan (Opsional)',
                        labelStyle:
                            TextStyle(color: Colors.white.withOpacity(0.5)),
                        filled: true,
                        fillColor: const Color(0xFF0F0F1A),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: () async {
                            final deleted =
                                await _confirmDeleteTransaction(t['id']);
                            if (deleted && context.mounted) {
                              Navigator.pop(context);
                            }
                          },
                          icon: const Icon(Icons.delete,
                              size: 16, color: Colors.redAccent),
                          label: const Text('Hapus',
                              style: TextStyle(color: Colors.redAccent)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.redAccent),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(
                                vertical: 14, horizontal: 16),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              final newDesc = descController.text.trim();
                              final newNote = noteController.text.trim();
                              await FirestoreService.updateTransaction(
                                  t['id'], {
                                'description': newDesc.isNotEmpty
                                    ? newDesc
                                    : t['description'],
                                'category': selectedCategory,
                                'note': newNote,
                              });
                              if (context.mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content:
                                          Text('Perubahan transaksi disimpan!'),
                                      backgroundColor: Colors.green),
                                );
                                _loadTransactions();
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6C63FF),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text('Simpan Perubahan',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
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
      _selectedDate =
          DateTime(_selectedDate.year, _selectedDate.month + increment, 1);
      _lastDocument = null;
      _hasMore = false;
      _selectedTransactionIds.clear();
    });
    _loadTransactions();
  }

  String _getMonthName(DateTime date) {
    const monthNames = [
      '',
      'Januari',
      'Februari',
      'Maret',
      'April',
      'Mei',
      'Juni',
      'Juli',
      'Agustus',
      'September',
      'Oktober',
      'November',
      'Desember'
    ];
    return '${monthNames[date.month]} ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F1A),
        elevation: 0,
        title: _isSelectionMode
            ? Text('${_selectedTransactionIds.length} Dipilih',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold))
            : const Text('Riwayat Transaksi',
                style: TextStyle(color: Colors.white)),
        leading: _isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () {
                  setState(() {
                    _isSelectionMode = false;
                    _selectedTransactionIds.clear();
                  });
                },
              )
            : null,
        actions: [
          if (_isSelectionMode) ...[
            TextButton.icon(
              onPressed: () {
                setState(() {
                  final allIds = _filteredTransactions
                      .map((t) => t['id']?.toString() ?? '')
                      .where((id) => id.isNotEmpty)
                      .toSet();
                  if (_selectedTransactionIds.length == allIds.length &&
                      allIds.isNotEmpty) {
                    _selectedTransactionIds.clear();
                  } else {
                    _selectedTransactionIds.addAll(allIds);
                  }
                });
              },
              icon: Icon(
                _selectedTransactionIds.length == _filteredTransactions.length &&
                        _filteredTransactions.isNotEmpty
                    ? Icons.deselect
                    : Icons.select_all,
                color: const Color(0xFF6C63FF),
                size: 18,
              ),
              label: Text(
                _selectedTransactionIds.length == _filteredTransactions.length &&
                        _filteredTransactions.isNotEmpty
                    ? 'Batal Semua'
                    : 'Pilih Semua',
                style: const TextStyle(
                    color: Color(0xFF6C63FF), fontWeight: FontWeight.bold),
              ),
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.calculate_outlined, color: Colors.white),
              tooltip: 'Kalkulator Seleksi Total',
              onPressed: () {
                setState(() {
                  _isSelectionMode = true;
                });
              },
            ),
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
                const PopupMenuItem(
                    value: 'csv',
                    child: Text('Ekspor ke CSV',
                        style: TextStyle(color: Colors.white))),
                const PopupMenuItem(
                    value: 'pdf',
                    child: Text('Ekspor ke PDF',
                        style: TextStyle(color: Colors.white))),
              ],
            ),
          ],
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
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
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
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF6C63FF)))
                : _filteredTransactions.isEmpty && !_hasMore
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.receipt_long,
                                size: 60, color: Colors.white.withOpacity(0.2)),
                            const SizedBox(height: 16),
                            Text('Belum ada transaksi di bulan ini',
                                style: TextStyle(
                                    color: Colors.white.withOpacity(0.4))),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadTransactions,
                        child: ListView.builder(
                          padding: EdgeInsets.fromLTRB(
                            24,
                            12,
                            24,
                            _isSelectionMode ? 120 : 12,
                          ),
                          itemCount:
                              _filteredTransactions.length + (_hasMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == _filteredTransactions.length) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 20),
                                child: OutlinedButton(
                                  onPressed: _isLoadingMore
                                      ? null
                                      : () => _loadTransactions(loadMore: true),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(
                                        color: Color(0xFF6C63FF)),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14),
                                  ),
                                  child: _isLoadingMore
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Color(0xFF6C63FF)),
                                        )
                                      : const Text('Muat 50 Transaksi Lagi',
                                          style: TextStyle(
                                              color: Color(0xFF6C63FF),
                                              fontWeight: FontWeight.bold)),
                                ),
                              );
                            }

                            final t = _filteredTransactions[index];
                            final String tId =
                                t['id']?.toString() ?? '$index';
                            final bool isSelected =
                                _selectedTransactionIds.contains(tId);
                            final isIncome = t['type'] == 'income';
                            final double amount =
                                (t['amount'] as num?)?.toDouble() ?? 0.0;
                            final String categoryName =
                                t['category'] ?? 'Lainnya';
                            final bool isAutoSynced =
                                t['is_auto_synced'] == true;
                            final bool isRecon = t['is_reconciliation'] == true;
                            final String? bank = t['bank_name'];
                            final String desc =
                                t['description'] ?? t['note'] ?? categoryName;
                            final String rawDate =
                                t['transaction_date'] ?? t['date'] ?? '';
                            final String displayDate = rawDate.isNotEmpty
                                ? DateFormat('dd MMM yyyy, HH:mm').format(
                                    DateTime.tryParse(rawDate) ??
                                        DateTime.now())
                                : '';

                            return Dismissible(
                              key: Key(tId),
                              direction: _isSelectionMode
                                  ? DismissDirection.none
                                  : DismissDirection.endToStart,
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.delete,
                                    color: Colors.white),
                              ),
                              confirmDismiss: (_) =>
                                  _confirmDeleteTransaction(t['id']),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () {
                                  if (_isSelectionMode) {
                                    setState(() {
                                      if (_selectedTransactionIds
                                          .contains(tId)) {
                                        _selectedTransactionIds.remove(tId);
                                      } else {
                                        _selectedTransactionIds.add(tId);
                                      }
                                    });
                                  } else {
                                    _showEditTransactionModal(t);
                                  }
                                },
                                onLongPress: () {
                                  if (!_isSelectionMode) {
                                    setState(() {
                                      _isSelectionMode = true;
                                      _selectedTransactionIds.add(tId);
                                    });
                                  }
                                },
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? const Color(0xFF252445)
                                        : const Color(0xFF1A1A2E),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: isSelected
                                          ? const Color(0xFF6C63FF)
                                          : (isAutoSynced
                                              ? const Color(0xFF6C63FF)
                                                  .withOpacity(0.3)
                                              : Colors.white
                                                  .withOpacity(0.05)),
                                      width: isSelected ? 1.5 : 1.0,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      if (_isSelectionMode) ...[
                                        Container(
                                          margin: const EdgeInsets.only(
                                              right: 12),
                                          width: 22,
                                          height: 22,
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? const Color(0xFF6C63FF)
                                                : Colors.transparent,
                                            borderRadius:
                                                BorderRadius.circular(6),
                                            border: Border.all(
                                              color: isSelected
                                                  ? const Color(0xFF6C63FF)
                                                  : Colors.white38,
                                              width: 1.5,
                                            ),
                                          ),
                                          child: isSelected
                                              ? const Icon(Icons.check,
                                                  size: 16,
                                                  color: Colors.white)
                                              : null,
                                        ),
                                      ],
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: (isIncome
                                                  ? Colors.green
                                                  : Colors.red)
                                              .withOpacity(0.15),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Icon(
                                          isIncome
                                              ? Icons.arrow_downward
                                              : Icons.arrow_upward,
                                          color: isIncome
                                              ? Colors.greenAccent
                                              : Colors.redAccent,
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              desc,
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 15),
                                            ),
                                            const SizedBox(height: 3),
                                            Row(
                                              children: [
                                                Text(
                                                  categoryName,
                                                  style: TextStyle(
                                                      color: Colors.white
                                                          .withOpacity(0.4),
                                                      fontSize: 12),
                                                ),
                                                if (isAutoSynced) ...[
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 6,
                                                        vertical: 1.5),
                                                    decoration: BoxDecoration(
                                                      color: const Color(
                                                              0xFF6C63FF)
                                                          .withOpacity(0.25),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              4),
                                                    ),
                                                    child: Text(
                                                      bank ?? 'Auto Sync',
                                                      style: const TextStyle(
                                                          color:
                                                              Color(0xFF9C95FF),
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.bold),
                                                    ),
                                                  ),
                                                ],
                                                if (isRecon) ...[
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 6,
                                                        vertical: 1.5),
                                                    decoration: BoxDecoration(
                                                      color: Colors.blue
                                                          .withOpacity(0.25),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              4),
                                                    ),
                                                    child: const Text(
                                                      'Rekonsiliasi',
                                                      style: TextStyle(
                                                          color:
                                                              Colors.blueAccent,
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.bold),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                            if (displayDate.isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 2),
                                                child: Text(
                                                  displayDate,
                                                  style: TextStyle(
                                                      color: Colors.white
                                                          .withOpacity(0.3),
                                                      fontSize: 11),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        '${isIncome ? '+' : '-'}${_formatCurrency(amount)}',
                                        style: TextStyle(
                                          color: isIncome
                                              ? Colors.greenAccent
                                              : Colors.redAccent,
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
      bottomNavigationBar: _isSelectionMode ? _buildCalculatorBar() : null,
    );
  }

  Widget _buildCalculatorBar() {
    double totalExpense = 0;
    double totalIncome = 0;
    int expenseCount = 0;
    int incomeCount = 0;

    for (final t in _transactions) {
      final id = t['id']?.toString() ?? '';
      if (_selectedTransactionIds.contains(id)) {
        final amt = (t['amount'] as num?)?.toDouble() ?? 0.0;
        if (t['type'] == 'income') {
          totalIncome += amt;
          incomeCount++;
        } else {
          totalExpense += amt;
          expenseCount++;
        }
      }
    }

    final int totalSelected = _selectedTransactionIds.length;
    final double netTotal = totalIncome - totalExpense;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF16162A),
        border: Border(
          top: BorderSide(
            color: const Color(0xFF6C63FF).withValues(alpha: 0.35),
            width: 1.5,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (totalSelected == 0) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.touch_app_outlined,
                        size: 18, color: Colors.white.withValues(alpha: 0.5)),
                    const SizedBox(width: 8),
                    Text(
                      'Centang transaksi di atas untuk menghitung total',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ] else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$totalSelected Transaksi Dipilih',
                      style: const TextStyle(
                        color: Color(0xFF9D97FF),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        setState(() => _selectedTransactionIds.clear());
                      },
                      child: Text(
                        'Reset Pilihan',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 12,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    // Total Pengeluaran
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 8, horizontal: 10),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.red.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.arrow_upward,
                                    size: 13, color: Colors.redAccent),
                                const SizedBox(width: 4),
                                Text(
                                  'Keluar ($expenseCount)',
                                  style: const TextStyle(
                                    color: Colors.redAccent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                _formatCurrency(totalExpense),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Total Pemasukan
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 8, horizontal: 10),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.green.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.arrow_downward,
                                    size: 13, color: Colors.greenAccent),
                                const SizedBox(width: 4),
                                Text(
                                  'Masuk ($incomeCount)',
                                  style: const TextStyle(
                                    color: Colors.greenAccent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                _formatCurrency(totalIncome),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (expenseCount > 0 && incomeCount > 0) ...[
                      const SizedBox(width: 8),
                      // Selisih Net
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 8, horizontal: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6C63FF)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(0xFF6C63FF)
                                  .withValues(alpha: 0.35),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.balance,
                                      size: 13, color: Color(0xFF9D97FF)),
                                  const SizedBox(width: 4),
                                  const Text(
                                    'Selisih',
                                    style: TextStyle(
                                      color: Color(0xFF9D97FF),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  '${netTotal >= 0 ? '+' : '-'}${_formatCurrency(netTotal.abs())}',
                                  style: TextStyle(
                                    color: netTotal >= 0
                                        ? Colors.greenAccent
                                        : Colors.redAccent,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
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
        child: Text(label,
            style: const TextStyle(color: Colors.white, fontSize: 13)),
      ),
    );
  }
}

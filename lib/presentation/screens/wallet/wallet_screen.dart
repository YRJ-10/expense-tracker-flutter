import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:expense_tracker_flutter/data/services/firestore_service.dart';
import 'package:expense_tracker_flutter/data/services/gmail_sync_service.dart';
import 'package:expense_tracker_flutter/utils/formatters.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  List<Map<String, dynamic>> _wallets = [];
  bool _isLoading = true;
  GmailSyncStatus _syncStatus = GmailSyncStatus(isConnected: false);
  bool _isSyncing = false;

  final List<Map<String, String>> _supportedBanks = [
    {'name': 'Bank Mandiri (Livin\')', 'code': 'MANDIRI', 'icon': '🏦'},
    {'name': 'Kas Fisik / Brankas / Tunai', 'code': 'CASH', 'icon': '💵'},
    {'name': 'Bank Central Asia (BCA)', 'code': 'BCA', 'icon': '🏛️'},
    {'name': 'Bank Rakyat Indonesia (BRI)', 'code': 'BRI', 'icon': '🏢'},
    {'name': 'Bank Jago', 'code': 'JAGO', 'icon': '💳'},
    {'name': 'E-Wallet (GoPay/OVO/ShopeePay)', 'code': 'EWALLET', 'icon': '📱'},
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
      setState(() => _isLoading = false);
      return;
    }

    try {
      final walletsData = await FirestoreService.getWallets(userId);
      final syncStatus = await GmailSyncService.getStatus(userId);

      if (mounted) {
        setState(() {
          _wallets = walletsData;
          _syncStatus = syncStatus;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleConnectGmail() async {
    final userId = FirestoreService.currentUserId;
    if (userId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Silakan login terlebih dahulu.'),
              backgroundColor: Colors.red),
        );
      }
      return;
    }

    final launched = await GmailSyncService.connectGmail(userId);
    if (!mounted) return;

    if (launched) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Halaman otorisasi Google dibuka. Selesaikan di browser lalu kembali ke aplikasi.'),
          backgroundColor: Color(0xFF6C63FF),
        ),
      );
      // Cek status berkala saat user menyelesaikan OAuth
      for (int i = 0; i < 6; i++) {
        await Future.delayed(const Duration(seconds: 3));
        if (!mounted) break;
        final status = await GmailSyncService.getStatus(userId);
        if (status.isConnected) {
          setState(() => _syncStatus = status);
          break;
        }
      }
      _loadData();
    } else {
      final authUrl = '${GmailSyncService.baseUrl}/auth/login?userId=$userId';
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          title: const Text('Otorisasi Gmail',
              style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Browser tidak terbuka otomatis. Silakan salin tautan berikut dan buka di Google Chrome / Browser HP Anda:',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 12),
              SelectableText(
                authUrl,
                style: const TextStyle(color: Color(0xFF6C63FF), fontSize: 13),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: authUrl));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Tautan otorisasi berhasil disalin!')),
                );
              },
              child: const Text('Salin Tautan',
                  style: TextStyle(color: Color(0xFF6C63FF))),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _loadData();
              },
              child:
                  const Text('Tutup', style: TextStyle(color: Colors.white54)),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _handleSyncNow() async {
    final userId = FirestoreService.currentUserId;
    if (userId == null) return;

    setState(() => _isSyncing = true);
    try {
      final result = await GmailSyncService.triggerSync(userId);
      if (!mounted) return;

      if (result.success) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A2E),
            title: const Text('Sinkronisasi Berhasil! 🎉',
                style: TextStyle(color: Colors.white)),
            content: Text(
              'Dipindai: ${result.totalScanned} email bank\n'
              'Transaksi baru ditambahkan: ${result.newTransactionsCount} transaksi.',
              style: const TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _loadData();
                },
                child: const Text('OK',
                    style: TextStyle(color: Color(0xFF6C63FF))),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error ?? 'Gagal sinkronisasi.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
      _loadData();
    }
  }

  void _showAddWalletModal() {
    final nameController = TextEditingController();
    final balanceController = TextEditingController();
    final accNumberController = TextEditingController();
    String selectedBankCode = 'MANDIRI';
    String selectedIcon = '🏦';

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
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
                    const Text('Tambah Rekening / Dompet Baru',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: selectedBankCode,
                      dropdownColor: const Color(0xFF1A1A2E),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Pilih Bank / Sumber Dana',
                        labelStyle:
                            TextStyle(color: Colors.white.withOpacity(0.5)),
                        filled: true,
                        fillColor: const Color(0xFF0F0F1A),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none),
                      ),
                      items: _supportedBanks.map((b) {
                        return DropdownMenuItem(
                          value: b['code'],
                          child: Text('${b['icon']} ${b['name']}'),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setModalState(() {
                            selectedBankCode = val;
                            final bank = _supportedBanks
                                .firstWhere((b) => b['code'] == val);
                            selectedIcon = bank['icon'] ?? '👛';
                            if (nameController.text.isEmpty) {
                              nameController.text = bank['name'] ?? '';
                            }
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Nama Rekening / Label',
                        hintText: selectedBankCode == 'CASH'
                            ? 'Misal: Kas Brankas / Kas Dompet'
                            : 'Misal: Mandiri Tabungan Utama',
                        hintStyle:
                            TextStyle(color: Colors.white.withOpacity(0.2)),
                        labelStyle:
                            TextStyle(color: Colors.white.withOpacity(0.5)),
                        filled: true,
                        fillColor: const Color(0xFF0F0F1A),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: accNumberController,
                      keyboardType: selectedBankCode == 'CASH'
                          ? TextInputType.text
                          : TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: selectedBankCode == 'CASH'
                            ? 'Lokasi / Keterangan (Opsional)'
                            : '4 Digit Terakhir No. Rekening (Opsional)',
                        hintText: selectedBankCode == 'CASH'
                            ? 'Misal: Brankas Kamar Utama'
                            : 'Contoh: 0182 (sesuai email bank)',
                        hintStyle:
                            TextStyle(color: Colors.white.withOpacity(0.2)),
                        labelStyle:
                            TextStyle(color: Colors.white.withOpacity(0.5)),
                        filled: true,
                        fillColor: const Color(0xFF0F0F1A),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: balanceController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: false),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        ThousandsSeparatorInputFormatter(),
                      ],
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: selectedBankCode == 'CASH'
                            ? 'Saldo Awal (Kas Fisik / Brankas)'
                            : 'Saldo Awal (Sesuai M-Banking)',
                        hintText: selectedBankCode == 'CASH'
                            ? 'Contoh: 100.000.000'
                            : 'Contoh: 1.000.000.000',
                        hintStyle:
                            TextStyle(color: Colors.white.withOpacity(0.2)),
                        labelStyle:
                            TextStyle(color: Colors.white.withOpacity(0.5)),
                        filled: true,
                        fillColor: const Color(0xFF0F0F1A),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          final name = nameController.text.trim();
                          if (name.isNotEmpty) {
                            final userId = FirestoreService.currentUserId;
                            if (userId == null) return;

                            final rawBal =
                                balanceController.text.replaceAll('.', '');
                            final initialBal = double.tryParse(rawBal) ?? 0.0;

                            await FirestoreService.addWallet({
                              'user_id': userId,
                              'name': name,
                              'bank_name': selectedBankCode,
                              'account_number': accNumberController.text.trim(),
                              'initial_balance': initialBal,
                              'balance': initialBal,
                              'icon': selectedIcon,
                            });

                            if (context.mounted) Navigator.pop(context);
                            _loadData();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6C63FF),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(
                          selectedBankCode == 'CASH'
                              ? 'Simpan Kas Tunai'
                              : 'Simpan Rekening',
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
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

  void _showReconciliationModal(Map<String, dynamic> wallet) {
    final actualBalanceController = TextEditingController();
    final noteController = TextEditingController();
    final double currentAppBal = (wallet['balance'] as num?)?.toDouble() ?? 0.0;
    final bool isCash =
        (wallet['bank_name'] ?? '').toString().toUpperCase() == 'CASH';

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final rawInput = actualBalanceController.text.replaceAll('.', '');
            final double actualVal = double.tryParse(rawInput) ?? currentAppBal;
            final double diff = actualVal - currentAppBal;

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
                      children: [
                        const Icon(Icons.sync_alt, color: Color(0xFF6C63FF)),
                        const SizedBox(width: 8),
                        Text(
                          isCash
                              ? 'Hitung Kas: ${wallet['name']}'
                              : 'Rekonsiliasi: ${wallet['name']}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isCash
                          ? 'Hitung uang fisik di brankas/dompet Anda dan cocokkan dengan saldo di aplikasi.'
                          : 'Cocokkan saldo aplikasi dengan saldo aktual di m-banking Anda.',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.6), fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F0F1A),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Saldo di Aplikasi Saat Ini:',
                              style: TextStyle(color: Colors.white70)),
                          Text(_formatCurrency(currentAppBal),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: actualBalanceController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: false),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        ThousandsSeparatorInputFormatter(),
                      ],
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: isCash
                            ? 'Saldo Riil di Brankas / Kas'
                            : 'Saldo Aktual di M-Banking',
                        labelStyle:
                            TextStyle(color: Colors.white.withOpacity(0.5)),
                        filled: true,
                        fillColor: const Color(0xFF0F0F1A),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none),
                      ),
                      onChanged: (_) => setModalState(() {}),
                    ),
                    const SizedBox(height: 12),
                    if (actualBalanceController.text.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: diff == 0
                              ? Colors.green.withOpacity(0.15)
                              : (diff > 0
                                  ? Colors.blue.withOpacity(0.15)
                                  : Colors.orange.withOpacity(0.15)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              diff == 0 ? 'Status:' : 'Selisih Penyesuaian:',
                              style: const TextStyle(color: Colors.white70),
                            ),
                            Text(
                              diff == 0
                                  ? 'Sudah Cocok! (Rp 0)'
                                  : '${diff > 0 ? '+' : ''}${_formatCurrency(diff)}',
                              style: TextStyle(
                                color: diff == 0
                                    ? Colors.greenAccent
                                    : (diff > 0
                                        ? Colors.blueAccent
                                        : Colors.orangeAccent),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: noteController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Catatan Penyesuaian (Opsional)',
                        hintText:
                            'Misal: Bunga bank, tarik tunai tanpa email, dsb',
                        hintStyle:
                            TextStyle(color: Colors.white.withOpacity(0.2)),
                        labelStyle:
                            TextStyle(color: Colors.white.withOpacity(0.5)),
                        filled: true,
                        fillColor: const Color(0xFF0F0F1A),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          final userId = FirestoreService.currentUserId;
                          if (userId == null) return;

                          final rawInput =
                              actualBalanceController.text.replaceAll('.', '');
                          final double? actual = double.tryParse(rawInput);
                          if (actual == null) return;

                          final success =
                              await GmailSyncService.reconcileBalance(
                            userId: userId,
                            walletId: wallet['id'],
                            actualBalance: actual,
                            note: noteController.text.trim().isNotEmpty
                                ? noteController.text.trim()
                                : null,
                          );

                          if (context.mounted) {
                            Navigator.pop(context);
                            if (success) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content:
                                        Text('Rekonsiliasi saldo berhasil!'),
                                    backgroundColor: Colors.green),
                              );
                            }
                            _loadData();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6C63FF),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Terapkan Rekonsiliasi',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
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

  Future<void> _confirmDeleteWallet(Map<String, dynamic> wallet) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Hapus Rekening/Dompet?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'Apakah Anda yakin ingin menghapus "${wallet['name']}"?\n\nRiwayat transaksi yang sudah dicatat tidak akan terhapus.',
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

    if (confirm == true && wallet['id'] != null) {
      await FirestoreService.deleteWallet(wallet['id']);
      _loadData();
    }
  }

  String _formatCurrency(double amount) {
    return 'Rp ${amount.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';
  }

  Widget _buildGmailSyncCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _syncStatus.isConnected
              ? [const Color(0xFF1E3A8A), const Color(0xFF1E1B4B)]
              : [const Color(0xFF312E81), const Color(0xFF1E1B4B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.mark_email_read,
                    color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Otomatisasi Bank via Gmail',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _syncStatus.isConnected
                          ? 'Terhubung: ${_syncStatus.email ?? "Gmail Aktif"}'
                          : 'Hubungkan Gmail (Read-Only) untuk auto sync Mandiri',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.7), fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _syncStatus.isConnected
                      ? Colors.green.withOpacity(0.2)
                      : Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: _syncStatus.isConnected
                          ? Colors.greenAccent
                          : Colors.orangeAccent,
                      width: 0.8),
                ),
                child: Text(
                  _syncStatus.isConnected ? 'Aktif' : 'Belum Konek',
                  style: TextStyle(
                    color: _syncStatus.isConnected
                        ? Colors.greenAccent
                        : Colors.orangeAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_syncStatus.isConnected) ...[
            Row(
              children: [
                Icon(Icons.access_time,
                    size: 14, color: Colors.white.withOpacity(0.5)),
                const SizedBox(width: 6),
                Text(
                  _syncStatus.lastSyncedAt != null
                      ? 'Terakhir sync: ${DateFormat('dd MMM HH:mm').format(DateTime.parse(_syncStatus.lastSyncedAt!).toLocal())} WIB'
                      : 'Belum pernah sinkronisasi',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.6), fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSyncing ? null : _handleSyncNow,
                icon: _isSyncing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.sync, color: Colors.white, size: 18),
                label: Text(
                  _isSyncing
                      ? 'Memindai Email Bank...'
                      : 'Sinkronkan Transaksi Sekarang',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _handleConnectGmail,
                icon: const Icon(Icons.login, color: Colors.white, size: 18),
                label: const Text('Koneksikan Akun Gmail',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        title: const Text('Rekening & Dompet',
            style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF0F0F1A),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF6C63FF)))
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  // 1. Gmail Sync Status & Action Card
                  _buildGmailSyncCard(),

                  // 2. Wallets Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text(
                          'Daftar Rekening & Kas Tunai',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: _showAddWalletModal,
                        icon: const Icon(Icons.add,
                            color: Color(0xFF6C63FF), size: 18),
                        label: const Text('Tambah',
                            style: TextStyle(color: Color(0xFF6C63FF))),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  if (_wallets.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A2E),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          const Icon(Icons.account_balance_outlined,
                              color: Colors.white54, size: 48),
                          const SizedBox(height: 12),
                          const Text('Belum ada rekening/dompet',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(
                            'Tambahkan rekening Mandiri Anda untuk mulai auto sync notifikasi transaksi.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 12),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _showAddWalletModal,
                            style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF6C63FF)),
                            child: const Text('Tambah Rekening Sekarang',
                                style: TextStyle(color: Colors.white)),
                          ),
                        ],
                      ),
                    )
                  else
                    ..._wallets.map((wallet) {
                      final double bal =
                          (wallet['balance'] as num?)?.toDouble() ?? 0.0;
                      final String accNum =
                          wallet['account_number']?.toString() ?? '';
                      final String bankName =
                          wallet['bank_name']?.toString() ?? '';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A2E),
                          borderRadius: BorderRadius.circular(18),
                          border:
                              Border.all(color: Colors.white.withOpacity(0.08)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF6C63FF)
                                        .withOpacity(0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(wallet['icon'] ?? '🏦',
                                      style: const TextStyle(fontSize: 22)),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        wallet['name'] ?? 'Rekening',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold),
                                      ),
                                      if (accNum.isNotEmpty)
                                        Text(
                                          'No. Rek: ****$accNum ($bankName)',
                                          style: TextStyle(
                                              color:
                                                  Colors.white.withOpacity(0.5),
                                              fontSize: 12),
                                        )
                                      else if (bankName.toUpperCase() == 'CASH')
                                        Text(
                                          'Kas Fisik / Brankas Tunai',
                                          style: TextStyle(
                                              color:
                                                  Colors.white.withOpacity(0.5),
                                              fontSize: 12),
                                        ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    const Text('Saldo',
                                        style: TextStyle(
                                            color: Colors.white54,
                                            fontSize: 11)),
                                    Text(
                                      _formatCurrency(bal),
                                      style: const TextStyle(
                                          color: Colors.greenAccent,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const Divider(color: Colors.white10, height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    TextButton.icon(
                                      onPressed: () =>
                                          _showReconciliationModal(wallet),
                                      icon: const Icon(Icons.sync_alt,
                                          size: 16, color: Color(0xFF6C63FF)),
                                      label: const Text('Rekonsiliasi',
                                          style: TextStyle(
                                              color: Color(0xFF6C63FF),
                                              fontSize: 13)),
                                    ),
                                    const SizedBox(width: 4),
                                    TextButton.icon(
                                      onPressed: () async {
                                        await Navigator.pushNamed(
                                            context, '/add-transaction');
                                        _loadData();
                                      },
                                      icon: const Icon(Icons.edit_note,
                                          size: 16, color: Colors.white70),
                                      label: const Text('Adjust',
                                          style: TextStyle(
                                              color: Colors.white70,
                                              fontSize: 13)),
                                    ),
                                  ],
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      color: Colors.redAccent, size: 20),
                                  tooltip: 'Hapus Rekening',
                                  onPressed: () => _confirmDeleteWallet(wallet),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:expense_tracker_flutter/data/services/firestore_service.dart';
import 'package:expense_tracker_flutter/data/services/notification_service.dart';
import 'package:expense_tracker_flutter/utils/formatters.dart';

class DebtScreen extends StatefulWidget {
  const DebtScreen({super.key});

  @override
  State<DebtScreen> createState() => _DebtScreenState();
}

class _DebtScreenState extends State<DebtScreen> {
  List<Map<String, dynamic>> _debts = [];
  List<Map<String, dynamic>> _wallets = [];
  bool _isLoading = true;

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
      final debts = await FirestoreService.getDebts(userId);
      final wallets = await FirestoreService.getWallets(userId);
      if (mounted) {
        setState(() {
          _debts = debts;
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

  // ---------------- MODAL TAMBAH UTANG/PIUTANG ----------------
  void _showAddDebtModal() {
    final nameController = TextEditingController();
    final amountController = TextEditingController();
    String type = 'borrowed'; // 'borrowed' (Utang) atau 'lent' (Piutang)
    DateTime? dueDate;
    bool isRecurring = false;
    int recurringDay = 25;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Catat Utang / Piutang Baru',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setStateModal(() => type = 'borrowed'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: type == 'borrowed'
                                    ? Colors.redAccent.withOpacity(0.2)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: type == 'borrowed'
                                        ? Colors.redAccent
                                        : Colors.white24),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.arrow_upward,
                                      size: 16,
                                      color: type == 'borrowed'
                                          ? Colors.redAccent
                                          : Colors.white60),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Utang Saya',
                                    style: TextStyle(
                                      color: type == 'borrowed'
                                          ? Colors.redAccent
                                          : Colors.white60,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setStateModal(() => type = 'lent'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: type == 'lent'
                                    ? Colors.blueAccent.withOpacity(0.2)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: type == 'lent'
                                        ? Colors.blueAccent
                                        : Colors.white24),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.arrow_downward,
                                      size: 16,
                                      color: type == 'lent'
                                          ? Colors.blueAccent
                                          : Colors.white60),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Piutang',
                                    style: TextStyle(
                                      color: type == 'lent'
                                          ? Colors.blueAccent
                                          : Colors.white60,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Nama Pihak / Akun',
                        hintText: type == 'borrowed'
                            ? 'Misal: Kartu Kredit Mandiri / Budi'
                            : 'Misal: Budi Pinjam',
                        hintStyle:
                            TextStyle(color: Colors.white.withOpacity(0.3)),
                        labelStyle:
                            TextStyle(color: Colors.white.withOpacity(0.5)),
                        filled: true,
                        fillColor: const Color(0xFF0F0F1A),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: amountController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: false),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        ThousandsSeparatorInputFormatter(),
                      ],
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        labelText: 'Total Tagihan / Utang Awal',
                        prefixText: 'Rp ',
                        prefixStyle: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold),
                        labelStyle:
                            TextStyle(color: Colors.white.withOpacity(0.5)),
                        filled: true,
                        fillColor: const Color(0xFF0F0F1A),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F0F1A),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          SwitchListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            title: const Text(
                              'Tagihan Rutin Bulanan',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold),
                            ),
                            subtitle: const Text(
                              'Misal: Kartu Kredit / Paylater / Cicilan',
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 11),
                            ),
                            value: isRecurring,
                            activeThumbColor: const Color(0xFF6C63FF),
                            onChanged: (val) =>
                                setStateModal(() => isRecurring = val),
                          ),
                          if (isRecurring) ...[
                            const Divider(color: Colors.white10, height: 1),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Jatuh tempo setiap tgl:',
                                      style: TextStyle(
                                          color: Colors.white70, fontSize: 13),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: DropdownButton<int>(
                                      value: recurringDay,
                                      isExpanded: true,
                                      dropdownColor: const Color(0xFF1A1A2E),
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold),
                                      underline: const SizedBox.shrink(),
                                      items: List.generate(
                                              31, (index) => index + 1)
                                          .map((d) => DropdownMenuItem(
                                                value: d,
                                                child: Text('Tanggal $d',
                                                    overflow:
                                                        TextOverflow.ellipsis),
                                              ))
                                          .toList(),
                                      onChanged: (val) {
                                        if (val != null)
                                          setStateModal(
                                              () => recurringDay = val);
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (!isRecurring) ...[
                      const SizedBox(height: 16),
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: dueDate ??
                                DateTime.now().add(const Duration(days: 30)),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2050),
                            builder: (context, child) => Theme(
                              data: ThemeData.dark().copyWith(
                                colorScheme: const ColorScheme.dark(
                                  primary: Color(0xFF6C63FF),
                                  surface: Color(0xFF1A1A2E),
                                ),
                              ),
                              child: child!,
                            ),
                          );
                          if (picked != null) {
                            setStateModal(() => dueDate = picked);
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
                            children: [
                              const Icon(Icons.event_outlined,
                                  color: Color(0xFF6C63FF), size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Tanggal Jatuh Tempo (Opsional)',
                                      style: TextStyle(
                                          color: Colors.white.withOpacity(0.5),
                                          fontSize: 11),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      dueDate != null
                                          ? DateFormat('dd MMMM yyyy', 'id_ID')
                                              .format(dueDate!)
                                          : 'Belum diatur (Pilih tanggal)',
                                      style: TextStyle(
                                        color: dueDate != null
                                            ? Colors.white
                                            : Colors.white38,
                                        fontSize: 14,
                                        fontWeight: dueDate != null
                                            ? FontWeight.w500
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (dueDate != null)
                                IconButton(
                                  icon: const Icon(Icons.clear,
                                      size: 16, color: Colors.white54),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () =>
                                      setStateModal(() => dueDate = null),
                                )
                              else
                                const Icon(Icons.chevron_right,
                                    color: Colors.white38, size: 20),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          final name = nameController.text.trim();
                          final rawAmt =
                              amountController.text.replaceAll('.', '');
                          final totalAmt = double.tryParse(rawAmt) ?? 0.0;
                          if (name.isNotEmpty && totalAmt > 0) {
                            final userId = FirestoreService.currentUserId;
                            if (userId == null) return;
                            await FirestoreService.addDebt({
                              'user_id': userId,
                              'person_name': name,
                              'amount': totalAmt,
                              'remaining_amount': totalAmt,
                              'paid_amount': 0.0,
                              'type': type,
                              'is_paid': false,
                              'is_recurring': isRecurring,
                              if (isRecurring) 'recurring_day': recurringDay,
                              if (!isRecurring && dueDate != null)
                                'due_date':
                                    dueDate!.toIso8601String().split('T')[0],
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
                        child: const Text('Simpan Data Utang',
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

  // ---------------- MODAL CICIL / BAYAR UTANG ----------------
  void _showPayDebtModal(Map<String, dynamic> debt) {
    final double totalAmt = (debt['amount'] as num?)?.toDouble() ?? 0.0;
    final double remainingAmt =
        (debt['remaining_amount'] as num?)?.toDouble() ??
            (debt['is_paid'] == true ? 0.0 : totalAmt);
    final String personName = debt['person_name'] ?? 'Utang';
    final String debtType = debt['type'] ?? 'borrowed';
    final bool isBorrowed = debtType == 'borrowed';

    final payAmountController = TextEditingController();
    final noteController = TextEditingController();
    String? selectedWalletId =
        _wallets.isNotEmpty ? _wallets.first['id'] : null;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final rawInput = payAmountController.text.replaceAll('.', '');
            final double payVal = double.tryParse(rawInput) ?? 0.0;
            final double sisaSetelahBayar =
                (remainingAmt - payVal).clamp(0.0, double.infinity);

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
                        Icon(
                            isBorrowed
                                ? Icons.payment
                                : Icons.account_balance_wallet,
                            color: const Color(0xFF6C63FF)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isBorrowed
                                ? 'Bayar Cicilan: $personName'
                                : 'Penerimaan Piutang: $personName',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Sisa tagihan saat ini: ${_formatCurrency(remainingAmt)}',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.6), fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: payAmountController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: false),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        ThousandsSeparatorInputFormatter(),
                      ],
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        labelText: 'Nominal yang Dibayar (Rp)',
                        prefixText: 'Rp ',
                        prefixStyle: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold),
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
                    // Quick button bayar lunas
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () {
                          payAmountController.text = remainingAmt
                              .toStringAsFixed(0)
                              .replaceAllMapped(
                                  RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                                  (m) => '${m[1]}.');
                          setModalState(() {});
                        },
                        icon: const Icon(Icons.done_all,
                            size: 16, color: Color(0xFF6C63FF)),
                        label: const Text('Bayar Lunas Sekaligus',
                            style: TextStyle(
                                color: Color(0xFF6C63FF), fontSize: 12)),
                      ),
                    ),
                    if (_wallets.isNotEmpty) ...[
                      const Text('Sumber Rekening / Dompet',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 13)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        dropdownColor: const Color(0xFF0F0F1A),
                        value: selectedWalletId,
                        items: _wallets.map((w) {
                          return DropdownMenuItem<String>(
                            value: w['id'],
                            child: Text('${w['icon'] ?? '🏦'} ${w['name']}',
                                style: const TextStyle(color: Colors.white)),
                          );
                        }).toList(),
                        onChanged: (val) =>
                            setModalState(() => selectedWalletId = val),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xFF0F0F1A),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    TextField(
                      controller: noteController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Catatan (Opsional)',
                        hintText: 'Misal: Cicilan ke-1 lewat Livin / Kas',
                        hintStyle:
                            TextStyle(color: Colors.white.withOpacity(0.3)),
                        labelStyle:
                            TextStyle(color: Colors.white.withOpacity(0.5)),
                        filled: true,
                        fillColor: const Color(0xFF0F0F1A),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (payVal > 0) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F0F1A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Sisa Tagihan Nanti:',
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 13)),
                            Text(
                              _formatCurrency(sisaSetelahBayar),
                              style: TextStyle(
                                color: sisaSetelahBayar == 0
                                    ? Colors.greenAccent
                                    : Colors.orangeAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          if (payVal <= 0) return;
                          final userId = FirestoreService.currentUserId;
                          if (userId == null) return;

                          await FirestoreService.payDebt(
                            debtId: debt['id'],
                            userId: userId,
                            paymentAmount: payVal,
                            walletId: selectedWalletId,
                            personName: personName,
                            debtType: debtType,
                            note: noteController.text.trim().isNotEmpty
                                ? noteController.text.trim()
                                : null,
                          );

                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    'Pembayaran ${_formatCurrency(payVal)} berhasil dicatat!'),
                                backgroundColor: Colors.green,
                              ),
                            );
                            _loadData();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6C63FF),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Konfirmasi Pembayaran',
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

  // ---------------- MODAL EDIT / PENYESUAIAN UTANG (FALLBACK PELAPIS) ----------------
  void _showEditDebtModal(Map<String, dynamic> debt) {
    final double totalAmt = (debt['amount'] as num?)?.toDouble() ?? 0.0;
    final double remainingAmt =
        (debt['remaining_amount'] as num?)?.toDouble() ??
            (debt['is_paid'] == true ? 0.0 : totalAmt);

    final nameController =
        TextEditingController(text: debt['person_name'] ?? '');
    final remainingController = TextEditingController(
      text: remainingAmt.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.'),
    );
    final totalController = TextEditingController(
      text: totalAmt.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.'),
    );
    bool isPaid = debt['is_paid'] == true || remainingAmt <= 0;
    bool isRecurring = debt['is_recurring'] == true;
    int recurringDay = (debt['recurring_day'] as num?)?.toInt() ?? 25;
    DateTime? editDueDate = debt['due_date'] != null
        ? DateTime.tryParse(debt['due_date'].toString())
        : null;

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
                      children: const [
                        Icon(Icons.tune, color: Color(0xFF6C63FF)),
                        SizedBox(width: 8),
                        Text(
                          'Penyesuaian Manual (Fallback)',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Koreksi langsung angka utang jika terjadi ketidaksesuaian tanpa memotong saldo rekening.',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.6), fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Nama Pihak / Akun',
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
                    TextField(
                      controller: remainingController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: false),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        ThousandsSeparatorInputFormatter(),
                      ],
                      style: const TextStyle(
                          color: Colors.orangeAccent,
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        labelText: 'Sisa Utang Riil Saat Ini (Rp)',
                        prefixText: 'Rp ',
                        prefixStyle: const TextStyle(
                            color: Colors.orangeAccent,
                            fontSize: 18,
                            fontWeight: FontWeight.bold),
                        labelStyle:
                            TextStyle(color: Colors.white.withOpacity(0.5)),
                        filled: true,
                        fillColor: const Color(0xFF0F0F1A),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none),
                      ),
                      onChanged: (val) {
                        final parsed =
                            double.tryParse(val.replaceAll('.', '')) ?? 0.0;
                        setModalState(() {
                          isPaid = parsed <= 0;
                        });
                      },
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: totalController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: false),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        ThousandsSeparatorInputFormatter(),
                      ],
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Total Plafon / Utang Awal (Rp)',
                        prefixText: 'Rp ',
                        prefixStyle: const TextStyle(color: Colors.white),
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
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F0F1A),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          SwitchListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            title: const Text(
                              'Tagihan Rutin Bulanan',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold),
                            ),
                            subtitle: const Text(
                              'Misal: Kartu Kredit / Paylater / Cicilan',
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 11),
                            ),
                            value: isRecurring,
                            activeThumbColor: const Color(0xFF6C63FF),
                            onChanged: (val) =>
                                setModalState(() => isRecurring = val),
                          ),
                          if (isRecurring) ...[
                            const Divider(color: Colors.white10, height: 1),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Jatuh tempo setiap tgl:',
                                      style: TextStyle(
                                          color: Colors.white70, fontSize: 13),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: DropdownButton<int>(
                                      value: recurringDay,
                                      isExpanded: true,
                                      dropdownColor: const Color(0xFF1A1A2E),
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold),
                                      underline: const SizedBox.shrink(),
                                      items: List.generate(
                                              31, (index) => index + 1)
                                          .map((d) => DropdownMenuItem(
                                                value: d,
                                                child: Text('Tanggal $d',
                                                    overflow:
                                                        TextOverflow.ellipsis),
                                              ))
                                          .toList(),
                                      onChanged: (val) {
                                        if (val != null)
                                          setModalState(
                                              () => recurringDay = val);
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (!isRecurring) ...[
                      const SizedBox(height: 14),
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: editDueDate ??
                                DateTime.now().add(const Duration(days: 30)),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2050),
                            builder: (context, child) => Theme(
                              data: ThemeData.dark().copyWith(
                                colorScheme: const ColorScheme.dark(
                                  primary: Color(0xFF6C63FF),
                                  surface: Color(0xFF1A1A2E),
                                ),
                              ),
                              child: child!,
                            ),
                          );
                          if (picked != null) {
                            setModalState(() => editDueDate = picked);
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
                            children: [
                              const Icon(Icons.event_outlined,
                                  color: Color(0xFF6C63FF), size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Tanggal Jatuh Tempo',
                                      style: TextStyle(
                                          color: Colors.white.withOpacity(0.5),
                                          fontSize: 11),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      editDueDate != null
                                          ? DateFormat('dd MMMM yyyy', 'id_ID')
                                              .format(editDueDate!)
                                          : 'Belum diatur (Pilih tanggal)',
                                      style: TextStyle(
                                        color: editDueDate != null
                                            ? Colors.white
                                            : Colors.white38,
                                        fontSize: 14,
                                        fontWeight: editDueDate != null
                                            ? FontWeight.w500
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (editDueDate != null)
                                IconButton(
                                  icon: const Icon(Icons.clear,
                                      size: 16, color: Colors.white54),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () =>
                                      setModalState(() => editDueDate = null),
                                )
                              else
                                const Icon(Icons.chevron_right,
                                    color: Colors.white38, size: 20),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Status Lunas',
                          style: TextStyle(color: Colors.white, fontSize: 14)),
                      value: isPaid,
                      activeThumbColor: Colors.greenAccent,
                      onChanged: (val) {
                        setModalState(() {
                          isPaid = val;
                          if (val) remainingController.text = '0';
                        });
                      },
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          final newName = nameController.text.trim();
                          final newRem = double.tryParse(remainingController
                                  .text
                                  .replaceAll('.', '')) ??
                              0.0;
                          final newTot = double.tryParse(
                                  totalController.text.replaceAll('.', '')) ??
                              totalAmt;
                          final newPaid =
                              (newTot - newRem).clamp(0.0, double.infinity);

                          await FirestoreService.updateDebt(debt['id'], {
                            'person_name': newName.isNotEmpty
                                ? newName
                                : debt['person_name'],
                            'amount': newTot,
                            'remaining_amount': newRem,
                            'paid_amount': newPaid,
                            'is_paid': isPaid || newRem <= 0,
                            'is_recurring': isRecurring,
                            'recurring_day': isRecurring ? recurringDay : null,
                            'due_date': !isRecurring && editDueDate != null
                                ? editDueDate!.toIso8601String().split('T')[0]
                                : null,
                            'updated_at': DateTime.now().toIso8601String(),
                          });

                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'Penyesuaian utang berhasil disimpan!'),
                                  backgroundColor: Colors.green),
                            );
                            _loadData();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6C63FF),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Simpan Penyesuaian',
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

  Future<bool> _confirmDeleteDebt(Map<String, dynamic> debt) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Hapus Catatan?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'Apakah Anda yakin ingin menghapus catatan utang/piutang "${debt['person_name']}"?',
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

    if (confirm == true && debt['id'] != null) {
      await FirestoreService.deleteDebt(debt['id']);
      _loadData();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // Hitung total akumulasi utang dan piutang
    double totalBorrowedRemaining = 0;
    double totalLentRemaining = 0;

    for (var d in _debts) {
      final double total = (d['amount'] as num?)?.toDouble() ?? 0.0;
      final double rem = (d['remaining_amount'] as num?)?.toDouble() ??
          (d['is_paid'] == true ? 0.0 : total);
      if (d['is_paid'] != true && rem > 0) {
        if (d['type'] == 'borrowed') {
          totalBorrowedRemaining += rem;
        } else {
          totalLentRemaining += rem;
        }
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        title: const Text('Utang & Piutang',
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
                  // 1. Ringkasan Utang & Piutang
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1A2E),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: Colors.redAccent.withOpacity(0.2)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.arrow_upward,
                                      size: 14, color: Colors.redAccent),
                                  const SizedBox(width: 4),
                                  Text('Total Utang Saya',
                                      style: TextStyle(
                                          color: Colors.white.withOpacity(0.7),
                                          fontSize: 11)),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _formatCurrency(totalBorrowedRemaining),
                                style: const TextStyle(
                                    color: Colors.redAccent,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1A2E),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: Colors.blueAccent.withOpacity(0.2)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.arrow_downward,
                                      size: 14, color: Colors.blueAccent),
                                  const SizedBox(width: 4),
                                  Text('Total Piutang Saya',
                                      style: TextStyle(
                                          color: Colors.white.withOpacity(0.7),
                                          fontSize: 11)),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _formatCurrency(totalLentRemaining),
                                style: const TextStyle(
                                    color: Colors.blueAccent,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // 2. Daftar Utang / Piutang
                  if (_debts.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A2E),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          const Icon(Icons.receipt_long_outlined,
                              size: 48, color: Colors.white24),
                          const SizedBox(height: 12),
                          const Text('Belum ada data utang/piutang',
                              style: TextStyle(color: Colors.white70)),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _showAddDebtModal,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Catat Utang / Piutang'),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF6C63FF)),
                          ),
                        ],
                      ),
                    )
                  else
                    ..._debts.map((debt) {
                      final bool isBorrowed = debt['type'] == 'borrowed';
                      final double total =
                          (debt['amount'] as num?)?.toDouble() ?? 0.0;
                      final double remaining =
                          (debt['remaining_amount'] as num?)?.toDouble() ??
                              (debt['is_paid'] == true ? 0.0 : total);
                      final double paid =
                          (debt['paid_amount'] as num?)?.toDouble() ??
                              (total - remaining);
                      final bool isPaid =
                          debt['is_paid'] == true || remaining <= 0;

                      final double progress = total > 0
                          ? (paid / total).clamp(0.0, 1.0)
                          : (isPaid ? 1.0 : 0.0);

                      return Dismissible(
                        key: Key(debt['id'] ?? UniqueKey().toString()),
                        direction: DismissDirection.endToStart,
                        confirmDismiss: (_) => _confirmDeleteDebt(debt),
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          decoration: BoxDecoration(
                              color: Colors.redAccent,
                              borderRadius: BorderRadius.circular(16)),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1A2E),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isPaid
                                  ? Colors.green.withOpacity(0.3)
                                  : (isBorrowed
                                      ? Colors.redAccent.withOpacity(0.2)
                                      : Colors.blueAccent.withOpacity(0.2)),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Header Item
                              Row(
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: (isBorrowed
                                                    ? Colors.redAccent
                                                    : Colors.blueAccent)
                                                .withOpacity(0.18),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            isBorrowed ? 'Utang' : 'Piutang',
                                            style: TextStyle(
                                              color: isBorrowed
                                                  ? Colors.redAccent
                                                  : Colors.blueAccent,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            debt['person_name']?.toString() ??
                                                'Akun',
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isPaid
                                          ? Colors.green.withOpacity(0.15)
                                          : Colors.orange.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      isPaid ? 'Lunas' : 'Belum Lunas',
                                      style: TextStyle(
                                        color: isPaid
                                            ? Colors.greenAccent
                                            : Colors.orangeAccent,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Builder(
                                builder: (context) {
                                  final isRecurring =
                                      debt['is_recurring'] == true;
                                  final recurringDay =
                                      (debt['recurring_day'] as num?)?.toInt();
                                  final dueStr = debt['due_date']?.toString();

                                  if (!isRecurring && dueStr == null)
                                    return const SizedBox.shrink();

                                  final targetDueDate =
                                      NotificationService.calculateNextDueDate(
                                    isRecurring: isRecurring,
                                    recurringDay: recurringDay,
                                    dueDateStr: dueStr,
                                    isPaid: isPaid,
                                  );

                                  if (targetDueDate == null)
                                    return const SizedBox.shrink();

                                  final now = DateTime.now();
                                  final diffHours =
                                      targetDueDate.difference(now).inHours;
                                  final diffDays = targetDueDate
                                      .difference(DateTime(
                                          now.year, now.month, now.day))
                                      .inDays;

                                  Color dueColor = Colors.white54;
                                  String dueText;
                                  final prefix = isRecurring
                                      ? 'Rutin tgl $recurringDay • '
                                      : '';

                                  if (isPaid && !isRecurring) {
                                    dueColor = Colors.white38;
                                    dueText =
                                        'Jatuh tempo: ${DateFormat('dd MMM yyyy', 'id_ID').format(targetDueDate)} (Lunas)';
                                  } else if (isPaid && isRecurring) {
                                    dueColor = Colors.greenAccent;
                                    dueText =
                                        '$prefix Siklus ini lunas (Berikutnya: ${DateFormat('dd MMM yyyy', 'id_ID').format(targetDueDate)})';
                                  } else if (diffHours < 0) {
                                    dueColor = Colors.redAccent;
                                    dueText =
                                        '$prefix Lewat jatuh tempo (${DateFormat('dd MMM yyyy', 'id_ID').format(targetDueDate)})';
                                  } else if (diffHours <= 12) {
                                    dueColor = Colors.redAccent;
                                    dueText =
                                        '$prefix ⚠️ Jatuh tempo dalam $diffHours jam!';
                                  } else if (diffDays == 0) {
                                    dueColor = Colors.amberAccent;
                                    dueText = '$prefix Jatuh tempo hari ini!';
                                  } else if (diffDays == 1) {
                                    dueColor = Colors.amberAccent;
                                    dueText = '$prefix Jatuh tempo besok!';
                                  } else {
                                    dueColor = Colors.white70;
                                    dueText =
                                        '$prefix Jatuh tempo: ${DateFormat('dd MMM yyyy', 'id_ID').format(targetDueDate)}';
                                  }

                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Row(
                                      children: [
                                        Icon(
                                            isRecurring
                                                ? Icons.autorenew
                                                : Icons.event_outlined,
                                            size: 13,
                                            color: dueColor),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            dueText,
                                            style: TextStyle(
                                              color: dueColor,
                                              fontSize: 11,
                                              fontWeight: (diffDays <= 1 ||
                                                          diffHours <= 12) &&
                                                      !isPaid
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 14),

                              // Progress Bar Pelunasan
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: progress,
                                  minHeight: 6,
                                  backgroundColor:
                                      Colors.white.withOpacity(0.08),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    isPaid
                                        ? Colors.greenAccent
                                        : (isBorrowed
                                            ? const Color(0xFF6C63FF)
                                            : Colors.blueAccent),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),

                              // Tiga Angka: Total, Sudah Dibayar, Sisa Tagihan
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('Total Awal',
                                          style: TextStyle(
                                              color:
                                                  Colors.white.withOpacity(0.5),
                                              fontSize: 11)),
                                      const SizedBox(height: 2),
                                      Text(_formatCurrency(total),
                                          style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 13)),
                                    ],
                                  ),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Text('Terbayar',
                                          style: TextStyle(
                                              color:
                                                  Colors.white.withOpacity(0.5),
                                              fontSize: 11)),
                                      const SizedBox(height: 2),
                                      Text(_formatCurrency(paid),
                                          style: const TextStyle(
                                              color: Colors.greenAccent,
                                              fontSize: 13)),
                                    ],
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text('Sisa Tagihan',
                                          style: TextStyle(
                                              color:
                                                  Colors.white.withOpacity(0.5),
                                              fontSize: 11)),
                                      const SizedBox(height: 2),
                                      Text(
                                        _formatCurrency(remaining),
                                        style: TextStyle(
                                          color: isPaid
                                              ? Colors.white54
                                              : (isBorrowed
                                                  ? Colors.redAccent
                                                  : Colors.blueAccent),
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const Divider(color: Colors.white10, height: 24),

                              // Action Buttons: Cicil / Bayar, Sesuaikan (Fallback)
                              Row(
                                children: [
                                  if (!isPaid) ...[
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: () =>
                                            _showPayDebtModal(debt),
                                        icon: const Icon(Icons.payments,
                                            size: 16, color: Colors.white),
                                        label: const Text('Cicil / Bayar',
                                            style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              const Color(0xFF6C63FF),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10)),
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 10),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  OutlinedButton.icon(
                                    onPressed: () => _showEditDebtModal(debt),
                                    icon: const Icon(Icons.tune,
                                        size: 15, color: Colors.white70),
                                    label: const Text('Sesuaikan',
                                        style: TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12)),
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(
                                          color: Colors.white24),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 10, horizontal: 12),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        size: 20, color: Colors.redAccent),
                                    tooltip: 'Hapus Catatan',
                                    onPressed: () => _confirmDeleteDebt(debt),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _showAddDebtModal,
                    icon: const Icon(Icons.add, color: Colors.white),
                    label: const Text('Catat Utang/Piutang Baru',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A1A2E),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }
}

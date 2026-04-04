import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:expense_tracker_flutter/utils/formatters.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _wallets = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadWallets();
  }

  Future<void> _loadWallets() async {
    setState(() => _isLoading = true);
    final userId = _supabase.auth.currentUser!.id;
    try {
      final walletsData = await _supabase
          .from('wallets')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: true);

      final transactionsData = await _supabase
          .from('transactions')
          .select('wallet_id, amount, type')
          .eq('user_id', userId)
          .not('wallet_id', 'is', null);

      List<Map<String, dynamic>> processedWallets = [];

      for (var w in walletsData) {
        double currentBalance = (w['balance'] as num).toDouble();
        final String wId = w['id'];
        
        for (var t in transactionsData) {
          if (t['wallet_id'] == wId) {
            final amt = (t['amount'] as num).toDouble();
            if (t['type'] == 'income') currentBalance += amt;
            else currentBalance -= amt;
          }
        }
        
        final newWallet = Map<String, dynamic>.from(w);
        newWallet['true_balance'] = currentBalance;
        processedWallets.add(newWallet);
      }
      
      setState(() {
        _wallets = processedWallets;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        // Fallback if table doesn't exist yet
        setState(() => _isLoading = false);
      }
    }
  }

  void _showAddWalletModal() {
    final nameController = TextEditingController();
    final balanceController = TextEditingController();

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      isScrollControlled: true,
      builder: (context) {
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
              const Text('Tambah Dompet', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Nama Dompet (Misal: BCA, GoPay)',
                  labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                  filled: true,
                  fillColor: const Color(0xFF0F0F1A),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: balanceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: false),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  ThousandsSeparatorInputFormatter(),
                ],
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Saldo Awal',
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
                    if (nameController.text.isNotEmpty) {
                      final userId = _supabase.auth.currentUser!.id;
                      try {
                        await _supabase.from('wallets').insert({
                          'user_id': userId,
                          'name': nameController.text,
                          'balance': double.tryParse(balanceController.text.replaceAll('.', '')) ?? 0,
                          'icon': '👛',
                        });
                        if (context.mounted) Navigator.pop(context);
                        _loadWallets();
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
                  child: const Text('Simpan', style: TextStyle(color: Colors.white)),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
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
        title: const Text('Dompet (Wallets)', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF0F0F1A),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF)))
          : ListView.builder(
              padding: const EdgeInsets.all(24),
              itemCount: _wallets.length + 1,
              itemBuilder: (context, index) {
                if (index == _wallets.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: ElevatedButton.icon(
                      onPressed: _showAddWalletModal,
                      icon: const Icon(Icons.add, color: Colors.white),
                      label: const Text('Tambah Dompet Baru', style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1A1A2E),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  );
                }
                final wallet = _wallets[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6C63FF).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6C63FF).withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Text(wallet['icon'] ?? '👛', style: const TextStyle(fontSize: 24)),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(wallet['name'], style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text(_formatCurrency((wallet['true_balance'] as num).toDouble()), style: const TextStyle(color: Colors.greenAccent, fontSize: 14)),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:expense_tracker_flutter/data/services/firestore_service.dart';
import 'package:expense_tracker_flutter/data/services/gmail_sync_service.dart';
import 'package:expense_tracker_flutter/data/services/biometric_service.dart';
import 'package:expense_tracker_flutter/presentation/screens/recurring/recurring_screen.dart';
import 'package:expense_tracker_flutter/presentation/screens/wallet/wallet_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  bool _isLoading = true;
  bool _isSaving = false;
  String _email = '';
  String? _photoUrl;
  GmailSyncStatus _syncStatus = GmailSyncStatus(isConnected: false);
  bool _isBiometricSupported = false;
  bool _isBiometricEnabled = false;
  bool _allowPinFallback = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final profile = await FirestoreService.getProfile(user.uid);
    final syncStatus = await GmailSyncService.getStatus(user.uid);
    final isBioSupported = await BiometricService.isBiometricSupported();
    final isBioEnabled = await BiometricService.isBiometricEnabled();
    final allowPin = await BiometricService.isPinFallbackAllowed();

    if (mounted) {
      setState(() {
        _nameController.text = profile?['full_name'] ?? user.displayName ?? '';
        _email = user.email ?? '';
        _emailController.text = user.email ?? '';
        _photoUrl = user.photoURL ?? profile?['photo_url'];
        _syncStatus = syncStatus;
        _isBiometricSupported = isBioSupported;
        _isBiometricEnabled = isBioEnabled;
        _allowPinFallback = allowPin;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleBiometric(bool enable) async {
    if (enable) {
      final success = await BiometricService.authenticate(
        reason: 'Pindai sidik jari Anda untuk mengaktifkan kunci biometrik',
        biometricOnly: true,
      );
      if (success) {
        await BiometricService.setBiometricEnabled(true);
        if (mounted) {
          setState(() => _isBiometricEnabled = true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Kunci sidik jari berhasil diaktifkan!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Verifikasi sidik jari dibatalkan atau tidak cocok.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    } else {
      await BiometricService.setBiometricEnabled(false);
      if (mounted) {
        setState(() => _isBiometricEnabled = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kunci sidik jari dinonaktifkan.'),
          ),
        );
      }
    }
  }

  Future<void> _togglePinFallback(bool allow) async {
    await BiometricService.setPinFallbackAllowed(allow);
    if (mounted) {
      setState(() => _allowPinFallback = allow);
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _isSaving = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final name = _nameController.text.trim();
    await user.updateDisplayName(name);
    await FirestoreService.saveProfile(user.uid, {
      'id': user.uid,
      'email': _email,
      'full_name': name,
      'updated_at': DateTime.now().toIso8601String(),
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Profil berhasil diperbarui!'),
        backgroundColor: Colors.green,
      ),
    );
    setState(() => _isSaving = false);
  }

  Future<void> _logout() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          title: const Text('Konfirmasi Logout', style: TextStyle(color: Colors.white)),
          content: const Text('Apakah Anda yakin ingin keluar dari akun ini?', style: TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              child: const Text('Logout', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_onboarding', true);
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  Widget _buildFallbackInitial() {
    return Center(
      child: Text(
        _nameController.text.isNotEmpty
            ? _nameController.text[0].toUpperCase()
            : '?',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 36,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F1A),
        elevation: 0,
        title: const Text('Profil', style: TextStyle(color: Colors.white)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const SizedBox(height: 24),

                  // Avatar (Google Photo or Initial)
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C63FF),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF6C63FF), width: 2),
                    ),
                    child: ClipOval(
                      child: _photoUrl != null && _photoUrl!.isNotEmpty
                          ? Image.network(
                              _photoUrl!,
                              width: 90,
                              height: 90,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _buildFallbackInitial(),
                            )
                          : _buildFallbackInitial(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _email,
                    style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14),
                  ),
                  const SizedBox(height: 32),

                  // Gmail Integration Status Tile
                  ListTile(
                    onTap: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen()));
                      _loadProfile();
                    },
                    leading: const Icon(Icons.account_balance, color: Color(0xFF6C63FF)),
                    title: const Text('Integrasi Mbanking', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      _syncStatus.isConnected ? 'Terhubung (${_syncStatus.email})' : 'Belum Terhubung',
                      style: TextStyle(color: _syncStatus.isConnected ? Colors.greenAccent : Colors.orangeAccent, fontSize: 12),
                    ),
                    trailing: const Icon(Icons.chevron_right, color: Colors.white54),
                    tileColor: const Color(0xFF1A1A2E),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  const SizedBox(height: 12),

                  ListTile(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const RecurringScreen())),
                    leading: const Icon(Icons.autorenew, color: Color(0xFF6C63FF)),
                    title: const Text('Transaksi Rutin', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    trailing: const Icon(Icons.chevron_right, color: Colors.white54),
                    tileColor: const Color(0xFF1A1A2E),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  const SizedBox(height: 12),

                  // Pengaturan Keamanan Biometrik
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A2E),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        SwitchListTile(
                          secondary: const Icon(Icons.fingerprint, color: Color(0xFF6C63FF)),
                          title: const Text(
                            'Kunci Sidik Jari',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            _isBiometricSupported
                                ? (_isBiometricEnabled ? 'Aktif (Kunci saat buka aplikasi)' : 'Nonaktif')
                                : 'Perangkat tidak mendukung biometrik',
                            style: TextStyle(
                              color: _isBiometricEnabled ? Colors.greenAccent : Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                          value: _isBiometricEnabled,
                          activeThumbColor: const Color(0xFF6C63FF),
                          onChanged: _isBiometricSupported ? (val) => _toggleBiometric(val) : null,
                        ),
                        if (_isBiometricEnabled) ...[
                          const Divider(color: Colors.white10, height: 1),
                          SwitchListTile(
                            secondary: const Icon(Icons.lock_outline, color: Colors.white54),
                            title: const Text(
                              'Cadangan PIN / Pola Layar',
                              style: TextStyle(color: Colors.white, fontSize: 14),
                            ),
                            subtitle: const Text(
                              'Izinkan PIN HP jika sensor sidik jari kotor/gagal',
                              style: TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                            value: _allowPinFallback,
                            activeThumbColor: const Color(0xFF6C63FF),
                            onChanged: (val) => _togglePinFallback(val),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Form
                  TextField(
                    controller: _nameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Nama Lengkap',
                      labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                      prefixIcon: const Icon(Icons.person_outlined, color: Color(0xFF6C63FF)),
                      filled: true,
                      fillColor: const Color(0xFF1A1A2E),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _emailController,
                    readOnly: true,
                    style: const TextStyle(color: Colors.white70),
                    decoration: InputDecoration(
                      labelText: 'Email Terdaftar',
                      labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                      prefixIcon: const Icon(Icons.email_outlined, color: Color(0xFF6C63FF)),
                      filled: true,
                      fillColor: const Color(0xFF1A1A2E),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Tombol Simpan
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveProfile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6C63FF),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isSaving
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              'Simpan Perubahan',
                              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Tombol Logout
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton(
                      onPressed: _logout,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.redAccent),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Logout',
                        style: TextStyle(color: Colors.redAccent, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  Center(
                    child: Text(
                      'Expense Tracker • Bank Sync v2.0',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.2),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:expense_tracker_flutter/data/services/biometric_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;

    // Pastikan status akun tersimpan (permanen) dimuat oleh Firebase Auth
    final user = FirebaseAuth.instance.currentUser ??
        await FirebaseAuth.instance.authStateChanges().first;
    final prefs = await SharedPreferences.getInstance();
    final hasSeenOnboarding = prefs.getBool('has_seen_onboarding') ?? false;

    if (!mounted) return;

    if (user != null) {
      // 1. Sesi login akun aktif permanen.
      // 2. Sekarang cek gembok biometrik pembuka aplikasi.
      final isBioEnabled = await BiometricService.isBiometricEnabled();
      if (!mounted) return;

      if (isBioEnabled) {
        // Cold start (aplikasi tertutup total): SELALU minta biometrik jika fitur aktif
        Navigator.pushReplacementNamed(context, '/biometric-lock');
      } else {
        Navigator.pushReplacementNamed(context, '/home');
      }
    } else if (hasSeenOnboarding) {
      // Hanya jika pengguna belum pernah login atau telah logout manual
      Navigator.pushReplacementNamed(context, '/login');
    } else {
      // Pertama kali buka app setelah install baru
      Navigator.pushReplacementNamed(context, '/onboarding');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.account_balance_wallet,
              size: 80,
              color: Color(0xFF6C63FF),
            ),
            const SizedBox(height: 24),
            const Text(
              'Expense Tracker',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Kelola keuanganmu dengan mudah',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
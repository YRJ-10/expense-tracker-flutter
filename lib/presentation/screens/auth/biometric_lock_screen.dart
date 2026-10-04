import 'package:flutter/material.dart';
import 'package:expense_tracker_flutter/data/services/biometric_service.dart';

class BiometricLockScreen extends StatefulWidget {
  final VoidCallback? onUnlocked;

  const BiometricLockScreen({super.key, this.onUnlocked});

  @override
  State<BiometricLockScreen> createState() => _BiometricLockScreenState();
}

class _BiometricLockScreenState extends State<BiometricLockScreen> {
  bool _isAuthenticating = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startAuth();
    });
  }

  Future<void> _startAuth({bool? forceBiometricOnly}) async {
    if (_isAuthenticating) return;

    setState(() {
      _isAuthenticating = true;
      _errorMessage = null;
    });

    final success = await BiometricService.authenticate(
      reason: 'Pindai sidik jari Anda untuk membuka Expense Tracker',
      biometricOnly: forceBiometricOnly,
    );

    if (!mounted) return;

    setState(() {
      _isAuthenticating = false;
    });

    if (success) {
      if (widget.onUnlocked != null) {
        widget.onUnlocked!();
      } else {
        Navigator.pushReplacementNamed(context, '/home');
      }
    } else {
      setState(() {
        _errorMessage = 'Verifikasi tidak berhasil. Silakan coba lagi.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF6C63FF).withValues(alpha: 0.4),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6C63FF).withValues(alpha: 0.2),
                        blurRadius: 24,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.fingerprint,
                    size: 54,
                    color: Color(0xFF6C63FF),
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Expense Tracker Terkunci',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Aplikasi dilindungi dengan kunci biometrik.\nSilakan pindai sidik jari Anda.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.redAccent.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _isAuthenticating ? null : () => _startAuth(forceBiometricOnly: true),
                    icon: _isAuthenticating
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.fingerprint, color: Colors.white),
                    label: Text(
                      _isAuthenticating ? 'Memverifikasi...' : 'Pindai Sidik Jari',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C63FF),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                FutureBuilder<bool>(
                  future: BiometricService.isPinFallbackAllowed(),
                  builder: (context, snapshot) {
                    if (snapshot.data == true) {
                      return TextButton.icon(
                        onPressed: _isAuthenticating ? null : () => _startAuth(forceBiometricOnly: false),
                        icon: const Icon(Icons.lock_outline, size: 18, color: Colors.white70),
                        label: const Text(
                          'Gunakan PIN / Pola Layar',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

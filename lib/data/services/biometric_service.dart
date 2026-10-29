import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BiometricService {
  static final LocalAuthentication _auth = LocalAuthentication();
  static const String _keyBiometricEnabled = 'biometric_lock_enabled';
  static const String _keyAllowPinFallback = 'biometric_allow_pin_fallback';
  static DateTime? _lastAuthTime;

  /// Rekam waktu sukses autentikasi
  static void recordAuthSuccess() {
    _lastAuthTime = DateTime.now();
  }

  /// Cek apakah sesi autentikasi biometrik masih valid (default 5 menit)
  static bool isAuthSessionValid({int timeoutMinutes = 5}) {
    if (_lastAuthTime == null) return false;
    return DateTime.now().difference(_lastAuthTime!).inMinutes < timeoutMinutes;
  }

  /// Hapus sesi autentikasi saat ini (misal saat logout)
  static void clearAuthSession() {
    _lastAuthTime = null;
  }

  /// Cek apakah perangkat mendukung autentikasi biometrik / sidik jari
  static Future<bool> isBiometricSupported() async {
    try {
      final isSupported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      return isSupported || canCheck;
    } catch (_) {
      return false;
    }
  }

  /// Ambil jenis biometrik yang tersedia di perangkat (misal fingerprint)
  static Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (_) {
      return [];
    }
  }

  /// Cek apakah fitur kunci biometrik aktif dari preferensi pengguna
  static Future<bool> isBiometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyBiometricEnabled) ?? false;
  }

  /// Simpan preferensi aktif/tidaknya kunci biometrik
  static Future<void> setBiometricEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBiometricEnabled, enabled);
  }

  /// Cek apakah opsi cadangan PIN/Pola diizinkan
  static Future<bool> isPinFallbackAllowed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAllowPinFallback) ?? true;
  }

  /// Simpan preferensi izin cadangan PIN/Pola
  static Future<void> setPinFallbackAllowed(bool allow) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAllowPinFallback, allow);
  }

  /// Lakukan proses autentikasi biometrik
  static Future<bool> authenticate({
    String reason = 'Pindai sidik jari Anda untuk membuka Expense Tracker',
    bool? biometricOnly,
  }) async {
    try {
      final allowPin = await isPinFallbackAllowed();
      final onlyBio = biometricOnly ?? !allowPin;

      final success = await _auth.authenticate(
        localizedReason: reason,
        options: AuthenticationOptions(
          biometricOnly: onlyBio,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
      if (success) {
        recordAuthSuccess();
      }
      return success;
    } on PlatformException catch (_) {
      return false;
    } catch (_) {
      return false;
    }
  }
}

import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BiometricService {
  static final LocalAuthentication _auth = LocalAuthentication();
  static const String _keyBiometricEnabled = 'biometric_lock_enabled';
  static const String _keyAllowPinFallback = 'biometric_allow_pin_fallback';
  static DateTime? _lastUnlockTime;

  /// Rekam waktu berhasil membuka gembok biometrik (in-memory)
  static Future<void> recordBiometricUnlock() async {
    _lastUnlockTime = DateTime.now();
  }

  /// Cek apakah gembok biometrik sudah kedaluwarsa (perlu scan ulang)
  /// Default: 5 menit (300 detik)
  static bool isBiometricLockExpired({int timeoutMinutes = 5}) {
    if (_lastUnlockTime == null) return true;
    return DateTime.now().difference(_lastUnlockTime!).inMinutes >= timeoutMinutes;
  }

  /// Hapus status unlock biometrik (misal saat logout manual dari profil)
  static Future<void> clearBiometricUnlock() async {
    _lastUnlockTime = null;
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
        await recordBiometricUnlock();
      }
      return success;
    } on PlatformException catch (_) {
      return false;
    } catch (_) {
      return false;
    }
  }
}

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Biometric authentication service — fingerprint / Face ID untuk login cepat.
///
/// Flow:
/// 1. User login normal pertama kali (email + password)
/// 2. Setelah sukses, app tawarkan "Enable biometric login"
/// 3. Kalau accept, credential di-store di SharedPreferences (base64 encode,
///    bukan crypto. Untuk MVP cukup karena protected by OS biometric prompt.
///    Production lebih baik pakai flutter_secure_storage di iOS Keychain /
///    Android Keystore — bisa di-upgrade nanti).
/// 4. Next launch, login screen detect biometric saved → tampilkan tombol
///    "Login dengan sidik jari" → tap → biometric prompt → auto-login.
///
/// PWA WebView TIDAK punya akses ke biometric hardware. Web Authentication
/// API tersedia tapi butuh server challenge + tidak reliable di Android.
class BiometricService {
  static const _kBiometricEnabledKey = 'natalo_biometric_enabled';
  static const _kBiometricCredentialKey = 'natalo_biometric_credential_v1';

  final LocalAuthentication _auth = LocalAuthentication();

  /// True kalau device punya hardware biometric + at least one enrolled.
  Future<bool> isDeviceSupported() async {
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return false;
      final canCheck = await _auth.canCheckBiometrics;
      if (!canCheck) return false;
      final biometrics = await _auth.getAvailableBiometrics();
      return biometrics.isNotEmpty;
    } catch (e) {
      if (kDebugMode) debugPrint('[biometric] device check failed: $e');
      return false;
    }
  }

  /// True kalau user sudah enable biometric login (credential ter-stored).
  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kBiometricEnabledKey) ?? false;
  }

  /// Show OS biometric prompt. Return true kalau auth sukses.
  Future<bool> authenticate({
    String reason = 'Verifikasi untuk login ke Natalo Petshop',
  }) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false, // izinkan PIN/pattern fallback
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[biometric] auth failed: $e');
      return false;
    }
  }

  /// Enable biometric login — minta user authenticate dulu (anti
  /// orang lain sembarangan enable), lalu save credential.
  ///
  /// Return true kalau sukses enable.
  Future<bool> enable({
    required String identifier,
    required String password,
  }) async {
    final supported = await isDeviceSupported();
    if (!supported) return false;
    final ok = await authenticate(
      reason: 'Aktifkan login dengan sidik jari',
    );
    if (!ok) return false;
    final prefs = await SharedPreferences.getInstance();
    final encoded = base64Encode(utf8.encode(jsonEncode({
      'i': identifier,
      'p': password,
    })));
    await prefs.setString(_kBiometricCredentialKey, encoded);
    await prefs.setBool(_kBiometricEnabledKey, true);
    return true;
  }

  /// Disable biometric — clear credential. Call saat logout / dari Settings.
  Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kBiometricCredentialKey);
    await prefs.setBool(_kBiometricEnabledKey, false);
  }

  /// Setelah biometric auth sukses, panggil ini untuk dapat credential.
  /// Caller pakai untuk auto-login via authService.login(...).
  Future<({String identifier, String password})?> readCredential() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(_kBiometricCredentialKey);
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final decoded = jsonDecode(utf8.decode(base64Decode(encoded)));
      if (decoded is Map &&
          decoded['i'] is String &&
          decoded['p'] is String) {
        return (
          identifier: decoded['i'] as String,
          password: decoded['p'] as String,
        );
      }
    } catch (_) {}
    return null;
  }
}

final biometricService = BiometricService();

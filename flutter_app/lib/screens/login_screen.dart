import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/app_analytics.dart';
import '../services/app_crashlytics.dart';
import '../services/auth_service.dart';
import '../services/biometric_service.dart';
import '../services/push_notification_service.dart';
import '../state/cart_store.dart';
import '../state/favorite_store.dart';
import '../state/member_store.dart';
import '../utils/haptics.dart';
import '../widgets/loading_button.dart';

const _brandBlue = Color(0xFF0B7FEA);

/// Login screen — match Capacitor APK persis:
/// - Custom back button "Kembali" + title "Masuk" tengah
/// - Logo image besar + judul "Masuk Member Natalo" + subtitle
/// - White card form dengan info "Akun member Natalo" blue tint
/// - Field Email/No HP + Password (Lupa password? link)
/// - "Masuk" pill button biru full width
/// - Footer "Belum punya akun? Daftar gratis"
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  bool _biometricEnabled = false;
  bool _biometricSupported = false;

  @override
  void initState() {
    super.initState();
    _checkBiometric();
  }

  Future<void> _checkBiometric() async {
    final supported = await biometricService.isDeviceSupported();
    final enabled = await biometricService.isEnabled();
    if (!mounted) return;
    setState(() {
      _biometricSupported = supported;
      _biometricEnabled = enabled;
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loginWithBiometric() async {
    final ok = await biometricService.authenticate(
      reason: 'Login ke Natalo Petshop',
    );
    if (!ok) return;
    final cred = await biometricService.readCredential();
    if (cred == null) {
      AppHaptics.warning();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Credential biometric hilang. Silakan login manual.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await biometricService.disable();
      setState(() => _biometricEnabled = false);
      return;
    }
    _emailController.text = cred.identifier;
    _passwordController.text = cred.password;
    await _login(fromBiometric: true);
  }

  Future<void> _login({bool fromBiometric = false}) async {
    if (!fromBiometric) AppHaptics.tap();
    setState(() => _loading = true);
    try {
      final profile = await authService.login(
        identifier: _emailController.text,
        password: _passwordController.text,
      );
      memberStore.setProfile(profile);
      await favoriteStore.refresh();
      try {
        await cartStore.syncToServer();
      } catch (_) {
        // Cart sync bisa di-retry dari cart/checkout; login tetap selesai.
      }
      if (!mounted) return;
      AppHaptics.success();
      // Register FCM token ke server setelah login (fire-and-forget).
      // No-op kalau Firebase belum di-setup.
      pushNotificationService.registerWithServer();
      // Analytics + Crashlytics — set user ID + log login event untuk
      // funnel analysis + crash attribution.
      AppAnalytics.setUserId(profile.email);
      AppAnalytics.logLogin(fromBiometric ? 'biometric' : 'password');
      AppCrashlytics.setUserId(profile.email);

      // Setelah login pertama berhasil DAN device support biometric +
      // belum enabled, tawarkan enable biometric.
      if (!fromBiometric && _biometricSupported && !_biometricEnabled) {
        await _promptEnableBiometric();
      }

      if (!mounted) return;
      final redirectRoute = _redirectRoute;
      Navigator.pushNamedAndRemoveUntil(
        context,
        redirectRoute ?? '/member',
        (route) => false,
        arguments: _redirectArguments,
      );
    } catch (error) {
      if (!mounted) return;
      AppHaptics.warning();
      // Friendly error message — translate technical errors ke user-readable.
      // ApiException punya statusCode kalau dari server response.
      final message = _humanizeLoginError(error);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? get _redirectRoute {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map && args['redirect'] is String) {
      final route = (args['redirect'] as String).trim();
      return route.isEmpty ? null : route;
    }
    if (args is String && args.trim().startsWith('/')) {
      return args.trim();
    }
    return null;
  }

  Object? get _redirectArguments {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) return args['arguments'];
    return null;
  }

  /// Translate technical error message dari API ke teks yang user-friendly.
  /// Backend Capacitor return error message Indonesian dari /api/auth/member-login
  /// (mis. "Password salah", "User tidak ditemukan") — pakai langsung kalau
  /// statusCode 400/401. Untuk network error generic, kasih hint actionable.
  String _humanizeLoginError(Object error) {
    final raw = error.toString();
    if (error is ApiException) {
      // Server error message — biasanya sudah user-friendly dari backend.
      // Tapi kalau bare "Request gagal." atau status 500, beri konteks.
      if (error.statusCode == 401) {
        return 'Email/HP atau password salah. Coba lagi atau pakai "Lupa password?".';
      }
      if (error.statusCode == 429) {
        return 'Terlalu banyak percobaan. Tunggu beberapa menit lalu coba lagi.';
      }
      if (error.statusCode != null && error.statusCode! >= 500) {
        return 'Server sedang bermasalah. Coba lagi nanti.';
      }
      return error.message;
    }
    // Network / timeout errors — exception message biasanya technical.
    final lower = raw.toLowerCase();
    if (lower.contains('socketexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('connection refused')) {
      return 'Tidak bisa connect ke server. Cek koneksi internet kamu.';
    }
    if (lower.contains('timeout')) {
      return 'Koneksi lambat. Coba lagi atau pakai jaringan lain.';
    }
    return 'Login gagal: $raw';
  }

  Future<void> _promptEnableBiometric() async {
    final accept = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        icon: const Icon(
          Icons.fingerprint_rounded,
          size: 48,
          color: _brandBlue,
        ),
        title: const Text(
          'Login lebih cepat?',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: const Text(
          'Aktifkan login dengan sidik jari / Face ID supaya tidak perlu ketik password lagi.',
          textAlign: TextAlign.center,
          style: TextStyle(height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Nanti saja'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _brandBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            child: const Text('Aktifkan'),
          ),
        ],
      ),
    );
    if (accept == true && mounted) {
      final ok = await biometricService.enable(
        identifier: _emailController.text,
        password: _passwordController.text,
      );
      if (!mounted) return;
      if (ok) {
        AppHaptics.success();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Biometric login aktif!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF17202A)),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text(
          'Masuk',
          style: TextStyle(
            color: Color(0xFF17202A),
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // ── Header section dengan logo + judul ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              color: const Color(0xFFEFF2F6),
              child: Column(
                children: [
                  // Logo Natalo (gambar) dengan halo putih shadow
                  Container(
                    height: 88,
                    width: 88,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: _brandBlue.withValues(alpha: 0.20),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    // Pakai icon-only.png (square iOS-style) — exact match
                    // Capacitor. brand/logo.png adalah wordmark horizontal
                    // (akan ter-crop di square 88x88).
                    child: Image.asset(
                      'assets/native/icon-only.png',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: _brandBlue,
                        alignment: Alignment.center,
                        child: const Text(
                          'NL',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Masuk Member Natalo',
                    style: TextStyle(
                      color: Color(0xFF111111),
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Belanja kebutuhan hewan jadi lebih mudah, cepat, dan hemat.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // ── White card form ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Info blue card
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF5FF),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Akun member Natalo',
                            style: TextStyle(
                              color: _brandBlue,
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Masuk untuk lanjut checkout, cek pesanan, dan pakai benefit member.',
                            style: TextStyle(
                              color: _brandBlue,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    // Email / No HP field
                    const Text(
                      'Email / No. HP',
                      style: TextStyle(
                        color: Color(0xFF111111),
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        hintText: 'Masukan Email / No Hp',
                        hintStyle: const TextStyle(
                          color: Color(0xFF9CA3AF),
                          fontWeight: FontWeight.w600,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        // Match Capacitor: rounded rectangle (radius 14) NOT
                        // full pill. Pill cuma untuk button "Masuk".
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide:
                              const BorderSide(color: Color(0xFFE5E7EB)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide:
                              const BorderSide(color: Color(0xFFE5E7EB)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide:
                              const BorderSide(color: _brandBlue, width: 1.4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Password label + Lupa password? link
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Password',
                            style: TextStyle(
                              color: Color(0xFF111111),
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pushNamed(
                              context, '/member/forgot-password'),
                          child: const Text(
                            'Lupa password?',
                            style: TextStyle(
                              color: _brandBlue,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        hintText: 'Masukkan password',
                        hintStyle: const TextStyle(
                          color: Color(0xFF9CA3AF),
                          fontWeight: FontWeight.w600,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _obscure = !_obscure),
                          tooltip: _obscure
                              ? 'Tampilkan password'
                              : 'Sembunyikan password',
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: const Color(0xFF9CA3AF),
                          ),
                        ),
                        // Match Capacitor: rounded rectangle (radius 14) NOT
                        // full pill. Pill cuma untuk button "Masuk".
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide:
                              const BorderSide(color: Color(0xFFE5E7EB)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide:
                              const BorderSide(color: Color(0xFFE5E7EB)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide:
                              const BorderSide(color: _brandBlue, width: 1.4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    // Masuk button — pill blue dengan loading state otomatis
                    // dari LoadingButton (spinner replace text saat _loading).
                    LoadingButton(
                      onPressed: _login,
                      loading: _loading,
                      color: _brandBlue,
                      child: const Text('Masuk'),
                    ),
                    // Biometric login button — muncul kalau device support +
                    // sudah pernah login + user enable biometric sebelumnya.
                    if (_biometricEnabled) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _loading ? null : _loginWithBiometric,
                        icon: const Icon(
                          Icons.fingerprint_rounded,
                          color: _brandBlue,
                          size: 24,
                        ),
                        label: const Text(
                          'Login dengan sidik jari',
                          style: TextStyle(
                            color: _brandBlue,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          side: const BorderSide(color: _brandBlue, width: 1.4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    const Divider(color: Color(0xFFE5E7EB), height: 1),
                    const SizedBox(height: 16),
                    // Footer "Belum punya akun? Daftar gratis"
                    Center(
                      child: Column(
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pushNamed(
                                context, '/member/register'),
                            style: TextButton.styleFrom(
                              foregroundColor: _brandBlue,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              minimumSize: const Size(44, 44),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text.rich(
                              TextSpan(
                                text: 'Belum punya akun? ',
                                style: TextStyle(
                                  color: Color(0xFF6B7280),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                                children: [
                                  TextSpan(
                                    text: 'Daftar gratis',
                                    style: TextStyle(
                                      color: _brandBlue,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Daftar gratis dan mulai kumpulkan benefit member Natalo.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF9CA3AF),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

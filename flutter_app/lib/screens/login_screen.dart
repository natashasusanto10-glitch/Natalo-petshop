import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

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

const _brandBlue = Color(0xFF0787F5);
const _brandBlueDark = Color(0xFF075FCC);

/// Login member visual shell. Auth flow tetap memakai service existing.
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
      await memberStore.setSession(
        profile: profile,
        token: authService.lastSessionToken,
      );
      try {
        await favoriteStore.refresh();
      } catch (_) {
        // Wishlist bisa di-refresh ulang dari halaman Akun/Wishlist.
      }
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
      AppAnalytics.logEvent('login', {
        'method': fromBiometric ? 'biometric' : 'password',
      });
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
      return 'Server butuh waktu lebih lama. Coba lagi sebentar.';
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

  void _openOtpLogin() {
    AppHaptics.tap();
    // Pass redirect arguments (kalau ada) ke OTP screen supaya post-login
    // routing tetap sama (deep link ke cart bisa balik ke cart setelah OTP).
    final args = ModalRoute.of(context)?.settings.arguments;
    Navigator.pushNamed(context, '/member/login-otp', arguments: args);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;
    final isSmallHeight = size.height < 720;
    final isSmallWidth = size.width < 360;
    final horizontalPadding = isSmallWidth ? 16.0 : 20.0;
    final sectionGap = isSmallHeight ? 20.0 : 26.0;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: cs.surface,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: cs.onSurface),
          onPressed: () => Navigator.pushNamedAndRemoveUntil(
            context,
            '/',
            (_) => false,
          ),
        ),
        title: Text(
          'Masuk',
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [cs.surface, cs.surfaceContainerHighest],
            ),
          ),
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.only(
              left: horizontalPadding,
              right: horizontalPadding,
              top: isSmallHeight ? 18 : 26,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _LoginHeroSection(
                      logoSize: isSmallHeight ? 72 : 84,
                      titleSize: isSmallWidth ? 34 : 40,
                    ),
                    SizedBox(height: sectionGap),
                    const _MemberBenefitRow(),
                    SizedBox(height: isSmallHeight ? 18 : 22),
                    Container(
                      padding: EdgeInsets.all(isSmallWidth ? 18 : 20),
                      decoration: BoxDecoration(
                        color: cs.surface,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: cs.outlineVariant),
                        boxShadow: [
                          BoxShadow(
                            color: _brandBlueDark.withValues(alpha: 0.08),
                            blurRadius: 28,
                            offset: const Offset(0, 14),
                          ),
                        ],
                      ),
                      child: AutofillGroup(
                        child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Email / No HP field
                          Text(
                            'Email / No. HP',
                            style: TextStyle(
                              color: cs.onSurface,
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _LoginTextField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            hint: 'Masukkan email atau nomor HP',
                            prefixIcon: Icons.mail_outline_rounded,
                            autofillHints: const [
                              AutofillHints.username,
                              AutofillHints.email,
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Password label + Lupa password? link
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Password',
                                  style: TextStyle(
                                    color: cs.onSurface,
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
                          _LoginTextField(
                            controller: _passwordController,
                            obscureText: _obscure,
                            hint: 'Masukkan password',
                            prefixIcon: Icons.lock_outline_rounded,
                            autofillHints: const [AutofillHints.password],
                            suffix: IconButton(
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                              tooltip: _obscure
                                  ? 'Tampilkan password'
                                  : 'Sembunyikan password',
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                color: const Color(0xFF7B8AA5),
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
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _brandBlue,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(54),
                              elevation: 0,
                              shadowColor: _brandBlue.withValues(alpha: 0.30),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
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
                                side: const BorderSide(
                                    color: _brandBlue, width: 1.4),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          const _LoginSeparator(),
                          const SizedBox(height: 14),
                          _WhatsAppOtpLoginButton(onTap: _openOtpLogin),
                        ],
                      ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 16, bottom: 12),
                      child: _RegisterBenefitCard(
                        onRegister: () =>
                            Navigator.pushNamed(context, '/member/register'),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 4),
                      child: _SecurityNote(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginHeroSection extends StatelessWidget {
  final double logoSize;
  final double titleSize;

  const _LoginHeroSection({
    required this.logoSize,
    required this.titleSize,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Positioned(
          right: 18,
          top: 8,
          child: Icon(
            Icons.pets_rounded,
            color: _brandBlue.withValues(alpha: 0.07),
            size: 58,
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: logoSize,
              width: logoSize,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(logoSize * 0.30),
                boxShadow: [
                  BoxShadow(
                    color: _brandBlue.withValues(alpha: 0.18),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset(
                'assets/native/icon-only.png',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: _brandBlue,
                  alignment: Alignment.center,
                  child: Text(
                    'NL',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: logoSize * 0.34,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 26),
            Text(
              'Masuk Member\nNatalo',
              maxLines: 2,
              overflow: TextOverflow.visible,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: titleSize,
                fontWeight: FontWeight.w900,
                height: 1.05,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Belanja kebutuhan hewan\njadi lebih mudah, cepat,\ndan hemat.',
              maxLines: 3,
              overflow: TextOverflow.visible,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                height: 1.42,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MemberBenefitRow extends StatelessWidget {
  const _MemberBenefitRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(
          child: _BenefitCard(
            icon: Icons.monetization_on_rounded,
            title: 'Poin Member',
            subtitle: 'Kumpulkan poin setiap belanja',
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: _BenefitCard(
            icon: Icons.confirmation_number_rounded,
            title: 'Voucher Eksklusif',
            subtitle: 'Voucher khusus member',
          ),
        ),
      ],
    );
  }
}

class _BenefitCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _BenefitCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 180;
        final iconWidget = Container(
          width: compact ? 46 : 52,
          height: compact ? 46 : 52,
          decoration: const BoxDecoration(
            color: _brandBlue,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: compact ? 24 : 27),
        );
        final textWidget = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.visible,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w900,
                height: 1.16,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              maxLines: 3,
              overflow: TextOverflow.visible,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 12.8,
                fontWeight: FontWeight.w600,
                height: 1.28,
              ),
            ),
          ],
        );

        return Container(
          constraints: const BoxConstraints(minHeight: 118),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: cs.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: _brandBlueDark.withValues(alpha: 0.07),
                blurRadius: 18,
                offset: const Offset(0, 9),
              ),
            ],
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    iconWidget,
                    const SizedBox(height: 12),
                    textWidget,
                  ],
                )
              : Row(
                  children: [
                    iconWidget,
                    const SizedBox(width: 12),
                    Expanded(child: textWidget),
                  ],
                ),
        );
      },
    );
  }
}

class _LoginTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData prefixIcon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffix;
  // #1 autofill: aktifkan Google Password Manager / auto-isi credential.
  final List<String>? autofillHints;

  const _LoginTextField({
    required this.controller,
    required this.hint,
    required this.prefixIcon,
    this.keyboardType,
    this.obscureText = false,
    this.suffix,
    this.autofillHints,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      autofillHints: autofillHints,
      style: TextStyle(
        color: cs.onSurface,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
          color: Color(0xFF98A2B3),
          fontWeight: FontWeight.w600,
        ),
        prefixIcon: Icon(prefixIcon, color: cs.onSurfaceVariant, size: 23),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 48,
          minHeight: 52,
        ),
        suffixIcon: suffix,
        filled: true,
        fillColor: Theme.of(context).brightness == Brightness.dark
            ? cs.surfaceContainerHighest
            : const Color(0xFFF8FBFF),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFD5DEEC)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFD5DEEC)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _brandBlue, width: 1.4),
        ),
      ),
    );
  }
}

class _LoginSeparator extends StatelessWidget {
  const _LoginSeparator();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(child: Divider(color: cs.outlineVariant, height: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'atau masuk lebih cepat',
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(child: Divider(color: cs.outlineVariant, height: 1)),
      ],
    );
  }
}

/// CTA login alternatif via OTP WhatsApp (Fonnte gateway).
///
/// Per user spec: hapus tombol "Masuk dengan Google" + icon G, ganti
/// jadi "Masuk dengan OTP WhatsApp" + icon WA hijau. Tap → push ke
/// `/member/login-otp` (LoginOtpScreen) yang handle 2-step flow:
/// 1. Input nomor HP → server kirim 6-digit OTP via Fonnte
/// 2. Input OTP → verify + session creation
///
/// Backend OTP path:
/// - POST /api/auth/member-login-otp/request — pakai sendCustomMessage
///   dari lib/whatsapp.js → callFonnte() dengan FONNTE_TOKEN env.
/// - POST /api/auth/member-login-otp/verify — bcrypt compare + JWT
///   session token.
///
/// Pastikan FONNTE_TOKEN env Vercel sudah di-set (Production + Preview
/// + Development) untuk OTP delivery jalan di production.
class _WhatsAppOtpLoginButton extends StatelessWidget {
  final VoidCallback onTap;

  const _WhatsAppOtpLoginButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: SizedBox(
          width: 26,
          height: 26,
          child: Center(
            child: SvgPicture.asset(
              'assets/icons/whatsapp.svg',
              width: 24,
              height: 24,
            ),
          ),
        ),
        label: const Text('Masuk dengan OTP WhatsApp'),
        style: OutlinedButton.styleFrom(
          foregroundColor: cs.onSurface,
          side: BorderSide(color: cs.outlineVariant, width: 1.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _RegisterBenefitCard extends StatelessWidget {
  final VoidCallback onRegister;

  const _RegisterBenefitCard({required this.onRegister});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: _brandBlueDark.withValues(alpha: 0.07),
            blurRadius: 22,
            offset: const Offset(0, 11),
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 78,
            height: 62,
            child: Image.asset(
              'assets/images/login_register_benefit.png',
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.card_giftcard_rounded,
                color: _brandBlue,
                size: 44,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: onRegister,
                  behavior: HitTestBehavior.opaque,
                  child: Text.rich(
                    TextSpan(
                      text: 'Belum punya akun? ',
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                      children: const [
                        TextSpan(
                          text: 'Daftar gratis',
                          style: TextStyle(
                            color: _brandBlue,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Kumpulkan poin dan dapatkan voucher khusus member Natalo.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton(
            onPressed: onRegister,
            style: OutlinedButton.styleFrom(
              foregroundColor: _brandBlue,
              side: const BorderSide(color: _brandBlue, width: 1.2),
              minimumSize: const Size(118, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
            child: const Text('Daftar gratis'),
          ),
        ],
      ),
    );
  }
}

class _SecurityNote extends StatelessWidget {
  const _SecurityNote();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.lock_rounded, color: _brandBlue, size: 16),
        const SizedBox(width: 6),
        Flexible(
          child: Text.rich(
            TextSpan(
              text: 'Data akun kamu aman bersama ',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              children: const [
                TextSpan(
                  text: 'Natalo.',
                  style: TextStyle(color: _brandBlue),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

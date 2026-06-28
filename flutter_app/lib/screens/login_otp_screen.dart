import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_client.dart';
import '../services/app_analytics.dart';
import '../services/app_crashlytics.dart';
import '../services/auth_service.dart';
import '../services/push_notification_service.dart';
import '../state/cart_store.dart';
import '../state/favorite_store.dart';
import '../state/member_store.dart';
import '../utils/haptics.dart';
import '../widgets/loading_button.dart';

// ── Design tokens — match login_screen.dart Natalo visual family ──
const _nataloBlue = Color(0xFF0787F5);
const _nataloBlueDark = Color(0xFF075FCC);
const _whatsappGreen = Color(0xFF22C55E);

const _waInfoBg = Color(0xFFE8F8EC);
const _waInfoBorder = Color(0xFFBBE5C5);

const _resendCooldownSeconds = 30;

/// Login passwordless via OTP WhatsApp. 2-step flow:
/// 1. User input nomor HP → tap "Kirim OTP" → server kirim 6-digit code via WA
/// 2. User input OTP → tap "Verifikasi" → server set session + return user
///
/// Match endpoint:
///   POST /api/auth/member-login-otp/request  → kirim OTP
///   POST /api/auth/member-login-otp/verify   → verify + create session
class LoginOtpScreen extends StatefulWidget {
  const LoginOtpScreen({super.key});

  @override
  State<LoginOtpScreen> createState() => _LoginOtpScreenState();
}

enum _OtpStep { phone, code }

class _LoginOtpScreenState extends State<LoginOtpScreen> {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _phoneFocus = FocusNode();
  final _otpFocus = FocusNode();

  _OtpStep _step = _OtpStep.phone;
  bool _loading = false;
  String? _maskedPhone;
  String? _normalizedPhone;
  int _resendSeconds = 0;
  Timer? _resendTimer;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _phoneFocus.dispose();
    _otpFocus.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  String _maskPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 6) return phone;
    final head = digits.substring(0, 3);
    final tail = digits.substring(digits.length - 3);
    return '$head****$tail';
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = _resendCooldownSeconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_resendSeconds <= 1) {
        timer.cancel();
        setState(() => _resendSeconds = 0);
      } else {
        setState(() => _resendSeconds -= 1);
      }
    });
  }

  Future<void> _requestOtp({bool isResend = false}) async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty || phone.length < 8) {
      AppHaptics.warning();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Masukkan nomor WhatsApp yang valid.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    AppHaptics.tap();
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    try {
      await authService.requestLoginOtp(phone: phone);
      if (!mounted) return;
      AppHaptics.success();
      setState(() {
        _step = _OtpStep.code;
        _maskedPhone = _maskPhone(phone);
        _normalizedPhone = phone;
      });
      _startResendCooldown();
      // Focus OTP field setelah transisi state.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _otpFocus.requestFocus();
      });
      if (isResend) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kode OTP baru dikirim ke WhatsApp kamu.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      AppHaptics.warning();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_humanizeError(error)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();
    final phone = _normalizedPhone ?? _phoneController.text.trim();
    if (otp.length != 6) {
      AppHaptics.warning();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kode OTP harus 6 digit.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    AppHaptics.tap();
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    try {
      final profile = await authService.verifyLoginOtp(
        phone: phone,
        otp: otp,
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
      pushNotificationService.registerWithServer();
      AppAnalytics.setUserId(profile.email);
      AppAnalytics.logEvent('login', {'method': 'whatsapp_otp'});
      AppCrashlytics.setUserId(profile.email);

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_humanizeError(error)),
          behavior: SnackBarBehavior.floating,
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

  String _humanizeError(Object error) {
    if (error is ApiException) {
      if (error.statusCode == 429) {
        return 'Terlalu banyak percobaan. Coba lagi nanti.';
      }
      if (error.statusCode != null && error.statusCode! >= 500) {
        return 'Server sedang bermasalah. Coba lagi nanti.';
      }
      return error.message;
    }
    final raw = error.toString().toLowerCase();
    if (raw.contains('socketexception') || raw.contains('failed host lookup')) {
      return 'Tidak bisa connect ke server. Cek koneksi internet kamu.';
    }
    if (raw.contains('timeout')) {
      return 'Server butuh waktu lebih lama. Coba lagi sebentar.';
    }
    return 'Login OTP gagal: $error';
  }

  void _backToPhoneStep() {
    AppHaptics.tap();
    setState(() {
      _step = _OtpStep.phone;
      _otpController.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _phoneFocus.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
          tooltip: 'Kembali',
          onPressed: () {
            AppHaptics.tap();
            if (_step == _OtpStep.code) {
              _backToPhoneStep();
            } else if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              Navigator.pushReplacementNamed(context, '/member/login');
            }
          },
        ),
        title: Text(
          'Login via WhatsApp',
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
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            children: [
              const _OtpHeroSection(),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.05, 0),
                        end: Offset.zero,
                      ).animate(anim),
                      child: child,
                    ),
                  ),
                  child: _step == _OtpStep.phone
                      ? _PhoneStep(
                          key: const ValueKey('phone'),
                          controller: _phoneController,
                          focusNode: _phoneFocus,
                          loading: _loading,
                          onSubmit: () => _requestOtp(),
                        )
                      : _CodeStep(
                          key: const ValueKey('code'),
                          controller: _otpController,
                          focusNode: _otpFocus,
                          loading: _loading,
                          maskedPhone: _maskedPhone ?? '',
                          resendSeconds: _resendSeconds,
                          onVerify: _verifyOtp,
                          onResend: () => _requestOtp(isResend: true),
                          onChangePhone: _backToPhoneStep,
                        ),
                ),
              ),
              const SizedBox(height: 18),
              _BackToPasswordLink(
                onTap: () {
                  AppHaptics.tap();
                  Navigator.pushReplacementNamed(context, '/member/login');
                },
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HERO SECTION — gradient + WhatsApp icon halo
// ─────────────────────────────────────────────────────────────────────────────

class _OtpHeroSection extends StatelessWidget {
  const _OtpHeroSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFE6F2FF), Color(0xFFF1F7FF)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _whatsappGreen.withValues(alpha: 0.20),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: const Icon(
              Icons.chat_rounded,
              color: _whatsappGreen,
              size: 46,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Masuk via OTP WhatsApp',
            textAlign: TextAlign.center,
            style: TextStyle(
              // Hero memakai gradient terang tetap (di-keep), jadi teks
              // gelap dipertahankan agar tetap terbaca di light gradient.
              color: Color(0xFF101828),
              fontSize: 22,
              fontWeight: FontWeight.w900,
              height: 1.2,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'Tanpa password. Kami kirim kode 6-digit ke WhatsApp kamu untuk verifikasi.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF667085),
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP 1 — input nomor HP + tombol "Kirim OTP"
// ─────────────────────────────────────────────────────────────────────────────

class _PhoneStep extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool loading;
  final VoidCallback onSubmit;

  const _PhoneStep({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.loading,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: _nataloBlueDark.withValues(alpha: 0.08),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nomor WhatsApp',
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 56,
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.telephoneNumber],
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d+\s-]')),
                LengthLimitingTextInputFormatter(20),
              ],
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: 'Contoh: 08123456789',
                hintStyle: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                isDense: true,
                filled: true,
                fillColor: Theme.of(context).brightness == Brightness.dark
                    ? cs.surfaceContainerHighest
                    : const Color(0xFFF8FAFD),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 18,
                ),
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(left: 14, right: 10),
                  child: Icon(
                    Icons.phone_iphone_rounded,
                    color: _nataloBlue,
                    size: 22,
                  ),
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 46,
                  minHeight: 46,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide(color: cs.outlineVariant),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide(color: cs.outlineVariant),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(color: _nataloBlue, width: 1.5),
                ),
              ),
              onSubmitted: (_) => onSubmit(),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _waInfoBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _waInfoBorder),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.chat_rounded,
                  color: _whatsappGreen,
                  size: 20,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Pastikan nomor WhatsApp kamu aktif dan sama dengan nomor yang terdaftar di akun Natalo.',
                    style: TextStyle(
                      color: Color(0xFF14532D),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          LoadingButton(
            onPressed: onSubmit,
            loading: loading,
            style: ElevatedButton.styleFrom(
              backgroundColor: _nataloBlue,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(56),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.2,
              ),
            ),
            icon: Icons.send_rounded,
            child: const Text('Kirim Kode OTP'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP 2 — input OTP 6-digit + verify + resend countdown
// ─────────────────────────────────────────────────────────────────────────────

class _CodeStep extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool loading;
  final String maskedPhone;
  final int resendSeconds;
  final VoidCallback onVerify;
  final VoidCallback onResend;
  final VoidCallback onChangePhone;

  const _CodeStep({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.loading,
    required this.maskedPhone,
    required this.resendSeconds,
    required this.onVerify,
    required this.onResend,
    required this.onChangePhone,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: _nataloBlueDark.withValues(alpha: 0.08),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text.rich(
            TextSpan(
              text: 'Kode 6-digit dikirim ke WhatsApp ',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
              children: [
                TextSpan(
                  text: maskedPhone,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const TextSpan(text: '. Berlaku 5 menit.'),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 60,
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              textAlign: TextAlign.center,
              autofocus: true,
              // #1 autofill: auto-isi kode OTP dari SMS/WhatsApp (Android).
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 24,
                fontWeight: FontWeight.w900,
                letterSpacing: 8,
              ),
              decoration: InputDecoration(
                hintText: '------',
                hintStyle: const TextStyle(
                  color: Color(0xFFCBD5E1),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 8,
                ),
                isDense: true,
                filled: true,
                fillColor: Theme.of(context).brightness == Brightness.dark
                    ? cs.surfaceContainerHighest
                    : const Color(0xFFF8FAFD),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide(color: cs.outlineVariant),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide(color: cs.outlineVariant),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(color: _nataloBlue, width: 1.5),
                ),
              ),
              onChanged: (value) {
                if (value.length == 6 && !loading) onVerify();
              },
              onSubmitted: (_) => onVerify(),
            ),
          ),
          const SizedBox(height: 18),
          LoadingButton(
            onPressed: onVerify,
            loading: loading,
            style: ElevatedButton.styleFrom(
              backgroundColor: _nataloBlue,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(56),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            child: const Text('Verifikasi & Masuk'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: loading ? null : onChangePhone,
                  icon: Icon(
                    Icons.edit_rounded,
                    size: 16,
                    color: cs.onSurfaceVariant,
                  ),
                  label: Text(
                    'Ubah nomor',
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextButton(
                  onPressed: (resendSeconds > 0 || loading) ? null : onResend,
                  child: Text(
                    resendSeconds > 0
                        ? 'Kirim ulang ($resendSeconds s)'
                        : 'Kirim ulang OTP',
                    style: TextStyle(
                      color:
                          resendSeconds > 0 ? cs.onSurfaceVariant : _nataloBlue,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FOOTER — link balik ke login password
// ─────────────────────────────────────────────────────────────────────────────

class _BackToPasswordLink extends StatelessWidget {
  final VoidCallback onTap;

  const _BackToPasswordLink({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: _nataloBlue,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        minimumSize: const Size(44, 44),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text.rich(
        TextSpan(
          text: 'Punya password? ',
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          children: const [
            TextSpan(
              text: 'Masuk dengan password',
              style: TextStyle(
                color: _nataloBlue,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

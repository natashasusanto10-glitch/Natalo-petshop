import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../utils/haptics.dart';
import '../widgets/loading_button.dart';

// ── Design tokens (match login_screen.dart Natalo visual family) ──
const _nataloBlue = Color(0xFF0787F5);
const _nataloBlueDark = Color(0xFF075FCC);
const _darkNavy = Color(0xFF101828);
const _textSecondary = Color(0xFF667085);
const _softBlueBg = Color(0xFFF1F7FF);
const _borderSoft = Color(0xFFE0E7F0);
const _heroGradientTop = Color(0xFFE6F2FF);
const _heroGradientBottom = Color(0xFFF1F7FF);

// Soft yellow info box tokens (reset rules).
const _warningBg = Color(0xFFFFF8E6);
const _warningBorder = Color(0xFFFAD77A);
const _warningText = Color(0xFF8A4B16);
const _warningIcon = Color(0xFFF59E0B);

// Success state palette.
const _successGreen = Color(0xFF16A34A);
const _successBg = Color(0xFFE6F8EE);
const _successBorder = Color(0xFFBBF0CD);

const _heroAsset = 'assets/images/forgot_password_hero_petshop.png';

/// Forgot password screen — premium redesign konsisten dengan visual family
/// halaman Masuk Member Natalo. Fokus visual: keamanan akun, email reset,
/// lock/key. Auth flow tetap memakai service existing
/// (`authService.forgotPassword`) — server selalu return sukses untuk anti
/// enumeration attack.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _emailFocus = FocusNode();
  bool _loading = false;
  bool _submitted = false;
  String? _submittedEmail;

  @override
  void dispose() {
    _emailController.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      AppHaptics.warning();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Masukkan email yang valid.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    AppHaptics.tap();
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    try {
      await authService.forgotPassword(email);
      if (!mounted) return;
      AppHaptics.success();
      setState(() {
        _submitted = true;
        _submittedEmail = email;
      });
    } catch (error) {
      if (!mounted) return;
      AppHaptics.warning();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal kirim link reset: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    if (_loading) return;
    // Reset state ke form supaya user lihat loading di tombol utama lagi.
    setState(() => _submitted = false);
    await _submit();
  }

  void _backToLogin() {
    AppHaptics.tap();
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacementNamed(context, '/member/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _softBlueBg,
      resizeToAvoidBottomInset: true,
      appBar: const _ForgotPasswordHeader(),
      body: SafeArea(
        top: false,
        bottom: true,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            children: [
              const _ForgotPasswordHeroSection(),
              const _ForgotPasswordCopy(),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.04),
                        end: Offset.zero,
                      ).animate(anim),
                      child: child,
                    ),
                  ),
                  child: _submitted
                      ? _ForgotPasswordSuccessCard(
                          key: const ValueKey('success'),
                          email: _submittedEmail ?? _emailController.text.trim(),
                          loading: _loading,
                          onBackToLogin: _backToLogin,
                          onResend: _resend,
                        )
                      : _ForgotPasswordFormCard(
                          key: const ValueKey('form'),
                          emailController: _emailController,
                          emailFocus: _emailFocus,
                          loading: _loading,
                          onSubmit: _submit,
                        ),
                ),
              ),
              const SizedBox(height: 18),
              _BackToLoginLink(onTap: _backToLogin),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HEADER (AppBar)
// ─────────────────────────────────────────────────────────────────────────────

class _ForgotPasswordHeader extends StatelessWidget
    implements PreferredSizeWidget {
  const _ForgotPasswordHeader();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.white,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, color: _darkNavy),
        tooltip: 'Kembali',
        onPressed: () {
          AppHaptics.tap();
          if (Navigator.canPop(context)) {
            Navigator.pop(context);
          } else {
            Navigator.pushReplacementNamed(context, '/member/login');
          }
        },
      ),
      title: const Text(
        'Lupa Password',
        style: TextStyle(
          color: _darkNavy,
          fontSize: 18,
          fontWeight: FontWeight.w900,
        ),
      ),
      centerTitle: true,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HERO SECTION — gradient background + image asset + secondary icons
// ─────────────────────────────────────────────────────────────────────────────

class _ForgotPasswordHeroSection extends StatelessWidget {
  const _ForgotPasswordHeroSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_heroGradientTop, _heroGradientBottom],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 188,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Soft halo behind hero — gives the illustration depth.
                Positioned.fill(
                  child: Center(
                    child: Container(
                      width: 196,
                      height: 196,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0.9),
                            Colors.white.withValues(alpha: 0.0),
                          ],
                          stops: const [0.45, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
                // Hero image — realistic dog/cat + envelope/lock/key icons.
                // Fallback ke icon stack kalau asset belum tersedia (graceful
                // degrade supaya build tidak break sebelum image di-drop).
                Image.asset(
                  _heroAsset,
                  height: 180,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const _HeroFallback(),
                ),
                // Secondary floating icons (envelope + lock) — sebagai dekorasi
                // tambahan untuk reinforce konteks keamanan email. Tetap muncul
                // walau image asset valid supaya hero terasa lebih kaya.
                const Positioned(
                  top: 6,
                  right: 18,
                  child: _FloatingIconBadge(
                    icon: Icons.mail_rounded,
                    color: _nataloBlue,
                  ),
                ),
                const Positioned(
                  bottom: 12,
                  left: 22,
                  child: _FloatingIconBadge(
                    icon: Icons.vpn_key_rounded,
                    color: Color(0xFFF59E0B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Fallback hero ketika asset image belum ada — komposisi icon yang tetap
/// terasa premium (lock besar + envelope + key) sehingga halaman tidak
/// kosong saat dev belum drop file final `forgot_password_hero_petshop.png`.
class _HeroFallback extends StatelessWidget {
  const _HeroFallback();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      height: 180,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 132,
            height: 132,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _nataloBlueDark.withValues(alpha: 0.18),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
          ),
          Container(
            width: 104,
            height: 104,
            decoration: const BoxDecoration(
              color: Color(0xFFEAF4FF),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.lock_rounded,
              color: _nataloBlue,
              size: 52,
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatingIconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _FloatingIconBadge({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.22),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HERO COPY — headline + subtitle di bawah ilustrasi
// ─────────────────────────────────────────────────────────────────────────────

class _ForgotPasswordCopy extends StatelessWidget {
  const _ForgotPasswordCopy();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(28, 6, 28, 0),
      child: Column(
        children: [
          Text(
            'Reset Password Akun Natalo',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _darkNavy,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              height: 1.18,
              letterSpacing: -0.2,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Masukkan email yang kamu pakai daftar. Kami akan kirim link aman untuk reset password kamu.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _textSecondary,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FORM CARD — premium card with email input + info box + primary button
// ─────────────────────────────────────────────────────────────────────────────

class _ForgotPasswordFormCard extends StatelessWidget {
  final TextEditingController emailController;
  final FocusNode emailFocus;
  final bool loading;
  final VoidCallback onSubmit;

  const _ForgotPasswordFormCard({
    super.key,
    required this.emailController,
    required this.emailFocus,
    required this.loading,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: _borderSoft),
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
          const Text(
            'Email',
            style: TextStyle(
              color: _darkNavy,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          _ForgotPasswordEmailField(
            controller: emailController,
            focusNode: emailFocus,
            onSubmit: onSubmit,
          ),
          const SizedBox(height: 14),
          const _ForgotPasswordInfoBox(
            message:
                'Link reset password berlaku 1 jam. Kamu bisa meminta link maksimal 3× per jam.',
          ),
          const SizedBox(height: 20),
          _ResetPasswordButton(loading: loading, onPressed: onSubmit),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EMAIL FIELD — 56px height + envelope icon prefix + rounded 18 radius
// ─────────────────────────────────────────────────────────────────────────────

class _ForgotPasswordEmailField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSubmit;

  const _ForgotPasswordEmailField({
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.done,
        autocorrect: false,
        enableSuggestions: false,
        style: const TextStyle(
          color: _darkNavy,
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          hintText: 'Email yang terdaftar di akun kamu',
          hintStyle: const TextStyle(
            color: Color(0xFF9CA3AF),
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
          isDense: true,
          filled: true,
          fillColor: const Color(0xFFF8FAFD),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 18,
          ),
          prefixIcon: const Padding(
            padding: EdgeInsets.only(left: 14, right: 10),
            child: Icon(
              Icons.mail_outline_rounded,
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
            borderSide: const BorderSide(color: _borderSoft),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: _borderSoft),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: _nataloBlue, width: 1.5),
          ),
        ),
        onSubmitted: (_) => onSubmit(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// INFO BOX — soft yellow notification for reset link rules
// ─────────────────────────────────────────────────────────────────────────────

class _ForgotPasswordInfoBox extends StatelessWidget {
  final String message;

  const _ForgotPasswordInfoBox({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: _warningBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _warningBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: _warningIcon,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: _warningText,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
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
// RESET PASSWORD BUTTON — full-width 56px pill Natalo blue
// ─────────────────────────────────────────────────────────────────────────────

class _ResetPasswordButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onPressed;

  const _ResetPasswordButton({
    required this.loading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return LoadingButton(
      onPressed: onPressed,
      loading: loading,
      style: ElevatedButton.styleFrom(
        backgroundColor: _nataloBlue,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(56),
        elevation: 0,
        shadowColor: _nataloBlueDark.withValues(alpha: 0.4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.2,
        ),
      ),
      child: const Text('Kirim Link Reset'),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SUCCESS CARD — confirmation state after submit
// ─────────────────────────────────────────────────────────────────────────────

class _ForgotPasswordSuccessCard extends StatelessWidget {
  final String email;
  final bool loading;
  final VoidCallback onBackToLogin;
  final VoidCallback onResend;

  const _ForgotPasswordSuccessCard({
    super.key,
    required this.email,
    required this.loading,
    required this.onBackToLogin,
    required this.onResend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: _successBorder),
        boxShadow: [
          BoxShadow(
            color: _successGreen.withValues(alpha: 0.10),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        children: [
          // Animated success check halo.
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: _successBg,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _successGreen.withValues(alpha: 0.18),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.mark_email_read_rounded,
              color: _successGreen,
              size: 38,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Cek email kamu',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _darkNavy,
              fontSize: 19,
              fontWeight: FontWeight.w900,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              text: 'Kami sudah kirim link reset password ke ',
              style: const TextStyle(
                color: _textSecondary,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                height: 1.55,
              ),
              children: [
                TextSpan(
                  text: email,
                  style: const TextStyle(
                    color: _darkNavy,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const TextSpan(
                  text:
                      ' (jika terdaftar). Buka email tersebut dan ikuti instruksinya.',
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              'Tidak menerima email dalam 5 menit? Cek folder Spam / Promosi.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Primary CTA: Kembali ke Masuk.
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onBackToLogin,
              style: ElevatedButton.styleFrom(
                backgroundColor: _nataloBlue,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(54),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              child: const Text('Kembali ke Masuk'),
            ),
          ),
          const SizedBox(height: 10),
          // Secondary CTA: Kirim ulang link.
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: loading ? null : onResend,
              style: OutlinedButton.styleFrom(
                foregroundColor: _nataloBlue,
                minimumSize: const Size.fromHeight(50),
                side: const BorderSide(color: _borderSoft, width: 1.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
              child: loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation(_nataloBlue),
                      ),
                    )
                  : const Text('Kirim ulang link'),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BACK TO LOGIN LINK — footer text link
// ─────────────────────────────────────────────────────────────────────────────

class _BackToLoginLink extends StatelessWidget {
  final VoidCallback onTap;

  const _BackToLoginLink({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: _nataloBlue,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        minimumSize: const Size(44, 44),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: const Text.rich(
        TextSpan(
          text: 'Ingat password? ',
          style: TextStyle(
            color: _textSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          children: [
            TextSpan(
              text: 'Kembali ke Masuk',
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../utils/haptics.dart';
import '../utils/phone_formatter.dart';

const _brandBlue = Color(0xFF0787F5);
const _brandBlueDark = Color(0xFF075FCC);
const _darkNavy = Color(0xFF101828);
const _textSecondary = Color(0xFF667085);
const _softBlueBg = Color(0xFFF1F7FF);
const _softBlueCard = Color(0xFFEAF5FF);
const _borderSoft = Color(0xFFE0E7F0);

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _otpController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _loading = false;
  bool _otpSent = false; // step 1 sukses → tampilkan field OTP
  // Resend OTP countdown — disabled selama N detik setelah kirim OTP
  // supaya user tidak spam request. Reset ke 60 setiap kali OTP terkirim
  // (step 1 sukses + resend tap). 0 = enabled, >0 = disabled (display "Xs").
  int _resendCountdown = 0;
  Timer? _resendTimer;
  bool _resendingOtp = false;

  @override
  void initState() {
    super.initState();
    for (final controller in [
      _nameController,
      _emailController,
      _phoneController,
      _passwordController,
      _confirmController,
      _otpController,
    ]) {
      controller.addListener(_onFormChanged);
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _nameController,
      _emailController,
      _phoneController,
      _passwordController,
      _confirmController,
      _otpController,
    ]) {
      controller.removeListener(_onFormChanged);
    }
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _otpController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  /// Start 60-second cooldown setelah OTP terkirim (step 1 sukses atau
  /// resend tap). Selama countdown >0, button resend disabled +
  /// tampilkan "Tunggu Xs". Timer.periodic 1 detik, auto-cancel saat 0.
  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendCountdown = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_resendCountdown <= 1) {
        t.cancel();
        setState(() => _resendCountdown = 0);
      } else {
        setState(() => _resendCountdown -= 1);
      }
    });
  }

  /// Resend OTP — panggil register endpoint mode step-1 (otp=null) supaya
  /// backend generate + kirim ulang kode. Reset cooldown setelah sukses.
  Future<void> _resendOtp() async {
    if (_resendCountdown > 0 || _resendingOtp) return;
    AppHaptics.tap();
    setState(() => _resendingOtp = true);
    try {
      final phoneRaw = _phoneController.text.replaceAll(RegExp(r'[^\d+]'), '');
      await authService.register(
        name: _nameController.text,
        email: _emailController.text,
        phone: phoneRaw,
        password: _passwordController.text,
        confirmPassword: _confirmController.text,
        otp: null, // null = step 1, kirim OTP baru
      );
      if (!mounted) return;
      AppHaptics.success();
      _startResendCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kode OTP baru sudah dikirim ke email & WhatsApp.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      AppHaptics.warning();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_friendlyRegisterError(error)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _resendingOtp = false);
    }
  }

  void _onFormChanged() {
    if (mounted) setState(() {});
  }

  bool get _hasValidEmail {
    final email = _emailController.text.trim();
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
  }

  bool get _hasValidPhone =>
      _phoneController.text.replaceAll(RegExp(r'[^\d]'), '').length >= 8;

  bool get _canSubmit {
    final baseValid = _nameController.text.trim().isNotEmpty &&
        _hasValidEmail &&
        _hasValidPhone &&
        _passwordController.text.length >= 8 &&
        _passwordController.text == _confirmController.text;

    if (!_otpSent) return baseValid;
    return baseValid && _otpController.text.trim().length >= 4;
  }

  Future<void> _onPrimary() async {
    AppHaptics.tap();
    if (!_validate()) return;
    setState(() => _loading = true);
    try {
      // Strip non-digit dari phone — PhoneFormatter kasih dash buat readable,
      // tapi backend expect digit format (+62812... atau 0812...).
      final phoneRaw = _phoneController.text.replaceAll(RegExp(r'[^\d+]'), '');
      final result = await authService.register(
        name: _nameController.text,
        email: _emailController.text,
        phone: phoneRaw,
        password: _passwordController.text,
        confirmPassword: _confirmController.text,
        otp: _otpSent ? _otpController.text : null,
      );
      if (!mounted) return;

      if (result == null) {
        // Step 1 sukses — OTP terkirim. Start 60s cooldown supaya user
        // tidak bisa spam resend langsung; button "Kirim Ulang Kode" baru
        // bisa di-tap setelah countdown selesai.
        AppHaptics.success();
        setState(() => _otpSent = true);
        _startResendCooldown();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Kode OTP dikirim ke email dan WhatsApp kamu. Masukkan satu kode yang sama.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      // Step 2 sukses — user dibuat. User tetap login manual supaya session
      // dan cart sync memakai flow login member yang sama.
      AppHaptics.success();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Akun berhasil dibuat. Silakan login.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pushReplacementNamed(context, '/member/login');
    } catch (error) {
      if (!mounted) return;
      AppHaptics.warning();
      final message = _friendlyRegisterError(error);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _friendlyRegisterError(Object error) {
    if (error is ApiException) {
      // Detect timeout — ApiException wrap TimeoutException dari .timeout()
      // jadi message string "TimeoutException after 0:00:10.000000:
      // Future not completed". Map ke pesan friendly khusus supaya user
      // tahu ini bukan error fatal — tinggal coba lagi.
      final msg = error.message;
      final isTimeout = msg.contains('TimeoutException') ||
          msg.contains('timeout') ||
          msg.contains('Timeout');
      if (isTimeout) {
        if (!_otpSent) {
          return 'Server lambat saat mengirim OTP. Coba lagi sebentar.';
        }
        return 'Server lambat saat mendaftar. Coba lagi sebentar.';
      }
      if (error.isNetworkError) {
        if (!_otpSent) {
          return 'Koneksi sedang lambat saat mengirim OTP. Coba lagi sebentar lagi.';
        }
        return 'Koneksi sedang lambat saat mendaftar. Coba lagi sebentar lagi.';
      }
      return error.message;
    }
    // Fallback untuk non-ApiException — generic friendly message.
    return 'Terjadi kendala. Coba lagi sebentar lagi.';
  }

  bool _validate() {
    if (_nameController.text.trim().isEmpty) {
      _showError('Nama lengkap harus diisi.');
      return false;
    }
    if (_emailController.text.trim().isEmpty) {
      _showError('Email wajib diisi.');
      return false;
    }
    if (!_hasValidEmail) {
      _showError('Format email belum sesuai.');
      return false;
    }
    // Validate digit count (skip dashes/spaces dari PhoneFormatter).
    if (_phoneController.text.trim().isEmpty) {
      _showError('Nomor handphone wajib diisi.');
      return false;
    }
    if (!_hasValidPhone) {
      _showError('Nomor handphone belum sesuai.');
      return false;
    }
    if (_passwordController.text.length < 8) {
      _showError('Password minimal 8 karakter.');
      return false;
    }
    if (_passwordController.text != _confirmController.text) {
      _showError('Konfirmasi password tidak sama.');
      return false;
    }
    if (_otpSent && _otpController.text.trim().length < 4) {
      _showError('Masukkan kode OTP yang dikirim ke email / WhatsApp.');
      return false;
    }
    return true;
  }

  void _showError(String msg) {
    AppHaptics.warning();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _softBlueBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: _darkNavy),
          onPressed: () => Navigator.pushReplacementNamed(
            context,
            '/member/login',
          ),
        ),
        title: const Text(
          'Daftar Member',
          style: TextStyle(
            color: _darkNavy,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          children: [
            const _RegisterHeroSection(),
            const _RegisterBenefitChips(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: _borderSoft),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.055),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _FieldLabel('Nama lengkap'),
                    _RegisterTextField(
                      controller: _nameController,
                      hint: 'Contoh: Andi Setiawan',
                      icon: Icons.person_outline_rounded,
                    ),
                    const SizedBox(height: 14),
                    const _FieldLabel('Email'),
                    _RegisterTextField(
                      controller: _emailController,
                      hint: 'Contoh: nama@email.com',
                      icon: Icons.mail_outline_rounded,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 14),
                    const _FieldLabel('No. handphone'),
                    _RegisterTextField(
                      controller: _phoneController,
                      hint: 'Contoh: 0812-3456-789',
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [PhoneFormatter()],
                    ),
                    const SizedBox(height: 14),
                    const _OtpInfoBox(),
                    const SizedBox(height: 14),
                    const _FieldLabel('Password'),
                    _RegisterTextField(
                      controller: _passwordController,
                      hint: 'Minimal 8 karakter',
                      icon: Icons.lock_outline_rounded,
                      obscure: _obscurePassword,
                      onToggleObscure: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    const SizedBox(height: 14),
                    const _FieldLabel('Konfirmasi password'),
                    _RegisterTextField(
                      controller: _confirmController,
                      hint: 'Ulangi password yang sama',
                      icon: Icons.lock_outline_rounded,
                      obscure: _obscureConfirm,
                      onToggleObscure: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                    if (_otpSent) ...[
                      const SizedBox(height: 14),
                      const _FieldLabel('Kode OTP'),
                      _RegisterTextField(
                        controller: _otpController,
                        hint: 'Masukkan 6 digit kode',
                        icon: Icons.password_rounded,
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 8),
                      // Destination hint — confirmasi ke user OTP dikirim
                      // ke mana, supaya tidak bingung buka email vs WA.
                      // Phone di-mask partial (0812***4567) untuk privacy
                      // (kalau screen di-screenshot tidak expose nomor full).
                      _OtpDestinationHint(
                        email: _emailController.text.trim(),
                        phone: _phoneController.text.trim(),
                      ),
                      const SizedBox(height: 10),
                      // Resend OTP row — disabled selama countdown 60s.
                      _ResendOtpRow(
                        countdown: _resendCountdown,
                        loading: _resendingOtp,
                        onTap: _resendOtp,
                      ),
                    ],
                    const SizedBox(height: 22),
                    _RegisterSubmitButton(
                      onPressed: _canSubmit ? _onPrimary : null,
                      loading: _loading,
                      otpSent: _otpSent,
                    ),
                  ],
                ),
              ),
            ),
            const _RegisterMemberBenefitCard(),
            _BackToLoginLink(
              onTap: () =>
                  Navigator.pushReplacementNamed(context, '/member/login'),
            ),
            SizedBox(height: 24 + MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;
  const _FieldLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        style: const TextStyle(
          color: _darkNavy,
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _RegisterHeroSection extends StatelessWidget {
  const _RegisterHeroSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, _softBlueBg],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 10),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: AspectRatio(
              aspectRatio: 853 / 385,
              child: Image.asset(
                'assets/images/register_member_hero_petshop.png',
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const _HeroFallback(),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Daftar Member Natalo',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _darkNavy,
                fontSize: 30,
                fontWeight: FontWeight.w900,
                height: 1.08,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 30),
            child: Text(
              'Gratis! Kumpulkan poin dan dapatkan voucher khusus member.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _textSecondary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                height: 1.38,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroFallback extends StatelessWidget {
  const _HeroFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_brandBlue, _brandBlueDark],
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: const Center(
        child: Icon(Icons.pets_rounded, color: Colors.white, size: 76),
      ),
    );
  }
}

class _RegisterBenefitChips extends StatelessWidget {
  const _RegisterBenefitChips();

  @override
  Widget build(BuildContext context) {
    const items = [
      _BenefitChipData(
        icon: Icons.pets_rounded,
        title: 'Poin Belanja',
        subtitle: 'Kumpulkan poin setiap transaksi',
      ),
      _BenefitChipData(
        icon: Icons.confirmation_number_rounded,
        title: 'Voucher Member',
        subtitle: 'Dapatkan voucher khusus member',
      ),
      _BenefitChipData(
        icon: Icons.local_offer_rounded,
        title: 'Promo Khusus',
        subtitle: 'Harga spesial untuk member',
      ),
    ];

    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) => _BenefitChip(item: items[index]),
      ),
    );
  }
}

class _BenefitChipData {
  final IconData icon;
  final String title;
  final String subtitle;

  const _BenefitChipData({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
}

class _BenefitChip extends StatelessWidget {
  final _BenefitChipData item;

  const _BenefitChip({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 190,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _borderSoft),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.045),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_brandBlue, _brandBlueDark],
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(item.icon, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _darkNavy,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  item.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
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

class _RegisterTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool obscure;
  final VoidCallback? onToggleObscure;
  final List<TextInputFormatter>? inputFormatters;

  const _RegisterTextField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.obscure = false,
    this.onToggleObscure,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscure,
      inputFormatters: inputFormatters,
      style: const TextStyle(
        color: _darkNavy,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
          color: Color(0xFF98A2B3),
          fontWeight: FontWeight.w600,
        ),
        prefixIcon: Icon(icon, color: const Color(0xFF98A2B3), size: 22),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        suffixIcon: onToggleObscure == null
            ? null
            : IconButton(
                onPressed: onToggleObscure,
                tooltip:
                    obscure ? 'Tampilkan password' : 'Sembunyikan password',
                icon: Icon(
                  obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: const Color(0xFF98A2B3),
                ),
              ),
        filled: true,
        fillColor: const Color(0xFFF8FBFF),
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
          borderSide: const BorderSide(color: _brandBlue, width: 1.5),
        ),
      ),
    );
  }
}

class _RegisterSubmitButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool loading;
  final bool otpSent;

  const _RegisterSubmitButton({
    required this.onPressed,
    required this.loading,
    required this.otpSent,
  });

  @override
  Widget build(BuildContext context) {
    final label = loading
        ? (otpSent ? 'Mendaftarkan...' : 'Mengirim OTP...')
        : (otpSent ? 'Daftar' : 'Kirim OTP');

    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: _brandBlue,
          foregroundColor: Colors.white,
          disabledBackgroundColor: _brandBlue.withValues(alpha: 0.38),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.86),
          elevation: onPressed == null ? 0 : 8,
          shadowColor: _brandBlue.withValues(alpha: 0.28),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: Row(
            key: ValueKey(label),
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading) ...[
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OtpInfoBox extends StatelessWidget {
  const _OtpInfoBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _softBlueCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD7E8FF)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CircleIcon(icon: Icons.info_rounded, size: 38),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Kode OTP dikirim ke email dan WhatsApp.',
                  style: TextStyle(
                    color: _brandBlueDark,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    height: 1.25,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Gunakan satu kode yang sama. WhatsApp bisa membutuhkan 30-60 detik.',
                  style: TextStyle(
                    color: Color(0xFF24527A),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.32,
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

class _CircleIcon extends StatelessWidget {
  final IconData icon;
  final double size;

  const _CircleIcon({required this.icon, this.size = 42});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: _brandBlue,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: Colors.white, size: size * 0.54),
    );
  }
}

class _RegisterMemberBenefitCard extends StatelessWidget {
  const _RegisterMemberBenefitCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 18),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _borderSoft),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.045),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: _softBlueCard,
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Icon(
              Icons.verified_user_rounded,
              color: _brandBlue,
              size: 42,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Kenapa daftar member Natalo?',
                  style: TextStyle(
                    color: _darkNavy,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 10),
                _BenefitBullet(
                  text: 'Kumpulkan loyalty poin setiap transaksi',
                ),
                SizedBox(height: 7),
                _BenefitBullet(
                  text: 'Dapat voucher dan promo khusus member',
                ),
                SizedBox(height: 7),
                _BenefitBullet(
                  text: 'Checkout lebih cepat dengan data akun tersimpan',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BenefitBullet extends StatelessWidget {
  final String text;

  const _BenefitBullet({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1, right: 8),
          child: Icon(
            Icons.check_circle_rounded,
            color: _brandBlue,
            size: 17,
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: _darkNavy,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
        ),
      ],
    );
  }
}

class _BackToLoginLink extends StatelessWidget {
  final VoidCallback onTap;

  const _BackToLoginLink({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 4),
        child: Text.rich(
          TextSpan(
            text: 'Sudah punya akun? ',
            style: TextStyle(
              color: _textSecondary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
            children: [
              TextSpan(
                text: 'Masuk',
                style: TextStyle(
                  color: _brandBlueDark,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

/// Destination hint — info ke user OTP dikirim ke email + WA mana.
/// Phone di-mask partial untuk privacy: 0812***4567 (4 awal + 4 akhir
/// visible, sisanya bintang). Match pattern IG/Tokopedia OTP screen.
class _OtpDestinationHint extends StatelessWidget {
  final String email;
  final String phone;

  const _OtpDestinationHint({required this.email, required this.phone});

  String _maskPhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.length <= 8) return digits;
    final start = digits.substring(0, 4);
    final end = digits.substring(digits.length - 4);
    return '$start${'*' * (digits.length - 8)}$end';
  }

  String _maskEmail(String raw) {
    final clean = raw.trim();
    final at = clean.indexOf('@');
    if (at <= 0) return clean;
    final local = clean.substring(0, at);
    final domain = clean.substring(at);
    if (local.length <= 2) return clean;
    final visible = local.substring(0, 2);
    return '$visible${'*' * (local.length - 2)}$domain';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            color: _textSecondary,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
          children: [
            const TextSpan(text: 'Kode dikirim ke '),
            TextSpan(
              text: _maskPhone(phone),
              style: const TextStyle(
                color: _darkNavy,
                fontWeight: FontWeight.w800,
              ),
            ),
            const TextSpan(text: ' dan '),
            TextSpan(
              text: _maskEmail(email),
              style: const TextStyle(
                color: _darkNavy,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Resend OTP row — disabled selama countdown >0 ("Tunggu 45s"), enabled
/// kalau 0 ("Kirim Ulang Kode"). Tap → trigger parent _resendOtp().
/// Loading state saat request in-flight (spinner kecil).
class _ResendOtpRow extends StatelessWidget {
  final int countdown;
  final bool loading;
  final VoidCallback onTap;

  const _ResendOtpRow({
    required this.countdown,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = countdown > 0 || loading;
    final label = loading
        ? 'Mengirim ulang...'
        : countdown > 0
            ? 'Kirim ulang dalam ${countdown}s'
            : 'Kirim Ulang Kode';
    final color = disabled ? _textSecondary : _brandBlueDark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading) ...[
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(_textSecondary),
                  ),
                ),
                const SizedBox(width: 8),
              ] else ...[
                Icon(
                  Icons.refresh_rounded,
                  size: 16,
                  color: color,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

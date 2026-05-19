import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../utils/haptics.dart';
import '../utils/phone_formatter.dart';
import '../widgets/loading_button.dart';

const _brandBlue = Color(0xFF0B7FEA);

/// Register screen — match Capacitor APK screenshot:
/// - Custom back + "Daftar Member" centered title
/// - Logo image + "Daftar Member Natalo" + subtitle "Gratis! Dapatkan harga khusus dan benefit member."
/// - Form card dengan field: Nama lengkap / Email / No HP / (info OTP blue card) / Password / Konfirmasi password
/// - "Kirim OTP" pill biru → trigger step 1 (kirim OTP ke email + WA)
/// - Step 2: OTP field muncul → "Daftar" button
/// - Manfaat card abu di bawah form
/// - "Sudah punya akun? Masuk" footer
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

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _otpController.dispose();
    super.dispose();
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
        // Step 1 sukses — OTP terkirim
        AppHaptics.success();
        setState(() => _otpSent = true);
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString()),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _validate() {
    if (_nameController.text.trim().isEmpty) {
      _showError('Nama lengkap harus diisi.');
      return false;
    }
    if (_emailController.text.trim().isEmpty) {
      _showError('Email harus diisi.');
      return false;
    }
    // Validate digit count (skip dashes/spaces dari PhoneFormatter).
    if (_phoneController.text.replaceAll(RegExp(r'[^\d]'), '').length < 8) {
      _showError('Nomor handphone tidak valid.');
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
      backgroundColor: const Color(0xFFF7FAFF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7FAFF),
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: const Color(0xFFF7FAFF),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF17202A)),
          onPressed: () => Navigator.pushReplacementNamed(
            context,
            '/member/login',
          ),
        ),
        title: const Text(
          'Daftar Member',
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
            // ── Header section ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              color: const Color(0xFFEFF2F6),
              child: Column(
                children: [
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
                    'Daftar Member Natalo',
                    style: TextStyle(
                      color: Color(0xFF111111),
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Gratis! Dapatkan harga khusus dan benefit member.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),

            // ── Form card ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
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
                    const _FieldLabel('Nama lengkap'),
                    _PillTextField(
                      controller: _nameController,
                      hint: 'Contoh: Andi Setiawan',
                    ),
                    const SizedBox(height: 14),
                    const _FieldLabel('Email'),
                    _PillTextField(
                      controller: _emailController,
                      hint: 'Contoh: nama@email.com',
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 14),
                    const _FieldLabel('No. handphone'),
                    _PillTextField(
                      controller: _phoneController,
                      hint: 'Contoh: 0812-3456-789',
                      keyboardType: TextInputType.phone,
                      inputFormatters: [PhoneFormatter()],
                    ),
                    const SizedBox(height: 14),
                    // ── Info OTP blue card ──
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
                            'Kode OTP dikirim ke email dan WhatsApp kamu.',
                            style: TextStyle(
                              color: _brandBlue,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              height: 1.4,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Email biasanya masuk dalam beberapa detik. WhatsApp bisa butuh 30–60 detik. Cukup masukkan satu kode yang sama.',
                            style: TextStyle(
                              color: _brandBlue,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    const _FieldLabel('Password'),
                    _PillTextField(
                      controller: _passwordController,
                      hint: 'Masukkan password (min. 8 karakter)',
                      obscure: _obscurePassword,
                      onToggleObscure: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    const SizedBox(height: 14),
                    const _FieldLabel('Konfirmasi password'),
                    _PillTextField(
                      controller: _confirmController,
                      hint: 'Ulangi password yang sama',
                      obscure: _obscureConfirm,
                      onToggleObscure: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                    if (_otpSent) ...[
                      const SizedBox(height: 14),
                      const _FieldLabel('Kode OTP'),
                      _PillTextField(
                        controller: _otpController,
                        hint: 'Masukkan 6 digit kode',
                        keyboardType: TextInputType.number,
                      ),
                    ],
                    const SizedBox(height: 22),
                    LoadingButton(
                      onPressed: _onPrimary,
                      loading: _loading,
                      color: _brandBlue,
                      child: Text(_otpSent ? 'Daftar' : 'Kirim OTP'),
                    ),
                    const SizedBox(height: 16),
                    // ── Manfaat card ──
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            'Manfaat jadi Member di Natalopetshop.com',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF111111),
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              height: 1.4,
                            ),
                          ),
                          SizedBox(height: 12),
                          _BenefitBullet(
                              text:
                                  'Kumpulkan Loyalty poin dari setiap transaksi anda.'),
                          SizedBox(height: 8),
                          _BenefitBullet(
                              text:
                                  'Belanja di natalopetshop.com lebih murah, cepat, hemat dan mudah.'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Footer "Sudah punya akun? Masuk" ──
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: GestureDetector(
                onTap: () =>
                    Navigator.pushReplacementNamed(context, '/member/login'),
                child: const Text.rich(
                  TextSpan(
                    text: 'Sudah punya akun? ',
                    style: TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    children: [
                      TextSpan(
                        text: 'Masuk',
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
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;
  // ignore: unused_element_parameter
  const _FieldLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF111111),
          fontSize: 14,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _PillTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;
  final bool obscure;
  final VoidCallback? onToggleObscure;
  final List<TextInputFormatter>? inputFormatters;

  const _PillTextField({
    required this.controller,
    required this.hint,
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
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
          color: Color(0xFF9CA3AF),
          fontWeight: FontWeight.w600,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
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
                  color: const Color(0xFF9CA3AF),
                ),
              ),
        border: OutlineInputBorder(
          // Capacitor pakai rounded rectangle (radius ~12-14) untuk input,
          // NOT full pill. Pill cuma untuk button. radius 14 lebih
          // konvensional + readable untuk form panjang.
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _brandBlue, width: 1.4),
        ),
      ),
    );
  }
}

class _BenefitBullet extends StatelessWidget {
  final String text;
  const _BenefitBullet({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6, right: 8),
            child: SizedBox(
              height: 6,
              width: 6,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0xFF334155),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF334155),
                fontSize: 13,
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

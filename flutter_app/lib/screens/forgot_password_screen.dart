import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../utils/haptics.dart';

const _brandBlue = Color(0xFF0B7FEA);

/// Forgot password screen — call /api/auth/forgot-password.
/// Setelah submit, tampil konfirmasi: "Kami sudah kirim link reset ke email
/// kamu (jika terdaftar)." — server selalu return sukses untuk anti
/// enumeration attack.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  bool _loading = false;
  bool _submitted = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
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
    setState(() => _loading = true);
    try {
      await authService.forgotPassword(email);
      if (!mounted) return;
      AppHaptics.success();
      setState(() => _submitted = true);
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
          onPressed: () => Navigator.pushNamedAndRemoveUntil(
            context,
            '/',
            (_) => false,
          ),
        ),
        title: const Text(
          'Lupa Password',
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
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
              color: const Color(0xFFEFF2F6),
              child: Column(
                children: [
                  Container(
                    height: 72,
                    width: 72,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF5FF),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.lock_reset_rounded,
                      color: _brandBlue,
                      size: 36,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Reset Password',
                    style: TextStyle(
                      color: Color(0xFF111111),
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Masukkan email yang kamu pakai daftar. Kami kirim link untuk reset password.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Form card / Success state ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
              child: _submitted
                  ? _SuccessCard(email: _emailController.text.trim())
                  : _FormCard(
                      emailController: _emailController,
                      loading: _loading,
                      onSubmit: _submit,
                    ),
            ),

            // ── Footer link kembali ke Login ──
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Text.rich(
                  TextSpan(
                    text: 'Ingat password? ',
                    style: TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    children: [
                      TextSpan(
                        text: 'Kembali ke Masuk',
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
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _FormCard extends StatelessWidget {
  final TextEditingController emailController;
  final bool loading;
  final VoidCallback onSubmit;

  const _FormCard({
    required this.emailController,
    required this.loading,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Email',
            style: TextStyle(
              color: Color(0xFF111111),
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              hintText: 'Email yang terdaftar di akun kamu',
              hintStyle: const TextStyle(
                color: Color(0xFF9CA3AF),
                fontWeight: FontWeight.w600,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
              prefixIcon: const Icon(
                Icons.mail_outline_rounded,
                color: Color(0xFF9CA3AF),
              ),
              // Match Capacitor: rounded rectangle (radius 14) untuk input.
              // Pill (999) cuma untuk button.
              border: OutlineInputBorder(
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
            onSubmitted: (_) => onSubmit(),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: Color(0xFFF59E0B),
                  size: 18,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Link reset password berlaku 1 jam. Hanya bisa diminta 3x per jam.',
                    style: TextStyle(
                      color: Color(0xFF92400E),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: loading ? null : onSubmit,
            style: ElevatedButton.styleFrom(
              backgroundColor: _brandBlue,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            child: loading
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : const Text('Kirim Link Reset'),
          ),
        ],
      ),
    );
  }
}

class _SuccessCard extends StatelessWidget {
  final String email;
  const _SuccessCard({required this.email});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Column(
        children: [
          Container(
            height: 64,
            width: 64,
            decoration: const BoxDecoration(
              color: Color(0xFFD1FAE5),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              color: Color(0xFF16A34A),
              size: 36,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Cek email kamu',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF111111),
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              text:
                  'Kalau email $email terdaftar di Natalo, kami sudah kirim link untuk reset password.\n\n',
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.55,
              ),
              children: const [
                TextSpan(
                  text:
                      'Cek folder Spam / Promosi kalau belum kelihatan dalam 5 menit.',
                  style: TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: _brandBlue,
              minimumSize: const Size.fromHeight(48),
              side: const BorderSide(color: Color(0xFFBFDBFE)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
            child: const Text('Kembali ke Masuk'),
          ),
        ],
      ),
    );
  }
}

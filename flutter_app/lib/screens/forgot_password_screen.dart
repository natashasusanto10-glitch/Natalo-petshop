import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/natalo_colors.dart';
import '../utils/haptics.dart';

/// Lupa Password — form email → submit → server kirim reset link.
///
/// Anti email enumeration: server selalu return success bahkan kalau email
/// tidak terdaftar. UI tampil success message yang sama biar tidak leak
/// info mana email yang valid.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _loading = false;
  bool _sent = false;
  String? _errorText;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    AppHaptics.tap();
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      await authService.forgotPassword(_emailController.text);
      if (!mounted) return;
      setState(() {
        _sent = true;
        _loading = false;
      });
      AppHaptics.success();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = e.toString().contains('429')
            ? 'Terlalu banyak percobaan. Coba lagi 1 jam.'
            : 'Gagal kirim link reset. Periksa koneksi.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFF),
      appBar: AppBar(
        title: const Text('Lupa Password'),
        backgroundColor: const Color(0xFFF7FAFF),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
          child: _sent ? _buildSuccessView() : _buildForm(),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF3FF),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Icon(
                Icons.lock_reset_rounded,
                color: NataloColors.primary,
                size: 44,
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Reset Password',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: NataloColors.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Masukkan email terdaftar, kami akan kirim link untuk\nreset password baru.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: NataloColors.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            'Email',
            style: TextStyle(
              color: NataloColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            enabled: !_loading,
            decoration: const InputDecoration(
              hintText: 'kamu@email.com',
              filled: true,
              fillColor: Colors.white,
            ),
            validator: (v) {
              final s = (v ?? '').trim();
              if (s.isEmpty) return 'Email wajib diisi';
              if (!s.contains('@') || !s.contains('.')) {
                return 'Format email tidak valid';
              }
              return null;
            },
          ),
          if (_errorText != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: Color(0xFFEF4444),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorText!,
                      style: const TextStyle(
                        color: Color(0xFFB91C1C),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _loading ? null : _submit,
            child: _loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : const Text('Kirim Link Reset'),
          ),
          const SizedBox(height: 20),
          TextButton(
            onPressed: _loading ? null : () => Navigator.pop(context),
            child: const Text(
              '← Kembali ke Login',
              style: TextStyle(
                color: NataloColors.primary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 32),
        Center(
          child: Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: const Color(0xFFD1FAE5),
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Icon(
              Icons.mark_email_read_rounded,
              color: Color(0xFF16A34A),
              size: 44,
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Link reset terkirim',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: NataloColors.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Kami sudah kirim link reset password ke:\n${_emailController.text}\n\nCek inbox (atau folder spam) lalu klik link-nya.\nLink berlaku 1 jam.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: NataloColors.textSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w500,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Kembali ke Login'),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => setState(() {
            _sent = false;
            _errorText = null;
          }),
          child: const Text(
            'Kirim ulang ke email lain',
            style: TextStyle(
              color: NataloColors.primary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

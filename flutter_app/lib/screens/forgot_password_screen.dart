import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/natalo_colors.dart';
import '../utils/haptics.dart';
import '../widgets/auth_shell.dart';

/// Lupa Password — form email → server kirim reset link.
/// Backend tetap anti email-enumeration; UI hanya menampilkan status aman.
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
    return AuthShell(
      icon: _sent ? Icons.mark_email_read_rounded : Icons.lock_reset_rounded,
      title: _sent ? 'Link reset terkirim' : 'Lupa Password',
      subtitle: _sent
          ? 'Cek email kamu lalu ikuti link reset password dari Natalo.'
          : 'Masukkan email member. Kami akan kirim link untuk membuat password baru.',
      footer: AuthSwitchFooter(
        text: 'Ingat password? ',
        actionText: 'Masuk',
        onTap: () => Navigator.pop(context),
      ),
      children: _sent ? _successChildren() : _formChildren(),
    );
  }

  List<Widget> _formChildren() => [
        const AuthInfoBox(
          icon: Icons.shield_rounded,
          text:
              'Demi keamanan, kami hanya mengirim link reset ke email member yang terdaftar.',
        ),
        const SizedBox(height: 18),
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AuthFieldLabel('Email member'),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                enabled: !_loading,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _loading ? null : _submit(),
                decoration: const InputDecoration(
                  hintText: 'kamu@email.com',
                  prefixIcon: Icon(Icons.alternate_email_rounded),
                  filled: true,
                  fillColor: Color(0xFFF8FBFF),
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
                const SizedBox(height: 14),
                AuthErrorBox(_errorText!),
              ],
              const SizedBox(height: 20),
              AuthPrimaryButton(
                onPressed: _submit,
                loading: _loading,
                label: 'Kirim Link Reset',
              ),
            ],
          ),
        ),
      ];

  List<Widget> _successChildren() => [
        AuthInfoBox(
          icon: Icons.mail_rounded,
          text:
              'Jika email ${_emailController.text} terdaftar, link reset sudah kami kirim. Link berlaku 1 jam.',
          color: NataloColors.successDark,
          background: NataloColors.successSoft,
        ),
        const SizedBox(height: 18),
        AuthPrimaryButton(
          onPressed: () => Navigator.pop(context),
          loading: false,
          label: 'Kembali ke Login',
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () => setState(() {
            _sent = false;
            _errorText = null;
          }),
          child: const Text(
            'Kirim ulang ke email lain',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ];
}

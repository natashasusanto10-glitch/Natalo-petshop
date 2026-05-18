import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../state/member_store.dart';
import '../theme/natalo_colors.dart';
import '../utils/haptics.dart';
import '../widgets/app_toast.dart';
import '../widgets/auth_shell.dart';

/// Register Member Natalo — 2-step flow.
/// Step 1 meminta data, step 2 verifikasi OTP dari backend existing.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _otpController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _loading = false;
  String? _errorText;
  bool _otpSent = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _otpController.dispose();
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
      final profile = await authService.register(
        name: _nameController.text,
        email: _emailController.text,
        phone: _phoneController.text,
        password: _passwordController.text,
        confirmPassword: _confirmPasswordController.text,
        otp: _otpSent ? _otpController.text : null,
      );

      if (profile == null) {
        if (!mounted) return;
        setState(() {
          _otpSent = true;
          _loading = false;
        });
        AppToast.show(
          context,
          'Kode OTP dikirim ke email & WhatsApp Anda.',
          kind: ToastKind.success,
        );
      } else {
        await memberStore.setSession(profile: profile);
        if (!mounted) return;
        AppToast.show(
          context,
          'Selamat datang, ${profile.name}!',
          kind: ToastKind.success,
        );
        if (Navigator.canPop(context)) {
          Navigator.pop(context, true);
        } else {
          Navigator.pushReplacementNamed(context, '/');
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = _humanizeError(e);
        _loading = false;
      });
    }
  }

  String _humanizeError(Object error) {
    final msg = error.toString();
    if (msg.toLowerCase().contains('otp')) {
      return 'Kode OTP salah atau kedaluwarsa. Cek email/WhatsApp.';
    }
    if (msg.contains('409') || msg.toLowerCase().contains('exist')) {
      return 'Email atau No. HP sudah terdaftar.';
    }
    if (msg.contains('429')) {
      return 'Terlalu banyak percobaan. Coba lagi nanti.';
    }
    return 'Pendaftaran gagal. Periksa data atau coba lagi.';
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      icon: _otpSent ? Icons.verified_user_rounded : Icons.person_add_rounded,
      title: _otpSent ? 'Verifikasi OTP' : 'Daftar Member Natalo',
      subtitle: _otpSent
          ? 'Masukkan kode 6 digit yang dikirim ke email dan WhatsApp kamu.'
          : 'Buat akun gratis untuk checkout lebih cepat dan pakai benefit member.',
      footer: AuthSwitchFooter(
        text: 'Sudah punya akun? ',
        actionText: 'Masuk',
        onTap: _loading
            ? () {}
            : () => Navigator.pushReplacementNamed(context, '/member/login'),
      ),
      children: [
        AuthInfoBox(
          icon: _otpSent
              ? Icons.mark_email_read_rounded
              : Icons.card_giftcard_rounded,
          text: _otpSent
              ? 'Kode OTP dikirim ke ${_emailController.text} dan WhatsApp ${_phoneController.text}.'
              : 'Data member dipakai untuk pesanan, voucher, poin, dan alamat pengiriman Natalo.',
        ),
        const SizedBox(height: 18),
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_otpSent) ..._step1Fields() else ..._step2Fields(),
              if (_errorText != null) ...[
                const SizedBox(height: 14),
                AuthErrorBox(_errorText!),
              ],
              const SizedBox(height: 20),
              AuthPrimaryButton(
                onPressed: _submit,
                loading: _loading,
                label: _otpSent ? 'Verifikasi & Daftar' : 'Kirim Kode OTP',
              ),
              if (_otpSent) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _loading
                      ? null
                      : () => setState(() {
                            _otpSent = false;
                            _otpController.clear();
                            _errorText = null;
                          }),
                  child: const Text(
                    'Ubah data pendaftaran',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _step1Fields() => [
        const AuthFieldLabel('Nama lengkap'),
        TextFormField(
          controller: _nameController,
          textCapitalization: TextCapitalization.words,
          enabled: !_loading,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            hintText: 'Contoh: Natasha Susanto',
            prefixIcon: Icon(Icons.badge_rounded),
            filled: true,
            fillColor: Color(0xFFF8FBFF),
          ),
          validator: (v) =>
              (v ?? '').trim().isEmpty ? 'Nama wajib diisi' : null,
        ),
        const SizedBox(height: 15),
        const AuthFieldLabel('Email'),
        TextFormField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          enabled: !_loading,
          textInputAction: TextInputAction.next,
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
        const SizedBox(height: 15),
        const AuthFieldLabel('No. HP WhatsApp'),
        TextFormField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          enabled: !_loading,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            hintText: '08xxxxxxxxxx',
            prefixIcon: Icon(Icons.phone_rounded),
            filled: true,
            fillColor: Color(0xFFF8FBFF),
          ),
          validator: (v) {
            final s = (v ?? '').trim();
            if (s.isEmpty) return 'No. HP wajib diisi';
            if (s.length < 8) return 'No. HP terlalu pendek';
            return null;
          },
        ),
        const SizedBox(height: 15),
        const AuthFieldLabel('Password'),
        TextFormField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          enabled: !_loading,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            hintText: 'Min 8 karakter',
            prefixIcon: const Icon(Icons.lock_rounded),
            filled: true,
            fillColor: const Color(0xFFF8FBFF),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                color: NataloColors.textTertiary,
              ),
              onPressed: () => setState(
                () => _obscurePassword = !_obscurePassword,
              ),
            ),
          ),
          validator: (v) {
            final s = v ?? '';
            if (s.isEmpty) return 'Password wajib diisi';
            if (s.length < 8) return 'Password min 8 karakter';
            return null;
          },
        ),
        const SizedBox(height: 15),
        const AuthFieldLabel('Konfirmasi password'),
        TextFormField(
          controller: _confirmPasswordController,
          obscureText: _obscureConfirm,
          enabled: !_loading,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: 'Ulangi password',
            prefixIcon: const Icon(Icons.lock_person_rounded),
            filled: true,
            fillColor: const Color(0xFFF8FBFF),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureConfirm
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                color: NataloColors.textTertiary,
              ),
              onPressed: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
            ),
          ),
          validator: (v) {
            if ((v ?? '').isEmpty) return 'Konfirmasi password wajib diisi';
            if (v != _passwordController.text) return 'Password tidak cocok';
            return null;
          },
        ),
      ];

  List<Widget> _step2Fields() => [
        const AuthFieldLabel('Kode OTP'),
        TextFormField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          enabled: !_loading,
          textAlign: TextAlign.center,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _loading ? null : _submit(),
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            letterSpacing: 8,
          ),
          decoration: const InputDecoration(
            hintText: '------',
            filled: true,
            fillColor: Color(0xFFF8FBFF),
            counterText: '',
          ),
          validator: (v) {
            final s = (v ?? '').trim();
            if (s.length != 6) return 'OTP harus 6 digit';
            return null;
          },
        ),
      ];
}

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../state/member_store.dart';
import '../theme/natalo_colors.dart';
import '../utils/haptics.dart';
import '../widgets/app_toast.dart';

/// Register Member Natalo — 2-step flow.
///
/// Step 1: name + email + phone + password + confirm → submit → server kirim
///         OTP ke email + WhatsApp.
/// Step 2: input OTP → submit → server bikin user → auto login + redirect.
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
  bool _otpSent = false; // true = step 2 (OTP screen)

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
        // Step 1 success — OTP sent.
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
        // Step 2 success — auto login.
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
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFF),
      appBar: AppBar(
        title: const Text('Daftar'),
        backgroundColor: const Color(0xFFF7FAFF),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _otpSent ? 'Verifikasi OTP' : 'Daftar Member Natalo',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: NataloColors.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _otpSent
                      ? 'Masukkan kode 6-digit yang dikirim ke email & WhatsApp.'
                      : 'Gratis. Cuma butuh 1 menit untuk daftar.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: NataloColors.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                if (!_otpSent) ..._step1Fields() else ..._step2Fields(),
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
                      : Text(_otpSent ? 'Verifikasi & Daftar' : 'Kirim Kode OTP'),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Sudah punya akun? ',
                      style: TextStyle(
                        color: NataloColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () => Navigator.pushReplacementNamed(
                                context,
                                '/member/login',
                              ),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Masuk',
                        style: TextStyle(
                          color: NataloColors.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _step1Fields() => [
        _LabeledField(
          label: 'Nama lengkap',
          child: TextFormField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            enabled: !_loading,
            decoration: const InputDecoration(
              hintText: 'Contoh: Natasha Susanto',
              filled: true,
              fillColor: Colors.white,
            ),
            validator: (v) =>
                (v ?? '').trim().isEmpty ? 'Nama wajib diisi' : null,
          ),
        ),
        _LabeledField(
          label: 'Email',
          child: TextFormField(
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
        ),
        _LabeledField(
          label: 'No. HP (WhatsApp)',
          child: TextFormField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            enabled: !_loading,
            decoration: const InputDecoration(
              hintText: '08xxxxxxxxxx',
              filled: true,
              fillColor: Colors.white,
            ),
            validator: (v) {
              final s = (v ?? '').trim();
              if (s.isEmpty) return 'No. HP wajib diisi';
              if (s.length < 8) return 'No. HP terlalu pendek';
              return null;
            },
          ),
        ),
        _LabeledField(
          label: 'Password',
          child: TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            enabled: !_loading,
            decoration: InputDecoration(
              hintText: 'Min 8 karakter',
              filled: true,
              fillColor: Colors.white,
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
        ),
        _LabeledField(
          label: 'Konfirmasi password',
          child: TextFormField(
            controller: _confirmPasswordController,
            obscureText: _obscureConfirm,
            enabled: !_loading,
            decoration: InputDecoration(
              hintText: 'Ulangi password',
              filled: true,
              fillColor: Colors.white,
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
              if (v != _passwordController.text) {
                return 'Password tidak cocok';
              }
              return null;
            },
          ),
        ),
      ];

  List<Widget> _step2Fields() => [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF3FF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.mail_outline_rounded,
                color: NataloColors.primary,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Kode OTP dikirim ke ${_emailController.text}\ndan WhatsApp ${_phoneController.text}.',
                  style: const TextStyle(
                    color: NataloColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _LabeledField(
          label: 'Kode OTP (6 digit)',
          child: TextFormField(
            controller: _otpController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            enabled: !_loading,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: 8,
            ),
            decoration: const InputDecoration(
              hintText: '------',
              filled: true,
              fillColor: Colors.white,
              counterText: '',
            ),
            validator: (v) {
              final s = (v ?? '').trim();
              if (s.length != 6) return 'OTP harus 6 digit';
              return null;
            },
          ),
        ),
      ];
}

class _LabeledField extends StatelessWidget {
  final String label;
  final Widget child;

  const _LabeledField({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: NataloColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

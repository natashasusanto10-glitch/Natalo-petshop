import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../state/member_store.dart';
import '../theme/natalo_colors.dart';
import '../utils/haptics.dart';
import '../widgets/app_toast.dart';

/// Login Member Natalo — form email/HP + password.
///
/// Sesuai design Android: logo "NL" gradient, judul "Masuk Member Natalo",
/// info box biru, dua field, "Lupa password?", tombol "Masuk", footer
/// "Belum punya akun? Daftar gratis".
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _obscurePassword = true;
  bool _loading = false;
  String? _errorText;

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
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
      final profile = await authService.login(
        identifier: _identifierController.text.trim(),
        password: _passwordController.text,
      );
      await memberStore.setSession(profile: profile);
      if (!mounted) return;
      AppToast.show(context, 'Selamat datang, ${profile.name}!');
      _continueAfterLogin();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = _humanizeError(e);
        _loading = false;
      });
    }
  }

  void _continueAfterLogin() {
    final routeArgs = ModalRoute.of(context)?.settings.arguments;
    String? redirectRoute;
    Object? redirectArguments;

    if (routeArgs is Map) {
      final redirect = routeArgs['redirect'];
      if (redirect is String && redirect.trim().isNotEmpty) {
        redirectRoute = redirect.trim();
      }
      redirectArguments = routeArgs['arguments'];
    }

    if (redirectRoute != null) {
      Navigator.pushReplacementNamed(
        context,
        redirectRoute,
        arguments: redirectArguments,
      );
      return;
    }

    // Pop back ke screen sebelumnya — atau ke home kalau direct nav.
    if (Navigator.canPop(context)) {
      Navigator.pop(context, true);
    } else {
      Navigator.pushReplacementNamed(context, '/');
    }
  }

  String _humanizeError(Object error) {
    final msg = error.toString();
    if (msg.contains('401') || msg.toLowerCase().contains('invalid')) {
      return 'Email/HP atau password salah.';
    }
    if (msg.contains('429') || msg.toLowerCase().contains('rate')) {
      return 'Terlalu banyak percobaan. Coba lagi nanti.';
    }
    if (msg.contains('500') || msg.toLowerCase().contains('server')) {
      return 'Server sedang bermasalah. Coba lagi sebentar.';
    }
    return 'Login gagal. Periksa koneksi atau coba lagi.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFF),
      appBar: AppBar(
        title: const Text('Masuk'),
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
                // Logo bulat dengan "NL" gradient + paw icon
                _NataloLogo(),
                const SizedBox(height: 20),
                const Text(
                  'Masuk Member Natalo',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: NataloColors.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Belanja kebutuhan hewan jadi lebih mudah, cepat,\ndan hemat.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: NataloColors.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                // Info box biru
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF3FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: NataloColors.primary,
                        size: 20,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Akun member Natalo\nMasuk untuk lanjut checkout, cek pesanan, dan pakai benefit member.',
                          style: TextStyle(
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
                // Email / No. HP field
                const Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Text(
                    'Email / No. HP',
                    style: TextStyle(
                      color: NataloColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextFormField(
                  controller: _identifierController,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  enabled: !_loading,
                  decoration: const InputDecoration(
                    hintText: 'contoh: kamu@email.com / 081234',
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  validator: (value) {
                    final v = (value ?? '').trim();
                    if (v.isEmpty) return 'Email atau No. HP wajib diisi';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                // Password field with Lupa password? right
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Password',
                      style: TextStyle(
                        color: NataloColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () => Navigator.pushNamed(
                                context,
                                '/member/forgot-password',
                              ),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Lupa password?',
                        style: TextStyle(
                          color: NataloColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  enabled: !_loading,
                  decoration: InputDecoration(
                    hintText: 'Masukkan password',
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
                  validator: (value) {
                    if ((value ?? '').isEmpty) return 'Password wajib diisi';
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
                      : const Text('Masuk'),
                ),
                const SizedBox(height: 24),
                // Footer: Belum punya akun?
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Belum punya akun? ',
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
                                '/member/register',
                              ),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Daftar gratis',
                        style: TextStyle(
                          color: NataloColors.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Daftar gratis dan mulai kumpulkan benefit member Natalo.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: NataloColors.textTertiary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Logo Natalo bulat dengan "NL" letterform + gradient blue.
class _NataloLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              NataloColors.primary,
              NataloColors.primaryLight,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: NataloColors.primary.withValues(alpha: 0.28),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: const Center(
          child: Text(
            'NL',
            style: TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
        ),
      ),
    );
  }
}

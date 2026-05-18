import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../state/cart_store.dart';
import '../state/member_store.dart';
import '../theme/natalo_colors.dart';
import '../utils/haptics.dart';
import '../widgets/app_toast.dart';
import '../widgets/auth_shell.dart';

/// Login member native Flutter. Logic auth/session tetap memakai endpoint
/// existing, file ini hanya merapikan UI.
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
      unawaited(cartStore.loadFromServer());
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
    return AuthShell(
      icon: Icons.person_rounded,
      title: 'Masuk Member Natalo',
      subtitle:
          'Masuk untuk checkout, cek pesanan, pakai voucher, dan simpan produk favorit.',
      footer: Column(
        children: [
          AuthSwitchFooter(
            text: 'Belum punya akun? ',
            actionText: 'Daftar gratis',
            onTap: _loading
                ? () {}
                : () => Navigator.pushReplacementNamed(
                      context,
                      '/member/register',
                    ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Daftar sekali, benefit member langsung ikut akun kamu.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: NataloColors.textTertiary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      children: [
        const AuthInfoBox(
          icon: Icons.local_offer_rounded,
          text:
              'Benefit member aktif otomatis saat checkout: voucher, riwayat pesanan, poin, dan alamat tersimpan.',
        ),
        const SizedBox(height: 18),
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AuthFieldLabel('Email / No. HP'),
              TextFormField(
                controller: _identifierController,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                enabled: !_loading,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  hintText: 'kamu@email.com / 08xxxxxxxxxx',
                  prefixIcon: Icon(Icons.alternate_email_rounded),
                  filled: true,
                  fillColor: Color(0xFFF8FBFF),
                ),
                validator: (value) {
                  final v = (value ?? '').trim();
                  if (v.isEmpty) return 'Email atau No. HP wajib diisi';
                  return null;
                },
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  const Expanded(child: AuthFieldLabel('Password')),
                  Transform.translate(
                    offset: const Offset(0, -3),
                    child: TextButton(
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
                          fontSize: 12.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                enabled: !_loading,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _loading ? null : _submit(),
                decoration: InputDecoration(
                  hintText: 'Masukkan password',
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
                validator: (value) {
                  if ((value ?? '').isEmpty) return 'Password wajib diisi';
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
                label: 'Masuk',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../utils/haptics.dart';
import '../widgets/loading_button.dart';

const _brandBlue = Color(0xFF0B7FEA);

/// **Reset Password** screen — landing untuk deep link dari email reset.
///
/// Flow:
/// 1. User tap "Lupa password?" di Login → `authService.forgotPassword(email)`
///    → server kirim email dengan link `natalopetshop.com/auth/reset-password?token=ABC`
/// 2. User buka email → tap link → Android intent-filter (App Links) buka
///    Flutter app → `deep_link_service` parse `?token=` → push screen ini
/// 3. User input password baru → `authService.resetPassword(token, newPassword)`
/// 4. Sukses → snackbar + navigate ke login
///
/// Token expired ~1 jam (server-side validate).
class ResetPasswordScreen extends StatefulWidget {
  /// Token dari URL query param `?token=ABC123`. Wajib ada.
  final String token;

  const ResetPasswordScreen({super.key, required this.token});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _newPasswordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _submitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _newPasswordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (widget.token.trim().isEmpty) {
      setState(() => _errorMessage =
          'Token reset tidak valid. Buka ulang link dari email kamu.');
      return;
    }
    AppHaptics.tap();
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      await authService.resetPassword(
        token: widget.token,
        newPassword: _newPasswordCtrl.text,
      );
      if (!mounted) return;
      AppHaptics.success();
      // Show success dialog, lalu navigate ke login.
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          icon: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFF16A34A).withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              color: Color(0xFF16A34A),
              size: 30,
            ),
          ),
          title: const Text(
            'Password Berhasil Diubah',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          content: const Text(
            'Sekarang kamu bisa login dengan password baru.',
            textAlign: TextAlign.center,
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _brandBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text(
                  'Login Sekarang',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
        context, '/member/login', (route) => false,
      );
    } catch (error) {
      if (!mounted) return;
      AppHaptics.warning();
      setState(() {
        _errorMessage = _humanize(error);
        _submitting = false;
      });
    }
  }

  String _humanize(Object error) {
    if (error is ApiException) {
      if (error.statusCode == 400 || error.statusCode == 410) {
        return 'Token reset sudah expired atau tidak valid. '
            'Request link baru lewat "Lupa password?".';
      }
      if (error.statusCode == 422) {
        return 'Password tidak memenuhi syarat. Min 8 karakter, '
            'kombinasi huruf + angka.';
      }
      return error.message;
    }
    return 'Gagal reset password: $error';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: cs.surface,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: cs.onSurface),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(
          'Reset Password',
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              color: cs.surfaceContainerHighest,
              child: Column(
                children: [
                  Container(
                    height: 88,
                    width: 88,
                    decoration: BoxDecoration(
                      color: cs.surface,
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
                    child: const Icon(
                      Icons.lock_reset_rounded,
                      color: _brandBlue,
                      size: 44,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Buat Password Baru',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Pilih password baru untuk akun kamu. '
                      'Min 8 karakter, kombinasi huruf + angka.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _FieldLabel('Password baru'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _newPasswordCtrl,
                        obscureText: _obscureNew,
                        decoration: InputDecoration(
                          hintText: 'Minimal 8 karakter',
                          suffixIcon: IconButton(
                            onPressed: () => setState(
                                () => _obscureNew = !_obscureNew),
                            icon: Icon(_obscureNew
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.length < 8) return 'Min 8 karakter';
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      const _FieldLabel('Konfirmasi password'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _confirmCtrl,
                        obscureText: _obscureConfirm,
                        decoration: InputDecoration(
                          hintText: 'Ketik ulang password baru',
                          suffixIcon: IconButton(
                            onPressed: () => setState(
                                () => _obscureConfirm = !_obscureConfirm),
                            icon: Icon(_obscureConfirm
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined),
                          ),
                        ),
                        validator: (v) => v != _newPasswordCtrl.text
                            ? 'Konfirmasi tidak cocok'
                            : null,
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: Color(0xFFEF4444),
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      LoadingButton(
                        onPressed: _submit,
                        loading: _submitting,
                        color: _brandBlue,
                        child: const Text('Reset Password'),
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
  const _FieldLabel(this.label);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label,
        style: TextStyle(
          color: cs.onSurface,
          fontSize: 14,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

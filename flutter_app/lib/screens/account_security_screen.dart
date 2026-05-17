import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../state/favorite_store.dart';
import '../state/member_store.dart';
import '../utils/haptics.dart';
import '../widgets/loading_button.dart';

const _brandBlue = Color(0xFF0B7FEA);
const _dangerRed = Color(0xFFEF4444);
const _warningOrange = Color(0xFFEA580C);

/// **Keamanan Akun** — match Capacitor PWA flow:
/// - **Reset password** via email link (forgot-password)
/// - **Logout dari semua perangkat lain** (revoke-others)
/// - **Hapus akun permanen** (confirmation phrase + Play Store mandatory)
///
/// Capacitor TIDAK punya endpoint `change-password` langsung (in-app). User
/// yang lupa password pakai "Lupa Password?" → email link → reset. Pattern
/// ini lebih aman + tidak butuh validate current password.
class AccountSecurityScreen extends StatefulWidget {
  const AccountSecurityScreen({super.key});

  @override
  State<AccountSecurityScreen> createState() => _AccountSecurityScreenState();
}

class _AccountSecurityScreenState extends State<AccountSecurityScreen> {
  bool _revokingOthers = false;

  Future<void> _sendPasswordResetEmail() async {
    final email = memberStore.profile?.email ?? '';
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Email akun tidak terbaca. Login ulang lalu coba lagi.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    AppHaptics.tap();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          'Kirim email reset password?',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: Text(
          'Link reset password akan dikirim ke $email. Buka email lalu klik '
          'tautan untuk ganti password baru. Link expired dalam 1 jam.',
          style: const TextStyle(height: 1.55),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _brandBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            child: const Text('Kirim'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await authService.forgotPassword(email);
      if (!mounted) return;
      AppHaptics.success();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Link reset terkirim ke $email. Cek inbox / spam.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Gagal kirim email: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _revokeOtherSessions() async {
    AppHaptics.tap();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          'Keluar dari semua perangkat lain?',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: const Text(
          'Semua sesi aktif di device lain akan di-logout. Berguna kalau kamu '
          'lupa logout di HP teman/laptop kerja. Device ini tetap login.',
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _warningOrange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            child: const Text('Keluar Semua'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _revokingOthers = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await authService.revokeOtherSessions();
      if (!mounted) return;
      AppHaptics.success();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Sesi di device lain berhasil di-logout.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      AppHaptics.warning();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Gagal: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _revokingOthers = false);
    }
  }

  Future<void> _confirmDeleteAccount() async {
    AppHaptics.tap();
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _DeleteAccountSheet(),
    );
    if (confirmed == true && mounted) {
      favoriteStore.clear();
      Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(title: const Text('Keamanan Akun')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          // ── Password section ─────────────────────────────────────────
          const _SectionLabel('Password'),
          const SizedBox(height: 8),
          _ActionCard(
            icon: Icons.lock_reset_rounded,
            title: 'Reset Password',
            subtitle:
                'Kirim link reset ke email akun. Buka link → set password baru.',
            onTap: _sendPasswordResetEmail,
          ),
          const SizedBox(height: 22),
          // ── Sessions section ─────────────────────────────────────────
          const _SectionLabel('Sesi Aktif'),
          const SizedBox(height: 8),
          _ActionCard(
            icon: Icons.devices_other_rounded,
            title: _revokingOthers ? 'Sedang logout...' : 'Logout dari Perangkat Lain',
            subtitle:
                'Logout semua sesi di device lain (selain HP ini). Berguna '
                'kalau lupa logout di HP teman/laptop.',
            iconColor: _warningOrange,
            onTap: _revokingOthers ? null : _revokeOtherSessions,
          ),
          const SizedBox(height: 22),
          // ── Danger zone ──────────────────────────────────────────────
          const _SectionLabel('Zona Berbahaya', color: _dangerRed),
          const SizedBox(height: 8),
          _ActionCard(
            icon: Icons.delete_forever_rounded,
            title: 'Hapus Akun',
            subtitle:
                'Permanen — data profil, alamat, dan wishlist akan dihapus. '
                'Riwayat order tetap disimpan (di-anonymize).',
            iconColor: _dangerRed,
            titleColor: _dangerRed,
            onTap: _confirmDeleteAccount,
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final Color? color;

  const _SectionLabel(this.text, {this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: TextStyle(
          color: color ?? const Color(0xFF111111),
          fontSize: 14,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color? iconColor;
  final Color? titleColor;
  final VoidCallback? onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.iconColor,
    this.titleColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ic = iconColor ?? _brandBlue;
    final enabled = onTap != null;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Opacity(
          opacity: enabled ? 1.0 : 0.55,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: ic.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: ic, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: titleColor ?? const Color(0xFF111111),
                          fontSize: 14.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                if (enabled)
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF9CA3AF),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Hapus akun sheet — confirmation phrase pattern (match Capacitor).
/// User HARUS ketik "HAPUS AKUN SAYA" persis untuk enable tombol delete.
class _DeleteAccountSheet extends StatefulWidget {
  const _DeleteAccountSheet();

  @override
  State<_DeleteAccountSheet> createState() => _DeleteAccountSheetState();
}

class _DeleteAccountSheetState extends State<_DeleteAccountSheet> {
  static const _phrase = 'HAPUS AKUN SAYA';
  final _phraseCtrl = TextEditingController();
  bool _deleting = false;
  String? _error;

  @override
  void dispose() {
    _phraseCtrl.dispose();
    super.dispose();
  }

  bool get _phraseMatches => _phraseCtrl.text.trim() == _phrase;

  Future<void> _submit() async {
    if (!_phraseMatches) return;
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await authService.deleteAccount(confirmation: _phrase);
      await memberStore.logout();
      if (!mounted) return;
      AppHaptics.warning();
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      AppHaptics.warning();
      setState(() {
        _error = error is ApiException
            ? error.message
            : 'Gagal hapus akun: $error';
        _deleting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                height: 4,
                width: 40,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _dangerRed.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.delete_forever_rounded,
                    color: _dangerRed,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Hapus Akun Permanen',
                    style: TextStyle(
                      color: Color(0xFF111111),
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _dangerRed.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: _dangerRed.withValues(alpha: 0.20), width: 1),
              ),
              child: const Text(
                'Yang AKAN DIHAPUS permanen:\n'
                '• Profil, alamat, no HP, email\n'
                '• Wishlist, voucher, poin loyalty\n'
                '• Cart aktif + semua sesi login\n'
                '• Password reset token\n'
                '\n'
                'Yang TETAP DISIMPAN (untuk pajak/audit):\n'
                '• Riwayat order (di-anonymize, no nama/HP)',
                style: TextStyle(
                  color: Color(0xFF111111),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  height: 1.6,
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Ketik persis "HAPUS AKUN SAYA" (huruf besar, dengan spasi) '
              'untuk konfirmasi:',
              style: TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _phraseCtrl,
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'HAPUS AKUN SAYA',
                isDense: true,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _dangerRed.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: _dangerRed,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            LoadingButton(
              onPressed: _phraseMatches ? _submit : null,
              loading: _deleting,
              color: _dangerRed,
              child: const Text('Hapus Akun Permanen'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed:
                  _deleting ? null : () => Navigator.pop(context, false),
              child: const Text('Batal'),
            ),
          ],
        ),
      ),
    );
  }
}

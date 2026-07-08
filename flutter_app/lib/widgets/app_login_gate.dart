import 'package:flutter/material.dart';

import '../theme/natalo_colors.dart';

/// Scaffold "login member diperlukan" bersama untuk semua layar yang di-gate
/// untuk guest (Pesanan, Alamat, Voucher, Transaksi, Notifikasi, Chat, dll).
///
/// Sebelumnya tiap layar punya salinan sendiri dengan copy/ikon/tombol yang
/// beda-beda ("Login dulu yuk" vs "Login member diperlukan", tombol full-width
/// vs auto, ikon bell/receipt/lock). Satu tampilan konsisten di sini —
/// gembok dalam bulatan biru, headline seragam, tombol "Masuk Member".
///
/// Semua gate menuju rute yang sama '/member/login'; parent umumnya
/// `AnimatedBuilder(memberStore)` → auto-refresh begitu login sukses. Kalau
/// perlu bawa argumen redirect (mis. chat wajib balik ke '/chat' dengan
/// productContext-nya), override lewat [onLogin].
class AppLoginRequiredScaffold extends StatelessWidget {
  /// Judul AppBar (mis. 'Pesanan Saya'). null → tanpa AppBar (mis. tab
  /// Transaksi yang gate-nya mengisi layar penuh tanpa app bar).
  final String? title;

  /// Kalimat kontekstual kenapa perlu login (mis. 'Masuk untuk melihat
  /// voucher yang aktif di akun kamu.').
  final String message;

  /// Headline utama. Default 'Login member diperlukan'.
  final String headline;

  /// Ikon di dalam bulatan. Default gembok.
  final IconData icon;

  /// Label tombol. Default 'Masuk Member'.
  final String buttonLabel;

  /// Override aksi login. Default: `pushNamed('/member/login')`.
  final VoidCallback? onLogin;

  /// Bottom nav opsional — dipakai gate tab (mis. Transaksi) supaya guest
  /// tetap bisa pindah tab. Layar yang di-push (Pesanan/Alamat/Notifikasi/
  /// Chat) biarkan null.
  final Widget? bottomNavigationBar;

  const AppLoginRequiredScaffold({
    super.key,
    this.title,
    required this.message,
    this.headline = 'Login member diperlukan',
    this.icon = Icons.lock_outline_rounded,
    this.buttonLabel = 'Masuk Member',
    this.onLogin,
    this.bottomNavigationBar,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: title == null ? null : AppBar(title: Text(title!)),
      bottomNavigationBar: bottomNavigationBar,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 80,
                  width: 80,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: NataloColors.primary.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: NataloColors.primary, size: 38),
                ),
                const SizedBox(height: 18),
                Text(
                  headline,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: onLogin ??
                      () => Navigator.pushNamed(context, '/member/login'),
                  child: Text(buttonLabel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

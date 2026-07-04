import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../config/api_config.dart';
import '../theme/natalo_colors.dart';
import '../utils/haptics.dart';

/// Layar "Bagikan Profil" ala IG — kartu QR biru brand (Desain C).
///
/// QR meng-encode URL profil publik `/u/{username}` sehingga bisa dipindai
/// untuk langsung membuka profil. Tanpa tombol Unduh (per keputusan):
/// hanya dua aksi — Bagikan (native share sheet) + Salin link (clipboard).
///
/// Label di bawah QR pakai `@username` (bukan kapital paksa) supaya konsisten
/// dgn header profil & mention. Fallback ke nama display kalau username
/// belum di-set (user lama).
class ProfileQrScreen extends StatelessWidget {
  final String displayName;
  final String? username;

  const ProfileQrScreen({
    super.key,
    required this.displayName,
    required this.username,
  });

  bool get _hasUsername => username != null && username!.isNotEmpty;

  /// URL profil publik untuk QR + share. Fallback ke base app kalau username
  /// belum ada.
  String get _profileUrl => _hasUsername
      ? ApiConfig.uri('/u/$username').toString()
      : ApiConfig.uri('/').toString();

  /// Label handle di bawah QR: `@username`, atau nama display sbg fallback.
  String get _handleLabel => _hasUsername ? '@$username' : displayName;

  Future<void> _share(BuildContext context) async {
    AppHaptics.tap();
    try {
      // sharePositionOrigin WAJIB untuk iOS (popover anchor) — tanpa ini
      // share gagal/senyap di iOS.
      final box = context.findRenderObject() as RenderBox?;
      await Share.share(
        'Lihat profil $_handleLabel di Natalo\n$_profileUrl',
        sharePositionOrigin:
            box != null ? box.localToGlobal(Offset.zero) & box.size : null,
      );
    } catch (_) {
      // Cancel / platform tak support — silent.
    }
  }

  Future<void> _copyLink(BuildContext context) async {
    AppHaptics.tap();
    await Clipboard.setData(ClipboardData(text: _profileUrl));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(
          content: Text('Link profil disalin'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Column(
            children: [
              // Header: tutup (X) + judul di tengah + spacer seimbang.
              Row(
                children: [
                  _HeaderIconButton(
                    icon: Icons.close_rounded,
                    tooltip: 'Tutup',
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const Expanded(
                    child: Text(
                      'Bagikan profil',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  // Spacer selebar tombol X agar judul benar-benar center.
                  const SizedBox(width: 40),
                ],
              ),

              // Kartu QR biru brand — pusat layar.
              Expanded(
                child: Center(
                  child: _QrBrandCard(
                    data: _profileUrl,
                    handleLabel: _handleLabel,
                  ),
                ),
              ),

              // Dua tombol aksi (tanpa Unduh).
              Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.ios_share_rounded,
                      label: 'Bagikan',
                      filled: true,
                      onTap: () => _share(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.link_rounded,
                      label: 'Salin link',
                      filled: false,
                      onTap: () => _copyLink(context),
                    ),
                  ),
                ],
              ),
              SizedBox(height: bottomInset + 16),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kartu biru brand berisi QR + handle. Rasio & padding meniru kartu IG.
class _QrBrandCard extends StatelessWidget {
  final String data;
  final String handleLabel;

  const _QrBrandCard({required this.data, required this.handleLabel});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Container(
        decoration: BoxDecoration(
          color: NataloColors.primary,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: NataloColors.primary.withValues(alpha: 0.28),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // QR di atas panel putih rounded supaya kontras tinggi + terbaca
            // scanner walau kartu berlatar biru.
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.all(18),
              child: QrImageView(
                data: data,
                version: QrVersions.auto,
                size: 208,
                gapless: false,
                backgroundColor: Colors.white,
                // Navy pekat (bukan hitam murni) supaya senada brand tapi
                // tetap kontras tinggi untuk pemindaian.
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Color(0xFF0B1B33),
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Color(0xFF0B1B33),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              handleLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Pindai untuk buka profil',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tombol aksi bawah. `filled=true` → biru brand solid (Bagikan);
/// `filled=false` → surface dengan border (Salin link).
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = filled ? Colors.white : cs.onSurface;
    return Material(
      color: filled ? NataloColors.primary : cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: filled
                ? null
                : Border.all(color: cs.outlineVariant, width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: fg),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: IconButton(
        icon: Icon(icon, size: 24),
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        onPressed: onTap,
      ),
    );
  }
}

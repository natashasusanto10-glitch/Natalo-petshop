import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/launch_popup.dart';
import '../utils/haptics.dart';
import '../utils/motion_prefs.dart';

/// Hasil interaksi popup pembuka.
enum LaunchPromoOutcome { cta, dismiss }

/// Popup pembuka gaya Shopee: SATU gambar kreatif penuh (admin-managed) +
/// tombol X. Tap gambar = CTA (deep link), X / tap area gelap / back =
/// dismiss. Menggantikan kartu teks hardcoded lama.
///
/// Gambar diasumsikan SUDAH di-precache oleh LaunchPromoGate sebelum dialog
/// dibuka (gagal precache = popup di-skip total), jadi di sini tidak perlu
/// placeholder/error state — CachedNetworkImage langsung hit cache.
Future<LaunchPromoOutcome> showLaunchPromoDialog(
  BuildContext context, {
  required LaunchPopup popup,
}) async {
  final reduce = MotionPrefs.shouldReduce(context);
  final result = await showGeneralDialog<LaunchPromoOutcome>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Tutup',
    barrierColor: const Color(0x8C0F172A), // rgba(15,23,42,.55)
    transitionDuration: Duration(milliseconds: reduce ? 120 : 240),
    pageBuilder: (context, _, __) => LaunchPromoDialog(popup: popup),
    transitionBuilder: (context, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      if (reduce) return FadeTransition(opacity: curved, child: child);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
  return result ?? LaunchPromoOutcome.dismiss;
}

class LaunchPromoDialog extends StatelessWidget {
  final LaunchPopup popup;
  const LaunchPromoDialog({super.key, required this.popup});

  void _close(BuildContext context, LaunchPromoOutcome outcome) {
    AppHaptics.tap();
    Navigator.of(context).pop(outcome);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Center(
      child: Padding(
        // 28: ruang samping + ruang untuk tombol X yang menjorok keluar
        // sudut gambar (Stack clip none).
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 380,
            // 68% tinggi layar: gambar 4:5 muat penuh + masih terlihat
            // konteks Beranda di belakang (gaya Shopee, bukan fullscreen).
            maxHeight: size.height * 0.68,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Semantics(
                label: popup.imageAlt.isEmpty ? 'Promo' : popup.imageAlt,
                button: popup.href != null,
                child: GestureDetector(
                  key: const ValueKey('launch-popup-image'),
                  // opaque: seluruh area kartu (termasuk saat gambar belum/
                  // gagal ter-render) menangkap tap — tanpa ini tap jatuh
                  // tembus ke barrier (= dismiss yang tidak diminta).
                  behavior: HitTestBehavior.opaque,
                  // Tap gambar = CTA hanya kalau admin set link tujuan.
                  onTap: popup.href == null
                      ? null
                      : () => _close(context, LaunchPromoOutcome.cta),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    // Min 200×200: jaga area hit + posisi tombol X wajar
                    // walau gambar gagal render (produksi normalnya tidak —
                    // gate sudah precache; gagal = popup di-skip).
                    child: ConstrainedBox(
                      constraints:
                          const BoxConstraints(minWidth: 200, minHeight: 200),
                      child: CachedNetworkImage(
                        imageUrl: popup.imageUrl,
                        fit: BoxFit.contain,
                        fadeInDuration: Duration.zero,
                        // errorWidget: jaring pengaman supaya error stream
                        // tidak rethrow (termasuk di test).
                        errorWidget: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: -12,
                right: -12,
                child: _CloseButton(
                  onTap: () => _close(context, LaunchPromoOutcome.dismiss),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// X bulat translusen putih (gaya Shopee) — kontras di atas gambar apa pun
/// maupun di atas barrier gelap saat menjorok keluar sudut gambar.
class _CloseButton extends StatelessWidget {
  final VoidCallback onTap;
  const _CloseButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey('launch-popup-close'),
      color: const Color(0x40FFFFFF),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1.5),
          ),
          child: const Icon(Icons.close_rounded, size: 20, color: Colors.white),
        ),
      ),
    );
  }
}

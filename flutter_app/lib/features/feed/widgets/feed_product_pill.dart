import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../theme/natalo_colors.dart';

/// Pill produk mungil ala TikTok untuk overlay feed (video & foto).
///
/// Glass netral transparan + blur ringan supaya tidak menutup isi video;
/// ikon keranjang kotak biru brand (bukan kuning TikTok); judul produk
/// (rotasi dikendalikan pemanggil lewat [title] — AnimatedSwitcher crossfade
/// saat judul berganti); `·N` jumlah produk tag + chevron; badge
/// `Diskon s/d {maks}%` terpisah di atas pill bila [maxDiscountPercent] > 0.
///
/// API primitif (tak terikat model) supaya dipakai video & foto lewat builder
/// bersama `feedProductPillFor`.
class FeedProductPill extends StatelessWidget {
  final String title;
  final int count;
  final int maxDiscountPercent;
  final VoidCallback onTap;

  const FeedProductPill({
    super.key,
    required this.title,
    required this.count,
    required this.onTap,
    this.maxDiscountPercent = 0,
  });

  @override
  Widget build(BuildContext context) {
    final white80 = Colors.white.withValues(alpha: 0.8);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (maxDiscountPercent > 0) ...[
          _PillDiscountBadge(percent: maxDiscountPercent),
          const SizedBox(height: 5),
        ],
        Material(
          color: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(3, 3, 9, 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.40),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.14),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 19,
                        height: 19,
                        decoration: BoxDecoration(
                          color: NataloColors.primary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.shopping_bag_outlined,
                          size: 12,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 150),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 260),
                          transitionBuilder: (child, animation) =>
                              FadeTransition(opacity: animation, child: child),
                          child: Text(
                            title,
                            key: ValueKey<String>(title),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              height: 1.2,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '·$count',
                        style: TextStyle(
                          color: white80,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          height: 1,
                        ),
                      ),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 13,
                        color: white80,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PillDiscountBadge extends StatelessWidget {
  final int percent;

  const _PillDiscountBadge({required this.percent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFF4D4F),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_offer, size: 10, color: Colors.white),
          const SizedBox(width: 3),
          Text(
            'Diskon s/d $percent%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9.5,
              fontWeight: FontWeight.w500,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

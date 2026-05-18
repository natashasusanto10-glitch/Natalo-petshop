import 'package:flutter/material.dart';

import '../models/product.dart';
import '../theme/natalo_colors.dart';
import '../theme/natalo_theme.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import '../utils/motion_prefs.dart';

/// Sticky bottom bar yang muncul saat user scroll melewati CTA utama
/// di product detail. Selalu reachable — drive konversi.
///
/// Pakai di Scaffold body sebagai Positioned, atau di bottomSheet area.
class StickyAddToCartBar extends StatelessWidget {
  final Product product;
  final VoidCallback onAddToCart;
  final bool visible;

  const StickyAddToCartBar({
    super.key,
    required this.product,
    required this.onAddToCart,
    this.visible = true,
  });

  @override
  Widget build(BuildContext context) {
    final reduce = MotionPrefs.shouldReduce(context);
    return AnimatedSlide(
      duration: MotionPrefs.effective(
        context,
        const Duration(milliseconds: 240),
      ),
      curve: Curves.easeOutCubic,
      offset: visible ? Offset.zero : const Offset(0, 1.4),
      child: AnimatedOpacity(
        duration:
            MotionPrefs.effective(context, const Duration(milliseconds: 180)),
        opacity: visible ? 1.0 : 0.0,
        child: Material(
          color: Colors.white,
          elevation: 18,
          shadowColor: Colors.black.withValues(alpha: 0.18),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          product.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF111111),
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          formatRupiah(product.finalPrice),
                          style: NataloTextStyles.productPrice.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            height: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: product.stock <= 0
                        ? null
                        : () {
                            if (!reduce) AppHaptics.tap();
                            onAddToCart();
                          },
                    icon: const Icon(
                      Icons.add_shopping_cart_rounded,
                      size: 18,
                    ),
                    label: const Text('Add Cart'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: NataloColors.nataloBlue,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFFE5E7EB),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

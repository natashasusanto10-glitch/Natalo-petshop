import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'feed_colors.dart';

/// Kartu produk anchor di atas identitas kreator (blur, bg black .52,
/// border white .16, radius 14; harga merah #FF5A5F; tombol keranjang
/// oranye #FF7A00 34x34). API primitif — decoupled dari model post,
/// supaya Pratinjau (model Product katalog) bisa memakai widget sama.
///
/// Ekstraksi 1:1 dari feed_screen (dulu `_ProductAnchorCard`) — field
/// model post (`products`/`featuredProduct`/`featuredIndex`) diganti
/// parameter primitif; pemanggil yang menghitung pricing (`formatRupiah`)
/// dan teks badge diskon.
class FeedProductAnchorCard extends StatelessWidget {
  final String title;
  final String? imageUrl;
  final String priceText;
  final String? strikePriceText;
  final String? discountBadgeText;
  final VoidCallback? onAddToCart;
  final VoidCallback? onTap;

  const FeedProductAnchorCard({
    super.key,
    required this.title,
    required this.priceText,
    this.imageUrl,
    this.strikePriceText,
    this.discountBadgeText,
    this.onAddToCart,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final badgeText = discountBadgeText;
    final url = imageUrl;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (badgeText != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFFF4D4F),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              badgeText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ),
          const SizedBox(height: 6),
        ],
        Material(
          color: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.52),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.16),
                    width: 1,
                  ),
                ),
                padding: const EdgeInsets.all(7),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: onTap,
                        borderRadius: BorderRadius.circular(9),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                width: 40,
                                height: 40,
                                child: (url != null && url.isNotEmpty)
                                    ? CachedNetworkImage(
                                        imageUrl: url,
                                        fit: BoxFit.cover,
                                        placeholder: (_, __) => Container(
                                          color: Colors.white
                                              .withValues(alpha: 0.08),
                                        ),
                                        errorWidget: (_, __, ___) => Container(
                                          color: Colors.white
                                              .withValues(alpha: 0.08),
                                          child: const Icon(
                                            Icons.image_not_supported_outlined,
                                            color: Colors.white54,
                                            size: 18,
                                          ),
                                        ),
                                      )
                                    : Container(
                                        color: Colors.white
                                            .withValues(alpha: 0.08),
                                        child: const Icon(
                                          Icons.shopping_bag_outlined,
                                          color: Colors.white54,
                                          size: 18,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 260),
                                transitionBuilder: (child, animation) =>
                                    FadeTransition(
                                        opacity: animation, child: child),
                                child: Column(
                                  key: ValueKey('$title|$priceText'),
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w800,
                                        height: 1.15,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.baseline,
                                      textBaseline: TextBaseline.alphabetic,
                                      children: [
                                        Text(
                                          priceText,
                                          style: const TextStyle(
                                            color: Color(0xFFFF5A5F),
                                            fontSize: 13,
                                            fontWeight: FontWeight.w900,
                                            height: 1,
                                          ),
                                        ),
                                        if (strikePriceText != null) ...[
                                          const SizedBox(width: 5),
                                          // Flexible (bukan Text polos) —
                                          // jaga-jaga di layar/lebar sempit
                                          // supaya harga coret ellipsis
                                          // alih-alih RenderFlex overflow;
                                          // di layar normal tetap tampil
                                          // penuh (ruang cukup) sama seperti
                                          // sebelum ekstraksi.
                                          Flexible(
                                            child: Text(
                                              strikePriceText!,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: Colors.white
                                                    .withValues(alpha: 0.5),
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                height: 1,
                                                decoration:
                                                    TextDecoration.lineThrough,
                                                decorationColor: Colors.white
                                                    .withValues(alpha: 0.5),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _AnchorCartButton(onTap: onAddToCart),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AnchorCartButton extends StatelessWidget {
  final VoidCallback? onTap;

  const _AnchorCartButton({this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: feedCommerceOrange,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: const SizedBox(
          width: 34,
          height: 34,
          child: Icon(
            Icons.add_shopping_cart_rounded,
            color: Colors.white,
            size: 18,
          ),
        ),
      ),
    );
  }
}

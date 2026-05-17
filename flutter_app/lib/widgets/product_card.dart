import 'package:flutter/material.dart';
import '../models/product.dart';
import '../state/cart_store.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import 'app_product_image.dart';
import 'app_toast.dart';
import 'app_ui.dart';
import 'favorite_button.dart';
import 'product_peek_dialog.dart';

/// Kartu produk default — match visual PWA components/ProductCard.tsx.
/// Container: white bg + border tipis + shadow halus (bukan glass), nama 12px
/// font-bold, harga 14px font-black brandBlue, strikethrough abu kalau diskon,
/// Member badge biru di pojok kalau ada memberPrice.
///
/// [showAddToCart] menampilkan tombol "+ Keranjang" wide pill di bawah card,
/// match PWA Products grid + Cart recommendations. Default false untuk
/// backward compat dengan tempat lain (mis. Home grid 2-col yang sudah ada).
class ProductCard extends StatelessWidget {
  final Product product;
  final void Function() onTap;
  final bool showAddToCart;
  // Wishlist heart di pojok kanan atas card. Default true untuk
  // backward compat (carousel home, recommendation grid). Set false
  // di Products grid screen — wishlist diakses dari product detail
  // page saja, supaya card lebih clean (konvensi Tokopedia/Shopee).
  final bool showWishlistButton;

  const ProductCard({
    super.key,
    required this.product,
    required this.onTap,
    this.showAddToCart = false,
    this.showWishlistButton = true,
  });

  @override
  Widget build(BuildContext context) {
    final hasMemberPrice =
        product.memberPrice != null && product.memberPrice! < product.price;

    return GestureDetector(
      onLongPress: () {
        // iOS-style peek — long-press preview tanpa navigate detail.
        showProductPeek(
          context,
          product: product,
          onOpenDetail: onTap,
          onAddToCart: () {
            cartStore.addProduct(product);
            AppToast.showCartAdded(
              context,
              '${product.title} masuk keranjang',
            );
          },
        );
      },
      child: AppPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE8EEF7)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF111111).withValues(alpha: 0.05),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Image area: aspect square, object-contain dengan padding 8 ──
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        color: Colors.white,
                        padding: const EdgeInsets.all(8),
                        child: Hero(
                          tag: 'product-image-${product.id}',
                          // Custom flight: rounded corner morph + subtle
                          // scale-up (102% → 100%) saat sampai detail.
                          // Tertiery: tambah cross-fade tipis supaya
                          // transisi tidak jarring kalau image cache miss.
                          flightShuttleBuilder: (
                            flightContext,
                            animation,
                            flightDirection,
                            fromHeroContext,
                            toHeroContext,
                          ) {
                            final isPush =
                                flightDirection == HeroFlightDirection.push;
                            final scaleTween = isPush
                                ? Tween<double>(begin: 0.96, end: 1.0)
                                : Tween<double>(begin: 1.0, end: 0.96);
                            final curved = CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOutCubic,
                              reverseCurve: Curves.easeInCubic,
                            );
                            return AnimatedBuilder(
                              animation: curved,
                              builder: (context, child) {
                                return Transform.scale(
                                  scale: scaleTween.evaluate(curved),
                                  child: child,
                                );
                              },
                              child: toHeroContext.widget,
                            );
                          },
                          child: AppProductImage(
                            imageUrl: product.imageUrl,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (hasMemberPrice)
                    Positioned(
                      left: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3B82F6),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.80),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: const Text(
                          'Member',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                  if (showWishlistButton)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: FavoriteButton(
                        product: product,
                        size: 34,
                        elevated: false,
                      ),
                    ),
                ],
              ),
            ),

            // ── Info: nama (max 2 baris) + harga utama + strikethrough ──
            const SizedBox(height: 8),
            SizedBox(
              height: 38,
              child: Text(
                product.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF27272A),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              formatRupiah(product.finalPrice),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF1E5FBF),
                fontSize: 14,
                fontWeight: FontWeight.w900,
                height: 1.05,
              ),
            ),
            if (product.hasDiscount)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  formatRupiah(product.price),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              ),
            if (showAddToCart) ...[
              const SizedBox(height: 8),
              // Row: stock indicator (kiri) + cart icon button 34×34 (kanan).
              // Pattern reference: informasi stok visible langsung tanpa
              // perlu tap detail, dan CTA cart compact (bukan full pill).
              _StockAndCartRow(product: product),
            ],
          ],
        ),
      ),
    ),
    );
  }
}

/// Row stock indicator + cart icon button 34×34 (reference pattern).
/// - Kiri: text "Stok X" hijau kalau ada / "Stok habis" merah
/// - Kanan: square primary button dengan add_shopping_cart icon
/// Pattern Tokopedia/Shopee — informative + minimalist CTA.
class _StockAndCartRow extends StatelessWidget {
  final Product product;

  const _StockAndCartRow({required this.product});

  @override
  Widget build(BuildContext context) {
    final outOfStock = product.stock <= 0;
    return Row(
      children: [
        Expanded(
          child: Text(
            outOfStock ? 'Stok habis' : 'Stok ${product.stock}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: outOfStock
                  ? const Color(0xFFEF4444)
                  : const Color(0xFF16A34A),
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Material(
          color: outOfStock
              ? const Color(0xFFCBD5E1)
              : const Color(0xFF0B7FEA),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: outOfStock
                ? null
                : () {
                    AppHaptics.success();
                    cartStore.addProduct(product);
                    AppToast.showCartAdded(
                      context,
                      '${product.title} masuk keranjang',
                    );
                  },
            borderRadius: BorderRadius.circular(12),
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
        ),
      ],
    );
  }
}

/// Pill button "+ Keranjang" — DEPRECATED. Diganti _StockAndCartRow.
/// Saat ini tidak digunakan, dipertahankan kalau-kalau ada caller lain.
// ignore: unused_element
class _AddToCartPill extends StatelessWidget {
  final Product product;

  const _AddToCartPill({required this.product});

  @override
  Widget build(BuildContext context) {
    final outOfStock = product.stock <= 0;
    return SizedBox(
      width: double.infinity,
      height: 34,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: outOfStock
              ? null
              : () {
                  AppHaptics.success();
                  cartStore.addProduct(product);
                  AppToast.showCartAdded(
                    context,
                    '${product.title} masuk keranjang',
                  );
                },
          borderRadius: BorderRadius.circular(999),
          child: Ink(
            decoration: BoxDecoration(
              color: outOfStock
                  ? const Color(0xFFEFF2F6)
                  : const Color(0xFF1E5FBF),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    outOfStock ? Icons.block_rounded : Icons.add_rounded,
                    size: 16,
                    color: outOfStock
                        ? const Color(0xFF9CA3AF)
                        : Colors.white,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    outOfStock ? 'Habis' : 'Keranjang',
                    style: TextStyle(
                      color: outOfStock
                          ? const Color(0xFF9CA3AF)
                          : Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
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

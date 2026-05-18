import 'package:flutter/material.dart';
import '../models/product.dart';
import '../state/cart_store.dart';
import '../state/member_store.dart';
import '../theme/natalo_colors.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import 'app_product_image.dart';
import 'app_toast.dart';
import 'app_ui.dart';
import 'favorite_button.dart';
import 'product_peek_dialog.dart';

/// Kartu produk default — match visual PWA components/ProductCard.tsx.
/// Container: white bg + border tipis + shadow halus (bukan glass), nama 12px
/// font-bold, harga brandBlue, hemat badge soft, rating + sold metadata,
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
                  color: NataloColors.nataloBlue,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
              ProductSavingsBadge(product: product),
              ProductRatingSoldMeta(product: product),
              if (showAddToCart) ...[
                const Spacer(),
                const SizedBox(height: 8),
                _GridCartButton(product: product),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ProductSavingsBadge extends StatelessWidget {
  final Product product;

  const ProductSavingsBadge({
    super.key,
    required this.product,
  });

  @override
  Widget build(BuildContext context) {
    final voucher = product.voucherPreview;
    final label = voucher?.badgeLabel.trim().isNotEmpty == true
        ? voucher!.badgeLabel
        : productSavingsLabel(product);
    if (label == null) return const SizedBox.shrink();

    final badge = Container(
      constraints: const BoxConstraints(maxWidth: double.infinity),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEEF4),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFFFB8CF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (voucher != null) ...[
            const Icon(
              Icons.confirmation_number_rounded,
              size: 11,
              color: Color(0xFFE91E63),
            ),
            const SizedBox(width: 3),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFE91E63),
                fontSize: 10.8,
                fontWeight: FontWeight.w900,
                height: 1.05,
              ),
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: voucher == null
          ? badge
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                AppHaptics.tap();
                _showVoucherPreviewSheet(context, product, voucher);
              },
              child: badge,
            ),
    );
  }
}

Future<void> _showVoucherPreviewSheet(
  BuildContext context,
  Product product,
  ProductVoucherPreview voucher,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      final isLoggedIn = memberStore.isLoggedIn;

      return SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.all(10),
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 30,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFE5EF),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.local_offer_rounded,
                      color: Color(0xFFE91E63),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Voucher Produk Natalo',
                          style: TextStyle(
                            color: Color(0xFF111827),
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          product.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F6),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFFFB8CF)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      voucher.badgeLabel,
                      style: const TextStyle(
                        color: Color(0xFFE91E63),
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      voucher.sheetSubtitle,
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (voucher.description != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        voucher.description!,
                        style: const TextStyle(
                          color: Color(0xFF4B5563),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Voucher akan dicek ulang otomatis saat checkout. Guest boleh melihat promo ini, tetapi perlu login member untuk memakai voucher.',
                style: TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(
                      context,
                      isLoggedIn ? '/cart' : '/member/login',
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: NataloColors.nataloBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: Text(
                    isLoggedIn ? 'Pakai di checkout' : 'Login untuk pakai',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class ProductRatingSoldMeta extends StatelessWidget {
  final Product product;

  const ProductRatingSoldMeta({
    super.key,
    required this.product,
  });

  @override
  Widget build(BuildContext context) {
    final hasRating = product.rating > 0;
    final hasSold = product.soldCount > 0;

    if (!hasRating && !hasSold) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        children: [
          if (hasRating) ...[
            const Icon(
              Icons.star_rounded,
              size: 13,
              color: Color(0xFFFFA000),
            ),
            const SizedBox(width: 2),
            Text(
              product.rating.toStringAsFixed(1),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF4B5563),
                fontSize: 11.2,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ],
          if (hasRating && hasSold) ...[
            const SizedBox(width: 5),
            const Text(
              '•',
              style: TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
            const SizedBox(width: 5),
          ],
          if (hasSold)
            Flexible(
              child: Text(
                '${formatSoldCount(product.soldCount)} terjual',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF4B5563),
                  fontSize: 11.2,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String? productSavingsLabel(Product product) {
  if (!product.hasDiscount) return null;
  final savings = (product.price - product.finalPrice).round();
  if (savings <= 0) return null;
  return 'Hemat ${formatRupiah(savings)}';
}

String formatSoldCount(int value) {
  if (value >= 1000000) {
    return '${_compactDecimal(value / 1000000)}jt+';
  }
  if (value >= 1000) {
    return '${_compactDecimal(value / 1000)}rb+';
  }
  return '$value+';
}

String _compactDecimal(double value) {
  final fixed =
      value >= 10 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
  return fixed.replaceAll('.', ',').replaceAll(',0', '');
}

/// Compact cart button untuk grid produk. Stok tetap dipakai untuk disable
/// action, tapi teks stok tidak ditampilkan di card grid.
class _GridCartButton extends StatelessWidget {
  final Product product;

  const _GridCartButton({required this.product});

  @override
  Widget build(BuildContext context) {
    final outOfStock = product.stock <= 0;
    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: outOfStock ? const Color(0xFFCBD5E1) : const Color(0xFF0B7FEA),
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
    );
  }
}

/// Pill button "+ Keranjang" — DEPRECATED. Diganti _GridCartButton.
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
                    color: outOfStock ? const Color(0xFF9CA3AF) : Colors.white,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    outOfStock ? 'Habis' : 'Keranjang',
                    style: TextStyle(
                      color:
                          outOfStock ? const Color(0xFF9CA3AF) : Colors.white,
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

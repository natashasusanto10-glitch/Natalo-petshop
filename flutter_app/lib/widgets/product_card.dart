import 'package:flutter/material.dart';
import '../models/product.dart';
import '../state/cart_store.dart';
import '../state/member_store.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
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
    final discountPercent = productDiscountPercent(product);

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
        borderRadius: AppRadius.large,
        child: Container(
          padding: AppSpacing.cardPaddingSmall,
          decoration: BoxDecoration(
            color: NataloColors.surface,
            borderRadius: AppRadius.large,
            border: Border.all(color: NataloColors.border),
            boxShadow: [
              BoxShadow(
                color: NataloColors.black.withValues(alpha: 0.04),
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
                        borderRadius: AppRadius.large,
                        child: Container(
                          color: NataloColors.white,
                          padding: const EdgeInsets.all(AppSpacing.sm),
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
                        left: AppSpacing.sm,
                        top: AppSpacing.sm,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.xs,
                          ),
                          decoration: BoxDecoration(
                            color: NataloColors.info,
                            borderRadius: AppRadius.pill,
                            border: Border.all(
                              color: NataloColors.white.withValues(alpha: 0.80),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    NataloColors.black.withValues(alpha: 0.05),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: const Text(
                            'Member',
                            style: TextStyle(
                              color: NataloColors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                    if (discountPercent != null)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: _ImageDiscountBadge(percent: discountPercent),
                      ),
                    if (showWishlistButton)
                      Positioned(
                        right: AppSpacing.xs,
                        top: discountPercent != null ? 38 : AppSpacing.xs,
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
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                height: 38,
                child: Text(
                  product.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: NataloColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
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
                const SizedBox(height: AppSpacing.sm),
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
    final shippingVoucher = product.shippingVoucherPreview;
    final productLabel = voucher?.badgeLabel.trim().isNotEmpty == true
        ? voucher!.badgeLabel.trim()
        : productSavingsLabel(product);
    final shippingLabel = shippingVoucher?.badgeLabel.trim().isNotEmpty == true
        ? shippingVoucher!.badgeLabel.trim()
        : shippingVoucher != null
            ? 'Gratis Ongkir'
            : null;

    final badges = <Widget>[
      if (productLabel != null)
        _ProductPromoBadge(
          label: productLabel,
          icon: voucher == null
              ? Icons.local_offer_rounded
              : Icons.confirmation_number_rounded,
          foregroundColor: NataloColors.danger,
          backgroundColor: NataloColors.dangerSoft,
          borderColor: NataloColors.danger.withValues(alpha: 0.28),
          onTap: voucher == null
              ? null
              : () {
                  AppHaptics.tap();
                  _showVoucherPreviewSheet(context, product, voucher);
                },
        ),
      if (shippingLabel != null)
        _ProductPromoBadge(
          label: shippingLabel,
          icon: Icons.local_shipping_rounded,
          foregroundColor: NataloColors.successDark,
          backgroundColor: NataloColors.successSoft,
          borderColor: NataloColors.success.withValues(alpha: 0.30),
          onTap: () {
            AppHaptics.tap();
            _showVoucherPreviewSheet(context, product, shippingVoucher!);
          },
        ),
    ];

    if (badges.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: badges,
      ),
    );
  }
}

class _ProductPromoBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color foregroundColor;
  final Color backgroundColor;
  final Color borderColor;
  final VoidCallback? onTap;

  const _ProductPromoBadge({
    required this.label,
    required this.icon,
    required this.foregroundColor,
    required this.backgroundColor,
    required this.borderColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      constraints: const BoxConstraints(maxWidth: double.infinity),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: AppRadius.pill,
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 11,
            color: foregroundColor,
          ),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foregroundColor,
                fontSize: 10.8,
                fontWeight: FontWeight.w900,
                height: 1.05,
              ),
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return badge;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: badge,
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
      final isShippingVoucher = voucher.isShippingVoucher;
      final isNewMemberVoucher = voucher.isNewMemberOnly;
      final accentColor =
          isShippingVoucher ? NataloColors.successDark : NataloColors.danger;
      final accentSoft = isShippingVoucher
          ? NataloColors.successSoft
          : NataloColors.dangerSoft;
      final voucherTitle = isShippingVoucher
          ? 'Voucher Gratis Ongkir Natalo'
          : isNewMemberVoucher
              ? 'Voucher New Member Natalo'
              : 'Voucher Produk Natalo';
      final voucherNote = isShippingVoucher
          ? 'Voucher gratis ongkir akan dicek ulang otomatis saat checkout. Guest boleh melihat promo ini, tetapi perlu login member untuk memakai voucher.'
          : isNewMemberVoucher
              ? 'Voucher khusus member baru. Guest boleh melihat promo ini, tetapi perlu daftar atau login member baru untuk memakai voucher saat checkout.'
              : 'Voucher akan dicek ulang otomatis saat checkout. Guest boleh melihat promo ini, tetapi perlu login member untuk memakai voucher.';

      return SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.all(AppSpacing.md),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.md,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          decoration: BoxDecoration(
            color: NataloColors.white,
            borderRadius: AppRadius.extraExtraLarge,
            boxShadow: [
              BoxShadow(
                color: NataloColors.black.withValues(alpha: 0.18),
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
                    color: NataloColors.grey200,
                    borderRadius: AppRadius.pill,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: accentSoft,
                      borderRadius: AppRadius.large,
                    ),
                    child: Icon(
                      isShippingVoucher
                          ? Icons.local_shipping_rounded
                          : Icons.local_offer_rounded,
                      color: accentColor,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          voucherTitle,
                          style: const TextStyle(
                            color: NataloColors.grey900,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          product.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: NataloColors.grey500,
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
              const SizedBox(height: AppSpacing.lg),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: accentSoft,
                  borderRadius: AppRadius.extraLarge,
                  border: Border.all(
                    color: accentColor.withValues(alpha: 0.28),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      voucher.badgeLabel,
                      style: TextStyle(
                        color: accentColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      voucher.sheetSubtitle,
                      style: const TextStyle(
                        color: NataloColors.grey500,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (isNewMemberVoucher) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.xs,
                        ),
                        decoration: BoxDecoration(
                          color: NataloColors.white.withValues(alpha: 0.74),
                          borderRadius: AppRadius.pill,
                          border: Border.all(
                            color: accentColor.withValues(alpha: 0.22),
                          ),
                        ),
                        child: const Text(
                          'Khusus member baru',
                          style: TextStyle(
                            color: NataloColors.danger,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                    if (voucher.description != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        voucher.description!,
                        style: const TextStyle(
                          color: NataloColors.grey600,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                voucherNote,
                style: const TextStyle(
                  color: NataloColors.grey500,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
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
                    foregroundColor: NataloColors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadius.large,
                    ),
                  ),
                  child: Text(
                    isLoggedIn
                        ? 'Pakai di checkout'
                        : isNewMemberVoucher
                            ? 'Daftar/Login untuk pakai'
                            : 'Login untuk pakai',
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
    final hasReview = product.reviewCount > 0;
    final hasSold = product.soldCount > 0;

    if (!hasRating && !hasReview && !hasSold) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        children: [
          if (hasRating || hasReview) ...[
            const Icon(
              Icons.star_rounded,
              size: 13,
              color: NataloColors.warning,
            ),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: RichText(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  style: const TextStyle(
                    color: NataloColors.grey600,
                    fontSize: 11.2,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                  children: [
                    if (hasRating)
                      TextSpan(text: product.rating.toStringAsFixed(1)),
                    if (hasRating && hasReview) const TextSpan(text: ' '),
                    if (hasReview)
                      TextSpan(
                        text: hasRating
                            ? '(${formatSoldCount(product.reviewCount)})'
                            : '${formatSoldCount(product.reviewCount)} ulasan',
                        style: const TextStyle(
                          color: NataloColors.grey500,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
          if ((hasRating || hasReview) && hasSold) ...[
            const SizedBox(width: AppSpacing.sm),
            const Text(
              '•',
              style: TextStyle(
                color: NataloColors.grey400,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          if (hasSold)
            Flexible(
              child: Text(
                '${formatSoldCount(product.soldCount)} terjual',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: NataloColors.grey600,
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

/// Compute discount percentage 0-99 (round down). Return null kalau
/// product tidak hasDiscount atau price = 0.
int? productDiscountPercent(Product product) {
  if (!product.hasDiscount) return null;
  if (product.price <= 0) return null;
  final pct =
      ((product.price - product.finalPrice) / product.price * 100).floor();
  if (pct <= 0) return null;
  // Cap di 99 supaya pill tidak overflow visual (mis. 3-digit "100%").
  return pct > 99 ? 99 : pct;
}

class _ImageDiscountBadge extends StatelessWidget {
  final int percent;

  const _ImageDiscountBadge({required this.percent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: const BoxDecoration(
        color: NataloColors.danger,
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(16),
          bottomLeft: Radius.circular(12),
        ),
      ),
      child: Text(
        '-$percent%',
        style: const TextStyle(
          color: NataloColors.white,
          fontSize: 12,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}

String formatSoldCount(int value) {
  if (value >= 1000000) {
    return '${_compactDecimal(value / 1000000)}jt+';
  }
  if (value >= 1000) {
    return '${_compactDecimal(value / 1000)}rb+';
  }
  if (value >= 100) return '${(value ~/ 50) * 50}+';
  return '$value';
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
        color: outOfStock ? NataloColors.grey300 : NataloColors.primary,
        borderRadius: AppRadius.medium,
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
          borderRadius: AppRadius.medium,
          child: const SizedBox(
            width: 34,
            height: 34,
            child: Icon(
              Icons.add_shopping_cart_rounded,
              color: NataloColors.white,
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
          borderRadius: AppRadius.pill,
          child: Ink(
            decoration: BoxDecoration(
              color: outOfStock ? NataloColors.infoSoft : NataloColors.primary,
              borderRadius: AppRadius.pill,
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    outOfStock ? Icons.block_rounded : Icons.add_rounded,
                    size: 16,
                    color:
                        outOfStock ? NataloColors.grey400 : NataloColors.white,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    outOfStock ? 'Habis' : 'Keranjang',
                    style: TextStyle(
                      color: outOfStock
                          ? NataloColors.grey400
                          : NataloColors.white,
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

import 'package:flutter/material.dart';

import '../models/product.dart';
import '../utils/formatters.dart';
import 'app_product_image.dart';

const _cardBlue = Color(0xFF1565D8);
const _textDark = Color(0xFF111827);
const _textMuted = Color(0xFF6B7280);
const _borderSoft = Color(0xFFE5E7EB);
const _discountRed = Color(0xFFE11D48);
const _discountSoft = Color(0xFFFFF1F2);
const _shippingGreen = Color(0xFF16A34A);
const _shippingSoft = Color(0xFFECFDF3);
const _starAmber = Color(0xFFF59E0B);

/// Compact product card for cart and wishlist surfaces only.
///
/// This intentionally does not replace the global [ProductCard]; it mirrors
/// the approved marketplace-style card for secondary shopping surfaces.
class CompactCommerceProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;
  final VoidCallback onAddToCart;
  final double? width;

  const CompactCommerceProductCard({
    super.key,
    required this.product,
    required this.onTap,
    required this.onAddToCart,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final adminDiscount = _adminDiscount(product);
    final discountPercent = _adminDiscountPercent(product);
    final promoChips = _promoChips(product, hasAdminDiscount: adminDiscount);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: width,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _borderSoft, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.045),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ProductImage(
                product: product,
                discountPercent: discountPercent,
              ),
              const SizedBox(height: 10),
              Text(
                product.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _textDark,
                  fontSize: 13.5,
                  height: 1.22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (promoChips.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: promoChips,
                ),
              ],
              const SizedBox(height: 7),
              _RatingSoldRow(product: product),
              const Spacer(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: _PriceBlock(
                      product: product,
                      hasAdminDiscount: adminDiscount,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _CartButton(
                    enabled: product.stock > 0,
                    onTap: onAddToCart,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductImage extends StatelessWidget {
  final Product product;
  final int? discountPercent;

  const _ProductImage({
    required this.product,
    required this.discountPercent,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.14,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                color: const Color(0xFFF8FAFC),
                padding: const EdgeInsets.all(8),
                child: AppProductImage(
                  imageUrl: product.imageUrl,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          if (discountPercent != null)
            Positioned(
              top: 0,
              right: 0,
              child: _DiscountBadge(percent: discountPercent!),
            ),
        ],
      ),
    );
  }
}

class _DiscountBadge extends StatelessWidget {
  final int percent;

  const _DiscountBadge({required this.percent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: const BoxDecoration(
        color: _discountRed,
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(16),
          bottomLeft: Radius.circular(14),
        ),
      ),
      child: Text(
        '$percent%',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          height: 1,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _PromoChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color foreground;
  final Color background;
  final Color border;

  const _PromoChip({
    required this.label,
    this.icon,
    required this.foreground,
    required this.background,
    required this.border,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 150),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: border, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: foreground),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground,
                  fontSize: 10.8,
                  height: 1,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RatingSoldRow extends StatelessWidget {
  final Product product;

  const _RatingSoldRow({required this.product});

  @override
  Widget build(BuildContext context) {
    final hasRating = product.rating > 0;
    final hasSold = product.soldCount > 0;

    if (!hasRating && !hasSold) return const SizedBox.shrink();

    return Row(
      children: [
        if (hasRating) ...[
          const Icon(Icons.star_rounded, color: _starAmber, size: 15),
          const SizedBox(width: 3),
          Text(
            product.rating.toStringAsFixed(1),
            style: const TextStyle(
              color: _textDark,
              fontSize: 11.8,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ],
        if (hasRating && hasSold) ...[
          const SizedBox(width: 6),
          const Text(
            '•',
            style: TextStyle(
              color: Color(0xFF9CA3AF),
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(width: 6),
        ],
        if (hasSold)
          Flexible(
            child: Text(
              '${_formatSoldCount(product.soldCount)} terjual',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _textMuted,
                fontSize: 11.8,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
          ),
      ],
    );
  }
}

class _PriceBlock extends StatelessWidget {
  final Product product;
  final bool hasAdminDiscount;

  const _PriceBlock({
    required this.product,
    required this.hasAdminDiscount,
  });

  @override
  Widget build(BuildContext context) {
    if (!hasAdminDiscount) {
      return Text(
        formatRupiah(product.finalPrice),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: _textDark,
          fontSize: 20,
          height: 1.04,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.25,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          formatRupiah(product.price),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _textDark,
            fontSize: 12.5,
            height: 1.05,
            fontWeight: FontWeight.w700,
            decoration: TextDecoration.lineThrough,
            decorationThickness: 1.5,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          formatRupiah(product.finalPrice),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _discountRed,
            fontSize: 20,
            height: 1.04,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.25,
          ),
        ),
      ],
    );
  }
}

class _CartButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;

  const _CartButton({
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: enabled ? const Color(0xFFBFD5FF) : _borderSoft,
              width: 1.2,
            ),
          ),
          child: Icon(
            enabled ? Icons.shopping_cart_outlined : Icons.block_rounded,
            size: 22,
            color: enabled ? _cardBlue : const Color(0xFF9CA3AF),
          ),
        ),
      ),
    );
  }
}

List<Widget> _promoChips(
  Product product, {
  required bool hasAdminDiscount,
}) {
  final chips = <Widget>[];

  if (hasAdminDiscount) {
    chips.add(
      const _PromoChip(
        label: 'Harga Diskon',
        foreground: _discountRed,
        background: _discountSoft,
        border: Color(0xFFFFC9D0),
      ),
    );
  }

  if (product.shippingVoucherPreview != null) {
    chips.add(
      const _PromoChip(
        label: 'Gratis Ongkir',
        icon: Icons.local_shipping_rounded,
        foreground: _shippingGreen,
        background: _shippingSoft,
        border: Color(0xFFBBF7D0),
      ),
    );
  }

  final voucherLabel = _voucherSavingsLabel(product);
  if (voucherLabel != null) {
    chips.add(
      _PromoChip(
        label: voucherLabel,
        icon: Icons.confirmation_number_rounded,
        foreground: _discountRed,
        background: _discountSoft,
        border: const Color(0xFFFFC9D0),
      ),
    );
  }

  return chips;
}

bool _adminDiscount(Product product) {
  final discount = product.discountPrice;
  return discount != null && discount > 0 && discount < product.price;
}

int? _adminDiscountPercent(Product product) {
  if (!_adminDiscount(product) || product.price <= 0) return null;
  final discount = product.discountPrice!;
  final percent = ((product.price - discount) / product.price * 100).round();
  if (percent <= 0) return null;
  return percent > 99 ? 99 : percent;
}

String? _voucherSavingsLabel(Product product) {
  final label = product.voucherPreview?.badgeLabel.trim();
  if (label == null || label.isEmpty) return null;
  if (label.toLowerCase().startsWith('hemat')) return label;
  return 'Hemat $label';
}

String _formatSoldCount(int value) {
  if (value >= 1000000) {
    return '${_compactDecimal(value / 1000000)}jt+';
  }
  if (value >= 1000) {
    return '${_compactDecimal(value / 1000)}rb+';
  }
  if (value >= 100) return '${(value ~/ 50) * 50}+';
  return value.toString();
}

String _compactDecimal(double value) {
  final fixed =
      value >= 10 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
  return fixed.replaceAll('.', ',').replaceAll(',0', '');
}

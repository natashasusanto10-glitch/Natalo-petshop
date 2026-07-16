import 'package:flutter/material.dart';

import '../../../models/feed_post.dart';
import '../../../theme/natalo_colors.dart';
import '../../../utils/action_throttle.dart';
import '../../../utils/formatters.dart';
import '../../../widgets/app_product_image.dart';
import '../../../widgets/compact_commerce_product_card.dart' show commerceGridSurfaceTint;
import '../../../widgets/sheet_drag_handle.dart';
import 'feed_post_shared_widgets.dart';

// Token kartu Katalog (Opsi 2). Literal lokal — di file asal (compact_commerce
// _product_card.dart) juga literal privat; redeklarasi di sini disengaja.
const _discountRed = Color(0xFFE11D48);
const _starAmber = Color(0xFFF59E0B);
const _cartBorder = Color(0xFFBFD5FF);

/// Kartu grid produk di sheet Links (Opsi 2) — meniru token kartu Katalog
/// (`CompactCommerceProductCard` squareImage), tapi diisi `FeedProductLink`.
/// Foto 1:1 cover full-bleed, badge -N%, harga coret+merah, rating•terjual
/// (sembunyi kalau 0), tombol keranjang biru.
class FeedProductGridCard extends StatelessWidget {
  final FeedProductLink product;
  final VoidCallback onTap;
  final VoidCallback onAddToCart;

  const FeedProductGridCard({
    super.key,
    required this.product,
    required this.onTap,
    required this.onAddToCart,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pricing = feedPostProductPricing(product);
    final percent = product.discountPercent;
    final showRating = product.avgRating > 0 || product.soldCount > 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: cs.outlineVariant, width: 1),
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
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: AppProductImage(
                        imageUrl: product.imageUrl,
                        fit: BoxFit.cover,
                        borderRadius: BorderRadius.zero,
                      ),
                    ),
                    if (percent > 0)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: _NBadge(percent: percent),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 13.5,
                        height: 1.22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (showRating) ...[
                      const SizedBox(height: 7),
                      _RatingSoldRow(product: product),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(child: _PriceBlock(pricing: pricing)),
                        const SizedBox(width: 8),
                        _CartButton(
                          enabled: product.isAvailable && product.stock > 0,
                          onTap: onAddToCart,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sheet Links ala TikTok — grid 2 kolom produk tag. Draggable (naik/ikut jari,
/// snap), latar abu muda supaya kartu putih menonjol. Pemanggil (host feed)
/// bertanggung jawab menjeda video via [onOpened]/[onClosed].
Future<void> showFeedProductLinksSheet(
  BuildContext context, {
  required List<FeedProductLink> products,
  required void Function(FeedProductLink) onOpenProduct,
  required void Function(FeedProductLink) onAddToCart,
  VoidCallback? onOpened,
  VoidCallback? onClosed,
}) {
  onOpened?.call();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.40),
    enableDrag: false, // DraggableScrollableSheet yang pegang gesture
    builder: (sheetContext) => _FeedProductLinksSheet(
      products: products,
      onOpenProduct: (link) {
        Navigator.of(sheetContext).pop();
        onOpenProduct(link);
      },
      onAddToCart: onAddToCart,
    ),
  ).whenComplete(() => onClosed?.call());
}

class _FeedProductLinksSheet extends StatelessWidget {
  final List<FeedProductLink> products;
  final void Function(FeedProductLink) onOpenProduct;
  final void Function(FeedProductLink) onAddToCart;

  const _FeedProductLinksSheet({
    required this.products,
    required this.onOpenProduct,
    required this.onAddToCart,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.66,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: commerceGridSurfaceTint(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                const SheetDragHandle(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                  child: Row(
                    children: [
                      Text(
                        'Produk (${products.length})',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 0.62,
                    ),
                    itemCount: products.length,
                    itemBuilder: (context, i) {
                      final product = products[i];
                      return FeedProductGridCard(
                        product: product,
                        onTap: () => onOpenProduct(product),
                        onAddToCart: () => onAddToCart(product),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _NBadge extends StatelessWidget {
  final int percent;
  const _NBadge({required this.percent});

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
        '-$percent%',
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

class _PriceBlock extends StatelessWidget {
  final FeedPostProductPricing pricing;
  const _PriceBlock({required this.pricing});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (!pricing.hasPromo) {
      return Text(
        formatRupiah(pricing.displayPrice),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: cs.onSurface,
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
          formatRupiah(pricing.originalPrice),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 12.5,
            height: 1.05,
            fontWeight: FontWeight.w700,
            decoration: TextDecoration.lineThrough,
            decorationThickness: 1.5,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          formatRupiah(pricing.displayPrice),
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

class _RatingSoldRow extends StatelessWidget {
  final FeedProductLink product;
  const _RatingSoldRow({required this.product});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasRating = product.avgRating > 0;
    final hasSold = product.soldCount > 0;
    return Row(
      children: [
        if (hasRating) ...[
          const Icon(Icons.star_rounded, color: _starAmber, size: 15),
          const SizedBox(width: 3),
          Text(
            product.avgRating.toStringAsFixed(1),
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 11.8,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ],
        if (hasRating && hasSold) ...[
          const SizedBox(width: 6),
          Text('•',
              style: TextStyle(
                  color: cs.onSurfaceVariant, fontSize: 11.5, height: 1,
                  fontWeight: FontWeight.w900)),
          const SizedBox(width: 6),
        ],
        if (hasSold)
          Flexible(
            child: Text(
              '${product.soldCount} terjual',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cs.onSurfaceVariant,
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

class _CartButton extends StatefulWidget {
  final bool enabled;
  final VoidCallback onTap;
  const _CartButton({required this.enabled, required this.onTap});

  @override
  State<_CartButton> createState() => _CartButtonState();
}

class _CartButtonState extends State<_CartButton> {
  final ActionThrottle _throttle =
      ActionThrottle(interval: const Duration(milliseconds: 650));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: widget.enabled ? () => _throttle.run(widget.onTap) : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: widget.enabled ? _cartBorder : cs.outlineVariant,
              width: 1.2,
            ),
          ),
          child: Icon(
            widget.enabled
                ? Icons.shopping_cart_outlined
                : Icons.block_rounded,
            size: 22,
            color: widget.enabled ? NataloColors.primary : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

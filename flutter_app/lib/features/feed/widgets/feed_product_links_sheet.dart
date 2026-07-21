import 'package:flutter/material.dart';

import '../../../models/feed_post.dart';
import '../../../theme/natalo_colors.dart';
import '../../../utils/action_throttle.dart';
import '../../../utils/formatters.dart';
import '../../../widgets/app_product_image.dart';
import '../../../widgets/compact_commerce_product_card.dart' show commerceGridSurfaceTint;
import '../../../widgets/sheet_drag_handle.dart';
import 'feed_post_shared_widgets.dart';

// Token warna kartu produk sheet Links — 3 hue tetap (biru aksen, hijau
// ongkir, merah diskon/hemat) + amber brand-eksklusif dari NataloColors.
// Redeklarasi lokal disengaja (pola sama dgn compact_commerce_product_card).
const _discountRed = Color(0xFFE11D48);
const _discountSoft = Color(0xFFFFF1F2);
const _shippingGreen = Color(0xFF16A34A);
const _shippingSoft = Color(0xFFECFDF3);
const _starAmber = Color(0xFFF59E0B);
const _cartBorder = Color(0xFFBFD5FF);

/// Sheet Links ala TikTok/IG — daftar produk tag di video/foto. Draggable
/// (naik/ikut jari, snap), latar abu muda supaya kartu putih menonjol.
/// Pemanggil (host feed) bertanggung jawab menjeda video via
/// [onOpened]/[onClosed].
///
/// Layout adaptif jumlah produk:
///   - 1 produk  → [FeedProductSingleCard] (foto besar, semua sinyal promo,
///     dua tombol) — ruang sheet dipakai penuh dgn sengaja, bukan 1 baris
///     tipis di tengah area kosong.
///   - 2+ produk → [FeedProductRowCard] list baris (hairline, 1 chip
///     prioritas/baris) — lebih banyak info per produk tanpa sesak,
///     scannable ala TikTok Shop/IG.
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
    // Drag-to-dismiss bawaan modal: tarik turun dari handle/header/atas-list
    // menutup sheet (ala TikTok Links). Sebelumnya false + DraggableScrollable
    // Sheet(minChildSize .45) → tarik turun cuma mengecil ke 45% lalu mentok,
    // tak pernah menutup, dan handle tak menggerakkan sheet.
    enableDrag: true,
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
    final single = products.length == 1;
    // Tinggi ADAPTIF: Column mainAxisSize.min + ListView shrinkWrap →
    // sheet setinggi konten (2-3 produk = separuh layar), capped 85% biar
    // tak pernah nabrak status bar; produk banyak otomatis scroll di dalam.
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: commerceGridSurfaceTint(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SheetDragHandle(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 14, 12),
                child: Row(
                  children: [
                    Text(
                      single ? 'Produk di video' : 'Produk',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    if (!single) ...[
                      const SizedBox(width: 6),
                      Text(
                        '${products.length}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ],
                ),
              ),
              if (single)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: FeedProductSingleCard(
                    product: products.first,
                    onTap: () => onOpenProduct(products.first),
                    onAddToCart: () => onAddToCart(products.first),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    itemCount: products.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      thickness: 0.5,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    itemBuilder: (context, i) {
                      final product = products[i];
                      return FeedProductRowCard(
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
      ),
    );
  }
}

/// Pilih SATU chip prioritas untuk tampil di baris list (2+ produk) — biar
/// tak bersaing dgn chip lain di ruang sempit. Prioritas: Brand Eksklusif >
/// Gratis Ongkir. Hemat (kalau ada & bukan yg terpilih) turun jadi teks
/// halus di bawah harga (lihat [_SecondaryLine]).
_ProductChipData? _primaryChip(FeedProductLink product) {
  if (product.isBrandExclusiveVoucher) {
    return const _ProductChipData(
      label: 'Brand Eksklusif',
      icon: Icons.workspace_premium_rounded,
      foreground: NataloColors.brandExclusiveDark,
      background: NataloColors.brandExclusiveSoft,
    );
  }
  if (product.shippingVoucher != null) {
    return const _ProductChipData(
      label: 'Gratis Ongkir',
      icon: Icons.local_shipping_rounded,
      foreground: _shippingGreen,
      background: _shippingSoft,
    );
  }
  return null;
}

class _ProductChipData {
  final String label;
  final IconData icon;
  final Color foreground;
  final Color background;
  const _ProductChipData({
    required this.label,
    required this.icon,
    required this.foreground,
    required this.background,
  });
}

class _PromoChip extends StatelessWidget {
  final _ProductChipData data;
  const _PromoChip({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: data.background,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(data.icon, size: 12, color: data.foreground),
          const SizedBox(width: 4),
          Text(
            data.label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              color: data.foreground,
            ),
          ),
        ],
      ),
    );
  }
}

/// Badge diskon di pojok foto — label & warna beda per sumber
/// (Flash Sale = merah + petir, Promo Toko = merah lembut + tag), paritas
/// dengan label yang dipakai kartu Katalog (feedPostProductPricing).
class _DiscountSourceBadge extends StatelessWidget {
  final bool isFlashSale;
  const _DiscountSourceBadge({required this.isFlashSale});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: isFlashSale ? _discountRed : _discountRed.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isFlashSale ? Icons.bolt_rounded : Icons.sell_rounded,
            size: 11,
            color: Colors.white,
          ),
          const SizedBox(width: 3),
          Text(
            isFlashSale ? 'Flash Sale' : 'Diskon',
            style: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// Baris list produk (2+ produk di sheet) — hairline separator (bukan
/// kartu+shadow), 1 chip promo prioritas, harga jadi fokus, hemat/rating
/// sebagai teks sekunder halus, tombol keranjang outline 44px.
class FeedProductRowCard extends StatelessWidget {
  final FeedProductLink product;
  final VoidCallback onTap;
  final VoidCallback onAddToCart;

  const FeedProductRowCard({
    super.key,
    required this.product,
    required this.onTap,
    required this.onAddToCart,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pricing = feedPostProductPricing(product);
    final chip = _primaryChip(product);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Stack(
                children: [
                  AppProductImage(
                    imageUrl: product.imageUrl,
                    fit: BoxFit.cover,
                    width: 72,
                    height: 72,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  if (product.hasDiscountSource)
                    Positioned(
                      top: 4,
                      left: 4,
                      child: _DiscountSourceBadge(
                        isFlashSale: product.isFlashSale,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (chip != null) _PromoChip(data: chip),
                    const SizedBox(height: 6),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.end,
                      spacing: 7,
                      children: [
                        Text(
                          formatRupiah(pricing.displayPrice),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -0.2,
                          ),
                        ),
                        if (pricing.hasPromo)
                          Text(
                            formatRupiah(pricing.originalPrice),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 11,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                      ],
                    ),
                    _SecondaryLine(product: product, chip: chip),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _CartButton(
                enabled: product.isAvailable && product.stock > 0,
                onTap: onAddToCart,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Teks halus di bawah harga — prioritas: hemat voucher (kalau tak jadi
/// chip utama) → rating•terjual → nothing. Satu baris, tak bersaing dgn
/// harga di atasnya.
class _SecondaryLine extends StatelessWidget {
  final FeedProductLink product;
  final _ProductChipData? chip;
  const _SecondaryLine({required this.product, required this.chip});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final discountVoucher = product.discountVoucher;
    // Hemat cuma jadi teks sekunder kalau BUKAN sudah tampil sebagai chip
    // utama (chip utama sekarang cuma Brand Eksklusif/Gratis Ongkir, jadi
    // hemat selalu boleh tampil di sini kalau ada).
    if (discountVoucher != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(
          discountVoucher.badgeLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
            color: _discountRed,
          ),
        ),
      );
    }
    final hasRating = product.avgRating > 0;
    final hasSold = product.soldCount > 0;
    if (!hasRating && !hasSold) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          if (hasRating) ...[
            const Icon(Icons.star_rounded, color: _starAmber, size: 12),
            const SizedBox(width: 3),
            Text(
              product.avgRating.toStringAsFixed(1),
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 10.5,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
          if (hasRating && hasSold) ...[
            const SizedBox(width: 5),
            Text('·', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 10.5)),
            const SizedBox(width: 5),
          ],
          if (hasSold)
            Flexible(
              child: Text(
                '${product.soldCount} terjual',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Kartu tunggal untuk 1 produk — ruang sheet dipakai penuh dgn sengaja:
/// foto besar, semua chip promo yang relevan (tak bersaing dgn kartu lain),
/// dua tombol (Lihat Detail outline + Tambah ke Keranjang accent).
class FeedProductSingleCard extends StatelessWidget {
  final FeedProductLink product;
  final VoidCallback onTap;
  final VoidCallback onAddToCart;

  const FeedProductSingleCard({
    super.key,
    required this.product,
    required this.onTap,
    required this.onAddToCart,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pricing = feedPostProductPricing(product);
    final chips = <_ProductChipData>[
      if (product.shippingVoucher != null)
        const _ProductChipData(
          label: 'Gratis Ongkir',
          icon: Icons.local_shipping_rounded,
          foreground: _shippingGreen,
          background: _shippingSoft,
        ),
      if (product.isBrandExclusiveVoucher)
        const _ProductChipData(
          label: 'Brand Eksklusif',
          icon: Icons.workspace_premium_rounded,
          foreground: NataloColors.brandExclusiveDark,
          background: NataloColors.brandExclusiveSoft,
        ),
      if (product.discountVoucher != null)
        _ProductChipData(
          label: product.discountVoucher!.badgeLabel,
          icon: Icons.confirmation_number_rounded,
          foreground: _discountRed,
          background: _discountSoft,
        ),
    ];
    final showRating = product.avgRating > 0 || product.soldCount > 0;
    final enabled = product.isAvailable && product.stock > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Stack(
                children: [
                  AppProductImage(
                    imageUrl: product.imageUrl,
                    fit: BoxFit.cover,
                    width: 104,
                    height: 104,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  if (product.hasDiscountSource)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: _DiscountSourceBadge(
                        isFlashSale: product.isFlashSale,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
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
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        height: 1.32,
                      ),
                    ),
                    if (showRating) ...[
                      const SizedBox(height: 6),
                      _RatingSoldRow(product: product),
                    ],
                    const SizedBox(height: 6),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.end,
                      spacing: 8,
                      children: [
                        Text(
                          formatRupiah(pricing.displayPrice),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 20,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -0.3,
                          ),
                        ),
                        if (pricing.hasPromo)
                          Text(
                            formatRupiah(pricing.originalPrice),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 12,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: chips.map((c) => _PromoChip(data: c)).toList(),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onTap,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  side: const BorderSide(color: _cartBorder, width: 1.3),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  foregroundColor: NataloColors.primary,
                ),
                child: const Text(
                  'Lihat Detail',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: _AddToCartButton(enabled: enabled, onTap: onAddToCart),
            ),
          ],
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
          const Icon(Icons.star_rounded, color: _starAmber, size: 13),
          const SizedBox(width: 4),
          Text(
            product.avgRating.toStringAsFixed(1),
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
        if (hasRating && hasSold) ...[
          const SizedBox(width: 6),
          Text('·', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
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
                fontSize: 11,
                fontWeight: FontWeight.w400,
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
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: widget.enabled ? () => _throttle.run(widget.onTap) : null,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: widget.enabled ? _cartBorder : cs.outlineVariant,
              width: 1.3,
            ),
          ),
          child: Icon(
            widget.enabled
                ? Icons.shopping_cart_outlined
                : Icons.block_rounded,
            size: 20,
            color: widget.enabled ? NataloColors.primary : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _AddToCartButton extends StatefulWidget {
  final bool enabled;
  final VoidCallback onTap;
  const _AddToCartButton({required this.enabled, required this.onTap});

  @override
  State<_AddToCartButton> createState() => _AddToCartButtonState();
}

class _AddToCartButtonState extends State<_AddToCartButton> {
  final ActionThrottle _throttle =
      ActionThrottle(interval: const Duration(milliseconds: 650));

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: widget.enabled ? () => _throttle.run(widget.onTap) : null,
      style: ElevatedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        backgroundColor: NataloColors.primary,
        disabledBackgroundColor:
            Theme.of(context).colorScheme.surfaceContainerHighest,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        elevation: 0,
      ),
      icon: Icon(
        widget.enabled ? Icons.add_shopping_cart_rounded : Icons.block_rounded,
        size: 17,
      ),
      label: Text(
        widget.enabled ? 'Tambah ke Keranjang' : 'Stok Habis',
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
    );
  }
}

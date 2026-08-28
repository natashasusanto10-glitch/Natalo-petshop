import 'package:flutter/material.dart';

import '../models/product.dart';
import '../screens/image_viewer_screen.dart';
import '../services/product_service.dart';
import '../state/cart_store.dart';
import '../theme/natalo_colors.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import '../utils/product_media.dart';
import 'app_product_image.dart';
import 'app_ui.dart';

const _brandBlue = NataloColors.nataloBlue;
const _discountRed = Color(0xFFE53958);

typedef ProductFetcher = Future<Product?> Function(String slug);

/// Hasil pilih varian: produk penuh + varian terpilih.
class ProductVariantPickResult {
  final Product product;
  final ProductVariant variant;

  const ProductVariantPickResult({
    required this.product,
    required this.variant,
  });
}

/// Bottom sheet pilih varian sebuah produk (fetch penuh by slug). Dipakai
/// halaman Cart (ganti varian) dan sheet Links feed (tambah ke keranjang
/// produk bervarian tanpa keluar dari video).
class ProductVariantPickerSheet extends StatefulWidget {
  final String productSlug;
  final ProductVariant? preselectedVariant;
  final String confirmLabel;
  final Color confirmColor;
  final ProductFetcher? productFetcher;

  const ProductVariantPickerSheet({
    super.key,
    required this.productSlug,
    this.preselectedVariant,
    required this.confirmLabel,
    required this.confirmColor,
    this.productFetcher,
  });

  static Future<ProductVariantPickResult?> show(
    BuildContext context, {
    required String productSlug,
    ProductVariant? preselectedVariant,
    required String confirmLabel,
    required Color confirmColor,
    ProductFetcher? productFetcher,
  }) {
    return showModalBottomSheet<ProductVariantPickResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => ProductVariantPickerSheet(
        productSlug: productSlug,
        preselectedVariant: preselectedVariant,
        confirmLabel: confirmLabel,
        confirmColor: confirmColor,
        productFetcher: productFetcher,
      ),
    );
  }

  @override
  State<ProductVariantPickerSheet> createState() =>
      _ProductVariantPickerSheetState();
}

class _ProductVariantPickerSheetState extends State<ProductVariantPickerSheet> {
  Product? _fullProduct;
  bool _loading = true;
  String? _error;
  final Map<String, String> _selectedOptions = {};

  @override
  void initState() {
    super.initState();
    _loadFullProduct();
  }

  Future<void> _loadFullProduct() async {
    try {
      final fetch = widget.productFetcher ?? productService.fetchProductBySlug;
      final result = await fetch(widget.productSlug);
      if (!mounted) return;
      if (result == null) {
        setState(() {
          _loading = false;
          _error = 'Produk tidak ditemukan.';
        });
        return;
      }
      final preselect = widget.preselectedVariant;
      if (preselect != null) {
        // Cari varian yang cocok id-nya di data penuh (untuk optionIds lengkap).
        ProductVariant current = preselect;
        for (final variant in result.variants) {
          if (variant.id == preselect.id) {
            current = variant;
            break;
          }
        }
        for (final attr in result.variantAttrs) {
          for (final opt in attr.options) {
            if (current.optionIds.contains(opt.id)) {
              _selectedOptions[attr.id] = opt.id;
              break;
            }
          }
        }
      }
      setState(() {
        _fullProduct = result;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Gagal memuat varian. Coba lagi.';
      });
    }
  }

  ProductVariant? get _matchedVariant {
    final product = _fullProduct;
    if (product == null) return null;
    if (_selectedOptions.length < product.variantAttrs.length) return null;
    for (final variant in product.variants) {
      if (!variant.isActive) continue;
      final matches = product.variantAttrs.every((attr) {
        final selectedOpt = _selectedOptions[attr.id];
        return selectedOpt != null && variant.optionIds.contains(selectedOpt);
      });
      if (matches) return variant;
    }
    return null;
  }

  bool _isOptionAvailable(String attrId, String optionId) {
    final product = _fullProduct;
    if (product == null) return false;
    final otherSelected = Map<String, String>.from(_selectedOptions);
    otherSelected.remove(attrId);
    for (final variant in product.variants) {
      if (!variant.isActive) continue;
      if (!variant.optionIds.contains(optionId)) continue;
      final matchesOthers = otherSelected.entries
          .every((entry) => variant.optionIds.contains(entry.value));
      if (matchesOthers) return true;
    }
    return false;
  }

  void _onSelect(String attrId, String optionId) {
    AppHaptics.selection();
    setState(() {
      _selectedOptions[attrId] = optionId;
    });
  }

  /// Buka viewer media produk yang SUDAH ada (dipakai juga oleh Detail
  /// Produk), bukan viewer khusus varian. Untungnya foto tiap varian sudah
  /// ikut masuk galeri lewat [productCarouselImages], jadi user bisa geser
  /// dari foto rasa ke foto kemasan dan video dalam satu tempat.
  ///
  /// Foto varian yang sedang terpilih dipakai sebagai slide awal; kalau
  /// belum ada varian terpilih (atau fotonya tidak ada di galeri), jatuh ke
  /// slide pertama.
  void _openMediaViewer(Product product) {
    AppHaptics.tap();
    final images = productCarouselImages(product);
    if (images.isEmpty) return;
    final variant = _matchedVariant;
    final focusUrl = variant?.imageUrl?.trim().isNotEmpty == true
        ? variant!.imageUrl!
        : product.imageUrl;
    final hasVideo = product.hasVideo;
    final slide = productMediaSlideIndex(
      images: images,
      imageUrl: focusUrl,
      hasVideo: hasVideo,
    );
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ImageViewerScreen(
          images: images,
          initialIndex: slide < 0 ? (hasVideo ? 1 : 0) : slide,
          productMediaViewer: true,
          product: product,
          selectedVariant: variant,
          videoUrl: hasVideo ? product.videoUrl : null,
          videoThumbnailUrl: hasVideo ? product.videoThumbnailUrl : null,
          videoDurationSec: hasVideo ? product.videoDurationSec : null,
          posterImageUrl: product.imageUrl,
          // Tombol "+ Keranjang" di mini bar viewer menjalankan konfirmasi
          // sheet ini, supaya menekan di lapisan mana pun hasilnya sama dan
          // dua-duanya tertutup sekaligus.
          onAddToCart: (_, __) => _confirm(popViewerFirst: true),
        ),
      ),
    );
  }

  void _confirm({bool popViewerFirst = false}) {
    final variant = _matchedVariant;
    final product = _fullProduct;
    if (variant == null || product == null) return;
    AppHaptics.tap();
    final navigator = Navigator.of(context);
    // Viewer berdiri DI ATAS sheet, jadi ia harus ditutup lebih dulu —
    // tanpa ini pop pertama cuma menutup viewer dan sheet tertinggal.
    if (popViewerFirst) navigator.pop();
    navigator.pop(
      ProductVariantPickResult(product: product, variant: variant),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final variant = _matchedVariant;
    return FractionallySizedBox(
      heightFactor: 0.78,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Container(
          color: cs.surface,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Variasi Produk',
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      color: cs.onSurfaceVariant,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: cs.outlineVariant),
              Expanded(child: _buildBody()),
              if (_fullProduct != null && _error == null)
                SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      border: Border(top: BorderSide(color: cs.outlineVariant)),
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: variant != null ? _confirm : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.confirmColor,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(0xFFCBD5E1),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        child: Text(widget.confirmLabel),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final cs = Theme.of(context).colorScheme;
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }
    if (_error != null || _fullProduct == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            _error ?? 'Produk tidak ditemukan.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
    final product = _fullProduct!;
    // Kosong untuk produk 2+ atribut — chip jatuh kembali ke teks polos.
    final thumbnails = variantOptionThumbnails(product);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      children: [
        _VariantSummary(
          product: product,
          variant: _matchedVariant,
          onZoom: () => _openMediaViewer(product),
        ),
        const SizedBox(height: 22),
        for (final attr in product.variantAttrs) ...[
          Text(
            attr.name,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: attr.options.map((opt) {
              final selected = _selectedOptions[attr.id] == opt.id;
              final available = _isOptionAvailable(attr.id, opt.id);
              return _VariantOptionChip(
                label: opt.value,
                thumbnailUrl: thumbnails[opt.id],
                selected: selected,
                available: available,
                onTap: () => _onSelect(attr.id, opt.id),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
        ],
      ],
    );
  }
}

class _ZoomBadge extends StatelessWidget {
  const _ZoomBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.66),
        borderRadius: BorderRadius.circular(7),
      ),
      child: const Icon(
        Icons.open_in_full_rounded,
        size: 15,
        color: Colors.white,
      ),
    );
  }
}

/// Chip satu opsi varian.
///
/// Tinggi minimum 44 (AppMinTapTarget) + ripple InkWell — sebelumnya chip
/// ini cuma GestureDetector setinggi ~34px tanpa umpan balik tekan sama
/// sekali, yang membuat sheet terasa mati saat disentuh.
///
/// GOTCHA: AppMinTapTarget WAJIB jadi ANAK InkWell, bukan pembungkusnya.
/// Flutter tidak punya hitSlop — kalau urutannya dibalik, area tap tidak
/// ikut membesar dan ripple-nya muncul di kotak yang salah.
class _VariantOptionChip extends StatelessWidget {
  final String label;
  final String? thumbnailUrl;
  final bool selected;
  final bool available;
  final VoidCallback onTap;

  const _VariantOptionChip({
    required this.label,
    required this.thumbnailUrl,
    required this.selected,
    required this.available,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final thumb = thumbnailUrl?.trim() ?? '';
    final borderRadius = BorderRadius.circular(99);
    return Semantics(
      button: true,
      selected: selected,
      enabled: available,
      label: available ? label : '$label, stok habis',
      // Tanpa ini Text di dalam ikut menyumbang node sendiri, sehingga
      // pembaca layar menyebut nama varian DUA KALI
      // ("Sarden, stok habis" lalu "Sarden").
      excludeSemantics: true,
      // ...tapi excludeSemantics juga ikut membuang aksi tap milik InkWell,
      // yang bikin chip tak bisa diaktifkan lewat pembaca layar. Jadi aksinya
      // dipasang ulang di sini.
      onTap: available ? onTap : null,
      child: Material(
        color: selected
            ? _brandBlue.withValues(alpha: 0.10)
            : available
                ? cs.surface
                : cs.surfaceContainerHighest,
        borderRadius: borderRadius,
        child: InkWell(
          onTap: available ? onTap : null,
          borderRadius: borderRadius,
          child: AppMinTapTarget(
            child: Container(
              // Padding kiri mengecil saat ada thumbnail supaya foto
              // menempel rapi ke tepi pil, bukan mengambang.
              padding: EdgeInsets.fromLTRB(thumb.isEmpty ? 14 : 6, 6, 14, 6),
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                border: Border.all(
                  color: selected ? _brandBlue : cs.outlineVariant,
                  width: selected ? 1.4 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (thumb.isNotEmpty) ...[
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        shape: BoxShape.circle,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: AppProductImage(
                        imageUrl: thumb,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      color: selected
                          ? _brandBlue
                          : available
                              ? cs.onSurfaceVariant
                              : cs.onSurfaceVariant.withValues(alpha: 0.45),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      decoration:
                          available ? null : TextDecoration.lineThrough,
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

class _VariantSummary extends StatelessWidget {
  final Product product;
  final ProductVariant? variant;
  final VoidCallback onZoom;

  const _VariantSummary({
    required this.product,
    required this.variant,
    required this.onZoom,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selectedVariant = variant;
    final selectedVariantLabel = selectedVariant == null
        ? null
        : cartVariantOptionLabel(product, selectedVariant);
    final imageUrl = selectedVariant?.imageUrl?.trim().isNotEmpty == true
        ? selectedVariant!.imageUrl!
        : product.imageUrl;
    final displayPrice = selectedVariant == null
        ? product.finalPrice.round()
        : effectiveCartVariantPrice(product, selectedVariant);
    final originalPrice = selectedVariant?.price ?? product.price.round();
    final hasDiscount = originalPrice > displayPrice;
    final discountPercent = hasDiscount && originalPrice > 0
        ? (((originalPrice - displayPrice) / originalPrice) * 100).round()
        : 0;
    final stock = selectedVariant?.stock;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92,
          height: 92,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                clipBehavior: Clip.antiAlias,
                child: AppProductImage(imageUrl: imageUrl, fit: BoxFit.cover),
              ),
              // Badge tetap 28px supaya tidak menutupi foto, tapi area
              // tap-nya 44 dan sengaja meluber keluar pojok (Stack
              // clipBehavior none) agar tetap nyaman disentuh.
              Positioned(
                right: -8,
                bottom: -8,
                child: Semantics(
                  button: true,
                  label: 'Perbesar foto produk',
                  // container+exclude+onTap: tanpa `container: true`, Semantics
                  // hanya menempel ke node induk sehingga labelnya melebur
                  // dengan harga ("Perbesar foto produk, Rp55.000, Pilih
                  // varian") dan tombolnya tak bisa difokus sendiri.
                  container: true,
                  excludeSemantics: true,
                  onTap: onZoom,
                  child: Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: onZoom,
                      child: const AppMinTapTarget(
                        child: _ZoomBadge(),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (selectedVariantLabel != null &&
                  selectedVariantLabel.isNotEmpty) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    selectedVariantLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Text(
                formatRupiah(displayPrice.toDouble()),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (hasDiscount) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        formatRupiah(originalPrice.toDouble()),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$discountPercent%',
                      style: const TextStyle(
                        color: _discountRed,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 6),
              Text(
                stock == null ? 'Pilih varian' : 'Stok: $stock',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

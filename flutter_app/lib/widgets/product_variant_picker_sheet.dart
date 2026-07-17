import 'package:flutter/material.dart';

import '../models/product.dart';
import '../services/product_service.dart';
import '../state/cart_store.dart';
import '../theme/natalo_colors.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import 'app_product_image.dart';

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

  void _confirm() {
    final variant = _matchedVariant;
    final product = _fullProduct;
    if (variant == null || product == null) return;
    AppHaptics.tap();
    Navigator.pop(
      context,
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      children: [
        _VariantSummary(product: product, variant: _matchedVariant),
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
              return GestureDetector(
                onTap: available ? () => _onSelect(attr.id, opt.id) : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? _brandBlue.withValues(alpha: 0.10)
                        : available
                            ? cs.surface
                            : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: selected ? _brandBlue : cs.outlineVariant,
                      width: selected ? 1.4 : 1,
                    ),
                  ),
                  child: Text(
                    opt.value,
                    style: TextStyle(
                      color: selected ? _brandBlue : cs.onSurfaceVariant,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
        ],
      ],
    );
  }
}

class _VariantSummary extends StatelessWidget {
  final Product product;
  final ProductVariant? variant;

  const _VariantSummary({required this.product, required this.variant});

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

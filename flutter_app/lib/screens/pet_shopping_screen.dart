import 'package:flutter/material.dart';

import '../models/pet_shopping.dart';
import '../models/product.dart';
import '../services/pet_service.dart';
import '../services/product_service.dart';
import '../state/cart_store.dart';
import '../theme/natalo_colors.dart';
import '../theme/natalo_text.dart';
import '../utils/formatters.dart';
import '../widgets/added_to_cart_sheet.dart';
import '../widgets/app_product_image.dart';
import '../widgets/app_toast.dart';
import '../widgets/product_variant_picker_sheet.dart';

typedef ProductBySlugFetcher = Future<Product?> Function(String slug);
typedef CartAdder = Future<bool> Function(
  Product product, {
  ProductVariant? variant,
});

/// Buka detail produk dari data belanja.
///
/// PENTING: route `/product-detail` menuntut objek `Product` PENUH sebagai
/// argumen dan TIDAK ADA route berbasis slug di app ini (lihat main.dart:460).
/// Data belanja cuma membawa slug, jadi fetch dulu — tanpa ini navigasi jatuh
/// ke `_ => const HomeScreen()` dan user mendarat di Beranda tanpa penjelasan.
Future<void> openPetShoppingProduct(
  BuildContext context,
  String slug, {
  ProductBySlugFetcher? fetcher,
}) async {
  final fetch = fetcher ?? productService.fetchProductBySlug;
  final product = await fetch(slug);
  if (!context.mounted) return;
  if (product == null) {
    AppToast.show(context, 'Produk tidak ditemukan lagi.',
        kind: ToastKind.error);
    return;
  }
  await Navigator.pushNamed(context, '/product-detail', arguments: product);
}

/// Halaman penuh kolom Belanja pet: grup fakta ("Pernah dipakai") dengan
/// hierarki paling kaya, lalu grup saran ("Mungkin cocok") yang lebih ringan.
/// Hierarki sengaja berbeda supaya tidak terbaca sebagai satu daftar panjang.
class PetShoppingScreen extends StatefulWidget {
  final String petId;
  final String petName;

  /// Seam test — default memakai service nyata.
  final PetShoppingFetcher? fetcher;
  final ProductBySlugFetcher? productFetcher;
  final CartAdder? cartAdder;

  const PetShoppingScreen({
    super.key,
    required this.petId,
    required this.petName,
    this.fetcher,
    this.productFetcher,
    this.cartAdder,
  });

  @override
  State<PetShoppingScreen> createState() => _PetShoppingScreenState();
}

class _PetShoppingScreenState extends State<PetShoppingScreen> {
  PetShopping? _data;
  bool _loading = true;
  bool _failed = false;
  String? _busySlug;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final fetch = widget.fetcher ?? petService.fetchPetShopping;
    try {
      final data = await fetch(widget.petId);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
        _failed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _buyAgain(PetShoppingProduct p) async {
    setState(() => _busySlug = p.slug);
    try {
      final add = widget.cartAdder ??
          (Product product, {ProductVariant? variant}) =>
              cartStore.addProduct(product, variant: variant);

      if (p.hasVariants) {
        // Sheet varian mengambil produk penuh by slug dan mengembalikan
        // Product + ProductVariant terpilih.
        final picked = await ProductVariantPickerSheet.show(
          context,
          productSlug: p.slug,
          confirmLabel: 'Tambah ke keranjang',
          confirmColor: NataloColors.primary,
          productFetcher: widget.productFetcher,
        );
        if (picked == null || !mounted) return;
        final ok = await add(picked.product, variant: picked.variant);
        if (!mounted || !ok) return;
        await showAddedToCartSheet(context, product: picked.product);
        return;
      }

      final fetchProduct =
          widget.productFetcher ?? productService.fetchProductBySlug;
      final product = await fetchProduct(p.slug);
      if (!mounted) return;
      if (product == null) {
        AppToast.show(context, 'Produk tidak ditemukan lagi.',
            kind: ToastKind.error);
        return;
      }
      final ok = await add(product);
      if (!mounted || !ok) return;
      await showAddedToCartSheet(context, product: product);
    } finally {
      if (mounted) setState(() => _busySlug = null);
    }
  }

  void _openCatalog({String? query, String? category}) {
    Navigator.pushNamed(
      context,
      '/products',
      arguments: ProductCatalogArgs(
        initialQuery: query,
        initialCategory: category,
      ),
    );
  }

  Future<void> _openProduct(PetShoppingProduct p) =>
      openPetShoppingProduct(context, p.slug, fetcher: widget.productFetcher);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('Belanja untuk ${widget.petName}')),
      body: Builder(
        builder: (_) {
          if (_loading) {
            return const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          if (_failed) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Gagal memuat belanja ${widget.petName}. Coba lagi nanti.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: NataloWeight.body,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            );
          }
          final data = _data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Pernah dipakai untuk ${widget.petName}',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: NataloWeight.strong),
                ),
              ),
              const SizedBox(height: 8),
              if (data.used.isEmpty && data.manual.isEmpty)
                _EmptyUsed(petName: widget.petName)
              else
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: cs.outlineVariant),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (var i = 0; i < data.used.length; i++) ...[
                        if (i > 0)
                          Divider(
                              height: 0.5,
                              thickness: 0.5,
                              color: cs.outlineVariant),
                        _UsedRow(
                          product: data.used[i],
                          busy: _busySlug == data.used[i].slug,
                          onBuyAgain: () => _buyAgain(data.used[i]),
                          onFindSimilar: () =>
                              _openCatalog(query: data.used[i].name),
                          onTap: () => _openProduct(data.used[i]),
                        ),
                      ],
                      for (final m in data.manual) ...[
                        Divider(
                            height: 0.5,
                            thickness: 0.5,
                            color: cs.outlineVariant),
                        _ManualRow(
                          manual: m,
                          onSearch: () => _openCatalog(query: m.brandText),
                        ),
                      ],
                    ],
                  ),
                ),
              if (data.suggested.isNotEmpty) ...[
                const SizedBox(height: 24),
                Semantics(
                  header: true,
                  child: Text(
                    'Mungkin cocok untuk ${widget.petName}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: NataloWeight.strong,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Bukan GridView.count(childAspectRatio: ...) — rasio tetap
                // overflow saat text scale sistem membesar (kartu berisi
                // gambar 1:1 + nama 2 baris + harga). Baris manual biar
                // tiap kartu tinggi mengikuti kontennya sendiri.
                Column(
                  children: [
                    for (var i = 0; i < data.suggested.length; i += 2)
                      Padding(
                        padding: EdgeInsets.only(
                            bottom:
                                i + 2 < data.suggested.length ? 10 : 0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _SuggestionCard(
                                product: data.suggested[i],
                                onTap: () => _openProduct(data.suggested[i]),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: i + 1 < data.suggested.length
                                  ? _SuggestionCard(
                                      product: data.suggested[i + 1],
                                      onTap: () =>
                                          _openProduct(data.suggested[i + 1]),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              Center(
                child: TextButton(
                  onPressed: () => _openCatalog(),
                  child: const Text(
                    'Jelajahi produk lain',
                    style: TextStyle(
                        fontSize: 13, fontWeight: NataloWeight.strong),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EmptyUsed extends StatelessWidget {
  final String petName;
  const _EmptyUsed({required this.petName});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'Belum ada produk yang tercatat untuk $petName. Catat perawatan dengan produk, nanti muncul di sini.',
        style: TextStyle(
          fontSize: 12,
          fontWeight: NataloWeight.body,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _UsedRow extends StatelessWidget {
  final PetShoppingProduct product;
  final bool busy;
  final VoidCallback onBuyAgain;
  final VoidCallback onFindSimilar;
  final VoidCallback onTap;

  const _UsedRow({
    required this.product,
    required this.busy,
    required this.onBuyAgain,
    required this.onFindSimilar,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final habis = !product.inStock;
    final usage = product.usageCount;
    final last = product.lastUsedAt;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Opacity(
                opacity: habis ? 0.4 : 1,
                child: AppProductImage(
                  imageUrl: product.imageUrl,
                  width: 56,
                  height: 56,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: NataloWeight.strong,
                        color: habis ? cs.onSurfaceVariant : cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    if (habis)
                      Text(
                        'Stok habis',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: NataloWeight.body,
                          color: cs.onSurfaceVariant,
                        ),
                      )
                    else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            'Harga sekarang',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: NataloWeight.body,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            formatRupiah(product.effectivePrice),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: NataloWeight.strong,
                              color: cs.onSurface,
                            ),
                          ),
                        ],
                      ),
                    if (usage != null && last != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        petShoppingUsageLabel(usage, last),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: NataloWeight.body,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Lebar TETAP: nama panjang yang mengalah (ellipsis), bukan tombol.
              SizedBox(
                width: 104,
                child: habis
                    ? Semantics(
                        container: true,
                        excludeSemantics: true,
                        button: true,
                        label: 'Cari serupa, ${product.name}',
                        child: TextButton(
                          onPressed: onFindSimilar,
                          child: const Text('Cari serupa',
                              style: TextStyle(fontSize: 12)),
                        ),
                      )
                    : Semantics(
                        container: true,
                        excludeSemantics: true,
                        button: true,
                        enabled: !busy,
                        label: 'Beli lagi, ${product.name}',
                        child: TextButton(
                          onPressed: busy ? null : onBuyAgain,
                          child: busy
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : const Text('Beli lagi',
                                  style: TextStyle(fontSize: 12)),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManualRow extends StatelessWidget {
  final PetShoppingManual manual;
  final VoidCallback onSearch;

  const _ManualRow({required this.manual, required this.onSearch});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(Icons.edit_note_rounded, size: 22, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  manual.brandText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: NataloWeight.strong,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  petShoppingUsageLabel(manual.usageCount, manual.lastUsedAt),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: NataloWeight.body,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 116,
            child: Semantics(
              button: true,
              label: 'Cari di Natalo, ${manual.brandText}',
              child: TextButton(
                onPressed: onSearch,
                child: const Text('Cari di Natalo',
                    style: TextStyle(fontSize: 12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  final PetShoppingProduct product;
  final VoidCallback onTap;

  const _SuggestionCard({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border.all(color: cs.outlineVariant),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: AppProductImage(
                  imageUrl: product.imageUrl,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: NataloWeight.strong,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                formatRupiah(product.effectivePrice),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: NataloWeight.body,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Argumen named-route `/pets/belanja`.
class PetShoppingArgs {
  final String petId;
  final String petName;
  const PetShoppingArgs({required this.petId, required this.petName});
}

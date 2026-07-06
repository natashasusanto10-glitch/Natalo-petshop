import 'package:flutter/material.dart';

import '../models/product.dart';
import '../services/product_service.dart';
import '../state/cart_store.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import 'app_product_image.dart';
import 'app_toast.dart';
import 'product_card.dart' show ProductSavingsBadge, ProductRatingSoldMeta;

/// Warna disamakan dengan halaman detail produk (product_detail_screen.dart)
/// supaya sheet konsisten dengan tombol "+ Keranjang" di bottom bar.
const _brandBlue = Color(0xFF1565D8);
const _successGreen = Color(0xFF16A34A);
const _disabledGrey = Color(0xFFD1D5DB);
const _disabledText = Color(0xFF9CA3AF);

/// Signature fetch rekomendasi — dibuat injectable supaya sheet bisa
/// di-test tanpa memanggil network. Default: productService.fetchRecommendations.
typedef RecommendationsFetcher = Future<List<Product>> Function({
  List<String> cartIds,
  List<String> viewedIds,
  List<String> excludeIds,
  int limit,
});

/// Bottom sheet "Lengkapi belanjaanmu" — muncul setelah user add product ke
/// keranjang dari halaman detail. Menampilkan konfirmasi + carousel
/// rekomendasi (berbasis isi keranjang) + tombol "Cek Keranjang".
///
/// `initialRelated` dipakai sebagai isi awal carousel (instan, dari
/// `_related` yang sudah ter-load di halaman detail). Saat sheet dibuka,
/// carousel di-refresh dengan rekomendasi berbasis isi keranjang.
Future<void> showAddedToCartSheet(
  BuildContext context, {
  required Product product,
  List<Product> initialRelated = const [],
  RecommendationsFetcher? fetchRecommendations,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _AddedToCartSheet(
      product: product,
      initialRelated: initialRelated,
      fetchRecommendations:
          fetchRecommendations ?? productService.fetchRecommendations,
    ),
  );
}

class _AddedToCartSheet extends StatefulWidget {
  final Product product;
  final List<Product> initialRelated;
  final RecommendationsFetcher fetchRecommendations;

  const _AddedToCartSheet({
    required this.product,
    required this.initialRelated,
    required this.fetchRecommendations,
  });

  @override
  State<_AddedToCartSheet> createState() => _AddedToCartSheetState();
}

class _AddedToCartSheetState extends State<_AddedToCartSheet> {
  late List<Product> _related = List.of(widget.initialRelated);
  bool _refreshed = false;

  @override
  void initState() {
    super.initState();
    _loadCartRecommendations();
  }

  Future<void> _loadCartRecommendations() async {
    final cartIds =
        cartStore.items.map((it) => it.product.id).toList(growable: false);
    final result = await widget.fetchRecommendations(
      cartIds: cartIds,
      viewedIds: cartIds.isEmpty ? [widget.product.id] : const [],
      excludeIds: cartIds.isEmpty ? [widget.product.id] : cartIds,
      limit: 10,
    );
    // Kalau gagal / kosong, pertahankan initialRelated (jangan dikosongkan).
    if (!mounted || result.isEmpty) return;
    setState(() {
      _related = List.of(result);
      _refreshed = true;
    });
  }

  void _openDetail(Product product) {
    AppHaptics.tap();
    final nav = Navigator.of(context);
    nav.pop();
    nav.pushNamed('/product-detail', arguments: product);
  }

  void _addRecommendation(Product product) {
    if (product.hasVariants) {
      // Produk varian tidak bisa langsung ditambah — buka detailnya.
      AppHaptics.tap();
      AppToast.show(
        context,
        'Pilih varian produk dulu.',
        kind: ToastKind.info,
      );
      final nav = Navigator.of(context);
      nav.pop();
      nav.pushNamed('/product-detail', arguments: product);
      return;
    }
    AppHaptics.success();
    cartStore.addProduct(product);
    AppToast.showCartAdded(
      context,
      '${product.title} masuk keranjang',
    );
    setState(() => _related.removeWhere((p) => p.id == product.id));
  }

  void _goToCart() {
    AppHaptics.tap();
    final nav = Navigator.of(context);
    nav.pop();
    nav.pushNamed('/cart');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Lengkapi belanjaanmu',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.of(context).maybePop(),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 46,
                  height: 46,
                  color: cs.surfaceContainerHighest,
                  child: AppProductImage(
                    imageUrl: widget.product.imageUrl,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.product.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 3),
                    const Row(
                      children: [
                        Icon(Icons.check_circle_rounded,
                            size: 16, color: _successGreen),
                        SizedBox(width: 5),
                        Text(
                          'Masuk ke keranjang!',
                          style: TextStyle(
                            color: _successGreen,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_related.isNotEmpty) ...[
            const SizedBox(height: 14),
            Divider(height: 1, color: cs.outlineVariant),
            const SizedBox(height: 14),
            Text(
              'Cek keperluan anabulmu yang lain yuk',
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: SizedBox(
                key: ValueKey(_refreshed),
                height: 296,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _related.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, index) => _SheetRecommendationCard(
                    product: _related[index],
                    onOpenDetail: () => _openDetail(_related[index]),
                    onAddToCart: () => _addRecommendation(_related[index]),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Divider(height: 1, color: cs.outlineVariant),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  key: const ValueKey('cek-keranjang-button'),
                  onPressed: _goToCart,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _brandBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  child: const Text('Cek Keranjang'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetRecommendationCard extends StatelessWidget {
  final Product product;
  final VoidCallback onOpenDetail;
  final VoidCallback onAddToCart;

  const _SheetRecommendationCard({
    required this.product,
    required this.onOpenDetail,
    required this.onAddToCart,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 150,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: onOpenDetail,
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      height: 118,
                      width: double.infinity,
                      color: cs.surfaceContainerHighest,
                      padding: const EdgeInsets.all(6),
                      child: AppProductImage(
                        imageUrl: product.imageUrl,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 32,
                    child: Text(
                      product.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    formatRupiah(product.finalPrice),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _brandBlue,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  ProductSavingsBadge(product: product),
                  ProductRatingSoldMeta(product: product),
                ],
              ),
            ),
            const Spacer(),
            const SizedBox(height: 8),
            _AddPill(
              key: ValueKey('add-to-cart-${product.id}'),
              onTap: onAddToCart,
              outOfStock: product.stock <= 0,
            ),
          ],
        ),
      ),
    );
  }
}

class _AddPill extends StatelessWidget {
  final VoidCallback onTap;
  final bool outOfStock;

  const _AddPill({super.key, required this.onTap, this.outOfStock = false});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: outOfStock ? null : onTap,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          decoration: BoxDecoration(
            color: outOfStock ? _disabledGrey : _brandBlue,
            borderRadius: BorderRadius.circular(10),
          ),
          child: SizedBox(
            height: 32,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  outOfStock ? Icons.block_rounded : Icons.add_rounded,
                  size: 16,
                  color: outOfStock ? _disabledText : Colors.white,
                ),
                const SizedBox(width: 4),
                Text(
                  outOfStock ? 'Habis' : 'Keranjang',
                  style: TextStyle(
                    color: outOfStock ? _disabledText : Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

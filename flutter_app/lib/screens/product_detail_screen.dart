import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/api_config.dart';
import '../models/product.dart';
import '../models/cart_item.dart';
import '../services/app_analytics.dart';
import '../services/app_crashlytics.dart';
import '../services/product_service.dart';
import '../state/cart_store.dart';
import '../state/recently_viewed_store.dart';
import 'checkout_screen.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import '../widgets/app_cart_button.dart';
import '../widgets/app_product_image.dart';
import '../widgets/app_toast.dart';
import '../widgets/app_ui.dart';
import '../widgets/animated_price.dart';
import '../widgets/favorite_button.dart';
import '../widgets/glass_surface.dart';
import '../widgets/product_card.dart';
import '../widgets/product_review_section.dart';
import 'image_viewer_screen.dart';

const _brandBlue = Color(0xFF0B7FEA);

class ProductDetailScreen extends StatefulWidget {
  final Product product;

  const ProductDetailScreen({super.key, required this.product});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  /// Mulai dengan product dari navigation args (untuk fast first paint),
  /// lalu replace dengan data full dari /api/products/{slug} yang punya
  /// variantAttrs + variants lengkap.
  late Product _product = widget.product;
  List<Product> _related = const [];
  // Map attribute.id → selected option.id. Kosong = belum pilih satu pun.
  final Map<String, String> _selectedOptions = {};

  /// Quantity selected oleh user — di-show di body Quantity Card,
  /// digunakan saat Add to Cart / Beli Sekarang.
  int _quantity = 1;

  Product get product => _product;

  void _onQuantityChanged(int next) {
    final maxStock = _displayStock;
    if (maxStock <= 0) return;
    AppHaptics.tap();
    setState(() => _quantity = next.clamp(1, maxStock));
  }

  /// Cari variant yang cocok dengan kombinasi option saat ini.
  /// Return null kalau belum semua attribute dipilih.
  ProductVariant? get _selectedVariant {
    if (!product.hasVariants || product.variantAttrs.isEmpty) return null;
    if (_selectedOptions.length < product.variantAttrs.length) return null;
    final selectedIds = _selectedOptions.values.toSet();
    for (final v in product.variants) {
      if (v.optionIds.length == selectedIds.length &&
          v.optionIds.toSet().containsAll(selectedIds)) {
        return v;
      }
    }
    return null;
  }

  /// Stok yang ditampilkan — dari variant kalau dipilih, fallback ke product.
  int get _displayStock {
    final v = _selectedVariant;
    if (v != null) return v.stock;
    return product.stock;
  }

  /// True kalau produk multi-varian tapi belum semua attribute terpilih.
  bool get _needsVariantSelection {
    return product.hasVariants &&
        product.variantAttrs.isNotEmpty &&
        _selectedVariant == null;
  }

  @override
  void initState() {
    super.initState();
    // Track view fire-and-forget. Match perilaku PWA ProductViewTracker —
    // dipakai untuk personalisasi recommendation di /api/cart/recommendations.
    // Gagal silent (offline, guest, dll), tidak blokir render screen.
    productService.trackView(product.slug);
    // Track ke local recently viewed — Home carousel akan ambil dari sini.
    // Pure client-side, tidak ada side effect ke server.
    recentlyViewedStore.add(product);
    // Analytics — log view_item event untuk funnel analysis (view →
    // add_to_cart → purchase). Standard Firebase recommended event.
    AppAnalytics.logViewProduct(
      productId: product.id,
      productName: product.title,
      price: product.price,
      category: product.category,
    );
    // Crashlytics breadcrumb — kalau crash terjadi nanti, log ini muncul
    // di crash report timeline untuk debug context.
    AppCrashlytics.log('Viewed product: ${product.id} ${product.title}');
    _loadRelated();
    _loadFullProduct();
  }

  /// Fetch full product dari /api/products/{slug} untuk dapat variantAttrs +
  /// variants. Replace state product hanya kalau response valid.
  Future<void> _loadFullProduct() async {
    final full = await productService.fetchProductBySlug(product.slug);
    if (!mounted || full == null) return;
    setState(() {
      _product = full;
      // Auto-select kalau cuma 1 varian yang valid — UX simplification.
      if (full.hasVariants && full.variants.length == 1) {
        final only = full.variants.first;
        _selectedOptions.clear();
        for (final id in only.optionIds) {
          // Find which attribute this option belongs to.
          for (final attr in full.variantAttrs) {
            if (attr.options.any((opt) => opt.id == id)) {
              _selectedOptions[attr.id] = id;
              break;
            }
          }
        }
      }
    });
  }

  void _onSelectOption(String attrId, String optionId) {
    AppHaptics.tap();
    setState(() {
      _selectedOptions[attrId] = optionId;
    });
  }

  Future<void> _loadRelated() async {
    final result = await productService.fetchRecommendations(
      viewedIds: [product.id],
      excludeIds: [product.id],
      limit: 6,
    );
    if (!mounted) return;
    setState(() => _related = result);
  }

  Future<void> _shareProduct(BuildContext context) async {
    AppHaptics.tap();
    final url = '${ApiConfig.publicSiteUrl}/products/${product.slug}';
    final text = '${product.title}\n${formatRupiah(product.finalPrice)}\n$url';
    final box = context.findRenderObject() as RenderBox?;
    try {
      await Share.share(
        text,
        subject: product.title,
        sharePositionOrigin:
            box != null ? box.localToGlobal(Offset.zero) & box.size : null,
      );
    } catch (_) {
      // Fail silently — share sheet ditutup user atau platform tidak support.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Detail Produk'),
        actions: [
          AppHeaderIconButton(
            onPressed: () => _shareProduct(context),
            tooltip: 'Bagikan',
            child: const Icon(Icons.ios_share_rounded),
          ),
          const AppCartButton(),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: _ProductHero(product: product),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _ProductInfo(product: product),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _VoucherAndTrust(product: product),
            ),
          ),
          // ── Variant Selector — hanya tampil kalau hasVariants ──
          if (product.hasVariants && product.variantAttrs.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: _VariantSelector(
                  product: product,
                  selectedOptions: _selectedOptions,
                  selectedVariant: _selectedVariant,
                  onSelect: _onSelectOption,
                ),
              ),
            ),
          // ── Quantity Card (reference pattern) — separate card di body ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _QuantityCard(
                quantity: _quantity,
                stock: _displayStock,
                onChanged: _onQuantityChanged,
              ),
            ),
          ),
          // ── Benefit grid 3 kolom: Brand / Kategori / Stok ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _BenefitGrid(
                brand: product.brand,
                category: product.category,
                stock: _displayStock,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _ProductTabsSection(
                product: product,
                related: _related,
              ),
            ),
          ),
          // ── Pengiriman & Layanan card ──
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _ServiceInfoCard(),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: ProductReviewSection(product: product),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _StickyPurchaseBar(
        product: product,
        selectedVariant: _selectedVariant,
        needsVariantSelection: _needsVariantSelection,
        displayStock: _displayStock,
      ),
    );
  }
}

class _ProductHero extends StatefulWidget {
  final Product product;

  const _ProductHero({required this.product});

  @override
  State<_ProductHero> createState() => _ProductHeroState();
}

class _ProductHeroState extends State<_ProductHero> {
  late final PageController _controller;
  int _activeIndex = 0;

  // Slide pertama = imageUrl (thumbnail utama), sisanya = gallery.
  // Match PWA components/ProductImageCarousel.tsx urutan.
  List<String> get _images {
    final all = <String>[
      if (widget.product.imageUrl.isNotEmpty) widget.product.imageUrl,
      ...widget.product.gallery.where((url) => url.isNotEmpty),
    ];
    // Dedup: kalau imageUrl sama dengan gallery[0], jangan ulang.
    final seen = <String>{};
    return all.where(seen.add).toList();
  }

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final images = _images;
    final showIndicators = images.length > 1;

    return GlassSurface(
      radius: 30,
      padding: EdgeInsets.zero,
      child: Stack(
        children: [
          SizedBox(
            height: 320,
            child: Stack(
              children: [
                Positioned.fill(
                  child: images.isEmpty
                      ? const _ImagePlaceholder()
                      : Hero(
                          tag: 'product-image-${widget.product.id}',
                          child: PageView.builder(
                            controller: _controller,
                            itemCount: images.length,
                            onPageChanged: (index) =>
                                setState(() => _activeIndex = index),
                            itemBuilder: (context, index) {
                              return GestureDetector(
                                // Tap image → buka fullscreen pinch-zoom
                                // gallery viewer dengan native Flutter
                                // InteractiveViewer (smooth + GPU-accelerated).
                                onTap: () {
                                  AppHaptics.tap();
                                  Navigator.push<void>(
                                    context,
                                    PageRouteBuilder<void>(
                                      opaque: false,
                                      barrierColor: Colors.black,
                                      transitionDuration:
                                          const Duration(milliseconds: 280),
                                      reverseTransitionDuration:
                                          const Duration(milliseconds: 220),
                                      pageBuilder: (_, __, ___) =>
                                          ImageViewerScreen(
                                        images: images,
                                        initialIndex: _activeIndex,
                                      ),
                                      transitionsBuilder:
                                          (_, animation, __, child) =>
                                              FadeTransition(
                                        opacity: animation,
                                        child: child,
                                      ),
                                    ),
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(26),
                                  child: AppProductImage(
                                    imageUrl: images[index],
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                ),
                if (showIndicators)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 14,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(images.length, (index) {
                        final active = index == _activeIndex;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          height: 6,
                          width: active ? 18 : 6,
                          decoration: BoxDecoration(
                            color: active
                                ? _brandBlue
                                : _brandBlue.withValues(alpha: 0.30),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        );
                      }),
                    ),
                  ),
                if (showIndicators)
                  Positioned(
                    right: 16,
                    bottom: 14,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${_activeIndex + 1}/${images.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (widget.product.hasDiscount &&
              widget.product.discountPercent != null)
            Positioned(
              left: 14,
              top: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '-${widget.product.discountPercent}%',
                  style: const TextStyle(
                    color: Color(0xFFEF4444),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          Positioned(
            right: 16,
            top: 16,
            child: FavoriteButton(product: widget.product, size: 46),
          ),
        ],
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Icon(
        Icons.image_outlined,
        size: 64,
        color: Color(0xFFE5E7EB),
      ),
    );
  }
}

class _ProductInfo extends StatelessWidget {
  final Product product;

  const _ProductInfo({required this.product});

  String _formatNumberId(num n) {
    final integer = n.round();
    final s = integer.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final reverseIndex = s.length - i;
      buffer.write(s[i]);
      if (reverseIndex > 1 && reverseIndex % 3 == 1) buffer.write('.');
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final hasDiscount = product.hasDiscount;
    final discount = product.discountPercent;
    final showRating = product.rating > 0 && product.reviewCount > 0;

    return GlassSurface(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Blok harga ala PWA PriceBlock: Rp + big number + strikethrough + red -X% ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        const Text(
                          'Rp',
                          style: TextStyle(
                            color: Color(0xFF111827),
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            height: 1,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatNumberId(product.finalPrice),
                          style: const TextStyle(
                            color: Color(0xFF111827),
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            height: 1,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                    if (hasDiscount) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            formatRupiah(product.price),
                            style: const TextStyle(
                              color: Color(0xFF9CA3AF),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                          if (discount != null && discount > 0) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF2F2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '-$discount%',
                                style: const TextStyle(
                                  color: Color(0xFFEF4444),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              AppStatusPill(
                icon: Icons.inventory_2_outlined,
                label: product.stock > 0 ? 'Stok ${product.stock}' : 'Habis',
                color: product.stock > 0
                    ? const Color(0xFF16A34A)
                    : const Color(0xFFEF4444),
              ),
            ],
          ),
          // ── Judul produk ── match PWA: text-base font-semibold (mobile)
          const SizedBox(height: 12),
          Text(
            product.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF111827),
              fontSize: 16,
              fontWeight: FontWeight.w700,
              height: 1.32,
            ),
          ),
          // ── SocialProofRow ── rating + reviewCount inline, format match PWA
          if (showRating) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.star_rounded,
                    size: 16, color: Color(0xFFFBBF24)),
                const SizedBox(width: 4),
                Text(
                  product.rating.toStringAsFixed(1),
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '(${product.reviewCount})',
                  style: const TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 3,
                  height: 3,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE5E7EB),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  product.brand,
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _VoucherAndTrust extends StatelessWidget {
  final Product product;

  const _VoucherAndTrust({required this.product});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AppPressable(
          onTap: () => Navigator.pushNamed(context, '/cart'),
          borderRadius: BorderRadius.circular(24),
          child: GlassSurface(
            radius: 24,
            tint: const Color(0xFFFFFBEB),
            padding: const EdgeInsets.all(16),
            border: Border.all(color: const Color(0xFFFDE68A)),
            child: Row(
              children: [
                Container(
                  height: 42,
                  width: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.local_offer_rounded,
                    color: Color(0xFFF59E0B),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Voucher member tersedia',
                        style: TextStyle(
                          color: Color(0xFF92400E),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Cek voucher di keranjang sebelum checkout.',
                        style: TextStyle(
                          color: Color(0xFFA16207),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFFF59E0B),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Row(
          children: [
            Expanded(
              child: _TrustTile(
                icon: Icons.verified_user_outlined,
                title: 'Original',
                subtitle: 'Produk resmi',
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: _TrustTile(
                icon: Icons.local_shipping_outlined,
                title: 'Cepat',
                subtitle: 'Area Medan',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Tab section "Deskripsi / Rekomendasi" — match PWA components/products/ProductTabs.tsx.
/// 2 tab dengan underline indicator, content lazy switch via IndexedStack.
class _ProductTabsSection extends StatefulWidget {
  final Product product;
  final List<Product> related;

  const _ProductTabsSection({
    required this.product,
    required this.related,
  });

  @override
  State<_ProductTabsSection> createState() => _ProductTabsSectionState();
}

class _ProductTabsSectionState extends State<_ProductTabsSection> {
  int _tabIndex = 0;
  bool _descExpanded = false;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Tab bar ──
          Row(
            children: [
              _Tab(
                label: 'Deskripsi',
                active: _tabIndex == 0,
                onTap: () => setState(() => _tabIndex = 0),
              ),
              _Tab(
                label: 'Rekomendasi',
                active: _tabIndex == 1,
                onTap: () => setState(() => _tabIndex = 1),
              ),
            ],
          ),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          // ── Content ──
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
            child:
                _tabIndex == 0 ? _buildDescription() : _buildRecommendations(),
          ),
        ],
      ),
    );
  }

  Widget _buildDescription() {
    final description = widget.product.description;
    final isLong = description.length > 220;
    final showText = (_descExpanded || !isLong)
        ? description
        : '${description.substring(0, 220)}...';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          showText.isEmpty ? 'Belum ada deskripsi produk.' : showText,
          style: const TextStyle(
            color: Color(0xFF475569),
            fontWeight: FontWeight.w600,
            height: 1.55,
            fontSize: 13.5,
          ),
        ),
        if (isLong) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => setState(() => _descExpanded = !_descExpanded),
            child: Text(
              _descExpanded ? 'Tutup' : 'Baca Selengkapnya',
              style: const TextStyle(
                color: _brandBlue,
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRecommendations() {
    if (widget.related.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            'Belum ada rekomendasi.',
            style: TextStyle(
              color: Color(0xFF9CA3AF),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Rekomendasi Produk',
          style: TextStyle(
            color: Color(0xFF17202A),
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: widget.related.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            // Lebih tinggi untuk metadata hemat + rating/terjual.
            childAspectRatio: 0.54,
          ),
          itemBuilder: (context, index) {
            final product = widget.related[index];
            return ProductCard(
              product: product,
              onTap: () {
                AppHaptics.tap();
                Navigator.pushNamed(
                  context,
                  '/product-detail',
                  arguments: product,
                );
              },
              showAddToCart: true,
            );
          },
        ),
      ],
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _Tab({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: active ? _brandBlue : Colors.transparent,
                  width: 2.5,
                ),
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: active ? _brandBlue : const Color(0xFF9CA3AF),
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Variant Selector — render satu section per attribute (mis. "Ukuran")
/// dengan chip per option. Chip yang di-tap → call onSelect(attrId, optionId).
/// Setelah semua attribute terpilih, _selectedVariant di parent state akan
/// auto-resolve via lookup variants[].optionIds match.
class _VariantSelector extends StatelessWidget {
  final Product product;
  final Map<String, String> selectedOptions;
  final ProductVariant? selectedVariant;
  final void Function(String attrId, String optionId) onSelect;

  const _VariantSelector({
    required this.product,
    required this.selectedOptions,
    required this.selectedVariant,
    required this.onSelect,
  });

  /// Cek apakah satu kombinasi attribute+option ada variant aktif yg cocok.
  /// Dipakai untuk dim/disabled chip yang tidak punya stok atau tidak ada
  /// kombinasi variantnya.
  bool _hasVariantFor(String attrId, String optionId) {
    // Build "trial selection" = selected sekarang + (attrId → optionId) override.
    final trial = Map<String, String>.from(selectedOptions);
    trial[attrId] = optionId;
    final trialIds = trial.values.toSet();
    return product.variants.any((v) {
      // Variant cocok kalau semua optionId di trial ada di variant.optionIds
      // (subset cocok — supaya saat belum semua attribute dipilih, chip yang
      // konsisten dengan sebagian pilihan tetap available).
      return trialIds.every((id) => v.optionIds.contains(id)) && v.stock > 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune_rounded, color: _brandBlue, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Pilih Varian',
                style: TextStyle(
                  color: Color(0xFF17202A),
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              if (selectedVariant != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1FAE5),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Stok ${selectedVariant!.stock}',
                    style: const TextStyle(
                      color: Color(0xFF16A34A),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          for (final attr in product.variantAttrs) ...[
            Text(
              attr.name,
              style: const TextStyle(
                color: Color(0xFF475569),
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: attr.options.map((opt) {
                final selected = selectedOptions[attr.id] == opt.id;
                final available = _hasVariantFor(attr.id, opt.id);
                return _VariantChip(
                  label: opt.value,
                  selected: selected,
                  enabled: available,
                  onTap: available ? () => onSelect(attr.id, opt.id) : null,
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
          ],
          if (selectedVariant != null) ...[
            const Divider(color: Color(0xFFE5E7EB), height: 1),
            const SizedBox(height: 10),
            Row(
              children: [
                const Text(
                  'Harga varian',
                  style: TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                // Animated price ticker — tween smoothly saat user ganti
                // varian (lebih native dari snap di Capacitor WebView).
                AnimatedPrice(
                  price: selectedVariant!.price,
                  style: const TextStyle(
                    color: _brandBlue,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            if (selectedVariant!.sku != null) ...[
              const SizedBox(height: 4),
              Text(
                'SKU: ${selectedVariant!.sku}',
                style: const TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ] else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'Pilih semua varian untuk lihat harga & stok.',
                style: TextStyle(
                  color: Color(0xFFF59E0B),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _VariantChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  const _VariantChip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = selected
        ? _brandBlue
        : enabled
            ? Colors.white
            : const Color(0xFFEFF2F6);
    final borderColor = selected
        ? _brandBlue
        : enabled
            ? const Color(0xFFE5E7EB)
            : const Color(0xFFE5E7EB);
    final textColor = selected
        ? Colors.white
        : enabled
            ? const Color(0xFF334155)
            : const Color(0xFF9CA3AF);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: borderColor),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 13,
              fontWeight: FontWeight.w900,
              decoration: enabled ? null : TextDecoration.lineThrough,
            ),
          ),
        ),
      ),
    );
  }
}

class _StickyPurchaseBar extends StatelessWidget {
  final Product product;
  final ProductVariant? selectedVariant;
  final bool needsVariantSelection;
  final int displayStock;

  const _StickyPurchaseBar({
    required this.product,
    required this.selectedVariant,
    required this.needsVariantSelection,
    required this.displayStock,
  });

  void _onChatWa(BuildContext context) {
    AppHaptics.tap();
    const waNumber = '6281330003880'; // brand WA Natalo
    final text = Uri.encodeComponent(
      'Halo Admin Natalo, saya ingin tanya tentang produk ${product.title}. Apakah ready?',
    );
    final url = Uri.parse('https://wa.me/$waNumber?text=$text');
    // Best-effort — di mobile ini akan trigger WhatsApp intent.
    launchUrl(url, mode: LaunchMode.externalApplication);
  }

  void _showSelectVariantToast(BuildContext context) {
    AppHaptics.warning();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Pilih varian dulu sebelum lanjut.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _onAddToCart(BuildContext context) {
    if (needsVariantSelection) {
      _showSelectVariantToast(context);
      return;
    }
    AppHaptics.success();
    cartStore.addProduct(product, variant: selectedVariant);
    AppToast.showCartAdded(
      context,
      '${product.title} masuk keranjang',
      onTap: () => Navigator.pushNamed(context, '/cart'),
    );
  }

  void _onBeliSekarang(BuildContext context) {
    if (needsVariantSelection) {
      _showSelectVariantToast(context);
      return;
    }
    AppHaptics.impact();
    // Buy Now flow — push CheckoutScreen langsung dengan single-item
    // override (bypass cart). Match reference pattern: user impulsive
    // buy tanpa harus add ke cart dulu.
    final item = CartItem(
      product: product,
      quantity: 1,
      variant: selectedVariant,
    );
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CheckoutScreen(items: [item]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final outOfStock = displayStock <= 0;
    final disabled = outOfStock || needsVariantSelection;
    final buyLabel = outOfStock
        ? 'Stok Habis'
        : needsVariantSelection
            ? 'Pilih Varian'
            : 'Beli Sekarang';
    return AppGlassBottomBar(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          // ── WhatsApp — icon-only supaya bar bawah tetap lega ──
          SizedBox(
            width: 54,
            height: 54,
            child: OutlinedButton(
              onPressed: () => _onChatWa(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF16A34A),
                minimumSize: const Size(54, 54),
                side: const BorderSide(color: Color(0xFFBBF7D0)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                padding: EdgeInsets.zero,
              ),
              child: const _WhatsAppIcon(),
            ),
          ),
          const SizedBox(width: 8),
          // ── + Keranjang — outline biru ──
          Expanded(
            flex: 5,
            child: OutlinedButton(
              onPressed: outOfStock ? null : () => _onAddToCart(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: _brandBlue,
                minimumSize: const Size.fromHeight(54),
                side: const BorderSide(color: Color(0xFFBFDBFE)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '+ Keranjang',
                  maxLines: 1,
                  softWrap: false,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // ── Beli Sekarang — filled biru, lebih lebar (flex 1.3) ──
          Expanded(
            flex: 6,
            child: ElevatedButton(
              onPressed: disabled ? null : () => _onBeliSekarang(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: _brandBlue,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(54),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  buyLabel,
                  maxLines: 1,
                  softWrap: false,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WhatsAppIcon extends StatelessWidget {
  const _WhatsAppIcon();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        const Icon(
          Icons.chat_bubble_rounded,
          color: Color(0xFF22C55E),
          size: 29,
        ),
        Transform.translate(
          offset: const Offset(0, -1),
          child: const Icon(
            Icons.call_rounded,
            color: Colors.white,
            size: 15,
          ),
        ),
      ],
    );
  }
}

class _TrustTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _TrustTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      radius: 20,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          SoftIconTile(icon: icon, size: 40),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF17202A),
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Separate Quantity Card di body — match pattern reference Anda.
/// User adjust qty di sini sebelum scroll ke bottom CTA.
class _QuantityCard extends StatelessWidget {
  final int quantity;
  final int stock;
  final ValueChanged<int> onChanged;

  const _QuantityCard({
    required this.quantity,
    required this.stock,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = stock <= 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Jumlah Produk',
                    style: TextStyle(
                      color: Color(0xFF17202A),
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Pilih jumlah sebelum checkout',
                    style: TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFF7FAFD),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: disabled || quantity <= 1
                        ? null
                        : () => onChanged(quantity - 1),
                    icon: const Icon(Icons.remove_rounded),
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                  ),
                  SizedBox(
                    width: 32,
                    child: Text(
                      disabled ? '0' : quantity.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF17202A),
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: disabled || quantity >= stock
                        ? null
                        : () => onChanged(quantity + 1),
                    icon: const Icon(Icons.add_rounded),
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Benefit grid 3 kolom: Brand / Kategori / Stok.
class _BenefitGrid extends StatelessWidget {
  final String brand;
  final String category;
  final int stock;

  const _BenefitGrid({
    required this.brand,
    required this.category,
    required this.stock,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _BenefitCard(
            icon: Icons.storefront_rounded,
            title: brand.isEmpty ? '-' : brand,
            subtitle: 'Brand',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _BenefitCard(
            icon: Icons.category_rounded,
            title: category.isEmpty ? '-' : category,
            subtitle: 'Kategori',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _BenefitCard(
            icon: Icons.inventory_2_rounded,
            title: stock > 0 ? stock.toString() : '0',
            subtitle: 'Stok',
          ),
        ),
      ],
    );
  }
}

class _BenefitCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _BenefitCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 92,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF0B7FEA), size: 22),
          const Spacer(),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF17202A),
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pengiriman & Layanan card — service rows trust message.
class _ServiceInfoCard extends StatelessWidget {
  const _ServiceInfoCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pengiriman & Layanan',
              style: TextStyle(
                color: Color(0xFF17202A),
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(height: 12),
            _ServiceRow(
              icon: Icons.local_shipping_rounded,
              title: 'Pengiriman cepat',
              description:
                  'Estimasi pengiriman mengikuti alamat dan kurir yang dipilih saat checkout.',
            ),
            SizedBox(height: 12),
            _ServiceRow(
              icon: Icons.verified_rounded,
              title: 'Produk original',
              description:
                  'Disiapkan dari katalog resmi Natalo Petshop, dijamin asli.',
            ),
            SizedBox(height: 12),
            _ServiceRow(
              icon: Icons.support_agent_rounded,
              title: 'Bantuan toko',
              description:
                  'Admin dapat membantu pengecekan produk sebelum pembelian.',
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _ServiceRow({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF5FF),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: const Color(0xFF0B7FEA), size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF17202A),
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                description,
                style: const TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 13,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

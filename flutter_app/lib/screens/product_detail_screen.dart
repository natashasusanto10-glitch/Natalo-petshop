import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/api_config.dart';
import '../models/cart_item.dart';
import '../models/product.dart';
import '../models/review.dart';
import '../services/api_client.dart';
import '../services/app_analytics.dart';
import '../services/app_crashlytics.dart';
import '../services/product_service.dart';
import '../services/report_service.dart';
import '../services/review_service.dart';
import '../services/stock_notification_service.dart';
import '../state/cart_store.dart';
import '../state/member_store.dart';
import '../state/recently_viewed_store.dart';
import 'checkout_screen.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import '../widgets/app_cart_button.dart';
import '../widgets/app_product_image.dart';
import '../widgets/app_toast.dart';
import '../widgets/app_ui.dart';
import '../widgets/animated_price.dart';
import '../widgets/flash_sale_countdown.dart';
import '../widgets/glass_surface.dart';
import '../widgets/moderation_action_sheet.dart';
import 'image_viewer_screen.dart';

const _brandBlue = Color(0xFF1565D8);
const _textDark = Color(0xFF111827);
const _textMedium = Color(0xFF374151);
const _textGray = Color(0xFF6B7280);
const _borderGray = Color(0xFFE5E7EB);
const _softBlueBg = Color(0xFFEAF3FF);
const _discountRed = Color(0xFFE11D48);
const _softDiscountBg = Color(0xFFFFEEF1);
const _successGreen = Color(0xFF16A34A);
const _starAmber = Color(0xFFF59E0B);

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
  ReviewSummary? _reviewSummary;
  List<ProductReview> _reviewPreview = const [];
  bool _descriptionExpanded = false;
  int _activeTab = 0;
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _overviewKey = GlobalKey();
  final GlobalKey _reviewsKey = GlobalKey();
  // Map attribute.id → selected option.id. Kosong = belum pilih satu pun.
  final Map<String, String> _selectedOptions = {};

  Product get product => _product;

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
      price: product.price.round(),
      category: product.category,
    );
    // Crashlytics breadcrumb — kalau crash terjadi nanti, log ini muncul
    // di crash report timeline untuk debug context.
    AppCrashlytics.log('Viewed product: ${product.id} ${product.title}');
    _loadRelated();
    _loadFullProduct();
    _loadReviewPreview();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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

  Future<void> _loadReviewPreview() async {
    try {
      final summaryFuture = reviewService.fetchSummary(product.slug);
      final reviewsFuture = reviewService.fetchReviews(product.slug);
      final summary = await summaryFuture;
      final reviews = await reviewsFuture;
      if (!mounted) return;
      setState(() {
        _reviewSummary = summary;
        _reviewPreview = reviews.reviews.take(2).toList();
      });
    } catch (_) {
      // Review preview is non-critical; product detail should still render.
    }
  }

  void _scrollToSection(GlobalKey key, int tabIndex) {
    AppHaptics.tap();
    setState(() => _activeTab = tabIndex);
    final targetContext = key.currentContext;
    if (targetContext == null) return;
    Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 340),
      curve: Curves.easeOutCubic,
      alignment: 0.08,
    );
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.08),
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
        controller: _scrollController,
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: _ProductHero(product: product),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
              child: _ProductInfo(
                product: product,
                displayStock: _displayStock,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
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
          SliverPersistentHeader(
            pinned: true,
            delegate: _ProductSectionTabsDelegate(
              activeIndex: _activeTab,
              onRecommendationTap: () => _scrollToSection(_overviewKey, 0),
              onReviewsTap: () => _scrollToSection(_reviewsKey, 1),
            ),
          ),
          SliverToBoxAdapter(
            child: KeyedSubtree(
              key: _overviewKey,
              child: _ProductInformationSection(
                product: product,
                displayStock: _displayStock,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _ProductDescriptionSection(
              product: product,
              expanded: _descriptionExpanded,
              onToggle: () {
                AppHaptics.tap();
                setState(() => _descriptionExpanded = !_descriptionExpanded);
              },
            ),
          ),
          SliverToBoxAdapter(
            child: _ProductRecommendationSection(related: _related),
          ),
          SliverToBoxAdapter(
            child: KeyedSubtree(
              key: _reviewsKey,
              child: _ProductReviewPreviewSection(
                product: product,
                summary: _reviewSummary,
                reviews: _reviewPreview,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 116)),
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
            height: 390,
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
                                  padding: const EdgeInsets.all(8),
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
                    left: 16,
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
  final int displayStock;

  const _ProductInfo({
    required this.product,
    required this.displayStock,
  });

  @override
  Widget build(BuildContext context) {
    final hasDiscount = product.hasDiscount;
    final discount = product.discountPercent;
    final savings = product.price - product.finalPrice;
    final hasRating = product.rating > 0;
    final hasReviews = product.reviewCount > 0;
    final hasSold = product.soldCount > 0;
    final inStock = displayStock > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasDiscount) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _softDiscountBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$discount% OFF',
              style: const TextStyle(
                color: _discountRed,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        Text(
          formatRupiah(product.finalPrice),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _textDark,
            fontSize: 32,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
        if (hasDiscount) ...[
          const SizedBox(height: 10),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: [
              Text(
                formatRupiah(product.price),
                style: const TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.lineThrough,
                ),
              ),
              Text(
                '$discount%',
                style: const TextStyle(
                  color: _discountRed,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (savings > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _softDiscountBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Hemat ${formatRupiah(savings)}',
                    style: const TextStyle(
                      color: _discountRed,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 18),
        Text(
          product.title,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _textDark,
            fontSize: 20,
            fontWeight: FontWeight.w900,
            height: 1.22,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (hasRating) ...[
              const Icon(Icons.star_rounded, size: 18, color: _starAmber),
              const SizedBox(width: 4),
              Text(
                product.rating.toStringAsFixed(1),
                style: const TextStyle(
                  color: _textMedium,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ] else
              const Text(
                'Belum ada ulasan',
                style: TextStyle(
                  color: _textGray,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            if (hasReviews) ...[
              const _InfoDot(),
              Text(
                '${product.reviewCount} ulasan',
                style: const TextStyle(
                  color: _textGray,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (hasSold) ...[
              const _InfoDot(),
              Text(
                '${_formatCompactCount(product.soldCount)} terjual',
                style: const TextStyle(
                  color: _textGray,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        Text(
          inStock ? 'Stok $displayStock tersedia' : 'Stok habis',
          style: TextStyle(
            color: inStock ? _successGreen : _discountRed,
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
        // Flash Sale countdown badge — hanya muncul kalau admin tag
        // produk ini dengan flashSaleEndsAt (Tier 1). Auto-hide saat
        // timer reach 0 atau expired.
        if (product.hasFlashSaleCountdown) ...[
          const SizedBox(height: 10),
          FlashSaleCountdown.compact(
            endsAt: product.flashSaleEndsAt!,
          ),
        ],
      ],
    );
  }
}

class _InfoDot extends StatelessWidget {
  const _InfoDot();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        '•',
        style: TextStyle(
          color: Color(0xFF9CA3AF),
          fontSize: 14,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _VoucherAndTrust extends StatelessWidget {
  final Product product;

  const _VoucherAndTrust({required this.product});

  @override
  Widget build(BuildContext context) {
    final voucher = product.voucherPreview;
    final voucherLabel = voucher?.badgeLabel.trim();
    final subtitle = voucherLabel != null && voucherLabel.isNotEmpty
        ? voucher?.isNewMemberOnly == true
            ? '$voucherLabel • khusus member baru saat checkout'
            : '$voucherLabel • cek di keranjang sebelum checkout'
        : 'Cek voucher di keranjang sebelum checkout';

    return AppPressable(
      onTap: () => Navigator.pushNamed(context, '/cart'),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _borderGray),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              height: 44,
              width: 44,
              decoration: BoxDecoration(
                color: _softBlueBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.percent_rounded, color: _brandBlue),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Voucher tersedia',
                    style: TextStyle(
                      color: _textDark,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _textGray,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: _textDark),
          ],
        ),
      ),
    );
  }
}

class _SectionShell extends StatelessWidget {
  final Widget child;

  const _SectionShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: child,
    );
  }
}

class _ProductSectionTabsDelegate extends SliverPersistentHeaderDelegate {
  final int activeIndex;
  final VoidCallback onRecommendationTap;
  final VoidCallback onReviewsTap;

  const _ProductSectionTabsDelegate({
    required this.activeIndex,
    required this.onRecommendationTap,
    required this.onReviewsTap,
  });

  @override
  double get minExtent => 56;

  @override
  double get maxExtent => 56;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return _ProductSectionTabs(
      activeIndex: activeIndex,
      onRecommendationTap: onRecommendationTap,
      onReviewsTap: onReviewsTap,
      elevated: overlapsContent || shrinkOffset > 0,
    );
  }

  @override
  bool shouldRebuild(covariant _ProductSectionTabsDelegate oldDelegate) {
    return oldDelegate.activeIndex != activeIndex;
  }
}

class _ProductSectionTabs extends StatelessWidget {
  final int activeIndex;
  final bool elevated;
  final VoidCallback onRecommendationTap;
  final VoidCallback onReviewsTap;

  const _ProductSectionTabs({
    required this.activeIndex,
    required this.elevated,
    required this.onRecommendationTap,
    required this.onReviewsTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: elevated ? 1 : 0,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      child: Container(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _borderGray)),
        ),
        child: Row(
          children: [
            _Tab(
              label: 'Rekomendasi',
              active: activeIndex == 0,
              onTap: onRecommendationTap,
            ),
            _Tab(
              label: 'Ulasan',
              active: activeIndex == 1,
              onTap: onReviewsTap,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductInformationSection extends StatelessWidget {
  final Product product;
  final int displayStock;

  const _ProductInformationSection({
    required this.product,
    required this.displayStock,
  });

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      _InfoRow(label: 'Berat Produk', value: _formatWeight(product.weightGram)),
      if (product.brand.isNotEmpty)
        _InfoRow(label: 'Brand', value: product.brand),
      if (product.category.isNotEmpty)
        _InfoRow(label: 'Kategori', value: product.category),
      _InfoRow(
        label: 'Stok',
        value: displayStock > 0 ? 'Tersedia' : 'Habis',
        valueColor: displayStock > 0 ? _successGreen : _discountRed,
      ),
    ];
    return _SectionShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Informasi Produk',
            style: TextStyle(
              color: _textDark,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          ...rows,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              '$label:',
              style: const TextStyle(
                color: _textGray,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor ?? _textDark,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductDescriptionSection extends StatelessWidget {
  final Product product;
  final bool expanded;
  final VoidCallback onToggle;

  const _ProductDescriptionSection({
    required this.product,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final description = product.description.trim();
    final hasDescription = description.isNotEmpty;
    return _SectionShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Deskripsi Produk',
            style: TextStyle(
              color: _textDark,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            hasDescription
                ? description
                : '${product.title} tersedia sebagai produk berkualitas untuk kebutuhan hewan peliharaan Anda.',
            maxLines: expanded ? null : 4,
            overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            style: const TextStyle(
              color: _textMedium,
              fontSize: 14,
              height: 1.55,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (description.length > 160) ...[
            const SizedBox(height: 8),
            AppPressable(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    expanded ? 'Tutup' : 'Baca selengkapnya',
                    style: const TextStyle(
                      color: _brandBlue,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: _brandBlue,
                    size: 20,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProductRecommendationSection extends StatelessWidget {
  final List<Product> related;

  const _ProductRecommendationSection({required this.related});

  @override
  Widget build(BuildContext context) {
    if (related.isEmpty) return const SizedBox.shrink();
    return _SectionShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Rekomendasi Untukmu',
                  style: TextStyle(
                    color: _textDark,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              AppPressable(
                onTap: () => Navigator.pushNamed(context, '/products'),
                borderRadius: BorderRadius.circular(8),
                child: const Row(
                  children: [
                    Text(
                      'Lihat semua',
                      style: TextStyle(
                        color: _brandBlue,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        color: _brandBlue, size: 20),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 252,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: related.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final product = related[index];
                return _DetailRecommendationCard(product: product);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRecommendationCard extends StatelessWidget {
  final Product product;

  const _DetailRecommendationCard({required this.product});

  @override
  Widget build(BuildContext context) {
    final savings = product.price - product.finalPrice;
    final voucherLabel = product.voucherPreview?.badgeLabel.trim();
    final savingsLabel = voucherLabel != null && voucherLabel.isNotEmpty
        ? voucherLabel
        : savings > 0
            ? 'Hemat ${formatRupiah(savings)}'
            : null;

    return SizedBox(
      width: 150,
      child: AppPressable(
        onTap: () {
          AppHaptics.tap();
          Navigator.pushNamed(context, '/product-detail', arguments: product);
        },
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _borderGray),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1.05,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AppProductImage(
                    imageUrl: product.imageUrl,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                product.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _textDark,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 6),
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
              if (savingsLabel != null) ...[
                const SizedBox(height: 5),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: _softDiscountBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    savingsLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _discountRed,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              if (product.rating > 0 || product.soldCount > 0)
                Row(
                  children: [
                    if (product.rating > 0) ...[
                      const Icon(Icons.star_rounded,
                          size: 14, color: _starAmber),
                      const SizedBox(width: 2),
                      Text(
                        product.rating.toStringAsFixed(1),
                        style: const TextStyle(
                          color: _textGray,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                    if (product.rating > 0 && product.soldCount > 0)
                      const Text(
                        ' • ',
                        style: TextStyle(color: _textGray, fontSize: 11),
                      ),
                    if (product.soldCount > 0)
                      Expanded(
                        child: Text(
                          '${_formatCompactCount(product.soldCount)} terjual',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _textGray,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
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

String _formatCompactCount(int value) {
  if (value >= 1000) {
    final compact = value / 1000;
    final text = compact >= 10
        ? compact.toStringAsFixed(0)
        : compact.toStringAsFixed(1).replaceAll('.', ',');
    return '${text}rb+';
  }
  if (value >= 100) return '${(value ~/ 50) * 50}+';
  return value.toString();
}

String _formatWeight(int grams) {
  if (grams <= 0) return '-';
  if (grams >= 1000 && grams % 1000 == 0) return '${grams ~/ 1000}kg';
  if (grams >= 1000) {
    return '${(grams / 1000).toStringAsFixed(1).replaceAll('.', ',')}kg';
  }
  return '$grams gram';
}

class _ProductReviewPreviewSection extends StatelessWidget {
  final Product product;
  final ReviewSummary? summary;
  final List<ProductReview> reviews;

  const _ProductReviewPreviewSection({
    required this.product,
    required this.summary,
    required this.reviews,
  });

  @override
  Widget build(BuildContext context) {
    final rating = (summary?.avgRating ?? product.rating);
    final reviewCount = summary?.reviewCount ?? product.reviewCount;
    final ratingCountFromBreakdown = summary?.ratingBreakdown.values
        .fold<int>(0, (sum, count) => sum + count);
    final ratingCount = (ratingCountFromBreakdown ?? 0) > 0
        ? ratingCountFromBreakdown!
        : reviewCount;
    final photoUrls =
        reviews.expand((review) => review.images).take(8).toList();

    return _SectionShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Expanded(
                child: Text(
                  'Ulasan pembeli',
                  style: TextStyle(
                    color: _textDark,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                'Lihat Semua',
                style: TextStyle(
                  color: _brandBlue,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: _brandBlue, size: 22),
            ],
          ),
          const SizedBox(height: 12),
          if (rating > 0 || reviewCount > 0)
            Row(
              children: [
                const Icon(Icons.star_rounded, color: _starAmber, size: 30),
                const SizedBox(width: 6),
                Text(
                  rating > 0 ? rating.toStringAsFixed(1) : '-',
                  style: const TextStyle(
                    color: _textDark,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'dari ${_formatCompactCount(ratingCount)} rating • ${_formatCompactCount(reviewCount)} ulasan',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _textGray,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            )
          else
            const Text(
              'Belum ada ulasan pembeli.',
              style: TextStyle(
                color: _textGray,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          if (photoUrls.isNotEmpty) ...[
            const SizedBox(height: 14),
            SizedBox(
              height: 78,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: photoUrls.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 78,
                      height: 78,
                      child: AppProductImage(
                        imageUrl: photoUrls[index],
                        fit: BoxFit.cover,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          if (reviews.isNotEmpty) ...[
            const SizedBox(height: 16),
            for (var i = 0; i < reviews.length; i++) ...[
              _ReviewPreviewTile(review: reviews[i]),
              if (i != reviews.length - 1)
                const Divider(height: 24, color: _borderGray),
            ],
          ],
        ],
      ),
    );
  }
}

class _ReviewPreviewTile extends StatelessWidget {
  final ProductReview review;

  const _ReviewPreviewTile({required this.review});

  @override
  Widget build(BuildContext context) {
    final name = review.userName.trim().isEmpty
        ? 'Pembeli Natalo'
        : review.userName.trim();
    final text = [
      if ((review.title ?? '').trim().isNotEmpty) review.title!.trim(),
      if ((review.content ?? '').trim().isNotEmpty) review.content!.trim(),
    ].join('\n');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 19,
          backgroundColor: const Color(0xFFE5E7EB),
          child: Text(
            name.isEmpty ? 'N' : name.substring(0, 1).toUpperCase(),
            style: const TextStyle(
              color: _textGray,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _textDark,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  // UGC moderation — review yang bukan milik user sendiri
                  // ada tombol "more" untuk Report/Block (Google Play UGC
                  // policy syarat). Tombol di-hide untuk review.isMine
                  // karena tidak masuk akal laporkan review sendiri.
                  if (!review.isMine)
                    InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => showModerationActions(
                        context,
                        targetKind: ReportTargetKind.productReview,
                        targetId: review.id,
                        authorName: review.userName,
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.more_horiz_rounded,
                          size: 18,
                          color: _textGray,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  for (var i = 0; i < 5; i++)
                    Icon(
                      Icons.star_rounded,
                      size: 15,
                      color: i < review.rating
                          ? _starAmber
                          : const Color(0xFFE5E7EB),
                    ),
                  const SizedBox(width: 8),
                  Text(
                    _formatDateId(review.createdAt),
                    style: const TextStyle(
                      color: _textGray,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              if ((review.variantLabel ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Varian: ${review.variantLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _textGray,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (text.isNotEmpty) ...[
                const SizedBox(height: 7),
                Text(
                  text,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _textMedium,
                    fontSize: 13,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

String _formatDateId(DateTime date) {
  if (date.millisecondsSinceEpoch == 0) return '';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
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
    // Saat out-of-stock, ganti tombol Beli + Keranjang dengan "Beri tahu
    // saya saat tersedia" — pre-order notification subscription. User
    // tetap bisa chat WA admin via tombol kiri.
    if (outOfStock) {
      return AppGlassBottomBar(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            SizedBox(
              width: 56,
              height: 50,
              child: OutlinedButton(
                onPressed: () => _onChatWa(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _brandBlue,
                  minimumSize: const Size(56, 50),
                  side: const BorderSide(color: _brandBlue, width: 1.2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: EdgeInsets.zero,
                ),
                child: const _WhatsAppIcon(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 4,
              child: _NotifyWhenAvailableButton(
                productId: product.id,
                variantId: selectedVariant?.id,
              ),
            ),
          ],
        ),
      );
    }
    final buyLabel = needsVariantSelection ? 'Pilih Varian' : 'Beli Sekarang';
    return AppGlassBottomBar(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            height: 50,
            child: OutlinedButton(
              onPressed: () => _onChatWa(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: _brandBlue,
                minimumSize: const Size(56, 50),
                side: const BorderSide(color: _brandBlue, width: 1.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: EdgeInsets.zero,
              ),
              child: const _WhatsAppIcon(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: OutlinedButton(
              onPressed: disabled ? null : () => _onBeliSekarang(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: _brandBlue,
                minimumSize: const Size.fromHeight(50),
                side: const BorderSide(color: _brandBlue, width: 1.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
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
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: outOfStock ? null : () => _onAddToCart(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: _brandBlue,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
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
        ],
      ),
    );
  }
}

/// Pre-Order Out-of-Stock — tombol subscribe restock notification.
///
/// Tap → POST /api/products/{id}/stock-notification → backend record
/// StockNotification subscription. Saat admin update stock 0 → >0,
/// backend fire FCM/APNs push ke user → tap notif → deep link buka
/// product detail.
///
/// State:
/// - loading: fetch initial subscription status (didChangeDependencies)
/// - subscribed: kalau true, tampil "Sudah didaftarkan" + tap untuk
///   unsubscribe. Kalau false, tampil "Beri tahu saat tersedia".
/// - busy: saat API call in progress (subscribe/unsubscribe), tombol
///   disabled + spinner.
class _NotifyWhenAvailableButton extends StatefulWidget {
  final String productId;
  final String? variantId;

  const _NotifyWhenAvailableButton({
    required this.productId,
    required this.variantId,
  });

  @override
  State<_NotifyWhenAvailableButton> createState() =>
      _NotifyWhenAvailableButtonState();
}

class _NotifyWhenAvailableButtonState
    extends State<_NotifyWhenAvailableButton> {
  bool _loading = true;
  bool _busy = false;
  bool _subscribed = false;

  @override
  void initState() {
    super.initState();
    _fetchStatus();
  }

  @override
  void didUpdateWidget(covariant _NotifyWhenAvailableButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Variant berubah → re-check subscription status untuk varian baru.
    if (oldWidget.variantId != widget.variantId ||
        oldWidget.productId != widget.productId) {
      _fetchStatus();
    }
  }

  Future<void> _fetchStatus() async {
    if (!memberStore.isLoggedIn) {
      // Guest user — tidak fetch status (belum bisa subscribe), tampil
      // sebagai "Beri tahu saat tersedia" → tap trigger login flow.
      if (mounted) {
        setState(() {
          _loading = false;
          _subscribed = false;
        });
      }
      return;
    }
    setState(() => _loading = true);
    final result = await stockNotificationService.isSubscribed(
      productId: widget.productId,
      variantId: widget.variantId,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _subscribed = result == true;
    });
  }

  Future<void> _toggle() async {
    if (_busy) return;
    if (!memberStore.isLoggedIn) {
      AppHaptics.tap();
      Navigator.pushNamed(context, '/member/login');
      return;
    }
    AppHaptics.tap();
    setState(() => _busy = true);
    try {
      if (_subscribed) {
        final res = await stockNotificationService.unsubscribe(
          productId: widget.productId,
          variantId: widget.variantId,
        );
        if (!mounted) return;
        if (res.ok) {
          setState(() => _subscribed = false);
          if (res.message.isNotEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(res.message),
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
      } else {
        final res = await stockNotificationService.subscribe(
          productId: widget.productId,
          variantId: widget.variantId,
        );
        if (!mounted) return;
        if (res.ok) {
          setState(() => _subscribed = true);
          AppHaptics.success();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                res.message.isNotEmpty
                    ? res.message
                    : 'Kamu akan dapat notifikasi saat produk tersedia.',
              ),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                res.message.isNotEmpty
                    ? res.message
                    : 'Gagal subscribe notifikasi.',
              ),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 401) {
        Navigator.pushNamed(context, '/member/login');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return SizedBox(
        height: 50,
        child: OutlinedButton(
          onPressed: null,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            side: BorderSide(color: _brandBlue.withValues(alpha: 0.3)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: const SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: _brandBlue,
            ),
          ),
        ),
      );
    }
    final label = _subscribed
        ? 'Sudah Didaftarkan • Tap untuk batal'
        : 'Beri Tahu Saya Saat Tersedia';
    final icon = _subscribed
        ? Icons.notifications_active_rounded
        : Icons.notifications_outlined;
    final bgColor = _subscribed ? const Color(0xFFE8F4FF) : _brandBlue;
    final fgColor = _subscribed ? _brandBlue : Colors.white;
    return SizedBox(
      height: 50,
      child: ElevatedButton.icon(
        onPressed: _busy ? null : _toggle,
        icon: _busy
            ? SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: fgColor,
                ),
              )
            : Icon(icon, size: 18, color: fgColor),
        label: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              color: fgColor,
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: bgColor,
          foregroundColor: fgColor,
          elevation: 0,
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: _subscribed
                ? const BorderSide(color: _brandBlue, width: 1.2)
                : BorderSide.none,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
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

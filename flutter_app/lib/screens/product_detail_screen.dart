import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../config/api_config.dart';
import '../config/natalo_store_config.dart';
import '../models/cart_item.dart';
import '../models/feed_post.dart';
import '../models/product.dart';
import '../models/review.dart';
import '../services/api_client.dart';
import '../services/app_analytics.dart';
import '../services/app_crashlytics.dart';
import '../services/feed_service.dart';
import '../services/product_service.dart';
import '../services/report_service.dart';
import '../services/review_service.dart';
import '../services/stock_notification_service.dart';
import '../shared/widgets/natalo_post_action_icon.dart';
import '../state/cart_store.dart';
import '../state/member_store.dart';
import '../state/recently_viewed_store.dart';
import 'checkout_screen.dart';
import 'member_post_detail_screen.dart';
import '../utils/fly_to_cart.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import '../widgets/app_cart_button.dart';
import '../widgets/natalo_paw_refresh_indicator.dart';
import '../widgets/app_product_image.dart';
import '../widgets/app_toast.dart';
import '../widgets/app_ui.dart';
import '../widgets/favorite_button.dart';
import '../widgets/flash_sale_countdown.dart';
import '../widgets/moderation_action_sheet.dart';
import 'image_viewer_screen.dart';

const _brandBlue = Color(0xFF1565D8);
const _textDark = Color(0xFF111827);
const _textMedium = Color(0xFF374151);
const _textGray = Color(0xFF6B7280);
const _borderGray = Color(0xFFE5E7EB);
const _discountRed = Color(0xFFE11D48);
const _softDiscountBg = Color(0xFFFFEEF1);
const _successGreen = Color(0xFF16A34A);
const _starAmber = Color(0xFFF59E0B);

class ProductDetailScreen extends StatefulWidget {
  final Product product;

  /// Saat dibuka dari notif "Toko membalas ulasanmu" (lihat
  /// notifications_screen.dart `_openReviewedProduct`), set true →
  /// auto-scroll ke section ulasan setelah first frame + tab badge
  /// di "Ulasan". Default false untuk entry-point lain (cart, search, dst).
  final bool focusReviewSection;

  const ProductDetailScreen({
    super.key,
    required this.product,
    this.focusReviewSection = false,
  });

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
  // List voucher untuk produk ini, hasil fetch /api/products/{slug}/vouchers.
  // Backend kembalikan campuran publicVoucher + shippingVoucher + memberVouchers.
  // Render sebagai horizontal scroll chip — beda dari single placeholder
  // sebelumnya yang cuma pakai product.voucherPreview.
  List<ProductVoucherPreview> _vouchers = const [];
  List<_ProductCustomerPost> _customerPosts = const [];
  bool _loadingCustomerPosts = true;
  bool _descriptionExpanded = false;
  int _activeTab = 0;
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _overviewKey = GlobalKey();
  final GlobalKey _reviewsKey = GlobalKey();
  // Posisi product hero image — dipakai oleh flyImageToCart saat user
  // tap "Tambah ke Keranjang" supaya mini image fly dari foto produk
  // (yang user sedang lihat) → ke cart icon di AppBar. Tokopedia pattern.
  final GlobalKey _heroImageKey = GlobalKey();
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
    return product.hasVariants && _selectedVariant == null;
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
    _loadVouchers();
    _loadCustomerPosts();

    // Auto-scroll ke section ulasan kalau dibuka dari notif review_reply.
    // _reviewsKey ada di tree dari initial render (preview section eagerly
    // rendered, isi reviews di-fetch async). Delay 350ms supaya layout
    // sudah settle setelah first frame + sticky tab bar terbentuk.
    if (widget.focusReviewSection) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 350), () {
          if (!mounted) return;
          _scrollToSection(_reviewsKey, 1);
        });
      });
    }
  }

  /// Fetch list voucher untuk produk ini. Non-blocking — kalau gagal /
  /// tidak ada voucher, widget fallback ke single placeholder.
  Future<void> _loadVouchers() async {
    try {
      final raw = await productService.fetchProductVouchers(product.slug);
      if (!mounted || raw.isEmpty) return;
      final parsed = <ProductVoucherPreview>[];
      for (final entry in raw) {
        try {
          parsed.add(ProductVoucherPreview.fromJson(entry));
        } catch (_) {
          // Skip entry yang malformed — jangan blokir voucher lain.
        }
      }
      if (!mounted || parsed.isEmpty) return;
      setState(() => _vouchers = parsed);
    } catch (_) {
      // Non-critical — fallback ke product.voucherPreview di widget.
    }
  }

  Future<void> _loadCustomerPosts() async {
    try {
      final raw = await productService.fetchProductFeedPosts(
        product.slug,
        limit: 12,
      );
      if (!mounted) return;
      final parsed = <_ProductCustomerPost>[];
      for (final entry in raw) {
        try {
          final post = _ProductCustomerPost.fromJson(entry);
          if (post.thumbnailUrl.isNotEmpty) parsed.add(post);
        } catch (_) {
          // Skip malformed UGC item; product detail remains usable.
        }
      }
      setState(() {
        _customerPosts = parsed;
        _loadingCustomerPosts = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingCustomerPosts = false);
    }
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

  void _syncVariantSelection(Map<String, String> options) {
    setState(() {
      _selectedOptions
        ..clear()
        ..addAll(options);
    });
  }

  String? _variantLabelFor(ProductVariant? variant) {
    if (variant == null) return null;
    return cartVariantOptionLabel(product, variant);
  }

  void _addToCart({
    ProductVariant? variant,
    int quantity = 1,
  }) {
    if (product.hasVariants && variant == null) {
      _openVariantSheet();
      return;
    }
    // Pre-check stok vs qty yang SUDAH di keranjang. cartStore.addItem
    // meng-clamp ke stok (single source of truth), tapi di sini kita kasih
    // feedback eksplisit supaya user paham kenapa qty tidak nambah.
    final variantId = variant?.id;
    final key =
        variantId == null ? product.id : '${product.id}:$variantId';
    final stock = variant?.stock ?? product.stock;
    final currentQty = cartStore.quantityFor(key);
    if (stock > 0 && currentQty >= stock) {
      AppHaptics.tap();
      AppToast.show(
        context,
        'Stok cuma $stock — semua sudah ada di keranjang.',
        kind: ToastKind.info,
      );
      return;
    }
    AppHaptics.success();
    // Fire fly-to-cart animation dulu (Overlay-based, tidak block UI).
    // Mini product image fly dari posisi hero image → cart icon di AppBar
    // dengan parabolic arc. Match Tokopedia / Shopee pattern.
    flyImageToCart(
      context: context,
      imageUrl: product.imageUrl,
      sourceKey: _heroImageKey,
    );
    cartStore.addProduct(
      product,
      variant: variant,
      variantLabel: _variantLabelFor(variant),
      quantity: quantity,
    );
    // Kalau jumlah yang diminta melebihi stok → ke-clamp di store, beri tahu.
    if (stock > 0 && currentQty + quantity > stock) {
      AppToast.show(
        context,
        'Stok tinggal $stock, jumlah disesuaikan.',
        kind: ToastKind.info,
      );
    } else {
      AppToast.showCartAdded(
        context,
        '${product.title} masuk keranjang',
        onTap: () => Navigator.pushNamed(context, '/cart'),
      );
    }
  }

  void _buyNow({
    ProductVariant? variant,
    int quantity = 1,
  }) {
    if (product.hasVariants && variant == null) {
      _openVariantSheet();
      return;
    }
    AppHaptics.impact();
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CheckoutScreen(
          items: [
            CartItem(
              product: product,
              quantity: quantity,
              variant: variant,
              variantLabel: _variantLabelFor(variant),
              unitPrice: variant == null
                  ? null
                  : effectiveCartVariantPrice(product, variant),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openVariantSheet() async {
    AppHaptics.tap();
    var sheetProduct = product;
    if (sheetProduct.hasVariants && sheetProduct.variantAttrs.isEmpty) {
      final full = await productService.fetchProductBySlug(sheetProduct.slug);
      if (!mounted) return;
      if (full == null || full.variantAttrs.isEmpty) {
        AppToast.show(
          context,
          'Varian produk belum siap. Coba lagi sebentar.',
          kind: ToastKind.warning,
        );
        return;
      }
      setState(() {
        _product = full;
        if (full.hasVariants && full.variants.length == 1) {
          final only = full.variants.first;
          _selectedOptions.clear();
          for (final id in only.optionIds) {
            for (final attr in full.variantAttrs) {
              if (attr.options.any((opt) => opt.id == id)) {
                _selectedOptions[attr.id] = id;
                break;
              }
            }
          }
        }
      });
      sheetProduct = full;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.38),
      builder: (sheetContext) {
        return _ProductVariantBottomSheet(
          product: sheetProduct,
          initialSelectedOptions: _selectedOptions,
          onSelectionChanged: _syncVariantSelection,
          onAddToCart: (variant, quantity) {
            Navigator.of(sheetContext).pop();
            _addToCart(variant: variant, quantity: quantity);
          },
          onBuyNow: (variant, quantity) {
            Navigator.of(sheetContext).pop();
            _buyNow(variant: variant, quantity: quantity);
          },
        );
      },
    );
  }

  void _openAllReviews() {
    AppHaptics.tap();
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _ProductReviewsScreen(
          product: product,
          initialSummary: _reviewSummary,
          selectedVariant: _selectedVariant,
          needsVariantSelection: _needsVariantSelection,
          displayStock: _displayStock,
          onSelectVariant: () {
            Navigator.of(context).pop();
            _openVariantSheet();
          },
          onAddToCart: (variant, quantity) {
            _addToCart(variant: variant, quantity: quantity);
          },
          onBuyNow: (variant, quantity) {
            _buyNow(variant: variant, quantity: quantity);
          },
        ),
      ),
    );
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
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        surfaceTintColor: cs.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        title: const Text('Detail Produk'),
        actions: [
          AppHeaderIconButton(
            onPressed: () => _shareProduct(context),
            tooltip: 'Bagikan',
            child: const NataloPostActionIcon(
              type: NataloPostActionIconType.share,
              size: 24,
              strokeWidth: 2.3,
            ),
          ),
          const AppCartButton(),
        ],
      ),
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverToBoxAdapter(
            // KeyedSubtree dengan _heroImageKey supaya flyImageToCart()
            // bisa lookup posisi hero area saat user tap "Tambah ke
            // Keranjang" → fly mini image dari sini ke cart icon AppBar.
            child: KeyedSubtree(
              key: _heroImageKey,
              child: _ProductHero(
                product: product,
                selectedVariant: _selectedVariant,
                needsVariantSelection: _needsVariantSelection,
                onSelectVariant: _openVariantSheet,
                onAddToCart: (variant, quantity) =>
                    _addToCart(variant: variant, quantity: quantity),
              ),
            ),
          ),
          if (product.hasVariants && product.variantAttrs.isNotEmpty)
            SliverToBoxAdapter(
              child: _VariantEntryRow(
                product: product,
                selectedOptions: _selectedOptions,
                selectedVariant: _selectedVariant,
                onTap: _openVariantSheet,
              ),
            ),
          if (product.hasFlashSaleCountdown)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
                child: _ProductFlashSaleBanner(product: product),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
              child: _ProductInfo(
                product: product,
                vouchers: _vouchers,
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
            child: _ProductCustomerPostsSection(
              posts: _customerPosts,
              loading: _loadingCustomerPosts,
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
                onViewAll: _openAllReviews,
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
        onSelectVariant: _openVariantSheet,
        onAddToCart: (variant, quantity) =>
            _addToCart(variant: variant, quantity: quantity),
        onBuyNow: (variant, quantity) =>
            _buyNow(variant: variant, quantity: quantity),
      ),
    );
  }
}

class _ProductHero extends StatefulWidget {
  final Product product;
  final ProductVariant? selectedVariant;
  final bool needsVariantSelection;
  final VoidCallback onSelectVariant;
  final void Function(ProductVariant? variant, int quantity) onAddToCart;

  const _ProductHero({
    required this.product,
    required this.selectedVariant,
    required this.needsVariantSelection,
    required this.onSelectVariant,
    required this.onAddToCart,
  });

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
    final cs = Theme.of(context).colorScheme;
    final images = _images;
    final showIndicators = images.length > 1;

    return LayoutBuilder(
      builder: (context, constraints) {
        final heroHeight = constraints.maxWidth.isFinite
            ? constraints.maxWidth.clamp(360.0, 430.0).toDouble()
            : 390.0;

        return ColoredBox(
          color: cs.surface,
          child: Stack(
            children: [
              SizedBox(
                height: heroHeight,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: images.isEmpty
                          ? const _ImagePlaceholder()
                          : PageView.builder(
                              // Hero wrap di PageView dihapus — bikin bug
                              // blank hitam saat user tap foto → buka
                              // ImageViewerScreen. Hero source di-"lift"
                              // ke overlay saat navigate, tapi destination
                              // (viewer) tidak punya matching Hero tag →
                              // source widget tidak balik ke tree dengan
                              // benar. Hero animation card → detail jadi
                              // hilang (acceptable trade — bug fix
                              // prioritas, animation bisa di-restore
                              // nanti via flightShuttleBuilder).
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
                                        opaque: true,
                                        barrierColor: Colors.black,
                                        transitionDuration:
                                            const Duration(milliseconds: 280),
                                        reverseTransitionDuration:
                                            const Duration(milliseconds: 220),
                                        pageBuilder: (_, __, ___) =>
                                            ImageViewerScreen(
                                          images: images,
                                          initialIndex: _activeIndex,
                                          productMediaViewer: true,
                                          product: widget.product,
                                          selectedVariant:
                                              widget.selectedVariant,
                                          needsVariantSelection:
                                              widget.needsVariantSelection,
                                          onSelectVariant:
                                              widget.onSelectVariant,
                                          onAddToCart: widget.onAddToCart,
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
                                  child: AppProductImage(
                                    imageUrl: images[index],
                                    width: double.infinity,
                                    height: double.infinity,
                                    fit: BoxFit.contain,
                                    borderRadius: BorderRadius.zero,
                                  ),
                                );
                              },
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
            ],
          ),
        );
      },
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Icon(
        Icons.image_outlined,
        size: 64,
        color: cs.outlineVariant,
      ),
    );
  }
}

class _ProductInfo extends StatelessWidget {
  final Product product;
  final List<ProductVoucherPreview> vouchers;

  const _ProductInfo({
    required this.product,
    this.vouchers = const [],
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasDiscount = product.hasDiscount;
    final discount = product.discountPercent;
    final savings = product.price - product.finalPrice;
    final hasRating = product.rating > 0;
    final hasReviews = product.reviewCount > 0;
    final hasSold = product.soldCount > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          formatRupiah(product.finalPrice),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: cs.onSurface,
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
                  color: _discountRed,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.lineThrough,
                  decorationColor: _discountRed,
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
        if (_VoucherAndTrust.hasVoucher(product, vouchers)) ...[
          const SizedBox(height: 12),
          _VoucherAndTrust(
            product: product,
            vouchers: vouchers,
          ),
          const SizedBox(height: 16),
        ] else
          const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                product.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  height: 1.22,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: FavoriteButton(
                product: product,
                size: 36,
              ),
            ),
          ],
        ),
        if (hasRating || hasReviews || hasSold) ...[
          const SizedBox(height: 12),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (hasRating) ...[
                const Icon(Icons.star_rounded, size: 18, color: _starAmber),
                const SizedBox(width: 4),
                Text(
                  product.rating.toStringAsFixed(1),
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
              if (hasReviews) ...[
                if (hasRating) const _InfoDot(),
                Text(
                  '${product.reviewCount} ulasan',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (hasSold) ...[
                if (hasRating || hasReviews) const _InfoDot(),
                Text(
                  '${_formatCompactCount(product.soldCount)} terjual',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _ProductFlashSaleBanner extends StatelessWidget {
  final Product product;

  const _ProductFlashSaleBanner({required this.product});

  @override
  Widget build(BuildContext context) {
    final endsAt = product.flashSaleEndsAt;
    if (endsAt == null || !product.hasFlashSaleCountdown) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFFE11D48), Color(0xFFDC2626)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE11D48).withValues(alpha: 0.22),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.flash_on_rounded,
            color: Colors.white,
            size: 20,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Flash Sale berakhir dalam',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 92,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFF7F1D1D).withValues(alpha: 0.58),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.16),
              ),
            ),
            child: DefaultTextStyle.merge(
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
              child: FlashSaleCountdown.digitsOnly(endsAt: endsAt),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoDot extends StatelessWidget {
  const _InfoDot();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        '•',
        style: TextStyle(
          color: cs.onSurfaceVariant,
          fontSize: 14,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

/// Compact voucher strip di product detail.
///
/// Intentionally tanpa icon / label "Voucher Toko": row langsung memperlihatkan
/// benefit checkout yang user peduli, mis. [Gratis Ongkir] [-Rp20.000].
class _VoucherAndTrust extends StatelessWidget {
  final Product product;
  final List<ProductVoucherPreview> vouchers;

  const _VoucherAndTrust({
    required this.product,
    this.vouchers = const [],
  });

  static bool hasVoucher(
    Product product,
    List<ProductVoucherPreview> vouchers,
  ) {
    return _resolveVouchers(product, vouchers).isNotEmpty;
  }

  static List<ProductVoucherPreview> _resolveVouchers(
    Product product,
    List<ProductVoucherPreview> vouchers,
  ) {
    final resolved = vouchers.isNotEmpty
        ? vouchers
        : (product.voucherPreview != null
            ? [product.voucherPreview!]
            : const <ProductVoucherPreview>[]);
    return resolved
        .where(
            (voucher) => voucher.isShippingVoucher || !_isPromoStore(voucher))
        .toList(growable: false);
  }

  static bool _isPromoStore(ProductVoucherPreview voucher) {
    final scope = voucher.discountScope.trim().toUpperCase();
    final type = voucher.type.trim().toUpperCase();
    return scope == 'STORE' || type.contains('STORE_PROMO');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final resolved = _resolveVouchers(product, vouchers);
    if (resolved.isEmpty) return const SizedBox.shrink();

    return AppPressable(
      onTap: () => _showPromoSheet(context, resolved),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        constraints: const BoxConstraints(minHeight: 46),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(
            top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.72)),
            bottom:
                BorderSide(color: cs.outlineVariant.withValues(alpha: 0.72)),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: [
                    for (final voucher in resolved) ...[
                      _VoucherChip(voucher: voucher),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              color: cs.onSurface,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  void _showPromoSheet(
    BuildContext context,
    List<ProductVoucherPreview> resolved,
  ) {
    AppHaptics.tap();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.38),
      builder: (context) => _PromoVoucherSheet(
        product: product,
        vouchers: resolved,
      ),
    );
  }
}

class _VoucherChip extends StatelessWidget {
  final ProductVoucherPreview voucher;

  const _VoucherChip({required this.voucher});

  @override
  Widget build(BuildContext context) {
    final shipping = voucher.isShippingVoucher;
    final tone = shipping ? _successGreen : _discountRed;
    final bg = shipping ? const Color(0xFFEFFAF4) : _softDiscountBg;
    final border = shipping ? const Color(0xFFC7F0D8) : const Color(0xFFFFC9D0);
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: border),
      ),
      child: Text(
        _voucherChipText(voucher),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: tone,
          fontSize: 13,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}

class _PromoVoucherSheet extends StatelessWidget {
  final Product product;
  final List<ProductVoucherPreview> vouchers;

  const _PromoVoucherSheet({
    required this.product,
    required this.vouchers,
  });

  @override
  Widget build(BuildContext context) {
    final shippingVouchers =
        vouchers.where((v) => v.isShippingVoucher).toList();
    final discountVouchers =
        vouchers.where((v) => !v.isShippingVoucher).toList();
    final discountProduct = product.price - product.finalPrice;
    final bestVoucherDiscount = discountVouchers
        .map((voucher) => _voucherDiscountEstimate(product, voucher))
        .fold<double>(0, (best, value) => value > best ? value : best);
    final showEstimate = discountProduct > 0 || bestVoucherDiscount > 0;
    final estimatedPrice =
        (product.finalPrice - bestVoucherDiscount).clamp(0, double.infinity);

    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.68,
          minChildSize: 0.42,
          maxChildSize: 0.92,
          builder: (context, scrollController) {
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
              children: [
                Center(
                  child: Container(
                    width: 72,
                    height: 5,
                    decoration: BoxDecoration(
                      color: cs.outlineVariant,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Promo & voucher',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
                if (showEstimate) ...[
                  const SizedBox(height: 16),
                  _PromoEstimateCard(
                    priceBeforePromo: product.price,
                    productDiscount: discountProduct,
                    voucherDiscount: bestVoucherDiscount,
                    estimatedPrice: estimatedPrice.toDouble(),
                  ),
                ],
                if (shippingVouchers.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text(
                    'Gratis ongkir tersedia di checkout',
                    style: TextStyle(
                      color: _successGreen,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                Text(
                  'Voucher tersedia',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                for (final voucher in vouchers) ...[
                  _VoucherSheetCard(voucher: voucher),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 8),
                Text(
                  'Voucher final akan dihitung saat checkout.',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PromoEstimateCard extends StatelessWidget {
  final double priceBeforePromo;
  final double productDiscount;
  final double voucherDiscount;
  final double estimatedPrice;

  const _PromoEstimateCard({
    required this.priceBeforePromo,
    required this.productDiscount,
    required this.voucherDiscount,
    required this.estimatedPrice,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _softDiscountBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFD4DC)),
      ),
      child: Column(
        children: [
          _PromoEstimateRow(
            label: 'Harga sebelum promo',
            value: formatRupiah(priceBeforePromo),
            valueColor: _textDark,
          ),
          if (productDiscount > 0)
            _PromoEstimateRow(
              label: 'Diskon barang',
              value: '-${formatRupiah(productDiscount)}',
              valueColor: _discountRed,
            ),
          if (voucherDiscount > 0)
            _PromoEstimateRow(
              label: 'Diskon voucher',
              value: '-${formatRupiah(voucherDiscount)}',
              valueColor: _discountRed,
            ),
          const Divider(height: 24, color: Color(0xFFE5E7EB)),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Perkiraan harga hemat',
                  style: TextStyle(
                    color: _textDark,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                formatRupiah(estimatedPrice),
                style: const TextStyle(
                  color: _discountRed,
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PromoEstimateRow extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;

  const _PromoEstimateRow({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: _textDark,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _VoucherSheetCard extends StatelessWidget {
  final ProductVoucherPreview voucher;

  const _VoucherSheetCard({required this.voucher});

  @override
  Widget build(BuildContext context) {
    final shipping = voucher.isShippingVoucher;
    final tone = shipping ? _successGreen : _discountRed;
    final bg = shipping ? const Color(0xFFF0FDF4) : _softDiscountBg;
    final border = shipping ? const Color(0xFFBBF7D0) : const Color(0xFFFFC9D0);
    final subtitle = _voucherSheetSubtitle(voucher);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _voucherChipText(voucher),
                  style: TextStyle(
                    color: tone,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: _textMedium,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          shipping
              ? Icon(
                  Icons.local_shipping_rounded,
                  color: tone,
                  size: 24,
                )
              : const _DiscountVoucherIcon(),
        ],
      ),
    );
  }
}

class _DiscountVoucherIcon extends StatelessWidget {
  const _DiscountVoucherIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: _discountRed,
        borderRadius: BorderRadius.circular(11),
        boxShadow: [
          BoxShadow(
            color: _discountRed.withValues(alpha: 0.18),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Icon(
            Icons.confirmation_number_rounded,
            color: Colors.white,
            size: 22,
          ),
          Container(
            width: 16,
            height: 16,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _discountRed,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: Colors.white,
                width: 1.4,
              ),
            ),
            child: const Text(
              '%',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                height: 1,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _voucherChipText(ProductVoucherPreview voucher) {
  if (voucher.isShippingVoucher) return 'Gratis Ongkir';
  final amount = voucher.discountAmount ?? voucher.savingAmount;
  if (amount != null && amount > 0) {
    return '-${formatRupiahCompact(amount)}';
  }
  final percent = voucher.discountPercent;
  if (percent != null && percent > 0) {
    final cap =
        voucher.maxDiscountAmount != null && voucher.maxDiscountAmount! > 0
            ? ' s.d. ${formatRupiahCompact(voucher.maxDiscountAmount!)}'
            : '';
    return 'Diskon ${percent.toStringAsFixed(0)}%$cap';
  }
  final label = voucher.badgeLabel.trim();
  return label.isEmpty ? 'Voucher hemat' : label;
}

String _voucherSheetSubtitle(ProductVoucherPreview voucher) {
  if (voucher.isShippingVoucher) {
    return 'Bisa digunakan saat checkout';
  }
  final minimum = voucher.minimumOrder;
  if (minimum > 0) {
    return 'Potongan belanja saat checkout • Min. belanja ${formatRupiahCompact(minimum)}';
  }
  return 'Potongan belanja saat checkout';
}

double _voucherDiscountEstimate(
  Product product,
  ProductVoucherPreview voucher,
) {
  if (voucher.isShippingVoucher) return 0;
  final direct = voucher.savingAmount ?? voucher.discountAmount;
  if (direct != null && direct > 0) return direct;

  final percent = voucher.discountPercent;
  if (percent == null || percent <= 0) return 0;
  final raw = product.finalPrice * (percent / 100);
  final cap = voucher.maxDiscountAmount;
  if (cap != null && cap > 0) return raw > cap ? cap : raw;
  return raw;
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
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      elevation: elevated ? 1 : 0,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: cs.outlineVariant)),
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

  const _ProductInformationSection({
    required this.product,
  });

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      _InfoRow(label: 'Berat Produk', value: _formatWeight(product.weightGram)),
      if (product.brand.isNotEmpty)
        _InfoRow(label: 'Brand', value: product.brand),
      if (product.category.isNotEmpty)
        _InfoRow(label: 'Kategori', value: product.category),
    ];
    final cs = Theme.of(context).colorScheme;
    return _SectionShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Informasi Produk',
            style: TextStyle(
              color: cs.onSurface,
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

  const _InfoRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              '$label:',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: cs.onSurface,
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
    final cs = Theme.of(context).colorScheme;
    final description = product.description.trim();
    final hasDescription = description.isNotEmpty;
    return _SectionShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Deskripsi Produk',
            style: TextStyle(
              color: cs.onSurface,
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
            style: TextStyle(
              color: cs.onSurfaceVariant,
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

class _ProductCustomerPostsSection extends StatelessWidget {
  final List<_ProductCustomerPost> posts;
  final bool loading;

  const _ProductCustomerPostsSection({
    required this.posts,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    if (!loading && posts.isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    return _SectionShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Postingan Pelanggan',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (!loading && posts.isNotEmpty)
                Text(
                  '${posts.length} post',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Foto dan video dari pelanggan yang men-tag produk ini.',
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 190,
            child: loading
                ? const _CustomerPostLoadingList()
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: posts.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      return _CustomerPostCard(post: posts[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _CustomerPostLoadingList extends StatelessWidget {
  const _CustomerPostLoadingList();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: 3,
      separatorBuilder: (_, __) => const SizedBox(width: 10),
      itemBuilder: (context, index) {
        return Container(
          width: 118,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
          ),
        );
      },
    );
  }
}

class _CustomerPostCard extends StatelessWidget {
  final _ProductCustomerPost post;

  const _CustomerPostCard({required this.post});

  /// Buka postingan pelanggan DI DALAM app (bukan browser web). Fetch
  /// detail postingan by ID lalu push MemberPostDetailScreen sebagai
  /// viewer (video native, like, komentar pakai session app). Sebelumnya
  /// pakai launchUrl ke web — keluar app, video lambat, harus login ulang.
  /// Reuse infra deep-link notif (feedService.fetchPostById + viewer
  /// screen). Tampilkan spinner saat fetch (~1 dtk); gagal → toast.
  Future<void> _openPost(BuildContext context) async {
    AppHaptics.tap();
    // Dialog loading di-pop via rootNavigator supaya pasti nutup overlay
    // dialog (showDialog default mount di root navigator), bukan nebak
    // canPop yang bisa salah pop route lain.
    final rootNav = Navigator.of(context, rootNavigator: true);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.25),
      builder: (_) => const Center(
        child: SizedBox(
          width: 44,
          height: 44,
          child: CircularProgressIndicator(strokeWidth: 2.6),
        ),
      ),
    );

    FeedPost? feedPost;
    var failed = false;
    try {
      feedPost = await feedService.fetchPostById(post.id);
    } catch (_) {
      failed = true;
    }

    rootNav.pop(); // tutup loading dialog
    if (!context.mounted) return;

    if (feedPost == null) {
      AppToast.show(
        context,
        failed
            ? 'Postingan belum bisa dibuka. Coba lagi.'
            : 'Postingan sudah tidak tersedia.',
        kind: ToastKind.warning,
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MemberPostDetailScreen(
          post: feedPost!,
          authorName: feedPost.author.displayName,
          authorPhotoUrl: feedPost.author.profilePhotoUrl,
          authorInitial: feedPost.author.initial,
          isOwner: false,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 118,
      child: AppPressable(
        onTap: () => _openPost(context),
        borderRadius: BorderRadius.circular(14),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              AppProductImage(
                imageUrl: post.thumbnailUrl,
                fit: BoxFit.cover,
                borderRadius: BorderRadius.zero,
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.10),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.62),
                    ],
                    stops: const [0, 0.48, 1],
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: _CustomerPostTypeBadge(post: post),
              ),
              if (post.isVideo && post.durationSec > 0)
                Positioned(
                  left: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.62),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _formatDuration(post.durationSec),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      post.authorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.favorite_rounded,
                          color: Colors.white,
                          size: 13,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          _formatCompactCount(post.likeCount),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (post.commentCount > 0) ...[
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.mode_comment_rounded,
                            color: Colors.white,
                            size: 12,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            _formatCompactCount(post.commentCount),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
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

class _CustomerPostTypeBadge extends StatelessWidget {
  final _ProductCustomerPost post;

  const _CustomerPostTypeBadge({required this.post});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.58),
        shape: BoxShape.circle,
      ),
      child: Icon(
        post.isVideo ? Icons.play_arrow_rounded : Icons.collections_rounded,
        color: Colors.white,
        size: post.isVideo ? 19 : 15,
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
    final cs = Theme.of(context).colorScheme;
    return _SectionShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Rekomendasi Untukmu',
                  style: TextStyle(
                    color: cs.onSurface,
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
    final cs = Theme.of(context).colorScheme;
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
            color: cs.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outlineVariant),
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
                style: TextStyle(
                  color: cs.onSurface,
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
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                    if (product.rating > 0 && product.soldCount > 0)
                      Text(
                        ' • ',
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
                      ),
                    if (product.soldCount > 0)
                      Expanded(
                        child: Text(
                          '${_formatCompactCount(product.soldCount)} terjual',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
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

String _formatDuration(int seconds) {
  final safe = seconds.clamp(0, 24 * 60 * 60);
  final minutes = safe ~/ 60;
  final rest = safe % 60;
  return '$minutes:${rest.toString().padLeft(2, '0')}';
}

class _ProductCustomerPost {
  final String id;
  final String kind;
  final String title;
  final String thumbnailUrl;
  final int durationSec;
  final int likeCount;
  final int commentCount;
  final String authorName;

  const _ProductCustomerPost({
    required this.id,
    required this.kind,
    required this.title,
    required this.thumbnailUrl,
    required this.durationSec,
    required this.likeCount,
    required this.commentCount,
    required this.authorName,
  });

  bool get isVideo => kind != 'PHOTO_CAROUSEL';

  factory _ProductCustomerPost.fromJson(Map<String, dynamic> json) {
    final author = json['author'];
    final authorName = author is Map<String, dynamic>
        ? (author['name'] ?? 'Pelanggan Natalo').toString()
        : 'Pelanggan Natalo';
    return _ProductCustomerPost(
      id: (json['id'] ?? '').toString(),
      kind: (json['kind'] ?? 'USER_VIDEO').toString(),
      title: (json['title'] ?? '').toString(),
      thumbnailUrl: (json['thumbnailUrl'] ?? '').toString(),
      durationSec: (json['videoDurationSec'] as num?)?.toInt() ?? 0,
      likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
      commentCount: (json['commentCount'] as num?)?.toInt() ?? 0,
      authorName: authorName.trim().isEmpty ? 'Pelanggan Natalo' : authorName,
    );
  }
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
  final VoidCallback onViewAll;

  const _ProductReviewPreviewSection({
    required this.product,
    required this.summary,
    required this.reviews,
    required this.onViewAll,
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
    final mediaItems =
        reviews.expand((review) => review.media).take(8).toList();

    final cs = Theme.of(context).colorScheme;
    return _SectionShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Ulasan pembeli',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: onViewAll,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Lihat Semua',
                        style: TextStyle(
                          color: _brandBlue,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: _brandBlue,
                        size: 22,
                      ),
                    ],
                  ),
                ),
              ),
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
                  style: TextStyle(
                    color: cs.onSurface,
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
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            )
          else
            Text(
              'Belum ada ulasan pembeli.',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          if (mediaItems.isNotEmpty) ...[
            const SizedBox(height: 14),
            SizedBox(
              height: 78,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: mediaItems.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  return _ReviewMediaThumb(
                    media: mediaItems[index],
                    size: 78,
                    onTap: () => _openReviewMediaViewer(
                      context,
                      mediaItems,
                      index,
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
                Divider(height: 24, color: cs.outlineVariant),
            ],
          ],
        ],
      ),
    );
  }
}

class _ReviewMediaThumb extends StatelessWidget {
  final ProductReviewMedia media;
  final double size;
  final VoidCallback onTap;

  const _ReviewMediaThumb({
    required this.media,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              fit: StackFit.expand,
              children: [
                AppProductImage(
                  imageUrl: media.previewUrl,
                  fit: BoxFit.cover,
                ),
                if (media.isVideo)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.18),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.play_circle_fill_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
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

void _openReviewMediaViewer(
  BuildContext context,
  List<ProductReviewMedia> media,
  int initialIndex,
) {
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => _ReviewMediaViewerScreen(
        media: media,
        initialIndex: initialIndex,
      ),
    ),
  );
}

class _ProductReviewsScreen extends StatefulWidget {
  final Product product;
  final ReviewSummary? initialSummary;
  final ProductVariant? selectedVariant;
  final bool needsVariantSelection;
  final int displayStock;
  final VoidCallback onSelectVariant;
  final void Function(ProductVariant? variant, int quantity) onAddToCart;
  final void Function(ProductVariant? variant, int quantity) onBuyNow;

  const _ProductReviewsScreen({
    required this.product,
    required this.initialSummary,
    required this.selectedVariant,
    required this.needsVariantSelection,
    required this.displayStock,
    required this.onSelectVariant,
    required this.onAddToCart,
    required this.onBuyNow,
  });

  @override
  State<_ProductReviewsScreen> createState() => _ProductReviewsScreenState();
}

class _ProductReviewsScreenState extends State<_ProductReviewsScreen> {
  ReviewSummary? _summary;
  List<ProductReview> _reviews = const [];
  String? _nextCursor;
  int? _ratingFilter;
  bool _mediaOnly = false;
  bool _loading = true;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _summary = widget.initialSummary;
    _loadInitial();
  }

  ReviewFilter get _filter => ReviewFilter(
        rating: _ratingFilter,
        withImage: _mediaOnly,
      );

  Future<void> _loadInitial() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        reviewService.fetchSummary(widget.product.slug),
        reviewService.fetchReviews(widget.product.slug,
            filter: _filter, limit: 20),
      ]);
      if (!mounted) return;
      final summary = results[0] as ReviewSummary;
      final page = results[1] as ProductReviewPage;
      setState(() {
        _summary = summary;
        _reviews = page.reviews;
        _nextCursor = page.nextCursor;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _nextCursor == null) return;
    setState(() => _loadingMore = true);
    try {
      final page = await reviewService.fetchReviews(
        widget.product.slug,
        filter: _filter.copyWith(cursor: _nextCursor),
        limit: 20,
      );
      if (!mounted) return;
      setState(() {
        _reviews = [..._reviews, ...page.reviews];
        _nextCursor = page.nextCursor;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  void _setRatingFilter(int? rating) {
    if (_ratingFilter == rating) return;
    AppHaptics.tap();
    setState(() => _ratingFilter = rating);
    _loadInitial();
  }

  void _toggleMediaOnly() {
    AppHaptics.tap();
    setState(() => _mediaOnly = !_mediaOnly);
    _loadInitial();
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    final rating = summary?.avgRating ?? widget.product.rating;
    final reviewCount = summary?.reviewCount ?? widget.product.reviewCount;
    final ratingCount = summary?.ratingBreakdown.values
            .fold<int>(0, (sum, count) => sum + count) ??
        reviewCount;

    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        elevation: 0.6,
        shadowColor: Colors.black.withValues(alpha: 0.12),
        titleSpacing: 0,
        title: Text(
          'Ulasan',
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: AppCartButton(),
          ),
        ],
      ),
      body: NataloPawRefreshIndicator(
        onRefresh: _loadInitial,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 126),
          children: [
            _ReviewSummaryHeader(
              rating: rating,
              ratingCount: ratingCount,
              reviewCount: reviewCount,
            ),
            const SizedBox(height: 16),
            _ReviewFilterBar(
              selectedRating: _ratingFilter,
              mediaOnly: _mediaOnly,
              onRatingChanged: _setRatingFilter,
              onToggleMedia: _toggleMediaOnly,
            ),
            const SizedBox(height: 12),
            if (_loading)
              const _ReviewListSkeleton()
            else if (_reviews.isEmpty)
              const _ReviewsEmptyState()
            else ...[
              for (var i = 0; i < _reviews.length; i++) ...[
                _FullReviewTile(review: _reviews[i]),
                if (i != _reviews.length - 1)
                  Divider(height: 28, color: cs.outlineVariant),
              ],
              if (_nextCursor != null) ...[
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _loadingMore ? null : _loadMore,
                  child: Text(_loadingMore ? 'Memuat...' : 'Muat lainnya'),
                ),
              ],
            ],
          ],
        ),
      ),
      bottomNavigationBar: _StickyPurchaseBar(
        product: widget.product,
        selectedVariant: widget.selectedVariant,
        needsVariantSelection: widget.needsVariantSelection,
        displayStock: widget.displayStock,
        onSelectVariant: widget.onSelectVariant,
        onAddToCart: widget.onAddToCart,
        onBuyNow: widget.onBuyNow,
      ),
    );
  }
}

class _ReviewSummaryHeader extends StatelessWidget {
  final double rating;
  final int ratingCount;
  final int reviewCount;

  const _ReviewSummaryHeader({
    required this.rating,
    required this.ratingCount,
    required this.reviewCount,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? cs.surfaceContainerHighest : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          const Icon(Icons.star_rounded, color: _starAmber, size: 38),
          const SizedBox(width: 10),
          Text(
            rating > 0 ? rating.toStringAsFixed(1) : '-',
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 30,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'dari ${_formatCompactCount(ratingCount)} rating • ${_formatCompactCount(reviewCount)} ulasan',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewFilterBar extends StatelessWidget {
  final int? selectedRating;
  final bool mediaOnly;
  final ValueChanged<int?> onRatingChanged;
  final VoidCallback onToggleMedia;

  const _ReviewFilterBar({
    required this.selectedRating,
    required this.mediaOnly,
    required this.onRatingChanged,
    required this.onToggleMedia,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _ReviewFilterChip(
            label: 'Semua',
            selected: selectedRating == null && !mediaOnly,
            onTap: () {
              if (mediaOnly) onToggleMedia();
              onRatingChanged(null);
            },
          ),
          const SizedBox(width: 8),
          _ReviewFilterChip(
            label: 'Foto & Video',
            icon: Icons.photo_library_outlined,
            selected: mediaOnly,
            onTap: onToggleMedia,
          ),
          const SizedBox(width: 8),
          for (var rating = 5; rating >= 1; rating--) ...[
            _ReviewFilterChip(
              label: '$rating',
              icon: Icons.star_rounded,
              selected: selectedRating == rating,
              onTap: () => onRatingChanged(rating),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _ReviewFilterChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  const _ReviewFilterChip({
    required this.label,
    this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ChoiceChip(
      selected: selected,
      onSelected: (_) => onTap(),
      avatar: icon == null
          ? null
          : Icon(
              icon,
              size: 16,
              color: selected ? Colors.white : _brandBlue,
            ),
      label: Text(label),
      selectedColor: _brandBlue,
      backgroundColor: cs.surface,
      labelStyle: TextStyle(
        color: selected ? Colors.white : cs.onSurfaceVariant,
        fontSize: 13,
        fontWeight: FontWeight.w800,
      ),
      side: BorderSide(
        color: selected ? _brandBlue : cs.outlineVariant,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    );
  }
}

class _FullReviewTile extends StatelessWidget {
  final ProductReview review;

  const _FullReviewTile({required this.review});

  @override
  Widget build(BuildContext context) {
    final name = review.userName.trim().isEmpty
        ? 'Pembeli Natalo'
        : review.userName.trim();
    final text = [
      if ((review.title ?? '').trim().isNotEmpty) review.title!.trim(),
      if ((review.content ?? '').trim().isNotEmpty) review.content!.trim(),
    ].join('\n');

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 21,
            backgroundColor: cs.surfaceContainerHighest,
            child: Text(
              name.isEmpty ? 'N' : name.substring(0, 1).toUpperCase(),
              style: TextStyle(
                color: cs.onSurfaceVariant,
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
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (!review.isMine)
                      InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => showModerationActions(
                          context,
                          targetKind: ReportTargetKind.productReview,
                          targetId: review.id,
                          authorName: review.userName,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            Icons.more_vert_rounded,
                            size: 19,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    for (var i = 0; i < 5; i++)
                      Icon(
                        Icons.star_rounded,
                        size: 17,
                        color: i < review.rating
                            ? _starAmber
                            : cs.outlineVariant,
                      ),
                    const SizedBox(width: 8),
                    Text(
                      _formatDateId(review.createdAt),
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                if ((review.variantLabel ?? '').isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Text(
                    'Varian: ${review.variantLabel}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                if (text.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    text,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 14,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (review.media.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 88,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: review.media.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (context, index) => _ReviewMediaThumb(
                        media: review.media[index],
                        size: 88,
                        onTap: () => _openReviewMediaViewer(
                          context,
                          review.media,
                          index,
                        ),
                      ),
                    ),
                  ),
                ],
                if (review.reply != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? cs.surfaceContainerHighest
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    child: Text(
                      'Admin Natalo: ${review.reply!.content}',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 13,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewListSkeleton extends StatelessWidget {
  const _ReviewListSkeleton();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: List.generate(
        4,
        (index) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 130,
                      height: 14,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      height: 12,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Container(
                      width: 220,
                      height: 12,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(999),
                      ),
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

class _ReviewsEmptyState extends StatelessWidget {
  const _ReviewsEmptyState();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 54),
      child: Column(
        children: [
          Icon(Icons.rate_review_outlined, color: cs.onSurfaceVariant, size: 42),
          const SizedBox(height: 12),
          Text(
            'Ulasan tidak ditemukan',
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Coba gunakan filter lain.',
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewMediaViewerScreen extends StatefulWidget {
  final List<ProductReviewMedia> media;
  final int initialIndex;

  const _ReviewMediaViewerScreen({
    required this.media,
    required this.initialIndex,
  });

  @override
  State<_ReviewMediaViewerScreen> createState() =>
      _ReviewMediaViewerScreenState();
}

class _ReviewMediaViewerScreenState extends State<_ReviewMediaViewerScreen> {
  late final PageController _pageController;
  late int _index;

  @override
  void initState() {
    super.initState();
    final maxIndex = widget.media.length - 1;
    _index = widget.initialIndex.clamp(0, maxIndex < 0 ? 0 : maxIndex);
    _pageController = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.media.length,
            onPageChanged: (value) => setState(() => _index = value),
            itemBuilder: (context, index) {
              final media = widget.media[index];
              if (media.isVideo) return _ReviewVideoPlayer(media: media);
              return InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: SizedBox.expand(
                  child: AppProductImage(
                    imageUrl: media.url,
                    fit: BoxFit.contain,
                    borderRadius: BorderRadius.zero,
                  ),
                ),
              );
            },
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.only(left: 8, top: 8),
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
            ),
          ),
          if (widget.media.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.paddingOf(context).bottom + 22,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${_index + 1}/${widget.media.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReviewVideoPlayer extends StatefulWidget {
  final ProductReviewMedia media;

  const _ReviewVideoPlayer({required this.media});

  @override
  State<_ReviewVideoPlayer> createState() => _ReviewVideoPlayerState();
}

class _ReviewVideoPlayerState extends State<_ReviewVideoPlayer> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    final controller =
        VideoPlayerController.networkUrl(Uri.parse(widget.media.url));
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();
      if (!mounted) return;
      setState(() => _ready = true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final controller = _controller;
    if (controller == null || !_ready) return;
    setState(() {
      controller.value.isPlaying ? controller.pause() : controller.play();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_failed) {
      return const Center(
        child: Text(
          'Video tidak bisa diputar',
          style: TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }
    if (!_ready || controller == null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          AppProductImage(
            imageUrl: widget.media.previewUrl,
            fit: BoxFit.contain,
            borderRadius: BorderRadius.zero,
          ),
          const Center(child: CircularProgressIndicator(color: Colors.white)),
        ],
      );
    }
    return GestureDetector(
      onTap: _togglePlay,
      child: Center(
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: VideoPlayer(controller),
        ),
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

    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 19,
          backgroundColor: cs.surfaceContainerHighest,
          child: Text(
            name.isEmpty ? 'N' : name.substring(0, 1).toUpperCase(),
            style: TextStyle(
              color: cs.onSurfaceVariant,
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
                      style: TextStyle(
                        color: cs.onSurface,
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
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.more_horiz_rounded,
                          size: 18,
                          color: cs.onSurfaceVariant,
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
                          : cs.outlineVariant,
                    ),
                  const SizedBox(width: 8),
                  Text(
                    _formatDateId(review.createdAt),
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
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
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
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
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
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
    final cs = Theme.of(context).colorScheme;
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
                color: active ? _brandBlue : cs.onSurfaceVariant,
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

class _VariantEntryRow extends StatelessWidget {
  final Product product;
  final Map<String, String> selectedOptions;
  final ProductVariant? selectedVariant;
  final VoidCallback onTap;

  const _VariantEntryRow({
    required this.product,
    required this.selectedOptions,
    required this.selectedVariant,
    required this.onTap,
  });

  String _availabilityLabel() {
    if (product.variantAttrs.isEmpty) return 'Pilih varian yang tersedia';
    if (product.variantAttrs.length == 1) {
      final attr = product.variantAttrs.first;
      final name = attr.name.trim().toLowerCase();
      return 'Tersedia ${attr.options.length} ${name.isEmpty ? 'varian' : name}';
    }
    return 'Tersedia ${product.variants.length} varian';
  }

  List<ProductVariant> _previewVariants() {
    final seen = <String>{};
    final result = <ProductVariant>[];
    for (final variant in product.variants) {
      final key = variant.imageUrl?.trim().isNotEmpty == true
          ? variant.imageUrl!.trim()
          : variant.optionIds.join('|');
      if (seen.add(key)) result.add(variant);
      if (result.length >= 8) break;
    }
    return result;
  }

  bool _isSelected(ProductVariant variant) {
    final selected = selectedVariant;
    if (selected != null) return selected.id == variant.id;
    if (selectedOptions.isEmpty) return false;
    return selectedOptions.values.every(variant.optionIds.contains);
  }

  Widget _buildVariantThumb(ProductVariant variant, ColorScheme cs) {
    final selected = _isSelected(variant);
    final imageUrl = variant.imageUrl?.trim().isNotEmpty == true
        ? variant.imageUrl!
        : product.imageUrl;

    return Container(
      width: 48,
      height: 48,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? _brandBlue : cs.outlineVariant,
          width: selected ? 1.6 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: AppProductImage(
          imageUrl: imageUrl,
          width: 44,
          height: 44,
          fit: BoxFit.contain,
          borderRadius: BorderRadius.zero,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final previewVariants = _previewVariants();

    return AppPressable(
      onTap: onTap,
      borderRadius: BorderRadius.zero,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(
            bottom: BorderSide(
              color: cs.outlineVariant,
              width: 1,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _availabilityLabel(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  color: cs.onSurface,
                  size: 28,
                ),
              ],
            ),
            if (previewVariants.isNotEmpty) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 50,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: previewVariants.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    return _buildVariantThumb(previewVariants[index], cs);
                  },
                ),
              ),
            ] else ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final attr in product.variantAttrs.take(2))
                    for (final option in attr.options.take(4))
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? cs.surfaceContainerHighest
                              : const Color(0xFFEAF3FF),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: cs.outlineVariant),
                        ),
                        child: Text(
                          option.value,
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProductVariantBottomSheet extends StatefulWidget {
  final Product product;
  final Map<String, String> initialSelectedOptions;
  final ValueChanged<Map<String, String>> onSelectionChanged;
  final void Function(ProductVariant variant, int quantity) onAddToCart;
  final void Function(ProductVariant variant, int quantity) onBuyNow;

  const _ProductVariantBottomSheet({
    required this.product,
    required this.initialSelectedOptions,
    required this.onSelectionChanged,
    required this.onAddToCart,
    required this.onBuyNow,
  });

  @override
  State<_ProductVariantBottomSheet> createState() =>
      _ProductVariantBottomSheetState();
}

class _ProductVariantBottomSheetState
    extends State<_ProductVariantBottomSheet> {
  late Map<String, String> _selectedOptions;
  int _quantity = 1;

  Product get _product => widget.product;

  @override
  void initState() {
    super.initState();
    _selectedOptions = Map<String, String>.from(widget.initialSelectedOptions);
  }

  ProductVariant? get _selectedVariant {
    if (!_product.hasVariants || _product.variantAttrs.isEmpty) return null;
    if (_selectedOptions.length < _product.variantAttrs.length) return null;
    final selectedIds = _selectedOptions.values.toSet();
    for (final v in _product.variants) {
      if (v.optionIds.length == selectedIds.length &&
          v.optionIds.toSet().containsAll(selectedIds)) {
        return v;
      }
    }
    return null;
  }

  bool _hasVariantFor(String attrId, String optionId) {
    final trial = Map<String, String>.from(_selectedOptions);
    trial[attrId] = optionId;
    final trialIds = trial.values.toSet();
    return _product.variants.any((variant) {
      return trialIds.every((id) => variant.optionIds.contains(id)) &&
          variant.stock > 0;
    });
  }

  void _selectOption(String attrId, String optionId) {
    AppHaptics.tap();
    setState(() {
      _selectedOptions[attrId] = optionId;
      final stock = _selectedVariant?.stock ?? 0;
      if (stock > 0) {
        _quantity = _quantity.clamp(1, stock);
      } else {
        _quantity = 1;
      }
    });
    widget
        .onSelectionChanged(Map<String, String>.unmodifiable(_selectedOptions));
  }

  int get _displayPrice => _selectedVariant == null
      ? _product.finalPrice.round()
      : effectiveCartVariantPrice(_product, _selectedVariant!);

  int? get _originalPrice {
    final original = _selectedVariant?.price ?? _product.price.round();
    if (_product.hasDiscount && original > _displayPrice) return original;
    return null;
  }

  int get _selectedStock => _selectedVariant?.stock ?? 0;

  bool get _canCheckout => _selectedVariant != null && _selectedStock > 0;

  _VariantStockStatus get _stockStatus {
    final variant = _selectedVariant;
    if (variant == null) return _VariantStockStatus.needSelection;
    if (variant.stock <= 0) return _VariantStockStatus.out;
    if (variant.stock <= 5) return _VariantStockStatus.low;
    return _VariantStockStatus.available;
  }

  String get _imageUrl {
    final variantImage = _selectedVariant?.imageUrl;
    if (variantImage != null && variantImage.trim().isNotEmpty) {
      return variantImage;
    }
    return _product.imageUrl;
  }

  void _decrement() {
    if (!_canCheckout || _quantity <= 1) return;
    AppHaptics.tap();
    setState(() => _quantity -= 1);
  }

  void _increment() {
    if (!_canCheckout || _quantity >= _selectedStock) return;
    AppHaptics.tap();
    setState(() => _quantity += 1);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final stockTone = _stockStatus.tone;
    final originalPrice = _originalPrice;

    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.46,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: EdgeInsets.fromLTRB(20, 10, 20, 18 + bottomInset),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 46,
                            height: 5,
                            decoration: BoxDecoration(
                              color: cs.outlineVariant,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            IconButton(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.close_rounded, size: 30),
                              color: cs.onSurface,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints.tightFor(
                                width: 42,
                                height: 42,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Varian produk',
                              style: TextStyle(
                                color: cs.onSurface,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: AppProductImage(
                                imageUrl: _imageUrl,
                                width: 112,
                                height: 112,
                                fit: BoxFit.contain,
                                borderRadius: BorderRadius.zero,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    formatRupiah(_displayPrice),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: cs.onSurface,
                                      fontSize: 26,
                                      height: 1,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  if (originalPrice != null) ...[
                                    const SizedBox(height: 9),
                                    Text(
                                      formatRupiah(originalPrice),
                                      style: const TextStyle(
                                        color: _discountRed,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        decoration: TextDecoration.lineThrough,
                                        decorationColor: _discountRed,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 10),
                                  _VariantStockPill(status: _stockStatus),
                                  if (_selectedVariant != null &&
                                      cartVariantOptionLabel(
                                            _product,
                                            _selectedVariant!,
                                          ) !=
                                          null) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      cartVariantOptionLabel(
                                        _product,
                                        _selectedVariant!,
                                      )!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: cs.onSurfaceVariant,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        for (final attr in _product.variantAttrs) ...[
                          Text(
                            '${attr.name}:',
                            style: TextStyle(
                              color: cs.onSurface,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: attr.options.map((opt) {
                              final selected =
                                  _selectedOptions[attr.id] == opt.id;
                              final available = _hasVariantFor(attr.id, opt.id);
                              return _VariantChip(
                                label: opt.value,
                                selected: selected,
                                enabled: available,
                                onTap: available
                                    ? () => _selectOption(attr.id, opt.id)
                                    : null,
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 18),
                        ],
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: stockTone.background,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: stockTone.border),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: RichText(
                                  text: TextSpan(
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: _textDark,
                                    ),
                                    children: [
                                      const TextSpan(text: 'Jumlah:  '),
                                      TextSpan(
                                        text: _stockStatus.label,
                                        style: TextStyle(
                                          color: stockTone.foreground,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              _QuantityStepper(
                                quantity: _canCheckout ? _quantity : 0,
                                canDecrease: _canCheckout && _quantity > 1,
                                canIncrease:
                                    _canCheckout && _quantity < _selectedStock,
                                onDecrease: _decrement,
                                onIncrease: _increment,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 18,
                        offset: const Offset(0, -8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _canCheckout
                              ? () => widget.onBuyNow(
                                    _selectedVariant!,
                                    _quantity,
                                  )
                              : null,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _brandBlue,
                            minimumSize: const Size.fromHeight(52),
                            side: const BorderSide(
                              color: _brandBlue,
                              width: 1.2,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                          child: const Text('Beli Sekarang'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _canCheckout
                              ? () => widget.onAddToCart(
                                    _selectedVariant!,
                                    _quantity,
                                  )
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _brandBlue,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(52),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                          child: const Text('+ Keranjang'),
                        ),
                      ),
                    ],
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

enum _VariantStockStatus {
  needSelection,
  available,
  low,
  out;

  String get label {
    switch (this) {
      case _VariantStockStatus.needSelection:
        return 'Pilih varian';
      case _VariantStockStatus.available:
        return 'Stok tersedia';
      case _VariantStockStatus.low:
        return 'Stok hampir habis';
      case _VariantStockStatus.out:
        return 'Stok habis';
    }
  }

  _StatusTone get tone {
    switch (this) {
      case _VariantStockStatus.needSelection:
        return const _StatusTone(
          foreground: _textGray,
          background: Color(0xFFF8FAFC),
          border: _borderGray,
        );
      case _VariantStockStatus.available:
        return const _StatusTone(
          foreground: _successGreen,
          background: Color(0xFFF0FDF4),
          border: Color(0xFFBBF7D0),
        );
      case _VariantStockStatus.low:
        return const _StatusTone(
          foreground: Color(0xFFF97316),
          background: Color(0xFFFFF7ED),
          border: Color(0xFFFED7AA),
        );
      case _VariantStockStatus.out:
        return const _StatusTone(
          foreground: _discountRed,
          background: _softDiscountBg,
          border: Color(0xFFFFC9D0),
        );
    }
  }
}

class _StatusTone {
  final Color foreground;
  final Color background;
  final Color border;

  const _StatusTone({
    required this.foreground,
    required this.background,
    required this.border,
  });
}

class _VariantStockPill extends StatelessWidget {
  final _VariantStockStatus status;

  const _VariantStockPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final tone = status.tone;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.border),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: tone.foreground,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _QuantityStepper extends StatelessWidget {
  final int quantity;
  final bool canDecrease;
  final bool canIncrease;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  const _QuantityStepper({
    required this.quantity,
    required this.canDecrease,
    required this.canIncrease,
    required this.onDecrease,
    required this.onIncrease,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: canDecrease ? onDecrease : null,
            icon: const Icon(Icons.remove_rounded),
            iconSize: 20,
            color: cs.onSurface,
            disabledColor: const Color(0xFFCBD5E1),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 40, height: 40),
          ),
          SizedBox(
            width: 32,
            child: Text(
              '$quantity',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          IconButton(
            onPressed: canIncrease ? onIncrease : null,
            icon: const Icon(Icons.add_rounded),
            iconSize: 22,
            color: cs.onSurface,
            disabledColor: const Color(0xFFCBD5E1),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 40, height: 40),
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
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = selected
        ? _brandBlue
        : enabled
            ? cs.surface
            : (isDark ? cs.surfaceContainerHighest : const Color(0xFFEFF2F6));
    final borderColor = selected ? _brandBlue : cs.outlineVariant;
    final textColor = selected
        ? Colors.white
        : enabled
            ? cs.onSurface
            : cs.onSurfaceVariant;
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
  final VoidCallback onSelectVariant;
  final void Function(ProductVariant? variant, int quantity) onAddToCart;
  final void Function(ProductVariant? variant, int quantity) onBuyNow;

  const _StickyPurchaseBar({
    required this.product,
    required this.selectedVariant,
    required this.needsVariantSelection,
    required this.displayStock,
    required this.onSelectVariant,
    required this.onAddToCart,
    required this.onBuyNow,
  });

  void _onChatWa(BuildContext context) {
    AppHaptics.tap();
    final uri = NataloStoreConfig.whatsappUri(
      message:
          'Halo Admin Natalo, saya ingin tanya tentang produk ${product.title}. Apakah ready?',
    );
    // Best-effort — di mobile ini akan trigger WhatsApp intent.
    launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _onAddToCart(BuildContext context) {
    if (needsVariantSelection) {
      onSelectVariant();
      return;
    }
    onAddToCart(selectedVariant, 1);
  }

  void _onBeliSekarang(BuildContext context) {
    if (needsVariantSelection) {
      onSelectVariant();
      return;
    }
    onBuyNow(selectedVariant, 1);
  }

  @override
  Widget build(BuildContext context) {
    final outOfStock = displayStock <= 0;
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
              onPressed: outOfStock ? null : () => _onBeliSekarang(context),
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

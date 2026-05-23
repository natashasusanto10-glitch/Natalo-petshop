import 'dart:async';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

// sample_brands + sample_products dihapus dari import — Home screen sekarang
// pure API-driven. Brand/produk yang muncul = data live dari Capacitor
// admin dashboard via Next.js API. Loading state pakai skeleton, empty
// state pakai widget dedicated.
import '../models/brand.dart';
import '../models/home_banner.dart';
import '../models/home_category.dart';
import '../models/product.dart';
import '../services/app_analytics.dart';
import '../services/connectivity_service.dart';
import '../services/search_service.dart';
import '../services/product_service.dart';
import '../state/recently_viewed_store.dart';
import '../state/search_history_store.dart';
import '../state/trending_placeholder_controller.dart';
import '../theme/natalo_colors.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import '../utils/in_app_browser.dart';
import '../widgets/app_cart_button.dart';
import '../widgets/app_notification_button.dart';
import '../widgets/app_product_image.dart';
import '../widgets/app_ui.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/flash_sale_countdown.dart';
import '../widgets/glass_surface.dart';
import '../widgets/natalo_paw_refresh_indicator.dart';
import '../widgets/upload_relay_card.dart';
import 'home_search_page.dart';
import '../widgets/skeleton_product_card.dart';

const _brandBlue = NataloColors.nataloBlue;
const _surface = Colors.transparent;

List<Product> _uniqueById(Iterable<Product> products) {
  final seen = <String>{};
  final result = <Product>[];
  for (final product in products) {
    if (seen.add(product.id)) result.add(product);
  }
  return result;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final Future<ProductResult> _productsFuture;
  // ── Infinite scroll "Jelajahi Produk Natalo" — match PWA HomeExploreProducts ──
  final ScrollController _scrollController = ScrollController();
  final List<Product> _exploreProducts = [];
  String? _exploreNextCursor;
  bool _exploreHasMore = true;
  bool _exploreLoading = false;
  bool _exploreInitialLoaded = false;
  int _exploreGeneration = 0;

  // ── Global counter — survive across HomeScreen instances ──
  //
  // Counter di-static supaya hidup across navigation. Setiap kali user
  // "balik ke Beranda" (initState run lagi via tab switch atau product
  // detail close), counter +1. Saat counter >= threshold, reshuffle
  // explore products dengan generation baru.
  //
  // Threshold alternate 2-3 — user spec "berubah setiap 2-3x user balik
  // ke halaman Beranda". Bukan strict 2 atau 3, tapi variasi supaya
  // user tidak bisa predict timing.
  //
  // Counter reset ke 0 saat app fully restart. Acceptable behavior:
  // fresh session = fresh first ordering.
  static int _globalHomeVisitCount = 0;
  static int _globalExploreGeneration = 0;
  static int _globalNextRegenerateThreshold = 2;

  // ── Brand, Category, Banner dynamic fetch ──
  List<PetBrand> _brands = const [];
  List<HomeCategory> _categories = const [];
  List<HomeBanner> _banners = const [];

  // ── Personalized recommendations dari server ──
  // Backend scan full catalog dengan scoring weighted: purchase × 3.0
  // (brand) / × 2.5 (category), view × 1.2 / × 1.8. Untuk user login
  // tambah signal dari order history + server-side user_product_views.
  // Kalau kosong (API gagal / offline / guest), widget fall back ke
  // client-side `_buildPersonalizedRecommendations` yang scan pool 48.
  List<Product> _personalizedRecs = const [];

  @override
  void initState() {
    super.initState();
    // Increment global visit counter — every initState (fresh HomeScreen
    // instance) counts as "user balik ke Beranda". Tab switch via
    // pushNamedAndRemoveUntil creates fresh instance → triggers ini.
    _globalHomeVisitCount += 1;
    if (_globalHomeVisitCount >= _globalNextRegenerateThreshold) {
      _globalHomeVisitCount = 0;
      _globalExploreGeneration += 1;
      // Alternate threshold 2 ↔ 3 supaya rotation tidak strict pattern.
      _globalNextRegenerateThreshold =
          _globalNextRegenerateThreshold == 2 ? 3 : 2;
    }
    _exploreGeneration = _globalExploreGeneration;

    _productsFuture = productService.fetchProducts(limit: 48);
    _scrollController.addListener(_onScroll);
    _loadDynamicSections();
    // ORDER MATTERS: personalized recs load DULU, lalu explore initial.
    // Sebelumnya kedua-duanya paralel → explore initial fetch dengan
    // exclude list kosong → ambil top personalized yang SAMA dengan
    // section "Rekomendasi Untuk Kamu" di atas → duplikat di 2 section.
    _initializeRecsAndExplore();
    // Re-fetch personalized recs setiap kali user buka produk baru
    // (recentlyViewedStore berubah) — server bisa update rekomendasi
    // berdasarkan signal baru.
    recentlyViewedStore.addListener(_onRecentlyViewedChanged);
  }

  /// Sequential init: personalized → explore. Mencegah race condition
  /// duplikat produk antara "Rekomendasi Untuk Kamu" + "Jelajahi".
  Future<void> _initializeRecsAndExplore() async {
    await _loadPersonalizedRecs();
    if (!mounted) return;
    await _loadMoreExplore(initial: true);
  }

  /// Re-fetch personalized recs saat recentlyViewedStore berubah.
  /// Debounce manual: skip kalau fetch terakhir < 5 detik lalu supaya
  /// tidak spam saat user scroll cepat antar produk.
  DateTime? _lastPersonalizedFetch;
  void _onRecentlyViewedChanged() {
    final now = DateTime.now();
    if (_lastPersonalizedFetch != null &&
        now.difference(_lastPersonalizedFetch!).inSeconds < 5) {
      return;
    }
    _loadPersonalizedRecs();
  }

  /// Fetch server-side personalized recommendations. Async, non-blocking.
  /// Hasil di-store di `_personalizedRecs`. Builder di `_RecommendationGrid`
  /// akan fall back ke client-side scoring kalau kosong.
  Future<void> _loadPersonalizedRecs() async {
    _lastPersonalizedFetch = DateTime.now();
    final viewedIds = recentlyViewedStore.items.map((p) => p.id).toList();
    try {
      final recs = await productService.fetchPersonalizedRecommendations(
        viewedIds: viewedIds,
        limit: 10,
      );
      if (!mounted) return;
      setState(() => _personalizedRecs = recs);
    } catch (_) {
      // Fallback ke client-side scoring tetap jalan via builder logic.
    }
  }

  Future<void> _loadDynamicSections() async {
    // Fetch paralel — semua endpoint cached di server (revalidate 300s).
    final results = await Future.wait([
      productService.fetchBrands(),
      productService.fetchCategories(),
      productService.fetchBanners(),
    ]);
    if (!mounted) return;
    setState(() {
      _brands = results[0] as List<PetBrand>;
      _categories = results[1] as List<HomeCategory>;
      _banners = results[2] as List<HomeBanner>;
    });
  }

  /// Pull-to-refresh handler — refetch semua data home (brands, categories,
  /// banners, recommendations, explore products) sekaligus. Haptic medium
  /// di awal supaya user dapat tactile confirmation refresh dimulai.
  Future<void> _refreshAll() async {
    AppHaptics.impact();
    // Reset explore state supaya benar-benar refetch dari halaman 1.
    _resetExploreProducts(regenerate: true);
    // Reset debounce supaya pull-to-refresh selalu trigger ulang.
    _lastPersonalizedFetch = null;
    // _loadDynamicSections paralel — tidak ada dependency dengan
    // personalized/explore. _initializeRecsAndExplore sequential
    // internal (personalized DULU baru explore — mencegah race
    // duplikat IDs).
    await Future.wait([
      _loadDynamicSections(),
      _initializeRecsAndExplore(),
    ]);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    recentlyViewedStore.removeListener(_onRecentlyViewedChanged);
    super.dispose();
  }

  void _onScroll() {
    if (_exploreLoading || !_exploreHasMore) return;
    // Trigger load saat 600px sebelum bottom — match PWA threshold.
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 600) {
      _loadMoreExplore();
    }
  }

  Future<void> _loadMoreExplore({bool initial = false}) async {
    if (_exploreLoading) return;
    if (!initial && !_exploreHasMore) return;
    setState(() => _exploreLoading = true);
    try {
      final accumulated = <Product>[];

      // Initial batch ditambah layer personalized (purchase × view signal).
      // Exclude IDs yang sudah ada di "Rekomendasi Untuk Kamu" supaya tidak
      // duplikat — section di atas Jelajahi. Personalized endpoint cap 20
      // produk, jadi top 10 di Rekomendasi + next 10 di Jelajahi initial.
      if (initial) {
        final excludeForPersonalized =
            _personalizedRecs.map((p) => p.id).toList();
        final viewedIds = recentlyViewedStore.items.map((p) => p.id).toList();
        final personalized =
            await productService.fetchPersonalizedRecommendations(
          viewedIds: viewedIds,
          excludeIds: excludeForPersonalized,
          limit: 8,
        );
        accumulated.addAll(personalized);
      }

      // Cursor catalog browse — append untuk variation + scrollable depth.
      // Filter `withImage=true` dihapus supaya produk dummy tanpa foto
      // tetap muncul (placeholder fallback di _HomeProductCard).
      final page = await productService.fetchProductsPage(
        cursor: _exploreNextCursor,
        limit: 14,
        withImage: false,
      );
      accumulated.addAll(page.products);

      if (!mounted) return;
      final nextProducts = _generateExploreProducts(accumulated);
      setState(() {
        final existingIds = _exploreProducts.map((item) => item.id).toSet();
        // Juga exclude IDs dari Rekomendasi Untuk Kamu section.
        final personalizedIds = _personalizedRecs.map((p) => p.id).toSet();
        _exploreProducts.addAll(
          nextProducts.where(
            (item) =>
                !personalizedIds.contains(item.id) && existingIds.add(item.id),
          ),
        );
        _exploreNextCursor = page.nextCursor;
        _exploreHasMore = page.hasMore && page.products.isNotEmpty;
        _exploreLoading = false;
        _exploreInitialLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _exploreLoading = false;
        _exploreHasMore = false;
        _exploreInitialLoaded = true;
      });
    }
  }

  void _resetExploreProducts({required bool regenerate}) {
    setState(() {
      if (regenerate) {
        _globalExploreGeneration += 1;
        _exploreGeneration = _globalExploreGeneration;
      }
      _exploreProducts.clear();
      _exploreNextCursor = null;
      _exploreHasMore = true;
      _exploreInitialLoaded = false;
    });
  }

  void _openProductDetail(BuildContext context, Product product) {
    // Preload main image + first gallery image sebelum navigate supaya
    // ProductDetail render instant tanpa shimmer flicker. Async tapi
    // tidak di-await — kalau image belum sempat preload, fallback ke
    // normal cache miss yang sudah handled by CachedNetworkImage.
    if (product.imageUrl.isNotEmpty) {
      precacheImage(CachedNetworkImageProvider(product.imageUrl), context);
    }
    if (product.gallery.isNotEmpty) {
      precacheImage(
        CachedNetworkImageProvider(product.gallery.first),
        context,
      );
    }
    Navigator.pushNamed(context, '/product-detail', arguments: product)
        .whenComplete(_maybeRegenerateExploreAfterReturn);
  }

  /// Trigger setelah product detail close (`.whenComplete`). User
  /// "balik ke Beranda" via back navigation dari detail = same count
  /// sebagai tab switch back to Beranda. Pakai global counter.
  void _maybeRegenerateExploreAfterReturn() {
    if (!mounted || _exploreLoading) return;
    _globalHomeVisitCount += 1;
    if (_globalHomeVisitCount < _globalNextRegenerateThreshold) return;
    _globalHomeVisitCount = 0;
    _globalNextRegenerateThreshold =
        _globalNextRegenerateThreshold == 2 ? 3 : 2;
    _resetExploreProducts(regenerate: true);
    _loadMoreExplore(initial: true);
  }

  void _openProducts(BuildContext context, {String? brand, String? category}) {
    Navigator.pushNamed(
      context,
      '/products',
      arguments: ProductCatalogArgs(
        selectedBrand: brand,
        initialCategory: category,
      ),
    );
  }

  /// Personalized recommendation algorithm.
  ///
  /// Combines TWO behavior signals:
  /// 1. **Recently viewed products** (`recentlyViewedStore`) — kebiasaan
  ///    user buka detail produk. Brand + category dari viewed → score.
  /// 2. **Search history** (`searchHistoryStore`) — kebiasaan user
  ///    mencari produk (search queries di Produk screen). Token-match
  ///    keyword vs product title/brand/category → score.
  ///
  /// Bobot search keyword PALING TINGGI (×2.0) untuk title match karena
  /// search intent eksplisit lebih kuat dibanding pasif view. Recent
  /// search dapat weight lebih tinggi via newest-first ordering.
  ///
  /// Fallback (kalau viewed + search semuanya kosong): pakai
  /// `_fallbackRecommendations` (promo + popular by reviewCount).
  List<Product> _buildPersonalizedRecommendations(List<Product> products) {
    if (products.isEmpty) return const [];

    final viewed = recentlyViewedStore.items;
    final searches = searchHistoryStore.entries;
    final fallback = _fallbackRecommendations(products);
    if (viewed.isEmpty && searches.isEmpty) return fallback;

    final viewedIds = viewed.map((product) => product.id).toSet();
    final brandScores = <String, double>{};
    final categoryScores = <String, double>{};

    // Signal 1: viewed products → brand + category preference.
    for (var index = 0; index < viewed.length; index += 1) {
      final product = viewed[index];
      final weight = (viewed.length - index).toDouble();
      final brand = product.brand.trim().toLowerCase();
      final category = product.category.trim().toLowerCase();
      if (brand.isNotEmpty) {
        brandScores[brand] = (brandScores[brand] ?? 0) + weight;
      }
      if (category.isNotEmpty) {
        categoryScores[category] = (categoryScores[category] ?? 0) + weight;
      }
    }

    // Signal 2: search history → keyword tokens dengan recency weight.
    // Tokenize multi-word query (mis. "makanan kucing" → ['makanan',
    // 'kucing']) supaya bisa match parsial dengan product field.
    final searchKeywords = <String, double>{};
    for (var i = 0; i < searches.length; i += 1) {
      final keyword = searches[i].toLowerCase().trim();
      if (keyword.isEmpty) continue;
      final weight = (searches.length - i).toDouble();
      // Whole query as one token (untuk exact match).
      searchKeywords[keyword] = (searchKeywords[keyword] ?? 0) + weight;
      // Plus individual tokens (untuk partial match).
      for (final token in keyword.split(RegExp(r'\s+'))) {
        if (token.length < 2) continue;
        if (token != keyword) {
          searchKeywords[token] = (searchKeywords[token] ?? 0) + weight * 0.5;
        }
      }
    }

    double score(Product product) {
      final brand = product.brand.trim().toLowerCase();
      final category = product.category.trim().toLowerCase();
      final title = product.title.toLowerCase();
      var value = 0.0;

      // From viewed-history signal (passive interest).
      value += (brandScores[brand] ?? 0) * 1.2;
      value += (categoryScores[category] ?? 0) * 1.8;

      // From search-history signal (ACTIVE intent — bobot lebih tinggi).
      // Title match = strongest signal (user explicitly searched something
      // matching product name).
      for (final entry in searchKeywords.entries) {
        final keyword = entry.key;
        final w = entry.value;
        if (title.contains(keyword)) value += w * 2.4;
        if (brand.contains(keyword)) value += w * 1.6;
        if (category.contains(keyword)) value += w * 1.6;
      }

      if (product.hasDiscount) value += 0.8;
      value += product.rating.clamp(0, 5) * 0.18;
      value += product.reviewCount.clamp(0, 500) / 500;
      return value;
    }

    final candidates = products
        .where((product) => !viewedIds.contains(product.id))
        .toList()
      ..sort((a, b) => score(b).compareTo(score(a)));
    final personalized = candidates.where((product) => score(product) > 0);
    return _uniqueById([...personalized, ...fallback, ...products])
        .take(10)
        .toList();
  }

  List<Product> _fallbackRecommendations(List<Product> products) {
    final promoProducts = products.where((product) => product.hasDiscount);
    final popularProducts = [...products]
      ..sort((a, b) => b.reviewCount.compareTo(a.reviewCount));
    return _uniqueById([...promoProducts, ...popularProducts, ...products])
        .take(10)
        .toList();
  }

  List<Product> _generateExploreProducts(List<Product> products) {
    if (products.length <= 1) return products;
    final viewed = recentlyViewedStore.items;
    final brandScores = <String, int>{};
    final categoryScores = <String, int>{};

    for (var index = 0; index < viewed.length; index += 1) {
      final weight = viewed.length - index;
      final brand = viewed[index].brand.trim().toLowerCase();
      final category = viewed[index].category.trim().toLowerCase();
      if (brand.isNotEmpty) {
        brandScores[brand] = (brandScores[brand] ?? 0) + weight;
      }
      if (category.isNotEmpty) {
        categoryScores[category] = (categoryScores[category] ?? 0) + weight;
      }
    }

    final generated = [...products]..sort((a, b) {
        final scoreCompare =
            _exploreScore(b, brandScores, categoryScores).compareTo(
          _exploreScore(a, brandScores, categoryScores),
        );
        if (scoreCompare != 0) return scoreCompare;
        return _stableExploreHash(a.id).compareTo(_stableExploreHash(b.id));
      });
    return generated;
  }

  int _exploreScore(
    Product product,
    Map<String, int> brandScores,
    Map<String, int> categoryScores,
  ) {
    final brand = product.brand.trim().toLowerCase();
    final category = product.category.trim().toLowerCase();
    var score = 0;
    score += (brandScores[brand] ?? 0) * 3;
    score += (categoryScores[category] ?? 0) * 5;
    if (product.hasDiscount) score += 2;
    score += product.reviewCount.clamp(0, 200) ~/ 40;
    score += _stableExploreHash(product.id) % 7;
    return score;
  }

  int _stableExploreHash(String value) {
    var hash = 0x811C9DC5 ^ _exploreGeneration;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }

  /// Open fullscreen search page (BerandaSearchPage).
  ///
  /// Previously pakai `showModalBottomSheet` dengan transparent
  /// background → bug: blur abu-abu, input susah dilihat, layout
  /// rusak saat keyboard muncul. Sekarang Navigator.push proper
  /// fullscreen route, no blur, search input autofocus dengan
  /// keyboard handle benar di iOS + Android.
  void _openHomeSearch(BuildContext context) {
    AppHaptics.tap();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const HomeSearchPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      // SafeArea(top: true, bottom: false) — top handle status bar / notch /
      // camera punch-hole (Android). Bottom inset di-handle Scaffold
      // bottomNavigationBar slot, BUKAN SafeArea internal — supaya tidak
      // double padding di iPhone X+ (home indicator) atau Android gesture.
      body: SafeArea(
        top: true,
        bottom: false,
        child: FutureBuilder<ProductResult>(
          future: _productsFuture,
          // Initial data empty supaya skeleton/loading UI muncul first paint
          // — bukan flash sampleProducts mock. Capacitor admin dashboard
          // adalah single source of truth.
          initialData: const ProductResult(
            products: <Product>[],
            fromApi: false,
          ),
          builder: (context, snapshot) {
            final result = snapshot.data;
            final products = result?.products ?? const <Product>[];
            // 3-tier eligibility — match backend getFlashSaleProducts():
            //   1. Explicit flashSaleEndsAt set + di future → always
            //   2. flashSaleEndsAt null + discount >= 20% → auto-include
            //   3. flashSaleEndsAt expired → exclude
            // Sorting: explicit-tagged (Tier 1) di awal sorted by earliest
            // endsAt, lalu Tier 2 by discount % desc.
            final flashSale =
                products.where((p) => p.isFlashSaleEligible).toList()
                  ..sort((a, b) {
                    final aEnds = a.flashSaleEndsAt;
                    final bEnds = b.flashSaleEndsAt;
                    if (aEnds != null && bEnds != null) {
                      return aEnds.compareTo(bEnds);
                    }
                    if (aEnds != null) return -1;
                    if (bEnds != null) return 1;
                    final aPct = a.discountPercent ?? 0;
                    final bPct = b.discountPercent ?? 0;
                    return bPct.compareTo(aPct);
                  });
            final flashSaleVisible = flashSale.take(8).toList();
            // Produk Terlaris — ranked by SOLD COUNT (jumlah terjual) sebagai
            // primary key. Tie-break ke reviewCount kalau soldCount sama
            // (mis. saat API list endpoint return soldCount=0 — fallback
            // graceful ke review-based ranking yang previously hardcoded).
            //
            // Filter: utamakan products dengan soldCount > 0 di top — yang
            // benar2 "laris" muncul lebih dulu. Kalau API belum return
            // soldCount yang valid, section fallback ke review-based.
            final bestSellers = ([...products]..sort((a, b) {
                    // Primary: soldCount desc (yang paling banyak terjual)
                    final byCount = b.soldCount.compareTo(a.soldCount);
                    if (byCount != 0) return byCount;
                    // Tie-break: reviewCount desc
                    return b.reviewCount.compareTo(a.reviewCount);
                  }))
                .take(8)
                .toList();
            return NataloPawRefreshIndicator(
              onRefresh: _refreshAll,
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _HomeStickyHeaderDelegate(
                      onOpenProducts: () => _openProducts(context),
                      onOpenSearch: () => _openHomeSearch(context),
                    ),
                  ),
                  // Background upload relay card — visible HANYA saat ada
                  // upload feed post aktif. AnimatedSize handle collapse
                  // smooth saat task hilang (success auto-dismiss).
                  const SliverToBoxAdapter(child: UploadRelayCard()),
                  if (result?.fromApi == false)
                    const SliverToBoxAdapter(child: _ApiFallbackNotice()),
                  // Trust marquee — TIDAK sticky. Ikut scroll bersama content
                  // di bawah sticky header (search bar). Saat user scroll
                  // ke bawah, trust strip hilang dari viewport, hanya search
                  // bar yang tetap visible.
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: _TrustMarquee(
                        key: ValueKey('home-trust-marquee'),
                        height: 36,
                      ),
                    ),
                  ),
                  // API banner carousel kalau ada banner aktif dari admin.
                  // Section auto-hide kalau _banners kosong (di _HeroBanner).
                  SliverToBoxAdapter(child: _HeroBanner(banners: _banners)),
                  SliverToBoxAdapter(
                    child: _ShortcutGrid(
                        onOpenProducts: () => _openProducts(context)),
                  ),
                  // Flash sale section — sembunyikan kalau tidak ada produk
                  // diskon dari API (bukan fallback ke mock). Single source of
                  // truth = Capacitor admin (admin set hasDiscount=true).
                  if (flashSaleVisible.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _FlashSaleGrid(
                        products: flashSaleVisible,
                        onTap: (product) =>
                            _openProductDetail(context, product),
                        onSeeAll: () => _openProducts(context),
                        onCountdownExpired: () {
                          // Refresh products supaya item yang expired
                          // hilang dari grid. Backend juga filter
                          // server-side, jadi list akan auto-cleanup.
                          _refreshAll();
                        },
                      ),
                    ),
                  // Produk Terlaris — sembunyikan kalau API belum return data.
                  if (bestSellers.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _HorizontalProductSection(
                        title: 'Produk Terlaris',
                        subtitle: 'Paling sering dibeli member Natalo',
                        products: bestSellers,
                        showRank: true,
                        onTap: (product) =>
                            _openProductDetail(context, product),
                      ),
                    ),
                  // Brand section — sembunyikan kalau API belum return data.
                  // Tidak ada fallback ke sampleBrands lagi: brand di Flutter
                  // harus sync dengan Capacitor admin dashboard (single source
                  // of truth). Skeleton/empty state ditangani di section sendiri.
                  if (_brands.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _BrandChoiceSection(
                        brands: _brands.take(12).toList(),
                        onTap: (brand) =>
                            _openProducts(context, brand: brand.name),
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: _CategorySection(
                      categories: _categories,
                      // Pass category name — ProductsScreen filter cocok by name
                      // (lihat `_filter.category == null || product.category == _filter.category`).
                      onTap: (name) => _openProducts(context, category: name),
                    ),
                  ),
                  // Rekomendasi personal — utamakan hasil server-side
                  // scoring (`_personalizedRecs`) yang scan SELURUH catalog
                  // dengan signal purchase + view weighted. Fallback ke
                  // client-side scoring (pool 48) kalau API gagal /
                  // offline / response kosong.
                  SliverToBoxAdapter(
                    child: AnimatedBuilder(
                      animation: recentlyViewedStore,
                      builder: (context, _) {
                        final recommendations = _personalizedRecs.isNotEmpty
                            ? _personalizedRecs
                            : _buildPersonalizedRecommendations(products);
                        if (recommendations.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return _RecommendationGrid(
                          products: recommendations,
                          onTap: (product) =>
                              _openProductDetail(context, product),
                        );
                      },
                    ),
                  ),
                  // ── "Jelajahi Produk Natalo" infinite scroll section ──
                  // Match PWA app/page.tsx HomeExploreProducts — semua produk
                  // diakhiri infinite scroll di sini.
                  const SliverToBoxAdapter(
                    child: _ExploreSectionHeader(),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        // Lebih tinggi untuk metadata hemat + rating/terjual.
                        childAspectRatio: 0.54,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          // Saat first load belum ada produk + masih loading,
                          // tampilkan skeleton — feels lebih native dari blank.
                          if (_exploreProducts.isEmpty &&
                              !_exploreInitialLoaded) {
                            return const SkeletonProductCard(
                              showAddToCart: false,
                            );
                          }
                          if (index >= _exploreProducts.length) {
                            // Safety guard
                            return const SizedBox.shrink();
                          }
                          final product = _exploreProducts[index];
                          return _HomeProductCard(
                            product: product,
                            onTap: () => _openProductDetail(context, product),
                          );
                        },
                        childCount:
                            _exploreProducts.isEmpty && !_exploreInitialLoaded
                                ? 6
                                : _exploreProducts.length,
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _ExploreFooter(
                      loading: _exploreLoading,
                      hasMore: _exploreHasMore,
                      initialLoaded: _exploreInitialLoaded,
                      productsCount: _exploreProducts.length,
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: const BottomNavBar(currentIndex: 0),
    );
  }
}

/// Header section "Jelajahi Produk Natalo" — match PWA app/page.tsx
/// (text-base font-black + subtitle gray).
class _ExploreSectionHeader extends StatelessWidget {
  const _ExploreSectionHeader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 28, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Jelajahi Produk Natalo',
            style: TextStyle(
              color: Color(0xFF111827),
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Temukan berbagai kebutuhan hewan kesayanganmu di Natalo',
            style: TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Footer infinite scroll: loader saat fetching, atau "Semua produk
/// sudah ditampilkan" saat hasMore false. Match PWA HomeExploreProducts.
class _ExploreFooter extends StatelessWidget {
  final bool loading;
  final bool hasMore;
  final bool initialLoaded;
  final int productsCount;

  const _ExploreFooter({
    required this.loading,
    required this.hasMore,
    required this.initialLoaded,
    required this.productsCount,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            height: 24,
            width: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (!hasMore && initialLoaded && productsCount > 0) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Center(
          child: Text(
            'Semua produk sudah ditampilkan',
            style: TextStyle(
              color: Color(0xFF9CA3AF),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
    return const SizedBox(height: 16);
  }
}

/// Banner saat fetch produk gagal. Cek ConnectivityService dulu — kalau
/// device benar2 offline, tampilkan pesan koneksi; selain itu copy netral
/// supaya user tidak otomatis menyalahkan internetnya (bisa jadi server
/// lambat, timeout sementara, dsb).
class _ApiFallbackNotice extends StatelessWidget {
  const _ApiFallbackNotice();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: connectivityService,
      builder: (context, _) {
        final offline = connectivityService.isOffline;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: AppInfoBanner(
            icon: offline ? Icons.wifi_off : Icons.refresh,
            message: offline
                ? 'Tidak ada koneksi internet. Coba lagi setelah online.'
                : 'Belum berhasil memuat. Tarik ke bawah untuk coba lagi.',
          ),
        );
      },
    );
  }
}

/// Collapsible sticky header — top state (logo+subtitle+search) menyusut
/// ke compact state (logo kecil, no subtitle, search) saat user scroll.
/// Lerp via shrinkOffset progress 0→1.
///
/// Top state: 128px (logo 44 + subtitle visible + search 42 + paddings)
/// Compact state: 120px (logo 32 + no subtitle + search 42 + paddings)
///
/// Spec acceptance: search bar 42px konsisten di kedua state, breathing
/// room cukup supaya tidak ke-clip oleh sliver boundary, smooth
/// easeOutCubic transition. Trust marquee bukan bagian sticky (sudah
/// dipindah ke SliverToBoxAdapter terpisah).
class _HomeStickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  final VoidCallback onOpenProducts;
  final VoidCallback onOpenSearch;

  const _HomeStickyHeaderDelegate({
    required this.onOpenProducts,
    required this.onOpenSearch,
  });

  // Extent calc — Row di sticky di-dominasi IconButton (Bell + Cart) yang
  // Material default min height 48px (touch target), BUKAN logo 32-44.
  // Content compact: padTop 6 + Row 48 + gap 8 + search 42 + padBottom 10 = 114
  // Content top:     padTop 8 + Row 48 + gap 10 + search 42 + padBottom 12 = 120
  // Extent perlu ≥ content + breathing room supaya shadow + radius search
  // tidak ke-clip oleh sliver boundary. Sebelumnya compact 100 → overflow
  // 8px → search bar bottom kepotong saat scroll (user report).
  static const double _topExtent = 128;
  static const double _compactExtent = 120;

  @override
  double get minExtent => _compactExtent;

  @override
  double get maxExtent => _topExtent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final maxShrink = (maxExtent - minExtent).clamp(1, double.infinity);
    final rawProgress = (shrinkOffset / maxShrink).clamp(0.0, 1.0).toDouble();
    // easeOutCubic untuk natural deceleration — match spec.
    final t = Curves.easeOutCubic.transform(rawProgress);

    return SizedBox.expand(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            bottom: BorderSide(
              color: Color.lerp(
                const Color(0x00EFF4FA),
                const Color(0xFFEFF4FA),
                t,
              )!,
            ),
          ),
          boxShadow: t > 0.05
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04 + 0.04 * t),
                    blurRadius: 12 * t,
                    offset: Offset(0, 4 * t),
                  ),
                ]
              : const [],
        ),
        child: _HomeHeader(
          onOpenProducts: onOpenProducts,
          onOpenSearch: onOpenSearch,
          progress: t,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _HomeStickyHeaderDelegate oldDelegate) {
    return oldDelegate.onOpenProducts != onOpenProducts ||
        oldDelegate.onOpenSearch != onOpenSearch;
  }
}

/// Header Beranda dengan collapsible behavior.
///
/// [progress] 0.0 = top state (full), 1.0 = compact (scrolled).
/// Driven by parent `_HomeStickyHeaderDelegate` via shrinkOffset lerp
/// dengan easeOutCubic.
///
/// Visual changes saat scroll:
/// - Logo box: 44 → 32 (lerp)
/// - Title font: 18 → 16
/// - Subtitle: opacity 1 → 0, height 18 → 0 (fully collapses)
/// - Search bar: TETAP 42px (was 38 — terlalu rapat, ke-clip di compact)
/// - Outer padding: top 8 → 6, bottom 12 → 10 (was 8, ke-clip)
///
/// Catatan: trust marquee TIDAK lagi bagian sticky header. Trust strip
/// di-render sebagai SliverToBoxAdapter terpisah di bawah sticky header
/// sehingga ikut scroll bersama content (user request).
class _HomeHeader extends StatelessWidget {
  final VoidCallback onOpenProducts;
  final VoidCallback onOpenSearch;
  final double progress;

  const _HomeHeader({
    required this.onOpenProducts,
    required this.onOpenSearch,
    this.progress = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    final logoSize = ui.lerpDouble(44, 32, progress)!;
    final logoRadius = ui.lerpDouble(13, 10, progress)!;
    final titleSize = ui.lerpDouble(18, 16, progress)!;
    final subtitleOpacity = (1 - progress * 1.6).clamp(0.0, 1.0);
    final subtitleHeight = ui.lerpDouble(18, 0, progress)!;
    final paddingTop = ui.lerpDouble(8, 6, progress)!;
    // Padding bottom: spec minta 10-12px supaya search bar tidak nempel
    // ke border bawah sticky (sebelumnya 8 di compact = terlalu rapat,
    // shadow + radius search ke-clip).
    final paddingBottom = ui.lerpDouble(12, 10, progress)!;
    final gapAfterRow = ui.lerpDouble(10, 8, progress)!;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, paddingTop, 16, paddingBottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Row 1: Logo + Title (+ Subtitle saat top) + Bell + Cart ──
          Row(
            children: [
              Container(
                width: logoSize,
                height: logoSize,
                decoration: BoxDecoration(
                  color: const Color(0xFF0B7FEA),
                  borderRadius: BorderRadius.circular(logoRadius),
                ),
                clipBehavior: Clip.antiAlias,
                alignment: Alignment.center,
                // Logo asset square — match Capacitor. Fallback "NL" text.
                child: Image.asset(
                  'assets/native/icon-only.png',
                  width: logoSize,
                  height: logoSize,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Text(
                    'NL',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: logoSize * 0.4,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Natalo Petshop',
                      style: TextStyle(
                        fontSize: titleSize,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF17202A),
                        height: 1.15,
                      ),
                    ),
                    // Subtitle — fade + collapse saat scroll.
                    // ClipRect supaya overflow tidak bocor saat height 0.
                    ClipRect(
                      child: SizedBox(
                        height: subtitleHeight,
                        child: Opacity(
                          opacity: subtitleOpacity,
                          child: const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Text(
                              'Kebutuhan hewan kesayanganmu',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF6B7280),
                                height: 1.1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const AppNotificationButton(),
              const AppCartButton(),
            ],
          ),
          SizedBox(height: gapAfterRow),
          // ── Search bar 42px (spec: 42-44 untuk ruang vertikal cukup
          // termasuk border + radius + shadow). Sebelumnya 38 → kurang
          // ruang di compact state, bagian bawah ke-clip saat scroll.
          GestureDetector(
            onTap: onOpenSearch,
            behavior: HitTestBehavior.opaque,
            child: Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: Color(0xFF94A3B8),
                  ),
                  const SizedBox(width: 10),
                  // Dynamic placeholder — rotates dari trending search API +
                  // fallback static. Hanya widget Text ini yang rebuild
                  // (via AnimatedBuilder listen trendingPlaceholderController),
                  // banner/kategori/produk sections TIDAK ke-rebuild saat
                  // placeholder ganti setiap 4 detik.
                  Expanded(
                    child: AnimatedBuilder(
                      animation: trendingPlaceholderController,
                      builder: (context, _) {
                        final text =
                            trendingPlaceholderController.currentPlaceholder;
                        return AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          // Override default Stack(alignment: center) — supaya
                          // text placeholder rata KIRI (sebelah kanan icon),
                          // bukan center di Expanded space. Pattern marketplace
                          // standard: icon + text mengalir dari kiri.
                          layoutBuilder: (currentChild, previousChildren) {
                            return Stack(
                              alignment: Alignment.centerLeft,
                              children: <Widget>[
                                ...previousChildren,
                                if (currentChild != null) currentChild,
                              ],
                            );
                          },
                          transitionBuilder: (child, animation) {
                            final slide = Tween<Offset>(
                              begin: const Offset(0, 0.3),
                              end: Offset.zero,
                            ).animate(animation);
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: slide,
                                child: child,
                              ),
                            );
                          },
                          child: Text(
                            text,
                            key: ValueKey(text),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.left,
                            style: const TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Trust marquee dipindah keluar sticky header — sekarang berada
          // di SliverToBoxAdapter terpisah di bawah ini (ikut scroll, bukan
          // pinned). Bentuknya tetap _TrustMarquee dengan ValueKey stabil.
        ],
      ),
    );
  }
}

class _HomeSearchSheet extends StatefulWidget {
  const _HomeSearchSheet();

  @override
  State<_HomeSearchSheet> createState() => _HomeSearchSheetState();
}

class _HomeSearchSheetState extends State<_HomeSearchSheet> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;
  SearchSuggestionResult _suggestions = const SearchSuggestionResult();
  bool _loading = false;
  // Popular + trending terms — di-load saat sheet open, di-cache untuk
  // session ini. Server provide top queries hari ini.
  List<String> _popular = const [];
  List<String> _trending = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
    _loadDiscoveryTerms();
  }

  Future<void> _loadDiscoveryTerms() async {
    final results = await Future.wait([
      searchService.popular(),
      searchService.trending(),
    ]);
    if (!mounted) return;
    setState(() {
      _popular = results[0];
      _trending = results[1];
    });
  }

  void _tapDiscoveryTerm(String term) {
    _controller.text = term;
    _submit(term);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final keyword = value.trim();
    if (keyword.length < 2) {
      setState(() {
        _suggestions = const SearchSuggestionResult();
        _loading = false;
      });
      return;
    }

    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 260), () async {
      final suggestions = await productService.fetchSuggestions(keyword);
      if (!mounted || _controller.text.trim() != keyword) return;
      setState(() {
        _suggestions = suggestions;
        _loading = false;
      });
    });
  }

  void _submit(String value) {
    final keyword = value.trim();
    if (keyword.isEmpty) return;
    // Analytics — log search event untuk UX research.
    AppAnalytics.logEvent('search', {'search_term': keyword});
    // Server log untuk popular/trending aggregation (fire-and-forget).
    searchService.log(keyword);
    Navigator.pop(context, keyword);
  }

  void _openCategory(LabelSuggestion item) {
    Navigator.pop(context);
    Navigator.pushNamed(
      context,
      '/products',
      arguments: ProductCatalogArgs(initialCategory: item.name),
    );
  }

  void _openBrand(LabelSuggestion item) {
    Navigator.pop(context);
    Navigator.pushNamed(
      context,
      '/products',
      arguments: ProductCatalogArgs(selectedBrand: item.name),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final keyword = _controller.text.trim();

    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, bottom + 12),
      child: GlassSurface(
        radius: 30,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.76,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 5,
                  width: 46,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const SoftIconTile(icon: Icons.search_rounded, size: 44),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Cari Produk Natalo',
                            style: TextStyle(
                              color: Color(0xFF17202A),
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            'Produk, brand, kategori, dan kebutuhan pet kamu.',
                            style: TextStyle(
                              color: Color(0xFF6B7280),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  onChanged: _onChanged,
                  onSubmitted: _submit,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Cari pakan, aksesoris, vitamin...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: keyword.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _controller.clear();
                              _onChanged('');
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: _HomeSearchContent(
                      key: ValueKey('$keyword-$_loading'),
                      query: keyword,
                      suggestions: _suggestions,
                      loading: _loading,
                      popular: _popular,
                      trending: _trending,
                      onSearch: _tapDiscoveryTerm,
                      onProduct: (item) => _submit(item.name),
                      onCategory: _openCategory,
                      onBrand: _openBrand,
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

class _HomeSearchContent extends StatelessWidget {
  final String query;
  final SearchSuggestionResult suggestions;
  final bool loading;
  final List<String> popular;
  final List<String> trending;
  final ValueChanged<String> onSearch;
  final ValueChanged<ProductSuggestion> onProduct;
  final ValueChanged<LabelSuggestion> onCategory;
  final ValueChanged<LabelSuggestion> onBrand;

  const _HomeSearchContent({
    super.key,
    required this.query,
    required this.suggestions,
    required this.loading,
    required this.popular,
    required this.trending,
    required this.onSearch,
    required this.onProduct,
    required this.onCategory,
    required this.onBrand,
  });

  @override
  Widget build(BuildContext context) {
    if (query.length < 2) {
      return _PopularSearchSeeds(
        popular: popular,
        trending: trending,
        onTap: onSearch,
      );
    }

    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text(
              'Mencari saran...',
              style: TextStyle(
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    }

    if (suggestions.isEmpty) {
      return ListView(
        shrinkWrap: true,
        children: [
          _HomeSearchRow(
            icon: Icons.search_rounded,
            title: 'Cari "$query"',
            subtitle: 'Lihat semua hasil di katalog',
            onTap: () => onSearch(query),
          ),
        ],
      );
    }

    return ListView(
      shrinkWrap: true,
      children: [
        ...suggestions.brands.take(3).map(
              (item) => _HomeSearchRow(
                icon: Icons.workspace_premium_outlined,
                title: 'Brand: ${item.name}',
                subtitle: '${item.count} produk',
                onTap: () => onBrand(item),
              ),
            ),
        ...suggestions.categories.take(3).map(
              (item) => _HomeSearchRow(
                icon: Icons.category_outlined,
                title: 'Kategori: ${item.name}',
                subtitle: '${item.count} produk',
                onTap: () => onCategory(item),
              ),
            ),
        ...suggestions.products.take(5).map(
              (item) => _HomeProductSuggestionRow(
                item: item,
                onTap: () => onProduct(item),
              ),
            ),
      ],
    );
  }
}

class _PopularSearchSeeds extends StatelessWidget {
  final List<String> popular;
  final List<String> trending;
  final ValueChanged<String> onTap;

  const _PopularSearchSeeds({
    required this.popular,
    required this.trending,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Fallback seeds kalau server endpoint belum return data.
    const fallbackSeeds = [
      'Royal Canin',
      'Pasir kucing',
      'Vitamin',
      'Snack kucing',
      'Grooming',
      'Aquarium',
    ];
    final displayPopular = popular.isNotEmpty ? popular : fallbackSeeds;

    return ListView(
      children: [
        const AppInfoBanner(
          icon: Icons.tips_and_updates_outlined,
          message:
              'Ketik minimal 2 huruf untuk melihat saran produk real-time.',
          color: _brandBlue,
        ),
        if (trending.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Row(
            children: [
              Icon(Icons.local_fire_department_rounded,
                  color: Color(0xFFEF4444), size: 18),
              SizedBox(width: 6),
              Text(
                'Trending sekarang',
                style: TextStyle(
                  color: Color(0xFF17202A),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: trending.map((term) {
              return ActionChip(
                avatar: const Icon(Icons.trending_up_rounded,
                    size: 16, color: Color(0xFFEF4444)),
                label: Text(term),
                onPressed: () => onTap(term),
              );
            }).toList(),
          ),
        ],
        const SizedBox(height: 14),
        const Text(
          'Pencarian populer',
          style: TextStyle(
            color: Color(0xFF17202A),
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: displayPopular.map((seed) {
            return ActionChip(
              avatar: const Icon(Icons.search_rounded, size: 16),
              label: Text(seed),
              onPressed: () => onTap(seed),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _HomeSearchRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _HomeSearchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: SoftIconTile(icon: icon, size: 40),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.north_west_rounded, size: 18),
      onTap: onTap,
    );
  }
}

class _HomeProductSuggestionRow extends StatelessWidget {
  final ProductSuggestion item;
  final VoidCallback onTap;

  const _HomeProductSuggestionRow({
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final priceLabel = item.priceMax > item.priceMin
        ? '${formatRupiah(item.priceMin)} - ${formatRupiah(item.priceMax)}'
        : formatRupiah(item.priceMin);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AppProductImage(
          imageUrl: item.imageUrl,
          height: 44,
          width: 44,
        ),
      ),
      title: Text(
        item.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      subtitle: Text('${item.brandName ?? 'Produk'} · $priceLabel'),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _TrustMarquee extends StatefulWidget {
  /// Visual height — default 38 (top state), lerp ke 32 saat header
  /// collapse di compact state (driven by _HomeHeader).
  final double height;

  const _TrustMarquee({super.key, this.height = 38});

  @override
  State<_TrustMarquee> createState() => _TrustMarqueeState();
}

class _TrustMarqueeState extends State<_TrustMarquee>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const _textStyle = TextStyle(
    color: Color(0xFF334155),
    fontSize: 11.5,
    fontWeight: FontWeight.w800,
  );

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 34),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<_TrustMarqueeItemData> _items(BuildContext context) {
    return [
      const _TrustMarqueeItemData(
        icon: Icons.local_shipping_outlined,
        iconColor: Color(0xFF143E7E),
        text: 'Gratis Ongkir Area Medan',
      ),
      const _TrustMarqueeItemData(
        icon: Icons.shield_outlined,
        iconColor: Color(0xFF16A34A),
        text: 'Produk Original 100%',
      ),
      _TrustMarqueeItemData(
        icon: Icons.chat_bubble_outline_rounded,
        iconColor: const Color(0xFF143E7E),
        text: 'Konsultasi via WhatsApp',
        showLinkIcon: true,
        onTap: () {
          AppHaptics.tap();
          final text = Uri.encodeComponent(
            'Halo Natalo Petshop, saya mau tanya...',
          );
          launchUrl(
            Uri.parse('https://wa.me/6281289997113?text=$text'),
            mode: LaunchMode.externalApplication,
          );
        },
      ),
      _TrustMarqueeItemData(
        icon: Icons.pets_rounded,
        iconColor: const Color(0xFF143E7E),
        text: 'Petshop Medan Terpercaya',
        onTap: () => AppInAppBrowser.openTentangNatalo(context),
      ),
      const _TrustMarqueeItemData(
        icon: Icons.card_giftcard_rounded,
        iconColor: Color(0xFFF59E0B),
        text: 'Banyak Promo Setiap Hari',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final items = _items(context);
    final groupWidth = _estimateGroupWidth(items);
    return Container(
      height: widget.height,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFFEAF5FF),
            Colors.white,
            Color(0xFFFFFBEB),
          ],
        ),
        border: Border.symmetric(
          horizontal: BorderSide(color: Color(0xFFE6F1FF)),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(-groupWidth * _controller.value, 0),
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: groupWidth * 2,
              maxWidth: groupWidth * 2,
              child: child,
            ),
          );
        },
        child: SizedBox(
          width: groupWidth * 2,
          child: Row(
            children: [
              _TrustMarqueeGroup(items: items),
              _TrustMarqueeGroup(items: items, duplicate: true),
            ],
          ),
        ),
      ),
    );
  }

  double _estimateGroupWidth(List<_TrustMarqueeItemData> items) {
    var width = 32.0;
    for (final item in items) {
      final painter = TextPainter(
        text: TextSpan(text: item.text, style: _textStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      width += 15 + 6 + painter.width + (item.showLinkIcon ? 16 : 0);
      width += 10 + 3 + 14;
    }
    return width;
  }
}

class _TrustMarqueeGroup extends StatelessWidget {
  final List<_TrustMarqueeItemData> items;
  final bool duplicate;

  const _TrustMarqueeGroup({
    required this.items,
    this.duplicate = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      hidden: duplicate,
      child: Row(
        children: [
          const SizedBox(width: 16),
          for (final item in items) ...[
            _TrustMarqueeItem(item: item),
            const SizedBox(width: 10),
            const _TrustDot(),
            const SizedBox(width: 14),
          ],
        ],
      ),
    );
  }
}

class _TrustMarqueeItem extends StatelessWidget {
  final _TrustMarqueeItemData item;

  const _TrustMarqueeItem({required this.item});

  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(item.icon, color: item.iconColor, size: 15),
        const SizedBox(width: 6),
        Text(
          item.text,
          maxLines: 1,
          style: _TrustMarqueeState._textStyle.copyWith(
            decoration: item.onTap == null ? null : TextDecoration.underline,
            decorationColor: const Color(0xFF9CA3AF),
            decorationStyle: TextDecorationStyle.dotted,
          ),
        ),
        if (item.showLinkIcon) ...[
          const SizedBox(width: 4),
          const Icon(
            Icons.open_in_new_rounded,
            color: Color(0xFF9CA3AF),
            size: 12,
          ),
        ],
      ],
    );

    final onTap = item.onTap;
    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: content,
      ),
    );
  }
}

class _TrustMarqueeItemData {
  final IconData icon;
  final Color iconColor;
  final String text;
  final VoidCallback? onTap;
  final bool showLinkIcon;

  const _TrustMarqueeItemData({
    required this.icon,
    required this.iconColor,
    required this.text,
    this.onTap,
    this.showLinkIcon = false,
  });
}

class _TrustDot extends StatelessWidget {
  const _TrustDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 3,
      height: 3,
      decoration: const BoxDecoration(
        color: Color(0xFFE5E7EB),
        shape: BoxShape.circle,
      ),
    );
  }
}

class _HeroBanner extends StatefulWidget {
  /// Banner dari API. Kalau kosong, fallback ke hardcoded asset lokal supaya
  /// UI tidak kosong saat first render / offline.
  final List<HomeBanner> banners;

  const _HeroBanner({required this.banners});

  @override
  State<_HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends State<_HeroBanner> {
  /// Fallback banner asset lokal — dipakai saat API banner kosong.
  /// Match heroSlides.ts di PWA secara konseptual (image-only).
  static const _fallbackBanners = [
    _LocalBanner(
        image: 'assets/banners/happy-dog.jpg',
        href: '/products?kategori=anjing'),
    _LocalBanner(
        image: 'assets/banners/bersinar-aquarium.jpeg',
        href: '/products?kategori=ikan'),
    _LocalBanner(
        image: 'assets/banners/instant-max-3-jam.jpg', href: '/products'),
    _LocalBanner(
        image: 'assets/banners/member-benefit.png', href: '/member/register'),
  ];

  late final PageController _controller;
  Timer? _timer;
  int _index = 0;

  int get _count => widget.banners.isNotEmpty
      ? widget.banners.length
      : _fallbackBanners.length;

  bool get _useApi => widget.banners.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_controller.hasClients || !mounted) return;
      final total = _count;
      if (total <= 1) return;
      final next = (_index + 1) % total;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 460),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onTap(String? href) {
    if (href == null || href.isEmpty) return;
    // Parse href ke route — pattern ringkas, deep link service untuk
    // case kompleks. Mayoritas href: /products?kategori=X atau /member/X.
    final uri = Uri.tryParse(href);
    if (uri == null) return;
    final path = uri.path;
    if (path.startsWith('/products')) {
      Navigator.pushNamed(
        context,
        '/products',
        arguments: ProductCatalogArgs(
          initialCategory: uri.queryParameters['kategori'],
          initialQuery: uri.queryParameters['q'],
          selectedBrand: uri.queryParameters['brand'],
        ),
      );
    } else if (path == '/member' || path.startsWith('/member/')) {
      Navigator.pushNamed(context, path);
    } else if (path == '/feed') {
      Navigator.pushNamed(context, '/feed');
    } else if (path == '/cart') {
      Navigator.pushNamed(context, '/cart');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Banner spec revisi:
    // - Horizontal padding 8 (sebelumnya 16 → bikin banner terlihat
    //   seperti card kecil di tengah)
    // - AspectRatio 16:7 responsive (sebelumnya fixed height 184px
    //   yang tidak adaptive ke screen width)
    // - Border radius 12 (sebelumnya 26 → terlalu rounded, looks
    //   card-y. Spec rekomendasi 10-14)
    // - Hapus white border + soften shadow (sebelumnya tampak card)
    // - viewportFraction default 1.0 (PageController tanpa argumen)
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 0),
      child: AspectRatio(
        aspectRatio: 16 / 7,
        child: Stack(
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: _count,
              onPageChanged: (value) => setState(() => _index = value),
              itemBuilder: (context, index) {
                if (_useApi) {
                  final banner = widget.banners[index];
                  return _BannerSlide(
                    imageUrl: banner.imageUrl,
                    alt: banner.imageAlt,
                    onTap: () => _onTap(banner.href),
                    isNetwork: true,
                  );
                }
                final fallback = _fallbackBanners[index];
                return _BannerSlide(
                  imageUrl: fallback.image,
                  alt: '',
                  onTap: () => _onTap(fallback.href),
                  isNetwork: false,
                );
              },
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 12,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_count, (dotIndex) {
                  final active = dotIndex == _index;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    height: 6,
                    width: active ? 18 : 6,
                    decoration: BoxDecoration(
                      color: active
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.46),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BannerSlide extends StatelessWidget {
  final String imageUrl;
  final String alt;
  final bool isNetwork;
  final VoidCallback onTap;

  const _BannerSlide({
    required this.imageUrl,
    required this.alt,
    required this.onTap,
    required this.isNetwork,
  });

  @override
  Widget build(BuildContext context) {
    // Banner slide revisi — clean rounded image tanpa card styling:
    // - Margin antar-slide DIHAPUS (sebelumnya 1px bikin sliver gap)
    // - White border DIHAPUS (bikin tampak card)
    // - Heavy shadow REDUCED (subtle hint depth, bukan card-y)
    // - Border radius 12 (match parent AspectRatio shape, kecil/halus)
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFFEAF5FF),
          ),
          child: isNetwork
              ? CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  fadeInDuration: const Duration(milliseconds: 220),
                  placeholder: (context, url) => Container(
                    color: const Color(0xFFEAF5FF),
                    alignment: Alignment.center,
                    child: const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    color: const Color(0xFFEAF5FF),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.image_outlined,
                      color: Color(0xFF93C5FD),
                      size: 48,
                    ),
                  ),
                )
              : Image.asset(
                  imageUrl,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  errorBuilder: (_, __, ___) => Container(
                    color: const Color(0xFFEAF5FF),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.image_outlined,
                      color: Color(0xFF93C5FD),
                      size: 48,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _LocalBanner {
  final String image;
  final String href;

  const _LocalBanner({required this.image, required this.href});
}

class _ShortcutGrid extends StatelessWidget {
  final VoidCallback onOpenProducts;

  const _ShortcutGrid({required this.onOpenProducts});

  @override
  Widget build(BuildContext context) {
    // Hybrid 4×2 grid: row 1 = pet kategori utama (Makanan Kucing/Anjing/
    // Pasir/Vitamin), row 2 = commerce shortcut (Voucher/Tukar Poin/
    // Grooming/Blog). Search intent + reward CTA dalam satu grid.
    // Pet category tap → ProductsScreen filtered by category name.
    final items = <_ShortcutItem>[
      // ── Row 1: Pet category (drive product discovery) ──
      _ShortcutItem(
        Icons.pets_rounded,
        'Makanan Kucing',
        const Color(0xFFEAF5FF),
        const Color(0xFF0B7FEA),
        onTap: (ctx) => Navigator.pushNamed(
          ctx,
          '/products',
          arguments:
              const ProductCatalogArgs(initialCategory: 'Makanan Kucing'),
        ),
      ),
      _ShortcutItem(
        Icons.cruelty_free_rounded,
        'Makanan Anjing',
        const Color(0xFFFFFBEB),
        const Color(0xFFF59E0B),
        onTap: (ctx) => Navigator.pushNamed(
          ctx,
          '/products',
          arguments:
              const ProductCatalogArgs(initialCategory: 'Makanan Anjing'),
        ),
      ),
      _ShortcutItem(
        Icons.inventory_2_rounded,
        'Pasir',
        const Color(0xFFF1F5F9),
        const Color(0xFF475569),
        onTap: (ctx) => Navigator.pushNamed(
          ctx,
          '/products',
          arguments: const ProductCatalogArgs(initialCategory: 'Pasir Kucing'),
        ),
      ),
      _ShortcutItem(
        Icons.medication_liquid_rounded,
        'Vitamin',
        const Color(0xFFFEF2F2),
        const Color(0xFFEF4444),
        onTap: (ctx) => Navigator.pushNamed(
          ctx,
          '/products',
          arguments: const ProductCatalogArgs(initialCategory: 'Vitamin'),
        ),
      ),
      // ── Row 2: Commerce shortcuts (drive engagement + reward) ──
      _ShortcutItem(
        Icons.local_offer_rounded,
        'Voucher',
        const Color(0xFFFDF2F8),
        const Color(0xFFDB2777),
        onTap: (ctx) => Navigator.pushNamed(ctx, '/member/vouchers'),
      ),
      _ShortcutItem(
        Icons.stars_rounded,
        'Tukar Poin',
        const Color(0xFFFFF7ED),
        const Color(0xFFEA580C),
        onTap: (ctx) => Navigator.pushNamed(ctx, '/member/loyalty'),
      ),
      const _ShortcutItem(
          Icons.spa_rounded, 'Grooming', Color(0xFFECFDF5), Color(0xFF16A34A)),
      const _ShortcutItem(
        Icons.menu_book_rounded,
        'Blog & Tips',
        Color(0xFFFEFCE8),
        Color(0xFFCA8A04),
        onTap: AppInAppBrowser.openBlog,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: items.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 10,
          crossAxisSpacing: 8,
          mainAxisExtent: 92,
        ),
        itemBuilder: (context, index) {
          final item = items[index];
          return InkWell(
            onTap: () {
              if (item.onTap != null) {
                item.onTap!(context);
              } else {
                onOpenProducts();
              }
            },
            borderRadius: BorderRadius.circular(18),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  height: 50,
                  width: 50,
                  decoration: BoxDecoration(
                    color: item.background,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(item.icon, color: item.color, size: 26),
                ),
                const SizedBox(height: 6),
                Text(
                  item.label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF3F3F46),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    height: 1.12,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FlashSaleGrid extends StatelessWidget {
  final List<Product> products;
  final ValueChanged<Product> onTap;
  final VoidCallback onSeeAll;
  final VoidCallback? onCountdownExpired;

  static const _maxVisible = 6;

  const _FlashSaleGrid({
    required this.products,
    required this.onTap,
    required this.onSeeAll,
    this.onCountdownExpired,
  });

  /// Cari endsAt paling awal dari produk yang punya explicit
  /// flashSaleEndsAt (Tier 1). Section header pakai timer ini sebagai
  /// urgency cue. Kalau tidak ada produk Tier 1, return null (header
  /// tampil tanpa countdown).
  DateTime? get _earliestEndsAt {
    DateTime? earliest;
    for (final p in products) {
      final ends = p.flashSaleEndsAt;
      if (ends == null) continue;
      if (earliest == null || ends.isBefore(earliest)) {
        earliest = ends;
      }
    }
    return earliest;
  }

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) return const SizedBox.shrink();

    final visible = products.take(_maxVisible).toList();
    final hasMore = products.length > _maxVisible;
    final endsAt = _earliestEndsAt;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '⚡ Flash Sale',
                      style: TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Diskon Spesial dari Natalo Petshop',
                      style: TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (hasMore)
                GestureDetector(
                  onTap: onSeeAll,
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                    child: Text(
                      'Lihat semua',
                      style: TextStyle(
                        color: _brandBlue,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          // Countdown timer bar — hanya tampil kalau ada produk Tier 1
          // (explicit flashSaleEndsAt). Tier 2 (auto-include via 20%
          // threshold) tidak pakai countdown.
          if (endsAt != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: FlashSaleCountdown(
                endsAt: endsAt,
                onExpired: onCountdownExpired,
              ),
            ),
          ],
          const SizedBox(height: 12),
          GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            itemCount: visible.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              // 0.62 → 0.56: cell sedikit lebih tinggi (~+8px) supaya text
              // section (title 32px + price + strikethrough optional) tidak
              // overflow di card produk dengan diskon. Saat ada strikethrough,
              // sebelumnya overflow ~4.6px.
              childAspectRatio: 0.56,
            ),
            itemBuilder: (context, index) {
              final product = visible[index];
              return _FlashSaleCard(
                product: product,
                onTap: () => onTap(product),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FlashSaleCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;

  const _FlashSaleCard({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final discountPercent = _activeHomeProductDiscountPercent(product);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x08000000),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  _HomeProductImage(
                    imageUrl: product.imageUrl,
                    height: 92,
                  ),
                  if (discountPercent != null)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: _HomeProductDiscountBadge(
                        percent: discountPercent,
                        compact: true,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 7),
              SizedBox(
                height: 27,
                child: Text(
                  product.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.8,
                    height: 1.18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              _FlashSalePriceBlock(product: product),
              _FlashSaleRatingSoldRow(product: product),
            ],
          ),
        ),
      ),
    );
  }
}

class _FlashSalePriceBlock extends StatelessWidget {
  final Product product;

  const _FlashSalePriceBlock({required this.product});

  @override
  Widget build(BuildContext context) {
    if (!product.hasDiscount) {
      return Text(
        formatRupiah(product.finalPrice),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 13,
          height: 1.05,
          fontWeight: FontWeight.w900,
          color: Color(0xFF111827),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          formatRupiah(product.price),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 9.5,
            height: 1,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
            decoration: TextDecoration.lineThrough,
            decorationThickness: 1.4,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          formatRupiah(product.finalPrice),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 13.5,
            height: 1.05,
            fontWeight: FontWeight.w900,
            color: Color(0xFFE11D48),
          ),
        ),
      ],
    );
  }
}

class _FlashSaleRatingSoldRow extends StatelessWidget {
  final Product product;

  const _FlashSaleRatingSoldRow({required this.product});

  @override
  Widget build(BuildContext context) {
    final hasRating = product.rating > 0;
    final hasSold = product.soldCount > 0;
    if (!hasRating && !hasSold) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          if (hasRating) ...[
            const Icon(
              Icons.star_rounded,
              size: 12,
              color: Color(0xFFFACC15),
            ),
            const SizedBox(width: 3),
            Text(
              product.rating.toStringAsFixed(1),
              style: const TextStyle(
                fontSize: 10.2,
                height: 1,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111827),
              ),
            ),
          ],
          if (hasRating && hasSold) ...[
            const SizedBox(width: 4),
            const Text(
              '•',
              style: TextStyle(
                fontSize: 10.2,
                height: 1,
                color: Color(0xFF9CA3AF),
              ),
            ),
            const SizedBox(width: 4),
          ],
          if (hasSold)
            Flexible(
              child: Text(
                '${_formatHomeProductSoldCount(product.soldCount)} terjual',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10.2,
                  height: 1,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF6B7280),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HomeProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;
  final int? rank;
  final double? width;
  final double imageHeight;
  final double priceFontSize;
  final bool compact;

  const _HomeProductCard({
    required this.product,
    required this.onTap,
    this.rank,
    this.width,
    this.imageHeight = 132,
    this.priceFontSize = 16,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final padding = compact ? 8.0 : 10.0;
    final nameHeight = compact ? 31.0 : 34.0;
    final discountPercent = _activeHomeProductDiscountPercent(product);

    return SizedBox(
      width: width,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.all(padding),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE5E7EB)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x08000000),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    _HomeProductImage(
                      imageUrl: product.imageUrl,
                      height: imageHeight,
                    ),
                    if (discountPercent != null)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: _HomeProductDiscountBadge(
                          percent: discountPercent,
                          compact: compact,
                        ),
                      ),
                    if (rank != null)
                      Positioned(
                        left: 8,
                        top: 8,
                        child: _HomeProductRankBadge(rank: rank!),
                      ),
                  ],
                ),
                SizedBox(height: compact ? 8 : 10),
                SizedBox(
                  height: nameHeight,
                  child: Text(
                    product.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111827),
                    ),
                  ),
                ),
                // Consumable repurchase badge — produk yang user pernah
                // beli dan sudah waktunya refill (food, pasir, vitamin, dst).
                if (product.isRepurchaseCandidate) ...[
                  SizedBox(height: compact ? 6 : 7),
                  _HomeProductRepurchaseBadge(product: product),
                ],
                SizedBox(height: compact ? 7 : 8),
                _HomeProductPriceRow(
                  product: product,
                  fontSize: priceFontSize,
                  compact: compact,
                ),
                _HomeProductSavingBadge(product: product, compact: compact),
                _HomeProductRatingSoldRow(product: product, compact: compact),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeProductImage extends StatelessWidget {
  final String imageUrl;
  final double height;

  const _HomeProductImage({
    required this.imageUrl,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl.trim().isNotEmpty;
    if (!hasImage) {
      return _HomeProductImagePlaceholder(height: height);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        height: height,
        width: double.infinity,
        fit: BoxFit.contain,
        placeholder: (_, __) => _HomeProductImagePlaceholder(height: height),
        errorWidget: (_, __, ___) => _HomeProductImagePlaceholder(
          height: height,
        ),
      ),
    );
  }
}

class _HomeProductImagePlaceholder extends StatelessWidget {
  final double height;

  const _HomeProductImagePlaceholder({required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF3F7FF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Center(
        child: Icon(
          Icons.pets_rounded,
          size: 34,
          color: Color(0xFF94A3B8),
        ),
      ),
    );
  }
}

class _HomeProductRankBadge extends StatelessWidget {
  final int rank;

  const _HomeProductRankBadge({required this.rank});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 12,
      backgroundColor: rank == 1
          ? const Color(0xFFF59E0B)
          : rank == 2
              ? const Color(0xFF94A3B8)
              : _brandBlue,
      child: Text(
        '$rank',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}

class _HomeProductPriceRow extends StatelessWidget {
  final Product product;
  final double fontSize;
  final bool compact;

  const _HomeProductPriceRow({
    required this.product,
    required this.fontSize,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    if (!product.hasDiscount) {
      return Text(
        formatRupiah(product.finalPrice),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          color: const Color(0xFF111827),
          height: 1.1,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          formatRupiah(product.price),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: compact ? fontSize - 2 : fontSize - 3,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF111827),
            height: 1.05,
            decoration: TextDecoration.lineThrough,
            decorationThickness: 1.5,
          ),
        ),
        SizedBox(height: compact ? 2 : 3),
        Text(
          formatRupiah(product.finalPrice),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: compact ? fontSize : fontSize + 1,
            fontWeight: FontWeight.w900,
            color: const Color(0xFFE11D48),
            height: 1.05,
          ),
        ),
      ],
    );
  }
}

class _HomeProductSavingBadge extends StatelessWidget {
  final Product product;
  final bool compact;

  const _HomeProductSavingBadge({
    required this.product,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final savingLabel = _homeProductSavingLabel(product);
    final shippingLabel = _homeProductShippingLabel(product);
    final badges = <Widget>[
      if (shippingLabel != null)
        _HomeProductPromoBadge(
          label: shippingLabel,
          compact: compact,
          icon: Icons.local_shipping_rounded,
          color: const Color(0xFF16A34A),
          backgroundColor: const Color(0xFFECFDF3),
          borderColor: const Color(0xFFA7F3D0),
        ),
      if (savingLabel != null)
        _HomeProductPromoBadge(
          label: savingLabel,
          compact: compact,
          icon: Icons.confirmation_number_rounded,
          color: const Color(0xFFEF4444),
          backgroundColor: const Color(0xFFFFF1F2),
          borderColor: const Color(0xFFFCA5A5),
        ),
    ];

    if (badges.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(top: compact ? 5 : 6),
      child: Wrap(
        spacing: compact ? 4 : 6,
        runSpacing: 4,
        children: badges,
      ),
    );
  }
}

class _HomeProductPromoBadge extends StatelessWidget {
  final String label;
  final bool compact;
  final IconData icon;
  final Color color;
  final Color backgroundColor;
  final Color borderColor;

  const _HomeProductPromoBadge({
    required this.label,
    required this.compact,
    required this.icon,
    required this.color,
    required this.backgroundColor,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: double.infinity),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: compact ? 11 : 13,
            color: color,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 9.5 : 11,
                fontWeight: FontWeight.w700,
                color: color,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeProductRatingSoldRow extends StatelessWidget {
  final Product product;
  final bool compact;

  const _HomeProductRatingSoldRow({
    required this.product,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final hasRating = product.rating > 0;
    final hasSold = product.soldCount > 0;
    if (!hasRating && !hasSold) return const SizedBox.shrink();

    final textSize = compact ? 10.2 : 11.0;

    return Padding(
      padding: EdgeInsets.only(top: compact ? 6 : 7),
      child: Row(
        children: [
          if (hasRating) ...[
            Icon(
              Icons.star_rounded,
              size: compact ? 12 : 14,
              color: const Color(0xFFFACC15),
            ),
            const SizedBox(width: 3),
            Text(
              product.rating.toStringAsFixed(1),
              style: TextStyle(
                fontSize: textSize,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF4B5563),
                height: 1,
              ),
            ),
          ],
          if (hasRating && hasSold) ...[
            const SizedBox(width: 5),
            Text(
              '•',
              style: TextStyle(
                fontSize: textSize,
                color: const Color(0xFF9CA3AF),
                height: 1,
              ),
            ),
            const SizedBox(width: 5),
          ],
          if (hasSold)
            Flexible(
              child: Text(
                '${_formatHomeProductSoldCount(product.soldCount)} terjual',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: textSize,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF4B5563),
                  height: 1,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String? _homeProductSavingLabel(Product product) {
  final voucher = product.voucherPreview;
  final voucherSaving = voucher?.savingAmount ?? voucher?.discountAmount;
  if (voucherSaving != null && voucherSaving > 0) {
    return 'Hemat s.d. ${formatRupiah(voucherSaving)}';
  }

  final voucherPercent = voucher?.discountPercent;
  if (voucherPercent != null && voucherPercent > 0) {
    return 'Hemat s.d. ${voucherPercent.round()}%';
  }

  if (!product.hasDiscount) return null;
  final savings = product.price - product.finalPrice;
  if (savings <= 0) return null;
  return 'Hemat s.d. ${formatRupiah(savings)}';
}

String? _homeProductShippingLabel(Product product) {
  final voucher = product.shippingVoucherPreview;
  if (voucher == null) return null;
  final label = voucher.badgeLabel.trim();
  return label.isNotEmpty ? label : 'Gratis Ongkir';
}

String _formatHomeProductSoldCount(int count) {
  if (count >= 1000) {
    final value = count / 1000;
    final text =
        value >= 10 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
    return '${text.replaceAll('.', ',').replaceAll(',0', '')}rb+';
  }
  if (count >= 100) return '${(count ~/ 50) * 50}+';
  return count.toString();
}

int? _activeHomeProductDiscountPercent(Product product) {
  final discount = product.discountPrice;
  if (discount == null || discount <= 0 || product.price <= 0) return null;
  if (discount >= product.price) return null;

  final endsAt = product.flashSaleEndsAt;
  if (endsAt != null && !endsAt.isAfter(DateTime.now())) return null;

  return (((product.price - discount) / product.price) * 100).round();
}

/// Badge "Saatnya beli ulang" untuk produk consumable yang sudah masuk
/// siklus refill (food, pasir, vitamin, dst).
///
/// Color palette: amber/yellow-warm (Color(0xFFD97706) text di soft
/// background Color(0xFFFFF7E6)) — beda dari diskon red supaya tidak
/// kontradiktif. Icon `autorenew_rounded` = repeat purchase metaphor.
class _HomeProductRepurchaseBadge extends StatelessWidget {
  final Product product;

  const _HomeProductRepurchaseBadge({required this.product});

  @override
  Widget build(BuildContext context) {
    final isOverdue = product.repurchaseReason == 'refill_overdue';
    final label = isOverdue ? 'Sudah lama tidak beli' : 'Saatnya beli ulang';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E6),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFFDE68A), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.autorenew_rounded,
            size: 11,
            color: Color(0xFFD97706),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFD97706),
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                height: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeProductDiscountBadge extends StatelessWidget {
  final int? percent;
  final bool compact;

  const _HomeProductDiscountBadge({
    required this.percent,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final value = percent;
    if (value == null || value <= 0) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFE11D48),
        borderRadius: BorderRadius.circular(compact ? 9 : 10),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        '-$value%',
        style: TextStyle(
          color: Colors.white,
          fontSize: compact ? 10.5 : 12,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}

class _HorizontalProductSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Product> products;
  final bool showRank;
  final ValueChanged<Product> onTap;

  const _HorizontalProductSection({
    required this.title,
    required this.subtitle,
    required this.products,
    required this.onTap,
    this.showRank = false,
  });

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Color(0xFF111827),
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pushNamed(context, '/products'),
                  child: const Text('Lihat semua'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 260,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: products.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final product = products[index];
                return _MiniProductCard(
                  product: product,
                  rank: showRank ? index + 1 : null,
                  onTap: () => onTap(product),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniProductCard extends StatelessWidget {
  final Product product;
  final int? rank;
  final VoidCallback onTap;

  const _MiniProductCard({
    required this.product,
    required this.onTap,
    this.rank,
  });

  @override
  Widget build(BuildContext context) {
    return _HomeProductCard(
      product: product,
      onTap: onTap,
      rank: rank,
      width: 150,
      imageHeight: 112,
      priceFontSize: 14,
      compact: true,
    );
  }
}

/// Brand Favorit — 2×3 grid carousel dengan auto-slide.
///
/// Layout:
/// - Max 6 brand per halaman (2 baris × 3 kolom)
/// - Multi-page kalau brands > 6 (mis. 7-12 = 2 halaman, dst.)
/// - Auto-slide setiap 3 detik, durasi 400ms easeOutCubic
/// - Auto-slide CUMA aktif kalau halaman > 1
/// - User swipe manual → timer di-reset (tidak overlap)
/// - TIDAK ada indicator dots (sesuai spec)
/// - Empty state → hidden (parent guard juga)
class _BrandChoiceSection extends StatefulWidget {
  final List<PetBrand> brands;
  final ValueChanged<PetBrand> onTap;

  const _BrandChoiceSection({required this.brands, required this.onTap});

  @override
  State<_BrandChoiceSection> createState() => _BrandChoiceSectionState();
}

class _BrandChoiceSectionState extends State<_BrandChoiceSection> {
  static const int _itemsPerPage = 6; // 2 rows × 3 cols
  static const Duration _autoSlideInterval = Duration(seconds: 3);
  static const Duration _animDuration = Duration(milliseconds: 400);

  late PageController _pageCtrl;
  Timer? _autoSlideTimer;
  int _currentPage = 0;
  late List<List<PetBrand>> _pages;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
    _pages = _chunkBrands(widget.brands);
    _maybeStartAutoSlide();
  }

  @override
  void didUpdateWidget(covariant _BrandChoiceSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Brand list bisa berubah saat API refresh — re-chunk + restart timer.
    if (oldWidget.brands.length != widget.brands.length ||
        !_sameBrandIds(oldWidget.brands, widget.brands)) {
      setState(() {
        _pages = _chunkBrands(widget.brands);
        _currentPage = _currentPage.clamp(0, _pages.length - 1);
      });
      if (_pageCtrl.hasClients) {
        _pageCtrl.jumpToPage(_currentPage);
      }
      _maybeStartAutoSlide();
    }
  }

  bool _sameBrandIds(List<PetBrand> a, List<PetBrand> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].name != b[i].name) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _autoSlideTimer?.cancel();
    _pageCtrl.dispose();
    super.dispose();
  }

  List<List<PetBrand>> _chunkBrands(List<PetBrand> brands) {
    final pages = <List<PetBrand>>[];
    for (var i = 0; i < brands.length; i += _itemsPerPage) {
      final end = (i + _itemsPerPage) < brands.length
          ? (i + _itemsPerPage)
          : brands.length;
      pages.add(brands.sublist(i, end));
    }
    return pages;
  }

  /// Start/restart auto-slide timer. Cancel kalau pages ≤ 1.
  void _maybeStartAutoSlide() {
    _autoSlideTimer?.cancel();
    if (_pages.length <= 1) return;
    _autoSlideTimer = Timer.periodic(_autoSlideInterval, (_) {
      if (!mounted || !_pageCtrl.hasClients) return;
      final nextPage = (_currentPage + 1) % _pages.length;
      _pageCtrl.animateToPage(
        nextPage,
        duration: _animDuration,
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _handlePageChanged(int index) {
    _currentPage = index;
    // Reset timer setiap page change (baik auto-slide atau user swipe).
    // Effect: user swipe manual → timer ulang 3 detik, tidak konflik.
    _maybeStartAutoSlide();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.brands.isEmpty || _pages.isEmpty) {
      return const SizedBox.shrink();
    }

    // Compute card height dari aspect ratio + screen width
    // (childAspectRatio: 1.45 = width/height).
    final screenWidth = MediaQuery.sizeOf(context).width;
    final innerWidth = screenWidth - 32; // 16 padding × 2
    final cardWidth = (innerWidth - 24) / 3; // 12 spacing × 2 between 3 cols
    final cardHeight = cardWidth / 1.45;
    final gridHeight = (cardHeight * 2) + 12; // 2 rows + mainAxisSpacing

    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Brand Favorit',
                    style: TextStyle(
                      color: Color(0xFF111827),
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pushNamed(context, '/brands'),
                  child: const Text('Lihat semua'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: gridHeight,
            child: PageView.builder(
              controller: _pageCtrl,
              itemCount: _pages.length,
              onPageChanged: _handlePageChanged,
              itemBuilder: (context, pageIndex) {
                final pageBrands = _pages[pageIndex];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    shrinkWrap: true,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.45,
                    ),
                    itemCount: pageBrands.length,
                    itemBuilder: (context, idx) {
                      final brand = pageBrands[idx];
                      return _BrandGridCard(
                        brand: brand,
                        onTap: () => widget.onTap(brand),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact brand card untuk 2×3 grid carousel.
/// Pertahankan visual style Natalo (white bg, soft border, soft shadow).
class _BrandGridCard extends StatelessWidget {
  final PetBrand brand;
  final VoidCallback onTap;

  const _BrandGridCard({required this.brand, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.025),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                flex: 5,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: _BrandLogoImage(brand: brand),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                brand.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrandLogoImage extends StatelessWidget {
  final PetBrand brand;

  const _BrandLogoImage({required this.brand});

  @override
  Widget build(BuildContext context) {
    // 1) Logo URL dari API → cached network image (PWA brand)
    final logoUrl = brand.logoUrl;
    if (logoUrl != null && logoUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: logoUrl,
        fit: BoxFit.contain,
        fadeInDuration: const Duration(milliseconds: 180),
        placeholder: (context, url) => const Center(
          child: SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        errorWidget: (context, url, error) => _BrandInitial(brand: brand),
      );
    }
    // 2) Image asset lokal (sampleBrands fallback)
    final imageAsset = brand.imageAsset;
    if (imageAsset != null) {
      return Image.asset(
        imageAsset,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) =>
            _BrandInitial(brand: brand),
      );
    }
    // 3) Fallback: inisial huruf
    return _BrandInitial(brand: brand);
  }
}

class _BrandInitial extends StatelessWidget {
  final PetBrand brand;

  const _BrandInitial({required this.brand});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        brand.name.isEmpty ? '?' : brand.name[0],
        style: TextStyle(
          color: brand.color,
          fontSize: 22,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

/// Kategori Populer — horizontal cards 148w dengan icon + nama,
/// sorted by product count (kategori dengan produk paling banyak dulu).
/// Pattern reference: clean, compact, fokus discovery.
class _CategorySection extends StatelessWidget {
  /// Kategori dari API (kosong = belum loaded). Saat kosong, section
  /// di-hide sama sekali — bukan tampil fallback hardcoded — supaya UI
  /// tidak misleading. PWA juga skip section ini kalau API return [].
  final List<HomeCategory> categories;
  final ValueChanged<String> onTap;

  const _CategorySection({
    required this.categories,
    required this.onTap,
  });

  // Map nama kategori → icon yang relevan. Fallback ke generic store icon.
  static IconData _iconFor(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('kucing') && lower.contains('makanan')) {
      return Icons.pets_rounded;
    }
    if (lower.contains('anjing') && lower.contains('makanan')) {
      return Icons.cruelty_free_rounded;
    }
    if (lower.contains('pasir') || lower.contains('litter')) {
      return Icons.inventory_2_rounded;
    }
    if (lower.contains('vitamin') || lower.contains('obat')) {
      return Icons.medication_liquid_rounded;
    }
    if (lower.contains('snack') || lower.contains('treat')) {
      return Icons.cookie_rounded;
    }
    if (lower.contains('mainan') || lower.contains('toy')) {
      return Icons.toys_rounded;
    }
    if (lower.contains('kandang') || lower.contains('cage')) {
      return Icons.home_rounded;
    }
    if (lower.contains('shampoo') || lower.contains('grooming')) {
      return Icons.spa_rounded;
    }
    if (lower.contains('burung') || lower.contains('bird')) {
      return Icons.flutter_dash_rounded;
    }
    if (lower.contains('ikan') || lower.contains('fish')) {
      return Icons.water_rounded;
    }
    return Icons.storefront_rounded;
  }

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) return const SizedBox.shrink();

    // Sort by productCount desc — kategori paling banyak produk tampil dulu.
    final sorted = [...categories]
      ..sort((a, b) => b.productCount.compareTo(a.productCount));
    final visible = sorted.take(8).toList();

    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Kategori Populer',
                    style: TextStyle(
                      color: Color(0xFF17202A),
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pushNamed(context, '/products'),
                  child: const Text('Lihat semua'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 68,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: visible.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final category = visible[index];
                return _PopularCategoryCard(
                  category: category,
                  icon: _iconFor(category.name),
                  onTap: () => onTap(category.name),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact horizontal category card — 148w row dengan icon + nama.
/// Pattern reference Anda: icon di kotak primaryLight, nama di samping.
class _PopularCategoryCard extends StatelessWidget {
  final HomeCategory category;
  final IconData icon;
  final VoidCallback onTap;

  const _PopularCategoryCard({
    required this.category,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 168,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF5FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  color: const Color(0xFF0B7FEA),
                  size: 23,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  category.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF17202A),
                    fontSize: 13,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
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

// _CategoryCard + _CategoryFallback dihapus — diganti dengan
// _PopularCategoryCard (icon + name horizontal row) di atas.

class _RecommendationGrid extends StatelessWidget {
  final List<Product> products;
  final ValueChanged<Product> onTap;

  const _RecommendationGrid({
    required this.products,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Rekomendasi Untuk Kamu',
            style: TextStyle(
              color: Color(0xFF111827),
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            itemCount: products.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              // Lebih tinggi untuk metadata hemat + rating/terjual.
              childAspectRatio: 0.54,
            ),
            itemBuilder: (context, index) {
              final product = products[index];
              return _HomeProductCard(
                product: product,
                onTap: () => onTap(product),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ShortcutItem {
  final IconData icon;
  final String label;
  final Color background;
  final Color color;
  // Optional per-item handler. Kalau null, _ShortcutGrid pakai default
  // (onOpenProducts). Pattern ini supaya tiap shortcut bisa navigate ke
  // destination berbeda tanpa harus refactor grid widget.
  final void Function(BuildContext context)? onTap;

  const _ShortcutItem(
    this.icon,
    this.label,
    this.background,
    this.color, {
    this.onTap,
  });
}

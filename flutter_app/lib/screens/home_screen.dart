import 'dart:async';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

// sample_brands + sample_products dihapus dari import — Home screen sekarang
// pure API-driven. Brand/produk yang muncul = data live dari Capacitor
// admin dashboard via Next.js API. Loading state pakai skeleton, empty
// state pakai widget dedicated.
import '../config/natalo_store_config.dart';
import '../models/brand.dart';
import '../models/home_banner.dart';
import '../models/home_category.dart';
import '../models/product.dart';
import '../services/app_analytics.dart';
import '../services/connectivity_service.dart';
import '../services/search_service.dart';
import '../services/product_service.dart';
import '../state/feed_upload_store.dart';
import '../state/recently_viewed_store.dart';
import '../state/search_history_store.dart';
import '../state/trending_placeholder_controller.dart';
import '../theme/natalo_colors.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import '../utils/in_app_browser.dart';
import '../widgets/app_cart_button.dart';
import '../widgets/app_chat_button.dart';
import '../widgets/app_notification_button.dart';
import '../widgets/app_product_image.dart';
import '../widgets/collapsing_header_delegate.dart';
import '../widgets/brand_exclusive_badge.dart';
import '../widgets/app_ui.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/flash_sale_countdown.dart';
import '../widgets/glass_surface.dart';
import '../widgets/natalo_paw_refresh_indicator.dart';
import '../features/feed/widgets/feed_upload_bar.dart';
import '../widgets/product_grid_video.dart';
import 'home_search_page.dart';
import '../widgets/skeleton_product_card.dart';
import 'package:shimmer/shimmer.dart';

const _brandBlue = NataloColors.nataloBlue;

// ── Hero biru beranda (redesign Jul 2026) ──
// Gradasi header: navy pekat → brand blue. Marquee strip meneruskan
// gradasi ke bawah supaya header+marquee terbaca sebagai SATU blok hero.
// Nilai asli dipindah ke NataloColors.hero* supaya halaman lain (Belanja,
// Transaksi, Akun, Notifikasi) pakai sumber yang sama; alias lokal
// dipertahankan agar referensi di file ini tidak berubah.
const _heroTop = NataloColors.heroTop;
const _heroMid = NataloColors.heroMid;
// Teks sekunder di atas biru (tagline, marquee) — biru muda lembut.
const _onHeroSubtle = NataloColors.onHeroSubtle;

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
  // ── Collapse header: engine 1:1 mengikuti jari (SAMA dengan halaman
  // Produk) — lihat CollapsingHeaderDelegate (pinned+floating+snap).
  // Lipatan digerakkan shrinkOffset native, jadi TIDAK ADA state/animation
  // controller header di sini lagi (model biner+histeresis lama dibalik atas
  // permintaan user setelah demo mockup). Listener scroll hanya untuk
  // paginasi explore.

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

  /// Brand untuk slider "Brand Favorit" di Home — HANYA brand yang punya
  /// logo gambar (admin upload). Brand tanpa logo (fallback huruf inisial)
  /// disembunyikan dari Home supaya rapi & profesional; tetap muncul di
  /// /brands "Lihat semua". TANPA cap jumlah — urutan diatur admin via
  /// position (API /api/brands orderBy position asc), jadi brand prioritas
  /// otomatis di slide depan. Sebelumnya di-cap take(12) → cuma 2 slide
  /// walau brand banyak.
  List<PetBrand> get _logoBrands => _brands
      .where((b) => b.logoUrl != null && b.logoUrl!.trim().isNotEmpty)
      .toList();

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

    // Cold-start resume check (Fase 2C-4) — bila ada upload feed yang
    // sempat jalan lalu app di-kill, tawarkan "Lanjutkan" di FeedUploadBar.
    // Post-frame supaya tidak block initState; idempotent (guard internal
    // di store sekali per proses).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(feedUploadStore.checkForResumableUpload());
    });

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
        // Ambil kandidat lebih banyak dari yang ditampilkan (10) supaya
        // rotasi harian di grid punya pool untuk digilir — lihat
        // `_dailyRotatingPick` di builder _RecommendationGrid.
        limit: 18,
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
    await Future.wait([_loadDynamicSections(), _initializeRecsAndExplore()]);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    recentlyViewedStore.removeListener(_onRecentlyViewedChanged);
    super.dispose();
  }

  void _onScroll() {
    // Collapse header di-handle NATIVE oleh sliver (pinned+floating) —
    // listener ini murni untuk paginasi explore.
    if (_exploreLoading || !_exploreHasMore) return;
    // Trigger load saat 600px sebelum bottom — match PWA threshold.
    if (!_scrollController.hasClients) return;
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
      precacheImage(CachedNetworkImageProvider(product.gallery.first), context);
    }
    Navigator.pushNamed(
      context,
      '/product-detail',
      arguments: product,
    ).whenComplete(_maybeRegenerateExploreAfterReturn);
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
    return _uniqueById([
      ...personalized,
      ...fallback,
      ...products,
    ]).take(10).toList();
  }

  List<Product> _fallbackRecommendations(List<Product> products) {
    final promoProducts = products.where((product) => product.hasDiscount);
    final popularProducts = [...products]
      ..sort((a, b) => b.reviewCount.compareTo(a.reviewCount));
    return _uniqueById([
      ...promoProducts,
      ...popularProducts,
      ...products,
    ]).take(10).toList();
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
        final scoreCompare = _exploreScore(
          b,
          brandScores,
          categoryScores,
        ).compareTo(_exploreScore(a, brandScores, categoryScores));
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

  // ── Rotasi harian rail "etalase" (Terlaris & Rekomendasi) ──
  //
  // Masalah: katalog Natalo relatif kecil → rail yang selalu ambil top-N
  // dengan urutan sama membuat Beranda terkesan "produknya itu-itu saja".
  // Solusi (client-only, tanpa ubah backend): gilir jendela produk kuat
  // pakai SEED HARIAN. Efeknya sama dengan rail "Jelajahi" (seed
  // generation): urutan STABIL sepanjang hari — user tidak disorientasi
  // saat scroll balik / buka-tutup app — lalu berganti sendiri tiap hari.
  //
  // Bukan pengacakan bohong: `pinned` teratas (juara sejati) SELALU tampil
  // dan seluruh kandidat berasal dari top-window yang memang kuat.

  /// Angka tanggal lokal (YYYYMMDD) — sama sepanjang hari, ganti tengah malam.
  int get _dailyRotationSeed {
    final now = DateTime.now();
    return now.year * 10000 + now.month * 100 + now.day;
  }

  /// Dari daftar `ranked` (sudah terurut, index kecil = paling kuat), ambil
  /// `count` produk dengan rotasi harian: `pinned` teratas SELALU tampil,
  /// sisanya dipilih bergilir tiap hari dari kandidat berikutnya. Hasil
  /// di-sort ulang mengikuti urutan `ranked` supaya nomor #1..#N monoton.
  List<Product> _dailyRotatingPick(
    List<Product> ranked, {
    required int pinned,
    required int count,
  }) {
    if (ranked.length <= count) return ranked.take(count).toList();
    final safePinned = pinned.clamp(0, count);
    final pinnedItems = ranked.take(safePinned).toList();
    final pool = ranked.sublist(safePinned);
    final need = count - pinnedItems.length;

    // Fisher-Yates ber-seed (LCG) — deterministik per hari, tanpa Random.
    final order = List<int>.generate(pool.length, (i) => i);
    var state = (_dailyRotationSeed & 0x7fffffff) | 1;
    for (var i = order.length - 1; i > 0; i -= 1) {
      state = (state * 1103515245 + 12345) & 0x7fffffff;
      final j = state % (i + 1);
      final tmp = order[i];
      order[i] = order[j];
      order[j] = tmp;
    }
    final picked = order.take(need).map((i) => pool[i]).toList();

    final chosen = <Product>[...pinnedItems, ...picked];
    final rankIndex = <String, int>{
      for (var i = 0; i < ranked.length; i += 1) ranked[i].id: i,
    };
    chosen.sort((a, b) =>
        (rankIndex[a.id] ?? 1 << 30).compareTo(rankIndex[b.id] ?? 1 << 30));
    return chosen;
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
      MaterialPageRoute(builder: (_) => const HomeSearchPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Latar seluruh Beranda abu muda (a la Shopee home) — SEMUA section jadi
      // kartu putih mengambang di atas abu, tak ada belang putih→abu di
      // tengah. Tile brand/kategori sudah Material(surface)=putih; grid
      // Rekomendasi/Jelajahi sudah putih; jadi cukup latar halaman jadi abu.
      backgroundColor: _homeGridSurfaceTint(context),
      // extendBody: konten memanjang ke belakang floating nav → frosted
      // glass nav punya konten untuk di-blur (efek kaca tembus). Grid/list
      // sudah kasih bottom padding untuk clear nav.
      extendBody: true,
      // SafeArea(top: true, bottom: false) — top handle status bar / notch /
      // camera punch-hole (Android). Bottom inset di-handle Scaffold
      // bottomNavigationBar slot, BUKAN SafeArea internal — supaya tidak
      // double padding di iPhone X+ (home indicator) atau Android gesture.
      //
      // Hero biru: strip setinggi status bar dicat _heroTop di BELAKANG
      // SafeArea (Stack layer bawah) supaya area notch menyatu dengan header
      // biru, bukan strip putih. AnnotatedRegion → ikon status bar putih
      // (hanya berlaku saat tab Beranda yang ter-paint di IndexedStack).
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: MediaQuery.paddingOf(context).top,
              child: const ColoredBox(color: _heroTop),
            ),
            SafeArea(
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
                  final rankedBySold = [...products]..sort((a, b) {
                      // Primary: soldCount desc (yang paling banyak terjual)
                      final byCount = b.soldCount.compareTo(a.soldCount);
                      if (byCount != 0) return byCount;
                      // Tie-break: reviewCount desc
                      return b.reviewCount.compareTo(a.reviewCount);
                    });
                  // Rotasi harian: 3 juara sejati tetap tampil, 5 slot lain
                  // digilir tiap hari dari kandidat kuat berikutnya (top ~24).
                  // Nomor #1..#8 tetap monoton (di-sort ulang by soldCount).
                  final bestSellers = _dailyRotatingPick(
                    rankedBySold.take(24).toList(),
                    pinned: 3,
                    count: 8,
                  );
                  return NataloPawRefreshIndicator(
                    onRefresh: _refreshAll,
                    // pinContent: konten diam total saat pull — tanpa ini bouncing
                    // physics membuat sliver non-pinned melar menjauh dari sticky
                    // header (celah putih "terbelah") + translateChild menggeser
                    // seluruh hero turun. Paw = satu-satunya yang bergerak.
                    pinContent: true,
                    // Paw muncul tepat di bawah header expanded (extent 164,
                    // sudah di dalam SafeArea). Refresh hanya mungkin di
                    // scroll ≈ 0 = header pasti expanded (floating fully
                    // revealed), jadi cukup satu angka.
                    topPadding: 170,
                    child: CustomScrollView(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        // Header collapsing 1:1 PINNED — extent 164
                        // (expanded) → 66 (collapsed). Lipatan digerakkan
                        // shrinkOffset native mengikuti jari; setelah mengecil
                        // DIAM terkunci, mengembang penuh lagi hanya saat
                        // scroll balik ke atas (BUKAN mid-list). Floating
                        // dibuang atas keputusan user (reveal terlalu gampang
                        // + fling jump). Engine SAMA dengan Produk (delegate
                        // bersama).
                        SliverPersistentHeader(
                          pinned: true,
                          delegate: CollapsingHeaderDelegate(
                            minHeight: _HomeHeader.collapsedExtent,
                            maxHeight: _HomeHeader.expandedExtent,
                            builder: (context, t) => _HomeHeader(
                              progress: t,
                              onOpenProducts: () => _openProducts(context),
                              onOpenSearch: () => _openHomeSearch(context),
                            ),
                          ),
                        ),
                        // Background upload relay card — visible HANYA saat ada
                        // upload feed post aktif. AnimatedSize handle collapse
                        // smooth saat task hilang (success auto-dismiss).
                        const SliverToBoxAdapter(child: FeedUploadBar()),
                        if (result?.fromApi == false)
                          const SliverToBoxAdapter(child: _ApiFallbackNotice()),
                        // Trust marquee SEKARANG bagian sticky header (ikut
                        // terlipat saat collapse) — lihat _HomeHeader. Sliver
                        // terpisah yang dulu di sini dihapus (spec collapsing
                        // header "Cara 1", membalikkan keputusan PR #54 dengan
                        // persetujuan user setelah demo perbandingan).
                        // API banner carousel kalau ada banner aktif dari admin.
                        // Section auto-hide kalau _banners kosong (di _HeroBanner).
                        SliverToBoxAdapter(
                          child: _HeroBanner(banners: _banners),
                        ),
                        SliverToBoxAdapter(
                          child: _ShortcutGrid(
                            onOpenProducts: () => _openProducts(context),
                          ),
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
                        // Brand section — sembunyikan kalau tidak ada brand berlogo.
                        // Tidak ada fallback ke sampleBrands lagi: brand di Flutter
                        // harus sync dengan admin dashboard (single source of truth).
                        // Pakai _logoBrands (hanya yang punya logo, tanpa cap) supaya
                        // semua brand berlogo bisa di-slide, bukan cuma 12.
                        if (_logoBrands.isNotEmpty)
                          SliverToBoxAdapter(
                            child: _BrandChoiceSection(
                              brands: _logoBrands,
                              onTap: (brand) =>
                                  _openProducts(context, brand: brand.name),
                            ),
                          ),
                        SliverToBoxAdapter(
                          child: _CategorySection(
                            categories: _categories,
                            // Pass category name — ProductsScreen filter cocok by name
                            // (lihat `_filter.category == null || product.category == _filter.category`).
                            onTap: (name) =>
                                _openProducts(context, category: name),
                          ),
                        ),
                        // Rekomendasi personal — utamakan hasil server-side
                        // scoring (`_personalizedRecs`) yang scan SELURUH catalog
                        // dengan signal purchase + view weighted. Fallback ke
                        // client-side scoring (pool 48) kalau API gagal /
                        // offline / response kosong.
                        //
                        // ── Zona belanja latar abu (ala Shopee) ──
                        // Rekomendasi + Jelajahi dibungkus satu DecoratedSliver
                        // (verified tetap lazy: SliverMainAxisGroup tak
                        // memaksa materialisasi list) supaya kartu putih
                        // menonjol di atas kanal abu, tanpa seam antar-section.
                        DecoratedSliver(
                          decoration: BoxDecoration(
                            color: _homeGridSurfaceTint(context),
                          ),
                          sliver: SliverMainAxisGroup(
                            slivers: [
                              SliverToBoxAdapter(
                                child: AnimatedBuilder(
                                  animation: recentlyViewedStore,
                                  builder: (context, _) {
                                    final recPool =
                                        _personalizedRecs.isNotEmpty
                                            ? _personalizedRecs
                                            : _buildPersonalizedRecommendations(
                                                products);
                                    if (recPool.isEmpty) {
                                      return const SizedBox.shrink();
                                    }
                                    // Rotasi harian: 4 rekomendasi paling
                                    // relevan tetap di atas, 6 sisanya digilir
                                    // tiap hari dari kandidat (pool 18 server).
                                    final recommendations = _dailyRotatingPick(
                                      recPool,
                                      pinned: 4,
                                      count: 10,
                                    );
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
                                padding:
                                    const EdgeInsets.fromLTRB(12, 12, 12, 16),
                                // Grid 2-kolom AUTO-HEIGHT (bukan SliverGrid dengan
                                // childAspectRatio tetap). Tiap baris = 1 Row berisi 2
                                // kartu — tinggi BARIS ikut konten terpanjang. Sebelumnya
                                // 0.54 dipaku → kartu dengan diskon + 2 badge (ongkir+
                                // hemat, wrap 2 baris) + rating overflow ~8-9px.
                                //
                                // BUKAN CrossAxisAlignment.stretch (beda dari pola yang
                                // sama di halaman Produk!): stretch di Row memaksa
                                // Flutter hitung intrinsic-height _HomeProductCard.
                                // Sesuatu di widget tree kartu ini tidak mendukung
                                // perhitungan itu → layout exception. Di app ini,
                                // FlutterError.onError (app_crashlytics.dart) di-override
                                // TANPA memanggil FlutterError.presentError, jadi
                                // exception layout itu tidak tercetak ke console SAMA
                                // SEKALI — hasilnya Beranda blank total (bukan cuma grid
                                // ini) tanpa jejak error apa pun. Ke-2 kartu di satu
                                // baris kebetulan hampir selalu sama tinggi (struktur
                                // konten seragam), jadi tanpa stretch pun rapi secara
                                // visual — trade-off yang aman untuk menghindari crash
                                // senyap ini.
                                sliver: SliverList(
                                  delegate: SliverChildBuilderDelegate(
                                    (context, rowIndex) {
                                      // Saat first load belum ada produk + masih loading,
                                      // tampilkan skeleton — feels lebih native dari blank.
                                      final showingSkeleton =
                                          _exploreProducts.isEmpty &&
                                              !_exploreInitialLoaded;
                                      final itemCount = showingSkeleton
                                          ? 6
                                          : _exploreProducts.length;
                                      final leftIndex = rowIndex * 2;
                                      final rightIndex = leftIndex + 1;
                                      final rowCount = (itemCount + 1) ~/ 2;
                                      final isLastRow =
                                          rowIndex == rowCount - 1;

                                      Widget cell(int index) {
                                        if (showingSkeleton) {
                                          return const SkeletonProductCard(
                                            showAddToCart: false,
                                            squareImage: true,
                                          );
                                        }
                                        final product = _exploreProducts[index];
                                        return _HomeProductCard(
                                          product: product,
                                          squareImage: true,
                                          onTap: () => _openProductDetail(
                                              context, product),
                                        );
                                      }

                                      return Padding(
                                        padding: EdgeInsets.only(
                                          bottom: isLastRow ? 0 : 6,
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(child: cell(leftIndex)),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: rightIndex < itemCount
                                                  ? cell(rightIndex)
                                                  // Jumlah ganjil — slot kanan kosong,
                                                  // kartu kiri tetap selebar 1 kolom.
                                                  : const SizedBox.shrink(),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                    childCount: (() {
                                      final showingSkeleton =
                                          _exploreProducts.isEmpty &&
                                              !_exploreInitialLoaded;
                                      final itemCount = showingSkeleton
                                          ? 6
                                          : _exploreProducts.length;
                                      return (itemCount + 1) ~/ 2;
                                    })(),
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
                              const SliverToBoxAdapter(
                                  child: SizedBox(height: 24)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
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
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 28, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Jelajahi Produk Natalo',
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Temukan berbagai kebutuhan hewan kesayanganmu di Natalo',
            style: TextStyle(
              color: cs.onSurfaceVariant,
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
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Center(
          child: Text(
            'Semua produk sudah ditampilkan',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
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

/// Header Beranda dengan collapse 1:1 (digerakkan shrinkOffset via
/// [CollapsingHeaderDelegate] — pinned+floating+snap, SAMA dengan Produk).
///
/// [progress] 0.0 = expanded, 1.0 = collapsed — diturunkan dari shrinkOffset.
///
/// Expanded : brand row (logo + nama + bell/chat/cart) + search 44 +
///            trust marquee (ikut terlipat — "Cara 1").
/// Collapsed: SATU baris — search 40 + dock chat+cart meluncur dari kanan
///            (translateX 14→0, scale .85→1, fade in). Bell ikut hilang
///            bersama brand row, TIDAK dipindah.
///
/// Efek "besar-kecil" logo+nama DIPERTAHANKAN: seluruh brand row menyusut
/// scale 1→.85 dari kiri sambil barisnya menutup.
///
/// SYARAT ENGINE 1:1: tinggi konten HARUS linear terhadap t (lihat
/// [expandedExtent]/[collapsedExtent]). Kunci: search 44→40 selalu ≤
/// [_dockHeight] 44, jadi `max(search, 44)` = 44 KONSTAN → tidak ada "kink"
/// di tengah range → extent linear, tidak ada celah/clip di frame mana pun.
/// (Search 46 lama > 44 akan membuat baris 46 di t=0 lalu 44 di t≥0.5 =
/// kink; itu sebab search diramping ke 44/40.)
class _HomeHeader extends StatelessWidget {
  final VoidCallback onOpenProducts;
  final VoidCallback onOpenSearch;
  final double progress;

  const _HomeHeader({
    required this.onOpenProducts,
    required this.onOpenSearch,
    this.progress = 0.0,
  });

  /// Row brand 48 + gap bawah 10 — di-fold penuh saat collapsed.
  static const double _brandBlockHeight = 58;

  /// Tinggi ikon dock (AppHeaderIconButton minHeight 44 — tap target). Baris
  /// search selalu setinggi ini (search ≤44), jadi rowHeight konstan → extent
  /// linear. Marquee (36 + pad 6 = 42) di-fold; nilainya sudah masuk
  /// [expandedExtent].
  static const double _dockHeight = 44;

  /// Extent expanded (t=0): padTop 8 + brand 58 + row 44 + padBottom 12 +
  /// marquee 42 = 164.
  static const double expandedExtent = 164;

  /// Extent collapsed (t=1): padTop 10 + brand 0 + row 44 + padBottom 12 +
  /// marquee 0 = 66.
  static const double collapsedExtent = 66;

  @override
  Widget build(BuildContext context) {
    final t = progress.clamp(0.0, 1.0);
    // Fade konten sedikit lebih cepat dari lipatan container — habis t≈0.62.
    final blockOpacity = (1 - t * 1.6).clamp(0.0, 1.0);
    final brandScale = ui.lerpDouble(1.0, 0.85, t)!;
    // Search compact 44→40 (≤ _dockHeight 44 → rowHeight konstan → extent
    // linear). Radius 14→12.
    final searchHeight = ui.lerpDouble(44, 40, t)!;
    final searchRadius = ui.lerpDouble(14, 12, t)!;
    final paddingTop = ui.lerpDouble(8, 10, t)!;
    // Dock chat+cart: lebar terbuka linear bersama lipatan; opacity nyusul
    // (mulai t=.2) supaya ikon terasa "meluncur masuk", bukan cuma muncul.
    final dockOpacity = ((t - 0.2) / 0.8).clamp(0.0, 1.0);
    final dockSlide = 14.0 * (1 - t);
    final dockScale = ui.lerpDouble(0.85, 1.0, t)!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            // Hero biru VERTIKAL murni (heroGradientV) — bukan diagonal.
            // Diagonal bikin garis tipis "seam" di sambungan blok hero
            // (status strip → header → marquee) karena tepi tiap blok punya
            // sebaran warna miring yang tidak sejajar antar kotak. Vertikal =
            // warna seragam tiap baris → sambungan menyatu mulus.
            gradient: NataloColors.heroGradientV,
            // Shadow bawah = pemisah dari konten, hanya saat collapsed
            // (expanded: marquee di bawahnya yang jadi penutup blok).
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
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, paddingTop, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Baris brand: logo + nama + bell/chat/cart. Terlipat
                // UTUH (height→0 + fade) sambil menyusut scale 1→.85 dari
                // kiri. Tinggi di-animate SEKALI via Align.heightFactor.
                ClipRect(
                  child: Align(
                    alignment: Alignment.topCenter,
                    heightFactor: 1 - t,
                    child: SizedBox(
                      height: _brandBlockHeight,
                      child: IgnorePointer(
                        // Saat terlipat, bell/chat/cart atas tidak ketap.
                        ignoring: t > 0.5,
                        child: Opacity(
                          opacity: blockOpacity,
                          child: Transform.scale(
                            scale: brandScale,
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Row(
                                children: [
                                  // Logo di CHIP PUTIH — kontras di atas hero.
                                  Container(
                                    width: 44,
                                    height: 44,
                                    padding: const EdgeInsets.all(3),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(13),
                                    ),
                                    alignment: Alignment.center,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: Image.asset(
                                        'assets/native/icon-only.png',
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            const Text(
                                          'NL',
                                          style: TextStyle(
                                            color: _heroMid,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 18,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'Natalo Petshop',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w900,
                                            color: Colors.white,
                                            height: 1.15,
                                          ),
                                        ),
                                        Padding(
                                          padding: EdgeInsets.only(top: 2),
                                          child: Text(
                                            'Kebutuhan hewan kesayanganmu',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: _onHeroSubtle,
                                              height: 1.1,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const AppNotificationButton(
                                    iconColor: Colors.white,
                                  ),
                                  const AppChatButton(iconColor: Colors.white),
                                  const AppCartButton(iconColor: Colors.white),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // ── Baris search + dock chat/cart ──
                // Tinggi baris DIPAKU _dockHeight (44) supaya extent tetap
                // linear (kontrak engine 1:1) apa pun tinggi visual search
                // (44→40, di-center dalam 44). Search center vertikal.
                SizedBox(
                  height: _dockHeight,
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: onOpenSearch,
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            height: searchHeight,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(searchRadius),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.search_rounded,
                                  size: 18,
                                  color: Color(0xFF64748B),
                                ),
                                const SizedBox(width: 10),
                                // Dynamic placeholder — rotates dari trending
                                // search API. Hanya Text ini yang rebuild.
                                Expanded(
                                  child: AnimatedBuilder(
                                    animation: trendingPlaceholderController,
                                    builder: (context, _) {
                                      final text = trendingPlaceholderController
                                          .currentPlaceholder;
                                      return AnimatedSwitcher(
                                        duration: const Duration(
                                          milliseconds: 300,
                                        ),
                                        switchInCurve: Curves.easeOutCubic,
                                        switchOutCurve: Curves.easeInCubic,
                                        layoutBuilder:
                                            (currentChild, previousChildren) {
                                          return Stack(
                                            alignment: Alignment.centerLeft,
                                            children: <Widget>[
                                              ...previousChildren,
                                              if (currentChild != null)
                                                currentChild,
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
                                            color: Color(0xFF64748B),
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
                      ),
                      // ── Dock chat + cart: DUPLIKAT yang di-reveal (bukan
                      // shared element yang terbang — spec #3). Lebar dibuka
                      // SEKALI via Align.widthFactor; ikon hanya transform
                      // (slide 14→0 + scale .85→1) + opacity. Kill-switch chat
                      // aman: AppChatButton SizedBox.shrink() → dock cart saja.
                      ClipRect(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          widthFactor: t,
                          child: IgnorePointer(
                            // Tap aktif hanya saat dock terlihat.
                            ignoring: t < 0.5,
                            child: Opacity(
                              opacity: dockOpacity,
                              child: Transform.translate(
                                offset: Offset(dockSlide, 0),
                                child: Transform.scale(
                                  scale: dockScale,
                                  alignment: Alignment.center,
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Gap ≥10 dari search — badge tidak
                                      // menabrak search di layar ≤360px.
                                      SizedBox(width: 10),
                                      AppChatButton(iconColor: Colors.white),
                                      AppCartButton(iconColor: Colors.white),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // ── Trust marquee — bagian header, ikut terlipat (Cara 1). Latar
        // ColoredBox = scaffold bg supaya sudut membulat strip tidak "bocor"
        // memperlihatkan konten yang lewat di belakang header pinned.
        //
        // TickerMode: matikan ticker marquee (repeat 34s) saat header
        // collapsed — marquee tetap mounted (state & posisi scroll marquee
        // awet) tapi tidak membakar frame untuk strip yang ter-clip 0px.
        ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: 1 - t,
            child: TickerMode(
              enabled: t < 0.99,
              child: Opacity(
                opacity: blockOpacity,
                child: ColoredBox(
                  // Base abu (bukan putih) supaya sudut membulat bawah header
                  // blend dgn latar Beranda yang kini abu — tak ada sabit putih.
                  color: _homeGridSurfaceTint(context),
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      // Vertikal murni — menyambung mulus dgn heroGradientV
                      // header di atasnya (batas atas = heroMid keduanya).
                      gradient: NataloColors.heroGradientVContinue,
                      borderRadius: BorderRadius.vertical(
                        bottom: Radius.circular(18),
                      ),
                    ),
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 6),
                      child: _TrustMarquee(
                        key: ValueKey('home-trust-marquee'),
                        height: 36,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
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
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Cari Produk Natalo',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            'Produk, brand, kategori, dan kebutuhan pet kamu.',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
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
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text(
              'Mencari saran...',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
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
          Row(
            children: [
              const Icon(
                Icons.local_fire_department_rounded,
                color: Color(0xFFEF4444),
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                'Trending sekarang',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
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
                avatar: const Icon(
                  Icons.trending_up_rounded,
                  size: 16,
                  color: Color(0xFFEF4444),
                ),
                label: Text(term),
                onPressed: () => onTap(term),
              );
            }).toList(),
          ),
        ],
        const SizedBox(height: 14),
        Text(
          'Pencarian populer',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
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
      leading: SoftIconBox(icon: icon, size: 40),
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

  const _HomeProductSuggestionRow({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final priceLabel = item.priceMax > item.priceMin
        ? '${formatRupiah(item.priceMin)} - ${formatRupiah(item.priceMax)}'
        : formatRupiah(item.priceMin);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AppProductImage(imageUrl: item.imageUrl, height: 44, width: 44),
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

  // Teks di ATAS HERO BIRU — putih-kebiruan terang supaya terbaca jelas
  // (versi lama _onHeroSubtle terlalu redup, user tidak bisa baca trust
  // point-nya). Tetap sedikit di bawah putih penuh supaya search bar putih
  // masih jadi fokus utama.
  static const _marqueeTextColor = NataloColors.onHeroBright;
  static const _textStyle = TextStyle(
    color: _marqueeTextColor,
    fontSize: 12,
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
    // Ikon di atas hero biru: putih-kebiruan seragam, kecuali dua aksen
    // lembut (hijau mint utk "Original", amber muda utk "Promo") supaya
    // strip tetap hidup tanpa norak.
    return [
      const _TrustMarqueeItemData(
        icon: Icons.local_shipping_outlined,
        iconColor: _TrustMarqueeState._marqueeTextColor,
        text: 'Gratis Ongkir Area Medan',
      ),
      const _TrustMarqueeItemData(
        icon: Icons.shield_outlined,
        iconColor: Color(0xFF8FE3B0),
        text: 'Produk Original 100%',
      ),
      _TrustMarqueeItemData(
        icon: Icons.chat_bubble_outline_rounded,
        iconColor: _TrustMarqueeState._marqueeTextColor,
        text: 'Konsultasi via WhatsApp',
        showLinkIcon: true,
        onTap: () {
          AppHaptics.tap();
          launchUrl(
            NataloStoreConfig.whatsappUri(
              message: 'Halo Natalo Petshop, saya mau tanya...',
            ),
            mode: LaunchMode.externalApplication,
          );
        },
      ),
      _TrustMarqueeItemData(
        icon: Icons.pets_rounded,
        iconColor: _TrustMarqueeState._marqueeTextColor,
        text: 'Petshop Medan Terpercaya',
        onTap: () => AppInAppBrowser.openTentangNatalo(context),
      ),
      const _TrustMarqueeItemData(
        icon: Icons.card_giftcard_rounded,
        iconColor: Color(0xFFFFD9A0),
        text: 'Banyak Promo Setiap Hari',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final items = _items(context);
    final groupWidth = _estimateGroupWidth(items);
    // Latar & border DIHAPUS — strip sekarang duduk di atas gradasi hero
    // biru yang dicat parent (SliverToBoxAdapter di build utama), sama di
    // light & dark mode. ClipRect tetap perlu utk crop konten marquee.
    return Container(
      height: widget.height,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(),
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

  const _TrustMarqueeGroup({required this.items, this.duplicate = false});

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
    // Tanpa cabang dark mode — strip selalu di atas hero biru (warna fixed).
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
            decorationColor: const Color(0xFF9FBEF0),
            decorationStyle: TextDecorationStyle.dotted,
          ),
        ),
        if (item.showLinkIcon) ...[
          const SizedBox(width: 4),
          const Icon(
            Icons.open_in_new_rounded,
            color: Color(0xFF9FBEF0),
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
        // Dot pemisah di atas hero biru — biru pucat, bukan abu (tenggelam).
        color: Color(0xFF9FBEF0),
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
      href: '/products?kategori=anjing',
    ),
    _LocalBanner(
      image: 'assets/banners/bersinar-aquarium.jpeg',
      href: '/products?kategori=ikan',
    ),
    _LocalBanner(
      image: 'assets/banners/instant-max-3-jam.jpg',
      href: '/products',
    ),
    _LocalBanner(
      image: 'assets/banners/member-benefit.png',
      href: '/member/register',
    ),
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
    final uri = Uri.tryParse(href);
    if (uri == null) return;

    // 1) URL eksternal (banner linkType=url) → buka di browser.
    //    Internal href selalu path-only (mulai '/'), jadi adanya scheme
    //    http(s) = eksternal.
    if (uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https')) {
      launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }

    final path = uri.path;
    final segments = uri.pathSegments;

    // 2) /products/<slug> → product detail (banner linkType=product).
    //    Fetch produk by slug lalu push detail. Dibedakan dari /products
    //    (catalog) yang tanpa slug.
    if (segments.length == 2 && segments[0] == 'products') {
      _openBannerProduct(segments[1]);
      return;
    }

    // 3) /products (catalog) — dengan optional filter dari query.
    //    diskon=1 → mode produk diskon (banner linkType=promo).
    if (path == '/products' || path.startsWith('/products')) {
      Navigator.pushNamed(
        context,
        '/products',
        arguments: ProductCatalogArgs(
          initialCategory: uri.queryParameters['kategori'],
          initialQuery: uri.queryParameters['q'],
          selectedBrand: uri.queryParameters['brand'],
          discountOnly: uri.queryParameters['diskon'] == '1',
        ),
      );
      return;
    }

    // 4) Internal routes lain.
    if (path == '/member' || path.startsWith('/member/')) {
      Navigator.pushNamed(context, path);
    } else if (path == '/feed') {
      Navigator.pushNamed(context, '/feed');
    } else if (path == '/cart') {
      Navigator.pushNamed(context, '/cart');
    }
  }

  /// Banner linkType=product → fetch produk by slug lalu buka detail.
  /// Loading dialog singkat; kalau gagal fetch (slug salah / dihapus),
  /// fallback ke katalog produk.
  Future<void> _openBannerProduct(String slug) async {
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
    Product? product;
    try {
      product = await productService.fetchProductBySlug(slug);
    } catch (_) {
      product = null;
    }
    rootNav.pop();
    if (!mounted) return;
    if (product == null) {
      Navigator.pushNamed(context, '/products');
      return;
    }
    Navigator.pushNamed(context, '/product-detail', arguments: product);
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
          decoration: const BoxDecoration(color: Color(0xFFEAF5FF)),
          child: isNetwork
              ? CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  fadeInDuration: const Duration(milliseconds: 220),
                  // Shimmer (bukan spinner) — spinner di area 16:7 terbaca
                  // sebagai "lubang loading"; shimmer terbaca sebagai
                  // "konten sedang datang". Fix keluhan ruang-kosong besar
                  // saat gambar banner lambat termuat.
                  placeholder: (context, url) => Shimmer.fromColors(
                    baseColor: const Color(0xFFE8EFF9),
                    highlightColor: const Color(0xFFF7FAFE),
                    child: Container(color: const Color(0xFFE8EFF9)),
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
      // ── Row 1: Kategori utama (selaras katalog live — semua ada isi) ──
      // Slug dipakai (bukan nama) supaya match backend + highlight sheet
      // kategori akurat. Lihat /api/categories untuk jumlah produk.
      _ShortcutItem(
        Icons.pets_rounded,
        'Makanan Kucing',
        const Color(0xFF0B7FEA),
        onTap: (ctx) => Navigator.pushNamed(
          ctx,
          '/products',
          arguments: const ProductCatalogArgs(
            initialCategory: 'makanan-kucing',
          ),
        ),
      ),
      // TULANG (SVG custom) — Material Icons tak punya tulang/anjing; dulu
      // cruelty_free_rounded (KELINCI, salah makna), lalu cookie (biskuit)
      // masih kurang pas. iconAsset menang atas `icon`; cookie disimpan
      // sebagai fallback kalau SVG gagal load.
      _ShortcutItem(
        Icons.cookie_rounded,
        'Makanan Anjing',
        const Color(0xFFF59E0B),
        iconAsset: 'assets/icons/bone.svg',
        onTap: (ctx) => Navigator.pushNamed(
          ctx,
          '/products',
          arguments: const ProductCatalogArgs(
            initialCategory: 'makanan-anjing',
          ),
        ),
      ),
      _ShortcutItem(
        Icons.set_meal_rounded,
        'Makanan Ikan',
        const Color(0xFF0891B2),
        onTap: (ctx) => Navigator.pushNamed(
          ctx,
          '/products',
          arguments: const ProductCatalogArgs(initialCategory: 'makanan-ikan'),
        ),
      ),
      _ShortcutItem(
        Icons.medication_rounded,
        'Obat & Suplemen',
        const Color(0xFFEF4444),
        onTap: (ctx) => Navigator.pushNamed(
          ctx,
          '/products',
          arguments: const ProductCatalogArgs(initialCategory: 'obat-suplemen'),
        ),
      ),
      // ── Row 2: Promo + Produk Baru + reward ──
      _ShortcutItem(
        Icons.local_fire_department_rounded,
        'Promo',
        const Color(0xFFE11D48),
        onTap: (ctx) => Navigator.pushNamed(
          ctx,
          '/products',
          arguments: const ProductCatalogArgs(discountOnly: true),
        ),
      ),
      _ShortcutItem(
        Icons.new_releases_rounded,
        'Produk Baru',
        const Color(0xFF16A34A),
        onTap: (ctx) => Navigator.pushNamed(
          ctx,
          '/products',
          arguments: const ProductCatalogArgs(newestOnly: true),
        ),
      ),
      _ShortcutItem(
        Icons.local_offer_rounded,
        'Voucher',
        const Color(0xFFDB2777),
        onTap: (ctx) => Navigator.pushNamed(ctx, '/member/vouchers'),
      ),
      _ShortcutItem(
        Icons.stars_rounded,
        'Tukar Poin',
        const Color(0xFFEA580C),
        onTap: (ctx) => Navigator.pushNamed(ctx, '/member/loyalty'),
      ),
    ];

    // Sel shortcut (ikon squircle 48 + label). Column min-height = konten.
    Widget buildCell(_ShortcutItem item) {
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
          mainAxisSize: MainAxisSize.min,
          children: [
            // Lingkaran 48px warna solid + icon PUTIH (redesign Jul 2026,
            // gaya "circle warna" ala marketplace — dulu squircle soft-tint
            // + icon berwarna yang terasa datar/pucat di device). Tap ≥48.
            Container(
              height: 48,
              width: 48,
              decoration: BoxDecoration(
                color: item.color,
                shape: BoxShape.circle,
              ),
              child: item.iconAsset != null
                  ? SvgPicture.asset(
                      item.iconAsset!,
                      width: 24,
                      height: 24,
                      colorFilter: const ColorFilter.mode(
                        Colors.white,
                        BlendMode.srcIn,
                      ),
                    )
                  : Icon(item.icon, color: Colors.white, size: 24),
            ),
            const SizedBox(height: 6),
            Text(
              item.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                height: 1.12,
              ),
            ),
          ],
        ),
      );
    }

    // Grid 4-kolom AUTO-HEIGHT (Column-of-Rows). SEBELUMNYA GridView.builder
    // shrinkWrap + mainAxisExtent 72 — di device iOS menyisakan tinggi HANTU
    // (~1 baris ekstra) → celah abu besar shortcut → Flash Sale (dibuktikan
    // border debug). Column-of-Rows: tinggi = konten persis, deterministik,
    // tak ada kolong. Pola sama dgn _FlashSaleGrid + grid utama.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        children: [
          for (var row = 0; row < (items.length + 3) ~/ 4; row++) ...[
            // 14 (dulu 6): jarak antar-baris shortcut dulu = jarak icon→label
            // dalam sel (6) → baris 1 & 2 terasa mepet. 14 memberi napas jelas.
            if (row > 0) const SizedBox(height: 14),
            Row(
              // start (bukan stretch): kalau ada label 2 baris, sel lain
              // tetap rata-atas, tak ikut memanjang.
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var col = 0; col < 4; col++) ...[
                  if (col > 0) const SizedBox(width: 8),
                  Expanded(
                    child: row * 4 + col < items.length
                        ? buildCell(items[row * 4 + col])
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _FlashSaleGrid extends StatelessWidget {
  final List<Product> products;
  final ValueChanged<Product> onTap;
  final VoidCallback onSeeAll;
  final VoidCallback? onCountdownExpired;

  // Grid 3 kolom × 3 baris = 9 (user minta grid atas-bawah, pakai spec kartu
  // grid 1:1). Sebelumnya sempat rail horizontal (8).
  static const _maxVisible = 9;

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

  // ── Redesign Jul 2026: PITA merah-tipis full-width + RAIL horizontal ──
  // Pita (bukan card di tengah) supaya saat section auto-hide tidak ada
  // "bekas lubang"; rail horizontal supaya 2 produk pun tidak menyisakan
  // kolom kanan kosong (kartu ke-3 mengintip → memancing scroll).
  // Warna disegarkan (dulu band #FFF7F7 + judul #8F2727 — terlalu pucat/
  // kusam kata user): band rose muda, judul + petir merah rose vivid yang
  // senada dengan chip countdown & badge diskon.
  static const _bandLight = Color(0xFFFFF1F2);
  static const _bandDark = Color(0xFF2B1719);
  static const _titleLight = Color(0xFFE11D48);
  static const _titleDark = Color(0xFFFDA4AF);

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) return const SizedBox.shrink();

    final visible = products.take(_maxVisible).toList();
    final hasMore = products.length > _maxVisible;
    final endsAt = _earliestEndsAt;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? _titleDark : _titleLight;

    return Container(
      // Celah 20: margin-atas abu (latar Beranda) memisahkan shortcut → pita
      // Flash Sale. Sejarah: 0 ("nempel") karena celah abu dikira bug; ternyata
      // bug-nya tinggi HANTU GridView shortcut (difix ke Column-of-Rows), lalu
      // 12 masih terasa rapat di device. Sekarang 20 = SAMA dengan ritme jarak
      // section lain (Flash→Terlaris, Terlaris→Brand, Brand→Kategori — semua
      // 20, keputusan user Jul 2026). Margin hanya di sini → tak memengaruhi
      // tampilan saat Flash Sale kosong.
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 14),
      color: isDark ? _bandDark : _bandLight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.bolt_rounded, size: 19, color: titleColor),
                const SizedBox(width: 3),
                Text(
                  'Flash Sale',
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                // Countdown kotak HH:MM:SS (Opsi B) — hanya kalau ada produk
                // Tier 1 (explicit flashSaleEndsAt). 3 kotak merah + separator
                // langsung di band = jelas "hitung mundur" (bukan pil tunggal
                // yang mirip durasi biasa). FittedBox: menyusut mulus di layar
                // sempit alih-alih overflow; Expanded mendorong "Lihat semua"
                // ke kanan.
                if (endsAt != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: FlashSaleCountdown.boxes(
                          endsAt: endsAt,
                          onExpired: onCountdownExpired,
                        ),
                      ),
                    ),
                  ),
                ] else
                  const Spacer(),
                if (hasMore)
                  GestureDetector(
                    onTap: onSeeAll,
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                      child: Text(
                        'Lihat semua ›',
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
          ),
          const SizedBox(height: 10),
          // Grid 3-kolom AUTO-HEIGHT (spec sama Beranda/Katalog) — dulu rail
          // horizontal; user minta grid 3×3 atas-bawah. Row-based auto-height
          // (BUKAN GridView aspect-tetap) supaya kartu foto 1:1 + progress
          // terjual tak overflow di layar sempit. Tepi 16, gap 6.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                for (var row = 0; row < (visible.length + 2) ~/ 3; row++)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: row == (visible.length + 2) ~/ 3 - 1 ? 0 : 6,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var col = 0; col < 3; col++) ...[
                          if (col > 0) const SizedBox(width: 6),
                          Expanded(
                            child: row * 3 + col < visible.length
                                ? _FlashSaleCard(
                                    product: visible[row * 3 + col],
                                    onTap: () => onTap(visible[row * 3 + col]),
                                  )
                                // Baris terakhir ganjil — slot kosong jaga
                                // lebar kolom tetap 1/3 (kartu tak melar).
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ],
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

class _FlashSaleCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;

  const _FlashSaleCard({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final discountPercent = _activeHomeProductDiscountPercent(product);

    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
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
              // Foto 1:1 full-bleed cover (spec grid) + badge diskon overlay.
              Stack(
                children: [
                  _HomeProductImageSquare(imageUrl: product.imageUrl),
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
              Padding(
                padding: const EdgeInsets.fromLTRB(7, 6, 7, 7),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 27,
                      child: Text(
                        product.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.8,
                          height: 1.18,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    _FlashSalePriceBlock(product: product),
                    _FlashSaleSoldProgress(product: product),
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
        style: TextStyle(
          fontSize: 13,
          height: 1.05,
          fontWeight: FontWeight.w900,
          color: Theme.of(context).colorScheme.onSurface,
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
            fontSize: 9.5,
            height: 1,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
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

/// Progress bar "terjual" ala Shopee di kartu flash sale — urgency cue
/// visual (bar makin penuh = makin laku). Persen = sold/(sold+stock),
/// clamp 6%–96% supaya bar tidak pernah tampak kosong/penuh sempurna.
/// Fallback: produk belum ada penjualan → baris rating lama (tinggi sama,
/// kartu-kartu di rail tetap rata).
class _FlashSaleSoldProgress extends StatelessWidget {
  final Product product;

  const _FlashSaleSoldProgress({required this.product});

  @override
  Widget build(BuildContext context) {
    final sold = product.soldCount;
    if (sold <= 0) return _FlashSaleRatingSoldRow(product: product);

    final stock = product.stock;
    final ratio = stock > 0 ? sold / (sold + stock) : 0.9;
    final fraction = ratio.clamp(0.06, 0.96);

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 5,
              child: Row(
                children: [
                  Expanded(
                    flex: (fraction * 100).round(),
                    child: const ColoredBox(color: Color(0xFFE06666)),
                  ),
                  Expanded(
                    flex: 100 - (fraction * 100).round(),
                    child: const ColoredBox(color: Color(0xFFFBE3E3)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${_formatHomeProductSoldCount(sold)} terjual',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 9.5,
              height: 1.05,
              fontWeight: FontWeight.w600,
              color: Color(0xFFA05252),
            ),
          ),
        ],
      ),
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
    // Tinggi tetap (bukan shrink ke 0) supaya kartu tanpa rating/terjual
    // tetap sama tinggi dengan tetangganya di baris yang sama — grid
    // flash sale row-loop tidak pakai CrossAxisAlignment.stretch, jadi
    // kerataan baris bergantung pada tiap bagian kartu punya tinggi
    // konsisten. 18 = padding-top 6 + tinggi baris teks/ikon ~12.
    if (!hasRating && !hasSold) return const SizedBox(height: 18);

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          if (hasRating) ...[
            const Icon(Icons.star_rounded, size: 12, color: Color(0xFFFACC15)),
            const SizedBox(width: 3),
            Text(
              product.rating.toStringAsFixed(1),
              style: TextStyle(
                fontSize: 10.2,
                height: 1,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (hasRating && hasSold) ...[
            const SizedBox(width: 4),
            Text(
              '•',
              style: TextStyle(
                fontSize: 10.2,
                height: 1,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                style: TextStyle(
                  fontSize: 10.2,
                  height: 1,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
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
  final double priceFontSize;
  final bool compact;
  // Grid utama Beranda: foto persegi 1:1 full-bleed (BoxFit.cover) + kartu
  // radius lebih kecil (10), ala Shopee. Default false supaya rail compact
  // (_MiniProductCard "Terlaris" dst) yang me-reuse widget ini TIDAK ikut
  // berubah — cukup diaktifkan di call-site grid 2-kolom.
  final bool squareImage;
  // Rail "ramping" (Terlaris): sembunyikan badge Hemat/Ongkir + harga-coret
  // + repurchase badge → semua kartu seragam (foto + nama + harga + terjual)
  // supaya rail fixed-height tak menyisakan kolong kosong di bawah kartu
  // yang tak diskon. Default false: grid & rail lain tak berubah.
  final bool railSlim;

  const _HomeProductCard({
    required this.product,
    required this.onTap,
    this.rank,
    this.width,
    this.priceFontSize = 16,
    this.compact = false,
    this.squareImage = false,
    this.railSlim = false,
  });

  @override
  Widget build(BuildContext context) {
    final padding = compact ? 8.0 : 10.0;
    final nameHeight = compact ? 31.0 : 34.0;
    final discountPercent = _activeHomeProductDiscountPercent(product);

    final cs = Theme.of(context).colorScheme;
    // Grid utama: radius kartu lebih kecil (8) + foto full-bleed. Rail
    // compact tetap radius 18 + foto fixed-height contain (tak berubah).
    final cardRadius = squareImage ? 8.0 : 18.0;

    final imageStack = Stack(
      children: [
        squareImage
            // Video HANYA di grid utama Beranda, TIDAK pernah di rail. `railSlim`
            // menandai kartu rail horizontal (Terlaris / carousel keranjang-kosong)
            // yang tetap foto-only sesuai plan; kedua grid asli membiarkan
            // `railSlim` default false → dapat video.
            ? ((product.hasVideo && !railSlim)
                ? ProductGridVideo(
                    videoUrl: product.videoUrl!,
                    imageUrl: product.imageUrl,
                  )
                : _HomeProductImageSquare(imageUrl: product.imageUrl))
            : _HomeProductImage(
                imageUrl: product.imageUrl,
                // Fallback non-square (tak ada caller aktif — semua grid/rail
                // sudah squareImage). Dipertahankan supaya path lama tak putus.
                height: 132,
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
          )
        // Rank badge (Terlaris dsb) pakai slot kiri-atas yang sama
        // — brand badge cuma tampil kalau slot itu kosong.
        else if (productHasBrandExclusiveBadge(
          isBrandExclusive: product.voucherPreview?.isBrandExclusive,
          brand: product.brand,
        ))
          Positioned(
            left: 8,
            top: 8,
            child: BrandExclusiveBadge(
              brand: product.brand,
              full: !compact,
            ),
          ),
      ],
    );

    final infoChildren = <Widget>[
      SizedBox(
        height: nameHeight,
        child: Text(
          product.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            height: 1.25,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
      ),
      // Consumable repurchase badge — produk yang user pernah
      // beli dan sudah waktunya refill (food, pasir, vitamin, dst).
      if (!railSlim && product.isRepurchaseCandidate) ...[
        SizedBox(height: compact ? 6 : 7),
        _HomeProductRepurchaseBadge(product: product),
      ],
      SizedBox(height: compact ? 7 : 8),
      _HomeProductPriceRow(
        product: product,
        fontSize: priceFontSize,
        compact: compact,
        finalPriceOnly: railSlim,
      ),
      if (!railSlim) _HomeProductSavingBadge(product: product, compact: compact),
      _HomeProductRatingSoldRow(product: product, compact: compact),
    ];

    // squareImage: foto full-bleed di atas (nempel tepi kartu), konten di
    // bawahnya dapat padding sendiri. Non-square (rail): perilaku lama.
    final Widget cardBody = squareImage
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              imageStack,
              Padding(
                padding: EdgeInsets.fromLTRB(padding, 8, padding, padding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: infoChildren,
                ),
              ),
            ],
          )
        : Padding(
            padding: EdgeInsets.all(padding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                imageStack,
                SizedBox(height: compact ? 8 : 10),
                ...infoChildren,
              ],
            ),
          );

    return SizedBox(
      width: width,
      child: Material(
        color: cs.surface,
        borderRadius: BorderRadius.circular(cardRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(cardRadius),
              border: Border.all(color: cs.outlineVariant),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x08000000),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: cardBody,
          ),
        ),
      ),
    );
  }
}

/// Latar abu muda di belakang grid produk utama (ala Shopee — kartu putih
/// menonjol di atas kanal abu). Dark mode: surface sedikit lebih rendah
/// supaya kartu tetap terpisah.
Color _homeGridSurfaceTint(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return Theme.of(context).brightness == Brightness.dark
      ? cs.surfaceContainerLow
      : const Color(0xFFEEF1F5);
}

/// Foto produk persegi 1:1 full-bleed (BoxFit.cover) untuk grid utama —
/// gambar mengisi penuh kotak seperti Shopee. Gambar Natalo dibuat 1:1
/// sesuai spec Shopee jadi cover tidak memotong apa pun.
class _HomeProductImageSquare extends StatelessWidget {
  final String imageUrl;

  const _HomeProductImageSquare({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl.trim().isNotEmpty;
    return AspectRatio(
      aspectRatio: 1,
      child: hasImage
          ? CachedNetworkImage(
              imageUrl: imageUrl,
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.cover,
              placeholder: (_, __) =>
                  const _HomeProductImageSquarePlaceholder(),
              errorWidget: (_, __, ___) =>
                  const _HomeProductImageSquarePlaceholder(),
            )
          : const _HomeProductImageSquarePlaceholder(),
    );
  }
}

class _HomeProductImageSquarePlaceholder extends StatelessWidget {
  const _HomeProductImageSquarePlaceholder();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? cs.surfaceContainerHighest
            : const Color(0xFFF3F7FF),
      ),
      child: Center(
        child: Icon(Icons.pets_rounded, size: 34, color: cs.onSurfaceVariant),
      ),
    );
  }
}

class _HomeProductImage extends StatelessWidget {
  final String imageUrl;
  final double height;

  const _HomeProductImage({required this.imageUrl, required this.height});

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
        errorWidget: (_, __, ___) =>
            _HomeProductImagePlaceholder(height: height),
      ),
    );
  }
}

class _HomeProductImagePlaceholder extends StatelessWidget {
  final double height;

  const _HomeProductImagePlaceholder({required this.height});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? cs.surfaceContainerHighest
            : const Color(0xFFF3F7FF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Center(
        child: Icon(Icons.pets_rounded, size: 34, color: cs.onSurfaceVariant),
      ),
    );
  }
}

class _HomeProductRankBadge extends StatelessWidget {
  final int rank;

  const _HomeProductRankBadge({required this.rank});

  @override
  Widget build(BuildContext context) {
    // Redesign: biru bertingkat (#1 paling pekat → #3 paling muda) — satu
    // keluarga warna brand, bukan emas/perak/biru campur (norak + tidak
    // konsisten dgn selera badge subtle). Bentuk pill "#N" pojok, bukan
    // lingkaran mengambang.
    final color = switch (rank) {
      1 => const Color(0xFF153E7E),
      2 => const Color(0xFF3A69B0),
      _ => const Color(0xFF7D9CC9),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '#$rank',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
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
  // Rail ramping (Terlaris): tampilkan HARGA AKHIR saja — harga coret asli
  // disembunyikan supaya tinggi kartu seragam. Kalau produk diskon, harga
  // akhir tetap merah (tetap terbaca sebagai harga promo).
  final bool finalPriceOnly;

  const _HomeProductPriceRow({
    required this.product,
    required this.fontSize,
    required this.compact,
    this.finalPriceOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!product.hasDiscount || finalPriceOnly) {
      final color = product.hasDiscount
          ? const Color(0xFFE11D48)
          : Theme.of(context).colorScheme.onSurface;
      return Text(
        formatRupiah(product.finalPrice),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          color: color,
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
            color: Theme.of(context).colorScheme.onSurfaceVariant,
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

  const _HomeProductSavingBadge({required this.product, required this.compact});

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
      child: Wrap(spacing: compact ? 4 : 6, runSpacing: 4, children: badges),
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
          Icon(icon, size: compact ? 11 : 13, color: color),
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
                color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
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
            // 258: ListView horizontal butuh tinggi tetap (semua kartu
            // sebaris = seragam). Kartu ramping (railSlim) = foto 1:1 (≈150)
            // + nama 2 baris + harga akhir 1 baris + "X terjual", TANPA harga
            // coret/badge → konten seragam, tinggi turun dari 312. (Bukan
            // auto-height: horizontal wajib seragam.)
            height: 258,
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
      // Foto 1:1 cover full-bleed (spec grid) — rail Terlaris pun menonjol
      // ala Shopee. imageHeight diabaikan saat squareImage (pakai AspectRatio).
      squareImage: true,
      // Ramping: cuma foto + nama + harga akhir + terjual (buang badge Hemat/
      // Ongkir + harga coret) → semua kartu seragam, rail tak menyisakan
      // kolong kosong di bawah kartu non-diskon.
      railSlim: true,
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

    // Compute card height dari aspect ratio + screen width.
    // Spec Brand Favorit (disepakati): kartu 4:3 (childAspectRatio 4/3),
    // logo dalam BOUNDING BOX 42dp (contain, lebar maks 82%) + nama di bawah.
    // Full-tile (aspect 0.8) sebelumnya adalah workaround untuk asset logo
    // kotak-putih; sekarang asset diganti TRANSPARAN → bounding box rapi.
    // HARUS sama dengan childAspectRatio gridDelegate di bawah.
    final screenWidth = MediaQuery.sizeOf(context).width;
    final innerWidth = screenWidth - 32; // 16 padding × 2
    final cardWidth = (innerWidth - 24) / 3; // 12 spacing × 2 between 3 cols
    final cardHeight = cardWidth / (4 / 3);
    final gridHeight = (cardHeight * 2) + 12; // 2 rows + mainAxisSpacing

    return Padding(
      // 20 = ritme jarak antar-section seragam (lihat komentar _FlashSaleGrid).
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Brand Favorit',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
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
                      childAspectRatio: 4 / 3,
                    ),
                    itemCount: pageBrands.length,
                    itemBuilder: (context, idx) {
                      final brand = pageBrands[idx];
                      return BrandGridCard(
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
class BrandGridCard extends StatelessWidget {
  final PetBrand brand;
  final VoidCallback? onTap;

  const BrandGridCard({super.key, required this.brand, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
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
              // Spec: BOUNDING BOX logo tinggi 42dp, lebar maks 82% kartu,
              // BoxFit.contain center. Full-tile (Expanded) dibuang — asset
              // logo sekarang TRANSPARAN jadi ruang putih di sekeliling logo
              // normal & rapi. Flexible + maxHeight 42: normal 42dp, tapi
              // kalau ruang sempit (kartu 4:3 pendek / textScale besar) logo
              // MENGALAH supaya nama tak overflow. FractionallySizedBox
              // batasi lebar ke 82% biar wordmark lebar tak mepet tepi.
              Flexible(
                child: FractionallySizedBox(
                  widthFactor: 0.82,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 42),
                    child: BrandLogoImage(brand: brand),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                brand.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BrandLogoImage extends StatelessWidget {
  final PetBrand brand;

  const BrandLogoImage({super.key, required this.brand});

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
        errorWidget: (context, url, error) => BrandInitial(brand: brand),
      );
    }
    // 2) Image asset lokal (sampleBrands fallback)
    final imageAsset = brand.imageAsset;
    if (imageAsset != null) {
      return Image.asset(
        imageAsset,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) =>
            BrandInitial(brand: brand),
      );
    }
    // 3) Fallback: inisial huruf
    return BrandInitial(brand: brand);
  }
}

class BrandInitial extends StatelessWidget {
  final PetBrand brand;

  const BrandInitial({super.key, required this.brand});

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

  const _CategorySection({required this.categories, required this.onTap});

  // Map nama kategori → icon yang relevan. Fallback ke generic store icon.
  // Icon FALLBACK — dipakai hanya saat kategori belum punya foto produk
  // (imageUrl null). Mapping dirapikan Jul 2026: anjing dulu
  // cruelty_free_rounded (icon KELINCI, salah makna — Material tak punya
  // icon anjing) → cookie (biskuit, selaras shortcut grid); ikan
  // water→set_meal (selaras shortcut); pasir box→grain (butiran);
  // snack cookie→icecream (cookie pindah ke anjing); kandang home→fence;
  // grooming spa→gunting; shampoo dipisah→sabun; aquarium dapat water.
  static IconData _iconFor(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('kucing') && lower.contains('makanan')) {
      return Icons.pets_rounded;
    }
    if (lower.contains('anjing') && lower.contains('makanan')) {
      return Icons.cookie_rounded;
    }
    if (lower.contains('pasir') || lower.contains('litter')) {
      return Icons.grain_rounded;
    }
    if (lower.contains('vitamin') || lower.contains('obat')) {
      return Icons.medication_liquid_rounded;
    }
    if (lower.contains('snack') || lower.contains('treat')) {
      return Icons.icecream_rounded;
    }
    if (lower.contains('mainan') || lower.contains('toy')) {
      return Icons.toys_rounded;
    }
    if (lower.contains('kandang') || lower.contains('cage')) {
      return Icons.fence_rounded;
    }
    if (lower.contains('shampoo') || lower.contains('sabun')) {
      return Icons.soap_rounded;
    }
    if (lower.contains('grooming')) {
      return Icons.content_cut_rounded;
    }
    if (lower.contains('burung') || lower.contains('bird')) {
      return Icons.flutter_dash_rounded;
    }
    if (lower.contains('aquarium') || lower.contains('akuarium')) {
      return Icons.water_rounded;
    }
    if (lower.contains('ikan') || lower.contains('fish')) {
      return Icons.set_meal_rounded;
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
      // 20 = ritme jarak antar-section seragam (lihat komentar _FlashSaleGrid).
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Kategori Populer',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
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
            height: 78,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: visible.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final category = visible[index];
                return _PopularCategoryCard(
                  category: category,
                  icon: _iconFor(category.name),
                  // Kartu 76% lebar layar → kartu berikutnya "peek" sebagai
                  // affordance scroll (spec). Hard scroll-snap = follow-up.
                  width: MediaQuery.sizeOf(context).width * 0.76,
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

/// Kartu kategori horizontal (spec): thumbnail 58×58 foto produk (cover +
/// overlay putih 12%) + nama; lebar kartu ~76% layar (peek). Fallback WAJIB:
/// imageUrl null / gambar rusak → icon kategori di latar biru muda.
class _PopularCategoryCard extends StatelessWidget {
  final HomeCategory category;
  final IconData icon;
  final double width;
  final VoidCallback onTap;

  const _PopularCategoryCard({
    required this.category,
    required this.icon,
    required this.width,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Fallback thumbnail (spec WAJIB) — imageUrl null ATAU gambar rusak/
    // cache-miss → icon kategori di latar biru muda, BUKAN broken image /
    // kotak abu kosong.
    Widget fallback() => ColoredBox(
          color: scheme.primary.withValues(alpha: 0.10),
          child: Center(child: Icon(icon, color: scheme.primary, size: 26)),
        );

    // Thumbnail: foto produk kategori (server kirim imageUrl = produk
    // TERBARU). CachedNetworkImage langsung (bukan AppProductImage) supaya
    // errorWidget → fallback icon. Overlay putih 12% meredam foto promo
    // yang mencolok (spec). cover-crop karena rasio foto tak konsisten.
    final url = category.imageUrl;
    final Widget thumb = (url != null && url.isNotEmpty)
        ? Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 180),
                placeholder: (_, __) => fallback(),
                errorWidget: (_, __, ___) => fallback(),
              ),
              const ColoredBox(color: Color(0x1FFFFFFF)),
            ],
          )
        : fallback();

    return SizedBox(
      width: width,
      child: Material(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: thumb,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    category.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
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

// _CategoryCard + _CategoryFallback dihapus — diganti dengan
// _PopularCategoryCard (icon + name horizontal row) di atas.

class _RecommendationGrid extends StatelessWidget {
  final List<Product> products;
  final ValueChanged<Product> onTap;

  const _RecommendationGrid({required this.products, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 24, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Rekomendasi Untuk Kamu',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          // Grid 2-kolom AUTO-HEIGHT (bukan GridView dengan childAspectRatio
          // tetap). Sebelumnya 0.54 dipaku → kartu dengan diskon + 2 badge
          // (ongkir+hemat, wrap 2 baris) + rating overflow ~8-9px. Sama
          // root cause & fix dengan section "Jelajahi Produk Natalo" —
          // lihat catatan lengkap di sana.
          //
          // BUKAN CrossAxisAlignment.stretch: stretch di Row memaksa
          // Flutter hitung intrinsic-height _HomeProductCard, yang
          // menyebabkan layout exception. FlutterError.onError custom di
          // app ini tidak memanggil FlutterError.presentError, jadi
          // exception itu tidak tercetak sama sekali — hasilnya SELURUH
          // Beranda blank tanpa jejak error apa pun. Kedua kartu di satu
          // baris kebetulan hampir selalu sama tinggi, jadi tanpa stretch
          // pun rapi secara visual.
          for (var i = 0; i < (products.length + 1) ~/ 2; i++)
            Padding(
              padding: EdgeInsets.only(
                bottom: i == ((products.length + 1) ~/ 2) - 1 ? 0 : 6,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _HomeProductCard(
                      product: products[i * 2],
                      squareImage: true,
                      onTap: () => onTap(products[i * 2]),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: i * 2 + 1 < products.length
                        ? _HomeProductCard(
                            product: products[i * 2 + 1],
                            squareImage: true,
                            onTap: () => onTap(products[i * 2 + 1]),
                          )
                        // Jumlah ganjil — slot kanan kosong, kartu kiri
                        // tetap selebar 1 kolom.
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ShortcutItem {
  final IconData icon;
  final String label;
  // Warna solid lingkaran tile (icon-nya putih) — redesign "circle warna"
  // Jul 2026; field `background` tint lama dihapus bersama gaya squircle.
  final Color color;
  // Optional glyph SVG (putih) — dipakai kalau Material Icons TAK punya
  // bentuk yang pas (mis. TULANG untuk Makanan Anjing; Material cuma punya
  // kelinci/cookie). Kalau null → render `icon`. `icon` tetap wajib sbg
  // fallback kalau aset SVG gagal load.
  final String? iconAsset;
  // Optional per-item handler. Kalau null, _ShortcutGrid pakai default
  // (onOpenProducts). Pattern ini supaya tiap shortcut bisa navigate ke
  // destination berbeda tanpa harus refactor grid widget.
  final void Function(BuildContext context)? onTap;

  const _ShortcutItem(
    this.icon,
    this.label,
    this.color, {
    this.iconAsset,
    this.onTap,
  });
}

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/natalo_colors.dart';

// sample_products dihapus dari import — products screen sekarang pure
// API-driven dari Capacitor backend. Loading state pakai skeleton grid,
// error state pakai banner + pull-to-refresh.
import '../models/product.dart';
import '../models/home_category.dart';
import '../services/product_service.dart';
import '../state/recently_viewed_store.dart';
import '../state/search_history_store.dart';
import '../utils/formatters.dart';
import '../utils/search_synonyms.dart';
import '../widgets/app_cart_button.dart';
import '../widgets/app_product_image.dart';
import '../widgets/app_ui.dart';
import '../widgets/skeleton_product_card.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/natalo_paw_refresh_indicator.dart';

const _brandBlue = NataloColors.nataloBlue;

/// Format raw category slug ke label readable. Defensive helper — kalau
/// backend Capacitor return slug-style (mis. `snack-treat-anjing`) langsung,
/// formatter ini auto-translate ke label rapi sebelum di-display.
///
/// Map dictionary di-prioritaskan; kalau tidak match, fallback ke
/// title-case dari split("-").
///
/// Aman dipanggil walau backend sudah return label rapi (mis. "Makanan
/// Kucing") — string tanpa `-` lewat fallback tidak akan diubah.
String formatCategoryLabel(String raw) {
  const map = {
    'semua': 'Semua',
    'aksesoris-perlengkapan': 'Aksesoris & Perlengkapan',
    'aquarium-kolam': 'Aquarium & Kolam',
    'kesehatan-vitamin-anjing': 'Vitamin Anjing',
    'kesehatan-vitamin-kucing': 'Vitamin Kucing',
    'makanan-ikan': 'Makanan Ikan',
    'makanan-kucing': 'Makanan Kucing',
    'makanan-anjing': 'Makanan Anjing',
    'peralatan-aquarium': 'Peralatan Aquarium',
    'snack-treat-anjing': 'Snack & Treat Anjing',
    'snack-treat-kucing': 'Snack & Treat Kucing',
  };
  final key = raw.trim().toLowerCase();
  if (map.containsKey(key)) return map[key]!;
  // Kalau sudah label rapi (mis. "Makanan Kucing"), return as-is.
  if (!raw.contains('-')) return raw;
  return raw
      .split('-')
      .where((word) => word.trim().isNotEmpty)
      .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
      .join(' ');
}

class ProductsScreen extends StatefulWidget {
  final String? selectedBrand;
  final String? initialQuery;
  final String? initialCategory;
  final bool discountOnly;
  final bool flashSaleOnly;
  final bool newestOnly;

  const ProductsScreen({
    super.key,
    this.selectedBrand,
    this.initialQuery,
    this.initialCategory,
    this.discountOnly = false,
    this.flashSaleOnly = false,
    this.newestOnly = false,
  });

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  static const _historyKey = 'natalo_search_history';

  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _searchDebounce;
  String _query = '';
  SearchSuggestionResult _suggestions = const SearchSuggestionResult();
  List<String> _searchHistory = const [];
  bool _suggestionLoading = false;
  // Gate untuk render suggestion panel — true HANYA saat user aktif
  // mengetik di search field, false setelah commit/apply/reset supaya
  // tidak ada gap kosong + icon search ngambang di antara filter chips
  // dan product grid (bug visual yang user report: "ruang kosong besar
  // di tengah halaman + icon search/panah melayang"). Sebelumnya panel
  // pake `query.length >= 2` doang → tetap show setelah commit search.
  bool _showSuggestionPanel = false;
  ProductCatalogFilter _filter = const ProductCatalogFilter();
  // Active filter mode untuk pinned glassy bar: semua/kategori/baru/populer.
  // State terpisah dari _filter karena UI bar pakai single-select pills.
  _ProductFilterMode _activeMode = _ProductFilterMode.semua;
  // Initial result empty — skeleton akan render until API responds. Tidak
  // pakai sampleProducts mock supaya tidak flash data palsu.
  ProductResult _result = const ProductResult(
    products: <Product>[],
    fromApi: false,
  );
  bool _loading = false;
  // Cursor-based infinite scroll — proper pagination yang scale ke
  // dataset besar (2000+ produk). Sebelumnya limit-incrementing
  // (`_pageLimit += 24`) yang capped di 200 backend → customer stuck
  // di 200 produk. Sekarang fetch batch 24 per request, lanjut dari
  // cursor terakhir → no ceiling.
  static const int _pageSize = 24;
  String? _nextCursor;
  bool _loadingMore = false;
  bool _hasMore = true;
  // BUGFIX(audit): epoch token cegah stale-future race. _loadProducts
  // increment epoch (reset point saat filter/query berubah); _loadMore &
  // _loadProducts capture epoch di awal & buang hasil kalau epoch berubah
  // saat await (request lama datang belakangan menimpa state baru).
  int _loadEpoch = 0;
  // Daftar kategori MASTER dari /api/categories (semua kategori yang punya
  // produk aktif + jumlahnya). Dipakai untuk isi filter sheet — sebelumnya
  // sheet derive dari produk yang KEBETULAN ter-load (page 1 = 24 produk),
  // jadi cuma muncul 2 kategori walau DB punya 20. Fallback ke derived
  // (_categories) kalau fetch master gagal.
  List<HomeCategory> _allCategories = const [];
  // ── Catalog rotation state — persisted via SharedPreferences ──
  //
  // Sebelumnya state in-memory only → reset tiap app restart, navigate
  // away, atau iOS background-kill. User per session selalu lihat
  // "fresh ordering" — tapi inconsistent: tap 2 produk hari ini,
  // restart, tap lagi → counter restart dari 0, padahal user kira
  // sudah dekat ke regenerate threshold.
  //
  // Sekarang persist ke SharedPreferences supaya:
  // - Counter survive app kill/restart → user trust progress menuju
  //   regenerate next.
  // - Generation salt survive → ordering pattern stay konsisten
  //   across sessions, tidak completely random saat reopen.
  // - Reset hanya happen at threshold (3 atau 4) atau via clear cache.
  static const _kKeyCatalogGeneration = 'products_catalog_generation';
  static const _kKeyProductReturnCount = 'products_return_count';
  static const _kKeyNextRegenerateAt = 'products_next_regenerate_at';
  int _catalogGeneration = 0;
  int _productReturnCount = 0;
  // Alternate 3 ↔ 4 (per user spec) — regenerate ordering setiap user
  // tap dan kembali 3-4 produk. Variable threshold supaya user tidak
  // bisa predict timing (always "feels fresh").
  int _nextCatalogRegenerateAt = 3;
  bool _rotationStateLoaded = false;

  bool get _shouldGenerateAllProducts {
    return widget.selectedBrand == null &&
        _activeMode == _ProductFilterMode.semua &&
        _query.trim().isEmpty &&
        _filter.category == null &&
        _filter.brand == null &&
        _filter.sort == ProductSort.newest &&
        _filter.inStockOnly &&
        !_filter.discountOnly &&
        !_filter.withImageOnly &&
        !widget.flashSaleOnly;
  }

  List<String> get _categories {
    final values = _result.products
        .map((product) => product.category)
        .toSet()
        .toList()
      ..sort();
    return values;
  }

  List<Product> get _products {
    final keyword = _query.trim().toLowerCase();
    final selectedBrandLc = widget.selectedBrand?.toLowerCase();
    final filterBrandLc = _filter.brand?.toLowerCase();
    final filtered = _result.products.where((product) {
      // Brand filter case-insensitive — defensive guard. Server SUDAH filter
      // by slug/name (lihat _loadProducts), tapi client compare jaga-jaga
      // kalau ada produk lolos dari server filter karena cache stale atau
      // data anomaly. Tanpa lowercase, "Whiskas" != "WHISKAS" → produk hilang.
      final productBrandLc = product.brand.toLowerCase();
      final brandMatch =
          selectedBrandLc == null || productBrandLc == selectedBrandLc;
      final filterBrandMatch =
          filterBrandLc == null || productBrandLc == filterBrandLc;
      // Kategori sudah difilter SERVER-SIDE di _loadProducts (lihat sana).
      // JANGAN filter lagi di client: _filter.category bisa berisi nama
      // ("Makanan Kucing") dari home chip sedang product.category = slug
      // ("makanan-kucing") → kalau dibandingkan langsung, semua produk
      // ke-filter habis walau server sudah kembalikan yang benar.
      const categoryMatch = true;
      final stockMatch = !_filter.inStockOnly || product.stock > 0;
      final discountMatch = !_filter.discountOnly || product.hasDiscount;
      final flashSaleMatch =
          !widget.flashSaleOnly || product.isFlashSaleEligible;
      // Search Filters extension — advanced filter from _FilterSheet:
      // multi-brand, price range, rating. Cek pakai finalPrice
      // (consider discount) supaya user yang filter "<50rb" tetap
      // dapat produk normal Rp80rb yang lagi diskon ke Rp40rb.
      final multiBrandMatch =
          _filter.brands.isEmpty || _filter.brands.contains(product.brand);
      final priceForFilter = product.finalPrice;
      final minPriceMatch =
          _filter.minPrice == null || priceForFilter >= _filter.minPrice!;
      final maxPriceMatch =
          _filter.maxPrice == null || priceForFilter <= _filter.maxPrice!;
      final ratingMatch =
          _filter.minRating == 0 || product.rating >= _filter.minRating;
      // Smart match dengan synonym expansion — "anjing" cocok produk
      // yang title-nya "dog food", "rc" cocok "Royal Canin", dll.
      // Search di title + brand + category sekaligus.
      final searchableText = [
        product.title,
        product.brand,
        product.category,
      ].join(' ');
      final keywordMatch =
          keyword.isEmpty || SearchSynonyms.matches(searchableText, keyword);

      return brandMatch &&
          filterBrandMatch &&
          categoryMatch &&
          stockMatch &&
          discountMatch &&
          flashSaleMatch &&
          multiBrandMatch &&
          minPriceMatch &&
          maxPriceMatch &&
          ratingMatch &&
          keywordMatch;
    }).toList();

    if (_shouldGenerateAllProducts) {
      return _generateAllProducts(filtered);
    }
    return _sortProducts(filtered);
  }

  @override
  void initState() {
    super.initState();
    final initialQuery = widget.initialQuery?.trim() ?? '';
    if (initialQuery.isNotEmpty) {
      _query = initialQuery;
      _searchController.text = initialQuery;
      _searchController.selection = TextSelection.fromPosition(
        TextPosition(offset: initialQuery.length),
      );
    }
    final initialCategory = widget.initialCategory?.trim() ?? '';
    // Guard sama seperti _onCategorySelected: "Semua" bukan nama kategori
    // asli — server tidak punya kategori bernama "Semua" (return total:0
    // kalau dikirim literal). Bisa masuk lewat deep link (?kategori=Semua)
    // atau share link — tanpa guard ini, halaman Produk kosong walau
    // Beranda (yang tidak kena filter ini) tetap normal.
    if (initialCategory.isNotEmpty && initialCategory.toLowerCase() != 'semua') {
      _filter = _filter.copyWith(category: initialCategory);
    }
    if (widget.discountOnly) {
      _filter = _filter.copyWith(discountOnly: true);
      _activeMode = _ProductFilterMode.semua;
    }
    // Shortcut "Produk Baru" → buka langsung mode terbaru (sort newest +
    // pill "Produk Baru" aktif + newArrivalsOnly true supaya server terapkan
    // cutoff 30-hari — lihat catatan di apiNewFilter).
    if (widget.newestOnly) {
      _filter = _filter.copyWith(
        sort: ProductSort.newest,
        clearCategory: true,
        newArrivalsOnly: true,
      );
      _activeMode = _ProductFilterMode.baru;
    }
    _scrollController.addListener(_onScroll);
    _loadSearchHistory();
    _loadRotationState();
    _loadAllCategories();
    _loadProducts();
  }

  /// Fetch daftar kategori master (/api/categories) untuk filter sheet.
  /// Fire-and-forget — kalau gagal, sheet fallback ke kategori yang
  /// ter-derive dari produk ter-load (_categories getter).
  Future<void> _loadAllCategories() async {
    try {
      final cats = await productService.fetchCategories();
      if (!mounted) return;
      setState(() => _allCategories = cats);
    } catch (_) {
      // Diam — fallback derived categories tetap jalan.
    }
  }

  /// Load persisted rotation counter + catalog generation dari prefs.
  /// Fire-and-forget — kalau gagal/disk corrupt, pakai default values
  /// (counter=0, generation=0, threshold=3) — first session behavior.
  Future<void> _loadRotationState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _catalogGeneration = prefs.getInt(_kKeyCatalogGeneration) ?? 0;
        _productReturnCount = prefs.getInt(_kKeyProductReturnCount) ?? 0;
        final saved = prefs.getInt(_kKeyNextRegenerateAt) ?? 3;
        // Clamp ke 3 atau 4 — defense kalau prefs corrupt nilai weird.
        _nextCatalogRegenerateAt = (saved == 3 || saved == 4) ? saved : 3;
        _rotationStateLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _rotationStateLoaded = true);
    }
  }

  /// Persist rotation state ke disk. Best-effort fire-and-forget — kalau
  /// disk write gagal, state in-memory tetap update (next launch fallback
  /// ke default kalau prefs unreadable).
  Future<void> _persistRotationState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kKeyCatalogGeneration, _catalogGeneration);
      await prefs.setInt(_kKeyProductReturnCount, _productReturnCount);
      await prefs.setInt(_kKeyNextRegenerateAt, _nextCatalogRegenerateAt);
    } catch (_) {
      // Silent fail — in-memory state masih valid.
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// Scroll listener — saat user near bottom (<600px to end) dan masih ada
  /// data + tidak sedang loading, fire load more. Threshold 600px supaya
  /// fetch lebih awal sebelum user lihat empty space.
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_loadingMore || _loading || !_hasMore) return;
    final position = _scrollController.position;
    if (position.maxScrollExtent - position.pixels < 600) {
      _loadMore();
    }
  }

  /// Load next page via cursor. Append produk ke list existing.
  /// Stop kalau response nextCursor null (no more pages).
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _nextCursor == null) return;
    final epoch = _loadEpoch;
    setState(() => _loadingMore = true);
    final result = await productService.fetchProducts(
      query: _query,
      limit: _pageSize,
      cursor: _nextCursor,
      // Kategori & brand difilter SERVER-SIDE. Backend sekarang accept
      // brand by slug ATAU name (case-insensitive) — fix di
      // lib/products.ts:974. Tanpa ini, brand cuma di-filter client dari
      // produk ter-load page-N → pilih brand kecil = 0 hasil walau ada
      // produk-nya. selectedBrand prioritas (dari home tap Brand Favorit),
      // _filter.brand fallback (dari filter sheet single-brand picker).
      category: _filter.category,
      brand: widget.selectedBrand ?? _filter.brand,
      newFilter: _filter.apiNewFilter,
      popularFilter: _filter.apiPopularFilter,
      inStock: _filter.inStockOnly,
      withImage: _filter.withImageOnly,
      discountOnly: widget.flashSaleOnly || _filter.discountOnly,
    );
    // Stale guard: filter/query berubah saat fetch in-flight (_loadProducts
    // increment epoch) → JANGAN append hasil lama ke list baru + JANGAN
    // timpa _nextCursor dengan cursor lama. Buang diam-diam.
    if (!mounted || epoch != _loadEpoch) {
      if (mounted) _loadingMore = false;
      return;
    }
    setState(() {
      // Append produk baru ke list existing.
      _result = ProductResult(
        products: [..._result.products, ...result.products],
        nextCursor: result.nextCursor,
        fromApi: result.fromApi,
        total: result.total,
        error: result.error,
      );
      _nextCursor = result.nextCursor;
      _hasMore = result.nextCursor != null;
      _loadingMore = false;
    });
  }

  /// Load halaman pertama. Reset cursor + accumulator.
  Future<void> _loadProducts() async {
    // Increment epoch → invalidasi _loadMore / _loadProducts lama yang masih
    // in-flight. Reset _loadingMore juga supaya tidak stuck kalau ada
    // loadMore yang ke-buang oleh stale-guard.
    final epoch = ++_loadEpoch;
    setState(() {
      _loading = true;
      // Reset pagination saat filter/query change.
      _nextCursor = null;
      _hasMore = true;
      _loadingMore = false;
    });
    final result = await productService.fetchProducts(
      query: _query,
      limit: _pageSize,
      // cursor: null → fetch dari awal
      category: _filter.category,
      // Brand server-side (sama logic dengan _loadMore — lihat komentar di sana).
      brand: widget.selectedBrand ?? _filter.brand,
      newFilter: _filter.apiNewFilter,
      popularFilter: _filter.apiPopularFilter,
      inStock: _filter.inStockOnly,
      withImage: _filter.withImageOnly,
      discountOnly: widget.flashSaleOnly || _filter.discountOnly,
    );
    // Stale guard: kalau filter/query berubah lagi saat fetch in-flight
    // (epoch ber-increment), buang hasil lama — response yang datang
    // belakangan tidak boleh menimpa hasil filter terbaru.
    if (!mounted || epoch != _loadEpoch) return;
    setState(() {
      _result = result;
      _nextCursor = result.nextCursor;
      _hasMore = result.nextCursor != null;
      _loading = false;
    });
  }

  /// Handle tap pada pinned filter bar pill. Mapping mode → filter flags:
  /// - Semua: reset semua flag
  /// - Kategori: buka bottom sheet kategori
  /// - Produk Baru: set apiNewFilter
  /// - Populer: set apiPopularFilter
  void _onFilterModeChanged(_ProductFilterMode mode) {
    if (mode == _ProductFilterMode.kategori) {
      _openCategoryBottomSheet();
      return;
    }
    if (_activeMode == mode) return;
    setState(() {
      _activeMode = mode;
      switch (mode) {
        case _ProductFilterMode.semua:
          _filter = const ProductCatalogFilter();
          break;
        case _ProductFilterMode.kategori:
          // Tetap pertahankan filter category yang sudah dipilih kalau ada.
          // newArrivalsOnly: false — browsing kategori bukan "produk baru".
          _filter = _filter.copyWith(
            sort: ProductSort.newest,
            newArrivalsOnly: false,
          );
          break;
        case _ProductFilterMode.baru:
          _filter = _filter.copyWith(
            sort: ProductSort.newest,
            clearCategory: true,
            newArrivalsOnly: true,
          );
          break;
        case _ProductFilterMode.populer:
          _filter = _filter.copyWith(
            sort: ProductSort.popular,
            clearCategory: true,
            newArrivalsOnly: false,
          );
          break;
      }
    });
    _loadProducts();
  }

  Future<void> _refreshAll() async {
    await _loadProducts();
  }

  void _resetFilters() {
    setState(() {
      _query = '';
      _searchController.clear();
      _suggestions = const SearchSuggestionResult();
      _filter = const ProductCatalogFilter();
      _activeMode = _ProductFilterMode.semua;
      _showSuggestionPanel = false;
    });
    _loadProducts();
  }

  void _onQueryChanged(String value) {
    setState(() {
      _query = value;
      // Panel open ketika user actively typing (apapun text yang ada).
      // Auto-close kalau field di-clear ke kosong.
      _showSuggestionPanel = value.isNotEmpty;
    });
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 360), () {
      _loadProducts();
      _loadSuggestions(value);
    });
  }

  Future<void> _loadSuggestions(String value) async {
    final keyword = value.trim();
    if (keyword.length < 2) {
      if (!mounted) return;
      setState(() {
        _suggestions = const SearchSuggestionResult();
        _suggestionLoading = false;
      });
      return;
    }

    setState(() => _suggestionLoading = true);
    // Pass filter kategori/brand aktif → suggestion konsisten dengan grid
    // (Opsi C). selectedBrand prioritas (dari home tap Brand Favorit),
    // _filter.brand fallback (dari filter sheet).
    final suggestions = await productService.fetchSuggestions(
      keyword,
      category: _filter.category,
      brand: widget.selectedBrand ?? _filter.brand,
    );
    if (!mounted || _query.trim() != keyword) return;
    setState(() {
      _suggestions = suggestions;
      _suggestionLoading = false;
    });
  }

  Future<void> _loadSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList(_historyKey) ?? const [];
    if (!mounted) return;
    setState(() => _searchHistory = history.take(6).toList());
  }

  Future<void> _saveSearch(String value) async {
    final keyword = value.trim();
    if (keyword.isEmpty) return;
    final next = [
      keyword,
      ..._searchHistory.where(
        (item) => item.toLowerCase() != keyword.toLowerCase(),
      ),
    ].take(6).toList();
    setState(() => _searchHistory = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_historyKey, next);
    // Sync ke global searchHistoryStore (versioned key `search_history_v1`)
    // supaya Home "Rekomendasi Untukmu" bisa pakai search behavior user
    // untuk personalized scoring. Fire-and-forget — kalau gagal, fallback
    // ke recently-viewed-based ranking saja.
    searchHistoryStore.push(keyword);
  }

  Future<void> _clearSearchHistory() async {
    setState(() => _searchHistory = const []);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
  }

  Future<void> _commitSearch(String value) async {
    final keyword = value.trim();
    if (keyword.isEmpty) return;
    _searchController.text = keyword;
    setState(() {
      _query = keyword;
      _suggestions = const SearchSuggestionResult();
      // Setelah commit search → suggestion panel tutup. Grid produk
      // muncul langsung di bawah filter chips tanpa gap kosong.
      _showSuggestionPanel = false;
    });
    // Hapus focus dari search field supaya keyboard tutup + tidak
    // re-trigger panel via focus listener (kalau ada di masa depan).
    FocusManager.instance.primaryFocus?.unfocus();
    await _saveSearch(keyword);
    await _loadProducts();
  }

  /// Tap product suggestion → buka product detail LANGSUNG (Opsi A).
  /// Sebelumnya _commitSearch(item.name) → cari nama produk dalam filter
  /// aktif, bisa 0 hasil (produk beda kategori dari filter). Suggestion
  /// sudah identify produk spesifik via slug → fetch + buka detail.
  /// Fallback: kalau slug gagal fetch (produk dihapus / network), jatuh
  /// ke _commitSearch(name) sebagai degradasi.
  Future<void> _openProductSuggestion(ProductSuggestion item) async {
    setState(() {
      _suggestions = const SearchSuggestionResult();
      _showSuggestionPanel = false;
    });
    FocusManager.instance.primaryFocus?.unfocus();
    await _saveSearch(item.name);
    if (!mounted) return;

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
      product = await productService.fetchProductBySlug(item.slug);
    } catch (_) {
      product = null;
    }

    rootNav.pop(); // tutup loading dialog
    if (!mounted) return;

    if (product == null) {
      // Slug gagal fetch — degradasi ke search by name.
      await _commitSearch(item.name);
      return;
    }
    await Navigator.pushNamed(context, '/product-detail', arguments: product);
  }

  void _applySuggestedCategory(String name) {
    setState(() {
      _filter = _filter.copyWith(category: name);
      _suggestions = const SearchSuggestionResult();
      _showSuggestionPanel = false;
    });
    FocusManager.instance.primaryFocus?.unfocus();
    _loadProducts();
  }

  void _applySuggestedBrand(String name) {
    setState(() {
      _filter = _filter.copyWith(brand: name);
      _suggestions = const SearchSuggestionResult();
      _showSuggestionPanel = false;
    });
    FocusManager.instance.primaryFocus?.unfocus();
    _loadProducts();
  }

  List<Product> _sortProducts(List<Product> products) {
    final sorted = [...products];
    switch (_filter.sort) {
      case ProductSort.priceLow:
        sorted.sort((a, b) => a.finalPrice.compareTo(b.finalPrice));
        break;
      case ProductSort.priceHigh:
        sorted.sort((a, b) => b.finalPrice.compareTo(a.finalPrice));
        break;
      case ProductSort.rating:
        sorted.sort((a, b) {
          final rating = b.rating.compareTo(a.rating);
          return rating == 0 ? b.reviewCount.compareTo(a.reviewCount) : rating;
        });
        break;
      case ProductSort.popular:
        // API `/api/products?popular=best-seller` sudah memberi ranking
        // rolling 7 hari dari order user. Jangan sort ulang di client,
        // supaya urutan "Populer" tetap mengikuti data pembelian terbaru.
        break;
      case ProductSort.newest:
        break;
    }
    return sorted;
  }

  Future<void> _openCategoryBottomSheet() async {
    FocusScope.of(context).unfocus();
    // Sumber utama: kategori master dari /api/categories (semua kategori
    // dengan produk aktif). Fallback ke kategori derive-dari-produk-terload
    // kalau master belum/ gagal ke-fetch. Value = slug; label di sheet
    // diformat via formatCategoryLabel.
    final masterSlugs = _allCategories
        .where((c) => c.productCount > 0)
        .map((c) => c.slug)
        .toList();
    final categories = [
      'Semua',
      ...(masterSlugs.isNotEmpty ? masterSlugs : _categories),
    ];
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.25),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.58,
          minChildSize: 0.35,
          maxChildSize: 0.85,
          expand: false,
          builder: (context, scrollController) {
            return _CategoryBottomSheet(
              scrollController: scrollController,
              selectedCategory: _filter.category,
              categories: categories,
              onSelected: (category) => Navigator.pop(context, category),
            );
          },
        );
      },
    );

    if (picked == null || !mounted) return;
    _onCategorySelected(picked);
  }

  void _onCategorySelected(String category) {
    setState(() {
      if (category == 'Semua') {
        _filter = const ProductCatalogFilter();
        _activeMode = _ProductFilterMode.semua;
      } else {
        _filter = _filter.copyWith(
          category: category,
          sort: ProductSort.newest,
          newArrivalsOnly: false,
        );
        _activeMode = _ProductFilterMode.kategori;
      }
    });
    _loadProducts();
  }

  Future<void> _openSortSheet() async {
    FocusScope.of(context).unfocus();
    final picked = await showModalBottomSheet<ProductSort>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SortBottomSheet(currentSort: _filter.sort),
    );
    if (picked == null || picked == _filter.sort) return;
    setState(() => _filter = _filter.copyWith(sort: picked));
    _loadProducts();
  }

  /// Open advanced Filter Sheet — price range, multi-brand, rating,
  /// promo/in-stock toggles. Returns updated filter via Navigator.pop.
  /// Sheet computes live preview count saat user toggle.
  Future<void> _openFilterSheet() async {
    FocusScope.of(context).unfocus();
    // Get all unique brands dari current loaded products untuk multi-
    // select brand list. Sort alphabetically untuk UX consistent.
    final allBrands = _result.products
        .map((p) => p.brand.trim())
        .where((b) => b.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    // Compute price range bounds dari product data (max price untuk
    // RangeSlider upper bound). Round up ke nearest 100k untuk UX
    // smooth slider.
    final maxProductPrice = _result.products.isEmpty
        ? 1000000.0
        : _result.products.map((p) => p.price).reduce((a, b) => a > b ? a : b);
    final priceMaxBound = ((maxProductPrice / 100000).ceil() * 100000)
        .clamp(100000, 10000000)
        .toDouble();

    final result = await showModalBottomSheet<ProductCatalogFilter>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _FilterSheet(
        currentFilter: _filter,
        allBrands: allBrands,
        priceMaxBound: priceMaxBound,
        // Live preview count — closure ke parent state supaya tetap
        // hitung filter result terbaru tiap toggle di sheet.
        previewCountForFilter: (filter) => _previewFilterMatchCount(filter),
      ),
    );
    if (result == null) return;
    setState(() => _filter = result);
    _loadProducts();
  }

  /// Hitung berapa produk yang match dengan filter candidate (untuk
  /// live preview di apply button). Same logic dengan `_products`
  /// getter, tapi terima filter parameter custom.
  int _previewFilterMatchCount(ProductCatalogFilter filter) {
    final keyword = _query.trim().toLowerCase();
    final selectedBrandLc = widget.selectedBrand?.toLowerCase();
    final filterBrandLc = filter.brand?.toLowerCase();
    var count = 0;
    for (final product in _result.products) {
      final productBrandLc = product.brand.toLowerCase();
      final brandMatch =
          selectedBrandLc == null || productBrandLc == selectedBrandLc;
      final filterBrandMatch =
          filterBrandLc == null || productBrandLc == filterBrandLc;
      final categoryMatch =
          filter.category == null || product.category == filter.category;
      final stockMatch = !filter.inStockOnly || product.stock > 0;
      final discountMatch = !filter.discountOnly || product.hasDiscount;
      final multiBrandMatch =
          filter.brands.isEmpty || filter.brands.contains(product.brand);
      final priceForFilter = product.finalPrice;
      final minPriceMatch =
          filter.minPrice == null || priceForFilter >= filter.minPrice!;
      final maxPriceMatch =
          filter.maxPrice == null || priceForFilter <= filter.maxPrice!;
      final ratingMatch =
          filter.minRating == 0 || product.rating >= filter.minRating;
      final searchableText = [
        product.title,
        product.brand,
        product.category,
      ].join(' ');
      final keywordMatch =
          keyword.isEmpty || SearchSynonyms.matches(searchableText, keyword);
      if (brandMatch &&
          filterBrandMatch &&
          categoryMatch &&
          stockMatch &&
          discountMatch &&
          multiBrandMatch &&
          minPriceMatch &&
          maxPriceMatch &&
          ratingMatch &&
          keywordMatch) {
        count++;
      }
    }
    return count;
  }

  /// Remove individual active filter chip — restore default for that field.
  void _removeFilterChip({
    bool clearMinPrice = false,
    bool clearMaxPrice = false,
    String? removeBrand,
    bool clearMinRating = false,
    bool clearDiscount = false,
    bool restoreInStock = false,
  }) {
    setState(() {
      var next = _filter;
      if (clearMinPrice) next = next.copyWith(clearMinPrice: true);
      if (clearMaxPrice) next = next.copyWith(clearMaxPrice: true);
      if (removeBrand != null) {
        next = next.copyWith(
          brands: next.brands.where((b) => b != removeBrand).toSet(),
        );
      }
      if (clearMinRating) next = next.copyWith(minRating: 0);
      if (clearDiscount) next = next.copyWith(discountOnly: false);
      if (restoreInStock) next = next.copyWith(inStockOnly: true);
      _filter = next;
    });
    _loadProducts();
  }

  /// Clear all advanced filters back to default — but keep search query,
  /// category, brand single chips (those are managed via _activeMode).
  void _clearAllAdvancedFilters() {
    setState(() {
      _filter = _filter.copyWith(
        clearMinPrice: true,
        clearMaxPrice: true,
        brands: const {},
        minRating: 0,
        discountOnly: false,
        inStockOnly: true,
      );
    });
    _loadProducts();
  }

  List<Product> _generateAllProducts(List<Product> products) {
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
        final scoreCompare = _generatedProductScore(
          b,
          brandScores,
          categoryScores,
        ).compareTo(
          _generatedProductScore(a, brandScores, categoryScores),
        );
        if (scoreCompare != 0) return scoreCompare;
        return _stableCatalogHash(a.id).compareTo(_stableCatalogHash(b.id));
      });
    return generated;
  }

  int _generatedProductScore(
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
    score += _stableCatalogHash(product.id) % 7;
    return score;
  }

  int _stableCatalogHash(String value) {
    var hash = 0x811C9DC5 ^ _catalogGeneration;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }

  void _openProduct(Product product) {
    // Preload images sebelum navigate → product detail render instant.
    // Native superpower: precacheImage warms ImageCache, jadi widget
    // ProductDetailScreen langsung dapat hit cache di first build.
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
        .whenComplete(_maybeRegenerateCatalogAfterReturn);
  }

  void _maybeRegenerateCatalogAfterReturn() {
    if (!mounted || !_shouldGenerateAllProducts) return;
    if (!_rotationStateLoaded) return; // wait until prefs hydrated
    _productReturnCount += 1;
    if (_productReturnCount < _nextCatalogRegenerateAt) {
      // Counter < threshold — persist incremented count saja, no
      // re-shuffle. User next session bisa lanjut dari sini.
      _persistRotationState();
      return;
    }
    setState(() {
      _catalogGeneration += 1;
      _productReturnCount = 0;
      // Alternate 3 ↔ 4 per user spec — variable threshold supaya feel
      // fresh + unpredictable. Pakai 3 vs 4 (was 2 vs 3) supaya user
      // bisa scroll lebih lama tanpa shuffle terlalu sering.
      _nextCatalogRegenerateAt = _nextCatalogRegenerateAt == 3 ? 4 : 3;
    });
    // Persist state baru setelah shuffle: generation++, count=0, threshold flipped.
    _persistRotationState();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final products = _products;
    final hasLoadError =
        !_result.fromApi && _result.error != null && products.isEmpty;
    final bottomPadding =
        kBottomNavigationBarHeight + MediaQuery.paddingOf(context).bottom + 16;

    return Scaffold(
      backgroundColor: cs.surface,
      // extendBody: konten tembus di belakang floating glass nav. Grid
      // sudah pakai bottomPadding (kBottomNavigationBarHeight + inset + 16).
      extendBody: true,
      body: NataloPawRefreshIndicator(
        onRefresh: _refreshAll,
        child: SafeArea(
          bottom: false,
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              const SliverToBoxAdapter(child: _ProductPageHeader()),
              SliverPersistentHeader(
                pinned: true,
                delegate: _PinnedHeaderDelegate(
                  // Extent disesuaikan: search 44 + gap 10 + count row 40 +
                  // gap 10 + chip 46 + bottom gap 12 + top padding 12 = ~174
                  minExtent: 174,
                  maxExtent: 174,
                  child: _CatalogHeader(
                    controller: _searchController,
                    query: _query,
                    activeMode: _activeMode,
                    selectedCategory: _filter.category,
                    visibleCount: products.length,
                    // Total dari API (jumlah produk sesuai filter di DB),
                    // bukan jumlah yang kebetulan ter-load. Tanpa ini header
                    // selalu tampil "24" walau DB punya ribuan → "dari N"
                    // tidak pernah muncul. Fallback ke loaded length kalau
                    // API tidak kirim total.
                    totalCount: _result.total ?? _result.products.length,
                    onQueryChanged: _onQueryChanged,
                    onSubmitQuery: _commitSearch,
                    onFilterModeChanged: _onFilterModeChanged,
                    onOpenSort: _openSortSheet,
                    onOpenFilterSheet: _openFilterSheet,
                    activeAdvancedFilterCount: _filter.activeCount,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _SearchSuggestionPanel(
                  // open: gate utama untuk render panel. Kalau false →
                  // SizedBox.shrink, no vertical space taken → product
                  // grid muncul langsung di bawah filter chips.
                  open: _showSuggestionPanel,
                  query: _query,
                  suggestions: _suggestions,
                  loading: _suggestionLoading,
                  history: _searchHistory,
                  onProduct: _openProductSuggestion,
                  onCategory: (item) => _applySuggestedCategory(item.name),
                  onBrand: (item) => _applySuggestedBrand(item.name),
                  onSearchQuery: _commitSearch,
                  onHistoryTap: _commitSearch,
                  onClearHistory: _clearSearchHistory,
                ),
              ),
              // Active filter chips bar — horizontal scroll list dari
              // semua filter aktif (price range, multi-brand, rating).
              // Tap × di chip = remove individual filter. "Clear All"
              // button di akhir kalau ada filter aktif. Auto-hide kalau
              // tidak ada advanced filter.
              if (_filter.hasAdvancedFilters)
                SliverToBoxAdapter(
                  child: _ActiveFiltersBar(
                    filter: _filter,
                    onRemoveMinPrice: () =>
                        _removeFilterChip(clearMinPrice: true),
                    onRemoveMaxPrice: () =>
                        _removeFilterChip(clearMaxPrice: true),
                    onRemoveBrand: (brand) =>
                        _removeFilterChip(removeBrand: brand),
                    onRemoveRating: () =>
                        _removeFilterChip(clearMinRating: true),
                    onRemoveDiscount: () =>
                        _removeFilterChip(clearDiscount: true),
                    onRemoveInStock: () =>
                        _removeFilterChip(restoreInStock: true),
                    onClearAll: _clearAllAdvancedFilters,
                  ),
                ),
              if (hasLoadError)
                SliverFillRemaining(
                  hasScrollBody: false,
                  // #4: AppErrorState dengan varian dari statusCode asli —
                  // 5xx tampil "server bermasalah" (bukan salah label
                  // "cek koneksi"), offline tampil network.
                  child: Center(
                    child: AppErrorState(
                      variant:
                          appErrorVariantFromStatus(_result.errorStatusCode),
                      title: 'Gagal memuat produk',
                      onRetry: _loadProducts,
                    ),
                  ),
                )
              else if (_loading && products.isEmpty)
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPadding),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.58,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => const SkeletonProductCard(
                        showAddToCart: false,
                      ),
                      childCount: 8,
                    ),
                  ),
                )
              else if (products.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyProductsState(
                    onReset: _resetFilters,
                    // "Terakhir kamu lihat" — jangan dead-end. Saat filter/
                    // search 0 hasil, kasih jalan keluar berupa produk yang
                    // pernah user buka (recently viewed, client-side store).
                    recentProducts: recentlyViewedStore.items.take(10).toList(),
                    onProductTap: _openProduct,
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPadding),
                  // Grid 2-kolom auto-height (bukan SliverGrid dengan
                  // childAspectRatio tetap). Tiap baris = 1 Row berisi 2
                  // kartu. crossAxisAlignment.stretch bikin 2 kartu SEBARIS
                  // sama tinggi (rapi), tapi tinggi BARIS ikut konten
                  // terpanjang di baris itu — jadi produk tanpa badge/
                  // rating/terjual tidak lagi menyisakan ruang kosong
                  // gede seperti waktu tinggi dipaku 0.58 untuk semua.
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, rowIndex) {
                        final leftIndex = rowIndex * 2;
                        final rightIndex = leftIndex + 1;
                        final left = products[leftIndex];
                        final hasRight = rightIndex < products.length;
                        final rowCount = (products.length + 1) ~/ 2;
                        final isLastRow = rowIndex == rowCount - 1;
                        return Padding(
                          padding: EdgeInsets.only(bottom: isLastRow ? 0 : 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: _ProductsPageProductCard(
                                  product: left,
                                  onTap: () => _openProduct(left),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: hasRight
                                    ? _ProductsPageProductCard(
                                        product: products[rightIndex],
                                        onTap: () =>
                                            _openProduct(products[rightIndex]),
                                      )
                                    // Slot kanan kosong (jumlah produk ganjil)
                                    // — jaga kartu kiri tetap selebar 1 kolom,
                                    // tidak melar full-width.
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          ),
                        );
                      },
                      childCount: (products.length + 1) ~/ 2,
                    ),
                  ),
                ),
              if (_loadingMore)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 28),
                    child: Center(
                      child: SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: NataloColors.primary,
                        ),
                      ),
                    ),
                  ),
                )
              else if (!_hasMore && products.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, bottomPadding),
                    child: Center(
                      child: Text(
                        'Sudah sampai akhir katalog',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const BottomNavBar(currentIndex: 1),
    );
  }
}

class _ProductPageHeader extends StatelessWidget {
  const _ProductPageHeader();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ColoredBox(
      color: cs.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Produk Natalo',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
            ),
            // Cart icon — match dengan home & wishlist header (single
            // source of truth via AppCartButton: shopping_cart_outlined
            // 24px, red badge live sync via cartStore).
            const AppCartButton(),
          ],
        ),
      ),
    );
  }
}

class _CatalogHeader extends StatelessWidget {
  final TextEditingController controller;
  final String query;
  final _ProductFilterMode activeMode;
  final String? selectedCategory;
  final int visibleCount;
  final int totalCount;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String> onSubmitQuery;
  final ValueChanged<_ProductFilterMode> onFilterModeChanged;
  final VoidCallback onOpenSort;

  /// NEW — buka advanced filter sheet (price, multi-brand, rating).
  final VoidCallback onOpenFilterSheet;

  /// NEW — badge count untuk Filter button icon.
  final int activeAdvancedFilterCount;

  const _CatalogHeader({
    required this.controller,
    required this.query,
    required this.activeMode,
    required this.selectedCategory,
    required this.visibleCount,
    required this.totalCount,
    required this.onQueryChanged,
    required this.onSubmitQuery,
    required this.onFilterModeChanged,
    required this.onOpenSort,
    required this.onOpenFilterSheet,
    required this.activeAdvancedFilterCount,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          bottom: BorderSide(
            color: isDark ? cs.outlineVariant : const Color(0xFFF1F5F9),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _ProductSearchBar(
              controller: controller,
              query: query,
              onChanged: onQueryChanged,
              onClear: () {
                controller.clear();
                onQueryChanged('');
              },
              onSubmitted: onSubmitQuery,
            ),
          ),
          const SizedBox(height: 10),
          // Product count + filter + sort button row — di atas filter chips.
          _ProductCountAndSortRow(
            visibleCount: visibleCount,
            totalCount: totalCount,
            onOpenSort: onOpenSort,
            onOpenFilterSheet: onOpenFilterSheet,
            activeFilterCount: activeAdvancedFilterCount,
          ),
          const SizedBox(height: 10),
          _HorizontalProductFilterChips(
            selectedMode: activeMode,
            selectedCategory: selectedCategory,
            onChanged: onFilterModeChanged,
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

/// Product count text + tombol Filter + Urutkan (compact soft blue).
class _ProductCountAndSortRow extends StatelessWidget {
  final int visibleCount;
  final int totalCount;
  final VoidCallback onOpenSort;
  final VoidCallback onOpenFilterSheet;
  final int activeFilterCount;

  const _ProductCountAndSortRow({
    required this.visibleCount,
    required this.totalCount,
    required this.onOpenSort,
    required this.onOpenFilterSheet,
    required this.activeFilterCount,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                ),
                children: [
                  const TextSpan(text: 'Menampilkan '),
                  TextSpan(
                    text: '$visibleCount',
                    style: const TextStyle(
                      color: Color(0xFF2568C7),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (totalCount > visibleCount) ...[
                    const TextSpan(text: ' dari '),
                    TextSpan(
                      text: '$totalCount',
                      style: const TextStyle(
                        color: Color(0xFF2568C7),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                  const TextSpan(text: ' produk'),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          // Filter button — NEW, advanced filter sheet (price, multi-brand,
          // rating). Badge merah dengan count kalau ada filter aktif.
          _HeaderActionPill(
            label: 'Filter',
            icon: Icons.tune_rounded,
            badge: activeFilterCount > 0 ? activeFilterCount : null,
            onTap: onOpenFilterSheet,
          ),
          const SizedBox(width: 8),
          // Urutkan button — glass ringan style match spec.
          _HeaderActionPill(
            label: 'Urutkan',
            icon: Icons.swap_vert_rounded,
            onTap: onOpenSort,
          ),
        ],
      ),
    );
  }
}

/// Compact pill button untuk header action (Filter, Urutkan).
/// Soft glass style — selaras dengan chip "Semua/Kategori/Baru" di bawah.
/// Support optional `badge` count (red dot dengan number) untuk indikator
/// filter aktif.
class _HeaderActionPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final int? badge;
  final VoidCallback onTap;

  const _HeaderActionPill({
    required this.label,
    required this.icon,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pill = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: badge != null
                  ? const Color(0xFF2568C7)
                  : cs.outlineVariant,
              width: badge != null ? 1.4 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.035),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: badge != null
                      ? const Color(0xFF2568C7)
                      : cs.onSurface,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                icon,
                size: 19,
                color: badge != null
                    ? const Color(0xFF2568C7)
                    : cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
    if (badge == null) return pill;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        pill,
        Positioned(
          top: -4,
          right: -4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: Colors.white, width: 1.5),
            ),
            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
            alignment: Alignment.center,
            child: Text(
              badge! > 9 ? '9+' : '$badge',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyProductsState extends StatelessWidget {
  final VoidCallback onReset;

  /// Produk yang pernah dibuka user (recently viewed) — ditampilkan
  /// sebagai strip horizontal "Terakhir kamu lihat" supaya 0-hasil tidak
  /// jadi dead-end. Kosong = strip disembunyikan (mis. user baru).
  final List<Product> recentProducts;
  final ValueChanged<Product>? onProductTap;

  const _EmptyProductsState({
    required this.onReset,
    this.recentProducts = const [],
    this.onProductTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // SingleChildScrollView guard — dengan strip "Terakhir kamu lihat",
    // konten bisa melebihi sisa viewport di layar pendek (SliverFillRemaining
    // hasScrollBody:false akan overflow tanpa ini).
    return SingleChildScrollView(
      child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              color: NataloColors.primaryLight,
              borderRadius: BorderRadius.circular(28),
            ),
            child: const Icon(
              Icons.search_off_rounded,
              color: NataloColors.primary,
              size: 42,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Produk tidak ditemukan',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Coba kata kunci lain atau ubah filter pencarian.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          ElevatedButton(
            onPressed: onReset,
            style: ElevatedButton.styleFrom(
              backgroundColor: _brandBlue,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
            child: const Text(
              'Reset Filter',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          if (recentProducts.isNotEmpty) ...[
            const SizedBox(height: 32),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Terakhir kamu lihat',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 168,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: recentProducts.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final product = recentProducts[index];
                  return _RecentlyViewedMiniCard(
                    product: product,
                    onTap: () => onProductTap?.call(product),
                  );
                },
              ),
            ),
          ],
        ],
      ),
      ),
    );
  }
}

/// Kartu mini produk untuk strip "Terakhir kamu lihat" di empty state.
/// Compact (112px lebar) — image + nama 2 baris + harga.
class _RecentlyViewedMiniCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;

  const _RecentlyViewedMiniCard({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 112,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AppProductImage(
                imageUrl: product.imageUrl,
                width: 96,
                height: 84,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              product.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
            const Spacer(),
            Text(
              formatRupiah(product.finalPrice),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: NataloColors.primary,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Active filter mode untuk pinned glassy bar (single-select).
enum _ProductFilterMode {
  semua,
  kategori,
  baru,
  populer,
}

extension _ProductFilterModeMeta on _ProductFilterMode {
  String get label {
    switch (this) {
      case _ProductFilterMode.semua:
        return 'Semua';
      case _ProductFilterMode.kategori:
        return 'Kategori';
      case _ProductFilterMode.baru:
        return 'Produk Baru';
      case _ProductFilterMode.populer:
        return 'Terlaris';
    }
  }

  IconData get icon {
    switch (this) {
      case _ProductFilterMode.semua:
        return Icons.grid_view_rounded;
      case _ProductFilterMode.kategori:
        return Icons.inventory_2_outlined;
      case _ProductFilterMode.baru:
        return Icons.fiber_new_rounded;
      case _ProductFilterMode.populer:
        return Icons.local_fire_department_rounded;
    }
  }

  Widget? get coloredIcon {
    switch (this) {
      case _ProductFilterMode.baru:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF16A34A),
            borderRadius: BorderRadius.circular(5),
          ),
          child: const Text(
            'NEW',
            style: TextStyle(
              color: Colors.white,
              fontSize: 8.5,
              height: 1,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.1,
            ),
          ),
        );
      case _ProductFilterMode.populer:
        return Container(
          width: 20,
          height: 20,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFFFFF1E7),
          ),
          child: const Icon(
            Icons.local_fire_department_rounded,
            size: 15,
            color: Color(0xFFF97316),
          ),
        );
      case _ProductFilterMode.semua:
      case _ProductFilterMode.kategori:
        return null;
    }
  }
}

class _ProductSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  const _ProductSearchBar({
    required this.controller,
    required this.query,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 42,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        textInputAction: TextInputAction.search,
        style: TextStyle(
          color: cs.onSurface,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          hintText: 'Cari produk Natalo',
          hintStyle: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 22,
            color: cs.onSurfaceVariant,
          ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 44, minHeight: 42),
          suffixIcon: query.isEmpty
              ? null
              : IconButton(
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: cs.onSurfaceVariant,
                  tooltip: 'Hapus',
                  visualDensity: VisualDensity.compact,
                ),
          filled: true,
          fillColor: cs.surfaceContainerHighest,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: cs.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: cs.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _brandBlue, width: 1.2),
          ),
        ),
      ),
    );
  }
}

/// Horizontal scroll chips dengan icon — Natalo style.
class _HorizontalProductFilterChips extends StatelessWidget {
  final _ProductFilterMode selectedMode;
  final String? selectedCategory;
  final ValueChanged<_ProductFilterMode> onChanged;

  const _HorizontalProductFilterChips({
    required this.selectedMode,
    required this.selectedCategory,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(left: 16, right: 20),
        child: Row(
          children: [
            for (final mode in _ProductFilterMode.values) ...[
              if (mode == _ProductFilterMode.kategori)
                ProductFilterChip(
                  // Apply formatter — defensive kalau backend kasih slug
                  // mentah (mis. "snack-treat-anjing" → "Snack & Treat Anjing").
                  label: selectedCategory != null
                      ? formatCategoryLabel(selectedCategory!)
                      : mode.label,
                  icon: mode.icon,
                  leadingIcon: mode.coloredIcon,
                  selected: selectedMode == _ProductFilterMode.kategori,
                  onTap: () => onChanged(mode),
                )
              else
                ProductFilterChip(
                  label: mode.label,
                  icon: mode.icon,
                  leadingIcon: mode.coloredIcon,
                  selected: selectedMode == mode,
                  onTap: () => onChanged(mode),
                ),
              if (mode != _ProductFilterMode.values.last)
                const SizedBox(width: 10),
            ],
          ],
        ),
      ),
    );
  }
}

/// Filter chip Natalo style — icon + label + active state biru.
class ProductFilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Widget? leadingIcon;
  final bool selected;
  final VoidCallback onTap;

  const ProductFilterChip({
    super.key,
    required this.label,
    required this.icon,
    this.leadingIcon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      height: 44,
      decoration: BoxDecoration(
        // Active: glossy gradient biru Natalo dengan white border 0.35
        // untuk highlight glass effect. Inactive: glass ringan (white 0.72
        // + border `#D8E4F4`) — spec "Visual Direction".
        gradient: selected
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2F7BEF), Color(0xFF0F63D8)],
              )
            : null,
        color: selected ? null : cs.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: selected
              ? Colors.white.withValues(alpha: 0.35)
              : cs.outlineVariant,
          width: 1,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: const Color(0xFF1F6FD1).withValues(alpha: 0.22),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.035),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                leadingIcon ??
                    Icon(
                      icon,
                      size: 18,
                      color: selected ? Colors.white : cs.onSurfaceVariant,
                    ),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? Colors.white : cs.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
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

class _ProductsPageProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;

  const _ProductsPageProductCard({
    required this.product,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final discountPercent = _activeProductDiscountPercent(product);

    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cs.outlineVariant),
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
                  _ProductGridImage(imageUrl: product.imageUrl),
                  if (discountPercent != null)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: _ProductDiscountBadge(
                        percent: discountPercent,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
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
              const SizedBox(height: 8),
              _ProductPriceRow(product: product),
              _ProductSavingBadge(product: product),
              _ProductRatingSoldRow(product: product),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductGridImage extends StatelessWidget {
  final String imageUrl;

  const _ProductGridImage({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl.trim().isNotEmpty;
    if (!hasImage) return const _ProductImagePlaceholder();

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        height: 132,
        width: double.infinity,
        fit: BoxFit.contain,
        placeholder: (_, __) => const _ProductImagePlaceholder(),
        errorWidget: (_, __, ___) => const _ProductImagePlaceholder(),
      ),
    );
  }
}

class _ProductImagePlaceholder extends StatelessWidget {
  const _ProductImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 132,
      width: double.infinity,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Center(
        child: Icon(
          Icons.pets_rounded,
          size: 34,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ProductPriceRow extends StatelessWidget {
  final Product product;

  const _ProductPriceRow({required this.product});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (!product.hasDiscount) {
      return Text(
        formatRupiah(product.finalPrice),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w900,
          color: cs.onSurface,
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
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
            height: 1.05,
            decoration: TextDecoration.lineThrough,
            decorationThickness: 1.5,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          formatRupiah(product.finalPrice),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w900,
            color: Color(0xFFE11D48),
            height: 1.05,
          ),
        ),
      ],
    );
  }
}

class _ProductSavingBadge extends StatelessWidget {
  final Product product;

  const _ProductSavingBadge({required this.product});

  @override
  Widget build(BuildContext context) {
    final savingLabel = _productSavingLabel(product);
    final shippingLabel = _productShippingLabel(product);
    final badges = <Widget>[
      if (shippingLabel != null)
        _ProductPromoBadge(
          label: shippingLabel,
          icon: Icons.local_shipping_rounded,
          color: const Color(0xFF16A34A),
          backgroundColor: const Color(0xFFECFDF3),
          borderColor: const Color(0xFFA7F3D0),
        ),
      if (savingLabel != null)
        _ProductPromoBadge(
          label: savingLabel,
          icon: Icons.confirmation_number_rounded,
          color: const Color(0xFFEF4444),
          backgroundColor: const Color(0xFFFFF1F2),
          borderColor: const Color(0xFFFCA5A5),
        ),
    ];

    if (badges.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: badges,
      ),
    );
  }
}

class _ProductPromoBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final Color backgroundColor;
  final Color borderColor;

  const _ProductPromoBadge({
    required this.label,
    required this.icon,
    required this.color,
    required this.backgroundColor,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
            size: 13,
            color: color,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
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

class _ProductRatingSoldRow extends StatelessWidget {
  final Product product;

  const _ProductRatingSoldRow({required this.product});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasRating = product.rating > 0;
    final hasSold = product.soldCount > 0;
    if (!hasRating && !hasSold) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Row(
        children: [
          if (hasRating) ...[
            const Icon(
              Icons.star_rounded,
              size: 14,
              color: Color(0xFFFACC15),
            ),
            const SizedBox(width: 3),
            Text(
              product.rating.toStringAsFixed(1),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: cs.onSurfaceVariant,
                height: 1,
              ),
            ),
          ],
          if (hasRating && hasSold) ...[
            const SizedBox(width: 5),
            Text(
              '•',
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurfaceVariant,
                height: 1,
              ),
            ),
            const SizedBox(width: 5),
          ],
          if (hasSold)
            Flexible(
              child: Text(
                '${_formatProductSoldCount(product.soldCount)} terjual',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurfaceVariant,
                  height: 1,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String? _productSavingLabel(Product product) {
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

String? _productShippingLabel(Product product) {
  final voucher = product.shippingVoucherPreview;
  if (voucher == null) return null;
  final label = voucher.badgeLabel.trim();
  return label.isNotEmpty ? label : 'Gratis Ongkir';
}

String _formatProductSoldCount(int count) {
  if (count >= 1000) {
    final value = count / 1000;
    final text =
        value >= 10 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
    return '${text.replaceAll('.', ',').replaceAll(',0', '')}rb+';
  }
  if (count >= 100) return '${(count ~/ 50) * 50}+';
  return count.toString();
}

int? _activeProductDiscountPercent(Product product) {
  final discount = product.discountPrice;
  if (discount == null || discount <= 0 || product.price <= 0) return null;
  if (discount >= product.price) return null;

  final endsAt = product.flashSaleEndsAt;
  if (endsAt != null && !endsAt.isAfter(DateTime.now())) return null;

  return (((product.price - discount) / product.price) * 100).round();
}

class _ProductDiscountBadge extends StatelessWidget {
  final int? percent;

  const _ProductDiscountBadge({required this.percent});

  @override
  Widget build(BuildContext context) {
    final value = percent;
    if (value == null || value <= 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFE11D48),
        borderRadius: BorderRadius.circular(10),
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
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}

/// Pinned header delegate untuk sliver yang stick di top scroll.
class _PinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  @override
  final double minExtent;
  @override
  final double maxExtent;
  final Widget child;

  const _PinnedHeaderDelegate({
    required this.minExtent,
    required this.maxExtent,
    required this.child,
  });

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return child;
  }

  @override
  bool shouldRebuild(covariant _PinnedHeaderDelegate oldDelegate) {
    return oldDelegate.child != child ||
        oldDelegate.minExtent != minExtent ||
        oldDelegate.maxExtent != maxExtent;
  }
}

class _SearchSuggestionPanel extends StatelessWidget {
  /// Master gate dari parent — false setelah commit search supaya panel
  /// tutup total (tidak ada vertical space taken). Kalau true, panel
  /// boleh muncul tergantung kondisi query/history di bawah.
  final bool open;
  final String query;
  final SearchSuggestionResult suggestions;
  final bool loading;
  final List<String> history;
  final ValueChanged<ProductSuggestion> onProduct;
  final ValueChanged<LabelSuggestion> onCategory;
  final ValueChanged<LabelSuggestion> onBrand;
  final ValueChanged<String> onSearchQuery;
  final ValueChanged<String> onHistoryTap;
  final VoidCallback onClearHistory;

  const _SearchSuggestionPanel({
    required this.open,
    required this.query,
    required this.suggestions,
    required this.loading,
    required this.history,
    required this.onProduct,
    required this.onCategory,
    required this.onBrand,
    required this.onSearchQuery,
    required this.onHistoryTap,
    required this.onClearHistory,
  });

  @override
  Widget build(BuildContext context) {
    // Hard gate dari parent — kalau panel tidak open (mis. setelah
    // commit search), langsung return shrink. Tidak ada vertical space
    // di sliver list, grid produk muncul langsung di bawah filter chips.
    if (!open) return const SizedBox.shrink();

    final keyword = query.trim();
    final showSuggest = keyword.length >= 2;
    final showHistory = keyword.isEmpty && history.isNotEmpty;

    if (!showSuggest && !showHistory) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: showHistory
          ? _SearchHistoryList(
              history: history,
              onTap: onHistoryTap,
              onClear: onClearHistory,
            )
          : _SuggestionList(
              query: keyword,
              suggestions: suggestions,
              loading: loading,
              onProduct: onProduct,
              onCategory: onCategory,
              onBrand: onBrand,
              onSearchQuery: onSearchQuery,
            ),
    );
  }
}

class _SearchHistoryList extends StatelessWidget {
  final List<String> history;
  final ValueChanged<String> onTap;
  final VoidCallback onClear;

  const _SearchHistoryList({
    required this.history,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Pencarian terakhir',
                style: TextStyle(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            TextButton(onPressed: onClear, child: const Text('Hapus')),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: history.map((item) {
            return ActionChip(
              avatar: const Icon(Icons.history_rounded, size: 16),
              label: Text(item),
              onPressed: () => onTap(item),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _SuggestionList extends StatelessWidget {
  final String query;
  final SearchSuggestionResult suggestions;
  final bool loading;
  final ValueChanged<ProductSuggestion> onProduct;
  final ValueChanged<LabelSuggestion> onCategory;
  final ValueChanged<LabelSuggestion> onBrand;
  final ValueChanged<String> onSearchQuery;

  const _SuggestionList({
    required this.query,
    required this.suggestions,
    required this.loading,
    required this.onProduct,
    required this.onCategory,
    required this.onBrand,
    required this.onSearchQuery,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (loading) {
      return Row(
        children: [
          const SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(
            'Mencari saran...',
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      );
    }

    if (suggestions.isEmpty) {
      return _SuggestionTile(
        icon: Icons.search_rounded,
        title: 'Cari "$query"',
        subtitle: 'Tekan enter untuk mencari',
        onTap: () => onSearchQuery(query),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Saran pencarian',
          style: TextStyle(
            color: cs.onSurface,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        ...suggestions.brands.take(3).map(
              (item) => _SuggestionTile(
                icon: Icons.workspace_premium_outlined,
                title: 'Brand: ${item.name}',
                subtitle: '${item.count} produk',
                onTap: () => onBrand(item),
              ),
            ),
        ...suggestions.categories.take(3).map(
              (item) => _SuggestionTile(
                icon: Icons.category_outlined,
                title: 'Kategori: ${item.name}',
                subtitle: '${item.count} produk',
                onTap: () => onCategory(item),
              ),
            ),
        ...suggestions.products.take(4).map(
              (item) => _ProductSuggestionTile(
                item: item,
                onTap: () => onProduct(item),
              ),
            ),
      ],
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SuggestionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: SoftIconBox(icon: icon, size: 38),
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

class _ProductSuggestionTile extends StatelessWidget {
  final ProductSuggestion item;
  final VoidCallback onTap;

  const _ProductSuggestionTile({
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final priceLabel = item.priceMax > item.priceMin
        ? '${formatRupiah(item.priceMin)} - ${formatRupiah(item.priceMax)}'
        : formatRupiah(item.priceMin);

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AppProductImage(
          imageUrl: item.imageUrl,
          height: 42,
          width: 42,
        ),
      ),
      title: Text(
        item.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      subtitle: Text('${item.brandName ?? 'Produk'} · $priceLabel'),
      trailing: const Icon(Icons.search_rounded, size: 18),
      onTap: onTap,
    );
  }
}

enum ProductSort { newest, popular, rating, priceLow, priceHigh }

class ProductCatalogFilter {
  final String? category;
  final String? brand;
  final ProductSort sort;
  final bool inStockOnly;
  final bool discountOnly;
  final bool withImageOnly;
  // Search Filters extension — Tokopedia-style advanced filter sheet.
  // Default null/empty = no constraint. Set by _FilterSheet, applied di
  // products_screen `.where()` filter chain bersama dengan field lain.
  /// Min harga inclusive (Rp). null = no lower bound.
  final double? minPrice;

  /// Max harga inclusive (Rp). null = no upper bound.
  final double? maxPrice;

  /// Multi-select brand names. Empty = all brands allowed.
  /// Berbeda dengan `brand` (single) yang dipakai filter chip atas.
  /// Kalau ada `brand` di-set, juga harus match dengan brands kalau set.
  final Set<String> brands;

  /// Minimum rating (1-5). 0 = no rating filter.
  final int minRating;

  /// True HANYA kalau user eksplisit pilih shortcut "Produk Baru" (pill
  /// _ProductFilterMode.baru). Server pakai flag ini untuk terapkan cutoff
  /// createdAt 30-hari (lihat NEW_PRODUCT_WINDOW_DAYS di lib/products.ts).
  ///
  /// SENGAJA dipisah dari `sort` — sebelumnya apiNewFilter derive dari
  /// `sort == ProductSort.newest`, padahal itu JUGA default sort untuk
  /// seluruh katalog (dan value yang dipakai saat pilih kategori/urutan
  /// "Terbaru" manual). Akibatnya server diam-diam filter HANYA produk
  /// umur <30 hari di kondisi normal → tab Produk kosong total kalau
  /// catalog di-bulk-import lebih dari 30 hari lalu (bug nyata, root
  /// cause "halaman produk kosong padahal DB penuh").
  final bool newArrivalsOnly;

  const ProductCatalogFilter({
    this.category,
    this.brand,
    this.sort = ProductSort.newest,
    this.newArrivalsOnly = false,
    // Default `true` — customer tidak lihat produk stok habis di katalog.
    // Behavior e-commerce standar (Shopee, Tokopedia): produk habis
    // di-hide dari list/search.
    //
    // Exception (accessible by URL):
    //  - Admin: dapat akses semua produk via /admin/products
    //  - User yang pernah beli: lihat produk via daftar pesanan
    //    (order detail page → klik produk → product detail tetap
    //    accessible terlepas stok)
    //
    // Newly created products dengan stok=0 sengaja tidak tampil sampai
    // admin isi stok. Admin perlu set stock saat create produk supaya
    // langsung visible.
    this.inStockOnly = true,
    this.discountOnly = false,
    this.withImageOnly = false,
    this.minPrice,
    this.maxPrice,
    this.brands = const {},
    this.minRating = 0,
  });

  String? get apiNewFilter => newArrivalsOnly ? 'newest' : null;

  String? get apiPopularFilter {
    return switch (sort) {
      ProductSort.popular => 'best-seller',
      ProductSort.rating => 'highest-rating',
      _ => null,
    };
  }

  int get activeCount {
    var count = 0;
    if (category != null) count++;
    if (brand != null) count++;
    if (sort != ProductSort.newest) count++;
    if (!inStockOnly) count++;
    if (discountOnly) count++;
    if (withImageOnly) count++;
    if (minPrice != null) count++;
    if (maxPrice != null) count++;
    if (brands.isNotEmpty) count++;
    if (minRating > 0) count++;
    return count;
  }

  /// True kalau ada advanced filter aktif (price/multi-brand/rating).
  /// Dipakai untuk show "Active Filters Bar" di atas grid.
  bool get hasAdvancedFilters =>
      minPrice != null ||
      maxPrice != null ||
      brands.isNotEmpty ||
      minRating > 0 ||
      discountOnly ||
      !inStockOnly;

  ProductCatalogFilter copyWith({
    String? category,
    bool clearCategory = false,
    String? brand,
    bool clearBrand = false,
    ProductSort? sort,
    bool? inStockOnly,
    bool? discountOnly,
    bool? withImageOnly,
    double? minPrice,
    bool clearMinPrice = false,
    double? maxPrice,
    bool clearMaxPrice = false,
    Set<String>? brands,
    int? minRating,
    bool? newArrivalsOnly,
  }) {
    return ProductCatalogFilter(
      category: clearCategory ? null : category ?? this.category,
      brand: clearBrand ? null : brand ?? this.brand,
      sort: sort ?? this.sort,
      inStockOnly: inStockOnly ?? this.inStockOnly,
      discountOnly: discountOnly ?? this.discountOnly,
      withImageOnly: withImageOnly ?? this.withImageOnly,
      minPrice: clearMinPrice ? null : minPrice ?? this.minPrice,
      maxPrice: clearMaxPrice ? null : maxPrice ?? this.maxPrice,
      brands: brands ?? this.brands,
      minRating: minRating ?? this.minRating,
      newArrivalsOnly: newArrivalsOnly ?? this.newArrivalsOnly,
    );
  }
}

// ════════════════════════════════════════════════════════════════
// Category bottom sheet — modal kategori untuk halaman Produk
// ════════════════════════════════════════════════════════════════

class _CategoryBottomSheet extends StatelessWidget {
  final ScrollController scrollController;
  final List<String> categories;
  final String? selectedCategory;
  final ValueChanged<String> onSelected;

  const _CategoryBottomSheet({
    required this.scrollController,
    required this.categories,
    required this.selectedCategory,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Pilih Kategori',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                itemCount: categories.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: cs.outlineVariant,
                ),
                itemBuilder: (context, index) {
                  final category = categories[index];
                  final label = category == 'Semua'
                      ? 'Semua'
                      : formatCategoryLabel(category);
                  final isSelected =
                      (selectedCategory == null && category == 'Semua') ||
                          selectedCategory == category;

                  return _CategoryBottomSheetItem(
                    label: label,
                    isSelected: isSelected,
                    onTap: () => onSelected(category),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryBottomSheetItem extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryBottomSheetItem({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: isSelected
              ? BoxDecoration(
                  color: const Color(0xFFEAF4FF),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFFB9DAFF),
                    width: 1,
                  ),
                )
              : null,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected
                        ? const Color(0xFF0D6FE8)
                        : cs.onSurface,
                  ),
                ),
              ),
              if (isSelected)
                const Icon(
                  Icons.check_rounded,
                  color: Color(0xFF0D6FE8),
                  size: 24,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// Sort bottom sheet — simple modal untuk pilih ProductSort
// ════════════════════════════════════════════════════════════════

class _SortBottomSheet extends StatelessWidget {
  final ProductSort currentSort;

  const _SortBottomSheet({required this.currentSort});

  static const _options = [
    (ProductSort.newest, 'Terbaru'),
    (ProductSort.popular, 'Paling Populer'),
    (ProductSort.rating, 'Rating Tertinggi'),
    (ProductSort.priceLow, 'Harga Terendah'),
    (ProductSort.priceHigh, 'Harga Tertinggi'),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Urutkan berdasarkan',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            for (final option in _options) ...[
              ListTile(
                onTap: () => Navigator.pop(context, option.$1),
                title: Text(
                  option.$2,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: option.$1 == currentSort
                        ? FontWeight.w700
                        : FontWeight.w600,
                    color: option.$1 == currentSort
                        ? const Color(0xFF2568C7)
                        : cs.onSurface,
                  ),
                ),
                trailing: option.$1 == currentSort
                    ? const Icon(
                        Icons.check_rounded,
                        color: Color(0xFF2568C7),
                        size: 20,
                      )
                    : null,
              ),
              if (option != _options.last)
                Divider(
                  height: 1,
                  thickness: 1,
                  color: cs.outlineVariant,
                  indent: 16,
                  endIndent: 16,
                ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// Advanced Filter Sheet — Search Filters scope
// ════════════════════════════════════════════════════════════════

/// Bottom sheet untuk advanced filter (price range, multi-brand,
/// rating, promo/in-stock toggles). 85% screen height, scrollable
/// internal, sticky apply button di bawah dengan live preview count.
class _FilterSheet extends StatefulWidget {
  final ProductCatalogFilter currentFilter;
  final List<String> allBrands;
  final double priceMaxBound;

  /// Closure dari parent — compute count match untuk filter candidate.
  /// Update live saat user toggle, displayed di apply button label.
  final int Function(ProductCatalogFilter) previewCountForFilter;

  const _FilterSheet({
    required this.currentFilter,
    required this.allBrands,
    required this.priceMaxBound,
    required this.previewCountForFilter,
  });

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late RangeValues _priceRange;
  late Set<String> _selectedBrands;
  late int _minRating;
  late bool _inStockOnly;
  late bool _discountOnly;
  late bool _brandListExpanded;

  @override
  void initState() {
    super.initState();
    _priceRange = RangeValues(
      widget.currentFilter.minPrice ?? 0,
      widget.currentFilter.maxPrice ?? widget.priceMaxBound,
    );
    _selectedBrands = Set<String>.from(widget.currentFilter.brands);
    _minRating = widget.currentFilter.minRating;
    _inStockOnly = widget.currentFilter.inStockOnly;
    _discountOnly = widget.currentFilter.discountOnly;
    _brandListExpanded = widget.allBrands.length <= 8;
  }

  ProductCatalogFilter get _candidateFilter {
    return widget.currentFilter.copyWith(
      minPrice: _priceRange.start > 0 ? _priceRange.start : null,
      clearMinPrice: _priceRange.start <= 0,
      maxPrice: _priceRange.end < widget.priceMaxBound ? _priceRange.end : null,
      clearMaxPrice: _priceRange.end >= widget.priceMaxBound,
      brands: _selectedBrands,
      minRating: _minRating,
      inStockOnly: _inStockOnly,
      discountOnly: _discountOnly,
    );
  }

  void _resetAll() {
    setState(() {
      _priceRange = RangeValues(0, widget.priceMaxBound);
      _selectedBrands = {};
      _minRating = 0;
      _inStockOnly = true;
      _discountOnly = false;
    });
  }

  void _apply() {
    Navigator.of(context).pop(_candidateFilter);
  }

  String _formatPriceShort(double value) {
    if (value >= 1000000) {
      final v = value / 1000000;
      return 'Rp ${v.toStringAsFixed(value % 1000000 == 0 ? 0 : 1)}jt';
    }
    if (value >= 1000) {
      return 'Rp ${(value / 1000).round()}rb';
    }
    return 'Rp ${value.toInt()}';
  }

  @override
  Widget build(BuildContext context) {
    final visibleBrands = _brandListExpanded
        ? widget.allBrands
        : widget.allBrands.take(8).toList();
    final hasMoreBrands = widget.allBrands.length > 8;
    final previewCount = widget.previewCountForFilter(_candidateFilter);
    final cs = Theme.of(context).colorScheme;

    return FractionallySizedBox(
      heightFactor: 0.85,
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
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Filter',
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _resetAll,
                      child: const Text(
                        'Reset',
                        style: TextStyle(
                          color: Color(0xFFEF4444),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: cs.outlineVariant),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  children: [
                    const _FilterSectionTitle('HARGA'),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatPriceShort(_priceRange.start),
                          style: const TextStyle(
                            color: Color(0xFF2568C7),
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          _formatPriceShort(_priceRange.end),
                          style: const TextStyle(
                            color: Color(0xFF2568C7),
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    RangeSlider(
                      values: _priceRange,
                      min: 0,
                      max: widget.priceMaxBound,
                      divisions: 20,
                      activeColor: const Color(0xFF2568C7),
                      inactiveColor: cs.outlineVariant,
                      labels: RangeLabels(
                        _formatPriceShort(_priceRange.start),
                        _formatPriceShort(_priceRange.end),
                      ),
                      onChanged: (range) => setState(() => _priceRange = range),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        const Expanded(child: _FilterSectionTitle('BRAND')),
                        if (_selectedBrands.isNotEmpty)
                          Text(
                            '${_selectedBrands.length}/${widget.allBrands.length}',
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (widget.allBrands.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'Belum ada brand di katalog.',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    else
                      ...visibleBrands.map((brand) {
                        final selected = _selectedBrands.contains(brand);
                        return _FilterCheckRow(
                          label: brand,
                          selected: selected,
                          onTap: () {
                            setState(() {
                              if (selected) {
                                _selectedBrands.remove(brand);
                              } else {
                                _selectedBrands.add(brand);
                              }
                            });
                          },
                        );
                      }),
                    if (hasMoreBrands && !_brandListExpanded)
                      TextButton(
                        onPressed: () =>
                            setState(() => _brandListExpanded = true),
                        child: Text(
                          'Lihat semua ${widget.allBrands.length} brand →',
                          style: const TextStyle(
                            color: Color(0xFF2568C7),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    const _FilterSectionTitle('RATING MINIMUM'),
                    const SizedBox(height: 8),
                    for (final rating in [4, 3, 2])
                      _FilterRadioRow(
                        selected: _minRating == rating,
                        onTap: () => setState(() =>
                            _minRating = _minRating == rating ? 0 : rating),
                        label: Row(
                          children: [
                            ...List.generate(
                              rating,
                              (_) => const Icon(
                                Icons.star_rounded,
                                size: 18,
                                color: Color(0xFFFBBF24),
                              ),
                            ),
                            ...List.generate(
                              5 - rating,
                              (_) => Icon(
                                Icons.star_outline_rounded,
                                size: 18,
                                color: cs.outlineVariant,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '$rating ke atas',
                              style: TextStyle(
                                color: cs.onSurfaceVariant,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 24),
                    const _FilterSectionTitle('TAMPILAN'),
                    const SizedBox(height: 4),
                    _FilterToggleRow(
                      label: 'Hanya tampilkan tersedia',
                      value: _inStockOnly,
                      onChanged: (v) => setState(() => _inStockOnly = v),
                    ),
                    _FilterToggleRow(
                      label: 'Sedang promo / diskon',
                      value: _discountOnly,
                      onChanged: (v) => setState(() => _discountOnly = v),
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    border: Border(
                      top: BorderSide(color: cs.outlineVariant),
                    ),
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      // BUGFIX(audit): JANGAN gate Apply pakai previewCount.
                      // previewCount cuma hitung produk yang KEBETULAN ter-load
                      // di memori (page 1), padahal filter sebenarnya server-
                      // side. Filter valid yang match-nya tidak ada di page
                      // ter-load → previewCount 0 → tombol mati permanen
                      // (user tak bisa apply filter yang sah). Selalu enable;
                      // kalau hasil 0 setelah apply, empty-state + Reset
                      // Filter yang handle.
                      onPressed: _apply,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2568C7),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFFCBD5E1),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      child: Text(
                        previewCount > 0
                            ? 'Tampilkan $previewCount produk'
                            : 'Terapkan Filter',
                      ),
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
}

class _FilterSectionTitle extends StatelessWidget {
  final String label;

  const _FilterSectionTitle(this.label);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      label,
      style: TextStyle(
        color: cs.onSurface,
        fontSize: 12,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.4,
      ),
    );
  }
}

class _FilterCheckRow extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterCheckRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Checkbox(
              value: selected,
              activeColor: const Color(0xFF2568C7),
              onChanged: (_) => onTap(),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterRadioRow extends StatelessWidget {
  final Widget label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterRadioRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? const Color(0xFF2568C7)
                      : cs.outlineVariant,
                  width: 2,
                ),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF2568C7),
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(child: label),
          ],
        ),
      ),
    );
  }
}

class _FilterToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _FilterToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: const Color(0xFF2568C7),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// Horizontal scrollable bar showing active filters as chips.
/// Tap × on chip = remove individual filter. "Hapus" button kanan
/// kalau ada filter aktif. Parent sliver-level conditional render
/// kalau filter.hasAdvancedFilters false.
class _ActiveFiltersBar extends StatelessWidget {
  final ProductCatalogFilter filter;
  final VoidCallback onRemoveMinPrice;
  final VoidCallback onRemoveMaxPrice;
  final ValueChanged<String> onRemoveBrand;
  final VoidCallback onRemoveRating;
  final VoidCallback onRemoveDiscount;
  final VoidCallback onRemoveInStock;
  final VoidCallback onClearAll;

  const _ActiveFiltersBar({
    required this.filter,
    required this.onRemoveMinPrice,
    required this.onRemoveMaxPrice,
    required this.onRemoveBrand,
    required this.onRemoveRating,
    required this.onRemoveDiscount,
    required this.onRemoveInStock,
    required this.onClearAll,
  });

  String _formatPriceShort(double value) {
    if (value >= 1000000) {
      final v = value / 1000000;
      return 'Rp${v.toStringAsFixed(value % 1000000 == 0 ? 0 : 1)}jt';
    }
    if (value >= 1000) {
      return 'Rp${(value / 1000).round()}rb';
    }
    return 'Rp${value.toInt()}';
  }

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];
    if (filter.minPrice != null) {
      chips.add(_ActiveFilterChip(
        label: '≥ ${_formatPriceShort(filter.minPrice!)}',
        onRemove: onRemoveMinPrice,
      ));
    }
    if (filter.maxPrice != null) {
      chips.add(_ActiveFilterChip(
        label: '≤ ${_formatPriceShort(filter.maxPrice!)}',
        onRemove: onRemoveMaxPrice,
      ));
    }
    for (final brand in filter.brands) {
      chips.add(_ActiveFilterChip(
        label: brand,
        onRemove: () => onRemoveBrand(brand),
      ));
    }
    if (filter.minRating > 0) {
      chips.add(_ActiveFilterChip(
        label: 'Rating ⭐${filter.minRating}+',
        onRemove: onRemoveRating,
      ));
    }
    if (filter.discountOnly) {
      chips.add(_ActiveFilterChip(
        label: 'Promo',
        onRemove: onRemoveDiscount,
      ));
    }
    if (!filter.inStockOnly) {
      chips.add(_ActiveFilterChip(
        label: 'Termasuk habis',
        onRemove: onRemoveInStock,
      ));
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surface,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: SizedBox(
        height: 32,
        child: Row(
          children: [
            Expanded(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: chips.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) => chips[i],
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: onClearAll,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFEF4444),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(48, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Hapus',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveFilterChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;

  const _ActiveFilterChip({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 10, right: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF4FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBED7FF), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF2568C7),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(99),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(
                Icons.close_rounded,
                size: 14,
                color: Color(0xFF2568C7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

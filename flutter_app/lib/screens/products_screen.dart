import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/natalo_colors.dart';

// sample_products dihapus dari import — products screen sekarang pure
// API-driven dari Capacitor backend. Loading state pakai skeleton grid,
// error state pakai banner + pull-to-refresh.
import '../models/product.dart';
import '../services/product_service.dart';
import '../state/recently_viewed_store.dart';
import '../state/search_history_store.dart';
import '../utils/formatters.dart';
import '../utils/search_synonyms.dart';
import '../widgets/app_cart_button.dart';
import '../widgets/app_product_image.dart';
import '../widgets/app_ui.dart';
import '../widgets/product_card.dart';
import '../widgets/skeleton_product_card.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/glass_surface.dart';
import '../widgets/barcode_scanner_modal.dart';
import '../widgets/natalo_paw_refresh_indicator.dart';
import '../widgets/voice_search_modal.dart';

const _brandBlue = NataloColors.nataloBlue;
const _textPrimary = Color(0xFF102033);
const _textSecondary = Color(0xFF64748B);
const _borderSoft = Color(0xFFE5EAF1);
const _dangerRed = Color(0xFFEF4444);

class ProductsScreen extends StatefulWidget {
  final String? selectedBrand;
  final String? initialQuery;
  final String? initialCategory;

  const ProductsScreen({
    super.key,
    this.selectedBrand,
    this.initialQuery,
    this.initialCategory,
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
  // Infinite scroll state — track current page limit. Each "load more"
  // bump limit by 24. fetchProducts query include up to current limit.
  // Crude tapi efektif untuk catalog under 1000 produk.
  int _pageLimit = 60;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _catalogGeneration = 0;
  int _productReturnCount = 0;
  int _nextCatalogRegenerateAt = 2;

  bool get _shouldGenerateAllProducts {
    return widget.selectedBrand == null &&
        _activeMode == _ProductFilterMode.semua &&
        _query.trim().isEmpty &&
        _filter.category == null &&
        _filter.brand == null &&
        _filter.sort == ProductSort.newest &&
        _filter.inStockOnly &&
        !_filter.discountOnly &&
        !_filter.withImageOnly;
  }

  List<String> get _categories {
    final values = _result.products
        .map((product) => product.category)
        .toSet()
        .toList()
      ..sort();
    return values;
  }

  List<String> get _brands {
    final values = _result.products
        .map((product) => product.brand)
        .toSet()
        .toList()
      ..sort();
    return values;
  }

  List<Product> get _products {
    final keyword = _query.trim().toLowerCase();
    final filtered = _result.products.where((product) {
      final brandMatch =
          widget.selectedBrand == null || product.brand == widget.selectedBrand;
      final filterBrandMatch =
          _filter.brand == null || product.brand == _filter.brand;
      final categoryMatch =
          _filter.category == null || product.category == _filter.category;
      final stockMatch = !_filter.inStockOnly || product.stock > 0;
      final discountMatch = !_filter.discountOnly || product.hasDiscount;
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
    if (widget.initialCategory?.trim().isNotEmpty == true) {
      _filter = _filter.copyWith(category: widget.initialCategory!.trim());
    }
    _scrollController.addListener(_onScroll);
    _loadSearchHistory();
    _loadProducts();
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

  /// Increment page limit + refetch. Kalau hasil count sama dengan sebelum,
  /// berarti API sudah return all available products → `_hasMore = false`.
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final prevCount = _result.products.length;
    _pageLimit += 24;
    final result = await productService.fetchProducts(
      query: _query,
      limit: _pageLimit,
      newFilter: _filter.apiNewFilter,
      popularFilter: _filter.apiPopularFilter,
      inStock: _filter.inStockOnly,
      withImage: _filter.withImageOnly,
    );
    if (!mounted) return;
    setState(() {
      _result = result;
      _loadingMore = false;
      // Kalau count tidak naik = sudah habis, stop load more.
      _hasMore = result.products.length > prevCount;
    });
  }

  Future<void> _loadProducts() async {
    setState(() {
      _loading = true;
      // Reset pagination saat filter/query change.
      _pageLimit = 60;
      _hasMore = true;
    });
    final result = await productService.fetchProducts(
      query: _query,
      limit: _pageLimit,
      newFilter: _filter.apiNewFilter,
      popularFilter: _filter.apiPopularFilter,
      inStock: _filter.inStockOnly,
      withImage: _filter.withImageOnly,
    );
    if (!mounted) return;
    setState(() {
      _result = result;
      _loading = false;
    });
  }

  /// Handle tap pada pinned filter bar pill. Mapping mode → filter flags:
  /// - Semua: reset semua flag
  /// - Kategori: keep current category, expose chips row di bawah bar
  /// - Produk Baru: set apiNewFilter
  /// - Populer: set apiPopularFilter
  void _onFilterModeChanged(_ProductFilterMode mode) {
    if (mode == _ProductFilterMode.kategori) {
      _openCategorySheet();
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
          _filter = _filter.copyWith(sort: ProductSort.newest);
          break;
        case _ProductFilterMode.baru:
          _filter = _filter.copyWith(
            sort: ProductSort.newest,
            clearCategory: true,
          );
          break;
        case _ProductFilterMode.populer:
          _filter = _filter.copyWith(
            sort: ProductSort.popular,
            clearCategory: true,
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
    });
    _loadProducts();
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
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
    final suggestions = await productService.fetchSuggestions(keyword);
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
    });
    await _saveSearch(keyword);
    await _loadProducts();
  }

  void _applySuggestedCategory(String name) {
    setState(() {
      _filter = _filter.copyWith(category: name);
      _suggestions = const SearchSuggestionResult();
    });
    _loadProducts();
  }

  void _applySuggestedBrand(String name) {
    setState(() {
      _filter = _filter.copyWith(brand: name);
      _suggestions = const SearchSuggestionResult();
    });
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

  Future<void> _openSortSheet() async {
    final option = await showModalBottomSheet<_SortOption>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SortBottomSheet(
        selectedSort: _filter.sort,
        activeMode: _activeMode,
        inStockOnly: _filter.inStockOnly,
      ),
    );
    if (option == null) return;

    setState(() {
      switch (option) {
        case _SortOption.defaultOrder:
          _filter = _filter.copyWith(sort: ProductSort.newest);
          if (_filter.category == null && _filter.brand == null) {
            _activeMode = _ProductFilterMode.semua;
          }
          break;
        case _SortOption.newest:
          _filter = _filter.copyWith(sort: ProductSort.newest);
          _activeMode = _ProductFilterMode.baru;
          break;
        case _SortOption.bestSeller:
          _filter = _filter.copyWith(sort: ProductSort.popular);
          _activeMode = _ProductFilterMode.populer;
          break;
        case _SortOption.priceLow:
          _filter = _filter.copyWith(sort: ProductSort.priceLow);
          break;
        case _SortOption.priceHigh:
          _filter = _filter.copyWith(sort: ProductSort.priceHigh);
          break;
        case _SortOption.inStock:
          _filter = _filter.copyWith(inStockOnly: true);
          break;
      }
    });
    await _loadProducts();
  }

  Future<void> _openCategorySheet() async {
    final category = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CategoryBottomSheet(
        categories: _categories,
        selectedCategory: _filter.category,
      ),
    );
    if (category == null) return;

    setState(() {
      if (category == 'Semua') {
        _filter = const ProductCatalogFilter();
        _activeMode = _ProductFilterMode.semua;
      } else {
        _filter =
            _filter.copyWith(category: category, sort: ProductSort.newest);
        _activeMode = _ProductFilterMode.kategori;
      }
    });
    await _loadProducts();
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

  Future<void> _openFilterSheet() async {
    final next = await showModalBottomSheet<ProductCatalogFilter>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ProductFilterSheet(
        initialFilter: _filter,
        categories: _categories,
        brands: _brands,
        lockedBrand: widget.selectedBrand,
      ),
    );
    if (next == null) return;
    setState(() {
      _filter = next;
      if (next.category != null) {
        _activeMode = _ProductFilterMode.kategori;
      } else if (next.sort == ProductSort.popular) {
        _activeMode = _ProductFilterMode.populer;
      } else if (next.sort == ProductSort.newest) {
        _activeMode = _ProductFilterMode.semua;
      }
    });
    await _loadProducts();
  }

  /// Smart barcode lookup — pakai exact match dulu (slug, id, atau
  /// product title contains code), kalau ketemu → langsung navigate
  /// ke detail. Kalau tidak ketemu → fallback ke text search.
  ///
  /// Tidak butuh endpoint baru di backend — pure client-side dari
  /// data product yang sudah di-fetch.
  void _handleBarcodeResult(String code) {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return;

    // Try exact match: slug, id, atau title yang contains kode unik.
    Product? match;
    for (final product in _result.products) {
      if (product.id == trimmed ||
          product.slug == trimmed ||
          product.slug.endsWith(trimmed) ||
          product.title.toLowerCase().contains(trimmed.toLowerCase())) {
        match = product;
        break;
      }
    }

    if (match != null) {
      // Direct navigation — UX lebih cepat, tap scan = langsung detail.
      _openProduct(match);
      return;
    }

    // Fallback: set sebagai search query — user lihat list filtered
    // pakai sinonim. Cocok kalau barcode kontain string brand/SKU.
    _searchController.text = trimmed;
    _searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: trimmed.length),
    );
    _commitSearch(trimmed);
    // Tampilkan snackbar kasih konteks ke user.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
            'Produk dengan barcode "$trimmed" tidak ditemukan. Mencari di katalog...'),
      ),
    );
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
    _productReturnCount += 1;
    if (_productReturnCount < _nextCatalogRegenerateAt) return;
    setState(() {
      _catalogGeneration += 1;
      _productReturnCount = 0;
      _nextCatalogRegenerateAt = _nextCatalogRegenerateAt == 2 ? 3 : 2;
    });
  }

  @override
  Widget build(BuildContext context) {
    final products = _products;
    final title =
        widget.selectedBrand == null ? 'Produk' : widget.selectedBrand!;
    final hasLoadError =
        !_result.fromApi && _result.error != null && products.isEmpty;

    return Scaffold(
      backgroundColor: Colors.white,
      body: NataloPawRefreshIndicator(
        onRefresh: _refreshAll,
        child: SafeArea(
          bottom: false,
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: _ProductPageHeader(title: title),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _PinnedHeaderDelegate(
                  minExtent: 192,
                  maxExtent: 192,
                  child: _CatalogHeader(
                    controller: _searchController,
                    query: _query,
                    visibleCount: products.length,
                    totalCount: _result.total ?? products.length,
                    loading: _loading,
                    activeCategory: _filter.category,
                    activeFilterCount: _filter.activeCount,
                    activeMode: _activeMode,
                    onQueryChanged: _onQueryChanged,
                    onSubmitQuery: _commitSearch,
                    onBarcodeResult: _handleBarcodeResult,
                    onOpenSort: _openSortSheet,
                    onOpenFilters: _openFilterSheet,
                    onFilterModeChanged: _onFilterModeChanged,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _SearchSuggestionPanel(
                  query: _query,
                  suggestions: _suggestions,
                  loading: _suggestionLoading,
                  history: _searchHistory,
                  onProduct: (item) => _commitSearch(item.name),
                  onCategory: (item) => _applySuggestedCategory(item.name),
                  onBrand: (item) => _applySuggestedBrand(item.name),
                  onSearchQuery: _commitSearch,
                  onHistoryTap: _commitSearch,
                  onClearHistory: _clearSearchHistory,
                ),
              ),
              if (hasLoadError)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _ProductErrorState(onRetry: _loadProducts),
                )
              else if (_loading && products.isEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 112),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 20,
                      crossAxisSpacing: 14,
                      childAspectRatio: 0.52,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => const SkeletonProductCard(
                        showAddToCart: true,
                      ),
                      childCount: 8,
                    ),
                  ),
                )
              else if (products.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyProductsState(onReset: _resetFilters),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 112),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 20,
                      crossAxisSpacing: 14,
                      childAspectRatio: 0.52,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final product = products[index];
                        return ProductCard(
                          product: product,
                          onTap: () => _openProduct(product),
                          showAddToCart: true,
                          showWishlistButton: false,
                        );
                      },
                      childCount: products.length,
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
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, 116),
                    child: Center(
                      child: Text(
                        'Sudah sampai akhir katalog',
                        style: TextStyle(
                          color: NataloColors.textMuted,
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
  final String title;

  const _ProductPageHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _textPrimary,
                fontSize: 30,
                fontWeight: FontWeight.w900,
                height: 1.1,
              ),
            ),
          ),
          const AppCartButton(),
        ],
      ),
    );
  }
}

class _CatalogHeader extends StatelessWidget {
  final TextEditingController controller;
  final String query;
  final int visibleCount;
  final int totalCount;
  final bool loading;
  final String? activeCategory;
  final int activeFilterCount;
  final _ProductFilterMode activeMode;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String> onSubmitQuery;
  final ValueChanged<String> onBarcodeResult;
  final VoidCallback onOpenSort;
  final VoidCallback onOpenFilters;
  final ValueChanged<_ProductFilterMode> onFilterModeChanged;

  const _CatalogHeader({
    required this.controller,
    required this.query,
    required this.visibleCount,
    required this.totalCount,
    required this.loading,
    required this.activeCategory,
    required this.activeFilterCount,
    required this.activeMode,
    required this.onQueryChanged,
    required this.onSubmitQuery,
    required this.onBarcodeResult,
    required this.onOpenSort,
    required this.onOpenFilters,
    required this.onFilterModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.98),
        border: const Border(
          bottom: BorderSide(color: Color(0xFFF1F5F9)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppSearchField(
              controller: controller,
              hintText: 'Cari produk Natalo',
              query: query,
              onChanged: onQueryChanged,
              onClear: () {
                controller.clear();
                onQueryChanged('');
              },
              onSubmitted: onSubmitQuery,
              onVoiceTap: () async {
                // Voice search — buka modal, kembalikan transcript final lalu
                // commit search. Native SpeechRecognizer support partial +
                // bahasa Indonesia (id_ID) jauh lebih akurat dari WebView API.
                final result = await showVoiceSearchModal(context);
                if (result == null || result.isEmpty) return;
                controller.text = result;
                controller.selection = TextSelection.fromPosition(
                  TextPosition(offset: result.length),
                );
                onSubmitQuery(result);
              },
              onBarcodeTap: () async {
                // Barcode scan — native camera + ML Kit barcode detection.
                // Smart lookup: kalau code match product di list → langsung
                // navigate ke detail. Kalau tidak → fallback ke search.
                final code = await showBarcodeScanner(context);
                if (code == null || code.isEmpty) return;
                onBarcodeResult(code);
              },
            ),
            const SizedBox(height: 14),
            _ProductSummary(
              visibleCount: visibleCount,
              totalCount: totalCount,
              loading: loading,
              onOpenSort: onOpenSort,
            ),
            const SizedBox(height: 12),
            _GlassyFilterBar(
              selectedMode: activeMode,
              activeCategory: activeCategory,
              activeFilterCount: activeFilterCount,
              onChanged: onFilterModeChanged,
              onOpenAdvancedFilter: onOpenFilters,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyProductsState extends StatelessWidget {
  final VoidCallback onReset;

  const _EmptyProductsState({required this.onReset});

  @override
  Widget build(BuildContext context) {
    return Padding(
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
          const Text(
            'Produk tidak ditemukan',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: NataloColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Coba kata kunci lain atau ubah filter pencarian.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: NataloColors.textSecondary,
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
        ],
      ),
    );
  }
}

class _ProductErrorState extends StatelessWidget {
  final VoidCallback onRetry;

  const _ProductErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1F2),
              borderRadius: BorderRadius.circular(28),
            ),
            child: const Icon(
              Icons.wifi_off_rounded,
              color: _dangerRed,
              size: 42,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Gagal memuat produk',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Periksa koneksi internet kamu lalu coba lagi.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _textSecondary,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          ElevatedButton(
            onPressed: onRetry,
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
              'Coba Lagi',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
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
        return 'Populer';
    }
  }

  IconData get icon {
    switch (this) {
      case _ProductFilterMode.semua:
        return Icons.apps_rounded;
      case _ProductFilterMode.kategori:
        return Icons.category_rounded;
      case _ProductFilterMode.baru:
        return Icons.fiber_new_rounded;
      case _ProductFilterMode.populer:
        return Icons.local_fire_department_rounded;
    }
  }
}

/// Summary row: counter "Menampilkan X dari Y" + chip pill aktif filter mode.
class _ProductSummary extends StatelessWidget {
  final int visibleCount;
  final int totalCount;
  final bool loading;
  final VoidCallback onOpenSort;

  const _ProductSummary({
    required this.visibleCount,
    required this.totalCount,
    required this.loading,
    required this.onOpenSort,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            loading
                ? 'Memuat produk...'
                : 'Menampilkan $visibleCount dari $totalCount produk',
            style: const TextStyle(
              color: _textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onOpenSort,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF3FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _brandBlue.withValues(alpha: 0.14)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Urutkan',
                    style: TextStyle(
                      color: _brandBlue,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(width: 5),
                  Icon(
                    Icons.swap_vert_rounded,
                    color: _brandBlue,
                    size: 17,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Pinned glassy filter bar — sticky di top scroll, 4 pills equal width,
/// backdrop blur halus, animated selection. Tombol tune di kanan untuk
/// advanced filter sheet (brand, sort, stock, discount).
class _GlassyFilterBar extends StatelessWidget {
  final _ProductFilterMode selectedMode;
  final String? activeCategory;
  final int activeFilterCount;
  final ValueChanged<_ProductFilterMode> onChanged;
  final VoidCallback onOpenAdvancedFilter;

  const _GlassyFilterBar({
    required this.selectedMode,
    required this.activeCategory,
    required this.activeFilterCount,
    required this.onChanged,
    required this.onOpenAdvancedFilter,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _ProductFilterMode.values.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == _ProductFilterMode.values.length) {
            return _AdvancedFilterChip(
              count: activeFilterCount,
              onTap: onOpenAdvancedFilter,
            );
          }
          final mode = _ProductFilterMode.values[index];
          return _FilterPill(
            mode: mode,
            label: mode == _ProductFilterMode.kategori
                ? activeCategory ?? mode.label
                : mode.label,
            selected: selectedMode == mode,
            onTap: () => onChanged(mode),
          );
        },
      ),
    );
  }
}

class _AdvancedFilterChip extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _AdvancedFilterChip({
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final active = count > 0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: active ? _brandBlue : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: active ? _brandBlue : _borderSoft),
            boxShadow: [
              if (active)
                BoxShadow(
                  color: _brandBlue.withValues(alpha: 0.16),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.tune_rounded,
                size: 18,
                color: active ? Colors.white : _textSecondary,
              ),
              if (count > 0) ...[
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  final _ProductFilterMode mode;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterPill({
    required this.mode,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: selected ? _brandBlue : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: selected ? _brandBlue : _borderSoft),
        boxShadow: [
          if (selected)
            BoxShadow(
              color: _brandBlue.withValues(alpha: 0.16),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  mode.icon,
                  size: 17,
                  color: selected ? Colors.white : _textSecondary,
                ),
                const SizedBox(width: 7),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 104),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? Colors.white : _textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
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

class _CategoryBottomSheet extends StatelessWidget {
  final List<String> categories;
  final String? selectedCategory;

  const _CategoryBottomSheet({
    required this.categories,
    required this.selectedCategory,
  });

  @override
  Widget build(BuildContext context) {
    final items = ['Semua', ...categories];
    return _SheetShell(
      title: 'Pilih Kategori',
      subtitle: 'Filter produk berdasarkan kebutuhan hewan peliharaanmu.',
      child: Flexible(
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(
            height: 1,
            color: Color(0xFFF1F5F9),
          ),
          itemBuilder: (context, index) {
            final category = items[index];
            final selected = category == 'Semua'
                ? selectedCategory == null
                : selectedCategory == category;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                category,
                style: TextStyle(
                  color: selected ? _brandBlue : _textPrimary,
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                ),
              ),
              trailing: selected
                  ? const Icon(Icons.check_rounded, color: _brandBlue)
                  : null,
              onTap: () => Navigator.pop(context, category),
            );
          },
        ),
      ),
    );
  }
}

enum _SortOption {
  defaultOrder,
  newest,
  bestSeller,
  priceLow,
  priceHigh,
  inStock,
}

class _SortBottomSheet extends StatelessWidget {
  final ProductSort selectedSort;
  final _ProductFilterMode activeMode;
  final bool inStockOnly;

  const _SortBottomSheet({
    required this.selectedSort,
    required this.activeMode,
    required this.inStockOnly,
  });

  @override
  Widget build(BuildContext context) {
    final options = [
      _SortRowData(
        option: _SortOption.defaultOrder,
        title: 'Semua / Default',
        icon: Icons.apps_rounded,
        selected: activeMode == _ProductFilterMode.semua &&
            selectedSort == ProductSort.newest,
      ),
      _SortRowData(
        option: _SortOption.newest,
        title: 'Terbaru',
        icon: Icons.fiber_new_rounded,
        selected: activeMode == _ProductFilterMode.baru &&
            selectedSort == ProductSort.newest,
      ),
      _SortRowData(
        option: _SortOption.bestSeller,
        title: 'Terlaris',
        icon: Icons.local_fire_department_rounded,
        selected: selectedSort == ProductSort.popular,
      ),
      _SortRowData(
        option: _SortOption.priceLow,
        title: 'Harga termurah',
        icon: Icons.south_rounded,
        selected: selectedSort == ProductSort.priceLow,
      ),
      _SortRowData(
        option: _SortOption.priceHigh,
        title: 'Harga tertinggi',
        icon: Icons.north_rounded,
        selected: selectedSort == ProductSort.priceHigh,
      ),
      _SortRowData(
        option: _SortOption.inStock,
        title: 'Stok tersedia',
        icon: Icons.inventory_2_rounded,
        selected: inStockOnly,
      ),
    ];

    return _SheetShell(
      title: 'Urutkan Produk',
      subtitle: 'Pilih urutan katalog yang paling nyaman untuk kamu.',
      child: Flexible(
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: options.length,
          separatorBuilder: (_, __) => const Divider(
            height: 1,
            color: Color(0xFFF1F5F9),
          ),
          itemBuilder: (context, index) {
            final item = options[index];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: SoftIconTile(
                icon: item.icon,
                size: 40,
                color: item.selected ? _brandBlue : _textSecondary,
              ),
              title: Text(
                item.title,
                style: TextStyle(
                  color: item.selected ? _brandBlue : _textPrimary,
                  fontWeight: item.selected ? FontWeight.w900 : FontWeight.w700,
                ),
              ),
              trailing: item.selected
                  ? const Icon(Icons.check_rounded, color: _brandBlue)
                  : null,
              onTap: () => Navigator.pop(context, item.option),
            );
          },
        ),
      ),
    );
  }
}

class _SortRowData {
  final _SortOption option;
  final String title;
  final IconData icon;
  final bool selected;

  const _SortRowData({
    required this.option,
    required this.title,
    required this.icon,
    required this.selected,
  });
}

class _SheetShell extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _SheetShell({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, bottomInset + 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.72,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      height: 5,
                      width: 46,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    style: const TextStyle(
                      color: _textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: _textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 14),
                  child,
                ],
              ),
            ),
          ),
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
    final keyword = query.trim();
    final showSuggest = keyword.length >= 2;
    final showHistory = keyword.isEmpty && history.isNotEmpty;

    if (!showSuggest && !showHistory) return const SizedBox.shrink();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.92)),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Pencarian terakhir',
                style: TextStyle(
                  color: Color(0xFF17202A),
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
    if (loading) {
      return const Row(
        children: [
          SizedBox(
            height: 18,
            width: 18,
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
        const Text(
          'Saran pencarian',
          style: TextStyle(
            color: Color(0xFF17202A),
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
      leading: SoftIconTile(icon: icon, size: 38),
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

  const ProductCatalogFilter({
    this.category,
    this.brand,
    this.sort = ProductSort.newest,
    this.inStockOnly = true,
    this.discountOnly = false,
    this.withImageOnly = false,
  });

  String? get apiNewFilter => sort == ProductSort.newest ? 'newest' : null;

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
    return count;
  }

  ProductCatalogFilter copyWith({
    String? category,
    bool clearCategory = false,
    String? brand,
    bool clearBrand = false,
    ProductSort? sort,
    bool? inStockOnly,
    bool? discountOnly,
    bool? withImageOnly,
  }) {
    return ProductCatalogFilter(
      category: clearCategory ? null : category ?? this.category,
      brand: clearBrand ? null : brand ?? this.brand,
      sort: sort ?? this.sort,
      inStockOnly: inStockOnly ?? this.inStockOnly,
      discountOnly: discountOnly ?? this.discountOnly,
      withImageOnly: withImageOnly ?? this.withImageOnly,
    );
  }
}

class _ProductFilterSheet extends StatefulWidget {
  final ProductCatalogFilter initialFilter;
  final List<String> categories;
  final List<String> brands;
  final String? lockedBrand;

  const _ProductFilterSheet({
    required this.initialFilter,
    required this.categories,
    required this.brands,
    this.lockedBrand,
  });

  @override
  State<_ProductFilterSheet> createState() => _ProductFilterSheetState();
}

class _ProductFilterSheetState extends State<_ProductFilterSheet> {
  late ProductCatalogFilter _draft = widget.initialFilter;

  void _apply() => Navigator.pop(context, _draft);

  void _reset() {
    setState(() {
      _draft = ProductCatalogFilter(
        brand: widget.lockedBrand == null ? null : _draft.brand,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, bottomInset + 12),
      child: GlassSurface(
        radius: 30,
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.82,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    height: 5,
                    width: 46,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const SoftIconTile(
                      icon: Icons.tune_rounded,
                      size: 44,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Filter Produk',
                            style: TextStyle(
                              color: Color(0xFF17202A),
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            'Atur katalog agar lebih cepat ketemu.',
                            style: TextStyle(
                              color: Color(0xFF6B7280),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(onPressed: _reset, child: const Text('Reset')),
                  ],
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      _FilterSection(
                        title: 'Urutkan',
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _SortChip(
                              label: 'Terbaru',
                              selected: _draft.sort == ProductSort.newest,
                              onTap: () => setState(
                                () => _draft = _draft.copyWith(
                                  sort: ProductSort.newest,
                                ),
                              ),
                            ),
                            _SortChip(
                              label: 'Terlaris',
                              selected: _draft.sort == ProductSort.popular,
                              onTap: () => setState(
                                () => _draft = _draft.copyWith(
                                  sort: ProductSort.popular,
                                ),
                              ),
                            ),
                            _SortChip(
                              label: 'Rating',
                              selected: _draft.sort == ProductSort.rating,
                              onTap: () => setState(
                                () => _draft = _draft.copyWith(
                                  sort: ProductSort.rating,
                                ),
                              ),
                            ),
                            _SortChip(
                              label: 'Harga rendah',
                              selected: _draft.sort == ProductSort.priceLow,
                              onTap: () => setState(
                                () => _draft = _draft.copyWith(
                                  sort: ProductSort.priceLow,
                                ),
                              ),
                            ),
                            _SortChip(
                              label: 'Harga tinggi',
                              selected: _draft.sort == ProductSort.priceHigh,
                              onTap: () => setState(
                                () => _draft = _draft.copyWith(
                                  sort: ProductSort.priceHigh,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _FilterSection(
                        title: 'Kategori',
                        child: _HorizontalChoices(
                          values: widget.categories,
                          selected: _draft.category,
                          emptyLabel: 'Kategori belum tersedia',
                          onSelected: (value) => setState(() {
                            _draft = _draft.copyWith(
                              category: value == _draft.category ? null : value,
                              clearCategory: value == _draft.category,
                            );
                          }),
                        ),
                      ),
                      if (widget.lockedBrand == null)
                        _FilterSection(
                          title: 'Brand',
                          child: _HorizontalChoices(
                            values: widget.brands,
                            selected: _draft.brand,
                            emptyLabel: 'Brand belum tersedia',
                            onSelected: (value) => setState(() {
                              _draft = _draft.copyWith(
                                brand: value == _draft.brand ? null : value,
                                clearBrand: value == _draft.brand,
                              );
                            }),
                          ),
                        ),
                      _FilterSection(
                        title: 'Preferensi',
                        child: Column(
                          children: [
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _draft.inStockOnly,
                              onChanged: (value) => setState(
                                () => _draft =
                                    _draft.copyWith(inStockOnly: value),
                              ),
                              title: const Text('Hanya produk tersedia'),
                              subtitle: const Text('Sembunyikan stok kosong'),
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _draft.discountOnly,
                              onChanged: (value) => setState(
                                () => _draft =
                                    _draft.copyWith(discountOnly: value),
                              ),
                              title: const Text('Produk diskon'),
                              subtitle:
                                  const Text('Tampilkan yang sedang hemat'),
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _draft.withImageOnly,
                              onChanged: (value) => setState(
                                () => _draft =
                                    _draft.copyWith(withImageOnly: value),
                              ),
                              title: const Text('Dengan foto produk'),
                              subtitle:
                                  const Text('Prioritaskan katalog lengkap'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _apply,
                    icon: const Icon(Icons.check_rounded),
                    label: Text(
                      _draft.activeCount == 0
                          ? 'Terapkan Filter'
                          : 'Terapkan ${_draft.activeCount} Filter',
                    ),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
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

class _FilterSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _FilterSection({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
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
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _HorizontalChoices extends StatelessWidget {
  final List<String> values;
  final String? selected;
  final String emptyLabel;
  final ValueChanged<String> onSelected;

  const _HorizontalChoices({
    required this.values,
    required this.selected,
    required this.emptyLabel,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return Text(
        emptyLabel,
        style: const TextStyle(
          color: Color(0xFF6B7280),
          fontWeight: FontWeight.w700,
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: values.take(24).map((value) {
        final active = value == selected;
        return _SortChip(
          label: value,
          selected: active,
          onTap: () => onSelected(value),
        );
      }).toList(),
    );
  }
}

class _SortChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SortChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      selected: selected,
      label: Text(label),
      onSelected: (_) => onTap(),
      selectedColor: _brandBlue,
      backgroundColor: Colors.white.withValues(alpha: 0.82),
      side: BorderSide(color: selected ? _brandBlue : const Color(0xFFE5E7EB)),
      labelStyle: TextStyle(
        color: selected ? Colors.white : const Color(0xFF475569),
        fontWeight: FontWeight.w900,
        fontSize: 12,
      ),
    );
  }
}

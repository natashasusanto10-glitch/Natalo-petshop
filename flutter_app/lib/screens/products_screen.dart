import 'dart:async';
import 'dart:ui';

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
import '../widgets/app_product_image.dart';
import '../widgets/app_ui.dart';
import '../widgets/skeleton_product_card.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/natalo_paw_refresh_indicator.dart';

const _brandBlue = NataloColors.nataloBlue;
const _textPrimary = Color(0xFF102033);
const _textSecondary = Color(0xFF64748B);
const _dangerRed = Color(0xFFEF4444);

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

  // ── Connected glass dropdown untuk chip Kategori ──
  // LayerLink jadi anchor — dropdown follow posisi chip via
  // CompositedTransformFollower. Overlay rendered above semua content
  // (di atas product grid + appBar). Animation open/close memberi kesan
  // dropdown "keluar dari chip" dan "kembali ke chip".
  final LayerLink _categoryLayerLink = LayerLink();
  OverlayEntry? _categoryOverlay;
  bool _categoryDropdownOpen = false;

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
    // Cleanup overlay kalau masih open saat user navigate away.
    _categoryOverlay?.remove();
    _categoryOverlay = null;
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
      _toggleCategoryDropdown();
      return;
    }
    // Tutup dropdown kalau user pilih filter lain.
    if (_categoryDropdownOpen) _closeCategoryDropdown();
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

  /// Toggle connected glass dropdown untuk kategori. Bukan bottom sheet —
  /// overlay dengan LayerLink + CompositedTransformFollower supaya
  /// dropdown "keluar dari" chip Kategori. Animation open/close
  /// memberi kesan dropdown kembali ke chip.
  void _toggleCategoryDropdown() {
    if (_categoryDropdownOpen) {
      _closeCategoryDropdown();
    } else {
      _showCategoryDropdown();
    }
  }

  void _showCategoryDropdown() {
    if (_categoryOverlay != null) return;
    // Tutup keyboard kalau search bar lagi focus — supaya dropdown
    // tidak ketabrak/overlay dengan keyboard.
    FocusScope.of(context).unfocus();
    final categories = ['Semua', ..._categories];
    final entry = OverlayEntry(
      builder: (overlayContext) => _CategoryDropdownOverlay(
        link: _categoryLayerLink,
        categories: categories,
        selectedCategory: _filter.category,
        onSelect: _onCategorySelected,
        onDismiss: _closeCategoryDropdown,
      ),
    );
    Overlay.of(context).insert(entry);
    _categoryOverlay = entry;
    setState(() => _categoryDropdownOpen = true);
  }

  void _closeCategoryDropdown() {
    final overlay = _categoryOverlay;
    if (overlay == null) return;
    overlay.remove();
    _categoryOverlay = null;
    if (mounted) {
      setState(() => _categoryDropdownOpen = false);
    }
  }

  void _onCategorySelected(String category) {
    _closeCategoryDropdown();
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
    _loadProducts();
  }

  Future<void> _openSortSheet() async {
    FocusScope.of(context).unfocus();
    _closeCategoryDropdown();
    final picked = await showModalBottomSheet<ProductSort>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SortBottomSheet(currentSort: _filter.sort),
    );
    if (picked == null || picked == _filter.sort) return;
    setState(() => _filter = _filter.copyWith(sort: picked));
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
    final hasLoadError =
        !_result.fromApi && _result.error != null && products.isEmpty;
    final bottomPadding =
        kBottomNavigationBarHeight + MediaQuery.paddingOf(context).bottom + 16;

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
                    totalCount: _result.products.length,
                    categoryLayerLink: _categoryLayerLink,
                    onQueryChanged: _onQueryChanged,
                    onSubmitQuery: _commitSearch,
                    onFilterModeChanged: _onFilterModeChanged,
                    onOpenSort: _openSortSheet,
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
                  child: _EmptyProductsState(onReset: _resetFilters),
                )
              else
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
                      (context, index) {
                        final product = products[index];
                        return _ProductsPageProductCard(
                          product: product,
                          onTap: () => _openProduct(product),
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
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, bottomPadding),
                    child: const Center(
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
  const _ProductPageHeader();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Colors.white,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Text(
          'Produk Natalo',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Color(0xFF111827),
            fontSize: 22,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
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
  final LayerLink categoryLayerLink;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String> onSubmitQuery;
  final ValueChanged<_ProductFilterMode> onFilterModeChanged;
  final VoidCallback onOpenSort;

  const _CatalogHeader({
    required this.controller,
    required this.query,
    required this.activeMode,
    required this.selectedCategory,
    required this.visibleCount,
    required this.totalCount,
    required this.categoryLayerLink,
    required this.onQueryChanged,
    required this.onSubmitQuery,
    required this.onFilterModeChanged,
    required this.onOpenSort,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFF1F5F9)),
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
          // Product count + sort button row — di atas filter chips.
          _ProductCountAndSortRow(
            visibleCount: visibleCount,
            totalCount: totalCount,
            onOpenSort: onOpenSort,
          ),
          const SizedBox(height: 10),
          _HorizontalProductFilterChips(
            selectedMode: activeMode,
            selectedCategory: selectedCategory,
            categoryLayerLink: categoryLayerLink,
            onChanged: onFilterModeChanged,
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

/// Product count text + tombol Urutkan (compact soft blue).
class _ProductCountAndSortRow extends StatelessWidget {
  final int visibleCount;
  final int totalCount;
  final VoidCallback onOpenSort;

  const _ProductCountAndSortRow({
    required this.visibleCount,
    required this.totalCount,
    required this.onOpenSort,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
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
          // Urutkan button — glass ringan style match spec (inactive chip
          // family). Selaras visual dengan chip "Semua" / "Produk Baru"
          // di bawahnya supaya tidak ada inconsistency dua kotak yang
          // serupa tapi style beda.
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onOpenSort,
              borderRadius: BorderRadius.circular(22),
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: const Color(0xFFD8E4F4),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.035),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Urutkan',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                    ),
                    SizedBox(width: 6),
                    Icon(
                      Icons.swap_vert_rounded,
                      size: 19,
                      color: Color(0xFF64748B),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
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
    return SizedBox(
      height: 42,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        textInputAction: TextInputAction.search,
        style: const TextStyle(
          color: Color(0xFF111827),
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          hintText: 'Cari produk Natalo',
          hintStyle: const TextStyle(
            color: Color(0xFF6B7280),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            size: 22,
            color: Color(0xFF6B7280),
          ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 44, minHeight: 42),
          suffixIcon: query.isEmpty
              ? null
              : IconButton(
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: const Color(0xFF6B7280),
                  tooltip: 'Hapus',
                  visualDensity: VisualDensity.compact,
                ),
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
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
/// Kategori chip jadi anchor LayerLink untuk dropdown glass.
class _HorizontalProductFilterChips extends StatelessWidget {
  final _ProductFilterMode selectedMode;
  final String? selectedCategory;
  final LayerLink categoryLayerLink;
  final ValueChanged<_ProductFilterMode> onChanged;

  const _HorizontalProductFilterChips({
    required this.selectedMode,
    required this.selectedCategory,
    required this.categoryLayerLink,
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
                CompositedTransformTarget(
                  link: categoryLayerLink,
                  child: ProductFilterChip(
                    // Apply formatter — defensive kalau backend kasih slug
                    // mentah (mis. "snack-treat-anjing" → "Snack & Treat Anjing").
                    label: selectedCategory != null
                        ? formatCategoryLabel(selectedCategory!)
                        : mode.label,
                    icon: mode.icon,
                    selected: selectedMode == _ProductFilterMode.kategori,
                    onTap: () => onChanged(mode),
                  ),
                )
              else
                ProductFilterChip(
                  label: mode.label,
                  icon: mode.icon,
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
  final bool selected;
  final VoidCallback onTap;

  const ProductFilterChip({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
        color: selected ? null : Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: selected
              ? Colors.white.withValues(alpha: 0.35)
              : const Color(0xFFD8E4F4),
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
                Icon(
                  icon,
                  size: 18,
                  color: selected
                      ? Colors.white
                      : const Color(0xFF64748B),
                ),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected
                          ? Colors.white
                          : const Color(0xFF111827),
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
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
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
              _ProductGridImage(imageUrl: product.imageUrl),
              const SizedBox(height: 10),
              Text(
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
    return Container(
      height: 132,
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

class _ProductPriceRow extends StatelessWidget {
  final Product product;

  const _ProductPriceRow({required this.product});

  @override
  Widget build(BuildContext context) {
    final promoLabel = _productPromoLabel(product);
    return Row(
      children: [
        Expanded(
          child: Text(
            formatRupiah(product.finalPrice),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: _brandBlue,
              height: 1.1,
            ),
          ),
        ),
        if (promoLabel != null) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF93C5FD)),
            ),
            child: Text(
              promoLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: _brandBlue,
                height: 1,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ProductSavingBadge extends StatelessWidget {
  final Product product;

  const _ProductSavingBadge({required this.product});

  @override
  Widget build(BuildContext context) {
    final label = _productSavingLabel(product);
    if (label == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.confirmation_number_rounded,
            size: 13,
            color: Color(0xFFEF4444),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFFEF4444),
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
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Color(0xFF4B5563),
                height: 1,
              ),
            ),
          ],
          if (hasRating && hasSold) ...[
            const SizedBox(width: 5),
            const Text(
              '•',
              style: TextStyle(
                fontSize: 11,
                color: Color(0xFF9CA3AF),
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
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF4B5563),
                  height: 1,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String? _productPromoLabel(Product product) {
  final percent = product.discountPercent;
  if (percent != null && percent > 0) return 'Diskon $percent%';
  if (product.voucherPreview != null) return 'Promo';
  return null;
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

String _formatProductSoldCount(int count) {
  if (count >= 1000) {
    final value = count / 1000;
    final text =
        value >= 10 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
    return '${text.replaceAll('.', ',').replaceAll(',0', '')}rb+';
  }
  if (count >= 100) return '${(count ~/ 50) * 50}+';
  if (count >= 10) return '${(count ~/ 10) * 10}+';
  return count.toString();
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

// ════════════════════════════════════════════════════════════════
// Connected glass dropdown — kategori chip anchor → dropdown
// ════════════════════════════════════════════════════════════════

class _CategoryDropdownOverlay extends StatefulWidget {
  final LayerLink link;
  final List<String> categories;
  final String? selectedCategory;
  final ValueChanged<String> onSelect;
  final VoidCallback onDismiss;

  const _CategoryDropdownOverlay({
    required this.link,
    required this.categories,
    required this.selectedCategory,
    required this.onSelect,
    required this.onDismiss,
  });

  @override
  State<_CategoryDropdownOverlay> createState() =>
      _CategoryDropdownOverlayState();
}

class _CategoryDropdownOverlayState extends State<_CategoryDropdownOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<double> _scaleY;
  late final Animation<Offset> _offset;

  static const _openDuration = Duration(milliseconds: 240);
  static const _closeDuration = Duration(milliseconds: 200);

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: _openDuration,
      reverseDuration: _closeDuration,
    );
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _scaleY = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
    );
    _offset = Tween<Offset>(
      begin: const Offset(0, -8),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
    );
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _dismissWithAnimation() async {
    await _ctrl.reverse();
    if (mounted) widget.onDismiss();
  }

  Future<void> _handleSelect(String category) async {
    await _ctrl.reverse();
    if (!mounted) return;
    widget.onSelect(category);
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    // Spec: max 46% screen height — supaya product grid masih terlihat
    // sebagian di bawah sheet (visual reassurance konten tetap ada).
    final maxHeight = screenSize.height * 0.46;
    return Stack(
      children: [
        // Backdrop tap dismiss — transparent layer cover whole screen.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _dismissWithAnimation,
          ),
        ),
        // Dropdown anchored ke chip Kategori via LayerLink.
        Positioned(
          left: 16,
          right: 16,
          // Offset top: chip 44px height + gap 8 = 52
          child: CompositedTransformFollower(
            link: widget.link,
            showWhenUnlinked: false,
            offset: const Offset(0, 52),
            child: Material(
              color: Colors.transparent,
              child: FadeTransition(
                opacity: _opacity,
                child: SlideTransition(
                  position: _offset,
                  child: ScaleTransition(
                    scale: _scaleY,
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: maxHeight),
                      child: _GlassCategoryDropdown(
                        categories: widget.categories,
                        selectedCategory: widget.selectedCategory,
                        onSelect: _handleSelect,
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

/// Glass sheet untuk daftar kategori, anchored ke chip Kategori.
///
/// Spec:
/// - Frosted glass via BackdropFilter sigma 14 + bg white 0.78
/// - Border `#D9E8FA` 0.9 width 1, radius 24
/// - Soft shadow `#0F172A` 0.08 blur 28 offset (0, 14)
/// - List text-only (NO icon kategori, NO chevron right)
/// - Item padding horizontal 20, vertical 17
/// - Divider thin `#E6EEF8`
/// - Selected item: card bg `#EAF3FF` 0.88 + border `#C9DFFF` + radius 14,
///   text color `#1467D9` w800, check icon kanan
/// - Max height 46% screen, scrollable
/// - Connected notch (rotated square) di atas — visual connector ke chip aktif
class _GlassCategoryDropdown extends StatelessWidget {
  final List<String> categories;
  final String? selectedCategory;
  final ValueChanged<String> onSelect;

  const _GlassCategoryDropdown({
    required this.categories,
    required this.selectedCategory,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.78),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: const Color(0xFFD9E8FA).withValues(alpha: 0.9),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                    blurRadius: 28,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                itemCount: categories.length,
                separatorBuilder: (_, __) => const Divider(
                  height: 1,
                  thickness: 1,
                  color: Color(0xFFE6EEF8),
                  indent: 8,
                  endIndent: 8,
                ),
                itemBuilder: (context, index) {
                  final rawName = categories[index];
                  final label = rawName == 'Semua'
                      ? 'Semua'
                      : formatCategoryLabel(rawName);
                  final isSelected =
                      (selectedCategory == null && rawName == 'Semua') ||
                          (selectedCategory != null &&
                              rawName == selectedCategory);
                  return _CategoryDropdownItem(
                    label: label,
                    isSelected: isSelected,
                    onTap: () => onSelect(rawName),
                  );
                },
              ),
            ),
          ),
        ),
        // Connected notch — small rotated square di atas sheet untuk visual
        // connector ke chip aktif. Border top + left supaya match border
        // sheet (yang dirotate 45°). Size 18 cukup kecil, tidak dominan.
        Positioned(
          top: -8,
          left: 0,
          right: 0,
          child: Center(
            child: Transform.rotate(
              angle: 0.785398, // 45° in radians
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.85),
                  border: Border.all(
                    color: const Color(0xFFD9E8FA),
                    width: 1,
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

class _CategoryDropdownItem extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryDropdownItem({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
          decoration: isSelected
              ? BoxDecoration(
                  color: const Color(0xFFEAF3FF).withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFFC9DFFF),
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
                    fontWeight:
                        isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected
                        ? const Color(0xFF1467D9)
                        : const Color(0xFF111827),
                  ),
                ),
              ),
              if (isSelected)
                const Icon(
                  Icons.check_rounded,
                  color: Color(0xFF1467D9),
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
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: Colors.white,
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
                color: const Color(0xFFD8DEE7),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Urutkan berdasarkan',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
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
                        : const Color(0xFF0F172A),
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
                  color: const Color(0xFFE2E8F0).withValues(alpha: 0.75),
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

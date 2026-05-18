import 'package:flutter/material.dart';

import '../state/cart_store.dart';
import '../state/member_store.dart';
import '../theme/natalo_colors.dart';
import '../utils/formatters.dart';
import '../widgets/app_cart_button.dart';

/// Home screen — landing utama. Stub menampilkan greeting + cart count +
/// quick nav grid ke halaman utama. Real implementation: hero banner,
/// featured products, brand strip, dst (port dari app/page.tsx).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Natalo Petshop'),
        actions: const [AppCartButton()],
      ),
      body: SafeArea(
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
            final flashSale =
                products.where((p) => p.hasDiscount).take(8).toList();
            final bestSellers = ([...products]
                  ..sort((a, b) => b.reviewCount.compareTo(a.reviewCount)))
                .take(8)
                .toList();
            return RefreshIndicator(
              onRefresh: _refreshAll,
              color: _brandBlue,
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
                  if (result?.fromApi == false && result?.error != null)
                    SliverToBoxAdapter(
                        child: _ApiFallbackNotice(error: result!.error!)),
                  const SliverToBoxAdapter(child: _TrustMarquee()),
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
                  if (flashSale.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _FlashSaleGrid(
                        products: flashSale,
                        onTap: (product) =>
                            _openProductDetail(context, product),
                        onSeeAll: () => _openProducts(context),
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
                  // Rekomendasi personal dari kebiasaan user membuka detail
                  // produk. Kalau belum ada history, fallback ke promo/popular.
                  SliverToBoxAdapter(
                    child: AnimatedBuilder(
                      animation: recentlyViewedStore,
                      builder: (context, _) {
                        final recommendations =
                            _buildPersonalizedRecommendations(products);
                        if (recommendations.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return _RecommendationGrid(
                          products: recommendations,
                          personalized: recentlyViewedStore.isNotEmpty,
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
                              showAddToCart: true,
                            );
                          }
                          if (index >= _exploreProducts.length) {
                            // Safety guard
                            return const SizedBox.shrink();
                          }
                          final product = _exploreProducts[index];
                          return ProductCard(
                            product: product,
                            onTap: () => _openProductDetail(context, product),
                            showAddToCart: true,
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

class _ApiFallbackNotice extends StatelessWidget {
  final String error;

  const _ApiFallbackNotice({required this.error});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: AppInfoBanner(
        icon: Icons.cloud_off_outlined,
        message: 'Koneksi ke server bermasalah. Tarik ke bawah untuk muat '
            'ulang. ($error)',
      ),
    );
  }
}

class _HomeStickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  final VoidCallback onOpenProducts;
  final VoidCallback onOpenSearch;

  const _HomeStickyHeaderDelegate({
    required this.onOpenProducts,
    required this.onOpenSearch,
  });

  @override
  double get minExtent => 128;

  @override
  double get maxExtent => 128;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(
          bottom: BorderSide(color: Color(0xFFEFF4FA)),
        ),
        boxShadow: overlapsContent || shrinkOffset > 0
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ]
            : const [],
      ),
      child: _HomeHeader(
        onOpenProducts: onOpenProducts,
        onOpenSearch: onOpenSearch,
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _HomeStickyHeaderDelegate oldDelegate) {
    return oldDelegate.onOpenProducts != onOpenProducts ||
        oldDelegate.onOpenSearch != onOpenSearch;
  }
}

class _HomeHeader extends StatelessWidget {
  final VoidCallback onOpenProducts;
  final VoidCallback onOpenSearch;

  const _HomeHeader({
    required this.onOpenProducts,
    required this.onOpenSearch,
  });

  @override
  Widget build(BuildContext context) {
    // Clean header sesuai design pattern reference:
    // - Logo box compact dengan brand primary bg + radius 13
    // - Title 17 w900 + subtitle 12 textSecondary
    // - 2 icon button kanan (notifikasi, cart)
    // - Search field full-width pakai default Material 3 input
    // No glass wrapper — pakai surface ThemeData (lebih cepat di HP murah,
    // lebih readable outdoor).
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 13),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFF0B7FEA),
                  borderRadius: BorderRadius.circular(13),
                ),
                clipBehavior: Clip.antiAlias,
                alignment: Alignment.center,
                // Logo asset utama — pakai icon-only.png (square iOS-style)
                // yang exact match dengan logo Capacitor. assets/brand/logo.png
                // adalah wordmark horizontal lebar (kurang cocok untuk 42x42
                // square box karena BoxFit.cover akan crop). Fallback ke "NL"
                // letter kalau image hilang (defensive).
                child: Image.asset(
                  'assets/native/icon-only.png',
                  width: 38,
                  height: 38,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Text(
                    'NL',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Natalo Petshop',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF17202A),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Kebutuhan hewan kesayanganmu',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
              const AppNotificationButton(),
              const AppCartButton(),
            ],
          ),
          const SizedBox(height: 10),
          // Search field — tap area buka full-screen search sheet.
          // Render custom pill agar tidak mewarisi intrinsic height TextField
          // yang bisa overflow 1-2 px di debug mode pada device tertentu.
          GestureDetector(
            onTap: onOpenSearch,
            behavior: HitTestBehavior.opaque,
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: Color(0xFF94A3B8),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Cari makanan, vitamin, pasir...',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
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
    AppAnalytics.logSearch(keyword);
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
  const _TrustMarquee();

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
      height: 38,
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: SizedBox(
        height: 184,
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.white.withValues(alpha: 0.56)),
          boxShadow: [
            BoxShadow(
              color: _brandBlue.withValues(alpha: 0.18),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
          color: const Color(0xFFEAF5FF),
        ),
        clipBehavior: Clip.antiAlias,
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

  static const _maxVisible = 6;

  const _FlashSaleGrid({
    required this.products,
    required this.onTap,
    required this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) return const SizedBox.shrink();

    final visible = products.take(_maxVisible).toList();
    final hasMore = products.length > _maxVisible;

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
                      'Diskon spesial dari admin Natalo',
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
    final off = product.discountPercent ?? 0;
    final hasMarkdown = product.hasDiscount;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEEF3FB)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF111111).withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: AppProductImage(
                        imageUrl: product.imageUrl,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  if (off > 0)
                    Positioned(
                      left: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '-$off%',
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
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 32,
                    child: Text(
                      product.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF334155),
                        fontSize: 11,
                        height: 1.25,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatRupiah(product.finalPrice),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NataloTextStyles.productPrice.copyWith(
                      fontSize: 13,
                      height: 1.05,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (hasMarkdown)
                    Text(
                      formatRupiah(product.price),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 10,
                        decoration: TextDecoration.lineThrough,
                      ),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 150,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFEEF3FB)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF111111).withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: AppProductImage(
                        imageUrl: product.imageUrl,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  if (rank != null)
                    Positioned(
                      left: 8,
                      top: 8,
                      child: CircleAvatar(
                        radius: 12,
                        backgroundColor: rank == 1
                            ? const Color(0xFFF59E0B)
                            : rank == 2
                                ? const Color(0xFFE5E7EB)
                                : _brandBlue,
                        child: Text(
                          '$rank',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF334155),
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    formatRupiah(product.finalPrice),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: NataloColors.nataloBlue,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      height: 1.05,
                    ),
                  ),
                  ProductSavingsBadge(product: product),
                  ProductRatingSoldMeta(product: product),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandChoiceSection extends StatelessWidget {
  final List<PetBrand> brands;
  final ValueChanged<PetBrand> onTap;

  const _BrandChoiceSection({required this.brands, required this.onTap});

  @override
  Widget build(BuildContext context) {
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
            height: 102,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: brands.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final brand = brands[index];
                return InkWell(
                  onTap: () => onTap(brand),
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    width: 112,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircleAvatar(
                          radius: 24,
                          backgroundColor: NataloColors.primary,
                          child: Icon(
                            Icons.pets_rounded,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                profile == null
                                    ? 'Halo, tamu'
                                    : 'Halo, ${profile.name}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                profile == null
                                    ? 'Login untuk akses pesanan + voucher'
                                    : profile.email ?? profile.phone ?? '',
                                style: const TextStyle(
                                  color: NataloColors.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (profile == null)
                          FilledButton(
                            onPressed: () => Navigator.pushNamed(
                              context,
                              '/member/login',
                            ),
                            child: const Text('Login'),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            _QuickGrid(),
            const SizedBox(height: 16),
            AnimatedBuilder(
              animation: cartStore,
              builder: (context, _) {
                if (cartStore.isEmpty) return const SizedBox.shrink();
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.shopping_cart_rounded),
                    title: Text('${cartStore.count} item di keranjang'),
                    subtitle: Text(
                      'Total: ${formatRupiah(cartStore.subtotal)}',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.pushNamed(context, '/cart'),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickGrid extends StatelessWidget {
  static const _items = [
    _QuickItem(Icons.storefront_rounded, 'Produk', '/products'),
    _QuickItem(Icons.local_offer_rounded, 'Brand', '/brands'),
    _QuickItem(Icons.video_library_rounded, 'Feed', '/feed'),
    _QuickItem(Icons.favorite_rounded, 'Wishlist', '/wishlist'),
    _QuickItem(Icons.receipt_long_rounded, 'Pesanan', '/member/orders'),
    _QuickItem(Icons.person_rounded, 'Akun', '/member'),
  ];

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
          const SizedBox(height: 4),
          Text(
            personalized
                ? 'Dipilih dari kategori dan brand yang sering kamu lihat'
                : 'Produk pilihan berdasarkan minat dan aktivitas belanjamu',
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 12,
              fontWeight: FontWeight.w600,
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
              return ProductCard(
                product: product,
                onTap: () => onTap(product),
                showAddToCart: true,
              );
            },
          ),
        ],
      ),
      itemBuilder: (context, i) {
        final item = _items[i];
        return Card(
          child: InkWell(
            onTap: () => Navigator.pushNamed(context, item.route),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    item.icon,
                    size: 28,
                    color: NataloColors.primary,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.label,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _QuickItem {
  final IconData icon;
  final String label;
  final String route;
  const _QuickItem(this.icon, this.label, this.route);
}

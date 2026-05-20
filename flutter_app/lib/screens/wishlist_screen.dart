import 'package:flutter/material.dart';

import '../models/product.dart';
import '../services/product_service.dart';
import '../state/cart_store.dart';
import '../state/favorite_store.dart';
import '../state/member_store.dart';
import '../state/recently_viewed_store.dart';
import '../state/search_history_store.dart';
import '../theme/natalo_colors.dart';
import '../utils/haptics.dart';
import '../widgets/app_cart_button.dart';
import '../widgets/app_toast.dart';
import '../widgets/app_ui.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/compact_commerce_product_card.dart';
import '../widgets/natalo_paw_refresh_indicator.dart';
import '../widgets/skeleton_product_card.dart';

const _brandBlue = NataloColors.primary;
const _lookAgainPageSize = 12;

/// Wishlist screen — member-only. Daftar produk yang user star, plus section
/// "Ayo Dilihat Kembali" dengan ranked recommendations berdasar search
/// history + recently viewed + favorites.
class WishlistScreen extends StatefulWidget {
  const WishlistScreen({super.key});

  @override
  State<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends State<WishlistScreen> {
  late Future<List<Product>> _productsFuture;
  final ScrollController _scrollController = ScrollController();

  // Search history — dipakai untuk rank "Look Again" recommendations.
  // TODO: load dari SearchHistoryStore atau SharedPreferences.
  List<String> _searchHistory = const [];

  // Look Again pagination state.
  List<Product> _lookAgainProducts = const [];
  int _lookAgainPage = 0;
  bool _lookAgainHasMore = false;
  bool _lookAgainLoading = false;
  bool _lookAgainInitialLoaded = false;

  @override
  void initState() {
    super.initState();
    _productsFuture = _loadProducts();
    _scrollController.addListener(_handleScroll);
    _loadSearchHistory();
    _loadLookAgain(initial: true);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients ||
        _lookAgainLoading ||
        !_lookAgainHasMore) {
      return;
    }

    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 420) {
      _loadLookAgain();
    }
  }

  /// Load favorite products dari favoriteStore atau API.
  Future<List<Product>> _loadProducts() async {
    if (!memberStore.isLoggedIn) return const [];
    try {
      await favoriteStore.refresh();
      return favoriteStore.fetchFavoriteProducts();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _loadSearchHistory() async {
    await searchHistoryStore.initialize();
    if (mounted) {
      setState(() => _searchHistory = searchHistoryStore.entries);
    }
  }

  /// Load look-again recommendations. Backend saat ini belum expose cursor,
  /// jadi pagination dibuat dengan menaikkan limit bertahap lalu dedupe.
  Future<void> _loadLookAgain({bool initial = false}) async {
    if (_lookAgainLoading) return;
    if (!initial && !_lookAgainHasMore) return;

    final nextPage = initial ? 1 : _lookAgainPage + 1;
    final requestLimit = nextPage * _lookAgainPageSize;
    final previousCount = initial ? 0 : _lookAgainProducts.length;

    if (mounted) {
      setState(() {
        if (initial) {
          _lookAgainProducts = const [];
          _lookAgainPage = 0;
          _lookAgainHasMore = false;
          _lookAgainInitialLoaded = false;
        }
        _lookAgainLoading = true;
      });
    }

    try {
      var result = await productService.fetchRecommendations(
        viewedIds: recentlyViewedStore.items.map((p) => p.id).toList(),
        excludeIds: favoriteStore.ids.toList(),
        limit: requestLimit,
      );
      if (result.length < requestLimit) {
        final fallback = await productService.fetchAll(limit: requestLimit);
        final merged = <String, Product>{};
        for (final product in [...result, ...fallback]) {
          if (product.id.isEmpty || favoriteStore.isFavorite(product.id)) {
            continue;
          }
          merged.putIfAbsent(product.id, () => product);
        }
        result = merged.values.toList(growable: false);
      }

      final nextProducts = _rankLookAgainProducts(result)
          .where((product) => !favoriteStore.isFavorite(product.id))
          .fold<Map<String, Product>>(
            <String, Product>{},
            (map, product) {
              if (product.id.isNotEmpty) {
                map.putIfAbsent(product.id, () => product);
              }
              return map;
            },
          )
          .values
          .toList(growable: false);

      if (!mounted) return;
      setState(() {
        _lookAgainProducts = nextProducts;
        _lookAgainPage = nextPage;
        _lookAgainHasMore = nextProducts.length >= requestLimit &&
            nextProducts.length > previousCount;
        _lookAgainLoading = false;
        _lookAgainInitialLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _lookAgainLoading = false;
        _lookAgainInitialLoaded = true;
      });
    }
  }

  /// Rank products berdasar relevance ke user (search history + recently
  /// viewed + product attributes). Higher score = lebih cocok ditampilkan
  /// di atas.
  List<Product> _rankLookAgainProducts(List<Product> products) {
    if (products.length <= 1) return products;
    final ranked = [...products]..sort((a, b) {
        final scoreCompare = _lookAgainScore(b).compareTo(_lookAgainScore(a));
        if (scoreCompare != 0) return scoreCompare;
        final ratingCompare = b.rating.compareTo(a.rating);
        if (ratingCompare != 0) return ratingCompare;
        return b.reviewCount.compareTo(a.reviewCount);
      });
    return ranked;
  }

  int _lookAgainScore(Product product) {
    final haystack =
        '${product.title} ${product.brand} ${product.category}'.toLowerCase();
    var score = 0;

    for (var index = 0; index < _searchHistory.length; index += 1) {
      final term = _searchHistory[index].trim().toLowerCase();
      if (term.isEmpty) continue;
      final weight = (_searchHistory.length - index).clamp(1, 8);
      if (haystack.contains(term)) score += (weight * 12).toInt();
      for (final token in term.split(RegExp(r'\s+'))) {
        if (token.length >= 3 && haystack.contains(token)) {
          score += (weight * 4).toInt();
        }
      }
    }

    for (final viewed in recentlyViewedStore.items.take(12)) {
      if (viewed.id == product.id) score += 10;
      if (viewed.category.isNotEmpty && viewed.category == product.category) {
        score += 5;
      }
      if (viewed.brand.isNotEmpty && viewed.brand == product.brand) {
        score += 4;
      }
    }

    if (product.hasDiscount) score += 2;
    score += product.reviewCount.clamp(0, 250) ~/ 50;
    return score;
  }

  Future<void> _refresh() async {
    AppHaptics.impact();
    if (memberStore.isLoggedIn) {
      await favoriteStore.refresh();
    }
    setState(() => _productsFuture = _loadProducts());
    await _productsFuture;
    await _loadSearchHistory();
    await _loadLookAgain(initial: true);
  }

  void _openProduct(Product product) {
    Navigator.pushNamed(context, '/product-detail', arguments: product)
        .then((_) => _refresh());
  }

  void _addToCart(Product product) {
    AppHaptics.success();
    cartStore.addProduct(product);
    AppToast.showCartAdded(
      context,
      '${product.title} masuk keranjang',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!memberStore.isLoggedIn) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Wishlist'),
          actions: const [AppCartButton()],
        ),
        body: AppEmptyState(
          lottiePath: AppLottiePaths.paw,
          lottieHeight: 180,
          icon: Icons.favorite_border_rounded,
          title: 'Wishlist khusus member',
          subtitle:
              'Login untuk menyimpan produk favorit dan membukanya kembali.',
          action: ElevatedButton(
            onPressed: () => Navigator.pushNamed(context, '/member/login'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _brandBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: 28,
                vertical: 14,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            child: const Text(
              'Masuk Member',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
            ),
          ),
        ),
        bottomNavigationBar: const BottomNavBar(currentIndex: 3),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        titleSpacing: 8,
        toolbarHeight: 64,
        // Cart icon di kanan atas — match home AppCartButton 1:1
        // (shopping_cart_outlined, 24px, badge merah live sync via
        // cartStore). Konsisten visual antar home, wishlist, dan
        // halaman lain yang punya header.
        actions: const [AppCartButton()],
        // Title — "Wishlist" saja saat kosong; tambah subtitle hanya
        // kalau ada item (per user request, hilangkan "0 produk disimpan"
        // yang redundant di empty state — placeholder hero card sudah
        // communicate state-nya).
        title: AnimatedBuilder(
          animation: favoriteStore,
          builder: (context, _) {
            final hasItems = favoriteStore.count > 0;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Wishlist',
                  style: TextStyle(
                    color: Color(0xFF17202A),
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
                if (hasItems) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${favoriteStore.count} produk disimpan',
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
      body: FutureBuilder<List<Product>>(
        future: _productsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            // Shimmer grid 2-col untuk wishlist — feels lebih native daripada
            // generic list skeleton.
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 132),
              children: const [
                SkeletonProductGrid(count: 6, showAddToCart: true),
                SizedBox(height: 24),
                SkeletonProductGrid(count: 4, showAddToCart: true),
              ],
            );
          }

          final products = snapshot.data ?? const <Product>[];
          final wishlistIds = products.map((product) => product.id).toSet();
          final lookAgain = _lookAgainProducts
              .where((product) => !wishlistIds.contains(product.id))
              .toList();
          return NataloPawRefreshIndicator(
            onRefresh: _refresh,
            child: CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                if (products.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: _WishlistEmptyCard(
                        onExploreProducts: () {
                          AppHaptics.tap();
                          Navigator.pushReplacementNamed(context, '/products');
                        },
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.54,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final product = products[index];
                          return AppAnimatedEntrance(
                            index: index,
                            child: CompactCommerceProductCard(
                              product: product,
                              onTap: () => _openProduct(product),
                              onAddToCart: () => _addToCart(product),
                            ),
                          );
                        },
                        childCount: products.length,
                      ),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: _LookAgainHeader(
                      hasSearchHistory: _searchHistory.isNotEmpty),
                ),
                if (!_lookAgainInitialLoaded && _lookAgainLoading)
                  const SliverPadding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
                    sliver: SliverToBoxAdapter(
                      child: SkeletonProductGrid(count: 4, showAddToCart: true),
                    ),
                  )
                else if (lookAgain.isEmpty)
                  const SliverToBoxAdapter(child: SizedBox.shrink())
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.54,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final product = lookAgain[index];
                          return AppAnimatedEntrance(
                            index: index,
                            child: CompactCommerceProductCard(
                              product: product,
                              onTap: () => _openProduct(product),
                              onAddToCart: () => _addToCart(product),
                            ),
                          );
                        },
                        childCount: lookAgain.length,
                      ),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 132),
                    child: _LookAgainFooter(
                      loading: _lookAgainLoading,
                      hasMore: _lookAgainHasMore,
                      hasItems: lookAgain.isNotEmpty,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: const BottomNavBar(currentIndex: 3),
    );
  }
}

/// Empty state Wishlist — match PWA pattern (sama dengan Cart empty):
/// illustration card + judul + body + CTA.
class _WishlistEmptyCard extends StatelessWidget {
  final VoidCallback onExploreProducts;

  const _WishlistEmptyCard({required this.onExploreProducts});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: const Color(0xFFD9E7FF),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.045),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          const _WishlistIllustration(),
          const SizedBox(height: 10),
          const Text(
            'Wishlist kamu masih kosong',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 24,
              height: 1.18,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Simpan makanan, vitamin, pasir, atau perlengkapan\nfavorit agar mudah dibeli lagi nanti.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF64748B),
              fontSize: 16,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Tekan ikon hati pada produk yang kamu suka.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF98A2B3),
              fontSize: 15,
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: onExploreProducts,
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: _brandBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
              child: const Text(
                'Jelajahi Produk',
                style: TextStyle(
                  fontSize: 17,
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

class _LookAgainHeader extends StatelessWidget {
  final bool hasSearchHistory;

  const _LookAgainHeader({required this.hasSearchHistory});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ayo dilihat kembali',
            style: TextStyle(
              color: Color(0xFF17202A),
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hasSearchHistory
                ? 'Dipilih dari kebiasaan pencarian dan produk yang kamu lihat.'
                : 'Produk pilihan yang mungkin cocok untuk kamu.',
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _LookAgainFooter extends StatelessWidget {
  final bool loading;
  final bool hasMore;
  final bool hasItems;

  const _LookAgainFooter({
    required this.loading,
    required this.hasMore,
    required this.hasItems,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: SizedBox(
          height: 26,
          width: 26,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      );
    }
    if (!hasMore && hasItems) {
      return const Center(
        child: Text(
          'Semua rekomendasi sudah tampil',
          style: TextStyle(
            color: Color(0xFF9CA3AF),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    return const SizedBox(height: 24);
  }
}

/// Wishlist illustration: same petshop family as empty cart, but with a clear
/// wishlist heart marker on the Natalo bag.
class _WishlistIllustration extends StatelessWidget {
  const _WishlistIllustration();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 245,
      width: double.infinity,
      child: Center(
        child: AspectRatio(
          aspectRatio: 640 / 335,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final height = constraints.maxHeight;
              return Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    'assets/images/empty_wishlist_natalo.png',
                    fit: BoxFit.contain,
                  ),
                  Positioned(
                    left: width * 0.43,
                    top: height * 0.54,
                    child: Container(
                      width: width * 0.15,
                      height: width * 0.13,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0475D8).withValues(alpha: 0.88),
                        borderRadius: BorderRadius.circular(width * 0.04),
                      ),
                      child: Icon(
                        Icons.favorite_rounded,
                        color: Colors.white,
                        size: width * 0.13,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

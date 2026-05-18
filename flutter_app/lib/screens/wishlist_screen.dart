import 'package:flutter/material.dart';

import '../models/product.dart';
import '../services/product_service.dart';
import '../state/favorite_store.dart';
import '../state/member_store.dart';
import '../state/recently_viewed_store.dart';
import '../state/search_history_store.dart';
import '../theme/natalo_colors.dart';
import '../utils/haptics.dart';
import '../widgets/app_ui.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/product_card.dart';
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

  @override
  Widget build(BuildContext context) {
    if (!memberStore.isLoggedIn) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Wishlist')),
        body: AppEmptyState(
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
        // Title style match PWA wishlist: "Wishlist\n{N} produk disimpan"
        title: AnimatedBuilder(
          animation: favoriteStore,
          builder: (context, _) {
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
          return RefreshIndicator(
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
                            child: ProductCard(
                              product: product,
                              onTap: () => _openProduct(product),
                              showAddToCart: true,
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
                            child: ProductCard(
                              product: product,
                              onTap: () => _openProduct(product),
                              showAddToCart: true,
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
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFDDE8F8)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF111111).withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          const _WishlistIllustration(),
          const SizedBox(height: 14),
          const Text(
            'Wishlist kamu masih kosong',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF17202A),
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'Simpan makanan, vitamin, pasir, atau perlengkapan favorit agar mudah dibeli lagi nanti.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Tekan ikon hati pada produk yang kamu suka.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF9CA3AF),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          ElevatedButton(
            onPressed: onExploreProducts,
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
              'Jelajahi Produk',
              style: TextStyle(
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

/// Wishlist illustration: heart icon dengan pet emoji di sekeliling.
class _WishlistIllustration extends StatelessWidget {
  const _WishlistIllustration();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 130,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Container(
            height: 130,
            width: 200,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFFFE4E6).withValues(alpha: 0.50),
                  _brandBlue.withValues(alpha: 0.06),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
            ),
          ),
          const Positioned(
            left: 8,
            top: 18,
            child: Text('🐱', style: TextStyle(fontSize: 38)),
          ),
          const Positioned(
            top: 0,
            child: Text('🐶', style: TextStyle(fontSize: 44)),
          ),
          const Positioned(
            right: 8,
            top: 18,
            child: Text('🐰', style: TextStyle(fontSize: 38)),
          ),
          const Positioned(
            left: 30,
            bottom: 4,
            child: Text('🐠', style: TextStyle(fontSize: 30)),
          ),
          const Positioned(
            right: 28,
            bottom: 6,
            child: Text('🐹', style: TextStyle(fontSize: 32)),
          ),
          Positioned(
            bottom: 18,
            child: Container(
              height: 62,
              width: 62,
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.32),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(
                Icons.favorite_rounded,
                color: Colors.white,
                size: 32,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

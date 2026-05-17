import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/product.dart';
import '../services/product_service.dart';
import '../state/favorite_store.dart';
import '../state/member_store.dart';
import '../state/recently_viewed_store.dart';
import '../utils/haptics.dart';
import '../widgets/app_motion.dart';
import '../widgets/app_ui.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/product_card.dart';
import '../widgets/skeleton_product_card.dart';

const _brandBlue = Color(0xFF0B7FEA);
const _searchHistoryKey = 'natalo_search_history';

class WishlistScreen extends StatefulWidget {
  const WishlistScreen({super.key});

  @override
  State<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends State<WishlistScreen> {
  late Future<List<Product>> _productsFuture;
  final ScrollController _scrollController = ScrollController();
  final List<Product> _lookAgainProducts = [];
  List<String> _searchHistory = const [];
  String? _lookAgainCursor;
  bool _lookAgainLoading = false;
  bool _lookAgainHasMore = true;
  bool _lookAgainInitialLoaded = false;

  @override
  void initState() {
    super.initState();
    _productsFuture = _loadProducts();
    _scrollController.addListener(_onScroll);
    _loadSearchHistory().then((_) => _loadLookAgain(initial: true));
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<List<Product>> _loadProducts() async {
    if (!memberStore.isLoggedIn) return [];
    return favoriteStore.fetchFavoriteProducts();
  }

  Future<void> _loadSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _searchHistory =
          (prefs.getStringList(_searchHistoryKey) ?? const []).take(8).toList();
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients ||
        _lookAgainLoading ||
        !_lookAgainHasMore) {
      return;
    }
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 520) {
      _loadLookAgain();
    }
  }

  Future<void> _loadLookAgain({bool initial = false}) async {
    if (_lookAgainLoading) return;
    if (!initial && !_lookAgainHasMore) return;
    setState(() {
      _lookAgainLoading = true;
      if (initial) {
        _lookAgainProducts.clear();
        _lookAgainCursor = null;
        _lookAgainHasMore = true;
        _lookAgainInitialLoaded = false;
      }
    });

    final page = await productService.fetchProductsPage(
      cursor: _lookAgainCursor,
      limit: 18,
      excludeIds: favoriteStore.ids.toList(),
    );
    if (!mounted) return;
    final nextProducts = _rankLookAgainProducts(page.products);
    setState(() {
      final existingIds =
          _lookAgainProducts.map((product) => product.id).toSet();
      _lookAgainProducts.addAll(
        nextProducts.where((product) => existingIds.add(product.id)),
      );
      _lookAgainCursor = page.nextCursor;
      _lookAgainHasMore = page.hasMore && page.products.isNotEmpty;
      _lookAgainLoading = false;
      _lookAgainInitialLoaded = true;
    });
  }

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
      if (haystack.contains(term)) score += weight * 12;
      for (final token in term.split(RegExp(r'\s+'))) {
        if (token.length >= 3 && haystack.contains(token)) {
          score += weight * 4;
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
          title: 'Wishlist khusus member',
          body: 'Login untuk menyimpan produk favorit dan membukanya kembali.',
          buttonLabel: 'Masuk Member',
          onPressed: () => Navigator.pushNamed(context, '/member/login'),
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
                        childAspectRatio: 0.58,
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
                        childAspectRatio: 0.58,
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

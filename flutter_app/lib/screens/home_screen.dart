import 'package:flutter/material.dart';

import '../models/product.dart';
import '../services/product_service.dart';
import '../state/member_store.dart';
import '../theme/natalo_colors.dart';
import '../widgets/app_cart_button.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/product_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<Product>> _productsFuture;

  @override
  void initState() {
    super.initState();
    _productsFuture = productService.fetchAll(limit: 24);
  }

  Future<void> _refresh() async {
    final future = productService.fetchAll(limit: 24);
    setState(() => _productsFuture = future);
    await future;
  }

  void _openProducts({String? category}) {
    Navigator.pushNamed(
      context,
      '/products',
      arguments: category == null
          ? null
          : ProductCatalogArgs(initialCategory: category),
    );
  }

  void _openProduct(Product product) {
    Navigator.pushNamed(context, '/product-detail', arguments: product);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F9FF),
      appBar: AppBar(
        title: const Text('Natalo Petshop'),
        actions: const [AppCartButton()],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: FutureBuilder<List<Product>>(
            future: _productsFuture,
            builder: (context, snapshot) {
              final products = snapshot.data ?? const <Product>[];
              final promo =
                  products.where((product) => product.hasDiscount).toList();
              final popular = [...products]
                ..sort((a, b) => b.soldCount.compareTo(a.soldCount));

              return ListView(
                padding: const EdgeInsets.fromLTRB(0, 12, 0, 120),
                children: [
                  // Trust marquee bar — Gratis Ongkir + Original + Konsultasi
                  const _TrustMarquee(),
                  const SizedBox(height: 14),
                  // Hero banner carousel (placeholder)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _HeroBannerCard(
                      onTap: () => _openProducts(),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        _HomeGreeting(onOpenProducts: () => _openProducts()),
                        const SizedBox(height: 18),
                        // 8 kategori grid (2 rows × 4 cols)
                        _CategoryGrid(
                          onOpenCategory: (category) =>
                              _openProducts(category: category),
                          onOpenVoucher: () =>
                              Navigator.pushNamed(context, '/member/vouchers'),
                          onOpenLoyalty: () =>
                              Navigator.pushNamed(context, '/member/loyalty'),
                          onOpenGrooming: () => _openProducts(category: 'Grooming'),
                          onOpenBlog: () =>
                              Navigator.pushNamed(context, '/help'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      products.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 48),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (products.isEmpty)
                    _EmptyHomeProducts(onRetry: _refresh)
                  else ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          if (promo.isNotEmpty)
                            _HomeProductSection(
                              title: 'Promo Natalo',
                              subtitle: 'Produk hemat yang sedang aktif',
                              products: promo.take(6).toList(),
                              onTap: _openProduct,
                              onSeeAll: () => _openProducts(),
                            ),
                          const SizedBox(height: 20),
                          _HomeProductSection(
                            title: 'Jelajahi Produk Natalo',
                            subtitle:
                                'Temukan berbagai kebutuhan hewan kesayanganmu',
                            products: popular.take(8).toList(),
                            onTap: _openProduct,
                            onSeeAll: () => _openProducts(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
      bottomNavigationBar: const BottomNavBar(currentIndex: 0),
    );
  }
}

class _HomeGreeting extends StatelessWidget {
  final VoidCallback onOpenProducts;

  const _HomeGreeting({required this.onOpenProducts});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: memberStore,
      builder: (context, _) {
        final profile = memberStore.profile;
        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE5EAF3)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 25,
                backgroundColor: Color(0xFFEAF3FF),
                child: Icon(Icons.pets_rounded, color: NataloColors.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile == null ? 'Halo, tamu' : 'Halo, ${profile.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: NataloColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      profile == null
                          ? 'Cari kebutuhan kucing dan anjing favoritmu.'
                          : profile.email ?? profile.phone ?? 'Member Natalo',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: NataloColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton(
                onPressed: onOpenProducts,
                child: const Text('Belanja'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HomeProductSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Product> products;
  final ValueChanged<Product> onTap;
  final VoidCallback onSeeAll;

  const _HomeProductSection({
    required this.title,
    required this.subtitle,
    required this.products,
    required this.onTap,
    required this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: NataloColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: NataloColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: onSeeAll,
              child: const Text('Lihat semua'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: products.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.56,
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
    );
  }
}

class _EmptyHomeProducts extends StatelessWidget {
  final Future<void> Function() onRetry;

  const _EmptyHomeProducts({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          const Icon(
            Icons.inventory_2_outlined,
            size: 52,
            color: NataloColors.textTertiary,
          ),
          const SizedBox(height: 12),
          const Text(
            'Produk belum tampil',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: onRetry,
            child: const Text('Coba lagi'),
          ),
        ],
      ),
    );
  }
}


/// Trust marquee — horizontal bar 3 trust signals.
class _TrustMarquee extends StatelessWidget {
  const _TrustMarquee();

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.local_shipping_outlined, 'Gratis Ongkir Area Medan',
          Color(0xFF16A34A)),
      (Icons.verified_outlined, 'Produk Original 100%', Color(0xFF1E5FBF)),
      (Icons.chat_bubble_outline_rounded, 'Konsultasi via WA',
          Color(0xFFEC4899)),
    ];
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final item = items[i];
          return Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFFE5EAF3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(item.$1, color: item.$3, size: 16),
                const SizedBox(width: 6),
                Text(
                  item.$2,
                  style: const TextStyle(
                    color: NataloColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
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

/// Hero banner — brand gradient card promo dengan premium polish:
/// - Glossy shine overlay (white 14% top-left → transparent) untuk
///   feel mengkilap seperti iOS App Store / Spotify promo card.
/// - Scale-pressed feedback 97% saat tap-down (320ms easeOutCubic).
/// - Soft inner highlight di atas via gradient — banner terasa lebih
///   "premium dimensional" bukan flat color.
class _HeroBannerCard extends StatefulWidget {
  final VoidCallback onTap;

  const _HeroBannerCard({required this.onTap});

  @override
  State<_HeroBannerCard> createState() => _HeroBannerCardState();
}

class _HeroBannerCardState extends State<_HeroBannerCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressCtrl;
  late final Animation<double> _pressScale;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
      reverseDuration: const Duration(milliseconds: 220),
    );
    _pressScale = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _pressCtrl.forward(),
      onTapCancel: () => _pressCtrl.reverse(),
      onTapUp: (_) {
        _pressCtrl.reverse();
        widget.onTap();
      },
      child: ScaleTransition(
        scale: _pressScale,
        child: Container(
          height: 160,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1E5FBF), Color(0xFF60A5FA)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: NataloColors.primary.withValues(alpha: 0.28),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // ── Glossy shine overlay (premium polish) ──
              // Diagonal sweep dari top-left (white 14%) ke center (transparent).
              // Memberikan kesan permukaan licin / glossy material.
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withValues(alpha: 0.14),
                          Colors.white.withValues(alpha: 0.04),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.35, 0.7],
                      ),
                    ),
                  ),
                ),
              ),
              // ── Soft top highlight band (rim light) ──
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 48,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: 0.18),
                          Colors.white.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.28),
                          width: 0.6,
                        ),
                      ),
                      child: const Text(
                        'PROMO BARU',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Belanja Hemat\nKebutuhan Hewan',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Diskon up to 30% untuk member',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: -10,
                bottom: -10,
                child: Icon(
                  Icons.pets_rounded,
                  size: 140,
                  color: Colors.white.withValues(alpha: 0.15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 8-icon kategori grid (2 rows x 4 cols).
class _CategoryGrid extends StatelessWidget {
  final ValueChanged<String?> onOpenCategory;
  final VoidCallback onOpenVoucher;
  final VoidCallback onOpenLoyalty;
  final VoidCallback onOpenGrooming;
  final VoidCallback onOpenBlog;

  const _CategoryGrid({
    required this.onOpenCategory,
    required this.onOpenVoucher,
    required this.onOpenLoyalty,
    required this.onOpenGrooming,
    required this.onOpenBlog,
  });

  @override
  Widget build(BuildContext context) {
    final items = <_CategoryItem>[
      _CategoryItem(
        icon: Icons.pets_rounded,
        bg: const Color(0xFFEEF4FF),
        iconColor: const Color(0xFF1E5FBF),
        label: 'Makanan Kucing',
        onTap: () => onOpenCategory('Makanan Kucing'),
      ),
      _CategoryItem(
        icon: Icons.cruelty_free_rounded,
        bg: const Color(0xFFFFF7E6),
        iconColor: const Color(0xFFD97706),
        label: 'Makanan Anjing',
        onTap: () => onOpenCategory('Makanan Anjing'),
      ),
      _CategoryItem(
        icon: Icons.inventory_2_outlined,
        bg: const Color(0xFFF3F4F6),
        iconColor: const Color(0xFF6B7280),
        label: 'Pasir',
        onTap: () => onOpenCategory('Pasir Kucing'),
      ),
      _CategoryItem(
        icon: Icons.medication_outlined,
        bg: const Color(0xFFFFE4E6),
        iconColor: const Color(0xFFE11D48),
        label: 'Vitamin',
        onTap: () => onOpenCategory('Vitamin'),
      ),
      _CategoryItem(
        icon: Icons.local_offer_outlined,
        bg: const Color(0xFFFCE7F3),
        iconColor: const Color(0xFFBE185D),
        label: 'Voucher',
        onTap: onOpenVoucher,
      ),
      _CategoryItem(
        icon: Icons.workspace_premium_outlined,
        bg: const Color(0xFFFFFBEB),
        iconColor: const Color(0xFFD97706),
        label: 'Tukar Poin',
        onTap: onOpenLoyalty,
      ),
      _CategoryItem(
        icon: Icons.spa_outlined,
        bg: const Color(0xFFECFDF5),
        iconColor: const Color(0xFF16A34A),
        label: 'Grooming',
        onTap: onOpenGrooming,
      ),
      _CategoryItem(
        icon: Icons.menu_book_outlined,
        bg: const Color(0xFFFEF3C7),
        iconColor: const Color(0xFF92400E),
        label: 'Blog & Tips',
        onTap: onOpenBlog,
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.88,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: item.onTap,
          child: Ink(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE5EAF3)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: item.bg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(item.icon, color: item.iconColor, size: 24),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    item.label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: NataloColors.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
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

class _CategoryItem {
  final IconData icon;
  final Color bg;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;
  const _CategoryItem({
    required this.icon,
    required this.bg,
    required this.iconColor,
    required this.label,
    required this.onTap,
  });
}

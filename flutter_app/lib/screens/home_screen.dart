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
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                children: [
                  _HomeGreeting(onOpenProducts: () => _openProducts()),
                  const SizedBox(height: 16),
                  _ShortcutRow(
                    onOpenCategory: (category) =>
                        _openProducts(category: category),
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
                      title: 'Pilihan Untukmu',
                      subtitle: 'Produk Natalo dari sistem',
                      products: popular.take(8).toList(),
                      onTap: _openProduct,
                      onSeeAll: () => _openProducts(),
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

class _ShortcutRow extends StatelessWidget {
  final ValueChanged<String?> onOpenCategory;

  const _ShortcutRow({required this.onOpenCategory});

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.pets_rounded, 'Kucing', 'Makanan Kucing'),
      (Icons.cruelty_free_rounded, 'Anjing', 'Makanan Anjing'),
      (Icons.inventory_2_rounded, 'Pasir', 'Pasir Kucing'),
      (Icons.medication_rounded, 'Vitamin', 'Vitamin'),
    ];

    return Row(
      children: [
        for (final item in items)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: InkWell(
                onTap: () => onOpenCategory(item.$3),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE5EAF3)),
                  ),
                  child: Column(
                    children: [
                      Icon(item.$1, color: NataloColors.primary),
                      const SizedBox(height: 6),
                      Text(
                        item.$2,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
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

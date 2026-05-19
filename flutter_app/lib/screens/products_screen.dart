import 'package:flutter/material.dart';

import '../models/product.dart';
import '../services/product_service.dart';
import '../state/search_history_store.dart';
import '../widgets/app_cart_button.dart';
import '../widgets/app_ui.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/haptic_refresh_indicator.dart';
import '../widgets/product_card.dart';
import '../widgets/skeleton_product_card.dart';

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
  late final TextEditingController _searchController;
  late Future<List<Product>> _future;
  String? _query;

  @override
  void initState() {
    super.initState();
    _query = widget.initialQuery;
    _searchController = TextEditingController(text: widget.initialQuery ?? '');
    _future = _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<Product>> _load() {
    return productService.fetchAll(
      brand: widget.selectedBrand,
      category: widget.initialCategory,
      query: _query,
      limit: 60,
    );
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() => _future = future);
    await future;
  }

  void _submitSearch(String value) {
    final trimmed = value.trim();
    setState(() {
      _query = trimmed.isEmpty ? null : trimmed;
      _future = _load();
    });
    // Save ke search history (kalau ada keyword valid). Fire-and-forget —
    // dipakai untuk wishlist look-again ranking + (future) home search suggestion.
    if (trimmed.isNotEmpty) {
      searchHistoryStore.push(trimmed);
    }
  }

  void _openProduct(Product product) {
    Navigator.pushNamed(context, '/product-detail', arguments: product);
  }

  String get _title {
    if (widget.initialCategory?.isNotEmpty == true) {
      return widget.initialCategory!;
    }
    if (widget.selectedBrand?.isNotEmpty == true) {
      return widget.selectedBrand!;
    }
    return 'Produk';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F9FF),
      appBar: AppBar(
        title: Text(_title),
        actions: const [AppCartButton()],
      ),
      body: SafeArea(
        bottom: false,
        child: HapticRefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  child: TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: _submitSearch,
                    decoration: InputDecoration(
                      hintText: 'Cari produk Natalo',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _searchController.clear();
                                _submitSearch('');
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                    ),
                  ),
                ),
              ),
              FutureBuilder<List<Product>>(
                future: _future,
                builder: (context, snapshot) {
                  final products = snapshot.data ?? const <Product>[];
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      products.isEmpty) {
                    return SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 116),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.56,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (_, __) =>
                              const SkeletonProductCard(showAddToCart: true),
                          childCount: 8,
                        ),
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return SliverFillRemaining(
                      hasScrollBody: false,
                      child: AppEmptyState(
                        icon: Icons.wifi_off_rounded,
                        title: 'Produk gagal dimuat',
                        subtitle: 'Coba refresh beberapa saat lagi.',
                        action: OutlinedButton(
                          onPressed: _refresh,
                          child: const Text('Coba lagi'),
                        ),
                      ),
                    );
                  }
                  if (products.isEmpty) {
                    return const SliverFillRemaining(
                      hasScrollBody: false,
                      child: AppEmptyState(
                        icon: Icons.search_off_rounded,
                        title: 'Produk tidak ditemukan',
                        subtitle: 'Coba kata kunci atau kategori lain.',
                      ),
                    );
                  }
                  return SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 116),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.56,
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
                  );
                },
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const BottomNavBar(currentIndex: 1),
    );
  }
}

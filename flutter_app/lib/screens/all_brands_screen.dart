import 'package:flutter/material.dart';

import '../models/brand.dart';
import '../services/product_service.dart';
import '../widgets/app_cart_button.dart';
import '../widgets/app_ui.dart';
import '../widgets/brand_card.dart';
import '../widgets/bottom_nav.dart';

/// **Semua Brand** screen — list brand dari API `/api/brands` (Capacitor
/// shared database). Sebelumnya pakai `sampleBrands` mock di
/// `lib/data/sample_brands.dart` — sekarang fetch real-time dari backend
/// supaya brand di Flutter sync dengan admin dashboard.
class AllBrandsScreen extends StatefulWidget {
  const AllBrandsScreen({super.key});

  @override
  State<AllBrandsScreen> createState() => _AllBrandsScreenState();
}

class _AllBrandsScreenState extends State<AllBrandsScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  late Future<List<PetBrand>> _brandsFuture;

  @override
  void initState() {
    super.initState();
    _brandsFuture = productService.fetchBrands();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _brandsFuture = productService.fetchBrands();
    });
    await _brandsFuture;
  }

  List<PetBrand> _filterByQuery(List<PetBrand> brands) {
    final keyword = _query.trim().toLowerCase();
    if (keyword.isEmpty) return brands;
    return brands
        .where((brand) => brand.name.toLowerCase().contains(keyword))
        .toList();
  }

  void _openBrand(PetBrand brand) {
    Navigator.pushNamed(context, '/products', arguments: brand.name);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Semua Brand'),
        actions: const [AppCartButton()],
      ),
      body: SafeArea(
        child: FutureBuilder<List<PetBrand>>(
          future: _brandsFuture,
          builder: (context, snapshot) {
            final loading = snapshot.connectionState == ConnectionState.waiting;
            final brands = snapshot.data ?? const <PetBrand>[];
            final filtered = _filterByQuery(brands);
            return RefreshIndicator(
              onRefresh: _refresh,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: _BrandHeader(
                      controller: _searchController,
                      query: _query,
                      total: filtered.length,
                      onChanged: (value) => setState(() => _query = value),
                      onClear: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    ),
                  ),
                  if (loading)
                    const SliverPadding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      sliver: _BrandGridSkeleton(),
                    )
                  else if (brands.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyBrandState(
                        title: 'Belum ada brand',
                        body: 'Admin belum menambahkan brand di katalog. '
                            'Cek lagi nanti atau pull-to-refresh.',
                      ),
                    )
                  else if (filtered.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyBrandState(
                        title: 'Brand tidak ditemukan',
                        body: 'Coba gunakan kata kunci lain.',
                      ),
                    )
                  else
                    SliverPadding(
                      padding: EdgeInsets.zero,
                      sliver: SliverAnimatedGrid(
                        key: ValueKey('brands-${filtered.length}-$_query'),
                        initialItemCount: filtered.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 12,
                          mainAxisExtent: 112,
                        ),
                        itemBuilder: (context, index, animation) {
                          final brand = filtered[index];
                          return Padding(
                            padding: EdgeInsets.fromLTRB(
                              index % 3 == 0 ? 16 : 0,
                              0,
                              index % 3 == 2 ? 16 : 0,
                              0,
                            ),
                            child: FadeTransition(
                              opacity: animation.drive(
                                CurveTween(curve: Curves.easeOutCubic),
                              ),
                              child: ScaleTransition(
                                scale: animation.drive(
                                  Tween<double>(begin: 0.94, end: 1).chain(
                                    CurveTween(curve: Curves.easeOutBack),
                                  ),
                                ),
                                child: BrandCard(
                                  brand: brand,
                                  onTap: () => _openBrand(brand),
                                ),
                              ),
                            ),
                          );
                        },
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

class _BrandHeader extends StatelessWidget {
  final TextEditingController controller;
  final String query;
  final int total;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _BrandHeader({
    required this.controller,
    required this.query,
    required this.total,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFEEF3FB)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF111111).withValues(alpha: 0.05),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Brand Favorit Natalo',
            style: TextStyle(
              color: Color(0xFF17202A),
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$total brand tersedia untuk dicari',
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          AppSearchField(
            controller: controller,
            hintText: 'Cari brand favoritmu...',
            query: query,
            onChanged: onChanged,
            onClear: onClear,
          ),
        ],
      ),
    );
  }
}

class _EmptyBrandState extends StatelessWidget {
  final String title;
  final String body;

  const _EmptyBrandState({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.search_off, size: 48, color: Color(0xFF9CA3AF)),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF111827),
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF6B7280)),
          ),
        ],
      ),
    );
  }
}

class _BrandGridSkeleton extends StatelessWidget {
  const _BrandGridSkeleton();

  @override
  Widget build(BuildContext context) {
    return SliverGrid.builder(
      itemCount: 9,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 14,
        crossAxisSpacing: 12,
        mainAxisExtent: 112,
      ),
      itemBuilder: (context, index) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF3F6FA),
            borderRadius: BorderRadius.circular(18),
          ),
        );
      },
    );
  }
}

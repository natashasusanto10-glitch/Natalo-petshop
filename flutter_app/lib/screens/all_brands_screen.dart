import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/brand.dart';
import '../models/product.dart';
import '../services/product_service.dart';
import '../utils/haptics.dart';

/// Semua Brand — grid logo brand pet care yang tersedia di Natalo.
///
/// SINKRON dengan home_screen Brand Favorit section: keduanya fetch dari
/// `productService.fetchBrands()` (`/api/brands`). Tap brand → buka
/// /products filter by brand. Brand baru yang admin tambah/hapus di
/// dashboard otomatis ke-reflect di sini — tidak ada hardcoded list lagi.
class AllBrandsScreen extends StatefulWidget {
  const AllBrandsScreen({super.key});

  @override
  State<AllBrandsScreen> createState() => _AllBrandsScreenState();
}

class _AllBrandsScreenState extends State<AllBrandsScreen> {
  List<PetBrand> _brands = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final brands = await productService.fetchBrands();
    if (!mounted) return;
    setState(() {
      _brands = brands;
      _loading = false;
      _error =
          brands.isEmpty ? 'Belum ada brand. Tarik ke bawah untuk refresh.' : null;
    });
  }

  void _openBrand(BuildContext context, PetBrand brand) {
    AppHaptics.tap();
    Navigator.pushNamed(
      context,
      '/products',
      arguments: ProductCatalogArgs(selectedBrand: brand.name),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Semua Brand'),
        backgroundColor: isDark ? cs.surface : const Color(0xFFF7FAFF),
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const _BrandGridSkeleton()
            : _brands.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 80),
                      Icon(
                        Icons.storefront_outlined,
                        size: 56,
                        color: cs.outline,
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: Text(
                          _error ?? 'Belum ada brand.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  )
                : GridView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.92,
                    ),
                    itemCount: _brands.length,
                    itemBuilder: (context, index) {
                      final brand = _brands[index];
                      return _BrandCard(
                        brand: brand,
                        onTap: () => _openBrand(context, brand),
                      );
                    },
                  ),
      ),
    );
  }
}

class _BrandGridSkeleton extends StatelessWidget {
  const _BrandGridSkeleton();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.92,
      ),
      itemCount: 9,
      itemBuilder: (context, _) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}

class _BrandCard extends StatelessWidget {
  final PetBrand brand;
  final VoidCallback onTap;

  const _BrandCard({required this.brand, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: brand.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                clipBehavior: Clip.antiAlias,
                // Logo dari API kalau ada, fallback inisial nama brand.
                child: brand.logoUrl != null
                    ? CachedNetworkImage(
                        imageUrl: brand.logoUrl!,
                        fit: BoxFit.contain,
                        errorWidget: (_, __, ___) => _BrandInitial(brand: brand),
                        placeholder: (_, __) => _BrandInitial(brand: brand),
                      )
                    : _BrandInitial(brand: brand),
              ),
              const SizedBox(height: 8),
              Text(
                brand.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              if (brand.productCount > 0) ...[
                const SizedBox(height: 2),
                Text(
                  '${brand.productCount} produk',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
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

class _BrandInitial extends StatelessWidget {
  final PetBrand brand;
  const _BrandInitial({required this.brand});

  @override
  Widget build(BuildContext context) {
    final initial = brand.name.isNotEmpty ? brand.name[0].toUpperCase() : '?';
    return Center(
      child: Text(
        initial,
        style: TextStyle(
          color: brand.color,
          fontSize: 24,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

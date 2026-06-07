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
                      // Aspect 1.0 (square card) — combo dengan BoxFit.cover
                      // di logo bikin logo isi penuh card edge-to-edge,
                      // tidak ada whitespace vertikal yg jelek.
                      childAspectRatio: 1.0,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Layout: card PUTIH (matches white-bg PNG logo dari admin upload —
    // tidak ada visible whitespace strip). Logo BoxFit.cover + ClipRRect
    // → isi penuh card area edge-to-edge, kalau perlu crop tipis di
    // edges, lebih bagus daripada whitespace kosong.
    // Brand name + productCount jadi badge OVERLAY di bawah card,
    // tidak ambil space dari logo area.
    return Material(
      color: isDark ? cs.surfaceContainerHighest : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Logo area: isi 65% tinggi card, BoxFit.contain (preserve
              // full logo, jangan crop). Whitespace di sekitar logo BLEND
              // INVISIBLE dengan card putih karena PNG logo dari admin
              // umumnya transparent atau white bg. Aspect square (1.0) +
              // padding 8 → logo punya nafas tapi tetap dominant.
              Expanded(
                flex: 65,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: brand.logoUrl != null
                      ? CachedNetworkImage(
                          imageUrl: brand.logoUrl!,
                          fit: BoxFit.contain,
                          fadeInDuration: const Duration(milliseconds: 180),
                          placeholder: (_, __) => _BrandInitial(brand: brand),
                          errorWidget: (_, __, ___) =>
                              _BrandInitial(brand: brand),
                        )
                      : _BrandInitial(brand: brand),
                ),
              ),
              // Footer badge: brand name + productCount, sectioned dengan
              // garis halus di atas biar terpisah dari logo.
              Container(
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      brand.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                    if (brand.productCount > 0)
                      Text(
                        '${brand.productCount} produk',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                  ],
                ),
              ),
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

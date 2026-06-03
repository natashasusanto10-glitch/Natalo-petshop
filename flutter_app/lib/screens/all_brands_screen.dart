import 'package:flutter/material.dart';

import '../models/product.dart';
import '../utils/haptics.dart';

/// Semua Brand — grid logo brand pet care yang tersedia di Natalo.
/// Tap brand → buka produk filter by brand name.
class AllBrandsScreen extends StatelessWidget {
  const AllBrandsScreen({super.key});

  // Brands list — hardcoded sementara, idealnya fetch dari API.
  static const _brands = <_BrandInfo>[
    _BrandInfo('Happy Dog', Color(0xFF1E5FBF), Icons.pets_rounded),
    _BrandInfo('Royal Canin', Color(0xFFEF4444), Icons.pets_rounded),
    _BrandInfo('Whiskas', Color(0xFFEC4899), Icons.pets_rounded),
    _BrandInfo('Pedigree', Color(0xFFF59E0B), Icons.pets_rounded),
    _BrandInfo('Me-O', Color(0xFF7C3AED), Icons.pets_rounded),
    _BrandInfo('Pro Plan', Color(0xFF16A34A), Icons.pets_rounded),
    _BrandInfo('Friskies', Color(0xFFD97706), Icons.pets_rounded),
    _BrandInfo('Equilibrio', Color(0xFF1E3A8A), Icons.pets_rounded),
    _BrandInfo('Natalo', Color(0xFF1E5FBF), Icons.pets_rounded),
    _BrandInfo('Cat Choize', Color(0xFFBE185D), Icons.pets_rounded),
    _BrandInfo('Maxi', Color(0xFF059669), Icons.pets_rounded),
    _BrandInfo('SmartHeart', Color(0xFF2563EB), Icons.pets_rounded),
  ];

  void _openBrand(BuildContext context, _BrandInfo brand) {
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
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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
    );
  }
}

class _BrandInfo {
  final String name;
  final Color accentColor;
  final IconData icon;
  const _BrandInfo(this.name, this.accentColor, this.icon);
}

class _BrandCard extends StatelessWidget {
  final _BrandInfo brand;
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
                  color: brand.accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  brand.icon,
                  size: 30,
                  color: brand.accentColor,
                ),
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
            ],
          ),
        ),
      ),
    );
  }
}

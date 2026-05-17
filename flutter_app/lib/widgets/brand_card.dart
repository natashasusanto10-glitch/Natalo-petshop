import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/brand.dart';
import 'app_ui.dart';
import 'glass_surface.dart';

class BrandCard extends StatelessWidget {
  final PetBrand brand;
  final VoidCallback onTap;

  const BrandCard({super.key, required this.brand, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AppPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: GlassSurface(
        radius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: SizedBox(
          height: 112,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: 52,
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: _BrandLogo(brand: brand),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                brand.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrandLogo extends StatelessWidget {
  final PetBrand brand;

  const _BrandLogo({required this.brand});

  @override
  Widget build(BuildContext context) {
    final logoUrl = brand.logoUrl;
    if (logoUrl != null && logoUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: logoUrl,
        fit: BoxFit.contain,
        placeholder: (_, __) => const SizedBox(
          height: 18,
          width: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        errorWidget: (_, __, ___) => _TextBrandLogo(brand: brand),
      );
    }

    final imageAsset = brand.imageAsset;
    if (imageAsset != null) {
      return Image.asset(
        imageAsset,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) =>
            _TextBrandLogo(brand: brand),
      );
    }

    return _TextBrandLogo(brand: brand);
  }
}

class _TextBrandLogo extends StatelessWidget {
  final PetBrand brand;

  const _TextBrandLogo({required this.brand});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 96),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: brand.color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        brand.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: brand.color,
          fontSize: 17,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

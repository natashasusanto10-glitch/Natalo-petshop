import 'package:flutter/material.dart';

import '../models/pet_shopping.dart';
import '../theme/natalo_colors.dart';
import '../theme/natalo_text.dart';
import '../utils/formatters.dart';
import 'app_product_image.dart';

/// Tinggi TETAP rail — dipakai rail terisi maupun skeleton supaya konten di
/// bawahnya tidak melonjak saat data tiba (spec: reserve space for async).
const double kPetShoppingRailHeight = 168;

const double _kCardWidth = 104;

/// Rail horizontal kolom Belanja di profil pet. Kartu TANPA tombol — satu
/// gesture per kartu → detail produk (spec Keputusan 9).
class PetShoppingRail extends StatelessWidget {
  final List<PetShoppingProduct> used;
  final List<PetShoppingProduct> suggested;
  final void Function(PetShoppingProduct product) onTapProduct;

  const PetShoppingRail({
    super.key,
    required this.used,
    required this.suggested,
    required this.onTapProduct,
  });

  @override
  Widget build(BuildContext context) {
    // Fakta lebih dulu, saran menyusul kalau masih kurang dari 4 kartu.
    final items = <_RailItem>[
      for (final u in used) _RailItem(u, isSuggestion: false),
      if (used.length < 4)
        for (final s in suggested.take(4 - used.length))
          _RailItem(s, isSuggestion: true),
    ];
    return SizedBox(
      height: kPetShoppingRailHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => _RailCard(
          item: items[i],
          onTap: () => onTapProduct(items[i].product),
        ),
      ),
    );
  }
}

class _RailItem {
  final PetShoppingProduct product;
  final bool isSuggestion;
  const _RailItem(this.product, {required this.isSuggestion});
}

class _RailCard extends StatelessWidget {
  final _RailItem item;
  final VoidCallback onTap;

  const _RailCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = item.product;
    return Semantics(
      button: true,
      label: item.isSuggestion ? '${p.name}, saran produk' : p.name,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: _kCardWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    AppProductImage(
                      imageUrl: p.imageUrl,
                      width: _kCardWidth,
                      height: _kCardWidth,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    if (item.isSuggestion)
                      Positioned(
                        top: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: NataloColors.primary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'Saran',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: NataloWeight.strong,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  p.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: NataloWeight.strong,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatRupiah(p.effectivePrice),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: NataloWeight.body,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Placeholder selagi fetch — tinggi identik dengan [PetShoppingRail].
class PetShoppingRailSkeleton extends StatelessWidget {
  const PetShoppingRailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget bar(double w) => Container(
          width: w,
          height: 9,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
          ),
        );
    return SizedBox(
      height: kPetShoppingRailHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 3,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, __) => SizedBox(
          width: _kCardWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: _kCardWidth,
                height: _kCardWidth,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 6),
              bar(_kCardWidth * 0.8),
              const SizedBox(height: 4),
              bar(_kCardWidth * 0.45),
            ],
          ),
        ),
      ),
    );
  }
}

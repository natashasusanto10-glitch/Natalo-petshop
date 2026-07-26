import 'package:flutter/material.dart';

import '../models/pet_shopping.dart';
import '../utils/formatters.dart';
import 'app_product_image.dart';

/// Lebar kartu — identik rail "Terlaris" Beranda (`_MiniProductCard`).
const double _kCardWidth = 150;

/// Maksimal kartu di rail profil (spec Keputusan 4). Saran yang tampil di
/// sini adalah 6 PERTAMA dari urutan `suggested` yang sama dengan grid
/// halaman penuh — server sudah menjamin urutan itu stabil sehari.
const int kPetShoppingRailMaxCards = 6;

/// Tinggi TETAP rail — dipakai rail terisi maupun skeleton supaya konten di
/// bawahnya tidak melonjak saat data tiba.
///
/// Rinciannya: foto 1:1 (150) + padding atas konten (8) + tinggi nama
/// dipaku (31) + jarak (8) + baris harga (≈19) + padding bawah (8) +
/// cadangan border/shadow (10) = 234. Kalau anatomi kartu berubah, angka
/// ini WAJIB dihitung ulang bersamaan — kalau tidak, skeleton→data akan
/// terlihat melonjak.
const double kPetShoppingRailHeight = 234;

/// Tinggi nama dipaku 2 baris supaya baris harga antar-kartu sejajar —
/// sama dengan kartu Beranda mode `compact`.
const double _kNameHeight = 31;

/// Rail horizontal kolom Belanja di profil pet. Kartu TANPA tombol dan TANPA
/// badge — satu gesture per kartu → detail produk.
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
    // Fakta lebih dulu, saran mengisi sisa slot.
    final items = <PetShoppingProduct>[
      ...used.take(kPetShoppingRailMaxCards),
      if (used.length < kPetShoppingRailMaxCards)
        ...suggested.take(kPetShoppingRailMaxCards - used.length),
    ];
    return SizedBox(
      height: kPetShoppingRailHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => _RailCard(
          product: items[i],
          onTap: () => onTapProduct(items[i]),
        ),
      ),
    );
  }
}

/// Kartu rail — token disamakan dengan kartu Beranda/Katalog: kartu putih
/// radius 8 + border tipis + shadow halus, foto 1:1 full-bleed `cover`.
/// TANPA badge diskon/hemat/rating: DTO Belanja tidak membawa datanya, dan
/// menampilkan klaim yang tidak didukung data adalah justru yang dihindari.
class _RailCard extends StatelessWidget {
  final PetShoppingProduct product;
  final VoidCallback onTap;

  const _RailCard({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      container: true,
      excludeSemantics: true,
      label: product.name,
      child: SizedBox(
        width: _kCardWidth,
        child: Material(
          color: cs.surface,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Container(
              // `border` di BoxDecoration.decoration bikin Container
              // auto-inset child (padding = border width) → foto 1:1
              // menyusut jadi 148x148. Border WAJIB di foregroundDecoration
              // (dicat di atas, tak mempengaruhi layout) supaya foto tetap
              // persis _kCardWidth x _kCardWidth.
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x08000000),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              foregroundDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppProductImage(
                    imageUrl: product.imageUrl,
                    width: _kCardWidth,
                    height: _kCardWidth,
                    fit: BoxFit.cover,
                    borderRadius: BorderRadius.zero,
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: _kNameHeight,
                          child: Text(
                            product.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.25,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          formatRupiah(product.effectivePrice),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            height: 1.1,
                            color: cs.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Placeholder selagi fetch — anatomi & tinggi identik dengan [PetShoppingRail].
class PetShoppingRailSkeleton extends StatelessWidget {
  const PetShoppingRailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget bar(double w, double h) => Container(
          width: w,
          height: h,
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
          child: Material(
            color: cs.surface,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: Container(
              foregroundDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: _kCardWidth,
                    height: _kCardWidth,
                    color: cs.surfaceContainerHighest,
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: _kNameHeight,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              bar(_kCardWidth - 16, 9),
                              const SizedBox(height: 5),
                              bar((_kCardWidth - 16) * 0.6, 9),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        bar((_kCardWidth - 16) * 0.5, 14),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// Badge "voucher brand-exclusive aktif" — dipakai di semua kartu produk
/// (Beranda, Katalog, Wishlist, rekomendasi Cart, hasil pencarian, Feed)
/// supaya konsisten satu sumber styling. Emas solid #F7A100, senada dengan
/// styling voucher brand di detail produk/cart/checkout.
///
/// [full] = label "Khusus {brand}" — untuk kartu lebar (>=150px).
/// [full]=false = lingkaran icon-only — untuk kartu sempit (mis. Recently
/// Viewed ~138px) supaya nama brand tidak overflow/terpotong.
class BrandExclusiveBadge extends StatelessWidget {
  final String brand;
  final bool full;

  const BrandExclusiveBadge({
    super.key,
    required this.brand,
    this.full = true,
  });

  static const _amber = Color(0xFFF7A100);

  @override
  Widget build(BuildContext context) {
    if (!full) {
      return Container(
        width: 20,
        height: 20,
        decoration: const BoxDecoration(
          color: _amber,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.workspace_premium_rounded,
          size: 12,
          color: Colors.white,
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 130),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: _amber,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.workspace_premium_rounded,
              size: 12, color: Colors.white),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              'Khusus $brand',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// True kalau produk ini layak dapat badge brand-exclusive: voucher preview
/// scoped brand DAN nama brand produk tidak kosong.
bool productHasBrandExclusiveBadge({
  required bool? isBrandExclusive,
  required String brand,
}) {
  return isBrandExclusive == true && brand.trim().isNotEmpty;
}

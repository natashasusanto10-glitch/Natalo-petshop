import 'package:flutter/material.dart';

import '../theme/natalo_colors.dart';

/// Badge "voucher brand-exclusive aktif" — dipakai di semua kartu produk
/// (Beranda, Katalog, Wishlist, rekomendasi Cart, hasil pencarian, Feed)
/// supaya konsisten satu sumber styling. Chip amber lembut (bg #FEF0DC,
/// border #FCD9A0, teks/ikon #B85C00) — senada dengan voucher brand "soft"
/// di detail produk/cart/checkout, dan sengaja tidak menutupi foto seperti
/// versi emas solid lama.
///
/// Label sekarang generik "Brand Eksklusif" — tidak mengulang nama brand
/// supaya tidak redundan saat user sudah search/filter brand tsb. [brand]
/// tetap diterima demi paritas API dengan call-site & eligibility gate.
///
/// [full]=true  = chip label "Brand Eksklusif" — untuk kartu lebar (>=150px).
/// [full]=false = lingkaran icon-only — untuk kartu sempit (mis. Recently
/// Viewed ~138px).
class BrandExclusiveBadge extends StatelessWidget {
  final String brand;
  final bool full;

  const BrandExclusiveBadge({
    super.key,
    required this.brand,
    this.full = true,
  });

  // Palet brand-exclusive "soft" — satu sumber di NataloColors, dipakai juga di
  // product_detail_screen / cart_screen / checkout_screen / member_vouchers.
  static const _softBg = NataloColors.brandExclusiveSoft;
  static const _softBorder = NataloColors.brandExclusiveBorder;
  static const _dark = NataloColors.brandExclusiveDark;

  @override
  Widget build(BuildContext context) {
    if (!full) {
      return Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: _softBg,
          shape: BoxShape.circle,
          border: Border.all(color: _softBorder),
        ),
        child: const Icon(
          Icons.workspace_premium_rounded,
          size: 12,
          color: _dark,
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 130),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: _softBg,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: _softBorder),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.workspace_premium_rounded, size: 12, color: _dark),
          SizedBox(width: 3),
          Flexible(
            child: Text(
              'Brand Eksklusif',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _dark,
                fontSize: 10,
                fontWeight: FontWeight.w700,
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

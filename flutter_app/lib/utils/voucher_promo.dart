import '../models/product.dart';
import 'formatters.dart';

// Estimasi diskon 1 voucher terhadap harga produk. Dipindah dari
// product_detail_screen.dart supaya bisa diuji tanpa widget.
double voucherDiscountEstimate(
  double productFinalPrice,
  ProductVoucherPreview voucher,
) {
  if (voucher.isShippingVoucher) return 0;
  final direct = voucher.savingAmount ?? voucher.discountAmount;
  if (direct != null && direct > 0) return direct;
  final percent = voucher.discountPercent;
  if (percent == null || percent <= 0) return 0;
  final raw = productFinalPrice * (percent / 100);
  final cap = voucher.maxDiscountAmount;
  if (cap != null && cap > 0) return raw > cap ? cap : raw;
  return raw;
}

// Estimasi bertumpuk lintas-slot: 1 voucher diskon produk terbaik + 1
// voucher loyalty terbaik (slot berbeda -> digabung). Ongkir tidak
// mengurangi harga barang.
class PromoEstimate {
  final double productVoucherDiscount;
  final double loyaltyVoucherDiscount;

  const PromoEstimate({
    required this.productVoucherDiscount,
    required this.loyaltyVoucherDiscount,
  });

  double get totalVoucherDiscount =>
      productVoucherDiscount + loyaltyVoucherDiscount;
}

PromoEstimate computePromoEstimate(
  double productFinalPrice,
  List<ProductVoucherPreview> vouchers,
) {
  double bestProduct = 0;
  double bestLoyalty = 0;
  for (final v in vouchers) {
    if (v.isShippingVoucher) continue;
    final d = voucherDiscountEstimate(productFinalPrice, v);
    if (v.isLoyaltyVoucher) {
      if (d > bestLoyalty) bestLoyalty = d;
    } else {
      if (d > bestProduct) bestProduct = d;
    }
  }
  return PromoEstimate(
    productVoucherDiscount: bestProduct,
    loyaltyVoucherDiscount: bestLoyalty,
  );
}

// Teks nominal diskon ("Hemat RpX" / "Diskon N%").
String voucherDiscountText(ProductVoucherPreview voucher) {
  if (voucher.isShippingVoucher) return 'Gratis Ongkir';
  final amount = voucher.discountAmount ?? voucher.savingAmount;
  if (amount != null && amount > 0) {
    return 'Hemat ${formatRupiahCompact(amount)}';
  }
  final percent = voucher.discountPercent;
  if (percent != null && percent > 0) {
    final cap =
        voucher.maxDiscountAmount != null && voucher.maxDiscountAmount! > 0
            ? ' s.d. ${formatRupiahCompact(voucher.maxDiscountAmount!)}'
            : '';
    return 'Diskon ${percent.toStringAsFixed(0)}%$cap';
  }
  final label = voucher.badgeLabel.trim();
  return label.isEmpty ? 'Voucher hemat' : label;
}

// Subtitle kartu voucher di sheet. Loyalty -> sebut jumlah poin.
String voucherSheetSubtitle(ProductVoucherPreview voucher) {
  if (voucher.isShippingVoucher) {
    return 'Bisa digunakan saat checkout';
  }
  final minimum = voucher.minimumOrder;
  if (voucher.isLoyaltyVoucher) {
    final points = voucher.loyaltyPoints;
    final base = points != null && points > 0
        ? 'Ditukar dari $points poin loyalty'
        : 'Hasil tukar poin loyalty';
    return minimum > 0
        ? '$base • Min. belanja ${formatRupiahCompact(minimum)}'
        : base;
  }
  final brand = voucher.brandName?.trim();
  final brandClause =
      (voucher.isBrandExclusive && brand != null && brand.isNotEmpty)
          ? 'Berlaku untuk $brand'
          : null;
  if (brandClause != null && minimum > 0) {
    return '$brandClause • Min. belanja ${formatRupiahCompact(minimum)}';
  }
  if (brandClause != null) return brandClause;
  if (minimum > 0) {
    return 'Potongan belanja saat checkout • Min. belanja ${formatRupiahCompact(minimum)}';
  }
  return 'Potongan belanja saat checkout';
}

// Teks compact untuk rail chip. Brand-exclusive tampil sebagai "Brand
// Eksklusif" (konsisten dgn badge sheet + grid); nama brand tetap muncul di
// subtitle sheet "Berlaku untuk {brand}".
String voucherChipText(ProductVoucherPreview voucher) {
  if (voucher.isShippingVoucher) return 'Gratis Ongkir';
  if (voucher.isBrandExclusive) return 'Brand Eksklusif';
  return voucherDiscountText(voucher);
}

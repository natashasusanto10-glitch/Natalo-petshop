import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/product.dart';
import 'package:natalo_petshop_flutter/utils/voucher_promo.dart';

ProductVoucherPreview vp(Map<String, dynamic> j) =>
    ProductVoucherPreview.fromJson(j);

void main() {
  test('computePromoEstimate: diskon produk terbaik + loyalty digabung', () {
    final vouchers = [
      vp({'id': 'brand', 'kind': 'PRODUCT_DISCOUNT', 'discountPercent': 10, 'maxDiscountAmount': 50000, 'minPurchase': 300000, 'brandName': 'Happy Dog'}),
      vp({'id': 'general', 'kind': 'PRODUCT_DISCOUNT', 'discountAmount': 20000, 'minPurchase': 200000}),
      vp({'id': 'loyalty', 'kind': 'LOYALTY_CLAIM', 'discountAmount': 150000, 'minPurchase': 1500000, 'loyaltyPoints': 200}),
      vp({'id': 'ongkir', 'kind': 'FREE_SHIPPING'}),
    ];
    final est = computePromoEstimate(542000, vouchers);
    expect(est.productVoucherDiscount, 50000);
    expect(est.loyaltyVoucherDiscount, 150000);
    expect(est.totalVoucherDiscount, 200000);
  });

  test('voucherSheetSubtitle: loyalty menyebut jumlah poin', () {
    final v = vp({'id': 'l', 'kind': 'LOYALTY_CLAIM', 'discountAmount': 150000, 'minPurchase': 1500000, 'loyaltyPoints': 200});
    final s = voucherSheetSubtitle(v);
    expect(s.contains('200 poin'), isTrue);
    expect(s.contains('Min. belanja'), isTrue);
  });

  test('voucherSheetSubtitle: loyalty tanpa poin -> fallback generik', () {
    final v = vp({'id': 'l', 'kind': 'LOYALTY_CLAIM', 'discountAmount': 150000, 'minPurchase': 1500000});
    expect(voucherSheetSubtitle(v).startsWith('Hasil tukar poin loyalty'), isTrue);
  });

  group('voucherCountdownLabel', () {
    final now = DateTime(2026, 7, 7, 8, 0, 0);

    test('expiry null -> null', () {
      expect(voucherCountdownLabel(null, now: now), isNull);
    });

    test('sudah lewat -> null', () {
      expect(
        voucherCountdownLabel(now.subtract(const Duration(seconds: 1)), now: now),
        isNull,
      );
    });

    test('> 24 jam -> "Sisa X hari" (dibulatkan ke bawah)', () {
      expect(
        voucherCountdownLabel(now.add(const Duration(days: 6, hours: 3)), now: now),
        'Sisa 6 hari',
      );
    });

    test('tepat 24 jam -> "Sisa 1 hari" (belum berdetak)', () {
      expect(
        voucherCountdownLabel(now.add(const Duration(hours: 24)), now: now),
        'Sisa 1 hari',
      );
    });

    test('<= 24 jam -> "Sisa HH:MM:SS"', () {
      expect(
        voucherCountdownLabel(
          now.add(const Duration(hours: 8, minutes: 12, seconds: 44)),
          now: now,
        ),
        'Sisa 08:12:44',
      );
    });
  });
}

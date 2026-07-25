import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/pet_shopping.dart';

void main() {
  test('parsing lengkap dari JSON API', () {
    final s = PetShopping.fromJson(const {
      'usedCount': 3,
      'used': [
        {
          'productId': 'p1',
          'slug': 'drontal-cat',
          'name': 'Drontal Cat',
          'imageUrl': 'https://cdn/x.jpg',
          'effectivePrice': 45000,
          'inStock': true,
          'hasVariants': false,
          'usageCount': 2,
          'lastUsedAt': '2026-04-25T00:00:00.000Z',
        },
      ],
      'manual': [
        {
          'brandText': 'Bravecto',
          'usageCount': 1,
          'lastUsedAt': '2026-06-25T00:00:00.000Z',
        },
      ],
      'suggested': [
        {
          'productId': 'p9',
          'slug': 'snack-dental',
          'name': 'Snack Dental Stick',
          'imageUrl': null,
          'effectivePrice': 28000,
          'inStock': true,
          'hasVariants': true,
        },
      ],
    });

    expect(s.usedCount, 3);
    expect(s.used.single.slug, 'drontal-cat');
    expect(s.used.single.usageCount, 2);
    expect(s.used.single.lastUsedAt, isNotNull);
    expect(s.manual.single.brandText, 'Bravecto');
    expect(s.suggested.single.hasVariants, isTrue);
    expect(s.suggested.single.imageUrl, isNull);
    expect(s.isEmpty, isFalse);
  });

  test('isEmpty hanya saat used, manual, dan suggested kosong semua', () {
    const empty = {'usedCount': 0, 'used': [], 'manual': [], 'suggested': []};
    expect(PetShopping.fromJson(empty).isEmpty, isTrue);

    final onlySuggested = PetShopping.fromJson(const {
      'usedCount': 0,
      'used': [],
      'manual': [],
      'suggested': [
        {
          'productId': 'p9',
          'slug': 's',
          'name': 'N',
          'effectivePrice': 1000,
          'inStock': true,
          'hasVariants': false,
        },
      ],
    });
    expect(onlySuggested.isEmpty, isFalse);
  });

  test('field hilang tidak bikin crash', () {
    final s = PetShopping.fromJson(const {});
    expect(s.usedCount, 0);
    expect(s.used, isEmpty);
    expect(s.isEmpty, isTrue);
  });

  test('label pemakaian: hitungan + waktu relatif', () {
    final now = DateTime(2026, 7, 25);
    expect(
      petShoppingUsageLabel(2, DateTime(2026, 4, 25), now: now),
      'Dipakai 2x, terakhir 3 bulan lalu',
    );
    expect(
      petShoppingUsageLabel(1, DateTime(2026, 7, 24), now: now),
      'Dipakai 1x, terakhir 1 hari lalu',
    );
    expect(
      petShoppingUsageLabel(1, DateTime(2026, 7, 25), now: now),
      'Dipakai 1x, terakhir hari ini',
    );
    expect(
      petShoppingUsageLabel(5, DateTime(2025, 1, 25), now: now),
      'Dipakai 5x, terakhir 1 tahun lalu',
    );
  });
}

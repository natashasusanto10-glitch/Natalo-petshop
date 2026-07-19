import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/services/product_service.dart';

void main() {
  group('extractRawList', () {
    test('map dengan key pertama berisi list', () {
      final result = extractRawList(
        {
          'items': [
            {'id': 'a'},
            {'id': 'b'},
          ],
        },
        const ['items', 'data'],
      );
      expect(result, hasLength(2));
      expect(result![0]['id'], 'a');
    });

    test('fallback ke key berikutnya kalau key pertama absen', () {
      final result = extractRawList(
        {
          'data': [
            {'id': 'x'},
          ],
        },
        const ['items', 'data'],
      );
      expect(result, hasLength(1));
    });

    test('data berupa List langsung (tanpa wrapper map)', () {
      final result = extractRawList(
        [
          {'id': 'a'},
        ],
        const ['items'],
      );
      expect(result, hasLength(1));
    });

    test('shape tak dikenal → null (bukan []) — null berarti GAGAL', () {
      expect(extractRawList({'foo': 'bar'}, const ['items']), isNull);
      expect(extractRawList('oops', const ['items']), isNull);
      expect(extractRawList(null, const ['items']), isNull);
    });

    test('list sukses tapi kosong → [] (bukan null)', () {
      expect(
        extractRawList({'items': <Object?>[]}, const ['items']),
        isEmpty,
      );
    });

    test('entry non-map disaring keluar', () {
      final result = extractRawList(
        {
          'items': [
            {'id': 'a'},
            42,
            'x',
          ],
        },
        const ['items'],
      );
      expect(result, hasLength(1));
    });
  });
}

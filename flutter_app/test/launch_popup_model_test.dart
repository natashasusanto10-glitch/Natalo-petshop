import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/launch_popup.dart';

void main() {
  test('fromApiJson parse lengkap', () {
    final p = LaunchPopup.fromApiJson({
      'id': 'p1',
      'image': 'https://cdn.example.com/popup.png',
      'imageAlt': 'Promo Juli',
      'href': '/products?diskon=1',
      'audience': 'all',
    });
    expect(p.id, 'p1');
    expect(p.imageUrl, 'https://cdn.example.com/popup.png');
    expect(p.imageAlt, 'Promo Juli');
    expect(p.href, '/products?diskon=1');
    expect(p.memberOnly, isFalse);
  });

  test('href kosong/null → null; audience default member', () {
    final p = LaunchPopup.fromApiJson({
      'id': 'p2',
      'image': 'https://cdn.example.com/x.png',
      'href': '  ',
    });
    expect(p.href, isNull);
    expect(p.memberOnly, isTrue);
  });

  test('image path relatif di-resolve jadi absolute', () {
    final p = LaunchPopup.fromApiJson({
      'id': 'p3',
      'image': '/uploads/popup.png',
    });
    expect(p.imageUrl, startsWith('http'));
    expect(p.imageUrl, endsWith('/uploads/popup.png'));
  });
}

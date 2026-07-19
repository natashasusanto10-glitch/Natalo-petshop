import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/app_notification.dart';

void main() {
  Map<String, dynamic> base() => {
        'id': 'n1',
        'title': 'Judul',
        'body': 'Isi',
        'type': 'info',
        'createdAt': '2026-07-19T00:00:00.000Z',
        'read': false,
      };

  test('parses imageUrl from camelCase key', () {
    final n = AppNotification.fromApiJson(
        {...base(), 'imageUrl': 'https://cdn/img.jpg'});
    expect(n.imageUrl, 'https://cdn/img.jpg');
  });

  test('parses imageUrl from snake_case and thumbnailUrl fallbacks', () {
    expect(
      AppNotification.fromApiJson(
              {...base(), 'image_url': 'https://cdn/a.jpg'})
          .imageUrl,
      'https://cdn/a.jpg',
    );
    expect(
      AppNotification.fromApiJson(
              {...base(), 'thumbnailUrl': 'https://cdn/b.jpg'})
          .imageUrl,
      'https://cdn/b.jpg',
    );
  });

  test('null when absent, and survives copyWith', () {
    final n = AppNotification.fromApiJson(base());
    expect(n.imageUrl, isNull);
    final withImg = AppNotification.fromApiJson(
        {...base(), 'imageUrl': 'https://cdn/img.jpg'});
    expect(withImg.copyWith(read: true).imageUrl, 'https://cdn/img.jpg');
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/share_content.dart';
import 'package:natalo_petshop_flutter/services/share_link_builder.dart';

void main() {
  const builder = ShareLinkBuilder(
    baseUrl: 'https://www.natalopetshop.com',
  );

  test('feed share uses public host, encoded post ID, and optional version',
      () {
    final payload = builder.build(
      const FeedShareContent(
        postId: 'post/a',
        authorName: 'Natalo Petshop',
        caption: 'Caption pribadi yang tidak boleh ikut dibagikan',
        shareVersion: 'abc123',
      ),
    );

    expect(
      payload.url.toString(),
      'https://www.natalopetshop.com/feed/post%2Fa?v=abc123',
    );
    expect(payload.text, endsWith(payload.url.toString()));
    expect(payload.text, isNot(contains('Caption pribadi')));
  });

  test('empty shareVersion is omitted and profile paths are normalized', () {
    final payload = builder.build(
      const ProfileShareContent(
        username: 'NataloPetshop',
        displayName: 'Natalo Petshop',
        shareVersion: ' ',
      ),
    );

    expect(payload.url.query, isEmpty);
    expect(payload.url.path, '/u/natalopetshop');
  });

  test('product payload uses canonical product URL and existing rupiah format',
      () {
    final payload = builder.build(
      const ProductShareContent(
        slug: 'makanan kucing',
        productName: 'Makanan Kucing',
        price: 12500,
        shareVersion: 'preview-1',
      ),
    );

    expect(
      payload.url.toString(),
      'https://www.natalopetshop.com/products/makanan%20kucing?v=preview-1',
    );
    expect(payload.text, contains('Rp12.500'));
  });
}

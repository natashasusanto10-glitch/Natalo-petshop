// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_action_rail.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_product_links_sheet.dart';
import 'package:natalo_petshop_flutter/screens/feed_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// Paritas foto dari `feed_video_post_view_pill_test.dart` — postingan foto
/// dengan `taggedProducts` harus pakai pill + `FeedProductLinksSheet` yang
/// sama, bukan kartu anchor lama `feedPostProductAnchorCardFor`.
///
/// NB: bikin raw JSON langsung (bukan lewat `FeedPost(...).toJson()`) —
/// `FeedPost.toJson()` cuma serialize field `products`, bukan
/// `taggedProducts`, jadi round-trip lewat toJson() akan kehilangan produk
/// yang ditag (gap pre-existing di model, di luar scope task ini).
Map<String, dynamic> _photoPostWithProductsJson() => {
      'id': 'photo-pill-regression',
      'slug': 'photo-pill-regression',
      'kind': 'PHOTO_CAROUSEL',
      'mediaItems': [
        {
          'id': 'photo-media-1',
          'mediaType': 'image',
          'mediaUrl': 'https://example.com/photo-1.jpg',
          'sortOrder': 0,
        },
        {
          'id': 'photo-media-2',
          'mediaType': 'image',
          'mediaUrl': 'https://example.com/photo-2.jpg',
          'sortOrder': 1,
        },
      ],
      'author': {'id': 'author-1', 'name': 'Tester'},
      'caption': 'Caption uji pill foto',
      'createdAt': '2026-07-16T00:00:00.000Z',
      'taggedProducts': [
        {
          'id': '1',
          'slug': 'a',
          'name': 'Produk A',
          'price': 55000,
          'discountPrice': 44500,
          'stock': 10,
        },
        {
          'id': '2',
          'slug': 'b',
          'name': 'Produk B',
          'price': 30000,
          'stock': 5
        },
      ],
    };

void main() {
  testWidgets('photo post pill opens the shared Links sheet', (tester) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({
      'feed_offline_cache_v2::guest':
          jsonEncode([_photoPostWithProductsJson()]),
    });

    await tester.pumpWidget(
      MaterialApp(
        routes: {
          '/member/login': (_) => const Scaffold(body: Text('Login')),
        },
        home: const FeedScreen(),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(FeedActionRail).evaluate().isNotEmpty) break;
    }
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('Produk A').evaluate().isNotEmpty) break;
    }
    expect(find.text('Produk A'), findsWidgets); // pill featured name
    expect(find.text('·2'), findsOneWidget); // pill count

    await tester.tap(find.text('Produk A').first);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('Produk (2)').evaluate().isNotEmpty) break;
    }

    expect(find.text('Produk (2)'), findsOneWidget); // sheet open
    expect(find.byType(FeedProductGridCard), findsNWidgets(2));
  });
}

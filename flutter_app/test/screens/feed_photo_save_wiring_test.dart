// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_action_rail.dart';
import 'package:natalo_petshop_flutter/screens/feed_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// Regresi: postingan PHOTO_CAROUSEL di feed imersif harus bisa disimpan
/// (bookmark). Dulu `_PhotoCarouselPostView` tidak meneruskan `onSave` ke
/// `FeedActionRail`, sehingga tombol bookmark = no-op diam (`onSave ?? () {}`)
/// dan foto/carousel "tidak bisa disave". Video post sudah benar; ini
/// menyamakan foto dengan video.
Map<String, dynamic> _photoPostJson() => {
      'id': 'photo-save-regression',
      'slug': 'photo-save-regression',
      'kind': 'PHOTO_CAROUSEL',
      'mediaItems': [
        {
          'id': 'photo-media-1',
          'mediaType': 'image',
          'mediaUrl': 'https://example.com/photo-1.jpg',
          'sortOrder': 0,
        },
      ],
      'author': {'id': 'author-1', 'name': 'Tester'},
      'caption': 'Caption uji save foto',
      'createdAt': '2026-07-18T00:00:00.000Z',
    };

void main() {
  testWidgets('photo post rail wires onSave (bookmark tidak no-op)',
      (tester) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({
      'feed_offline_cache_v2': jsonEncode([_photoPostJson()]),
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

    expect(find.byType(FeedActionRail), findsOneWidget);
    final rail = tester.widget<FeedActionRail>(find.byType(FeedActionRail));
    expect(
      rail.onSave,
      isNotNull,
      reason: 'Tombol simpan pada postingan foto harus terhubung ke aksi save.',
    );
  });
}

// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_action_rail.dart';
import 'package:natalo_petshop_flutter/screens/feed_screen.dart';
import 'package:natalo_petshop_flutter/widgets/feed_tagged_users_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// Task 11 — single-tap pada foto (atau badge) TOGGLE layer pill tag:
/// tap pertama tampilkan, tap kedua sembunyikan lagi.
Map<String, dynamic> _photoPostJson() => {
      'id': 'photo-tag-toggle-regression',
      'slug': 'photo-tag-toggle-regression',
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
      'caption': 'Caption uji toggle pill tag',
      'createdAt': '2026-07-18T00:00:00.000Z',
      'taggedUsers': [
        {
          'userId': 'u1',
          'username': 'budi',
          'name': 'Budi',
          'mediaIndex': 0,
          'x': 0.5,
          'y': 0.5,
        },
      ],
    };

void main() {
  testWidgets('single-tap badge toggle pill on lalu off', (tester) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({
      'feed_offline_cache_v2::guest': jsonEncode([_photoPostJson()]),
    });

    await tester.pumpWidget(
      MaterialApp(
        routes: {
          '/member/login': (_) => const Scaffold(body: Text('Login')),
          '/u': (_) => const Scaffold(body: Text('Profil')),
        },
        home: const FeedScreen(),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(FeedActionRail).evaluate().isNotEmpty) break;
    }
    expect(find.byType(FeedActionRail), findsOneWidget);
    expect(find.byType(FeedTaggedBadge), findsOneWidget);
    expect(find.text('budi'), findsNothing);

    // Beri waktu ekstra supaya scroll/ballistic settle awal feed selesai
    // (Scrollable ballistic sementara blokir hit-test — lihat gotcha
    // double-tap-like-settle) sebelum menyentuh badge.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    await tester.tap(find.byType(FeedTaggedBadge));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('budi'), findsOneWidget,
        reason: 'Tap pertama pada badge harus menampilkan pill tag.');

    await tester.tap(find.byType(FeedTaggedBadge));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('budi'), findsNothing,
        reason: 'Tap kedua pada badge harus menyembunyikan lagi pill tag.');
  });
}

// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_action_rail.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_post_shared_widgets.dart';
import 'package:natalo_petshop_flutter/screens/feed_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// REGRESI KRITIS Task 11: menambahkan `onTap` (toggle pill tag) ke
/// GestureDetector media yang sama dengan `onDoubleTap` (like) TIDAK boleh
/// merusak double-tap-like. Flutter menunda single-tap otomatis saat
/// `onDoubleTap` terdaftar di detector yang sama, jadi double-tap di sini
/// harus tetap memicu like, sedangkan single-tap (test terpisah) tetap
/// men-toggle pill.
Map<String, dynamic> _photoPostJson() => {
      'id': 'photo-tag-doubletap-regression',
      'slug': 'photo-tag-doubletap-regression',
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
      'caption': 'Caption uji double-tap like',
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
  testWidgets(
      'double-tap pada foto tetap men-trigger like walau onTap tag pill ditambah',
      (tester) async {
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

    // NB: `rail.liked` round-trips lewat apiClient/http asli — di bawah
    // flutter_test synthetic HttpOverrides request itu SELALU gagal cepat,
    // jadi optimistic liked=true langsung rollback ke false dalam pump yang
    // sama (lihat member_post_detail_double_tap_test.dart). Heart-burst
    // overlay (dipicu murni lokal di `_onDoubleTapLike`, tidak bergantung
    // network) jadi sinyal yang reliable bahwa double-tap (bukan single-tap)
    // yang dikenali.
    expect(find.byType(FeedPostBurstHeart), findsNothing);

    // Tap ganda di tengah foto (jauh dari badge pojok kiri-bawah) supaya
    // hanya mengenai media GestureDetector, bukan FeedTaggedBadge.
    const center = Offset(200, 300);
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(
      find.byType(FeedPostBurstHeart),
      findsOneWidget,
      reason: 'Double-tap pada media foto harus tetap memicu heart burst '
          '(like) meskipun GestureDetector yang sama kini juga punya onTap '
          'untuk toggle pill tag orang.',
    );

    // Pill tag TIDAK boleh nyangkut terbuka akibat single-tap yang tertunda
    // ter-absorb ke dalam double-tap (tidak pernah trigger onTap).
    expect(find.text('budi'), findsNothing);

    // toggleLike (network gagal di bawah synthetic HttpOverrides) memicu
    // AppToast dengan Timer dismiss ~2.35s sendiri — biarkan self-dismiss
    // dulu sebelum test selesai supaya binding teardown tidak menjaring
    // "Timer still pending" (lihat member_post_detail_double_tap_test.dart).
    for (var i = 0; i < 24; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  });
}

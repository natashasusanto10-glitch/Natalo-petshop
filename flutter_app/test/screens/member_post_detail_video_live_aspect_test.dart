// Task 2 — verifikasi _VideoAspectBox (via kotak media Postingan video)
// memakai fallbackAspectRatio saat sesi TIDAK memiliki controller ukuran
// asli (mis. sessionFor mengembalikan non-VideoPlayerSession seperti fake
// test biasa, atau belum ada sesi sama sekali).
//
// GOTCHA infra: `_VideoAspectBox` privat ke member_post_detail_screen.dart
// (privasi Dart per-file) → tak bisa di-import langsung dari test file lain.
// `debugPostVideoSessionFactory` di harness test repo ini (lihat
// member_post_detail_screen_coordinator_test.dart) menyuntik `_FakeSession`
// yang implement `PlaybackSession`, BUKAN `VideoPlayerSession` — jadi
// `_VideoAspectBox._bind()` (cast `is VideoPlayerSession`) selalu gagal dan
// jalur fallback yang teruji di sini persis jalur nyata saat controller
// belum siap/tak ber-platform. Jalur live-size (controller.value.size nyata)
// sudah diverifikasi murni oleh unit test
// test/features/feed/layout/postingan_media_aspect_ratio_test.dart (Task 1)
// dan akan dikonfirmasi lagi lewat device-verify — memasang
// VideoPlayerController nyata butuh plugin platform yang tak tersedia di
// widget test, jadi TIDAK dipaksakan (menghindari test rapuh).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/video/post_video_coordinator.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/screens/member_post_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';

class _FakeSession implements PlaybackSession {
  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seekTo(Duration position) async {}

  @override
  Future<void> setVolume(double v) async {}

  @override
  Future<void> setPlaybackSpeed(double speed) async {}

  @override
  Future<void> dispose() async {}

  @override
  Duration get position => Duration.zero;
}

FeedPost _fakeVideoPost({double aspectRatio = 1.7778}) {
  return FeedPost.fromJson({
    'id': 'post-1',
    'slug': 'post-1',
    'kind': 'USER_VIDEO',
    'videoUrl': 'https://example.com/post-1.mp4',
    'thumbnailUrl': 'https://example.com/post-1.jpg',
    'durationSec': 10,
    // Metadata TERSIMPAN sengaja landscape (16:9) — mensimulasikan video
    // portrait bermetadata salah dari brief. Karena sesi fake tak memberi
    // ukuran asli, kotak tetap pakai fallback ini (bukti jalur fallback).
    'aspectRatio': aspectRatio,
    'author': {'id': 'author-1', 'name': 'Tester'},
    'likeCount': 0,
    'commentCount': 0,
    'shareCount': 0,
    'createdAt': DateTime.now().toIso8601String(),
  });
}

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    debugPostVideoSessionFactory = (_) => _FakeSession();
  });

  tearDown(() {
    debugPostVideoSessionFactory = null;
  });

  testWidgets(
    'kotak media video pakai fallbackAspectRatio ketika sesi belum punya '
    'controller ukuran asli (jalur fallback _VideoAspectBox)',
    (tester) async {
      final post = _fakeVideoPost();
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: MemberPostDetailScreen(post: post, posts: [post]),
        ),
      );
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }

      // Sesi fake bukan VideoPlayerSession → _VideoAspectBox tak pernah
      // dapat live size → kotak media WAJIB tetap pakai rasio tersimpan
      // (dihitung dari aspectWidthInt/aspectHeightInt via
      // resolvePostinganMediaAspectRatio — 16/9, bukan literal aspectRatio
      // JSON — makanya toleransinya longgar).
      final aspectRatioFinder = find.byWidgetPredicate(
        (widget) =>
            widget is AspectRatio &&
            (widget.aspectRatio - (16 / 9)).abs() < 1e-6,
      );
      expect(
        aspectRatioFinder,
        findsWidgets,
        reason: 'kotak video harus tetap pakai fallbackAspectRatio '
            '(metadata tersimpan) selama controller ukuran asli belum siap',
      );

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 20));
    },
  );
}

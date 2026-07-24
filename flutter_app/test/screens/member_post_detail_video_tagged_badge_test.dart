// Bug fix: halaman Postingan (detail) untuk VIDEO tidak pernah menampilkan
// badge "orang ditandai" — _PostMediaSurface hanya memasang
// _PostinganTaggedPeopleLayer di branch carousel & photo, branch video
// dilewati. Video taggedUsers tak punya koordinat x/y (beda dari foto), jadi
// perbaikannya BUKAN pakai _PostinganTaggedPeopleLayer (pin), tapi widget
// _PostinganVideoTaggedBadge baru: badge pojok kiri-bawah + tap → sheet
// "Ditandai dalam video ini" (showFeedTaggedUsersSheet, sama dengan yang
// dipakai feed_video_post_view.dart — satu-satunya surface tag video).
//
// GOTCHA infra: sama seperti member_post_detail_video_live_aspect_test.dart,
// pakai debugPostVideoSessionFactory dengan _FakeSession (bukan
// VideoPlayerSession asli) supaya tak butuh plugin platform video_player.

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

FeedPost _fakeVideoPost({List<FeedTaggedUser> taggedUsers = const []}) {
  return FeedPost.fromJson({
    'id': 'post-1',
    'slug': 'post-1',
    'kind': 'USER_VIDEO',
    'videoUrl': 'https://example.com/post-1.mp4',
    'thumbnailUrl': 'https://example.com/post-1.jpg',
    'durationSec': 10,
    'aspectRatio': 0.5625,
    'author': {'id': 'author-1', 'name': 'Tester'},
    'likeCount': 0,
    'commentCount': 0,
    'shareCount': 0,
    'createdAt': DateTime.now().toIso8601String(),
    'taggedUsers': taggedUsers
        .map((t) => {
              'userId': t.userId,
              'username': t.username,
              'name': t.name,
            })
        .toList(),
  });
}

Future<void> _pumpSettleBounded(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
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
    'video dengan taggedUsers → badge "orang ditandai" tampil di halaman Postingan',
    (tester) async {
      final post = _fakeVideoPost(
        taggedUsers: const [
          FeedTaggedUser(userId: 'u1', username: 'andi', name: 'Andi'),
        ],
      );
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(home: MemberPostDetailScreen(post: post, posts: [post])),
      );
      await _pumpSettleBounded(tester);

      expect(find.byIcon(Icons.person), findsWidgets);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 20));
    },
  );

  testWidgets(
    'video tanpa taggedUsers → badge tidak tampil (bukan false positive)',
    (tester) async {
      final post = _fakeVideoPost(taggedUsers: const []);
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(home: MemberPostDetailScreen(post: post, posts: [post])),
      );
      await _pumpSettleBounded(tester);

      expect(find.byIcon(Icons.person), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 20));
    },
  );

  testWidgets(
    'tap badge video → sheet "Ditandai dalam video ini" terbuka (bukan pin koordinat)',
    (tester) async {
      final post = _fakeVideoPost(
        taggedUsers: const [
          FeedTaggedUser(userId: 'u1', username: 'andi', name: 'Andi'),
        ],
      );
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(home: MemberPostDetailScreen(post: post, posts: [post])),
      );
      await _pumpSettleBounded(tester);

      await tester.tap(find.byIcon(Icons.person).first);
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.text('Ditandai dalam video ini'), findsOneWidget);
      expect(find.text('Andi'), findsOneWidget);
    },
  );
}

// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_video_post_view.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/state/account_scope.dart';
import 'package:natalo_petshop_flutter/widgets/feed_tagged_users_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// In-memory [VideoPlayerPlatform] — auto-emits `initialized` so a plain
/// controller reaches a playable state in the widget test. Salinan minimal
/// dari harness `feed_video_post_view_pill_test.dart`.
class _FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  _FakeVideoPlayerPlatform();

  final Map<int, StreamController<VideoEvent>> _streams = {};
  int _nextId = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> create(DataSource dataSource) => _create();

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) => _create();

  Future<int?> _create() async {
    final id = _nextId++;
    final stream = StreamController<VideoEvent>();
    _streams[id] = stream;
    stream.add(VideoEvent(
      eventType: VideoEventType.initialized,
      size: const Size(720, 1280),
      duration: const Duration(seconds: 10),
    ));
    return id;
  }

  @override
  Future<void> dispose(int playerId) async {
    await _streams.remove(playerId)?.close();
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _streams[playerId]!.stream;

  @override
  Future<void> play(int playerId) async {}

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Widget buildView(int playerId) => const SizedBox.shrink();
}

FeedPost _fakeVideoPostWithSelfTag({
  required bool? viewerTagHidden,
  required String selfUserId,
}) {
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
    'viewerLiked': false,
    'createdAt': DateTime.now().toIso8601String(),
    if (viewerTagHidden != null) 'viewerTagHidden': viewerTagHidden,
    'taggedUsers': [
      {'userId': selfUserId, 'username': 'aku', 'name': 'Aku'},
      {'userId': 'other1', 'username': 'lain', 'name': 'Lain'},
    ],
  });
}

Widget _hostVideo(FeedPost post) {
  return MaterialApp(
    home: Scaffold(
      body: FeedVideoPostView(
        post: post,
        isActive: true,
        preloadedController: null,
        ownsController: true,
        playbackManagedExternally: false,
        onOverlayStateChanged: (_) {},
        onMediaZoomChanged: (_) {},
      ),
    ),
  );
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    VideoPlayerPlatform.instance = _FakeVideoPlayerPlatform();
  });

  // Bounded pump loop (BUKAN pumpAndSettle) — widget video punya timer
  // stall-recovery yang berulang tanpa henti di harness fake player ini
  // (posisi tak pernah maju), jadi pumpAndSettle tidak pernah "settle" dan
  // hang. Pola sama dengan feed_video_post_view_pill_test.dart.
  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() condition, {
    int maxIterations = 20,
  }) async {
    for (var i = 0; i < maxIterations; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (condition()) return;
    }
  }

  // Modal bottom sheet slide-in butuh waktu tetap untuk selesai animasi
  // (default transition ~250ms) — TANPA ini "Aku" ke-render di tree tapi
  // posisinya masih di luar viewport (sheet belum sepenuhnya naik), jadi
  // tap berikutnya miss (hit-test warning + gagal trigger onTap).
  Future<void> settleModalTransition(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> openOwnTagOptionsSheet(WidgetTester tester) async {
    await pumpUntil(
        tester, () => find.byType(FeedTaggedBadge).evaluate().isNotEmpty);
    expect(find.byType(FeedTaggedBadge), findsOneWidget);
    // A literal pixel tap (`tester.tap(find.byType(FeedTaggedBadge))`)
    // reliably misses here: `FeedTaggedBadge` is Positioned bottom-left
    // right above the action rail (bottom: navClearance + 4), while
    // `FeedPostCreatorIdentity`'s avatar sits in the SAME Stack painted
    // AFTER it (on top) at bottom: navClearance + 16. Both insets add the
    // same `navClearance`, so their RELATIVE vertical gap (12px) is
    // constant regardless of device/viewport size — with this fixture's
    // short caption (or none), the info column collapses short enough
    // that the creator avatar's own opaque GestureDetector (tap → profile)
    // geometrically overlaps and swallows the tap meant for the badge,
    // confirmed via debugDumpRenderTree(): avatar's RenderClipOval/
    // GestureDetector sits directly in the hit-test path at the badge's
    // computed center, while the badge's own Semantics node is absent
    // from it. Driving the sheet-open via the same callback the
    // GestureDetector would have invoked keeps this exercising the real
    // "seed from viewerTagHidden" code path (the thing under test) without
    // depending on caption-length-sensitive pixel geometry that isn't
    // what this test is about. Filed as a real (if minor) layout overlap
    // worth a follow-up, not something to paper over by tuning fixture
    // caption length.
    final badge = tester.widget<FeedTaggedBadge>(find.byType(FeedTaggedBadge));
    badge.onTap?.call();
    await settleModalTransition(tester);
    expect(find.text('Ditandai dalam video ini'), findsOneWidget);
    await tester.tap(find.text('Aku'));
    await settleModalTransition(tester);
    expect(find.text('Opsi Tag'), findsOneWidget);
  }

  testWidgets(
      'viewerTagHidden=true dari server → sheet Opsi Tag seed "Tampilkan" '
      'pada initial build (bukan hardcoded false)', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    debugSetAccountOwnerId(() => 'self1');
    addTearDown(debugResetAccountOwnerId);

    final post = _fakeVideoPostWithSelfTag(
      viewerTagHidden: true,
      selfUserId: 'self1',
    );
    await tester.pumpWidget(_hostVideo(post));

    await openOwnTagOptionsSheet(tester);

    // Server bilang tag SUDAH hidden — sheet Opsi Tag harus tampil label
    // "Tampilkan", BUKAN "Sembunyikan" (yang berarti seed masih hardcoded
    // false — bug: un-hide unreachable setelah app restart).
    expect(find.text('Tampilkan di profil saya'), findsOneWidget);
    expect(find.text('Sembunyikan dari profil saya'), findsNothing);
  });

  testWidgets(
      'viewerTagHidden=false dari server → sheet Opsi Tag seed "Sembunyikan" '
      'pada initial build', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    debugSetAccountOwnerId(() => 'self1');
    addTearDown(debugResetAccountOwnerId);

    final post = _fakeVideoPostWithSelfTag(
      viewerTagHidden: false,
      selfUserId: 'self1',
    );
    await tester.pumpWidget(_hostVideo(post));

    await openOwnTagOptionsSheet(tester);

    expect(find.text('Sembunyikan dari profil saya'), findsOneWidget);
    expect(find.text('Tampilkan di profil saya'), findsNothing);
  });

  testWidgets(
      'viewerTagHidden absen (legacy/anon) → seed default false '
      '(Sembunyikan), tidak crash', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    debugSetAccountOwnerId(() => 'self1');
    addTearDown(debugResetAccountOwnerId);

    final post = _fakeVideoPostWithSelfTag(
      viewerTagHidden: null,
      selfUserId: 'self1',
    );
    await tester.pumpWidget(_hostVideo(post));

    await openOwnTagOptionsSheet(tester);

    expect(find.text('Sembunyikan dari profil saya'), findsOneWidget);
  });
}

// ignore_for_file: depend_on_referenced_packages
//
// Regresi "kedip putih lalu video muncul di tengah flight" — device-confirmed
// bug PR #226. Root cause: shuttle Hero (PostHero._shuttle) sebelumnya
// menerbangkan `_InlineVideoPlayer` MENTAH; widget itu selalu lahir sebagai
// ELEMENT/STATE baru di overlay flight (Hero mem-placeholder-kan slot asal),
// dan state baru itu hanya attach/bind ke PostVideoCoordinator lewat callback
// VisibilityDetector — throttled (default ~500ms, jauh lebih lambat dari
// durasi animasi flight). Karena itu SEPANJANG flight, video baru itu selalu
// unbound (`_boundSession == null`) → merender placeholder/thumbnail dingin,
// bukan video yang barusan hidup di origin.
//
// Fix: PostHero.flightChild — surface ringan (_HeroVideoFlightSurface) yang
// MEMBACA sesi yang sudah ada dari coordinator secara SINKRON di initState
// (tanpa VisibilityDetector), dipakai HANYA di dalam shuttle.
//
// Test ini pop mid-flight (SATU frame setelah pop, sebelum animasi selesai)
// dan pastikan shuttle overlay merender VideoPlayer terikat ke controller
// YANG SAMA dengan video origin yang sudah initialized — bukan
// `_InlineVideoPlayer` baru yang unbound.

import 'dart:async';

import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/transition/post_hero.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/screens/member_post_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:visibility_detector/visibility_detector.dart';

// ─── Fakes (pola sama dgn member_post_detail_screen_fullscreen_test.dart) ──

class _FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  final Map<int, StreamController<VideoEvent>> _streams = {};
  int _nextId = 0;
  int createCount = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> create(DataSource dataSource) => _create();

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) => _create();

  Future<int?> _create() async {
    createCount++;
    final id = _nextId++;
    final stream = StreamController<VideoEvent>();
    _streams[id] = stream;
    stream.add(
      VideoEvent(
        eventType: VideoEventType.initialized,
        size: const Size(720, 1280),
        duration: const Duration(seconds: 10),
      ),
    );
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

class _NoopCacheManager implements CacheManager {
  @override
  Future<FileInfo?> getFileFromCache(String key,
          {bool ignoreMemCache = false}) async =>
      null;

  @override
  Future<FileInfo> downloadFile(String url,
          {String? key,
          Map<String, String>? authHeaders,
          bool force = false}) =>
      Completer<FileInfo>().future;

  @override
  Future<void> removeFile(String key) async {}

  @override
  Future<void> emptyCache() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopMetadataStorage implements IVideoPlayerMetadataStorage {
  final Map<String, int> _store = {};

  @override
  Set<String> get keys => _store.keys.toSet();

  @override
  Future<int?> read(String key) async => _store[key];

  @override
  Future<void> write(String key, int value) async => _store[key] = value;

  @override
  Future<void> remove(String key) async => _store.remove(key);

  @override
  Future<void> erase() async => _store.clear();
}

// ─── Fixture ────────────────────────────────────────────────────────────

FeedPost _fakeVideoPost({String id = 'p1'}) {
  return FeedPost.fromJson({
    'id': id,
    'slug': id,
    'kind': 'USER_VIDEO',
    'videoUrl': 'https://example.com/$id.mp4',
    'thumbnailUrl': 'https://example.com/$id.jpg',
    'durationSec': 10,
    'aspectRatio': 0.5625,
    'author': {'id': 'author-1', 'name': 'Tester'},
    'likeCount': 0,
    'commentCount': 0,
    'shareCount': 0,
    'createdAt': DateTime.now().toIso8601String(),
  });
}

void main() {
  late _FakeVideoPlayerPlatform fakePlatform;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    VisibilityDetectorController.instance.updateInterval = Duration.zero;

    fakePlatform = _FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = fakePlatform;

    CachedVideoPlayerPlus.cacheManager = _NoopCacheManager();
    CachedVideoPlayerPlus.metadataStorage = _NoopMetadataStorage();
  });

  testWidgets(
    'pop mid-flight: shuttle video menampilkan VideoPlayer(controller) YANG '
    'SAMA dgn origin — bukan _InlineVideoPlayer baru yang unbound',
    (tester) async {
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final post = _fakeVideoPost();
      final navigatorKey = GlobalKey<NavigatorState>();

      // Route peluncur BERISI Hero ber-tag SAMA (grid tile) — tanpa ini,
      // `Hero` di viewer tidak punya pasangan dan Flutter TIDAK menerbangkan
      // apa pun (langsung render normal, tanpa shuttle sama sekali), jadi
      // bug ini tak akan pernah tertangkap. Push lewat NavigatorState
      // langsung (bukan simulasi tap) — layar peluncur murni statis untuk
      // pasangan tag Hero, tak perlu gesture nyata.
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: Scaffold(
            body: Center(
              child: PostHero(
                scope: 'profile',
                postId: post.id,
                child: const SizedBox(
                  key: Key('grid-tile'),
                  width: 80,
                  height: 80,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => MemberPostDetailScreen(
            post: post,
            posts: [post],
            heroScope: 'profile',
          ),
        ),
      );

      // Tunggu video origin ready (VideoPlayer nyata terpasang & initialized).
      VideoPlayerController? originController;
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        final finder = find.byType(VideoPlayer);
        if (finder.evaluate().isNotEmpty) {
          final controller =
              tester.widget<VideoPlayer>(finder.first).controller;
          if (controller.value.isInitialized) {
            originController = controller;
            break;
          }
        }
      }
      expect(originController, isNotNull,
          reason: 'origin video harus initialized sebelum pop');

      // Settle push dulu sebelum pop. Hero close-only gating (§ dokumentasi
      // `_HeroFlightGate` di member_post_detail_screen.dart) baru mengekspos
      // PostHero sisi viewer SETELAH transisi push selesai (+ satu frame
      // jeda) — video di atas biasanya sudah initialized JAUH sebelum push
      // selesai, jadi tanpa settle ini pop bisa terjadi sebelum viewer
      // punya Hero sama sekali → tidak ada pasangan → tidak ada flight.
      // Fetch ulang controller SETELAH settle: begitu Hero terpasang,
      // subtree `_InlineVideoPlayer` di posisi itu di-reparent (tree-shape
      // berubah dari child polos → Hero>ClipRRect>_HeroContent>child), jadi
      // elemen lama dibuang & session/controller yang benar adalah yang
      // terikat SETELAH reparent itu — origin lama sebelum settle tidak
      // valid lagi untuk dibandingkan dengan controller shuttle.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final settledFinder = find.byType(VideoPlayer);
      expect(settledFinder.evaluate().isNotEmpty, isTrue,
          reason: 'origin video harus tetap ada setelah push settle');
      originController =
          tester.widget<VideoPlayer>(settledFinder.first).controller;
      expect(originController.value.isInitialized, isTrue,
          reason: 'origin video harus tetap initialized setelah push settle');

      // Pop, lalu pump SATU frame pendek — mid-flight, JAUH sebelum animasi
      // Hero (~300ms) selesai.
      navigatorKey.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      // Shuttle harus merender VideoPlayer terikat controller ORIGIN yang
      // SAMA — bukan cold-start baru (beda instance / belum initialized).
      final flightVideoPlayers = find.byType(VideoPlayer);
      expect(
        flightVideoPlayers.evaluate().isNotEmpty,
        isTrue,
        reason:
            'shuttle harus menggambar VideoPlayer sejak frame pertama flight, '
            'bukan placeholder/kosong dulu baru video "muncul di tengah"',
      );
      final flightController =
          tester.widget<VideoPlayer>(flightVideoPlayers.first).controller;
      expect(
        identical(flightController, originController),
        isTrue,
        reason: 'shuttle harus memakai SATU controller/texture yang sama '
            'dengan origin (tanpa re-init/placeholder kosong)',
      );

      // Selama flight, KEDUA endpoint Hero (origin di layar peluncur & viewer
      // yang dipop) menampilkan placeholder kosong bawaan Flutter — satu-
      // satunya tempat _InlineVideoPlayer boleh hidup adalah di luar flight.
      // Fresh _InlineVideoPlayer TIDAK boleh ikut terbang di dalam shuttle
      // (itulah sumber flash: state baru yg belum sempat bind sesi via
      // VisibilityDetector throttled). Cek GLOBAL (bukan diskop ke satu
      // PostHero) supaya benar-benar menangkap widget yang shuttle pasang.
      expect(
        find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_InlineVideoPlayer',
        ),
        findsNothing,
        reason: 'mid-flight seharusnya TIDAK ada _InlineVideoPlayer baru '
            '(unbound) di tree sama sekali — origin dipagar Hero placeholder, '
            'shuttle pakai flightChild',
      );

      // Selesaikan animasi supaya timer tidak nyangkut di teardown.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    },
  );
}

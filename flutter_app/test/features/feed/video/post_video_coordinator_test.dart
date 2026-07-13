import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/video/post_video_coordinator.dart';

class FakePlaybackSession implements PlaybackSession {
  FakePlaybackSession(this.postId);

  final String postId;
  int playCount = 0;
  int pauseCount = 0;
  int disposeCount = 0;
  double volume = 1;
  bool playing = false;
  Duration _position = Duration.zero;

  @override
  Future<void> play() async {
    playCount++;
    playing = true;
  }

  @override
  Future<void> pause() async {
    pauseCount++;
    playing = false;
  }

  @override
  Future<void> seekTo(Duration position) async {
    _position = position;
  }

  @override
  Future<void> setVolume(double v) async {
    volume = v;
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
  }

  @override
  Duration get position => _position;
}

class FakeMutedSource extends ChangeNotifier {
  bool muted = true;

  void set(bool value) {
    muted = value;
    notifyListeners();
  }
}

void main() {
  late FakeMutedSource mutedSource;
  late Map<String, FakePlaybackSession> sessions;
  late PostVideoCoordinator coordinator;

  setUp(() {
    mutedSource = FakeMutedSource();
    sessions = {};
    coordinator = PostVideoCoordinator(
      sessionFactory: (postId) {
        final session = FakePlaybackSession(postId);
        sessions[postId] = session;
        return session;
      },
      mutedListenable: mutedSource,
      readMuted: () => mutedSource.muted,
    );
  });

  group('slot & eviction LRU', () {
    test('maks 3 sesi: yang bukan asal/aktif/preload dieviction LRU', () {
      // Inline Postingan: A asal + aktif.
      coordinator.setOrigin('A');
      coordinator.setActive('A');
      // Fullscreen: swipe ke B, preload C.
      coordinator.setActive('B');
      coordinator.preloadNext('C');
      expect(coordinator.livePostIds, {'A', 'B', 'C'});

      // Swipe lagi: C aktif, preload D. B bukan asal/aktif/preload,
      // tidak attached → keluar window → dispose.
      coordinator.setActive('C');
      coordinator.preloadNext('D');

      expect(coordinator.livePostIds, {'A', 'C', 'D'});
      expect(sessions['B']!.disposeCount, 1);
      // A (asal) tetap hidup meski attachment 0 — pinned.
      expect(sessions['A']!.disposeCount, 0);
    });

    test('sesi attached tidak dieviction walau keluar window LRU', () {
      coordinator.attach('view-b', 'B');
      coordinator.setOrigin('A');
      coordinator.setActive('C');
      coordinator.preloadNext('D');
      // 4 sesi, B di luar peran tapi masih attached → tetap hidup.
      expect(coordinator.livePostIds, contains('B'));
      expect(sessions['B']!.disposeCount, 0);

      // Detach → sekarang boleh dieviction.
      coordinator.detach('view-b', 'B');
      expect(coordinator.livePostIds, isNot(contains('B')));
      expect(sessions['B']!.disposeCount, 1);
    });
  });

  group('pinned vs attached', () {
    test('pinned melindungi saat attachment sesaat 0 di transisi', () {
      coordinator.setOrigin('A');
      coordinator.attach('inline', 'A');
      coordinator.setActive('A');

      // Transisi ke fullscreen: inline detach dulu, fullscreen belum attach.
      coordinator.detach('inline', 'A');
      expect(sessions['A']!.disposeCount, 0);
      expect(coordinator.livePostIds, contains('A'));

      // Fullscreen attach ke sesi YANG SAMA.
      final borrowed = coordinator.attach('fullscreen', 'A');
      expect(borrowed, same(sessions['A']));
    });

    test('attachment 0 + tidak pinned tapi masih di window → tidak dispose',
        () {
      coordinator.attach('v1', 'A');
      coordinator.detach('v1', 'A');
      // Cuma 1 sesi (≤3) → tetap hidup walau tak pinned & tak attached.
      expect(sessions['A']!.disposeCount, 0);
    });
  });

  group('mute rules', () {
    test('sesi baru selalu paused + volume 0; aktif dapat feedMuted', () {
      coordinator.preloadNext('B');
      expect(sessions['B']!.volume, 0);
      expect(sessions['B']!.playing, isFalse);

      mutedSource.muted = false;
      coordinator.setActive('A');
      expect(sessions['A']!.volume, 1);
      expect(sessions['A']!.playing, isTrue);
    });

    test('unmute global TIDAK menyentuh background/preload', () {
      coordinator.setOrigin('A');
      coordinator.setActive('A');
      coordinator.setActive('B'); // A jadi background
      coordinator.preloadNext('C');
      expect(sessions['A']!.volume, 0);
      expect(sessions['C']!.volume, 0);

      mutedSource.set(false); // unmute global

      expect(sessions['B']!.volume, 1); // hanya aktif
      expect(sessions['A']!.volume, 0);
      expect(sessions['A']!.playing, isFalse);
      expect(sessions['C']!.volume, 0);
      expect(sessions['C']!.playing, isFalse);
    });

    test('mute global menurunkan volume aktif ke 0', () {
      mutedSource.muted = false;
      coordinator.setActive('A');
      expect(sessions['A']!.volume, 1);

      mutedSource.set(true);
      expect(sessions['A']!.volume, 0);
    });

    test('preload → aktif diberi nilai feedMuted SAAT ITU', () {
      coordinator.preloadNext('B'); // lahir muted
      expect(sessions['B']!.volume, 0);

      mutedSource.set(false); // user unmute sebelum swipe
      expect(sessions['B']!.volume, 0); // preload tak tersentuh

      coordinator.setActive('B'); // baru sekarang dapat nilai terkini
      expect(sessions['B']!.volume, 1);
      expect(sessions['B']!.playing, isTrue);
      expect(coordinator.preloadPostId, isNull);
    });
  });

  group('intent playback', () {
    test('setActive: aktif lama paused + volume 0', () {
      mutedSource.muted = false;
      coordinator.setActive('A');
      coordinator.setActive('B');
      expect(sessions['A']!.playing, isFalse);
      expect(sessions['A']!.volume, 0);
      expect(sessions['B']!.playing, isTrue);
    });

    test('userTogglePlay pause lalu play lagi; reportVisible hormati pause',
        () {
      coordinator.setActive('A');
      expect(sessions['A']!.playing, isTrue);

      coordinator.userTogglePlay();
      expect(sessions['A']!.playing, isFalse);

      // Visible saat user-paused → TIDAK auto-resume.
      coordinator.reportVisible('A');
      expect(sessions['A']!.playing, isFalse);

      coordinator.userTogglePlay();
      expect(sessions['A']!.playing, isTrue);
    });

    test('reportHidden pause; reportVisible resume hanya video aktif', () {
      coordinator.setActive('A');
      coordinator.reportHidden('A');
      expect(sessions['A']!.playing, isFalse);

      coordinator.reportVisible('A');
      expect(sessions['A']!.playing, isTrue);

      // Non-aktif tidak pernah di-play oleh reportVisible.
      coordinator.preloadNext('B');
      coordinator.reportVisible('B');
      expect(sessions['B']!.playing, isFalse);
    });
  });

  group('pauseAll & dispose', () {
    test('pauseAll pause semua sesi; visible tak resume sampai intent baru',
        () {
      coordinator.setOrigin('A');
      coordinator.setActive('A');
      coordinator.setActive('B');
      coordinator.preloadNext('C');

      coordinator.pauseAll();
      expect(sessions['A']!.playing, isFalse);
      expect(sessions['B']!.playing, isFalse);
      expect(sessions['C']!.playing, isFalse);

      coordinator.reportVisible('B');
      expect(sessions['B']!.playing, isFalse); // masih suspended

      coordinator.setActive('B'); // intent baru
      expect(sessions['B']!.playing, isTrue);
    });

    test('dispose: semua sesi di-dispose TEPAT sekali, idempotent', () {
      coordinator.setOrigin('A');
      coordinator.setActive('A');
      coordinator.setActive('B');
      coordinator.preloadNext('C');

      coordinator.dispose();
      coordinator.dispose(); // idempotent

      for (final s in sessions.values) {
        expect(s.disposeCount, 1, reason: 'sesi ${s.postId}');
      }
      expect(coordinator.isDisposed, isTrue);
      expect(coordinator.livePostIds, isEmpty);
    });

    test('eviction + dispose coordinator tidak double-dispose sesi', () {
      coordinator.setOrigin('A');
      coordinator.setActive('A');
      coordinator.setActive('B');
      coordinator.preloadNext('C');
      coordinator.setActive('C');
      coordinator.preloadNext('D'); // B dieviction di sini

      coordinator.dispose();

      expect(sessions['B']!.disposeCount, 1);
      expect(sessions['A']!.disposeCount, 1);
      expect(sessions['C']!.disposeCount, 1);
      expect(sessions['D']!.disposeCount, 1);
    });

    test('setelah dispose, listener mute tidak lagi menyentuh sesi', () {
      coordinator.setActive('A');
      coordinator.dispose();
      final volumeBefore = sessions['A']!.volume;
      mutedSource.set(false);
      expect(sessions['A']!.volume, volumeBefore);
    });
  });
}

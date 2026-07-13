import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/video/post_video_coordinator.dart';
import 'package:natalo_petshop_flutter/features/feed/video/video_audio_arbiter.dart';

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

class DeferredPlaySession extends FakePlaybackSession {
  DeferredPlaySession(super.postId);

  Completer<void>? playGate;

  @override
  Future<void> play() async {
    final gate = playGate;
    if (gate != null) await gate.future;
    await super.play();
  }
}

class DelayedPlaybackSession extends FakePlaybackSession {
  DelayedPlaybackSession(super.postId, this.events);

  final List<String> events;
  Completer<void>? volumeGate;
  Completer<void>? pauseGate;

  @override
  Future<void> setVolume(double value) async {
    events.add('$postId:volume:$value:start');
    final gate = volumeGate;
    if (gate != null) await gate.future;
    await super.setVolume(value);
    events.add('$postId:volume:$value:end');
  }

  @override
  Future<void> pause() async {
    events.add('$postId:pause:start');
    final gate = pauseGate;
    if (gate != null) await gate.future;
    await super.pause();
    events.add('$postId:pause:end');
  }

  @override
  Future<void> play() async {
    events.add('$postId:play');
    await super.play();
  }
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

  Future<void> settlePlayback() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

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
      audioArbiter: VideoAudioArbiter(),
    );
  });

  test('app-wide arbiter transfers audio and stale A cannot silence B',
      () async {
    final arbiter = VideoAudioArbiter();
    final sourceA = FakeMutedSource()..muted = false;
    final sourceB = FakeMutedSource()..muted = false;
    final sessionA = DeferredPlaySession('A');
    final sessionB = FakePlaybackSession('B');
    final coordinatorA = PostVideoCoordinator(
      sessionFactory: (_) => sessionA,
      mutedListenable: sourceA,
      readMuted: () => sourceA.muted,
      audioArbiter: arbiter,
    );
    final coordinatorB = PostVideoCoordinator(
      sessionFactory: (_) => sessionB,
      mutedListenable: sourceB,
      readMuted: () => sourceB.muted,
      audioArbiter: arbiter,
    );

    coordinatorA.setActive('A');
    await Future<void>.delayed(Duration.zero);
    expect(sessionA.playing, isTrue);
    expect(sessionA.volume, 1);

    sessionA.playGate = Completer<void>();
    coordinatorA.reportVisible('A');
    await Future<void>.delayed(Duration.zero);
    coordinatorB.setActive('B');
    await Future<void>.delayed(Duration.zero);
    expect(sessionA.playing, isFalse);
    expect(sessionA.volume, 0);
    expect(sessionB.playing, isTrue);
    expect(sessionB.volume, 1);

    sessionA.playGate!.complete();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    coordinatorA.reportHidden('A');
    await Future<void>.delayed(Duration.zero);
    expect(sessionB.playing, isTrue);
    expect(sessionB.volume, 1);

    coordinatorB.pauseAll();
    await Future<void>.delayed(Duration.zero);
    expect(sessionA.playing, isFalse,
        reason: 'A only returns after a fresh explicit eligible resume');
    coordinatorA.resumeAll();
    await Future<void>.delayed(Duration.zero);
    expect(sessionA.playing, isTrue);
    expect(sessionA.volume, 1);

    coordinatorA.dispose();
    coordinatorB.dispose();
  });

  test('A to B waits for old active mute and pause before B audio starts',
      () async {
    final events = <String>[];
    final a = DelayedPlaybackSession('A', events);
    final b = DelayedPlaybackSession('B', events);
    final source = FakeMutedSource()..muted = false;
    final coordinator = PostVideoCoordinator(
      sessionFactory: (id) => id == 'A' ? a : b,
      mutedListenable: source,
      readMuted: () => source.muted,
      audioArbiter: VideoAudioArbiter(),
    );

    coordinator.setActive('A');
    await Future<void>.delayed(Duration.zero);
    expect(a.playing, isTrue);

    a.volumeGate = Completer<void>();
    a.pauseGate = Completer<void>();
    coordinator.setActive('B');
    await Future<void>.delayed(Duration.zero);
    expect(b.playCount, 0);
    expect(events, isNot(contains('B:volume:1.0:start')));

    a.volumeGate!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(b.playCount, 0, reason: 'B still waits for A pause');
    a.pauseGate!.complete();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(a.volume, 0);
    expect(a.playing, isFalse);
    expect(b.volume, 1);
    expect(b.playing, isTrue);
    expect(events.indexOf('A:pause:end'),
        lessThan(events.indexOf('B:volume:1.0:start')));
    coordinator.dispose();
  });

  test('superseded claim delayed in setVolume never invokes stale play',
      () async {
    final arbiter = VideoAudioArbiter();
    final source = FakeMutedSource()..muted = false;
    final events = <String>[];
    final a = DelayedPlaybackSession('A', events)
      ..volumeGate = Completer<void>();
    final b = FakePlaybackSession('B');
    final coordinatorA = PostVideoCoordinator(
      sessionFactory: (_) => a,
      mutedListenable: source,
      readMuted: () => source.muted,
      audioArbiter: arbiter,
    );
    final coordinatorB = PostVideoCoordinator(
      sessionFactory: (_) => b,
      mutedListenable: source,
      readMuted: () => source.muted,
      audioArbiter: arbiter,
    );

    coordinatorA.setActive('A');
    await Future<void>.delayed(Duration.zero);
    coordinatorB.setActive('B');
    await Future<void>.delayed(Duration.zero);
    expect(b.playing, isTrue);

    a.volumeGate!.complete();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(a.playCount, 0,
        reason: 'stale token must be checked before play is invoked');
    expect(a.volume, 0);
    expect(b.playing, isTrue);

    coordinatorA.dispose();
    coordinatorB.dispose();
  });

  group('session adoption', () {
    test('adopt bypasses factory and coordinator disposes adopted session',
        () async {
      final adopted = FakePlaybackSession('A');
      expect(coordinator.adoptSession('A', adopted), isTrue);

      expect(coordinator.attach('view-a', 'A'), same(adopted));
      expect(sessions, isEmpty);
      coordinator.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(adopted.disposeCount, 1);
    });

    test('duplicate adoption is rejected and duplicate is cleaned once',
        () async {
      final first = FakePlaybackSession('A');
      final duplicate = FakePlaybackSession('A-duplicate');
      expect(coordinator.adoptSession('A', first), isTrue);
      expect(coordinator.adoptSession('A', duplicate), isFalse);
      await Future<void>.delayed(Duration.zero);

      expect(coordinator.sessionFor('A'), same(first));
      expect(duplicate.disposeCount, 1);
      coordinator.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(first.disposeCount, 1);
    });
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

      // Detach preserves the short transition grace while below the new cap.
      coordinator.detach('view-b', 'B');
      expect(coordinator.livePostIds, contains('B'));
      expect(sessions['B']!.disposeCount, 0);
    });
  });

  group('adaptive preload window', () {
    test('deduplicates and hard caps preload IDs at three', () {
      coordinator.setOrigin('origin');
      coordinator.setActive('active');
      coordinator.setPreloadWindow(['a', 'a', 'b', 'c', 'd', 'active']);

      expect(coordinator.preloadPostIds, {'a', 'b', 'c'});
      expect(coordinator.livePostIds.length, 5);
      expect(sessions['d'], isNull);
      for (final id in ['a', 'b', 'c']) {
        expect(sessions[id]!.playing, isFalse);
        expect(sessions[id]!.volume, 0);
      }
    });

    test('window replacement evicts stale preload and clear keeps roles',
        () async {
      coordinator.setOrigin('origin');
      coordinator.setActive('active');
      coordinator.setPreloadWindow(['a', 'b', 'c']);
      coordinator.setPreloadWindow(['c', 'd']);
      await Future<void>.delayed(Duration.zero);

      expect(coordinator.preloadPostIds, {'c', 'd'});
      expect(coordinator.livePostIds, {'origin', 'active', 'c', 'd'});
      expect(sessions['a']!.disposeCount, 1);
      expect(sessions['b']!.disposeCount, 1);

      coordinator.setPreloadWindow(const []);
      await Future<void>.delayed(Duration.zero);
      expect(coordinator.livePostIds, {'origin', 'active'});
      expect(sessions['c']!.disposeCount, 1);
      expect(sessions['d']!.disposeCount, 1);
    });

    test('attached session survives clear then disposes after detach',
        () async {
      coordinator.attach('view-a', 'a');
      coordinator.setPreloadWindow(['a']);
      coordinator.setPreloadWindow(const []);
      expect(coordinator.livePostIds, contains('a'));

      coordinator.detach('view-a', 'a');
      coordinator.setPreloadWindow(const []);
      await Future<void>.delayed(Duration.zero);
      expect(coordinator.livePostIds, isNot(contains('a')));
      expect(sessions['a']!.disposeCount, 1);
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
    test('sesi baru selalu paused + volume 0; aktif dapat feedMuted', () async {
      coordinator.preloadNext('B');
      expect(sessions['B']!.volume, 0);
      expect(sessions['B']!.playing, isFalse);

      mutedSource.muted = false;
      coordinator.setActive('A');
      await settlePlayback();
      expect(sessions['A']!.volume, 1);
      expect(sessions['A']!.playing, isTrue);
    });

    test('unmute global TIDAK menyentuh background/preload', () async {
      coordinator.setOrigin('A');
      coordinator.setActive('A');
      coordinator.setActive('B'); // A jadi background
      coordinator.preloadNext('C');
      await settlePlayback();
      expect(sessions['A']!.volume, 0);
      expect(sessions['C']!.volume, 0);

      mutedSource.set(false); // unmute global

      expect(sessions['B']!.volume, 1); // hanya aktif
      expect(sessions['A']!.volume, 0);
      expect(sessions['A']!.playing, isFalse);
      expect(sessions['C']!.volume, 0);
      expect(sessions['C']!.playing, isFalse);
    });

    test('mute global menurunkan volume aktif ke 0', () async {
      mutedSource.muted = false;
      coordinator.setActive('A');
      await settlePlayback();
      expect(sessions['A']!.volume, 1);

      mutedSource.set(true);
      expect(sessions['A']!.volume, 0);
    });

    test('preload → aktif diberi nilai feedMuted SAAT ITU', () async {
      coordinator.preloadNext('B'); // lahir muted
      expect(sessions['B']!.volume, 0);

      mutedSource.set(false); // user unmute sebelum swipe
      expect(sessions['B']!.volume, 0); // preload tak tersentuh

      coordinator.setActive('B'); // baru sekarang dapat nilai terkini
      await settlePlayback();
      expect(sessions['B']!.volume, 1);
      expect(sessions['B']!.playing, isTrue);
      expect(coordinator.preloadPostId, isNull);
    });
  });

  group('intent playback', () {
    test('setActive: aktif lama paused + volume 0', () async {
      mutedSource.muted = false;
      coordinator.setActive('A');
      coordinator.setActive('B');
      await settlePlayback();
      expect(sessions['A']!.playing, isFalse);
      expect(sessions['A']!.volume, 0);
      expect(sessions['B']!.playing, isTrue);
    });

    test('userTogglePlay pause lalu play lagi; reportVisible hormati pause',
        () async {
      coordinator.setActive('A');
      await settlePlayback();
      expect(sessions['A']!.playing, isTrue);

      coordinator.userTogglePlay();
      await settlePlayback();
      expect(sessions['A']!.playing, isFalse);

      // Visible saat user-paused → TIDAK auto-resume.
      coordinator.reportVisible('A');
      expect(sessions['A']!.playing, isFalse);

      coordinator.userTogglePlay();
      await settlePlayback();
      expect(sessions['A']!.playing, isTrue);
    });

    test('reportHidden pause; reportVisible resume hanya video aktif',
        () async {
      coordinator.setActive('A');
      await settlePlayback();
      coordinator.reportHidden('A');
      await settlePlayback();
      expect(sessions['A']!.playing, isFalse);

      coordinator.reportVisible('A');
      await settlePlayback();
      expect(sessions['A']!.playing, isTrue);

      // Non-aktif tidak pernah di-play oleh reportVisible.
      coordinator.preloadNext('B');
      coordinator.reportVisible('B');
      expect(sessions['B']!.playing, isFalse);
    });
  });

  group('pauseAll & dispose', () {
    test('pauseAll pause semua sesi; visible tak resume sampai intent baru',
        () async {
      coordinator.setOrigin('A');
      coordinator.setActive('A');
      coordinator.setActive('B');
      coordinator.preloadNext('C');

      coordinator.pauseAll();
      await settlePlayback();
      expect(sessions['A']!.playing, isFalse);
      expect(sessions['B']!.playing, isFalse);
      expect(sessions['C']!.playing, isFalse);

      coordinator.reportVisible('B');
      expect(sessions['B']!.playing, isFalse); // masih suspended

      coordinator.setActive('B'); // intent baru
      await settlePlayback();
      expect(sessions['B']!.playing, isTrue);
    });

    test('resumeAll: sesi aktif main lagi dgn mute terkini; background tidak',
        () async {
      coordinator.setOrigin('A');
      coordinator.setActive('A');
      coordinator.setActive('B'); // A jadi background
      coordinator.preloadNext('C');

      coordinator.pauseAll();
      await settlePlayback();
      expect(sessions['A']!.playing, isFalse);
      expect(sessions['B']!.playing, isFalse);
      expect(sessions['C']!.playing, isFalse);

      mutedSource.set(false); // user unmute selagi suspended
      coordinator.resumeAll();
      await settlePlayback();

      // Sesi aktif (B) main lagi dgn volume mute terkini.
      expect(sessions['B']!.playing, isTrue);
      expect(sessions['B']!.volume, 1);
      // Background & preload TIDAK ikut main.
      expect(sessions['A']!.playing, isFalse);
      expect(sessions['A']!.volume, 0);
      expect(sessions['C']!.playing, isFalse);
      expect(sessions['C']!.volume, 0);
    });

    test('resumeAll hormati user-pause eksplisit', () {
      coordinator.setActive('A');
      coordinator.userTogglePlay(); // user pause eksplisit
      coordinator.pauseAll();

      coordinator.resumeAll();
      expect(sessions['A']!.playing, isFalse);
    });

    test('intent setelah dispose tidak menambah sesi / panggil factory', () {
      coordinator.setActive('A');
      coordinator.dispose();
      final sessionCountBefore = sessions.length;

      // Semua void intent: silent no-op, tidak bikin sesi baru.
      coordinator.setActive('Z');
      coordinator.preloadNext('Y');
      coordinator.setOrigin('X');
      coordinator.userTogglePlay();
      coordinator.resumeAll();
      coordinator.pauseAll();

      expect(coordinator.livePostIds, isEmpty);
      expect(sessions.length, sessionCountBefore);
      expect(sessions.containsKey('Z'), isFalse);
      expect(sessions.containsKey('Y'), isFalse);
      expect(sessions.containsKey('X'), isFalse);

      // attach setelah dispose → throw (view initState keliru).
      expect(() => coordinator.attach('v', 'W'), throwsStateError);
      expect(sessions.containsKey('W'), isFalse);
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

  group('registry notifier (KUNCI 1)', () {
    test('fire saat sesi DIBUAT (attach/setActive/preloadNext/setOrigin)', () {
      var fires = 0;
      coordinator.registryListenable.addListener(() => fires++);

      coordinator.setOrigin('A'); // buat sesi A
      expect(fires, 1);
      coordinator.setActive('A'); // A sudah ada → tak ada sesi baru/hapus
      expect(fires, 1);
      coordinator.setActive('B'); // buat sesi B
      expect(fires, 2);
      coordinator.preloadNext('C'); // buat sesi C
      expect(fires, 3);
      coordinator.attach('v', 'C'); // C sudah ada → tak ada perubahan registry
      expect(fires, 3);
    });

    test('fire saat sesi DIHAPUS (eviction LRU)', () {
      coordinator.setOrigin('A');
      coordinator.setActive('A');
      coordinator.setActive('B');
      coordinator.preloadNext('C');

      var fires = 0;
      coordinator.registryListenable.addListener(() => fires++);

      // Swipe: C aktif (sudah ada), preload D (buat) → B keluar window & dispose.
      coordinator.setActive('C'); // tak ada create/remove
      expect(fires, 0);
      coordinator.preloadNext('D'); // buat D + evict B → himpunan berubah
      expect(fires, 1);
      expect(coordinator.livePostIds, {'A', 'C', 'D'});
    });

    test('TIDAK fire saat play/pause/volume/mute (bukan perubahan registry)',
        () {
      coordinator.setActive('A');
      coordinator.preloadNext('B');

      var fires = 0;
      coordinator.registryListenable.addListener(() => fires++);

      coordinator.reportHidden('A');
      coordinator.reportVisible('A');
      coordinator.userTogglePlay();
      coordinator.userTogglePlay();
      coordinator.pauseAll();
      coordinator.resumeAll();
      mutedSource.set(false); // mute toggle
      mutedSource.set(true);

      expect(fires, 0);
    });

    test('view-simulasi adopt sesi preload setelah preloadNext via notifier',
        () {
      // View untuk post 'B' sudah mounted TAPI B belum punya sesi.
      PlaybackSession? adopted;
      const myPostId = 'B';
      void recheck() => adopted ??= coordinator.sessionFor(myPostId);

      coordinator.registryListenable.addListener(recheck);
      recheck(); // cek awal di "build": belum ada
      expect(adopted, isNull);

      coordinator.setActive('A');
      expect(adopted, isNull); // sesi A lahir, tapi bukan B

      // Coordinator preload B (swipe berikutnya) → notifier fire → view adopt.
      coordinator.preloadNext('B');
      expect(adopted, isNotNull);
      expect(adopted, same(sessions['B']));
    });

    test('dispose fire sekali agar view lepas (sessionFor → null)', () {
      coordinator.setActive('A');
      var fires = 0;
      String? seen = 'sentinel';
      coordinator.registryListenable.addListener(() {
        fires++;
        seen = coordinator.sessionFor('A') == null ? null : 'ada';
      });
      coordinator.dispose();
      expect(fires, 1);
      expect(seen, isNull);
    });
  });

  group('KUNCI 2 — detach origin tetap hidup via pinned', () {
    test(
        'origin detach (attachment 0) tapi pinned → TIDAK dispose + masih '
        'sessionFor, walau >3 sesi', () {
      // Origin A dipakai inline; masuk fullscreen swipe menumpuk B/C/D.
      coordinator.setOrigin('A');
      coordinator.attach('inline', 'A');
      coordinator.setActive('A');
      coordinator.setActive('B');
      coordinator.preloadNext('C');

      // Origin inline detach (pindah ke fullscreen). Attachment A → 0.
      coordinator.detach('inline', 'A');
      // Tambah tekanan LRU: sesi ke-4.
      coordinator.setActive('C');
      coordinator.preloadNext('D');

      // A tetap hidup (pinned origin) walau attachment 0 & di luar peran aktif.
      expect(coordinator.livePostIds, contains('A'));
      expect(sessions['A']!.disposeCount, 0);
      expect(coordinator.sessionFor('A'), same(sessions['A']));
    });
  });

  group('urutan transisi deterministik (T7)', () {
    test(
        'setActive pause+mute active lama + evict yang lepas-role; '
        'origin & next selamat', () {
      coordinator.setOrigin('A'); // A pinned origin
      coordinator.setActive('A');
      coordinator.setActive('B'); // B active
      coordinator.preloadNext('C'); // C next
      expect(coordinator.livePostIds, {'A', 'B', 'C'});

      // Swipe B→C jadi active, preload D. B lepas semua peran (bukan origin/
      // active/next) & tak attached → dieviction. A(origin)+D(next) selamat.
      coordinator.setActive('C');
      coordinator.preloadNext('D');

      expect(sessions['B']!.pauseCount, greaterThan(0));
      expect(sessions['B']!.volume, 0);
      expect(sessions['B']!.disposeCount, 1);
      expect(coordinator.livePostIds, {'A', 'C', 'D'});
      expect(sessions['A']!.disposeCount, 0);
      expect(sessions['D']!.disposeCount, 0);
    });
  });
}

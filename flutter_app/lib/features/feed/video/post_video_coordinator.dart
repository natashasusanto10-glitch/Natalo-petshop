import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../../state/settings_store.dart';
import 'video_audio_arbiter.dart';

/// Abstraksi tipis di atas controller video (plugin-free) supaya
/// [PostVideoCoordinator] bisa di-unit-test tanpa plugin. Implementasi nyata
/// (membungkus VideoPlayerController / CachedVideoPlayerPlus) hidup di T3;
/// test memakai fake.
abstract class PlaybackSession {
  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(Duration position);
  Future<void> setVolume(double volume);
  Future<void> dispose();

  /// Posisi playback terakhir yang diketahui (untuk resume timestamp).
  Duration get position;
}

/// Factory pembuat sesi playback untuk sebuah post. Coordinator TIDAK tahu
/// URL/detail video — pemanggil (T3) menutup lookup post di closure ini.
typedef PlaybackSessionFactory = PlaybackSession Function(String postId);

/// Coordinator playback video untuk alur Postingan → fullscreen (plan
/// 2026-07-13, desain "C-lite" §2). Logika murni, plugin-free.
///
/// Kontrak inti (KUNCI USER):
/// - Coordinator adalah SATU-SATUNYA pemanggil [PlaybackSession.dispose].
/// - Maks 5 controller hidup: video ASAL, video AKTIF fullscreen, dan sampai
///   tiga adaptive preload. Asal == aktif → satu controller.
/// - `pinned` TERPISAH dari refcount attachment: dispose HANYA jika
///   tidak attached && tidak pinned && keluar window LRU. Attachment yang
///   sesaat 0 di tengah transisi TIDAK memicu dispose.
/// - Mute: hanya controller AKTIF mengikuti `feedMuted` (volume 0/1); semua
///   inactive/preload SELALU paused + volume 0; preload → aktif baru diberi
///   nilai `feedMuted` saat itu; unmute global TIDAK menyentuh background.
class PostVideoCoordinator {
  PostVideoCoordinator({
    required PlaybackSessionFactory sessionFactory,
    Listenable? mutedListenable,
    bool Function()? readMuted,
    VideoAudioArbiter? audioArbiter,
  })  : _sessionFactory = sessionFactory,
        _mutedListenable = mutedListenable ?? appSettingsStore,
        _readMuted = readMuted ?? (() => appSettingsStore.feedMuted),
        _audioArbiter = audioArbiter ?? videoAudioArbiter {
    _mutedListenable.addListener(_onMutedChanged);
  }

  /// Origin + active + at most three adaptive preload sessions.
  static const int maxSessions = 5;
  static const int maxPreloadSessions = 3;

  final PlaybackSessionFactory _sessionFactory;
  final Listenable _mutedListenable;
  final bool Function() _readMuted;
  final VideoAudioArbiter _audioArbiter;
  VideoAudioClaim? _audioClaim;
  Future<void>? _playbackTail;
  int _playbackGeneration = 0;

  final Map<String, _SessionEntry> _entries = <String, _SessionEntry>{};

  /// Revisi registry sesi (KUNCI 1 / T7). Naik SETIAP keberadaan/identitas
  /// sesi per-post berubah: sesi dibuat ([attach]/[setActive]/[preloadNext]/
  /// [setOrigin]), atau dihapus (eviction LRU / [dispose]). TIDAK naik untuk
  /// play/pause/seek/setVolume — supaya managed view (T7-integrasi) bisa
  /// listen tanpa badai rebuild dan re-cek [sessionFor] hanya saat sesi
  /// benar-benar lahir/mati.
  final ValueNotifier<int> _registryRevision = ValueNotifier<int>(0);

  /// True saat suatu mutasi mengubah himpunan sesi hidup; di-flush jadi satu
  /// fire di batas mutasi terluar (hindari fire re-entran/berulang).
  bool _registryDirty = false;
  int _mutationDepth = 0;

  /// Video ASAL (inline di Postingan) — pinned selama fullscreen terbuka.
  String? _originPostId;

  /// Video AKTIF (yang boleh bersuara / play) — pinned.
  String? _activePostId;

  final LinkedHashSet<String> _preloadPostIds = LinkedHashSet<String>();

  /// True hanya bila user secara eksplisit pause video aktif
  /// ([userTogglePlay]). Visibilitas/init TIDAK boleh menyetel ini.
  bool _userPausedActive = false;

  /// True saat [pauseAll] (background/route tertutup) — visibilitas tidak
  /// boleh auto-resume sampai ada intent baru (setActive/userTogglePlay).
  bool _suspended = false;

  bool _disposed = false;
  int _clock = 0;

  String? get originPostId => _originPostId;
  String? get activePostId => _activePostId;
  String? get preloadPostId =>
      _preloadPostIds.isEmpty ? null : _preloadPostIds.first;
  Set<String> get preloadPostIds => Set.unmodifiable(_preloadPostIds);
  bool get isDisposed => _disposed;

  /// Notifier registry sesi (KUNCI 1 / T7). Managed view yang belum punya sesi
  /// listen ke sini; saat fire, view re-cek [sessionFor]`(myPostId)` dan adopt
  /// bila sesinya sudah lahir (mis. hasil [preloadNext] saat swipe). Fire hanya
  /// saat keberadaan/identitas sesi per-post berubah, bukan tiap play/pause/
  /// volume.
  ValueListenable<int> get registryListenable => _registryRevision;

  /// Post yang saat ini punya sesi hidup (untuk debug/test).
  @visibleForTesting
  Set<String> get livePostIds => Set.unmodifiable(_entries.keys);

  /// Sesi milik [postId], bila hidup. View pemakai HANYA boleh merender dari
  /// sesi ini — play/pause/volume/dispose tetap urusan coordinator
  /// (`playbackManagedExternally: true`).
  PlaybackSession? sessionFor(String postId) => _entries[postId]?.session;

  /// Posisi playback terakhir [postId], bila sesinya hidup.
  Duration? positionOf(String postId) => _entries[postId]?.session.position;

  /// Transfers an already-started session into coordinator ownership.
  /// Duplicate/dead-coordinator sessions are disposed deterministically.
  bool adoptSession(String postId, PlaybackSession session) {
    if (_disposed || postId.trim().isEmpty || _entries.containsKey(postId)) {
      unawaited(session.dispose());
      return false;
    }
    return _guard(() {
      unawaited(session.pause());
      unawaited(session.setVolume(0));
      _entries[postId] = _SessionEntry(session)..lastUsed = ++_clock;
      _registryDirty = true;
      _evict();
      return true;
    });
  }

  // ── Intent dari view ──────────────────────────────────────────────────

  /// Sebuah view (inline/fullscreen item) mulai merender video [postId].
  /// Membuat sesi bila belum ada. Sesi baru SELALU lahir paused + volume 0
  /// — hanya [setActive] yang memberi suara/play.
  PlaybackSession attach(String viewId, String postId) {
    // Runtime guard (bukan cuma assert): view initState bisa race dgn dispose
    // coordinator. attach() punya return value + kontraknya "view sedang mau
    // merender" — kalau coordinator mati, caller keliru → throw, jangan diam2
    // bikin sesi yatim di luar lifecycle coordinator.
    if (_disposed) {
      throw StateError('PostVideoCoordinator.attach setelah dispose');
    }
    return _guard(() {
      final entry = _ensureEntry(postId);
      entry.attachedViewIds.add(viewId);
      entry.lastUsed = ++_clock;
      _evict();
      return entry.session;
    });
  }

  /// View berhenti merender [postId]. Attachment sesaat 0 TIDAK men-dispose:
  /// pinned + window LRU yang menentukan (lihat [_evict]).
  void detach(String viewId, String postId) {
    if (_disposed) return;
    final entry = _entries[postId];
    if (entry == null) return;
    _guard(() {
      entry.attachedViewIds.remove(viewId);
      _evict();
    });
  }

  /// Tandai video ASAL (inline Postingan) — pinned selama fullscreen buka.
  /// Kirim `null` saat fullscreen ditutup dan inline sudah tidak butuh pin.
  ///
  /// KONTRAK PENTING (F3): saat menutup fullscreen, view inline (T3) WAJIB
  /// `attach()` ulang ke sesi asal SEBELUM memanggil `setOrigin(null)`. Kalau
  /// tidak, dengan >3 sesi hidup, unpin bisa membuat sesi asal keluar window
  /// LRU dan langsung dieviction → resume inline instan hilang. Sebagai
  /// pertahanan inti, `setOrigin(null)` di sini men-touch `lastUsed` bekas
  /// origin agar ia jadi sesi PALING BARU dipakai; dengan begitu, walau
  /// sesaat unpinned & unattached, ia tetap paling belakang untuk dieviction.
  void setOrigin(String? postId) {
    if (_disposed) return;
    _guard(() {
      final previousOrigin = _originPostId;
      _originPostId = postId;
      if (postId != null) {
        _ensureEntry(postId).lastUsed = ++_clock;
      } else if (previousOrigin != null) {
        // Lindungi bekas origin: naikkan recency-nya supaya tidak jatuh keluar
        // window LRU sebelum inline sempat re-attach.
        final prev = _entries[previousOrigin];
        if (prev != null) prev.lastUsed = ++_clock;
      }
      _evict();
    });
  }

  /// Jadikan [postId] video AKTIF: aktif lama → paused + volume 0; aktif
  /// baru → volume dari `feedMuted` SAAT INI, lalu play (autoplay ala IG).
  void setActive(String postId) {
    if (_disposed) return;
    _guard(() {
      final previous = _activePostId;
      final previousSession = previous != null && previous != postId
          ? _entries[previous]?.session
          : null;
      _activePostId = postId;
      _userPausedActive = false;
      _suspended = false;
      _preloadPostIds.remove(postId);
      final entry = _ensureEntry(postId);
      entry.lastUsed = ++_clock;
      final generation = ++_playbackGeneration;
      _enqueuePlayback(() async {
        if (previousSession != null) {
          await previousSession.setVolume(0);
          await previousSession.pause();
        }
        await _claimAndPlay(entry, generation);
      });
      _evict();
    });
  }

  /// Siapkan satu video berikutnya: sesi dibuat paused + volume 0 dan
  /// pinned sampai window berubah (preload berikutnya / jadi aktif).
  void preloadNext(String postId) {
    setPreloadWindow([postId]);
  }

  /// Replaces the adaptive preload window atomically. IDs are de-duplicated,
  /// ordered, capped at three, and always kept paused and muted.
  void setPreloadWindow(Iterable<String> postIds) {
    if (_disposed) return;
    final protectedIds = <String>{
      if (_originPostId != null) _originPostId!,
      if (_activePostId != null) _activePostId!,
      ..._entries.entries
          .where((entry) => entry.value.attachedViewIds.isNotEmpty)
          .map((entry) => entry.key),
    };
    final availableSlots =
        (maxSessions - protectedIds.length).clamp(0, maxPreloadSessions);
    final next = <String>{};
    for (final id in postIds) {
      if (next.length >= availableSlots) break;
      if (id.isEmpty || id == _activePostId || id == _originPostId) continue;
      next.add(id);
    }
    _guard(() {
      _preloadPostIds
        ..clear()
        ..addAll(next);
      for (final id in next) {
        final entry = _ensureEntry(id);
        entry.lastUsed = ++_clock;
        unawaited(entry.session.pause());
        unawaited(entry.session.setVolume(0));
      }
      _disposeStaleUnprotectedEntries();
      _evict();
    });
  }

  /// View melaporkan video aktif terlihat lagi — resume bila user tidak
  /// sedang pause eksplisit dan coordinator tidak disuspend ([pauseAll]).
  void reportVisible(String postId) {
    if (_disposed) return;
    final entry = _entries[postId];
    if (entry == null) return;
    entry.lastUsed = ++_clock;
    if (postId != _activePostId) return;
    if (_userPausedActive || _suspended) return;
    final generation =
        _playbackGeneration == 0 ? ++_playbackGeneration : _playbackGeneration;
    _enqueuePlayback(() => _claimAndPlay(entry, generation));
  }

  /// View melaporkan video tidak terlihat — pause (sesi tetap hidup).
  void reportHidden(String postId) {
    if (_disposed) return;
    final entry = _entries[postId];
    if (entry == null) return;
    if (postId == _activePostId) {
      _playbackGeneration++;
      _releaseAudioClaim();
    }
    unawaited(entry.session.pause());
    unawaited(entry.session.setVolume(0));
    _enqueuePlayback(() async {
      await entry.session.setVolume(0);
      await entry.session.pause();
    });
  }

  /// User tap play/pause di video aktif. Satu-satunya sumber `userPaused`.
  void userTogglePlay() {
    if (_disposed) return;
    final active = _activePostId;
    if (active == null) return;
    final entry = _entries[active];
    if (entry == null) return;
    if (_userPausedActive) {
      _userPausedActive = false;
      _suspended = false;
      final generation = ++_playbackGeneration;
      _enqueuePlayback(() => _claimAndPlay(entry, generation));
    } else {
      _userPausedActive = true;
      _playbackGeneration++;
      _releaseAudioClaim();
      unawaited(entry.session.pause());
      unawaited(entry.session.setVolume(0));
    }
  }

  /// Background / route tertutup → pause SEMUA sesi (audio hantu #2).
  /// Tidak ada yang di-dispose; resume butuh intent baru.
  void pauseAll() {
    if (_disposed) return;
    _suspended = true;
    _playbackGeneration++;
    _releaseAudioClaim();
    for (final entry in _entries.values) {
      unawaited(entry.session.pause());
      unawaited(entry.session.setVolume(0));
    }
  }

  /// Foreground / route dibuka lagi → clear suspend DAN resume playback sesi
  /// AKTIF (kecuali user memang lagi pause eksplisit), dengan volume mengikuti
  /// `feedMuted` saat ini. Sesi non-aktif tetap paused + volume 0.
  ///
  /// Tanpa ini, `pauseAll` menyetel `_suspended=true` dan hanya
  /// setActive/userTogglePlay yang meng-clear-nya — jadi kalau foreground cuma
  /// mem-forward reportVisible, video aktif mati permanen.
  void resumeAll() {
    if (_disposed) return;
    _suspended = false;
    final active = _activePostId;
    if (active == null) return;
    if (_userPausedActive) return;
    final entry = _entries[active];
    if (entry == null) return;
    final generation = ++_playbackGeneration;
    _enqueuePlayback(() => _claimAndPlay(entry, generation));
  }

  /// Dispose coordinator + SEMUA sesi. Idempotent; setelah ini semua intent
  /// void (setActive/preloadNext/setOrigin/userTogglePlay/resumeAll/pauseAll)
  /// jadi silent no-op via runtime guard, dan [attach] melempar StateError.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _playbackGeneration++;
    _releaseAudioClaim();
    _mutedListenable.removeListener(_onMutedChanged);
    final entries = _entries.values.toList();
    final hadEntries = entries.isNotEmpty;
    _entries.clear();
    _originPostId = null;
    _activePostId = null;
    _preloadPostIds.clear();
    // Beri tahu view yang masih listen bahwa semua sesi lenyap (mereka re-cek
    // sessionFor → null → lepas), lalu tutup notifier. Fire sebelum dispose
    // karena notifyListeners menolak setelah dispose.
    if (hadEntries) _registryRevision.value++;
    _registryRevision.dispose();
    for (final entry in entries) {
      unawaited(entry.session.dispose());
    }
  }

  // ── Internal ──────────────────────────────────────────────────────────

  /// Jalankan mutasi lalu flush satu fire registry di batas terluar bila
  /// himpunan sesi berubah. Nesting (mis. listener re-entran) di-coalesce.
  T _guard<T>(T Function() body) {
    _mutationDepth++;
    try {
      return body();
    } finally {
      _mutationDepth--;
      if (_mutationDepth == 0 && _registryDirty && !_disposed) {
        _registryDirty = false;
        _registryRevision.value++;
      }
    }
  }

  void _onMutedChanged() {
    if (_disposed) return;
    final active = _activePostId;
    if (active == null) return;
    final entry = _entries[active];
    if (entry == null) return;
    // HANYA aktif yang mengikuti feedMuted; background/preload tidak
    // pernah dinaikkan volumenya oleh unmute global.
    unawaited(entry.session.setVolume(
      !_readMuted() && (_audioClaim?.isCurrent ?? false) ? 1 : 0,
    ));
  }

  void _enqueuePlayback(Future<void> Function() operation) {
    Future<void> run() {
      return operation();
    }

    final previous = _playbackTail;
    var next =
        previous == null ? Future<void>.sync(run) : previous.then((_) => run());
    next = next.catchError((Object error) {
      // Player teardown may reject an operation already queued. Keep the
      // serial tail usable for later lifecycle intents.
    });
    _playbackTail = next;
    unawaited(next.whenComplete(() {
      if (identical(_playbackTail, next)) _playbackTail = null;
    }));
  }

  bool _canPlayEntry(_SessionEntry entry, int generation) {
    return !_disposed &&
        generation == _playbackGeneration &&
        !_suspended &&
        !_userPausedActive &&
        identical(_entries[_activePostId]?.session, entry.session);
  }

  Future<void> _claimAndPlay(_SessionEntry entry, int generation) async {
    if (!_canPlayEntry(entry, generation)) {
      return;
    }
    final claim = _audioArbiter.claim(
      owner: this,
      onFocusLost: _onAudioFocusLost,
    );
    _audioClaim = claim;
    await entry.session.setVolume(
      !_readMuted() && claim.isCurrent ? 1 : 0,
    );
    if (!claim.isCurrent || !_canPlayEntry(entry, generation)) {
      await entry.session.setVolume(0);
      return;
    }
    await entry.session.play();
    if (!claim.isCurrent || !_canPlayEntry(entry, generation)) {
      await entry.session.setVolume(0);
      await entry.session.pause();
    }
  }

  void _onAudioFocusLost() {
    _playbackGeneration++;
    _audioClaim = null;
    final active = _activePostId;
    final entry = active == null ? null : _entries[active];
    if (entry == null) return;
    unawaited(entry.session.pause());
    unawaited(entry.session.setVolume(0));
  }

  void _releaseAudioClaim() {
    _audioClaim?.release();
    _audioClaim = null;
  }

  _SessionEntry _ensureEntry(String postId) {
    final existing = _entries[postId];
    if (existing != null) return existing;
    final session = _sessionFactory(postId);
    // Sesi baru selalu netral: paused + volume 0.
    unawaited(session.pause());
    unawaited(session.setVolume(0));
    final entry = _SessionEntry(session)..lastUsed = ++_clock;
    _entries[postId] = entry;
    _registryDirty = true; // sesi lahir → registry berubah (KUNCI 1).
    return entry;
  }

  bool _isPinned(String postId) =>
      postId == _originPostId ||
      postId == _activePostId ||
      _preloadPostIds.contains(postId);

  void _disposeStaleUnprotectedEntries() {
    final staleIds = _entries.entries
        .where((entry) =>
            !_isPinned(entry.key) && entry.value.attachedViewIds.isEmpty)
        .map((entry) => entry.key)
        .toList();
    for (final id in staleIds) {
      final entry = _entries.remove(id);
      if (entry == null) continue;
      _registryDirty = true;
      unawaited(entry.session.dispose());
    }
  }

  /// Dispose sesi yang: tidak pinned && tidak attached && keluar window LRU.
  /// Window = [maxSessions] sesi paling baru dipakai (pinned selalu masuk
  /// window lebih dulu).
  void _evict() {
    if (_entries.length <= maxSessions) {
      // Masih di dalam window — tidak ada yang keluar LRU, tidak ada
      // dispose (attachment 0 sesaat aman di sini).
      return;
    }
    final ids = _entries.keys.toList()
      ..sort((a, b) {
        final pinnedA = _isPinned(a) ? 1 : 0;
        final pinnedB = _isPinned(b) ? 1 : 0;
        if (pinnedA != pinnedB) return pinnedB - pinnedA;
        return _entries[b]!.lastUsed.compareTo(_entries[a]!.lastUsed);
      });
    for (var i = maxSessions; i < ids.length; i++) {
      final id = ids[i];
      final entry = _entries[id]!;
      if (_isPinned(id)) continue; // safety — pinned tak pernah dieviction.
      if (entry.attachedViewIds.isNotEmpty) continue; // masih dirender.
      _entries.remove(id);
      _registryDirty = true; // sesi mati → registry berubah (KUNCI 1).
      unawaited(entry.session.dispose());
    }
  }
}

class _SessionEntry {
  _SessionEntry(this.session);

  final PlaybackSession session;
  final Set<String> attachedViewIds = <String>{};
  int lastUsed = 0;
}

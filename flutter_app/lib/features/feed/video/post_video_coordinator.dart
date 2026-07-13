import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../state/settings_store.dart';

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
/// - Maks 3 controller hidup: video ASAL, video AKTIF fullscreen, dan satu
///   NEXT-PRELOAD. Asal == aktif → satu controller. Sisanya dieviction LRU.
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
  })  : _sessionFactory = sessionFactory,
        _mutedListenable = mutedListenable ?? appSettingsStore,
        _readMuted = readMuted ?? (() => appSettingsStore.feedMuted) {
    _mutedListenable.addListener(_onMutedChanged);
  }

  /// Jumlah maksimum sesi hidup — asal + aktif + next-preload (§2.3).
  static const int maxSessions = 3;

  final PlaybackSessionFactory _sessionFactory;
  final Listenable _mutedListenable;
  final bool Function() _readMuted;

  final Map<String, _SessionEntry> _entries = <String, _SessionEntry>{};

  /// Video ASAL (inline di Postingan) — pinned selama fullscreen terbuka.
  String? _originPostId;

  /// Video AKTIF (yang boleh bersuara / play) — pinned.
  String? _activePostId;

  /// NEXT-PRELOAD (paused + muted) — pinned sampai window berubah.
  String? _preloadPostId;

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
  String? get preloadPostId => _preloadPostId;
  bool get isDisposed => _disposed;

  /// Post yang saat ini punya sesi hidup (untuk debug/test).
  @visibleForTesting
  Set<String> get livePostIds => Set.unmodifiable(_entries.keys);

  /// Sesi milik [postId], bila hidup. View pemakai HANYA boleh merender dari
  /// sesi ini — play/pause/volume/dispose tetap urusan coordinator
  /// (`playbackManagedExternally: true`).
  PlaybackSession? sessionFor(String postId) => _entries[postId]?.session;

  /// Posisi playback terakhir [postId], bila sesinya hidup.
  Duration? positionOf(String postId) => _entries[postId]?.session.position;

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
    final entry = _ensureEntry(postId);
    entry.attachedViewIds.add(viewId);
    entry.lastUsed = ++_clock;
    _evict();
    return entry.session;
  }

  /// View berhenti merender [postId]. Attachment sesaat 0 TIDAK men-dispose:
  /// pinned + window LRU yang menentukan (lihat [_evict]).
  void detach(String viewId, String postId) {
    if (_disposed) return;
    final entry = _entries[postId];
    if (entry == null) return;
    entry.attachedViewIds.remove(viewId);
    _evict();
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
  }

  /// Jadikan [postId] video AKTIF: aktif lama → paused + volume 0; aktif
  /// baru → volume dari `feedMuted` SAAT INI, lalu play (autoplay ala IG).
  void setActive(String postId) {
    if (_disposed) return;
    final previous = _activePostId;
    if (previous != null && previous != postId) {
      final prevEntry = _entries[previous];
      if (prevEntry != null) {
        unawaited(prevEntry.session.pause());
        unawaited(prevEntry.session.setVolume(0));
      }
    }
    _activePostId = postId;
    _userPausedActive = false;
    _suspended = false;
    if (_preloadPostId == postId) _preloadPostId = null;
    final entry = _ensureEntry(postId);
    entry.lastUsed = ++_clock;
    unawaited(entry.session.setVolume(_readMuted() ? 0 : 1));
    unawaited(entry.session.play());
    _evict();
  }

  /// Siapkan satu video berikutnya: sesi dibuat paused + volume 0 dan
  /// pinned sampai window berubah (preload berikutnya / jadi aktif).
  void preloadNext(String postId) {
    if (_disposed) return;
    if (postId == _activePostId) return;
    _preloadPostId = postId;
    final entry = _ensureEntry(postId);
    entry.lastUsed = ++_clock;
    unawaited(entry.session.pause());
    unawaited(entry.session.setVolume(0));
    _evict();
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
    unawaited(entry.session.play());
  }

  /// View melaporkan video tidak terlihat — pause (sesi tetap hidup).
  void reportHidden(String postId) {
    if (_disposed) return;
    final entry = _entries[postId];
    if (entry == null) return;
    unawaited(entry.session.pause());
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
      unawaited(entry.session.play());
    } else {
      _userPausedActive = true;
      unawaited(entry.session.pause());
    }
  }

  /// Background / route tertutup → pause SEMUA sesi (audio hantu #2).
  /// Tidak ada yang di-dispose; resume butuh intent baru.
  void pauseAll() {
    if (_disposed) return;
    _suspended = true;
    for (final entry in _entries.values) {
      unawaited(entry.session.pause());
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
    unawaited(entry.session.setVolume(_readMuted() ? 0 : 1));
    unawaited(entry.session.play());
  }

  /// Dispose coordinator + SEMUA sesi. Idempotent; setelah ini semua intent
  /// void (setActive/preloadNext/setOrigin/userTogglePlay/resumeAll/pauseAll)
  /// jadi silent no-op via runtime guard, dan [attach] melempar StateError.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _mutedListenable.removeListener(_onMutedChanged);
    final entries = _entries.values.toList();
    _entries.clear();
    _originPostId = null;
    _activePostId = null;
    _preloadPostId = null;
    for (final entry in entries) {
      unawaited(entry.session.dispose());
    }
  }

  // ── Internal ──────────────────────────────────────────────────────────

  void _onMutedChanged() {
    if (_disposed) return;
    final active = _activePostId;
    if (active == null) return;
    final entry = _entries[active];
    if (entry == null) return;
    // HANYA aktif yang mengikuti feedMuted; background/preload tidak
    // pernah dinaikkan volumenya oleh unmute global.
    unawaited(entry.session.setVolume(_readMuted() ? 0 : 1));
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
    return entry;
  }

  bool _isPinned(String postId) =>
      postId == _originPostId ||
      postId == _activePostId ||
      postId == _preloadPostId;

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

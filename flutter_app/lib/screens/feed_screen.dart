import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shimmer/shimmer.dart';
import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../config/api_config.dart';
import '../theme/natalo_text.dart';
import '../features/feed/widgets/feed_action_rail.dart';
import '../features/feed/video/adaptive_video_preload_policy.dart';
import '../features/feed/video/feed_video_observation.dart';
import '../features/feed/video/preload_generation.dart';
import '../features/feed/video/single_dispose_guard.dart';
import '../features/feed/video/social_video_session_observer.dart';
import '../features/feed/video/video_media_cache.dart';
import '../features/feed/video/video_preload_metrics.dart';
import '../features/feed/widgets/feed_creator_overlay.dart';
import '../features/feed/widgets/feed_post_shared_widgets.dart';
import '../features/feed/widgets/feed_product_links_sheet.dart';
import '../features/feed/widgets/feed_video_post_view.dart';
import '../models/feed_post.dart';
import '../models/product.dart';
import '../screens/feed_user_search_screen.dart';
import '../services/api_client.dart';
import '../services/block_service.dart';
import '../services/feed_service.dart';
import '../services/product_service.dart';
import '../services/report_service.dart';
import '../services/video_quality_service.dart';
import '../state/cart_store.dart';
import '../state/feed_local_store.dart';
import '../state/feed_store.dart';
import '../state/member_store.dart';
import '../state/settings_store.dart';
import '../utils/android_back_overlays.dart';
import '../utils/haptics.dart';
import '../widgets/app_toast.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/feed_comment_sheet.dart';
import 'feed_media_picker_screen.dart';
import '../widgets/moderation_action_sheet.dart';

// Duplikat dari feed_action_rail.dart — dipakai _FeedPlusGlyph (tombol
// upload top-bar), yang tidak ikut diekstraksi karena bukan bagian rail.
const _feedActionForegroundColor = Color(0xFFFFFFFF);
const _feedActionShadowColor = Color(0x99000000);
// Anchor bawah BERSAMA caption + action rail — SATU angka untuk foto DAN
// video (jangan dibedakan per jenis post). Di video ini berarti overlap
// 12px ke atas hit-area scrubber 28px (zona transparan) supaya caption/rail
// duduk dekat garis progress ala IG, bukan melayang di atas seluruh box.
const _feedTopActionRightInset = 8.0;

@visibleForTesting
bool feedPreloadCompletionIsCurrent({
  required Object? registeredSlot,
  required Object candidate,
  required int? registeredGeneration,
  required int startedGeneration,
}) {
  return identical(registeredSlot, candidate) &&
      (registeredGeneration ?? -1) >= startedGeneration;
}

@visibleForTesting
bool registerFeedPreloadControllerIfCurrent<TSlot extends Object,
    TController extends Object>({
  required String id,
  required Map<String, TSlot> registeredSlots,
  required TSlot candidate,
  required Map<String, int> registeredGenerations,
  required int startedGeneration,
  required Map<String, TController> controllers,
  required TController controller,
}) {
  if (!feedPreloadCompletionIsCurrent(
    registeredSlot: registeredSlots[id],
    candidate: candidate,
    registeredGeneration: registeredGenerations[id],
    startedGeneration: startedGeneration,
  )) {
    return false;
  }
  controllers[id] = controller;
  return true;
}

@visibleForTesting
Future<VideoPlayerController?> initializeFeedCachedPreloadForObservation({
  required CachedVideoPlayerPlus player,
  required SocialVideoSessionObserver observer,
  required String postId,
  required bool Function() isCurrent,
  Future<void>? initialization,
}) async {
  await (initialization ?? player.initialize());
  final controller = player.controller;
  if (!isCurrent()) return null;
  observeFeedPreloadCreated(
    observer,
    postId: postId,
    controller: controller,
  );
  observeFeedControllerInitialized(
    observer,
    postId: postId,
    controller: controller,
    ownerId: feedPreloadOwnerId(postId),
  );
  return controller;
}

@visibleForTesting
Future<void> disposeFeedCachedPreloadForObservation({
  required CachedVideoPlayerPlus player,
  required VideoPlayerController? controller,
  required SocialVideoSessionObserver observer,
  required String postId,
  Future<void>? initialization,
}) async {
  if (!player.isInitialized && initialization != null) {
    await player.dispose();
    unawaited(() async {
      try {
        await initialization;
        if (!player.isInitialized) return;
        final controllerIdentity = player.controller;
        await player.dispose();
        observeFeedControllerDisposed(
          observer,
          postId: postId,
          controller: controllerIdentity,
          ownerId: feedPreloadOwnerId(postId),
        );
      } catch (_) {}
    }());
    return;
  }
  final controllerIdentity =
      controller ?? (player.isInitialized ? player.controller : null);
  try {
    await player.dispose();
  } finally {
    if (controllerIdentity != null) {
      observeFeedControllerDisposed(
        observer,
        postId: postId,
        controller: controllerIdentity,
        ownerId: feedPreloadOwnerId(postId),
      );
    }
  }
}

@visibleForTesting
bool feedPreloadUrlNeedsReplacement(String? existingUrl, String resolvedUrl) {
  return existingUrl != null && existingUrl != resolvedUrl;
}

@visibleForTesting
String feedResolvePreloadUrl({
  required String canonicalUrl,
  required String? dataSaverUrl,
  required String qualityPreference,
  NetworkTier? networkTier,
}) {
  return videoQualityService.resolvePlaybackUrl(
    canonicalUrl,
    dataSaverUrl: dataSaverUrl,
    userPreference: qualityPreference,
    // Test bridge only; production callers leave this null.
    // ignore: invalid_use_of_visible_for_testing_member
    networkTier: networkTier,
  );
}

/// Instagram Reels-style fullscreen vertical video feed.
/// - Fullscreen video/image background per post (cover fit)
/// - Top right: + button untuk upload (placeholder snackbar)
/// - Right column: like / comment / send / more — tight spacing rapi
/// - Bottom: avatar lingkaran + @username + caption + product chip
/// - Bottom nav: dark variant (semi-transparent blur), tetap visible
///
/// Native Flutter superpower yang Capacitor sulit replikasi:
/// - ExoPlayer/AVPlayer untuk video playback (hardware-decoded)
/// - VisibilityDetector untuk autoplay/pause
/// - 60fps animations (double-tap heart, like burst)
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final PageController _pageController = PageController();
  final GlobalKey _createPostOriginKey = GlobalKey();
  // Parallel maps: _preloadedControllers untuk reads (.value, VideoPlayer
  // widget, play/pause). _preloadedCachedPlayers untuk lifecycle (dispose
  // via wrapper supaya cache file di-track properly oleh
  // flutter_cache_manager). Wrapper instances 1:1 dengan controller di
  // map sebelahnya — selalu created bersamaan via CachedVideoPlayerPlus
  // pipeline. Pisah Map supaya existing code yang akses controller tidak
  // perlu di-refactor.
  final Map<String, VideoPlayerController> _preloadedControllers = {};
  final Map<String, CachedVideoPlayerPlus> _preloadedCachedPlayers = {};
  final Map<CachedVideoPlayerPlus, Future<void>> _cachedPreloadInitializations =
      {};
  final Map<String, String> _preloadedUrls = {};
  final Map<String, int> _preloadSlotGenerations = {};
  final Set<String> _localControllerOwners = <String>{};
  final ValueNotifier<int> _preloadRevision = ValueNotifier<int>(0);
  final SingleDisposeGuard<VideoPlayerController> _plainPreloadDisposer =
      SingleDisposeGuard<VideoPlayerController>();
  final SingleDisposeGuard<CachedVideoPlayerPlus> _cachedPreloadDisposer =
      SingleDisposeGuard<CachedVideoPlayerPlus>();
  StreamSubscription<NetworkTier>? _networkTierSubscription;
  late bool _lastPreloadAutoplay;
  late String _lastPreloadQuality;
  List<FeedPost> _posts = const [];
  String? _nextCursor;
  bool _loading = true;
  bool _loadingMore = false;
  bool _interactionLocked = false;
  bool _openingCreateRoute = false;
  bool _mediaZooming = false;
  bool _disposing = false;
  int _activeIndex = 0;
  VideoSwipeDirection _swipeDirection = VideoSwipeDirection.forward;
  Duration _activeBufferAhead = Duration.zero;
  int _preloadGeneration = 0;
  int _cartCount = 0;

  /// Gap #9: distinguish "no posts" vs "fetch error" — UI bisa show retry.
  String? _loadError;

  @override
  void initState() {
    super.initState();
    // Gap #11: load offline cache first untuk show stale data instantly
    // sambil network fetch jalan. Plus #7: hydrate likedStore.
    _bootstrapFromCache();
    _loadInitial();
    // Top-right cart icon — sync badge ke cartStore.totalQuantity supaya
    // real-time match dengan keranjang. Listener di-detach di dispose().
    _cartCount = cartStore.totalQuantity;
    cartStore.addListener(_syncTopCartCount);
    // UGC moderation — saat user block creator, refresh feed supaya
    // post-post dari creator itu langsung hilang dari view. blockService
    // notifyListeners() di-dispatch dari [moderation_action_sheet.dart].
    blockService.addListener(_onBlocklistChanged);
    blockService.load();
    _lastPreloadAutoplay = appSettingsStore.feedAutoplay;
    _lastPreloadQuality = appSettingsStore.feedVideoQuality;
    appSettingsStore.addListener(_onPreloadSettingsChanged);
    _networkTierSubscription =
        videoQualityService.tierChanges.listen(_onNetworkTierChanged);
    // Auto-trigger upload kalau dipush dari UploadVideoCta (Account screen
    // "Upload Video" button) yang kirim arguments `{openUpload: true}`.
    // Pakai post-frame callback supaya context.modalRoute settled.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map && args['openUpload'] == true) {
        _onUpload();
      }
    });
  }

  @override
  void dispose() {
    _disposing = true;
    cartStore.removeListener(_syncTopCartCount);
    blockService.removeListener(_onBlocklistChanged);
    appSettingsStore.removeListener(_onPreloadSettingsChanged);
    unawaited(_networkTierSubscription?.cancel());
    // Prefer dispose via wrapper — handles both underlying controller +
    // cache file reference. Sisa controllers tanpa wrapper (shouldn't
    // happen di prod tapi defensive) di-dispose langsung.
    for (final entry in _preloadedCachedPlayers.entries) {
      unawaited(_disposeCachedPreloadOnce(
        entry.key,
        entry.value,
        _preloadedControllers[entry.key],
      ));
    }
    for (final id in _preloadedControllers.keys.toList()) {
      if (!_preloadedCachedPlayers.containsKey(id)) {
        final controller = _preloadedControllers[id];
        if (controller != null) {
          unawaited(_disposePlainPreloadOnce(id, controller));
        }
      }
    }
    _preloadedCachedPlayers.clear();
    _preloadedControllers.clear();
    _preloadedUrls.clear();
    _preloadSlotGenerations.clear();
    _preloadRevision.dispose();
    _pageController.dispose();
    super.dispose();
  }

  /// Fix A5 — handoff preload TERKONFIRMASI. Dipanggil state
  /// FeedVideoPostView di initState (adopt), bukan dari build() screen.
  /// Remove atomik dari kedua map paralel: begitu diklaim, satu-satunya
  /// pemilik adalah state pengklaim (yang dispose); yang tidak pernah
  /// diklaim tetap di map dan di-dispose oleh screen (eviction window /
  /// dispose()). MP4 in-flight: wrapper sudah di map tapi controller
  /// belum → claim mengembalikan wrapper-saja; guard di _managePreloadWindow
  /// (`_preloadedCachedPlayers[id] != cachedPlayer`) mencegah controller
  /// hasil init masuk kembali ke map sebagai zombie, dan state pengklaim
  /// men-dispose wrapper orphan itu.
  PreloadedVideoClaim? _claimPreloadedVideo(String postId) {
    final controller = _preloadedControllers[postId];
    final cachedPlayer = _preloadedCachedPlayers[postId];
    if (controller == null && cachedPlayer == null) return null;
    if (controller == null) return const PreloadedVideoClaim.pending();
    _preloadedControllers.remove(postId);
    _preloadedCachedPlayers.remove(postId);
    _preloadedUrls.remove(postId);
    _preloadSlotGenerations.remove(postId);
    return PreloadedVideoClaim(
      controller: controller,
      cachedPlayer: cachedPlayer,
    );
  }

  void _onLocalControllerOwnershipChanged(String postId, bool ownsLocally) {
    if (_disposing) return;
    if (ownsLocally) {
      _localControllerOwners.add(postId);
      unawaited(_evictPreload(postId));
    } else {
      _localControllerOwners.remove(postId);
      if (mounted) unawaited(_managePreloadWindow(_activeIndex));
    }
  }

  void _onPreloadSettingsChanged() {
    if (_disposing) return;
    final autoplay = appSettingsStore.feedAutoplay;
    final quality = appSettingsStore.feedVideoQuality;
    if (autoplay == _lastPreloadAutoplay && quality == _lastPreloadQuality) {
      return;
    }
    _lastPreloadAutoplay = autoplay;
    _lastPreloadQuality = quality;
    if (mounted) unawaited(_managePreloadWindow(_activeIndex));
  }

  void _onNetworkTierChanged(NetworkTier _) {
    if (_disposing) return;
    _activeBufferAhead = Duration.zero;
    if (mounted) unawaited(_managePreloadWindow(_activeIndex));
  }

  Future<void> _disposePlainPreloadOnce(
    String postId,
    VideoPlayerController controller,
  ) async {
    await _plainPreloadDisposer.dispose(controller, () async {
      try {
        await controller.dispose();
      } finally {
        observeFeedControllerDisposed(
          socialVideoSessionObserver,
          postId: postId,
          controller: controller,
          ownerId: feedPreloadOwnerId(postId),
        );
      }
    });
  }

  Future<void> _disposeCachedPreloadOnce(
    String postId,
    CachedVideoPlayerPlus player,
    VideoPlayerController? controller,
  ) async {
    await _cachedPreloadDisposer.dispose(player, () async {
      await disposeFeedCachedPreloadForObservation(
        player: player,
        controller: controller,
        observer: socialVideoSessionObserver,
        postId: postId,
        initialization: _cachedPreloadInitializations[player],
      );
    });
  }

  Future<void> _evictPreload(String id) async {
    final cachedPlayer = _preloadedCachedPlayers.remove(id);
    final controller = _preloadedControllers.remove(id);
    _preloadedUrls.remove(id);
    _preloadSlotGenerations.remove(id);
    if (cachedPlayer != null) {
      await _disposeCachedPreloadOnce(
        id,
        cachedPlayer,
        controller,
      );
    } else if (controller != null) {
      await _disposePlainPreloadOnce(id, controller);
    }
    if (!_disposing) _preloadRevision.value++;
  }

  /// Cache hasil filter — re-compute hanya saat _posts berubah atau
  /// blocklist berubah. PERF: sebelumnya `_visiblePosts` getter
  /// re-filter O(n) di setiap build (page swipe, like tap, comment
  /// count change, dll). Dengan 50+ post cached → noticeable jank.
  /// Cache di-invalidate via `_rebuildVisiblePostsCache()` di
  /// blocklist change + setiap _posts assignment.
  List<FeedPost> _visiblePostsCache = const [];

  /// Re-filter _posts setelah user block creator. Dipanggil oleh
  /// [blockService.notifyListeners] dari [moderation_action_sheet.dart].
  void _onBlocklistChanged() {
    if (!mounted) return;
    _rebuildVisiblePostsCache();
    setState(() {});
  }

  /// Re-compute cache filtered. Caller WAJIB panggil setelah set
  /// _posts (post fetch, post add/delete) atau setelah blocklist
  /// change. setState terpisah supaya caller bisa batch.
  void _rebuildVisiblePostsCache() {
    if (!blockService.isLoaded || blockService.count == 0) {
      _visiblePostsCache = _posts;
      return;
    }
    _visiblePostsCache = _posts.where((p) {
      return !blockService.isUserBlocked(
        userId: p.author.id,
        userName: p.author.displayName,
      );
    }).toList(growable: false);
  }

  /// Read-only view ke cache — sekarang O(1) lookup, gak re-filter
  /// per build.
  List<FeedPost> get _visiblePosts => _visiblePostsCache;

  void _syncTopCartCount() {
    final next = cartStore.totalQuantity;
    if (!mounted || next == _cartCount) return;
    setState(() => _cartCount = next);
  }

  void _openCartPage() {
    AppHaptics.tap();
    Navigator.pushNamed(
      context,
      '/cart',
      arguments: const {'origin': 'feed'},
    );
  }

  void _openFeedSearch() {
    AppHaptics.tap();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FeedUserSearchScreen()),
    );
  }

  /// Gap #11: hydrate dari offline cache supaya feed tidak blank saat
  /// network slow. Cache otomatis di-replace saat fetch sukses.
  ///
  /// Defensive: kalau SharedPreferences corrupt atau decode fail, log
  /// + continue (jangan crash app). User crash report "saat buka feed
  /// langsung crash" sering disebabkan unhandled exception di sini.
  Future<void> _bootstrapFromCache() async {
    try {
      await feedLocalStore.initialize();
      if (!mounted) return;
      final cached = feedLocalStore.cachedPosts;
      if (cached.isNotEmpty && _posts.isEmpty) {
        setState(() {
          _posts = List<FeedPost>.from(cached);
          _rebuildVisiblePostsCache();
          // Tetap _loading=true sampai fetch network done — supaya kalau
          // network sukses, cache di-replace tanpa flicker UX.
        });
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[feed] _bootstrapFromCache error: $e\n$st');
      }
      // Silent fail — network fetch akan retake over.
    }
  }

  /// Gap #9: error-aware loader. Sebelumnya error di-swallow → user
  /// lihat empty state misleading. Sekarang catch + set _loadError +
  /// fall back ke cache kalau ada.
  ///
  /// Defensive 2: catch generic Exception too (was: only ApiException).
  /// Kalau JSON parse / type cast error throw uncaught → crash app saat
  /// buka tab Feed. Sekarang fallback ke error state dengan retry.
  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    // Capture timestamp SEBELUM await — stale-write guard. Kalau user tap
    // like di tengah fetch, store skip overwrite interaction fields karena
    // localActionAt > fetchedAt.
    final fetchedAt = DateTime.now();
    try {
      final page = await feedService.fetchPublicFeed();
      if (!mounted) return;
      // Seed shared FeedStore — single source of truth untuk like/comment
      // sync antar screen (Feed / Detail / Public Profile / Postingan Saya).
      feedStore.mergeFromServer(page.items, fetchedAt: fetchedAt);
      // Gap #7: merge backend viewerLiked dengan local cache.
      try {
        feedLocalStore.mergeBackendLiked(page.items);
        await feedLocalStore.cachePosts(page.items);
      } catch (e) {
        // Cache fail tidak block UI — log only.
        if (kDebugMode) debugPrint('[feed] cache persist error: $e');
      }
      if (!mounted) return;
      setState(() {
        _posts = page.items;
        _rebuildVisiblePostsCache();
        _nextCursor = page.nextCursor;
        _loading = false;
      });
      _preloadNext(_activeIndex);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = _posts.isEmpty
            ? (e.statusCode != null
                ? 'Feed tidak bisa dimuat (${e.statusCode}).'
                : 'Periksa koneksi internet lalu coba lagi.')
            : null;
      });
    } catch (e, st) {
      // Generic catch — JSON parse error, type cast error, dst yang
      // sebelumnya leak ke runtime crash. User pernah report "crash
      // saat tap tab Feed" → root cause sering di sini.
      if (kDebugMode) {
        debugPrint('[feed] _loadInitial unexpected error: $e\n$st');
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = _posts.isEmpty
            ? 'Feed sedang bermasalah. Tap untuk coba lagi.'
            : null;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _nextCursor == null) return;
    _loadingMore = true;
    final fetchedAt = DateTime.now();
    try {
      final page = await feedService.fetchPublicFeed(cursor: _nextCursor);
      if (!mounted) {
        _loadingMore = false;
        return;
      }
      feedStore.mergeFromServer(page.items, fetchedAt: fetchedAt);
      feedLocalStore.mergeBackendLiked(page.items);
      setState(() {
        _posts.addAll(page.items);
        _rebuildVisiblePostsCache();
        _nextCursor = page.nextCursor;
        _loadingMore = false;
      });
      _preloadNext(_activeIndex);
    } on ApiException catch (_) {
      // Pagination error — silent. User tetap bisa lihat existing posts.
      if (!mounted) return;
      setState(() => _loadingMore = false);
    } catch (_) {
      // BUGFIX(audit): error non-ApiException (mis. JSON parse / type-cast
      // saat response korup / schema berubah) sebelumnya BOCOR keluar tanpa
      // reset _loadingMore → guard di awal selalu return → pagination MATI
      // PERMANEN walau koneksi pulih. Reset flag di sini.
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  void _onPageChanged(int index) {
    _swipeDirection = index < _activeIndex
        ? VideoSwipeDirection.backward
        : VideoSwipeDirection.forward;
    _activeBufferAhead = Duration.zero;
    setState(() => _activeIndex = index);
    _preloadNext(index);
    // BUGFIX(audit): bandingkan index dengan _visiblePosts (list TERFILTER
    // yang dipakai PageView), bukan _posts (unfiltered). Saat ada user
    // diblok, _visiblePosts.length < _posts.length → trigger loadMore meleset
    // (kepicu kecepatan / tak pernah kepicu di ujung list pendek).
    if (index >= _visiblePosts.length - 2 && _nextCursor != null) {
      _loadMore();
    }
  }

  /// Adaptive controller window. Data saver/offline/autoplay-off keep none;
  /// cellular/unknown keep one directional target; WiFi keeps up to three.
  ///
  /// State per slot setelah pre-init:
  ///   - prev (i-1):    paused, seek 0, prepared. Attached saat user
  ///                    swipe back → instant play tanpa loading spinner.
  ///   - current (i):   widget FeedVideoPostView manage sendiri (play loop).
  ///   - next (i+1):    paused, seek 0, prepared. Attached saat swipe
  ///                    forward → instant play.
  ///   - next+1 (i+2):  paused, seek 0, prepared. Attached saat swipe
  ///                    dua kali berturut-turut → tetap instant play.
  ///   - others (jauh): unloaded (dispose), free ~30MB native heap/slot.
  ///
  /// Total RAM aktif: 4 controllers × ~30MB = ~120MB. Safe untuk phone
  /// 2GB+. Android ExoPlayer limit ~8 slot di low-end device, kita pakai 4
  /// jadi masih ample headroom untuk PIP/background notifications.
  Future<void> _managePreloadWindow(int activeIndex) async {
    final generation = ++_preloadGeneration;
    final networkTier = videoQualityService.currentTier;
    final qualityPreference = appSettingsStore.feedVideoQuality;
    // Build set of post IDs yang harus di-keep di window.
    // Forward preload 2 (next + next+1) — penting untuk smooth TikTok-style
    // swipe sequence. Backward preload 1 (prev) cukup karena user jarang
    // swipe-back lebih dari sekali berturut-turut.
    // BUGFIX(audit): index window pakai _visiblePosts (list TERFILTER yg
    // dipakai PageView), bukan _posts (unfiltered). activeIndex = index di
    // VISIBLE list (dari onPageChanged). Saat ada user diblok, _posts[index]
    // BUKAN post yang ditonton user → preload controller video untuk post
    // yang salah (swipe tidak instan). Pakai _visiblePosts konsisten.
    final visible = _visiblePosts;
    final offsets = adaptiveVideoPreloadPolicy.offsets(
      qualityPreference: qualityPreference,
      networkTier: networkTier,
      autoplayEnabled: appSettingsStore.feedAutoplay,
      swipeDirection: _swipeDirection,
      activeBufferAhead: _activeBufferAhead,
      interactionLocked: _interactionLocked || _mediaZooming,
    );
    final keepIds = <String>{};
    for (final offset in offsets) {
      final i = activeIndex + offset;
      if (i >= 0 && i < visible.length) {
        keepIds.add(visible[i].id);
      }
    }

    // Dispose controllers di luar window — free ~30MB per controller +
    // release native ExoPlayer/AVPlayer slot (limited 4-8 di Android).
    // Dispose via wrapper kalau ada (handle cache properly), fallback ke
    // controller dispose langsung. Cache file di disk TIDAK dihapus —
    // tetap available untuk repeat-view (itu point disk cache).
    final staleIds = {
      ..._preloadedControllers.keys,
      ..._preloadedCachedPlayers.keys,
    }.where((id) => !keepIds.contains(id)).toList();
    for (final id in staleIds) {
      await _evictPreload(id);
      if (_disposing || generation != _preloadGeneration) return;
      recordVideoPreloadMetric(
        'evicted',
        surface: 'main_feed',
        tier: networkTier,
        windowSize: keepIds.length,
      );
    }

    if (offsets.isEmpty) return;

    // Pre-init controllers yang masih dalam window tapi belum ada.
    // Paralel init (Future.wait) supaya prev + next siap bersamaan.
    final activePost = activeIndex >= 0 && activeIndex < visible.length
        ? visible[activeIndex]
        : null;
    final initFutures = <Future<void>>[];

    for (final id in keepIds) {
      // Skip current — widget FeedVideoPostView create sendiri di-mount.
      if (activePost != null && id == activePost.id) continue;
      if (_localControllerOwners.contains(id)) continue;
      FeedPost? post;
      for (final p in _posts) {
        if (p.id == id) {
          post = p;
          break;
        }
      }
      if (post == null) continue;
      final url = post.videoPlaybackUrl;

      // Resolve before skipping: cellular Auto/Data Saver may legitimately
      // use the backend-provided 480p URL when the canonical URL is absent.
      final resolvedUrl = feedResolvePreloadUrl(
        canonicalUrl: url,
        dataSaverUrl: post.videoDataSaverUrl,
        qualityPreference: qualityPreference,
      );
      if (resolvedUrl.isEmpty) continue;

      final thumb = post.thumbnailUrl;
      if (mounted && thumb != null && thumb.isNotEmpty) {
        // PERF: precacheImage blocking main thread (decode + cache write).
        // Schedule off-frame via microtask supaya gak nge-stutter swipe.
        // Fire-and-forget — kalau gagal, image fallback ke normal lazy load.
        Future.microtask(() {
          if (!mounted) return;
          precacheImage(CachedNetworkImageProvider(thumb), context);
        });
      }

      // Network-aware quality rewrite (Sprint 2 #7) + user preference dari
      // Settings (data_saver → paksa 480p, high → cap 720p, auto → tier-based).
      final existingUrl = _preloadedUrls[id];
      if (feedPreloadUrlNeedsReplacement(existingUrl, resolvedUrl)) {
        await _evictPreload(id);
        if (_disposing || generation != _preloadGeneration) return;
      }
      if (preloadSlotOccupied(
        id,
        _preloadedControllers,
        _preloadedCachedPlayers,
      )) {
        _preloadSlotGenerations[id] = generation;
        continue;
      }
      if (_disposing || generation != _preloadGeneration) return;

      // ── HLS bypass cache wrapper ──
      // HLS (.m3u8) = manifest + multiple segments. CachedVideoPlayerPlus
      // download single URL ke disk dan play dari local file — works
      // untuk MP4 progressive (1 file = 1 video), TAPI rusak untuk HLS
      // karena segments tidak ke-cache (cuma playlist file). Saat
      // playback, video_player coba load segments dari local cache path
      // → relative URL miss → fail.
      //
      // Solusi: kalau URL HLS, pakai plain VideoPlayerController.networkUrl
      // langsung. HLS handle own caching at HTTP layer (range requests).
      // MP4 tetap pakai CachedVideoPlayerPlus untuk repeat-view benefit
      // (legacy support untuk post .mp4 yang belum di-migrate).
      final isHls = resolvedUrl.contains('.m3u8');
      recordVideoPreloadMetric(
        'requested',
        surface: 'main_feed',
        tier: networkTier,
        windowSize: keepIds.length,
      );
      if (isHls) {
        final controller = VideoPlayerController.networkUrl(
          Uri.parse(resolvedUrl),
        );
        observeFeedPreloadCreated(
          socialVideoSessionObserver,
          postId: id,
          controller: controller,
        );
        _preloadedControllers[id] = controller;
        _preloadedUrls[id] = resolvedUrl;
        _preloadSlotGenerations[id] = generation;
        initFutures.add(
          controller.initialize().then((_) async {
            if (!feedPreloadCompletionIsCurrent(
              registeredSlot: _preloadedControllers[id],
              candidate: controller,
              registeredGeneration: _preloadSlotGenerations[id],
              startedGeneration: generation,
            )) {
              if (identical(_preloadedControllers[id], controller)) {
                await _evictPreload(id);
              }
              return;
            }
            observeFeedControllerInitialized(
              socialVideoSessionObserver,
              postId: id,
              controller: controller,
              ownerId: feedPreloadOwnerId(id),
            );
            await controller.setLooping(true);
            if (!feedPreloadCompletionIsCurrent(
              registeredSlot: _preloadedControllers[id],
              candidate: controller,
              registeredGeneration: _preloadSlotGenerations[id],
              startedGeneration: generation,
            )) {
              return;
            }
            await controller.setVolume(0);
            if (!feedPreloadCompletionIsCurrent(
              registeredSlot: _preloadedControllers[id],
              candidate: controller,
              registeredGeneration: _preloadSlotGenerations[id],
              startedGeneration: generation,
            )) {
              return;
            }
            await controller.seekTo(Duration.zero);
            if (!_disposing) _preloadRevision.value++;
            recordVideoPreloadMetric(
              'ready',
              surface: 'main_feed',
              tier: networkTier,
              windowSize: keepIds.length,
            );
          }).catchError((Object _) async {
            observeFeedControllerFailed(
              socialVideoSessionObserver,
              postId: id,
              controller: controller,
              ownerId: feedPreloadOwnerId(id),
            );
            if (identical(_preloadedControllers[id], controller)) {
              _preloadedControllers.remove(id);
              _preloadedUrls.remove(id);
              _preloadSlotGenerations.remove(id);
            }
            await _disposePlainPreloadOnce(id, controller);
            recordVideoPreloadMetric(
              'failed',
              surface: 'main_feed',
              tier: networkTier,
              windowSize: keepIds.length,
            );
          }),
        );
        continue;
      }

      // MP4 path — keep cache wrapper.
      // Wrap dengan CachedVideoPlayerPlus → disk cache otomatis aktif.
      // Repeat-view video sama → load instant dari disk HP (0 data).
      // TTL 7 hari — cache invalidate kalau lebih lama (auto re-download).
      // .controller exposes underlying VideoPlayerController, jadi existing
      // code yang akses .value / play() / pause() tetap work.
      final cachedPlayer = CachedVideoPlayerPlus.networkUrl(
        Uri.parse(resolvedUrl),
        invalidateCacheIfOlderThan: const Duration(days: 7),
        cacheKey: videoMediaCacheKey(mediaId: id, url: resolvedUrl),
      );
      _preloadedCachedPlayers[id] = cachedPlayer;
      _preloadedUrls[id] = resolvedUrl;
      _preloadSlotGenerations[id] = generation;
      final initialization = cachedPlayer.initialize();
      _cachedPreloadInitializations[cachedPlayer] = initialization;
      initFutures.add(
        initializeFeedCachedPreloadForObservation(
          player: cachedPlayer,
          observer: socialVideoSessionObserver,
          postId: id,
          initialization: initialization,
          isCurrent: () => feedPreloadCompletionIsCurrent(
            registeredSlot: _preloadedCachedPlayers[id],
            candidate: cachedPlayer,
            registeredGeneration: _preloadSlotGenerations[id],
            startedGeneration: generation,
          ),
        ).then((controller) async {
          // Entry mungkin sudah DIKONSUMSI itemBuilder (post keburu aktif —
          // child dispose wrapper in-flight sendiri) atau di-evict window.
          // Tanpa guard ini, controller di-re-add ke map sebagai zombie
          // yang tidak pernah di-dispose (leak native player).
          if (controller == null) {
            if (_preloadedCachedPlayers[id] == cachedPlayer) {
              await _evictPreload(id);
            }
            return;
          }
          if (!registerFeedPreloadControllerIfCurrent(
            id: id,
            registeredSlots: _preloadedCachedPlayers,
            candidate: cachedPlayer,
            registeredGenerations: _preloadSlotGenerations,
            startedGeneration: generation,
            controllers: _preloadedControllers,
            controller: controller,
          )) {
            await _disposeCachedPreloadOnce(id, cachedPlayer, controller);
            return;
          }
          // Prepared state: paused, frame 0 ready, muted, looping prepped.
          // Saat widget attach via preloadedController prop, tinggal play()
          // — instant, no init lag.
          await controller.setLooping(true);
          if (!feedPreloadCompletionIsCurrent(
            registeredSlot: _preloadedCachedPlayers[id],
            candidate: cachedPlayer,
            registeredGeneration: _preloadSlotGenerations[id],
            startedGeneration: generation,
          )) {
            return;
          }
          await controller.setVolume(0);
          if (!feedPreloadCompletionIsCurrent(
            registeredSlot: _preloadedCachedPlayers[id],
            candidate: cachedPlayer,
            registeredGeneration: _preloadSlotGenerations[id],
            startedGeneration: generation,
          )) {
            return;
          }
          await controller.seekTo(Duration.zero);
          if (!_disposing) _preloadRevision.value++;
          recordVideoPreloadMetric(
            'ready',
            surface: 'main_feed',
            tier: networkTier,
            windowSize: keepIds.length,
          );
        }).catchError((Object _) async {
          // Init gagal — kemungkinan besar disk cache corrupt (force-kill
          // mid-write left partial file). Invalidate cache entry supaya
          // attempt berikutnya (e.g. preload pass berikutnya, atau saat
          // user scroll ke post ini dan _maybeInitVideo run) bisa fresh-
          // fetch dari network. Tanpa ini, cache wrapper tetap baca file
          // corrupt setiap retry.
          final ownController =
              cachedPlayer.isInitialized ? cachedPlayer.controller : null;
          final ownsFailedGeneration = ownController == null
              ? identical(_preloadedCachedPlayers.remove(id), cachedPlayer)
              : removeFailedPreloadGeneration(
                  id: id,
                  failedWrapper: cachedPlayer,
                  failedController: ownController,
                  controllers: _preloadedControllers,
                  wrappers: _preloadedCachedPlayers,
                );
          if (!ownsFailedGeneration) return;
          if (ownController != null) {
            observeFeedControllerFailed(
              socialVideoSessionObserver,
              postId: id,
              controller: ownController,
              ownerId: feedPreloadOwnerId(id),
            );
          }
          _preloadedUrls.remove(id);
          _preloadSlotGenerations.remove(id);
          await _disposeCachedPreloadOnce(
            id,
            cachedPlayer,
            ownController,
          );
          if (!_disposing) _preloadRevision.value++;
          try {
            await evictVideoMediaCache(mediaId: id, url: resolvedUrl);
          } catch (_) {}
          recordVideoPreloadMetric(
            'failed',
            surface: 'main_feed',
            tier: networkTier,
            windowSize: keepIds.length,
          );
        }).whenComplete(
          () => _cachedPreloadInitializations.remove(cachedPlayer),
        ),
      );
    }
    await Future.wait(initFutures);
  }

  /// Backward-compat alias — internal callers (_loadInitial,
  /// _onPageChanged) tetap pakai nama _preloadNext. Forward ke
  /// _managePreloadWindow yang handle 3-item sliding window.
  Future<void> _preloadNext(int index) => _managePreloadWindow(index);

  void _onActiveBufferAheadChanged(String postId, Duration bufferAhead) {
    if (_activeIndex < 0 || _activeIndex >= _visiblePosts.length) return;
    if (_visiblePosts[_activeIndex].id != postId) return;
    final wasEligible = _activeBufferAhead >=
        AdaptiveVideoPreloadPolicy.cellularBufferAheadThreshold;
    if (bufferAhead > _activeBufferAhead) _activeBufferAhead = bufferAhead;
    final isEligible = _activeBufferAhead >=
        AdaptiveVideoPreloadPolicy.cellularBufferAheadThreshold;
    if (!wasEligible && isEligible) {
      unawaited(_managePreloadWindow(_activeIndex));
    }
  }

  void _setFeedInteractionLocked(bool locked) {
    if (!mounted || _interactionLocked == locked) return;
    setState(() => _interactionLocked = locked);
    unawaited(_managePreloadWindow(_activeIndex));
  }

  void _setFeedMediaZooming(bool zooming) {
    if (!mounted || _mediaZooming == zooming) return;
    setState(() => _mediaZooming = zooming);
    unawaited(_managePreloadWindow(_activeIndex));
  }

  Future<void> _onUpload() async {
    if (_openingCreateRoute) return;
    _openingCreateRoute = true;
    _setFeedInteractionLocked(true);
    // Unified "Postingan baru" flow — push FeedMediaPickerScreen via
    // FeedMediaPickerScreen.open() yang juga dipakai oleh member_screen
    // dan member_posts_screen. Picker IG-style (preview + gallery grid)
    // handle photo + video di satu screen, lalu push FeedNewPostScreen
    // untuk caption + product tag + submit.
    //
    // Sebelumnya feed_screen pakai _UploadChoiceSheet (split video/photo
    // dulu) → flow lama yang inkonsisten dengan akun entry. Sekarang
    // SEMUA "+" icon (feed + akun + postingan saya) lead ke flow yang
    // sama untuk konsistensi UX.
    try {
      await FeedMediaPickerScreen.openFromOrigin(
        context,
        _createPostOriginKey,
      );
      if (mounted) _setFeedInteractionLocked(false);
      if (!mounted) return;
      await _loadInitial();
    } finally {
      _openingCreateRoute = false;
      if (mounted) _setFeedInteractionLocked(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final canRefresh =
        !_interactionLocked && !keyboardOpen && _activeIndex == 0 && !_loading;
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      extendBodyBehindAppBar: true,
      // extendBody: true — media (video/foto) memanjang ke belakang bottom
      // nav supaya frosted glass nav (BottomNavVariant.dark) punya konten
      // untuk di-blur, konsisten dengan halaman lain. Sebelumnya false
      // (media berhenti di atas nav) → nav Feed jadi hitam solid, tidak
      // tembus seperti nav di halaman lain. Caption/actions overlay pakai
      // Positioned dengan padding eksplisit dari MediaQuery bottom inset,
      // jadi tidak tertutup nav walau media kini extend penuh ke bawah.
      extendBody: true,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        // Outer Stack — feed content only. Upload entry tetap tersedia via
        // deep link/flow, tetapi tombol plus tidak tampil di layar Feed.
        child: Stack(
          children: [
            // Body content per state.
            // Gap #9: kalau load error + tidak ada cached posts → tampil
            // _ErrorState dengan retry button (bukan _EmptyState yang
            // misleading "belum ada postingan").
            if (_loading && _posts.isEmpty)
              const _LoadingState()
            else if (_loadError != null && _posts.isEmpty)
              _FeedErrorState(message: _loadError!, onRetry: _loadInitial)
            else if (_posts.isEmpty)
              const _EmptyState()
            else
              RefreshIndicator(
                color: Colors.white,
                backgroundColor: Colors.black87,
                // Wider displacement supaya pull-down feel lebih elastic —
                // user tarik lebih jauh sebelum trigger refresh, match
                // iOS rubber-band feel di TikTok / IG Reels.
                displacement: 80,
                strokeWidth: 2.6,
                notificationPredicate: (notification) {
                  return canRefresh && notification.depth == 0;
                },
                onRefresh: _loadInitial,
                child: Builder(builder: (context) {
                  // Filter post dari blocked users sebelum render. Re-compute
                  // setiap rebuild — cheap karena blockService.isLoaded check
                  // + Set lookup O(1) per post.
                  final visible = _visiblePosts;
                  return PageView.builder(
                    controller: _pageController,
                    scrollDirection: Axis.vertical,
                    physics: (_interactionLocked || _mediaZooming)
                        ? const NeverScrollableScrollPhysics()
                        // BouncingScrollPhysics di parent untuk rubber-band
                        // overscroll di Android (iOS default sudah elastic).
                        // PageScrollPhysics di-keep untuk page snap behavior
                        // (TikTok-style snap per post).
                        : const PageScrollPhysics(
                            parent: BouncingScrollPhysics(),
                          ),
                    itemCount: visible.length,
                    onPageChanged: _onPageChanged,
                    itemBuilder: (context, index) {
                      final post = visible[index];
                      // Branch by kind: PHOTO_CAROUSEL render carousel
                      // PageView horizontal 1-8 foto; video kind render
                      // FeedVideoPostView dengan VideoPlayerController.
                      // ValueKey(post.id) WAJIB — tanpa key, Flutter match
                      // State by posisi list. Saat _visiblePosts bergeser
                      // (block/unblock user), State di index i menerima post
                      // BERBEDA dan controller video lama tetap memutar klip
                      // lama di bawah post baru (audio nyasar).
                      if (post.isPhotoCarousel) {
                        return _PhotoCarouselPostView(
                          key: ValueKey('feed-photo-${post.id}'),
                          post: post,
                          isActive: index == _activeIndex,
                          onOverlayStateChanged: _setFeedInteractionLocked,
                          onMediaZoomChanged: _setFeedMediaZooming,
                        );
                      }
                      return FeedVideoPostView(
                        key: ValueKey('feed-video-${post.id}'),
                        post: post,
                        isActive: index == _activeIndex,
                        framing: FeedVideoFraming.mainFeed,
                        // Fix A5: JANGAN remove() dari map di build().
                        // Kalau parent rebuild tapi state ber-key sama masih
                        // hidup (initState tidak jalan lagi), controller yang
                        // di-remove di sini tidak pernah diadopsi siapa pun →
                        // yatim: tak pernah di-dispose, kandidat audio hantu.
                        // Handoff terkonfirmasi: state penerima mengklaim
                        // sendiri via callback di initState — remove dari map
                        // terjadi di sana. Wrapper cache ikut dalam claim
                        // (child tetap butuh wrapper untuk dispose proper).
                        preloadedController: null,
                        claimPreloadedVideo: () =>
                            _claimPreloadedVideo(post.id),
                        preloadListenable: _preloadRevision,
                        onLocalOwnershipChanged: (owns) =>
                            _onLocalControllerOwnershipChanged(post.id, owns),
                        onBufferAheadChanged: (ahead) =>
                            _onActiveBufferAheadChanged(post.id, ahead),
                        onOverlayStateChanged: _setFeedInteractionLocked,
                        onMediaZoomChanged: _setFeedMediaZooming,
                      );
                    },
                  );
                }),
              ),
            // Top overlay — `+` upload (kiri) + search/cart stack (kanan).
            // Plain icons (no glass/blur pill) per mockup TikTok-style. Safe
            // area aware via MediaQuery.padding.top supaya tidak overlap
            // dengan notch / status bar di iOS+Android. Saat overlay aktif,
            // chrome menghilang bersama bottom nav agar compact media bersih.
            AnimatedOpacity(
              key: const ValueKey('feed-top-chrome'),
              opacity: (_mediaZooming || _interactionLocked) ? 0 : 1,
              duration: const Duration(milliseconds: 160),
              child: IgnorePointer(
                ignoring: _mediaZooming || _interactionLocked,
                child: Stack(
                  children: [
                    Positioned(
                      top: MediaQuery.paddingOf(context).top + 8,
                      left: 4,
                      child: RepaintBoundary(
                        key: _createPostOriginKey,
                        child: _FeedTopIconButton(
                          key: const ValueKey('feed-create-post'),
                          iconChild: const _FeedPlusGlyph(),
                          onTap: _onUpload,
                          tooltip: 'Upload video',
                        ),
                      ),
                    ),
                    Positioned(
                      top: MediaQuery.paddingOf(context).top + 8,
                      right: _feedTopActionRightInset,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _FeedTopIconButton(
                            icon: Icons.search_rounded,
                            onTap: _openFeedSearch,
                            tooltip: 'Cari',
                          ),
                          const SizedBox(height: 2),
                          _FeedTopIconButton(
                            // Icon SHAPE match home AppCartButton:
                            // shopping_cart_outlined. Size tetap 28 (default
                            // _FeedTopIconButton) supaya tetap prominent di atas
                            // video — beda dari home yang 24 karena context-nya
                            // beda (header dense dengan banyak icon).
                            icon: Icons.shopping_cart_outlined,
                            onTap: _openCartPage,
                            tooltip: 'Keranjang',
                            badgeCount: _cartCount > 0 ? _cartCount : null,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: (_interactionLocked || _mediaZooming)
            ? const SizedBox.shrink(key: ValueKey('feed-nav-hidden'))
            : const BottomNavBar(
                key: ValueKey('feed-nav-visible'),
                currentIndex: 2,
                variant: BottomNavVariant.dark,
              ),
      ),
    );
  }
}

/// Sprint 5 #7 — Skeleton shimmer loader.
///
/// Mirror struktur actual feed card (video area + right rail + bottom info)
/// dengan grey shimmer placeholder. Perceived performance jauh lebih
/// premium dari spinner kosong — user paham "feed sedang load",
/// bukan "loading screen blank".
///
/// Pakai shimmer package yang sudah installed (app_product_image +
/// skeleton_product_card juga pakai).
class _LoadingState extends StatelessWidget {
  const _LoadingState();

  static const _baseColor = Color(0xFF1A1F26);
  static const _highlightColor = Color(0xFF2A2F36);

  @override
  Widget build(BuildContext context) {
    // MediaQuery.padding.bottom SUDAH mencakup tinggi nav (extendBody) —
    // lihat feedPostOverlayBaseInset. Jangan tambah kFloatingNavClearance.
    final base = feedPostOverlayBaseInset(context);
    // Mirror anchor rail dan caption dari post nyata supaya transisi
    // skeleton → konten tidak bikin elemen loncat posisi.
    final actionRailInset = base + feedPostActionRailBottomGap;
    final feedInfoInset = base + feedPostOverlayBottomGap;

    return Shimmer.fromColors(
      baseColor: _baseColor,
      highlightColor: _highlightColor,
      period: const Duration(milliseconds: 1400),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Video area placeholder — full screen background.
          const ColoredBox(color: _baseColor),

          // Gradient overlay bottom (mock real card supaya skeleton tidak
          // terlihat solid flat).
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 280,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      _baseColor.withValues(alpha: 0.6),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Right action rail mock — Like/Comment/Share only. Match
          // positioning aktual yang duduk tepat di atas bottom nav.
          Positioned(
            right: feedPostActionRailRightInset,
            bottom: actionRailInset,
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SkeletonCircle(size: 38),
                SizedBox(height: 10),
                _SkeletonCircle(size: 38),
                SizedBox(height: 10),
                _SkeletonCircle(size: 38),
              ],
            ),
          ),

          // Bottom-left info mock — product chip + username + caption bars.
          Positioned(
            left: 16,
            right: 78,
            bottom: feedInfoInset,
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Product link chip mock — pill shape ~40px tinggi.
                _SkeletonBar(width: 220, height: 40, radius: 16),
                SizedBox(height: 12),
                // Username mock — pendek ~120px.
                _SkeletonBar(width: 120, height: 14, radius: 4),
                SizedBox(height: 10),
                // Caption mock — 2 baris.
                _SkeletonBar(width: double.infinity, height: 12, radius: 4),
                SizedBox(height: 6),
                _SkeletonBar(width: 240, height: 12, radius: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Plain top-overlay icon button untuk feed (`+` upload kiri, keranjang
/// kanan). NO glass pill / blur / background — TikTok style polos cuma
/// icon putih dengan soft drop shadow biar tetap legible di atas video
/// yang bright. Optional badgeCount untuk indikator jumlah keranjang.
class _FeedTopIconButton extends StatelessWidget {
  final IconData? icon;
  final Widget? iconChild;
  final VoidCallback onTap;
  final String? tooltip;
  final int? badgeCount;

  const _FeedTopIconButton({
    super.key,
    this.icon,
    this.iconChild,
    required this.onTap,
    this.tooltip,
    this.badgeCount,
  }) : assert(icon != null || iconChild != null);

  @override
  Widget build(BuildContext context) {
    final iconWidget = Stack(
      clipBehavior: Clip.none,
      children: [
        iconChild ??
            Icon(
              icon,
              color: Colors.white,
              // 28px — sized untuk visibility tinggi di atas video terang/
              // gelap. Beda dari home AppCartButton (24px) karena context
              // berbeda: home header dense banyak icon, feed top icon harus
              // prominent solo dengan soft drop shadow.
              size: 28,
              shadows: const [
                Shadow(
                  color: Color(0xCC000000),
                  blurRadius: 10,
                  offset: Offset(0, 1),
                ),
              ],
            ),
        if (badgeCount != null && badgeCount! > 0)
          Positioned(
            top: -4,
            right: -6,
            child: Container(
              constraints: const BoxConstraints(
                minWidth: 18,
                minHeight: 18,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.black, width: 1.2),
              ),
              alignment: Alignment.center,
              child: Text(
                badgeCount! > 99 ? '99+' : '$badgeCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: NataloWeight.strong,
                  height: 1,
                ),
              ),
            ),
          ),
      ],
    );
    final button = InkResponse(
      onTap: onTap,
      radius: 26,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: iconWidget,
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

/// Glyph `+` upload — flat tanpa wadah, 32px stroke 2.6 supaya presence-nya
/// setara tombol create IG/TikTok. Icons.add_rounded 28 terlalu kurus di
/// atas video (weight glyph material tidak bisa ditebalkan).
class _FeedPlusGlyph extends StatelessWidget {
  const _FeedPlusGlyph();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 32,
      width: 32,
      child: CustomPaint(painter: _PlusGlyphPainter()),
    );
  }
}

class _PlusGlyphPainter extends CustomPainter {
  const _PlusGlyphPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * 0.5, size.height * 0.16)
      ..lineTo(size.width * 0.5, size.height * 0.84)
      ..moveTo(size.width * 0.16, size.height * 0.5)
      ..lineTo(size.width * 0.84, size.height * 0.5);
    final shadowPaint = Paint()
      ..color = _feedActionShadowColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.8);
    final paint = Paint()
      ..color = _feedActionForegroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path.shift(const Offset(0, 1.2)), shadowPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Helper skeleton circle (untuk action rail icons).
class _SkeletonCircle extends StatelessWidget {
  final double size;
  const _SkeletonCircle({required this.size});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(height: 6),
        // Count label placeholder bawah icon.
        Container(
          width: 22,
          height: 8,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }
}

/// Helper skeleton bar (untuk text placeholders).
class _SkeletonBar extends StatelessWidget {
  final double width;
  final double height;
  final double radius;

  const _SkeletonBar({
    required this.width,
    required this.height,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 72,
              width: 72,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.play_circle_outline_rounded,
                color: Colors.white60,
                size: 36,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Belum ada konten di Feed',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: NataloWeight.strong,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Konten video Natalo akan tampil di sini.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: NataloWeight.body,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Gap #9 — feed error state dengan retry button.
/// Tampil ketika fetchPublicFeed throw + tidak ada cached posts.
class _FeedErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _FeedErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 72,
              width: 72,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.wifi_off_rounded,
                color: Colors.white60,
                size: 36,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Feed tidak bisa dimuat',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: NataloWeight.strong,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: NataloWeight.body,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () {
                AppHaptics.tap();
                onRetry();
              },
              icon: const Icon(Icons.refresh_rounded, color: Colors.white),
              label: const Text(
                'Coba lagi',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: NataloWeight.strong,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white54),
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// PHOTO_CAROUSEL post view — render 1-8 foto pakai PageView horizontal +
/// dots indicator + heart burst + action rail. Reuse helper components
/// (FeedActionRail, FeedPostCreatorIdentity, FeedExpandableCaption)
/// dari FeedVideoPostView via lokasi sama-file.
///
/// Beda dari FeedVideoPostView:
///   - Tidak ada VideoPlayerController (foto static, no playback state)
///   - Tidak ada progress bar (no duration)
///   - Tidak ada autoplay logic
///   - Tambah dots indicator + horizontal PageView swipe antar foto
class _PhotoCarouselPostView extends StatefulWidget {
  final FeedPost post;
  final bool isActive;
  final ValueChanged<bool> onOverlayStateChanged;
  final ValueChanged<bool> onMediaZoomChanged;

  const _PhotoCarouselPostView({
    super.key,
    required this.post,
    required this.isActive,
    required this.onOverlayStateChanged,
    required this.onMediaZoomChanged,
  });

  @override
  State<_PhotoCarouselPostView> createState() => _PhotoCarouselPostViewState();
}

class _PhotoCarouselPostViewState extends State<_PhotoCarouselPostView>
    with SingleTickerProviderStateMixin {
  late final PageController _photoPageController;
  int _photoIndex = 0;
  bool _liked = false;
  bool _saved = false;
  int _likeCount = 0;
  int _commentCount = 0;
  int _shareCount = 0;
  bool _shareInFlight = false;
  bool _commentDrawerOpen = false;

  /// True selama animasi close yang dipicu Android back berjalan (flag
  /// [_commentDrawerOpen] sudah false tapi surface masih hidup). Menjaga
  /// back ownership selama fase itu — paritas dengan video yang memakai
  /// phase `closing` (_commentDrawerMounted tetap true saat closing).
  bool _commentDrawerClosing = false;

  /// Lease lock overlay Feed — dilepas HANYA lewat
  /// [_releaseCommentOverlayLock] supaya rail/chrome/nav/paging selalu pulih
  /// tepat sekali, apa pun jalur close-nya.
  bool _commentOverlayLockHeld = false;
  bool _androidBackCommentCloserRegistered = false;
  late final VoidCallback _androidBackCommentCloserCallback =
      _androidBackCommentCloser;
  bool _hideOverlayForLongPress = false;
  bool _hideOverlayForPinchZoom = false;

  // Panel caption ala IG (paritas FeedVideoPostView): scrim gelap naik +
  // chip produk fade menghilang saat caption dibuka.
  bool _captionExpanded = false;

  void _setCaptionExpanded(bool value) {
    if (_captionExpanded == value || !mounted) return;
    setState(() => _captionExpanded = value);
  }

  // Heart burst (sama dengan FeedVideoPostView) — posisi mengikuti double tap.
  late final AnimationController _heartBurstController;
  late final Animation<double> _heartScale;
  late final Animation<double> _heartOpacity;
  late final Animation<double> _heartTravel;
  Offset? _heartBurstPosition;
  // Target "terbang ke rail" — pusat tombol like, di-capture saat gesture.
  Offset? _heartBurstTarget;
  final GlobalKey _likeButtonKey = GlobalKey();

  // Product chip rotation — sama pattern dengan FeedVideoPostView untuk video.
  // Tagged products di PHOTO_CAROUSEL/COMMUNITY post juga butuh chip
  // produk di atas nama user. Multi-product → rotate per 2.5 detik.
  int _featuredProductIndex = 0;
  Timer? _productRotationTimer;

  @override
  void initState() {
    super.initState();
    _photoPageController = PageController();
    // Seed store dengan post saat ini supaya feedStore.get always returns
    // non-null. Idempotent — kalau store sudah punya, NoOp.
    feedStore.seed([widget.post]);
    _syncFromStore();
    // Subscribe untuk sync state lintas screen — kalau Detail screen
    // toggle like atau add comment, listener ini fire & local mirror ikut.
    feedStore.addListener(_onFeedStoreChanged);

    _heartBurstController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );
    _heartScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.35, end: 1.42)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 34,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.42, end: 1.00)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 22,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.00, end: 0.82)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 18,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.82, end: 0.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 26,
      ),
    ]).animate(_heartBurstController);
    _heartOpacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 25,
      ),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 38),
      TweenSequenceItem(
        tween:
            Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeIn)),
        weight: 37,
      ),
    ]).animate(_heartBurstController);
    // Terbang ke rail: mulai setelah pop (0.5) lalu melesat easeIn.
    _heartTravel = CurvedAnimation(
      parent: _heartBurstController,
      curve: const Interval(0.5, 1.0, curve: Curves.easeInCubic),
    );

    // Pre-cache thumbnail foto pertama supaya muncul instan.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final m in widget.post.mediaItems.take(3)) {
        precacheImage(CachedNetworkImageProvider(m.mediaUrl), context);
      }
    });

    _syncProductRotation();
  }

  @override
  void didUpdateWidget(covariant _PhotoCarouselPostView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-sync rotation kalau post berubah (PageView ke post lain) atau
    // tagged products length berubah (admin edit tag dari background).
    if (oldWidget.post.id != widget.post.id ||
        oldWidget.post.taggedProducts.length !=
            widget.post.taggedProducts.length) {
      _featuredProductIndex = 0;
      _syncProductRotation();
    } else if (oldWidget.isActive != widget.isActive) {
      // Pause rotation saat post tidak aktif (out of viewport).
      _syncProductRotation();
    }
    // Panel caption ikut tertutup saat swipe ke post lain / ganti post.
    if ((oldWidget.post.id != widget.post.id ||
            (oldWidget.isActive && !widget.isActive)) &&
        _captionExpanded) {
      _captionExpanded = false;
    }
  }

  @override
  void deactivate() {
    // View keluar dari tree (swipe post lain / pindah tab) selagi drawer
    // aktif: lepas back closer + lock overlay sekarang — surface ikut
    // ter-unmount sehingga onClosed tidak akan pernah datang. Tanpa ini
    // closer basi menelan back press tab lain dan Feed terkunci selamanya.
    // Flag di-reset langsung (tanpa setState — ilegal saat deactivate)
    // supaya reactivate membangun ulang dari keadaan closed yang konsisten.
    _commentDrawerOpen = false;
    _commentDrawerClosing = false;
    _unregisterAndroidBackCommentCloser();
    _releaseCommentOverlayLock(defer: true);
    super.deactivate();
  }

  @override
  void dispose() {
    feedStore.removeListener(_onFeedStoreChanged);
    _stopProductRotation();
    _photoPageController.dispose();
    _heartBurstController.dispose();
    super.dispose();
  }

  /// Read latest state dari shared FeedStore, fallback ke widget.post.
  /// Dipanggil di initState + setiap notifyListeners dari store.
  void _syncFromStore() {
    final storePost = feedStore.get(widget.post.id);
    final fresh = storePost ?? widget.post;
    _liked = fresh.viewerLiked ||
        fresh.isLiked ||
        (storePost == null && feedLocalStore.isLiked(widget.post.id));
    _saved = fresh.viewerSaved;
    _likeCount = fresh.likeCount;
    _commentCount = fresh.commentCount;
    _shareCount = fresh.shareCount;
  }

  void _onFeedStoreChanged() {
    if (!mounted) return;
    final fresh = feedStore.get(widget.post.id);
    if (fresh == null) return;
    final newLiked = fresh.viewerLiked || fresh.isLiked;
    if (newLiked == _liked &&
        fresh.viewerSaved == _saved &&
        fresh.likeCount == _likeCount &&
        fresh.commentCount == _commentCount &&
        fresh.shareCount == _shareCount) {
      return;
    }
    setState(() {
      _liked = newLiked;
      _saved = fresh.viewerSaved;
      _likeCount = fresh.likeCount;
      _commentCount = fresh.commentCount;
      _shareCount = fresh.shareCount;
    });
  }

  // ─── Product chip rotation ──────────────────────────────────────────
  // Max products per post:
  //   - Admin    → 5 (lebih banyak slot untuk produk recommendation)
  //   - Customer → 3 (community post tag terbatas supaya tidak spammy)
  List<FeedProductLink> _rotatingProductsForPost(FeedPost post) {
    final maxProducts = post.author.isAdmin ? 5 : 3;
    return post.taggedProducts.take(maxProducts).toList();
  }

  void _syncProductRotation() {
    _stopProductRotation();
    final products = _rotatingProductsForPost(widget.post);
    if (!widget.isActive || products.length <= 1) return;
    _productRotationTimer = Timer.periodic(
      const Duration(milliseconds: 2500),
      (_) {
        if (!mounted || !widget.isActive) return;
        setState(() {
          _featuredProductIndex = (_featuredProductIndex + 1) % products.length;
        });
      },
    );
  }

  void _stopProductRotation() {
    _productRotationTimer?.cancel();
    _productRotationTimer = null;
  }

  Future<void> _onLikePressed() async {
    // TANPA busy-guard — tiap tap langsung diteruskan ke store yang flip
    // UI optimistis instan + coalesce request (intent terakhir menang).
    // Dulu guard di sini menelan tap selama request jalan → unlike harus
    // ditekan berkali-kali di jaringan lambat.
    AppHaptics.impact();
    try {
      final result = await feedStore.toggleLike(widget.post.id);
      feedLocalStore.setLiked(widget.post.id, result.liked);
    } on FeedViewerChangedException {
      // Ignore stale completion from the previous authenticated viewer.
    } catch (error) {
      if (!mounted) return;
      if (error is ApiException && error.statusCode == 401) {
        if (memberStore.isLoggedIn) {
          await memberStore.logout();
        }
        if (!mounted) return;
        Navigator.pushNamed(context, '/member/login');
      } else {
        AppToast.show(
          context,
          error is ApiException && error.statusCode == 404
              ? 'Postingan tidak tersedia.'
              : 'Like belum tersimpan. Coba lagi.',
          kind: ToastKind.warning,
        );
      }
    }
  }

  Future<void> _onSavePressed() async {
    AppHaptics.tap();
    try {
      await feedStore.toggleSaved(widget.post.id);
    } on FeedViewerChangedException {
      // The new viewer owns the rebased saved state.
    } catch (error) {
      if (!mounted) return;
      if (error is ApiException && error.statusCode == 401) {
        if (memberStore.isLoggedIn) await memberStore.logout();
        if (!mounted) return;
        Navigator.pushNamed(context, '/member/login');
        return;
      }
      AppToast.show(
        context,
        error is ApiException && error.statusCode == 404
            ? 'Postingan tidak tersedia.'
            : 'Postingan belum bisa disimpan. Coba lagi.',
        kind: ToastKind.warning,
      );
    }
  }

  void _rememberHeartBurstPosition(TapDownDetails details) {
    _heartBurstPosition = details.localPosition;
  }

  /// Pusat tombol like rail dalam koordinat ~global (Stack mengisi layar
  /// dari 0,0), untuk target "terbang ke rail". Null kalau belum ter-render.
  Offset? _resolveLikeCenter() {
    final box = _likeButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(box.size.center(Offset.zero));
  }

  void _onDoubleTapLike() {
    AppHaptics.impact();
    if (!_liked) {
      _onLikePressed();
    }
    _heartBurstTarget = _resolveLikeCenter();
    _heartBurstController.forward(from: 0);
  }

  Future<void> _onComment() async {
    if (_commentDrawerOpen) return;
    AppHaptics.tap();
    FocusScope.of(context).unfocus();
    _acquireCommentOverlayLock();
    // Android back ownership — paritas dengan adapter video: back menutup
    // drawer DULU, bukan pindah tab / double-back exit.
    _registerAndroidBackCommentCloser();
    if (mounted) setState(() => _commentDrawerOpen = true);
  }

  /// SEMUA jalur close (handle, backdrop, guard terminal, Android back)
  /// berakhir di sini via [FeedReelsCommentSurface.onClosed]. Lock overlay
  /// dilepas berdasarkan lease terpisah — BUKAN flag [_commentDrawerOpen] —
  /// supaya close yang diminta parent (back press men-set flag false lebih
  /// dulu) tetap melepaskan lock saat surface selesai menutup.
  void _onEmbeddedCommentClosed() {
    _commentDrawerClosing = false;
    _unregisterAndroidBackCommentCloser();
    if (mounted && _commentDrawerOpen) {
      setState(() => _commentDrawerOpen = false);
    }
    _releaseCommentOverlayLock();
  }

  void _acquireCommentOverlayLock() {
    if (_commentOverlayLockHeld) return;
    _commentOverlayLockHeld = true;
    widget.onOverlayStateChanged(true);
  }

  void _releaseCommentOverlayLock({bool defer = false}) {
    if (!_commentOverlayLockHeld) return;
    _commentOverlayLockHeld = false;
    if (!defer) {
      widget.onOverlayStateChanged(false);
      return;
    }
    // Deactivate/dispose: parent tidak boleh setState di tengah teardown
    // subtree — tunda ke microtask (pola yang sama dengan adapter video).
    scheduleMicrotask(() {
      if (_commentOverlayLockHeld) return;
      widget.onOverlayStateChanged(false);
    });
  }

  void _registerAndroidBackCommentCloser() {
    if (_androidBackCommentCloserRegistered) return;
    pushAndroidBackOverlayCloser(_androidBackCommentCloserCallback);
    _androidBackCommentCloserRegistered = true;
  }

  void _unregisterAndroidBackCommentCloser() {
    if (!_androidBackCommentCloserRegistered) return;
    _androidBackCommentCloserRegistered = false;
    popAndroidBackOverlayCloser(_androidBackCommentCloserCallback);
  }

  void _androidBackCommentCloser() {
    // consumeAndroidBackOverlay melepas closer sebelum memanggilnya. Daftar
    // ulang segera supaya back press kedua selama animasi close tetap
    // dikonsumsi drawer ini (sebagai no-op), bukan jatuh ke tab nav di
    // bawahnya — persis perilaku video (_commentDrawerMounted true saat
    // closing). _commentDrawerClosing menjaga jendela animasi close saat
    // _commentDrawerOpen sudah false.
    _androidBackCommentCloserRegistered = false;
    if (!_commentDrawerOpen && !_commentDrawerClosing) return;
    _registerAndroidBackCommentCloser();
    if (!_commentDrawerOpen) return; // sedang closing — back kedua = no-op
    _commentDrawerClosing = true;
    // Flag open false men-drive FeedReelsCommentSurface menutup (prop open);
    // lock overlay TETAP dipegang sampai onClosed → _onEmbeddedCommentClosed.
    if (mounted) setState(() => _commentDrawerOpen = false);
  }

  Future<void> _onShare() async {
    if (_shareInFlight) return;
    _shareInFlight = true;
    AppHaptics.tap();
    try {
      final url = ApiConfig.uri('/feed/${widget.post.id}').toString();
      final result = await Share.share(
        widget.post.title.isNotEmpty ? '${widget.post.title}\n$url' : url,
      );
      if (result.status != ShareResultStatus.success || !mounted) return;
      feedStore.incrementShareCount(widget.post.id);
      final serverCount = await feedService.trackShare(widget.post.id);
      if (serverCount != null) {
        feedStore.setShareCount(widget.post.id, serverCount);
      }
    } catch (_) {
      // Cancel atau share fail — silent.
    } finally {
      _shareInFlight = false;
    }
  }

  // ─── Product chip handlers ──────────────────────────────────────────
  // Reuse pattern dari FeedVideoPostView. Tap chip → kalau 1 produk, langsung
  // open product sheet. Multi-produk → buka carousel sheet (Shop the Look).
  // Quick-add → direct cart add (skip variant picker kalau hasVariants).

  Future<void> _openProductLinksSheet(List<FeedProductLink> products) async {
    if (products.isEmpty) return;
    AppHaptics.tap();
    await showFeedProductLinksSheet(
      context,
      products: products,
      onOpenProduct: (link) => _openProductLinkDetail(link),
      onAddToCart: (link) => _addFeedLinkToCart(link),
      onOpened: () => widget.onOverlayStateChanged(true),
      onClosed: () => widget.onOverlayStateChanged(false),
    );
  }

  Future<void> _openProductLinkDetail(FeedProductLink link) async {
    final product = await productService.fetchProductBySlug(link.slug);
    if (!mounted) return;
    if (product == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Produk tidak ditemukan.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    _openProductDetail(product);
  }

  void _openProductDetail(Product product) {
    AppHaptics.tap();
    Navigator.pushNamed(context, '/product-detail', arguments: product);
  }

  void _addFeedLinkToCart(FeedProductLink link, {int quantity = 1}) {
    if (!link.isAvailable || link.stock <= 0) {
      _showProductUnavailable();
      return;
    }
    if (link.hasVariants) {
      _openProductLinkDetail(link);
      return;
    }
    final product = feedPostProductFromFeedLink(link);
    cartStore.addProduct(product, quantity: quantity);
    if (!mounted) return;
    AppToast.showCartAdded(
      context,
      quantity > 1
          ? '$quantity x ${link.name} masuk keranjang'
          : '${link.name} masuk keranjang',
    );
  }

  void _showProductUnavailable() {
    AppToast.show(
      context,
      'Produk sedang tidak tersedia.',
      kind: ToastKind.warning,
    );
  }

  void _onLongPressStart(LongPressStartDetails _) {
    AppHaptics.selection();
    setState(() => _hideOverlayForLongPress = true);
  }

  void _onLongPressEnd(LongPressEndDetails _) {
    setState(() => _hideOverlayForLongPress = false);
  }

  void _onMediaZoomChanged(bool zooming) {
    if (!mounted || _hideOverlayForPinchZoom == zooming) return;
    setState(() => _hideOverlayForPinchZoom = zooming);
    widget.onMediaZoomChanged(zooming);
  }

  Future<void> _showMoreActionsSheet() async {
    AppHaptics.tap();
    final result = await showModerationActions(
      context,
      targetKind: ReportTargetKind.feedPost,
      targetId: widget.post.id,
      authorId: widget.post.author.id,
      authorName: widget.post.author.isOfficialAccount
          ? null
          : widget.post.author.displayName,
      useFeedStyle: true,
    );
    if (result == null || !mounted) return;
    // FeedScreen listen blockService.notifyListeners → auto-refresh
    // visible filter kalau result.didBlock. Tidak perlu manual reload.
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final photos = post.mediaItems;
    // MediaQuery.padding.bottom SUDAH mencakup tinggi nav (extendBody) —
    // lihat feedPostOverlayBaseInset. Jangan tambah kFloatingNavClearance.
    final navClearance = feedPostOverlayBaseInset(context);
    // Gunakan pasangan anchor yang sama dengan video post. Rail sengaja 12dp
    // lebih rendah dari caption agar action terbawah sejajar metadata bawah.
    final actionRailInset = navClearance + feedPostActionRailBottomGap;
    final feedInfoInset = navClearance + feedPostOverlayBottomGap;

    // Product chip — same rotation pattern dengan video post.
    final products = _rotatingProductsForPost(post);

    return VisibilityDetector(
      key: ValueKey('photo-post-${post.id}'),
      onVisibilityChanged: (info) {
        if (!mounted) return;
        if (info.visibleFraction > 0.5 &&
            widget.isActive &&
            !feedLocalStore.hasViewedThisSession(post.id)) {
          feedLocalStore.markViewedThisSession(post.id);
          feedService.trackView(post.id);
        }
      },
      child: FeedReelsCommentSurface(
        post: post,
        open: _commentDrawerOpen,
        onClosed: _onEmbeddedCommentClosed,
        overlay: Stack(
          fit: StackFit.expand,
          children: [
            // Heart burst double-tap — muncul di titik jari, MERAH, lalu
            // terbang mengecil ke tombol like rail (target di-capture saat
            // gesture; null → fade di tempat).
            IgnorePointer(
              child: AnimatedBuilder(
                animation: _heartBurstController,
                builder: (context, _) => feedPostBuildFlyingBurstHeart(
                  tap: _heartBurstPosition,
                  target: _heartBurstTarget,
                  scale: _heartScale.value,
                  opacity: _heartOpacity.value,
                  travel: _heartTravel.value,
                  screenSize: MediaQuery.sizeOf(context),
                ),
              ),
            ),
            // ── Scrim panel caption (mode baca ala IG) — paritas dengan
            // FeedVideoPostView: gradien gelap naik saat caption expand,
            // tap area mana pun menutup panel; tembus saat tertutup. ──
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !_captionExpanded,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _setCaptionExpanded(false),
                  // Klaim drag vertikal supaya PageView feed tidak pindah
                  // post saat user menarik di area scrim (mode baca modal).
                  onVerticalDragStart: (_) {},
                  onVerticalDragUpdate: (_) {},
                  child: AnimatedOpacity(
                    opacity: _captionExpanded ? 1 : 0,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.30),
                            Colors.black.withValues(alpha: 0.66),
                            Colors.black.withValues(alpha: 0.72),
                          ],
                          stops: const [0.18, 0.40, 0.72, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Dots indicator (kalau >1 foto) — tengah atas, Instagram-style
            // pill background semi-transparent. Active dot widen ke 16px.
            if (photos.length > 1 &&
                !_hideOverlayForLongPress &&
                !_hideOverlayForPinchZoom)
              Positioned(
                top: MediaQuery.paddingOf(context).top + 12,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(photos.length, (i) {
                        final active = i == _photoIndex;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          width: active ? 16 : 4,
                          height: 4,
                          decoration: BoxDecoration(
                            color: active
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              ),
            // Right action rail — sama pattern dengan FeedVideoPostView:
            // Like / Comment / Share / More (Report/Block).
            Positioned(
              right: feedPostActionRailRightInset,
              bottom: actionRailInset,
              child: AnimatedOpacity(
                opacity: (_hideOverlayForLongPress || _hideOverlayForPinchZoom)
                    ? 0
                    : 1,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring:
                      _hideOverlayForLongPress || _hideOverlayForPinchZoom,
                  // Cart di rail DIHAPUS — duplikat dengan cart kanan-atas
                  // (satu-satunya pintu keranjang di feed).
                  child: FeedActionRail(
                    likeKey: _likeButtonKey,
                    likeCount: _likeCount,
                    liked: _liked,
                    commentCount: _commentCount,
                    shareCount: _shareCount,
                    saved: _saved,
                    onLike: _onLikePressed,
                    onComment: _onComment,
                    onShare: _onShare,
                    onSave: _onSavePressed,
                    onMore: () => _showMoreActionsSheet(),
                  ),
                ),
              ),
            ),
            // Bottom info: product tag + creator + caption.
            Positioned(
              left: 16,
              right: 78,
              bottom: feedInfoInset,
              child: AnimatedOpacity(
                opacity: (_hideOverlayForLongPress || _hideOverlayForPinchZoom)
                    ? 0
                    : 1,
                duration: const Duration(milliseconds: 150),
                child: IgnorePointer(
                  ignoring:
                      _hideOverlayForLongPress || _hideOverlayForPinchZoom,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Product chip — only when post has tagged products.
                      // Reuse widget yang sama dengan FeedVideoPostView untuk
                      // consistency visual antar video post & photo carousel.
                      // Saat caption expand: chip "tenggelam" (fade + turun +
                      // tinggi mengempis) — paritas video post.
                      if (products.isNotEmpty)
                        ClipRect(
                          child: AnimatedAlign(
                            alignment: Alignment.bottomLeft,
                            heightFactor: _captionExpanded ? 0 : 1,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutCubic,
                            child: AnimatedSlide(
                              offset: _captionExpanded
                                  ? const Offset(0, 0.12)
                                  : Offset.zero,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOutCubic,
                              child: AnimatedOpacity(
                                opacity: _captionExpanded ? 0 : 1,
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOut,
                                child: IgnorePointer(
                                  ignoring: _captionExpanded,
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 9),
                                    child: feedProductPillFor(
                                      products,
                                      _featuredProductIndex,
                                      onTap: () =>
                                          _openProductLinksSheet(products),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      FeedPostCreatorIdentity(
                        author: post.author,
                        displayName: post.author.displayHandle,
                      ),
                      const SizedBox(height: 7),
                      FeedExpandableCaption(
                        text: post.caption ?? '',
                        createdAt: post.createdAt,
                        expanded: _captionExpanded,
                        onExpandedChanged: _setCaptionExpanded,
                        onMentionTap: (handle) => Navigator.of(context)
                            .pushNamed('/u', arguments: handle),
                      ),
                      FeedPostSocialProof(post: post),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        child: ColoredBox(
          color: Colors.black,
          // Media-only child. Feed chrome lives in [overlay] so the drawer
          // can compact the photo without squeezing captions/actions into it.
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTapDown: _rememberHeartBurstPosition,
            onDoubleTap: _onDoubleTapLike,
            onLongPressStart: _onLongPressStart,
            onLongPressEnd: _onLongPressEnd,
            child: PageView.builder(
              controller: _photoPageController,
              itemCount: photos.length,
              onPageChanged: (idx) => setState(() => _photoIndex = idx),
              itemBuilder: (context, index) {
                final photo = photos[index];
                // Pinch-zoom sementara: begitu gesture selesai, foto
                // snap back ke ukuran asli supaya feed tidak nyangkut
                // dalam state zoom.
                return SizedBox.expand(
                  child: FeedPostSnapBackZoomMedia(
                    clipBehavior: Clip.none,
                    minScale: 1,
                    maxScale: 4,
                    onZoomingChanged: _onMediaZoomChanged,
                    child: CachedNetworkImage(
                      imageUrl: photo.url,
                      fit: BoxFit.contain,
                      placeholder: (_, __) => const SizedBox.shrink(),
                      errorWidget: (_, __, ___) => const Center(
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: Colors.white54,
                          size: 48,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

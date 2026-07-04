import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shimmer/shimmer.dart';
import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../config/api_config.dart';
import '../features/feed/widgets/feed_video_scrubber.dart';
import '../models/cart_item.dart';
import '../models/feed_post.dart';
import '../models/product.dart';
import '../screens/checkout_screen.dart';
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
import '../utils/formatters.dart';
import '../utils/action_throttle.dart';
import '../utils/haptics.dart';
import '../utils/mention_text.dart';
import '../widgets/app_toast.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/feed_comment_sheet.dart';
import '../widgets/feed_upload_sheet.dart';
import '../widgets/moderation_action_sheet.dart';

const _officialGold = Color(0xFFF4D47C);
const _feedBlue = Color(0xFF0B7FEA);
const _feedActionForegroundColor = Color(0xFFFFFFFF);
const _feedActionShadowColor = Color(0x99000000);
const _feedActionTextShadowColor = Color(0xB3000000);
const _feedActionIconSize = 32.0;
const _feedActionStrokeWidth = 2.2;
const _feedActionCountFontSize = 12.0;
const _feedActionItemSpacing = 18.0;
const _feedActionBottomInset = 24.0;
const _feedActionRailRightInset = 4.0;
const _feedTopActionRightInset = 8.0;

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
  // Parallel maps: _preloadedControllers untuk reads (.value, VideoPlayer
  // widget, play/pause). _preloadedCachedPlayers untuk lifecycle (dispose
  // via wrapper supaya cache file di-track properly oleh
  // flutter_cache_manager). Wrapper instances 1:1 dengan controller di
  // map sebelahnya — selalu created bersamaan via CachedVideoPlayerPlus
  // pipeline. Pisah Map supaya existing code yang akses controller tidak
  // perlu di-refactor.
  final Map<String, VideoPlayerController> _preloadedControllers = {};
  final Map<String, CachedVideoPlayerPlus> _preloadedCachedPlayers = {};
  List<FeedPost> _posts = const [];
  String? _nextCursor;
  bool _loading = true;
  bool _loadingMore = false;
  bool _interactionLocked = false;
  bool _mediaZooming = false;
  int _activeIndex = 0;
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
    cartStore.removeListener(_syncTopCartCount);
    blockService.removeListener(_onBlocklistChanged);
    // Prefer dispose via wrapper — handles both underlying controller +
    // cache file reference. Sisa controllers tanpa wrapper (shouldn't
    // happen di prod tapi defensive) di-dispose langsung.
    for (final player in _preloadedCachedPlayers.values) {
      player.dispose();
    }
    for (final id in _preloadedControllers.keys.toList()) {
      if (!_preloadedCachedPlayers.containsKey(id)) {
        _preloadedControllers[id]?.dispose();
      }
    }
    _preloadedCachedPlayers.clear();
    _preloadedControllers.clear();
    _pageController.dispose();
    super.dispose();
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

  bool get _shouldPreloadNext {
    return appSettingsStore.feedAutoplay &&
        appSettingsStore.feedVideoQuality != 'data_saver';
  }

  /// Sliding window 4-item — keep prev, current, next, next+1 controllers
  /// hidup di RAM. Sesuai Reels/TikTok spec: swipe forward smooth dua kali
  /// berturut-turut tanpa loading spinner.
  ///
  /// State per slot setelah pre-init:
  ///   - prev (i-1):    paused, seek 0, prepared. Attached saat user
  ///                    swipe back → instant play tanpa loading spinner.
  ///   - current (i):   widget _FeedPostView manage sendiri (play loop).
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
    final keepIds = <String>{};
    for (final offset in const [-1, 0, 1, 2]) {
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
    final staleIds = _preloadedControllers.keys
        .where((id) => !keepIds.contains(id))
        .toList();
    for (final id in staleIds) {
      final cachedPlayer = _preloadedCachedPlayers.remove(id);
      _preloadedControllers.remove(id);
      if (cachedPlayer != null) {
        await cachedPlayer.dispose();
      }
    }

    if (!_shouldPreloadNext) return;

    // Pre-init controllers yang masih dalam window tapi belum ada.
    // Paralel init (Future.wait) supaya prev + next siap bersamaan.
    final activePost = activeIndex >= 0 && activeIndex < visible.length
        ? visible[activeIndex]
        : null;
    final initFutures = <Future<void>>[];

    for (final id in keepIds) {
      // Skip current — widget _FeedPostView create sendiri di-mount.
      if (activePost != null && id == activePost.id) continue;
      if (_preloadedControllers.containsKey(id)) continue;

      FeedPost? post;
      for (final p in _posts) {
        if (p.id == id) {
          post = p;
          break;
        }
      }
      if (post == null) continue;
      final url = post.videoUrl;
      if (url.isEmpty) continue;

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
      final resolvedUrl = videoQualityService.resolvePlaybackUrl(
        url,
        userPreference: appSettingsStore.feedVideoQuality,
      );

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
      if (isHls) {
        final controller = VideoPlayerController.networkUrl(
          Uri.parse(resolvedUrl),
        );
        _preloadedControllers[id] = controller;
        initFutures.add(
          controller.initialize().then((_) async {
            await controller.setLooping(true);
            await controller.setVolume(0);
            await controller.seekTo(Duration.zero);
          }).catchError((Object _) async {
            _preloadedControllers.remove(id);
            await controller.dispose();
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
      );
      _preloadedCachedPlayers[id] = cachedPlayer;
      initFutures.add(
        cachedPlayer.initialize().then((_) async {
          final controller = cachedPlayer.controller;
          _preloadedControllers[id] = controller;
          // Prepared state: paused, frame 0 ready, muted, looping prepped.
          // Saat widget attach via preloadedController prop, tinggal play()
          // — instant, no init lag.
          await controller.setLooping(true);
          await controller.setVolume(0);
          await controller.seekTo(Duration.zero);
        }).catchError((Object _) async {
          // Init gagal — kemungkinan besar disk cache corrupt (force-kill
          // mid-write left partial file). Invalidate cache entry supaya
          // attempt berikutnya (e.g. preload pass berikutnya, atau saat
          // user scroll ke post ini dan _maybeInitVideo run) bisa fresh-
          // fetch dari network. Tanpa ini, cache wrapper tetap baca file
          // corrupt setiap retry.
          final p = _preloadedCachedPlayers.remove(id);
          _preloadedControllers.remove(id);
          if (p != null) {
            try {
              await p.dispose();
            } catch (_) {}
          }
          try {
            await DefaultCacheManager().removeFile(resolvedUrl);
          } catch (_) {}
        }),
      );
    }
    await Future.wait(initFutures);
  }

  /// Backward-compat alias — internal callers (_loadInitial,
  /// _onPageChanged) tetap pakai nama _preloadNext. Forward ke
  /// _managePreloadWindow yang handle 3-item sliding window.
  Future<void> _preloadNext(int index) => _managePreloadWindow(index);

  void _setFeedInteractionLocked(bool locked) {
    if (!mounted || _interactionLocked == locked) return;
    setState(() => _interactionLocked = locked);
  }

  void _setFeedMediaZooming(bool zooming) {
    if (!mounted || _mediaZooming == zooming) return;
    setState(() => _mediaZooming = zooming);
  }

  Future<void> _onUpload() async {
    AppHaptics.tap();
    _setFeedInteractionLocked(true);
    // Unified "Postingan baru" flow — push FeedMediaPickerScreen via
    // FeedUploadSheet.show() yang juga dipakai oleh member_screen dan
    // member_posts_screen. Picker IG-style (preview + gallery grid)
    // handle photo + video di satu screen, lalu push FeedNewPostScreen
    // untuk caption + product tag + submit.
    //
    // Sebelumnya feed_screen pakai _UploadChoiceSheet (split video/photo
    // dulu) → flow lama yang inkonsisten dengan akun entry. Sekarang
    // SEMUA "+" icon (feed + akun + postingan saya) lead ke flow yang
    // sama untuk konsistensi UX.
    await FeedUploadSheet.show(context);
    if (mounted) _setFeedInteractionLocked(false);
    if (!mounted) return;
    await _loadInitial();
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
                      // _FeedPostView dengan VideoPlayerController.
                      if (post.isPhotoCarousel) {
                        return _PhotoCarouselPostView(
                          post: post,
                          isActive: index == _activeIndex,
                          onOverlayStateChanged: _setFeedInteractionLocked,
                          onMediaZoomChanged: _setFeedMediaZooming,
                        );
                      }
                      return _FeedPostView(
                        post: post,
                        isActive: index == _activeIndex,
                        preloadedController:
                            _preloadedControllers.remove(post.id),
                        // Pass wrapper juga — child butuh wrapper untuk
                        // dispose proper (release cache reference).
                        preloadedCachedPlayer:
                            _preloadedCachedPlayers.remove(post.id),
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
            // dengan notch / status bar di iOS+Android. Hide saat interaction
            // locked (comment drawer / cinema mode) supaya tidak distract.
            if (!_interactionLocked)
              AnimatedOpacity(
                opacity: _mediaZooming ? 0 : 1,
                duration: const Duration(milliseconds: 160),
                child: IgnorePointer(
                  ignoring: _mediaZooming,
                  child: Stack(
                    children: [
                      Positioned(
                        top: MediaQuery.paddingOf(context).top + 8,
                        left: 4,
                        child: _FeedTopIconButton(
                          icon: Icons.add_rounded,
                          onTap: _onUpload,
                          tooltip: 'Upload video',
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
        child: _interactionLocked
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
    final mediaQuery = MediaQuery.of(context);
    // extendBody: true → tambah kFloatingNavClearance supaya shimmer
    // placeholder action rail tidak tertutup floating nav.
    final actionRailInset =
        _feedActionBottomInset + mediaQuery.padding.bottom + kFloatingNavClearance;
    final feedInfoInset = mediaQuery.padding.bottom + 100;

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
            right: _feedActionRailRightInset,
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
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final int? badgeCount;

  const _FeedTopIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.badgeCount,
  });

  @override
  Widget build(BuildContext context) {
    final iconWidget = Stack(
      clipBehavior: Clip.none,
      children: [
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
                  fontWeight: FontWeight.w900,
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
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Konten video Natalo akan tampil di sini.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w600,
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
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w600,
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
                  fontWeight: FontWeight.w900,
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
/// (_ReelsAction, _FeedCreatorIdentity, _ExpandableCaption)
/// dari _FeedPostView via lokasi sama-file.
///
/// Beda dari _FeedPostView:
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
  int _likeCount = 0;
  int _commentCount = 0;
  int _shareCount = 0;
  bool _likeBusy = false;
  bool _captionExpanded = false;
  bool _hideOverlayForLongPress = false;
  bool _hideOverlayForPinchZoom = false;

  // Heart burst (sama dengan _FeedPostView) — posisi mengikuti double tap.
  late final AnimationController _heartBurstController;
  late final Animation<double> _heartScale;
  late final Animation<double> _heartOpacity;
  Offset? _heartBurstPosition;

  // Product chip rotation — sama pattern dengan _FeedPostView untuk video.
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
        fresh.likeCount == _likeCount &&
        fresh.commentCount == _commentCount &&
        fresh.shareCount == _shareCount) {
      return;
    }
    setState(() {
      _liked = newLiked;
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
    if (_likeBusy) return;
    AppHaptics.impact();
    setState(() => _likeBusy = true);
    // Delegate ke FeedStore: optimistic + API + reconcile + rollback +
    // mutex semua di-handle di sana. Listener kita yang propagasi state
    // ke local field via _onFeedStoreChanged → setState.
    try {
      final result = await feedStore.toggleLike(widget.post.id);
      feedLocalStore.setLiked(widget.post.id, result.liked);
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
    } finally {
      if (mounted) setState(() => _likeBusy = false);
    }
  }

  void _rememberHeartBurstPosition(TapDownDetails details) {
    _heartBurstPosition = details.localPosition;
  }

  void _onDoubleTapLike() {
    AppHaptics.impact();
    if (!_liked) {
      _onLikePressed();
    }
    _heartBurstController.forward(from: 0);
  }

  void _onComment() {
    AppHaptics.tap();
    // TODO: open comment sheet (reuse FeedCommentSheet — sama dengan video).
    // Untuk MVP carousel, buka modal sheet dengan post comments.
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        snap: true,
        // Explicit snap points: tarik ke salah satu dari 3 size. Bukan
        // free-drag. Match Apple Maps / Spotify pattern — bottom sheet
        // selalu terasa "settled" di posisi yang jelas, bukan random
        // height yang berubah-ubah.
        snapSizes: const [0.5, 0.7, 0.95],
        builder: (_, scrollController) => FeedCommentSheet(
          post: widget.post,
          applyKeyboardInset: true,
          sheetScrollController: scrollController,
          onClose: () => Navigator.pop(context),
          onAddedCountChanged: (count) {
            if (!mounted) return;
            // Propagasi ke FeedStore — semua screen lain yang baca count
            // dari store ikut update. Local field di-update otomatis lewat
            // _onFeedStoreChanged listener.
            final base = feedStore.get(widget.post.id)?.commentCount ??
                widget.post.commentCount;
            feedStore.setCommentCount(widget.post.id, base + count);
          },
        ),
      ),
    );
  }

  Future<void> _onShare() async {
    AppHaptics.tap();
    try {
      final url = ApiConfig.uri('/feed/${widget.post.id}').toString();
      await Share.share(
        widget.post.title.isNotEmpty ? '${widget.post.title}\n$url' : url,
      );
      if (!mounted) return;
      setState(() => _shareCount += 1);
      await feedService.trackShare(widget.post.id);
    } catch (_) {
      // Cancel atau share fail — silent.
    }
  }

  // ─── Product chip handlers ──────────────────────────────────────────
  // Reuse pattern dari _FeedPostView. Tap chip → kalau 1 produk, langsung
  // open product sheet. Multi-produk → buka carousel sheet (Shop the Look).
  // Quick-add → direct cart add (skip variant picker kalau hasVariants).

  Future<void> _onProductsTap(List<FeedProductLink> products) async {
    if (products.isEmpty) return;
    if (products.length == 1) {
      await _onProductTap(products.first);
      return;
    }
    AppHaptics.tap();
    widget.onOverlayStateChanged(true);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.18),
      builder: (_) => _FeedTaggedProductsSheet(
        products: products,
        onOpenProduct: (link) async {
          await _onProductTap(link);
        },
        onAdd: (link, quantity) async {
          _addFeedLinkToCart(link, quantity: quantity);
        },
        onBuy: (link, quantity) async {
          _buyFeedLinkNow(link, quantity: quantity);
        },
      ),
    ).whenComplete(() => widget.onOverlayStateChanged(false));
  }

  Future<void> _quickAddProduct(FeedProductLink link) async {
    _addFeedLinkToCart(link);
  }

  Future<void> _onProductTap(FeedProductLink link) async {
    AppHaptics.tap();
    widget.onOverlayStateChanged(true);
    final product = await productService.fetchProductBySlug(link.slug);
    if (!mounted) {
      widget.onOverlayStateChanged(false);
      return;
    }
    if (product == null) {
      widget.onOverlayStateChanged(false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Produk tidak ditemukan.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.18),
      builder: (_) => _FeedProductSheet(
        product: product,
        onOpenProduct: () => _openProductDetail(product),
        onAdd: (quantity) => _addProductToCart(product, quantity: quantity),
        onBuy: (quantity) => _buyProductNow(product, quantity: quantity),
      ),
    ).whenComplete(() => widget.onOverlayStateChanged(false));
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
      _onProductTap(link);
      return;
    }
    final product = _productFromFeedLink(link);
    cartStore.addProduct(product, quantity: quantity);
    if (!mounted) return;
    AppToast.showCartAdded(
      context,
      quantity > 1
          ? '$quantity x ${link.name} masuk keranjang'
          : '${link.name} masuk keranjang',
    );
  }

  void _addProductToCart(Product product, {int quantity = 1}) {
    if (product.stock <= 0) {
      _showProductUnavailable();
      return;
    }
    if (product.hasVariants) {
      _openProductDetail(product);
      return;
    }
    cartStore.addProduct(product, quantity: quantity);
    if (!mounted) return;
    AppToast.showCartAdded(
      context,
      quantity > 1
          ? '$quantity x ${product.title} masuk keranjang'
          : '${product.title} masuk keranjang',
    );
  }

  void _buyFeedLinkNow(FeedProductLink link, {int quantity = 1}) {
    if (!link.isAvailable || link.stock <= 0) {
      _showProductUnavailable();
      return;
    }
    if (link.hasVariants) {
      _onProductTap(link);
      return;
    }
    _buyProductNow(_productFromFeedLink(link), quantity: quantity);
  }

  void _buyProductNow(Product product, {int quantity = 1}) {
    if (product.stock <= 0) {
      _showProductUnavailable();
      return;
    }
    if (product.hasVariants) {
      _openProductDetail(product);
      return;
    }
    AppHaptics.impact();
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CheckoutScreen(
          items: [
            CartItem(
              product: product,
              quantity: quantity.clamp(1, math.max(1, product.stock)),
            ),
          ],
        ),
      ),
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
    // extendBody: true di Scaffold → Stack ini memanjang sampai tepi bawah
    // layar (bukan berhenti di atas nav lagi). kFloatingNavClearance
    // (dari bottom_nav.dart) + safe-area device supaya action rail/caption
    // tidak tertutup floating nav.
    final navClearance =
        MediaQuery.paddingOf(context).bottom + kFloatingNavClearance;
    final actionRailInset = _feedActionBottomInset + navClearance;
    // Foto carousel tidak punya rail durasi, jadi caption dirapatkan langsung
    // ke atas nav (gap kecil) — konsisten "rapat" dengan video, tanpa void.
    final feedInfoInset = navClearance + 12.0;

    // Product chip — same rotation pattern dengan video post.
    final products = _rotatingProductsForPost(post);
    final featuredProduct = products.isEmpty
        ? null
        : products[_featuredProductIndex % products.length];

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
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Backdrop: pure BLACK solid (Instagram-style), bukan blur.
            // Foto tetap utuh (BoxFit.contain centered) — letterbox top+bottom
            // hitam supaya action rail putih konsisten kontras dengan video
            // feed dan content focus jelas. Blur backdrop dipakai sebelumnya
            // bikin icon putih low-contrast saat foto bg putih (mis. foto
            // product di studio).
            // Foto carousel — PageView horizontal swipe.
            GestureDetector(
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
                  return Center(
                    child: _SnapBackZoomMedia(
                      clipBehavior: Clip.none,
                      minScale: 1,
                      maxScale: 4,
                      onZoomingChanged: _onMediaZoomChanged,
                      child: AspectRatio(
                        aspectRatio: _instagramImageAspectRatio(
                          photo.width,
                          photo.height,
                        ),
                        child: CachedNetworkImage(
                          imageUrl: photo.url,
                          fit: BoxFit.cover,
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
                    ),
                  );
                },
              ),
            ),
            // Heart burst overlay (double-tap signature) di titik jari.
            IgnorePointer(
              child: AnimatedBuilder(
                animation: _heartBurstController,
                builder: (context, _) {
                  if (_heartOpacity.value == 0) {
                    return const SizedBox.shrink();
                  }

                  final position = _heartBurstPosition;
                  final progress = _heartBurstController.value;
                  final heart = Opacity(
                    opacity: _heartOpacity.value,
                    child: Transform.translate(
                      offset: Offset(0, -14 * progress),
                      child: Transform.scale(
                        scale: _heartScale.value,
                        child: Transform.rotate(
                          angle: -0.08,
                          child: const Icon(
                            Icons.favorite_rounded,
                            color: Color(0xFFEF4444),
                            size: 128,
                            shadows: [
                              Shadow(color: Colors.black54, blurRadius: 28),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                  if (position == null) {
                    return Center(child: heart);
                  }
                  return Stack(
                    children: [
                      Positioned(
                        left: position.dx - 64,
                        top: position.dy - 64,
                        width: 128,
                        height: 128,
                        child: Center(child: heart),
                      ),
                    ],
                  );
                },
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
            // Right action rail — sama pattern dengan _FeedPostView:
            // Like / Comment / Share / More (Report/Block).
            Positioned(
              right: _feedActionRailRightInset,
              bottom: actionRailInset,
              child: AnimatedOpacity(
                opacity: (_hideOverlayForLongPress || _hideOverlayForPinchZoom)
                    ? 0
                    : 1,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring:
                      _hideOverlayForLongPress || _hideOverlayForPinchZoom,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ReelsAction(
                        iconChild: _ReelsHeartGlyph(liked: _liked),
                        count: _likeCount,
                        onTap: _onLikePressed,
                      ),
                      const SizedBox(height: _feedActionItemSpacing),
                      _ReelsAction(
                        iconChild: const _ReelsCommentGlyph(),
                        count: _commentCount,
                        onTap: _onComment,
                      ),
                      const SizedBox(height: _feedActionItemSpacing),
                      _ReelsAction(
                        iconChild: const _ReelsShareGlyph(),
                        count: _shareCount,
                        onTap: _onShare,
                      ),
                      const SizedBox(height: _feedActionItemSpacing),
                      // More actions (Report/Block) — Google Play UGC policy.
                      _ReelsAction(
                        iconChild: const _ReelsMoreGlyph(),
                        onTap: () => _showMoreActionsSheet(),
                      ),
                    ],
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
                      // Reuse widget yang sama dengan _FeedPostView untuk
                      // consistency visual antar video post & photo carousel.
                      if (products.isNotEmpty) ...[
                        _ProductLinkChip(
                          products: products,
                          featuredProduct: featuredProduct!,
                          featuredIndex:
                              _featuredProductIndex % products.length,
                          onTap: () => _onProductsTap(products),
                          onQuickAdd: () => _quickAddProduct(featuredProduct),
                        ),
                        const SizedBox(height: 9),
                      ],
                      _FeedCreatorIdentity(
                        author: post.author,
                        displayName: post.author.displayHandle,
                      ),
                      const SizedBox(height: 7),
                      _ExpandableCaption(
                        text: post.caption ?? '',
                        expanded: _captionExpanded,
                        onToggle: () => setState(
                            () => _captionExpanded = !_captionExpanded),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Satu fullscreen page Reels-style — video/thumbnail + Reels overlay.
class _FeedPostView extends StatefulWidget {
  final FeedPost post;
  final bool isActive;
  final VideoPlayerController? preloadedController;

  /// Wrapper instance dari CachedVideoPlayerPlus — null kalau controller
  /// adopt dari preload tapi wrapper sudah hilang (rare), atau kalau
  /// child create fresh via _maybeInitVideo. Disimpan supaya dispose
  /// proper handle cache file lifecycle via wrapper.dispose().
  final CachedVideoPlayerPlus? preloadedCachedPlayer;
  final ValueChanged<bool> onOverlayStateChanged;
  final ValueChanged<bool> onMediaZoomChanged;

  const _FeedPostView({
    required this.post,
    required this.isActive,
    required this.preloadedController,
    required this.onOverlayStateChanged,
    required this.onMediaZoomChanged,
    this.preloadedCachedPlayer,
  });

  @override
  State<_FeedPostView> createState() => _FeedPostViewState();
}

class _FeedPostViewState extends State<_FeedPostView>
    with TickerProviderStateMixin {
  static const double _commentSheetMinExtent = 0.22;
  static const double _commentSheetInitialExtent = 0.60;
  static const double _commentSheetMaxExtentCap = 0.82;
  static const double _commentSheetDismissExtent = 0.30;

  VideoPlayerController? _videoController;

  /// Wrapper instance untuk lifecycle network video (disk cache). Null
  /// kalau ga ada wrapper (defensive). Disposed di dispose() lebih dulu
  /// dari _videoController supaya cache file di-release proper. Untuk
  /// adopt-from-parent path: copy dari widget.preloadedCachedPlayer.
  /// Untuk fresh-create path: di-set di _maybeInitVideo.
  CachedVideoPlayerPlus? _cachedPlayer;
  final DraggableScrollableController _commentSheetController =
      DraggableScrollableController();
  final ValueNotifier<double> _commentSheetExtent =
      ValueNotifier<double>(_commentSheetInitialExtent);
  bool _liked = false;
  int _likeCount = 0;
  int _commentCount = 0;
  int _shareCount = 0;
  bool _isPaused = false;
  bool _captionExpanded = false;
  bool _commentDrawerMounted = false;
  bool _commentSheetOpen = false;
  bool _videoLoadFailed = false;
  bool _likeBusy = false;
  bool _commentSheetClosingFromDrag = false;
  int _commentAddedCount = 0;
  int _featuredProductIndex = 0;
  Timer? _productRotationTimer;
  double _commentDragOffset = 0;

  // End-of-video product CTA — slide-in card di 2.5s terakhir tiap loop
  // supaya user yang nonton sampai abis lihat reminder produk dengan tombol
  // "Beli" lebih prominent dari `_ProductLinkChip` yang selalu visible kecil
  // di bawah. Reset tiap loop wrap (position < 500ms), tapi sticky setelah
  // user dismiss (per-session). Skip untuk post tanpa tagged products atau
  // video <3 detik.
  bool _endOfVideoCtaVisible = false;
  bool _endOfVideoCtaDismissed = false;

  // Delayed loading spinner — sebagian besar video load <1s (preloaded
  // controller siap instan, fresh init biasanya 400-900ms). Spinner yang
  // muncul instant bikin user anxiety ("kok lama?"). Delay 800ms supaya
  // kalau video keburu ready, spinner gak pernah muncul = perceived
  // instant. Kalau lewat 800ms baru spinner muncul (genuine slow load,
  // butuh feedback visual).
  Timer? _loadingSpinnerDelay;
  bool _showLoadingSpinner = false;

  // Animation untuk heart burst di tengah saat double-tap.
  late final AnimationController _heartBurstController;
  late final Animation<double> _heartScale;
  late final Animation<double> _heartOpacity;
  Offset? _heartBurstPosition;

  @override
  void initState() {
    super.initState();
    // Seed shared FeedStore + subscribe — single source of truth untuk
    // like/comment sync antar screen. Detail screen yang juga listen ke
    // store akan auto-update kalau user toggle dari sini, dan sebaliknya.
    feedStore.seed([widget.post]);
    feedStore.addListener(_onFeedStoreChanged);
    // Gap #7: initialize _liked dari backend/store + local cache.
    // Kalau FeedStore sudah punya post, store/backend adalah source of
    // truth. Local cache hanya fallback awal agar launch offline tetap
    // terasa instant, dan tidak boleh membuat unlike terbaru tetap merah.
    _liked = widget.post.viewerLiked ||
        widget.post.isLiked ||
        (feedStore.get(widget.post.id) == null &&
            feedLocalStore.isLiked(widget.post.id));
    _likeCount = widget.post.likeCount;
    _commentCount = widget.post.commentCount;
    _shareCount = widget.post.shareCount;

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
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.0),
        weight: 38,
      ),
      TweenSequenceItem(
        tween:
            Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeIn)),
        weight: 37,
      ),
    ]).animate(_heartBurstController);

    _commentSheetController.addListener(_syncCommentSheetProgress);

    _adoptPreloadedController();
    _maybeInitVideo();
    _syncProductRotation();
  }

  bool get _dataSaverEnabled =>
      appSettingsStore.feedVideoQuality == 'data_saver';

  bool get _shouldAutoplay =>
      appSettingsStore.feedAutoplay && !_dataSaverEnabled;

  Future<void> _adoptPreloadedController() async {
    final controller = widget.preloadedController;
    if (controller == null) return;
    _videoController = controller;
    // Adopt wrapper juga supaya child bisa dispose properly. Wrapper
    // might be null (legacy or unwrapped). Either way, controller-level
    // ops tetap work.
    _cachedPlayer = widget.preloadedCachedPlayer;
    controller.addListener(_handleVideoPositionForCta);
    // Preloaded controller selalu sudah initialize() — timer reset di sini
    // cuma untuk kasus defensif (controller mungkin dispose dari luar). Kalau
    // sudah initialized, helper-nya early-return tanpa schedule spinner.
    _resetLoadingSpinnerTimer();
    await controller.setVolume(appSettingsStore.feedMuted ? 0 : 1);
    if (widget.isActive && _shouldAutoplay) {
      await controller.play();
    }
    if (mounted) setState(() {});
  }

  /// Listener position video → toggle end-of-video product CTA visibility.
  /// Dipanggil tiap frame video (puluhan kali/detik). Cepat-keluar untuk
  /// kondisi yang gak perlu re-render supaya gak ngabisin frame budget.
  void _handleVideoPositionForCta() {
    final ctrl = _videoController;
    if (ctrl == null || !mounted) return;
    final value = ctrl.value;
    if (!value.isInitialized) return;

    final durMs = value.duration.inMilliseconds;
    // Skip ultra-short clips (<3s) — gak ada window 2.5s yang masuk akal.
    if (durMs < 3000) return;
    final posMs = value.position.inMilliseconds;

    // Detect loop wrap (position balik ke awal) — reset visibility supaya
    // CTA muncul lagi di loop berikutnya. Dismissed flag tetap di-hormati.
    if (posMs < 500 && _endOfVideoCtaVisible) {
      setState(() => _endOfVideoCtaVisible = false);
      return;
    }

    // Show window: 2.5 detik terakhir, kecuali 50ms terakhir (avoid flicker
    // di loop boundary saat position mau wrap).
    final remainingMs = durMs - posMs;
    final inShowWindow = remainingMs > 50 && remainingMs <= 2500;
    if (inShowWindow && !_endOfVideoCtaVisible && !_endOfVideoCtaDismissed) {
      // Cek post punya tagged product yang valid sebelum trigger setState —
      // hindari render kosong.
      if (_rotatingProductsForPost(widget.post).isEmpty) return;
      setState(() => _endOfVideoCtaVisible = true);
    }
  }

  void _dismissEndOfVideoCta() {
    if (!mounted) return;
    setState(() {
      _endOfVideoCtaVisible = false;
      _endOfVideoCtaDismissed = true;
    });
  }

  /// Reset spinner-delay timer setelah controller di-set atau di-swap. Kalau
  /// controller sudah initialized (preload sukses), spinner tidak diperlukan
  /// sama sekali — early return. Kalau belum, schedule spinner muncul 1200ms
  /// kemudian — kalau initialize keburu selesai sebelum timer fire,
  /// _cancelLoadingSpinnerDelay dipanggil dan spinner tidak pernah render.
  ///
  /// Delay 1200ms (sebelumnya 800ms) — match IG/TikTok pattern. Video load
  /// fast di 4G/WiFi (~500-1000ms), spinner sebelum 1200ms cuma bikin user
  /// anxious padahal video sebentar lagi siap. Kalau load >1.2 detik (4G
  /// marginal / 3G), baru spinner muncul sebagai genuine feedback.
  void _resetLoadingSpinnerTimer() {
    _loadingSpinnerDelay?.cancel();
    _loadingSpinnerDelay = null;
    if (_showLoadingSpinner) {
      _showLoadingSpinner = false;
    }
    final ctrl = _videoController;
    if (ctrl == null || ctrl.value.isInitialized || _videoLoadFailed) return;
    _loadingSpinnerDelay = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      final c = _videoController;
      if (c == null || c.value.isInitialized || _videoLoadFailed) return;
      setState(() => _showLoadingSpinner = true);
    });
  }

  void _cancelLoadingSpinnerDelay() {
    _loadingSpinnerDelay?.cancel();
    _loadingSpinnerDelay = null;
    if (_showLoadingSpinner && mounted) {
      setState(() => _showLoadingSpinner = false);
    }
  }

  @override
  void didUpdateWidget(covariant _FeedPostView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      if (widget.isActive) {
        if (!_isPaused && _shouldAutoplay) {
          _videoController?.play();
        }
        _syncProductRotation();
      } else {
        _isPaused = false;
        _commentDrawerMounted = false;
        _commentSheetOpen = false;
        _commentAddedCount = 0;
        _featuredProductIndex = 0;
        _commentSheetClosingFromDrag = false;
        _commentDragOffset = 0;
        _commentSheetExtent.value = _commentSheetInitialExtent;
        // Reset CTA: user swipe ke post lain → next visit dapat fresh
        // chance (dismissed flag clear, visible flag clear).
        _endOfVideoCtaVisible = false;
        _endOfVideoCtaDismissed = false;
        // Reset long-press state (paused / 2x speed) + scrubber state.
        // Defensive — pastikan video tidak stuck di 2x atau paused saat
        // user swipe ke post lain di tengah long-press.
        _longPressPaused = false;
        _longPressSpeedActive = false;
        _hideOverlayForLongPress = false;
        _hideOverlayForPinchZoom = false;
        _isScrubbing = false;
        widget.onOverlayStateChanged(false);
        widget.onMediaZoomChanged(false);
        _videoController?.pause();
        try {
          _videoController?.setPlaybackSpeed(1.0);
        } catch (_) {}
        _videoController?.seekTo(Duration.zero);
        _stopProductRotation();
      }
    }
    if (oldWidget.post.id != widget.post.id ||
        oldWidget.post.taggedProducts.length !=
            widget.post.taggedProducts.length) {
      _featuredProductIndex = 0;
      _endOfVideoCtaVisible = false;
      _endOfVideoCtaDismissed = false;
      _syncProductRotation();
    }
  }

  Future<void> _maybeInitVideo({bool userInitiated = false}) async {
    if (_videoController != null) return;
    final url = widget.post.videoUrl;
    if (url.isEmpty) return;
    if (_dataSaverEnabled && !userInitiated) return;
    setState(() => _videoLoadFailed = false);
    // Sprint 2 #7 — Network-aware quality rewrite + user preference.
    final resolvedUrl = videoQualityService.resolvePlaybackUrl(
      url,
      userPreference: appSettingsStore.feedVideoQuality,
    );
    final isHls = resolvedUrl.contains('.m3u8');

    // Attempt 1: pakai cached_video_player_plus wrapper kalau MP4
    // (repeat-view benefit). HLS bypass karena segments tidak ke-cache.
    final firstAttempt = await _tryInitVideoController(
      resolvedUrl: resolvedUrl,
      useCacheWrapper: !isHls,
      userInitiated: userInitiated,
    );
    if (firstAttempt || !mounted) return;

    // Attempt 2: bug recovery — cold-start setelah force-kill app kadang
    // bikin cache wrapper punya partial file (force-kill mid-write).
    // Wrapper baca SQLite entry "cached" → coba play dari local file
    // corrupt → init throw. Solusi: invalidate cache untuk URL ini lalu
    // re-init bypass wrapper (langsung network). Kalau ini juga gagal
    // baru declare _videoLoadFailed (real network/codec error).
    if (!isHls) {
      try {
        await DefaultCacheManager().removeFile(resolvedUrl);
      } catch (_) {
        // Ignore — cache entry mungkin tidak ada (race), retry tetap
        // worth dicoba dengan plain controller.
      }
    }
    final secondAttempt = await _tryInitVideoController(
      resolvedUrl: resolvedUrl,
      useCacheWrapper: false, // bypass wrapper di retry
      userInitiated: userInitiated,
    );
    if (secondAttempt || !mounted) return;

    setState(() => _videoLoadFailed = true);
  }

  /// Helper init satu attempt. Return true kalau sukses (controller
  /// ready & assigned ke _videoController), false kalau exception.
  /// Cleanup dispose dilakukan internal kalau gagal supaya caller tidak
  /// perlu handle leak.
  Future<bool> _tryInitVideoController({
    required String resolvedUrl,
    required bool useCacheWrapper,
    required bool userInitiated,
  }) async {
    CachedVideoPlayerPlus? wrapper;
    VideoPlayerController? controller;
    try {
      if (useCacheWrapper) {
        wrapper = CachedVideoPlayerPlus.networkUrl(
          Uri.parse(resolvedUrl),
          invalidateCacheIfOlderThan: const Duration(days: 7),
        );
        controller = wrapper.controller;
      } else {
        controller = VideoPlayerController.networkUrl(Uri.parse(resolvedUrl));
      }
      _cachedPlayer = wrapper;
      _resetLoadingSpinnerTimer();
      if (mounted) setState(() {});
      if (useCacheWrapper) {
        await wrapper!.initialize();
      } else {
        await controller.initialize();
      }
      if (!mounted) {
        if (wrapper != null) {
          await wrapper.dispose();
        } else {
          await controller.dispose();
        }
        _cachedPlayer = null;
        return true; // not failed, just unmounted; skip retry
      }
      _videoController = controller;
      controller.addListener(_handleVideoPositionForCta);
      _cancelLoadingSpinnerDelay();
      await controller.setLooping(true);
      await controller.setVolume(appSettingsStore.feedMuted ? 0 : 1);
      if (widget.isActive && (_shouldAutoplay || userInitiated)) {
        await controller.play();
      }
      _isPaused = !controller.value.isPlaying;
      setState(() {});
      return true;
    } catch (_) {
      _cancelLoadingSpinnerDelay();
      if (wrapper != null) {
        try {
          await wrapper.dispose();
        } catch (_) {}
      } else if (controller != null) {
        try {
          await controller.dispose();
        } catch (_) {}
      }
      _cachedPlayer = null;
      _videoController = null;
      return false;
    }
  }

  @override
  void dispose() {
    feedStore.removeListener(_onFeedStoreChanged);
    _loadingSpinnerDelay?.cancel();
    _stopProductRotation();
    // Defensive: kalau widget unmount sebelum drawer close (mis. user
    // scroll ke post lain saat drawer open), cleanup back closer
    // supaya gak ghost ke widget yang udah dispose.
    popAndroidBackOverlayCloser(_androidBackCommentCloser);
    _commentSheetController.removeListener(_syncCommentSheetProgress);
    _commentSheetController.dispose();
    _commentSheetExtent.dispose();
    _videoController?.removeListener(_handleVideoPositionForCta);
    // Prefer dispose via wrapper — handle cache reference cleanup.
    // Wrapper.dispose() internally call controller.dispose() too, jadi
    // tidak perlu double-dispose. Kalau wrapper null (defensive), fallback
    // ke controller dispose direct.
    if (_cachedPlayer != null) {
      _cachedPlayer!.dispose();
      _cachedPlayer = null;
    } else {
      _videoController?.dispose();
    }
    _videoController = null;
    _heartBurstController.dispose();
    super.dispose();
  }

  void _syncCommentSheetProgress() {
    if (!_commentSheetController.isAttached) return;
    final hostHeight = _commentSheetHostHeight(context);
    final maxExtent = _commentSheetMaxExtentFor(hostHeight);
    final size = _commentSheetController.size;
    final extent = size.clamp(_commentSheetMinExtent, maxExtent).toDouble();
    if ((_commentSheetExtent.value - extent).abs() > 0.002) {
      _commentSheetExtent.value = extent;
    }
    if (_commentSheetOpen &&
        !_commentSheetClosingFromDrag &&
        size <= _commentSheetMinExtent + 0.012) {
      _commentSheetClosingFromDrag = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _closeComments();
      });
    }
  }

  double _commentSheetHostHeight(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return math.max(1.0, screenHeight - keyboardInset);
  }

  double _commentMinVideoHeightFor(double hostHeight) {
    return (hostHeight * 0.30).clamp(220.0, 280.0).toDouble();
  }

  double _commentSheetMaxExtentFor(double hostHeight) {
    final minVideoHeight = _commentMinVideoHeightFor(hostHeight);
    final extent = 1 - (minVideoHeight / math.max(1.0, hostHeight));
    return extent
        .clamp(_commentSheetInitialExtent, _commentSheetMaxExtentCap)
        .toDouble();
  }

  List<FeedProductLink> _rotatingProductsForPost(FeedPost post) {
    final maxProducts = post.author.isAdmin ? 5 : 3;
    // Pakai `taggedProducts` — itu yang backend return (lihat
    // lib/feed/queries.ts:208). Sebelumnya pakai `productsInVideo` yang
    // tidak pernah di-populate backend → product bar di atas nama user
    // tidak pernah muncul untuk admin post yang tag produk.
    // `productsInVideo` field tetap di model untuk future use kalau ada
    // timed product feature (produk muncul di detik tertentu video).
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

  /// Sync local mirror dari shared FeedStore. Dipanggil saat store
  /// notify (toggle dari Detail/Profile screen yang lain juga update
  /// store → kita ikut rebuild).
  void _onFeedStoreChanged() {
    if (!mounted) return;
    final fresh = feedStore.get(widget.post.id);
    if (fresh == null) return;
    final newLiked = fresh.viewerLiked || fresh.isLiked;
    if (newLiked == _liked &&
        fresh.likeCount == _likeCount &&
        fresh.commentCount == _commentCount &&
        fresh.shareCount == _shareCount) {
      return;
    }
    setState(() {
      _liked = newLiked;
      _likeCount = fresh.likeCount;
      _commentCount = fresh.commentCount;
      _shareCount = fresh.shareCount;
    });
  }

  Future<void> _onLikePressed() async {
    if (_likeBusy) return;
    AppHaptics.impact();
    setState(() => _likeBusy = true);
    // Delegate ke FeedStore — optimistic + API + reconcile + rollback +
    // mutex semua handled di sana. Local field auto-update lewat
    // _onFeedStoreChanged listener saat store notify.
    try {
      final result = await feedStore.toggleLike(widget.post.id);
      // Sync ke FeedLocalStore (SharedPreferences) supaya next launch
      // reflect liked state instant.
      feedLocalStore.setLiked(widget.post.id, result.liked);
    } catch (error) {
      if (!mounted) return;
      if (error is ApiException && error.statusCode == 401) {
        // BUG FIX: kalau backend reject 401 padahal client kira logged-in
        // (zombie session — user.id tidak ada di DB / token expired), JANGAN
        // langsung push login. Clear local cache dulu via logout() supaya
        // memberStore.isLoggedIn = false → halaman lain auto-respond.
        // Tanpa ini, user di-redirect ke login tapi cache "logged in" tetap,
        // jadi looping.
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
    } finally {
      if (mounted) setState(() => _likeBusy = false);
    }
  }

  /// Double-tap → like (kalau belum) + heart burst di posisi jari.
  /// Instagram Reels signature gesture.
  void _rememberHeartBurstPosition(TapDownDetails details) {
    _heartBurstPosition = details.localPosition;
  }

  void _onDoubleTapLike() {
    if (!_liked) {
      _onLikePressed();
    } else {
      AppHaptics.impact();
    }
    _heartBurstController.forward(from: 0);
  }

  Future<void> _onComment() async {
    if (_commentDrawerMounted) return;
    AppHaptics.tap();
    FocusScope.of(context).unfocus();
    widget.onOverlayStateChanged(true);
    // Register closer ke Android back coordinator — Samsung Back press
    // di MainNavigationScreen akan call ini DULU sebelum tab nav /
    // double-back exit. Closer dipanggil ulang via _closeComments,
    // sehingga state UI + back stack sync.
    pushAndroidBackOverlayCloser(_androidBackCommentCloser);
    setState(() {
      _commentDrawerMounted = true;
      _commentAddedCount = 0;
      _commentSheetClosingFromDrag = false;
      _commentDragOffset = 0;
    });
    _commentSheetExtent.value = _commentSheetInitialExtent;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_commentDrawerMounted) return;
      if (_commentSheetController.isAttached) {
        _commentSheetController.jumpTo(_commentSheetInitialExtent);
      }
      setState(() => _commentSheetOpen = true);
    });
  }

  /// Stable reference closer untuk Android back coordinator. Method
  /// (bukan variable assignment ke lambda) supaya consistent reference
  /// + lint-clean. Identitas reference match via tear-off di push/pop.
  void _androidBackCommentCloser() {
    if (_commentDrawerMounted) _closeComments();
  }

  void _closeComments([int addedCount = 0]) {
    if (!_commentDrawerMounted) return;
    FocusScope.of(context).unfocus();
    AppHaptics.tap();
    // Cleanup Android back closer reference — defensive double-pop
    // dilindungi oleh identical() check di popAndroidBackOverlayCloser.
    // Aman dipanggil walau closer udah ke-consume oleh back press
    // (consumeAndroidBackOverlay sudah removeLast SEBELUM call closer).
    popAndroidBackOverlayCloser(_androidBackCommentCloser);
    final countDelta = math.max(addedCount, _commentAddedCount);
    if (countDelta > 0) {
      // Propagasi ke FeedStore — semua screen lain (Detail / Public
      // Profile / Postingan Saya) yang baca count dari store ikut update.
      // Local _commentCount field auto-update via _onFeedStoreChanged.
      final base = feedStore.get(widget.post.id)?.commentCount ?? _commentCount;
      feedStore.setCommentCount(widget.post.id, base + countDelta);
    }
    setState(() {
      _commentSheetOpen = false;
      _commentAddedCount = 0;
      _commentDragOffset = 0;
    });
    Future<void>.delayed(const Duration(milliseconds: 280), () {
      if (!mounted || _commentSheetOpen) return;
      _commentSheetExtent.value = _commentSheetInitialExtent;
      _commentSheetClosingFromDrag = false;
      if (_commentSheetController.isAttached) {
        _commentSheetController.jumpTo(_commentSheetInitialExtent);
      }
      setState(() => _commentDrawerMounted = false);
      widget.onOverlayStateChanged(false);
    });
  }

  void _onCommentDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? 0;
    if (!_commentSheetController.isAttached || delta == 0) return;
    final screenHeight = math.max(1.0, MediaQuery.sizeOf(context).height);
    final maxExtent =
        _commentSheetMaxExtentFor(_commentSheetHostHeight(context));
    final nextSize = (_commentSheetController.size - (delta / screenHeight))
        .clamp(_commentSheetMinExtent, maxExtent)
        .toDouble();
    _commentSheetController.jumpTo(nextSize);
  }

  void _onCommentDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final size = _commentSheetController.isAttached
        ? _commentSheetController.size
        : _commentSheetInitialExtent;
    final maxExtent =
        _commentSheetMaxExtentFor(_commentSheetHostHeight(context));
    if (velocity > 520 || size <= _commentSheetDismissExtent) {
      _closeComments();
      return;
    }
    final expandThreshold = (_commentSheetInitialExtent + maxExtent) / 2;
    final target =
        size >= expandThreshold ? maxExtent : _commentSheetInitialExtent;
    _commentSheetController.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  /// Open moderation actions sheet (Report / Block).
  ///
  /// Wajib ada per Google Play UGC policy — see [moderation_action_sheet.dart]
  /// untuk rasionalnya. Setelah block, kirim signal ke parent supaya
  /// post dari user yang baru di-block langsung hilang dari feed (pakai
  /// notifyListeners dari [blockService] yang di-listen di FeedScreen).
  Future<void> _onMoreActions() async {
    AppHaptics.tap();
    widget.onOverlayStateChanged(true);
    final post = widget.post;
    await showModerationActions(
      context,
      targetKind: ReportTargetKind.feedPost,
      targetId: post.id,
      authorId: post.author.id,
      authorName:
          post.author.isOfficialAccount ? null : post.author.displayName,
      allowBlock: !post.author.isOfficialAccount,
      useFeedStyle: true,
    );
    if (mounted) widget.onOverlayStateChanged(false);
  }

  Future<void> _onShare() async {
    AppHaptics.tap();
    final url =
        '${ApiConfig.publicSiteUrl}/feed/${Uri.encodeComponent(widget.post.id)}';
    final caption = widget.post.title.isNotEmpty
        ? '${widget.post.title}\n$url'
        : 'Lihat di Natalo Petshop:\n$url';
    final box = context.findRenderObject() as RenderBox?;
    try {
      await Share.share(
        caption,
        sharePositionOrigin:
            box != null ? box.localToGlobal(Offset.zero) & box.size : null,
      );
      if (!mounted) return;
      setState(() => _shareCount += 1);
      await feedService.trackShare(widget.post.id);
    } catch (_) {}
  }

  void _openCart({bool fromFeed = false}) {
    AppHaptics.tap();
    Navigator.pushNamed(
      context,
      '/cart',
      arguments: fromFeed ? const {'origin': 'feed'} : null,
    );
  }

  /// Sprint 3 #10 — Cinema mode fullscreen native player.
  ///
  /// Push fullscreen route dengan VideoPlayer yang re-attach ke controller
  /// existing — playback state (currentTime, volume, looping) preserved.
  /// User dapat AVPlayer-style fullscreen experience tanpa kehilangan
  /// position playback saat balik ke feed.
  ///
  /// iOS: AVPlayer di-render native via video_player package — sudah
  /// support gesture native, scrubbing, AirPlay button (kalau enabled
  /// di Info.plist).
  // ignore: unused_element
  Future<void> _openCinemaMode() async {
    final ctrl = _videoController;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    AppHaptics.tap();
    widget.onOverlayStateChanged(true);
    // Pause feed video selama fullscreen open — restore saat user balik.
    // Hindari double-playback (audio overlap dari 2 controller).
    final wasPlaying = ctrl.value.isPlaying;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _FullScreenVideoPage(controller: ctrl),
        fullscreenDialog: true,
      ),
    );
    widget.onOverlayStateChanged(false);
    if (mounted && wasPlaying && !ctrl.value.isPlaying) {
      // Restore playback kalau user pause di fullscreen lalu close.
      ctrl.play();
    }
  }

  Future<void> _openFeedCartSheet() async {
    AppHaptics.tap();
    widget.onOverlayStateChanged(true);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.22),
      builder: (sheetContext) => _FeedCartSheet(
        onOpenFullCart: () {
          Navigator.of(sheetContext).pop();
          _openCart(fromFeed: true);
        },
      ),
    ).whenComplete(() => widget.onOverlayStateChanged(false));
  }

  Future<void> _onProductsTap(List<FeedProductLink> products) async {
    if (products.isEmpty) {
      await _openFeedCartSheet();
      return;
    }
    if (products.length == 1) {
      await _onProductTap(products.first);
      return;
    }
    AppHaptics.tap();
    widget.onOverlayStateChanged(true);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.18),
      builder: (_) => _FeedTaggedProductsSheet(
        products: products,
        onOpenProduct: (link) async {
          await _onProductTap(link);
        },
        onAdd: (link, quantity) async {
          _addFeedLinkToCart(link, quantity: quantity);
        },
        onBuy: (link, quantity) async {
          _buyFeedLinkNow(link, quantity: quantity);
        },
      ),
    ).whenComplete(() => widget.onOverlayStateChanged(false));
  }

  Future<void> _quickAddProduct(FeedProductLink link) async {
    _addFeedLinkToCart(link);
  }

  void _addFeedLinkToCart(
    FeedProductLink link, {
    int quantity = 1,
  }) {
    if (!link.isAvailable || link.stock <= 0) {
      _showProductUnavailable();
      return;
    }

    if (link.hasVariants) {
      _onProductTap(link);
      return;
    }

    final product = _productFromFeedLink(link);
    cartStore.addProduct(product, quantity: quantity);
    if (!mounted) return;
    AppToast.showCartAdded(
      context,
      quantity > 1
          ? '$quantity x ${link.name} masuk keranjang'
          : '${link.name} masuk keranjang',
    );
  }

  void _buyFeedLinkNow(
    FeedProductLink link, {
    int quantity = 1,
  }) {
    if (!link.isAvailable || link.stock <= 0) {
      _showProductUnavailable();
      return;
    }

    if (link.hasVariants) {
      _onProductTap(link);
      return;
    }

    _buyProductNow(_productFromFeedLink(link), quantity: quantity);
  }

  Future<void> _onProductTap(FeedProductLink link) async {
    AppHaptics.tap();
    widget.onOverlayStateChanged(true);
    final product = await productService.fetchProductBySlug(link.slug);
    if (!mounted) {
      widget.onOverlayStateChanged(false);
      return;
    }
    if (product == null) {
      widget.onOverlayStateChanged(false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Produk tidak ditemukan.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.18),
      builder: (_) => _FeedProductSheet(
        product: product,
        onOpenProduct: () => _openProductDetail(product),
        onAdd: (quantity) => _addProductToCart(product, quantity: quantity),
        onBuy: (quantity) => _buyProductNow(product, quantity: quantity),
      ),
    ).whenComplete(() => widget.onOverlayStateChanged(false));
  }

  void _openProductDetail(Product product) {
    AppHaptics.tap();
    Navigator.pushNamed(context, '/product-detail', arguments: product);
  }

  void _addProductToCart(
    Product product, {
    int quantity = 1,
  }) {
    if (product.stock <= 0) {
      _showProductUnavailable();
      return;
    }
    if (product.hasVariants) {
      _openProductDetail(product);
      return;
    }
    cartStore.addProduct(product, quantity: quantity);
    if (!mounted) return;
    AppToast.showCartAdded(
      context,
      quantity > 1
          ? '$quantity x ${product.title} masuk keranjang'
          : '${product.title} masuk keranjang',
    );
  }

  void _buyProductNow(
    Product product, {
    int quantity = 1,
  }) {
    if (product.stock <= 0) {
      _showProductUnavailable();
      return;
    }
    if (product.hasVariants) {
      _openProductDetail(product);
      return;
    }
    AppHaptics.impact();
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CheckoutScreen(
          items: [
            CartItem(
              product: product,
              quantity: quantity.clamp(1, math.max(1, product.stock)),
            ),
          ],
        ),
      ),
    );
  }

  void _showProductUnavailable() {
    AppToast.show(
      context,
      'Produk sedang tidak tersedia.',
      kind: ToastKind.warning,
    );
  }

  Future<void> _onTapMedia() async {
    final ctrl = _videoController;
    if (ctrl == null) {
      await _maybeInitVideo(userInitiated: true);
      if (mounted) setState(() => _isPaused = false);
      return;
    }
    if (ctrl.value.isPlaying) {
      ctrl.pause();
      setState(() => _isPaused = true);
    } else {
      ctrl.play();
      setState(() => _isPaused = false);
    }
  }

  /// Long-press gesture with 3-zone behavior (TikTok/IG Reels signature):
  ///   - Left third  → temporary 2x speed
  ///   - Center third → temporary pause (existing behavior)
  ///   - Right third → temporary 2x speed
  ///
  /// Zone detection via `LongPressStartDetails.localPosition.dx` /
  /// container width. State direset di `_onLongPressEnd` regardless of
  /// zone. Hide overlay tetap aktif untuk semua zone supaya feels native.
  ///
  /// Scrubber guard: kalau `_isScrubbing` true (user lagi drag progress
  /// bar), long-press di-skip — scrubber pegang gesture priority.
  bool _longPressPaused = false;
  bool _longPressSpeedActive = false;
  bool _hideOverlayForLongPress = false;
  bool _hideOverlayForPinchZoom = false;
  // Last-known media area width (set di build LayoutBuilder). Dipakai
  // untuk hitung zone dari localPosition.dx. Default screen width — akan
  // di-update ke real value saat build pertama.
  double _mediaAreaWidth = 0;

  /// Scrubber state — true saat user lagi drag/tap progress bar.
  /// Disable long-press handler supaya gesture tidak conflict.
  bool _isScrubbing = false;

  void _onMediaZoomChanged(bool zooming) {
    if (!mounted || _hideOverlayForPinchZoom == zooming) return;
    setState(() => _hideOverlayForPinchZoom = zooming);
    widget.onMediaZoomChanged(zooming);
  }

  void _onLongPressStart(LongPressStartDetails details) {
    if (_isScrubbing) return; // Scrubber priority
    final ctrl = _videoController;
    if (ctrl == null || !ctrl.value.isInitialized) return;

    // Zone detection: 0-0.4 = left, 0.4-0.6 = center, 0.6-1.0 = right.
    // Center zone dibuat lebih kecil supaya 2x speed lebih mudah
    // di-trigger (zona kiri/kanan luas).
    final width = _mediaAreaWidth > 0
        ? _mediaAreaWidth
        : MediaQuery.of(context).size.width;
    final ratio = (details.localPosition.dx / width).clamp(0.0, 1.0);
    final isCenterZone = ratio >= 0.4 && ratio <= 0.6;

    if (isCenterZone) {
      // Center: pause-while-held (existing behavior).
      if (!ctrl.value.isPlaying) return; // Hanya kalau playing
      AppHaptics.impact();
      ctrl.pause();
      setState(() {
        _longPressPaused = true;
        _hideOverlayForLongPress = true;
      });
    } else {
      // Left or right: 2x speed-while-held.
      if (!ctrl.value.isPlaying) return; // Hanya kalau playing
      AppHaptics.impact();
      ctrl.setPlaybackSpeed(2.0);
      setState(() {
        _longPressSpeedActive = true;
        _hideOverlayForLongPress = true;
      });
    }
  }

  Future<void> _onLongPressEnd(LongPressEndDetails details) async {
    final ctrl = _videoController;
    if (_longPressPaused) {
      setState(() {
        _longPressPaused = false;
        _hideOverlayForLongPress = false;
      });
      if (ctrl != null && !_isPaused) {
        // Resume cuma kalau user tidak previously tap-paused juga.
        ctrl.play();
      }
    } else if (_longPressSpeedActive) {
      setState(() {
        _longPressSpeedActive = false;
        _hideOverlayForLongPress = false;
      });
      // Reset speed ke 1.0 + force position resync. AVPlayer di iOS
      // (dan kemungkinan ExoPlayer di Android) drift internal time
      // tracking setelah rate change → release ke 1.0 = position
      // reporter "lompat" ke posisi yang dia hitung based on
      // rate × elapsed, sementara visible frame ketinggalan. Player
      // resync visible → keliatan LONCAT.
      //
      // Fix: capture position SEBELUM rate change, set 1.0, seek
      // explicit ke captured position. Force player re-sync internal
      // time tracking ke actual rendered frame. SeekTo ke posisi
      // yang frame-nya masih di buffer (sama persis) biasanya
      // instant — no visible decode delay.
      // Defensive try-catch — controller bisa di-dispose tengah
      // jalan (mis. user swipe ke post lain saat masih long-press).
      try {
        final pos = ctrl?.value.position;
        ctrl?.setPlaybackSpeed(1.0);
        if (pos != null && ctrl != null && ctrl.value.isInitialized) {
          await ctrl.seekTo(pos);
        }
      } catch (_) {}
    }
  }

  Future<void> _toggleMuteWhilePaused() async {
    final ctrl = _videoController;
    if (ctrl == null || !_isPaused) return;
    AppHaptics.tap();
    final nextMuted = !appSettingsStore.feedMuted;
    await appSettingsStore.setFeedMuted(nextMuted);
    await ctrl.setVolume(nextMuted ? 0 : 1);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final products = _rotatingProductsForPost(post);
    final featuredProduct = products.isEmpty
        ? null
        : products[_featuredProductIndex % products.length];
    return VisibilityDetector(
      key: ValueKey('feed-post-${post.id}'),
      onVisibilityChanged: (info) {
        final ctrl = _videoController;
        if (!mounted) return;
        // Gap #3: track view event saat post >50% visible + active.
        // Debounced via FeedLocalStore.hasViewedThisSession — no
        // double-count saat user swipe back/forth ke post sama.
        if (info.visibleFraction > 0.5 &&
            widget.isActive &&
            !feedLocalStore.hasViewedThisSession(post.id)) {
          feedLocalStore.markViewedThisSession(post.id);
          // Fire-and-forget — analytics non-critical, jangan await.
          feedService.trackView(post.id);
        }
        if (ctrl == null) return;
        if (info.visibleFraction > 0.7 && widget.isActive && _shouldAutoplay) {
          if (!ctrl.value.isPlaying && !_isPaused) ctrl.play();
        } else {
          ctrl.pause();
        }
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final keyboard = MediaQuery.viewInsetsOf(context).bottom;
          final commentSheetHostHeight =
              math.max(1.0, constraints.biggest.height - keyboard);
          final commentSheetMaxExtent =
              _commentSheetMaxExtentFor(commentSheetHostHeight);
          // Cache media area width untuk zone detection di long-press
          // handler (left/center/right 2x speed vs pause).
          _mediaAreaWidth = constraints.maxWidth;
          // extendBody: true di Scaffold → Stack ini memanjang sampai tepi
          // bawah layar (dulu false, body berhenti di atas nav). Sekarang
          // insets di sini relatif ke SCREEN bottom, jadi tambah
          // kFloatingNavClearance (dari bottom_nav.dart) + safe-area device
          // supaya action rail/caption tidak tertutup floating nav.
          final navClearance =
              MediaQuery.paddingOf(context).bottom + kFloatingNavClearance;
          // Stack bawah rapat ala IG Reels (bawah → atas):
          //   nav → rail durasi (bottom: navClearance) → caption → nama.
          // Scrubber box 28px, visual line di dasarnya duduk tepat di atas
          // floating nav. Caption di atas rail dengan gap kecil supaya tidak
          // overlap hit-area scrub. Sebelumnya rail di bottom:0 (tenggelam di
          // bawah nav) + caption di 24+navClearance → void besar di antara.
          const railBand = 28.0;
          final feedInfoInset = navClearance + railBand + 6.0;
          final actionRailInset = _feedActionBottomInset + navClearance + railBand;
          final minimized = _commentSheetOpen;

          return ColoredBox(
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_commentDrawerMounted)
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: !_commentSheetOpen,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _closeComments,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 240),
                          curve: Curves.easeOutCubic,
                          color: Colors.black.withValues(
                            alpha: _commentSheetOpen ? 0.72 : 0,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (_commentDrawerMounted)
                  AnimatedSlide(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    offset:
                        _commentSheetOpen ? Offset.zero : const Offset(0, 1),
                    child: AnimatedPadding(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      padding: EdgeInsets.only(bottom: keyboard),
                      child: DraggableScrollableSheet(
                        controller: _commentSheetController,
                        initialChildSize: FeedCommentSheet.reelsHeightFactor,
                        minChildSize: _commentSheetMinExtent,
                        maxChildSize: commentSheetMaxExtent,
                        snap: false,
                        builder: (context, scrollController) {
                          return FeedCommentSheet(
                            post: widget.post,
                            applyKeyboardInset: false,
                            sheetScrollController: scrollController,
                            onClose: _closeComments,
                            onAddedCountChanged: (count) {
                              _commentAddedCount = count;
                            },
                            onDragUpdate: _onCommentDragUpdate,
                            onDragEnd: _onCommentDragEnd,
                          );
                        },
                      ),
                    ),
                  ),
                _CommentVideoFrame(
                  open: minimized,
                  extentListenable: _commentSheetExtent,
                  dragOffsetPx: _commentDragOffset,
                  keyboardInsetPx: keyboard,
                  screenSize: constraints.biggest,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // ── Background: video atau thumbnail ──
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
                        bottom: 0,
                        child: GestureDetector(
                          onTap: _onTapMedia,
                          onDoubleTapDown: _rememberHeartBurstPosition,
                          onDoubleTap: _onDoubleTapLike,
                          // Sprint 4 #1 — Long-press signature gesture.
                          onLongPressStart: _onLongPressStart,
                          onLongPressEnd: _onLongPressEnd,
                          child: _SnapBackZoomMedia(
                            minScale: 1,
                            maxScale: 4,
                            onZoomingChanged: _onMediaZoomChanged,
                            child: _MediaBackground(
                              post: post,
                              videoController: _videoController,
                              compactPreview: _commentDrawerMounted,
                            ),
                          ),
                        ),
                      ),
                      if (_videoLoadFailed)
                        Positioned.fill(
                          child: Center(
                            child: _VideoRetryButton(onRetry: _maybeInitVideo),
                          ),
                        ),
                      // Spinner hanya muncul kalau video belum ready DAN
                      // sudah lewat 800ms grace period (lihat
                      // _resetLoadingSpinnerTimer). Kalau initialize selesai
                      // < 800ms, spinner tidak pernah render → perceived
                      // instant. Thumbnail dari _MediaBackground tetap
                      // visible di atas background hitam selama itu.
                      if (_showLoadingSpinner &&
                          _videoController != null &&
                          !_videoController!.value.isInitialized &&
                          !_videoLoadFailed)
                        Positioned.fill(
                          child: Center(
                            child: SizedBox(
                              height: 26,
                              width: 26,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white.withValues(alpha: 0.82),
                              ),
                            ),
                          ),
                        ),
                      // ── Heart burst overlay (Reels double-tap signature) ──
                      Positioned.fill(
                        child: IgnorePointer(
                          child: AnimatedBuilder(
                            animation: _heartBurstController,
                            builder: (context, _) {
                              if (_heartOpacity.value == 0) {
                                return const SizedBox.shrink();
                              }

                              final position = _heartBurstPosition;
                              final progress = _heartBurstController.value;
                              final heart = Opacity(
                                opacity: _heartOpacity.value,
                                child: Transform.translate(
                                  offset: Offset(0, -18 * progress),
                                  child: Transform.scale(
                                    scale: _heartScale.value,
                                    child: Transform.rotate(
                                      angle: -0.08,
                                      child: const Icon(
                                        Icons.favorite_rounded,
                                        color: Color(0xFFEF4444),
                                        size: 128,
                                        shadows: [
                                          Shadow(
                                            color: Colors.white54,
                                            blurRadius: 2,
                                          ),
                                          Shadow(
                                            color: Colors.black54,
                                            blurRadius: 28,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );

                              if (position == null) {
                                return Center(child: heart);
                              }

                              return Stack(
                                children: [
                                  Positioned(
                                    left: position.dx - 64,
                                    top: position.dy - 64,
                                    width: 128,
                                    height: 128,
                                    child: Center(child: heart),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                      // Play + volume controls hide saat:
                      // 1. Comment drawer open (mode preview minimized)
                      // 2. Cinema/fullscreen mode (irrelevant — handled
                      //    di Cinema screen sendiri)
                      // Per user spec: play button besar tidak boleh
                      // muncul di video preview saat comment drawer aktif.
                      if (_isPaused &&
                          _videoController != null &&
                          !minimized &&
                          !_commentSheetOpen)
                        Center(
                          child: _PausedVideoControls(
                            muted: appSettingsStore.feedMuted,
                            onToggleMute: _toggleMuteWhilePaused,
                            onTogglePlayPause: _onTapMedia,
                          ),
                        ),
                      if (!minimized) ...[
                        // Fullscreen button di-hapus per user spec — tidak
                        // perlu, bikin UI Reels feels cluttered. Video
                        // tetap fullscreen vertical default. Cinema mode
                        // (kalau perlu nanti) bisa di-trigger lewat
                        // long-press atau gesture, bukan dedicated button.
                        // ── Bottom gradient untuk text readability ──
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: 330,
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withValues(alpha: 0.24),
                                    Colors.black.withValues(alpha: 0.76),
                                  ],
                                  stops: const [0, 0.54, 1],
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (_videoController != null)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: navClearance,
                            child: FeedVideoScrubber(
                              controller: _videoController!,
                              isCurrent: widget.isActive,
                              onScrubbingChanged: (scrubbing) {
                                if (!mounted) return;
                                setState(() => _isScrubbing = scrubbing);
                              },
                            ),
                          ),
                        // ── Right action column (Reels-style: tight + minimal) ──
                        // Sprint 4 #1 — Hide overlays selama long-press
                        // supaya user dapat clean view sementara hold.
                        // Action rail hide saat comment drawer open + saat
                        // long-press. Per user spec: video preview clean,
                        // tidak ada actions yang mengganggu.
                        Positioned(
                          right: _feedActionRailRightInset,
                          bottom: actionRailInset,
                          child: AnimatedOpacity(
                            opacity: (_hideOverlayForLongPress ||
                                    _hideOverlayForPinchZoom ||
                                    _commentSheetOpen)
                                ? 0
                                : 1,
                            duration: const Duration(milliseconds: 200),
                            child: IgnorePointer(
                              ignoring: _hideOverlayForLongPress ||
                                  _hideOverlayForPinchZoom ||
                                  _commentSheetOpen,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _ReelsAction(
                                    iconChild: _ReelsHeartGlyph(liked: _liked),
                                    count: _likeCount,
                                    onTap: _onLikePressed,
                                  ),
                                  const SizedBox(
                                      height: _feedActionItemSpacing),
                                  _ReelsAction(
                                    iconChild: const _ReelsCommentGlyph(),
                                    count: _commentCount,
                                    onTap: _onComment,
                                  ),
                                  const SizedBox(
                                      height: _feedActionItemSpacing),
                                  _ReelsAction(
                                    iconChild: const _ReelsShareGlyph(),
                                    count: _shareCount,
                                    onTap: _onShare,
                                  ),
                                  const SizedBox(
                                      height: _feedActionItemSpacing),
                                  // ── More actions (Report / Block) ──
                                  // Google Play UGC policy requirement: setiap
                                  // post UGC harus ada cara user laporkan +
                                  // blokir kreator. Tanpa button ini, app
                                  // ditolak Google saat submit Production.
                                  _ReelsAction(
                                    iconChild: const _ReelsMoreGlyph(),
                                    onTap: _onMoreActions,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // ── Bottom info: commerce group + creator + caption ──
                        // Same AnimatedOpacity wrapper untuk hide saat long-press.
                        Positioned(
                          left: 16,
                          right: 78,
                          bottom: feedInfoInset,
                          child: AnimatedOpacity(
                            opacity: (_hideOverlayForLongPress ||
                                    _hideOverlayForPinchZoom)
                                ? 0
                                : 1,
                            duration: const Duration(milliseconds: 150),
                            child: IgnorePointer(
                              ignoring: _hideOverlayForLongPress ||
                                  _hideOverlayForPinchZoom,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (products.isNotEmpty) ...[
                                    _ProductCommerceOverlayGroup(
                                      products: products,
                                      featuredProduct: featuredProduct!,
                                      featuredIndex: _featuredProductIndex %
                                          products.length,
                                      showProductCard: _endOfVideoCtaVisible &&
                                          !_commentSheetOpen,
                                      onTap: () => _onProductsTap(products),
                                      onBuy: () =>
                                          _quickAddProduct(featuredProduct),
                                      onQuickAdd: () =>
                                          _quickAddProduct(featuredProduct),
                                      onDismiss: _dismissEndOfVideoCta,
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                  _FeedCreatorIdentity(
                                    author: post.author,
                                    displayName: post.author.displayHandle,
                                  ),
                                  const SizedBox(height: 7),
                                  _ExpandableCaption(
                                    text: post.caption ?? '',
                                    expanded: _captionExpanded,
                                    onToggle: () => setState(() =>
                                        _captionExpanded = !_captionExpanded),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CommentVideoFrame extends StatelessWidget {
  final bool open;
  final ValueListenable<double> extentListenable;
  final double dragOffsetPx;
  final double keyboardInsetPx;
  final Size screenSize;
  final Widget child;

  const _CommentVideoFrame({
    required this.open,
    required this.extentListenable,
    required this.dragOffsetPx,
    required this.keyboardInsetPx,
    required this.screenSize,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final width = math.max(1.0, screenSize.width);
    final height = math.max(1.0, screenSize.height);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: open ? 1 : 0),
      duration: Duration(milliseconds: open ? 260 : 220),
      curve: open ? Curves.easeOutCubic : Curves.easeInOutCubic,
      child: RepaintBoundary(child: child),
      builder: (context, openProgress, child) {
        return ValueListenableBuilder<double>(
          valueListenable: extentListenable,
          child: child,
          builder: (context, sheetExtent, child) {
            // Pattern linked motion: video FILLS area di atas drawer,
            // bukan floating rounded preview card. Saat drawer grow ke
            // atas, video shrink vertically dari bawah. Saat drawer drag
            // ke bawah, video expand lagi. Width selalu full screen.
            //
            // Drawer extent berasal langsung dari DraggableScrollableSheet.
            // Ini membuat video dan drawer bergerak 1:1 saat user drag,
            // termasuk saat sheet berada di bawah initial extent.
            final drawerExtent = sheetExtent.clamp(0.0, 1.0).toDouble();
            // Saat keyboard terbuka, comment drawer di-layout dalam area yang
            // sudah dikurangi bottom inset oleh AnimatedPadding. Video frame
            // harus memakai tinggi efektif yang sama, kalau tidak sheet naik
            // tetapi video tetap menimpa bagian atas drawer.
            final keyboardInset =
                keyboardInsetPx.clamp(0.0, height - 1).toDouble();
            final sheetHostHeight = math.max(1.0, height - keyboardInset);
            final drawerTopY =
                sheetHostHeight * (1 - drawerExtent) + dragOffsetPx;
            final fullRect = Rect.fromLTWH(0, 0, width, height);
            // Video frame saat drawer open: full width, dari y=0 sampai
            // drawer's top edge. Animasi rect interpolate dari fullscreen
            // ke aboveDrawer rect.
            final aboveDrawerRect = Rect.fromLTWH(
              0,
              0,
              width,
              drawerTopY.clamp(0.0, height),
            );
            final rect = Rect.lerp(fullRect, aboveDrawerRect, openProgress)!;
            final bottomRadius = 22.0 * openProgress;
            return Positioned.fromRect(
              rect: rect,
              child: DecoratedBox(
                decoration: const BoxDecoration(color: Colors.black),
                child: ClipRRect(
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(bottomRadius),
                    bottomRight: Radius.circular(bottomRadius),
                  ),
                  child: DecoratedBox(
                    decoration: const BoxDecoration(color: Colors.black),
                    child: child,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Caption dengan truncate 2 lines + "more" toggle — Reels pattern.
class _FeedCreatorIdentity extends StatelessWidget {
  final FeedAuthor author;
  final String displayName;

  const _FeedCreatorIdentity({
    required this.author,
    required this.displayName,
  });

  @override
  Widget build(BuildContext context) {
    // Identity tap-able buat user dengan username — buka public profile
    // /u/{username}. Official account tetap non-tappable (admin = brand
    // tunggal, gak ada profile page sendiri). User tanpa username
    // (existing yang belum set) gak tappable juga supaya gak nge-route
    // ke handle null.
    final canOpenProfile = author.hasUsername;
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _FeedCreatorAvatar(
          name: displayName,
          profilePhotoUrl: author.profilePhotoUrl,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: author.isOfficialAccount ? _officialGold : Colors.white,
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
              height: 1.1,
              shadows: const [
                Shadow(
                  color: Colors.black54,
                  blurRadius: 6,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
        if (author.isOfficialAccount) ...[
          const SizedBox(width: 6),
          const Icon(
            Icons.verified_rounded,
            color: _officialGold,
            size: 17,
            shadows: [
              Shadow(
                color: Colors.black54,
                blurRadius: 5,
              ),
            ],
          ),
        ],
      ],
    );
    if (!canOpenProfile) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        AppHaptics.tap();
        Navigator.pushNamed(
          context,
          '/u',
          arguments: author.username!.toLowerCase(),
        );
      },
      child: row,
    );
  }
}

class _FeedCreatorAvatar extends StatelessWidget {
  final String name;
  final String? profilePhotoUrl;

  const _FeedCreatorAvatar({
    required this.name,
    required this.profilePhotoUrl,
  });

  @override
  Widget build(BuildContext context) {
    final url = profilePhotoUrl?.trim();
    final hasPhoto = url != null && url.isNotEmpty;

    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.88),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.30),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(
        child: hasPhoto
            ? CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (_, __) => _AvatarFallback(name: name),
                errorWidget: (_, __, ___) => _AvatarFallback(name: name),
              )
            : _AvatarFallback(name: name),
      ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  final String name;

  const _AvatarFallback({required this.name});

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial = trimmed.isEmpty ? 'N' : trimmed[0].toUpperCase();
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _feedBlue.withValues(alpha: 0.92),
            const Color(0xFF38BDF8).withValues(alpha: 0.86),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}

class _ExpandableCaption extends StatefulWidget {
  final String text;
  final bool expanded;
  final VoidCallback onToggle;

  const _ExpandableCaption({
    required this.text,
    required this.expanded,
    required this.onToggle,
  });

  @override
  State<_ExpandableCaption> createState() => _ExpandableCaptionState();
}

class _ExpandableCaptionState extends State<_ExpandableCaption> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    if (text.isEmpty) return const SizedBox.shrink();
    const limit = 90;
    final isLong = text.length > limit;
    final visible = widget.expanded || !isLong
        ? text
        : '${text.substring(0, limit).trimRight()}... ';

    // Dispose recognizers lama tiap rebuild — fresh per render.
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();

    const baseStyle = TextStyle(
      color: Colors.white,
      fontSize: 13.2,
      fontWeight: FontWeight.w600,
      height: 1.38,
      shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
    );
    const mentionStyle = TextStyle(
      color: Color(0xFF60A5FA),
      fontSize: 13.2,
      fontWeight: FontWeight.w900,
      height: 1.38,
      shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
    );

    final mentionSpans = buildMentionSpans(
      visible,
      onMentionTap: (handle) {
        Navigator.of(context).pushNamed('/u', arguments: handle);
      },
      defaultStyle: baseStyle,
      mentionStyle: mentionStyle,
      collectRecognizers: _recognizers,
    );

    return GestureDetector(
      onTap: isLong ? widget.onToggle : null,
      child: Text.rich(
        TextSpan(
          style: baseStyle,
          children: [
            ...mentionSpans,
            if (isLong)
              TextSpan(
                text: widget.expanded ? '  lebih sedikit' : 'selengkapnya',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.78),
                  fontSize: 12.8,
                  fontWeight: FontWeight.w800,
                ),
              ),
          ],
        ),
        maxLines: widget.expanded ? null : 2,
        overflow:
            widget.expanded ? TextOverflow.visible : TextOverflow.ellipsis,
      ),
    );
  }
}

class _SnapBackZoomMedia extends StatefulWidget {
  final Widget child;
  final Clip clipBehavior;
  final double minScale;
  final double maxScale;
  final ValueChanged<bool>? onZoomingChanged;

  const _SnapBackZoomMedia({
    required this.child,
    this.clipBehavior = Clip.hardEdge,
    this.minScale = 1,
    this.maxScale = 4,
    this.onZoomingChanged,
  });

  @override
  State<_SnapBackZoomMedia> createState() => _SnapBackZoomMediaState();
}

class _SnapBackZoomMediaState extends State<_SnapBackZoomMedia>
    with SingleTickerProviderStateMixin {
  late final AnimationController _snapBackController;
  final Map<int, Offset> _activePointers = {};
  Animation<double>? _snapBackAnimation;
  double _scale = 1;
  double _gestureStartScale = 1;
  double _gestureStartDistance = 1;
  bool _pinching = false;
  bool _notifiedZooming = false;

  @override
  void initState() {
    super.initState();
    _snapBackController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(_handleSnapBackTick);
  }

  @override
  void dispose() {
    _snapBackController.dispose();
    super.dispose();
  }

  void _handlePointerDown(PointerDownEvent event) {
    _activePointers[event.pointer] = event.localPosition;
    if (_activePointers.length == 2) {
      _startPinch();
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_activePointers.containsKey(event.pointer)) return;
    _activePointers[event.pointer] = event.localPosition;
    if (!_pinching || _activePointers.length < 2) return;

    final distance = _currentPointerDistance();
    if (distance <= 0 || _gestureStartDistance <= 0) return;

    final nextScale = (_gestureStartScale * distance / _gestureStartDistance)
        .clamp(widget.minScale, widget.maxScale)
        .toDouble();
    if ((nextScale - _scale).abs() < 0.001) return;
    setState(() => _scale = nextScale);
  }

  void _handlePointerUp(PointerUpEvent event) {
    _activePointers.remove(event.pointer);
    if (_pinching && _activePointers.length < 2) {
      _endPinch();
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _activePointers.remove(event.pointer);
    if (_pinching && _activePointers.length < 2) {
      _endPinch();
    }
  }

  void _startPinch() {
    if (_snapBackController.isAnimating) {
      _snapBackController.stop();
    }
    _pinching = true;
    _setZooming(true);
    _gestureStartScale = _scale;
    _gestureStartDistance = math.max(1.0, _currentPointerDistance());
  }

  void _endPinch() {
    _pinching = false;
    if ((_scale - widget.minScale).abs() <= 0.001) {
      setState(() => _scale = widget.minScale);
      _setZooming(false);
      return;
    }

    _snapBackAnimation = Tween<double>(
      begin: _scale,
      end: widget.minScale,
    ).animate(
      CurvedAnimation(
        parent: _snapBackController,
        curve: Curves.easeOutCubic,
      ),
    );
    _snapBackController.forward(from: 0);
  }

  void _handleSnapBackTick() {
    final animation = _snapBackAnimation;
    if (animation == null) return;
    setState(() => _scale = animation.value);
    if (_snapBackController.isCompleted) {
      _setZooming(false);
    }
  }

  void _setZooming(bool zooming) {
    if (_notifiedZooming == zooming) return;
    _notifiedZooming = zooming;
    widget.onZoomingChanged?.call(zooming);
  }

  double _currentPointerDistance() {
    if (_activePointers.length < 2) return 0;
    final points = _activePointers.values.take(2).toList(growable: false);
    return (points[0] - points[1]).distance;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      behavior: HitTestBehavior.translucent,
      child: ClipRect(
        clipBehavior: widget.clipBehavior,
        child: Transform.scale(
          scale: _scale,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Video player kalau ada videoUrl, fallback thumbnail kalau tidak.
class _MediaBackground extends StatelessWidget {
  final FeedPost post;
  final VideoPlayerController? videoController;
  final bool compactPreview;

  const _MediaBackground({
    required this.post,
    required this.videoController,
    this.compactPreview = false,
  });

  @override
  Widget build(BuildContext context) {
    final ctrl = videoController;

    if (ctrl != null && ctrl.value.isInitialized) {
      final size = ctrl.value.size;
      if (compactPreview) {
        return Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Colors.black),
            Center(
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: size.width,
                  height: size.height,
                  child: VideoPlayer(ctrl),
                ),
              ),
            ),
          ],
        );
      }

      return Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.black),
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: VideoPlayer(ctrl),
            ),
          ),
        ],
      );
    }
    final thumb = post.thumbnailUrl;
    if (thumb != null) {
      if (compactPreview) {
        return Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Colors.black),
            Center(
              child: CachedNetworkImage(
                imageUrl: thumb,
                fit: BoxFit.contain,
                placeholder: (_, __) => const SizedBox.shrink(),
                errorWidget: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ],
        );
      }

      return Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.black),
          CachedNetworkImage(
            imageUrl: thumb,
            fit: BoxFit.cover,
            placeholder: (_, __) => const SizedBox.shrink(),
            errorWidget: (_, __, ___) => const SizedBox.shrink(),
          ),
        ],
      );
    }
    return const ColoredBox(color: Colors.black);
  }
}

/// Sprint 3 #10 — Cinema mode fullscreen player.
///
/// Wrap existing VideoPlayerController di Scaffold full-screen dengan
/// AppBar minimal + tap-to-toggle controls. Aspect ratio preserved supaya
/// landscape video tampil proper letterbox di portrait phone, dan vice
/// versa.
///
/// Tidak buat controller baru — re-attach controller yang sudah playing
/// di feed supaya position + buffered chunks preserved. User tap close →
/// kembali ke feed dengan playback state continued.
class _FullScreenVideoPage extends StatefulWidget {
  final VideoPlayerController controller;

  const _FullScreenVideoPage({required this.controller});

  @override
  State<_FullScreenVideoPage> createState() => _FullScreenVideoPageState();
}

class _FullScreenVideoPageState extends State<_FullScreenVideoPage> {
  bool _controlsVisible = true;
  Timer? _hideControlsTimer;

  @override
  void initState() {
    super.initState();
    // Set immersive mode — hide status bar + nav bar untuk true cinema feel.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _scheduleHideControls();
    // Unmute video di cinema mode (default feed muted).
    widget.controller.setVolume(1.0);
    if (!widget.controller.value.isPlaying) {
      widget.controller.play();
    }
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    // Restore system UI saat exit fullscreen.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // Mute back saat balik ke feed (feed default mute).
    widget.controller.setVolume(0);
    super.dispose();
  }

  void _scheduleHideControls() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHideControls();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.controller.value.size;
    final aspect =
        size.width > 0 && size.height > 0 ? size.width / size.height : 9 / 16;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: aspect,
                child: VideoPlayer(widget.controller),
              ),
            ),
            // Controls overlay — fade in/out smooth.
            AnimatedOpacity(
              opacity: _controlsVisible ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: SafeArea(
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                          tooltip: 'Tutup cinema mode',
                        ),
                        const Spacer(),
                      ],
                    ),
                    const Spacer(),
                    // Progress bar bawah + play/pause toggle
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 24,
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              widget.controller.value.isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 32,
                            ),
                            onPressed: () {
                              setState(() {
                                widget.controller.value.isPlaying
                                    ? widget.controller.pause()
                                    : widget.controller.play();
                              });
                              _scheduleHideControls();
                            },
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: VideoProgressIndicator(
                              widget.controller,
                              allowScrubbing: true,
                              colors: const VideoProgressColors(
                                playedColor: Colors.white,
                                bufferedColor: Colors.white24,
                                backgroundColor: Colors.white12,
                              ),
                            ),
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
    );
  }
}

double _instagramImageAspectRatio(int? width, int? height) {
  final w = width ?? 0;
  final h = height ?? 0;
  if (w <= 0 || h <= 0) return 4 / 5;
  final ratio = w / h;
  if (ratio.isNaN || ratio.isInfinite || ratio <= 0) return 4 / 5;
  return ratio.clamp(4 / 5, 1.91).toDouble();
}

class _VideoRetryButton extends StatelessWidget {
  final VoidCallback onRetry;

  const _VideoRetryButton({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onRetry,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.58),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.refresh_rounded, color: Colors.white, size: 18),
              SizedBox(width: 7),
              Text(
                'Coba lagi',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PausedVideoControls extends StatelessWidget {
  final bool muted;
  final VoidCallback onToggleMute;
  final VoidCallback onTogglePlayPause;

  const _PausedVideoControls({
    required this.muted,
    required this.onToggleMute,
    required this.onTogglePlayPause,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkResponse(
            onTap: onToggleMute,
            radius: 22,
            child: Container(
              height: 38,
              width: 38,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.46),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.16),
                ),
              ),
              child: Icon(
                muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                color: Colors.white,
                size: 20,
                shadows: const [
                  Shadow(color: Colors.black87, blurRadius: 8),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkResponse(
            onTap: onTogglePlayPause,
            radius: 42,
            child: Container(
              height: 80,
              width: 80,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                ),
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 46,
                shadows: [
                  Shadow(color: Colors.black87, blurRadius: 8),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ReelsAction extends StatefulWidget {
  final Widget iconChild;
  final int? count;
  final VoidCallback onTap;

  const _ReelsAction({
    required this.iconChild,
    this.count,
    required this.onTap,
  });

  @override
  State<_ReelsAction> createState() => _ReelsActionState();
}

class _ReelsActionState extends State<_ReelsAction>
    with SingleTickerProviderStateMixin {
  late final ActionThrottle _throttle;
  late final AnimationController _tapPulseController;
  late final Animation<double> _tapPulseScale;

  @override
  void initState() {
    super.initState();
    _throttle = ActionThrottle(interval: const Duration(milliseconds: 220));
    _tapPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _tapPulseScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.18)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.18, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 55,
      ),
    ]).animate(_tapPulseController);
  }

  @override
  void dispose() {
    _tapPulseController.dispose();
    super.dispose();
  }

  void _handleTap() {
    final accepted = _throttle.run(widget.onTap);
    if (!accepted) return;
    _tapPulseController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 54,
      child: Material(
        color: Colors.transparent,
        child: InkResponse(
          onTap: _handleTap,
          radius: 28,
          child: ScaleTransition(
            scale: _tapPulseScale,
            child: SizedBox(
              height: widget.count == null ? 44 : 60,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  widget.iconChild,
                  if (widget.count != null) ...[
                    const SizedBox(height: 2),
                    RepaintBoundary(
                      child: Text(
                        _formatCount(widget.count!),
                        style: const TextStyle(
                          color: _feedActionForegroundColor,
                          fontSize: _feedActionCountFontSize,
                          fontWeight: FontWeight.w900,
                          height: 1,
                          shadows: [
                            Shadow(
                              color: _feedActionTextShadowColor,
                              blurRadius: 2.4,
                              offset: Offset(0, 0.8),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    }
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return '$count';
  }
}

class _ReelsHeartGlyph extends StatelessWidget {
  final bool liked;

  const _ReelsHeartGlyph({
    required this.liked,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _feedActionIconSize,
      width: _feedActionIconSize,
      child: CustomPaint(painter: _HeartGlyphPainter(liked: liked)),
    );
  }
}

class _HeartGlyphPainter extends CustomPainter {
  final bool liked;

  const _HeartGlyphPainter({
    required this.liked,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path = _buildHeartPath(size);
    final shadowPaint = Paint()
      ..color = _feedActionShadowColor
      ..style = liked ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = _feedActionStrokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    canvas.drawPath(path.shift(const Offset(0, 1.2)), shadowPaint);

    final paint = Paint()
      ..color = liked ? const Color(0xFFEF4444) : _feedActionForegroundColor
      ..style = liked ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = _feedActionStrokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, paint);
  }

  Path _buildHeartPath(Size size) {
    return Path()
      ..moveTo(size.width * 0.50, size.height * 0.844)
      ..cubicTo(
        size.width * 0.469,
        size.height * 0.815,
        size.width * 0.342,
        size.height * 0.698,
        size.width * 0.244,
        size.height * 0.592,
      )
      ..cubicTo(
        size.width * 0.158,
        size.height * 0.498,
        size.width * 0.129,
        size.height * 0.425,
        size.width * 0.129,
        size.height * 0.346,
      )
      ..cubicTo(
        size.width * 0.129,
        size.height * 0.231,
        size.width * 0.219,
        size.height * 0.150,
        size.width * 0.338,
        size.height * 0.150,
      )
      ..cubicTo(
        size.width * 0.406,
        size.height * 0.150,
        size.width * 0.460,
        size.height * 0.179,
        size.width * 0.500,
        size.height * 0.231,
      )
      ..cubicTo(
        size.width * 0.540,
        size.height * 0.179,
        size.width * 0.594,
        size.height * 0.150,
        size.width * 0.662,
        size.height * 0.150,
      )
      ..cubicTo(
        size.width * 0.781,
        size.height * 0.150,
        size.width * 0.871,
        size.height * 0.231,
        size.width * 0.871,
        size.height * 0.346,
      )
      ..cubicTo(
        size.width * 0.871,
        size.height * 0.425,
        size.width * 0.842,
        size.height * 0.498,
        size.width * 0.756,
        size.height * 0.592,
      )
      ..cubicTo(
        size.width * 0.658,
        size.height * 0.698,
        size.width * 0.531,
        size.height * 0.815,
        size.width * 0.50,
        size.height * 0.844,
      )
      ..close();
  }

  @override
  bool shouldRepaint(covariant _HeartGlyphPainter oldDelegate) {
    return oldDelegate.liked != liked;
  }
}

class _ReelsCommentGlyph extends StatelessWidget {
  const _ReelsCommentGlyph();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: _feedActionIconSize,
      width: _feedActionIconSize,
      child: CustomPaint(painter: _CommentGlyphPainter()),
    );
  }
}

class _CommentGlyphPainter extends CustomPainter {
  const _CommentGlyphPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final shadowPaint = Paint()
      ..color = _feedActionShadowColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = _feedActionStrokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    final paint = Paint()
      ..color = _feedActionForegroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = _feedActionStrokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      ..moveTo(size.width * 0.519, size.height * 0.169)
      ..cubicTo(
        size.width * 0.731,
        size.height * 0.169,
        size.width * 0.879,
        size.height * 0.300,
        size.width * 0.879,
        size.height * 0.469,
      )
      ..cubicTo(
        size.width * 0.879,
        size.height * 0.640,
        size.width * 0.731,
        size.height * 0.765,
        size.width * 0.519,
        size.height * 0.765,
      )
      ..cubicTo(
        size.width * 0.473,
        size.height * 0.765,
        size.width * 0.431,
        size.height * 0.758,
        size.width * 0.392,
        size.height * 0.746,
      )
      ..lineTo(size.width * 0.185, size.height * 0.850)
      ..lineTo(size.width * 0.252, size.height * 0.660)
      ..cubicTo(
        size.width * 0.179,
        size.height * 0.610,
        size.width * 0.131,
        size.height * 0.544,
        size.width * 0.131,
        size.height * 0.469,
      )
      ..cubicTo(
        size.width * 0.131,
        size.height * 0.300,
        size.width * 0.279,
        size.height * 0.169,
        size.width * 0.519,
        size.height * 0.169,
      )
      ..close();

    canvas.drawPath(path.shift(const Offset(0, 1.2)), shadowPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ReelsShareGlyph extends StatelessWidget {
  const _ReelsShareGlyph();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: _feedActionIconSize,
      width: _feedActionIconSize,
      child: CustomPaint(painter: _ShareGlyphPainter()),
    );
  }
}

class _ShareGlyphPainter extends CustomPainter {
  const _ShareGlyphPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final shadowPaint = Paint()
      ..color = _feedActionShadowColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = _feedActionStrokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    final paint = Paint()
      ..color = _feedActionForegroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = _feedActionStrokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      ..moveTo(size.width * 0.167, size.height * 0.800)
      ..cubicTo(
        size.width * 0.183,
        size.height * 0.512,
        size.width * 0.350,
        size.height * 0.333,
        size.width * 0.563,
        size.height * 0.333,
      )
      ..lineTo(size.width * 0.563, size.height * 0.154)
      ..lineTo(size.width * 0.875, size.height * 0.433)
      ..lineTo(size.width * 0.563, size.height * 0.713)
      ..lineTo(size.width * 0.563, size.height * 0.538)
      ..cubicTo(
        size.width * 0.400,
        size.height * 0.542,
        size.width * 0.275,
        size.height * 0.625,
        size.width * 0.167,
        size.height * 0.800,
      );

    canvas.drawPath(path.shift(const Offset(0, 1.2)), shadowPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ReelsMoreGlyph extends StatelessWidget {
  const _ReelsMoreGlyph();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: _feedActionIconSize,
      width: _feedActionIconSize,
      child: CustomPaint(painter: _MoreGlyphPainter()),
    );
  }
}

class _MoreGlyphPainter extends CustomPainter {
  const _MoreGlyphPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width * 0.067;
    final centers = [
      Offset(size.width * 0.30, size.height * 0.50),
      Offset(size.width * 0.50, size.height * 0.50),
      Offset(size.width * 0.70, size.height * 0.50),
    ];
    final shadowPaint = Paint()
      ..color = _feedActionShadowColor
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    final paint = Paint()
      ..color = _feedActionForegroundColor
      ..style = PaintingStyle.fill;

    for (final center in centers) {
      canvas.drawCircle(center.translate(0, 1.2), radius, shadowPaint);
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Compact product pill — Final Lock Spec Feed Product Tag.
///
/// Layout: `[icon bag biru] [Diskon X% merah] | [Nama produk putih] [chevron]`
/// - Icon bag biru Natalo + stroke putih (per spec mockup).
/// - Diskon X% warna merah hanya tampil kalau hasActiveDiscount.
/// - Separator `|` warna white32.
/// - Nama produk 1 baris truncate.
/// - Chevron bawah → onTap buka bottom sheet "Lihat Produk".
/// - Background: dark translucent (Colors.black 0.55) + backdrop blur.
/// - No quick-add button (removed per spec) — full pill area tap-to-open.
class _ProductCommerceOverlayGroup extends StatelessWidget {
  final List<FeedProductLink> products;
  final FeedProductLink featuredProduct;
  final int featuredIndex;
  final bool showProductCard;
  final VoidCallback onTap;
  final VoidCallback onBuy;
  final VoidCallback? onQuickAdd;
  final VoidCallback onDismiss;

  const _ProductCommerceOverlayGroup({
    required this.products,
    required this.featuredProduct,
    required this.featuredIndex,
    required this.showProductCard,
    required this.onTap,
    required this.onBuy,
    this.onQuickAdd,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomCenter,
          child: showProductCard
              ? Column(
                  key: const ValueKey('product-card-open'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSlide(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      offset: Offset.zero,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 220),
                        opacity: 1,
                        child: _EndOfVideoProductCta(
                          product: featuredProduct,
                          onTap: onTap,
                          onBuy: onBuy,
                          onDismiss: onDismiss,
                        ),
                      ),
                    ),
                    const _ProductCardArrowPointer(),
                  ],
                )
              : const SizedBox.shrink(key: ValueKey('product-card-closed')),
        ),
        _ProductLinkChip(
          products: products,
          featuredProduct: featuredProduct,
          featuredIndex: featuredIndex,
          onTap: onTap,
          onQuickAdd: onQuickAdd,
        ),
      ],
    );
  }
}

class _ProductCardArrowPointer extends StatelessWidget {
  const _ProductCardArrowPointer();

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(
      size: Size(22, 10),
      painter: _DownArrowPainter(),
    );
  }
}

class _DownArrowPainter extends CustomPainter {
  const _DownArrowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();

    final fill = Paint()
      ..color = Colors.black.withValues(alpha: 0.50)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fill);

    final stroke = Paint()
      ..color = Colors.white.withValues(alpha: 0.14)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ProductLinkChip extends StatelessWidget {
  final List<FeedProductLink> products;
  final FeedProductLink featuredProduct;
  final int featuredIndex;
  final VoidCallback onTap;
  // onQuickAdd kept di signature untuk backward-compat dengan call sites
  // di feed screen — TIDAK dirender di pill (per spec). Bisa di-remove
  // belakangan setelah audit semua call sites.
  // ignore: unused_element_parameter
  final VoidCallback? onQuickAdd;

  const _ProductLinkChip({
    required this.products,
    required this.featuredProduct,
    required this.featuredIndex,
    required this.onTap,
    this.onQuickAdd,
  });

  @override
  Widget build(BuildContext context) {
    final product = featuredProduct;
    // Label by discountSource dari backend: Flash Sale → "Flash Sale X%",
    // Promo Toko → "Diskon X%". Sebelumnya hardcode "Flash Sale" untuk
    // semua diskon → Promo Toko salah tampil "Flash Sale".
    final badgeText = product.hasActiveDiscount
        ? (product.isFlashSale
            ? 'Flash Sale ${product.discountPercent}%'
            : 'Diskon ${product.discountPercent}%')
        : null;
    return Material(
      color: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.48),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.16),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E7BFF),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.18),
                      ),
                    ),
                    child: const Icon(
                      Icons.shopping_bag_outlined,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  if (badgeText != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        badgeText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          height: 1,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) =>
                          FadeTransition(opacity: animation, child: child),
                      child: Row(
                        key: ValueKey(product.id),
                        children: [
                          Expanded(
                            child: Text(
                              product.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white.withValues(alpha: 0.90),
                    size: 24,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeedTaggedProductsSheet extends StatelessWidget {
  final List<FeedProductLink> products;
  final Future<void> Function(FeedProductLink product) onOpenProduct;
  final Future<void> Function(FeedProductLink product, int quantity) onAdd;
  final Future<void> Function(FeedProductLink product, int quantity) onBuy;

  const _FeedTaggedProductsSheet({
    required this.products,
    required this.onOpenProduct,
    required this.onAdd,
    required this.onBuy,
  });

  @override
  Widget build(BuildContext context) {
    // Cek apakah ANY product punya diskon aktif → tampilkan banner promo
    // di atas list. Banner umum (highest discount %) supaya 1 sheet bisa
    // cover multi-product video tagging.
    final discounted = products.where((p) => p.hasActiveDiscount).toList();
    final bannerPercent = discounted.isEmpty
        ? 0
        : discounted
            .map((p) => p.discountPercent)
            .reduce((a, b) => a > b ? a : b);
    return FractionallySizedBox(
      heightFactor: 0.62,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFF0B0D12),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.42),
              blurRadius: 26,
              offset: const Offset(0, -12),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    height: 4,
                    width: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.30),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                // ── Header row: title (left) + cart icon + X close (right) ──
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        'Lihat Produk (${products.length})',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    // Cart icon dengan badge count — tap → buka Keranjang.
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        final nav = Navigator.of(context);
                        nav.pop();
                        nav.pushNamed('/cart');
                      },
                      child: AnimatedBuilder(
                        animation: cartStore,
                        builder: (context, _) {
                          final count = cartStore.totalQuantity;
                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: const Color(0xFF1E5BFF),
                                    width: 1.5,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.shopping_cart_outlined,
                                  color: Color(0xFF1E5BFF),
                                  size: 20,
                                ),
                              ),
                              if (count > 0)
                                Positioned(
                                  top: -4,
                                  right: -4,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFA726),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: const Color(0xFF0B0D12),
                                        width: 1.4,
                                      ),
                                    ),
                                    constraints: const BoxConstraints(
                                      minWidth: 18,
                                      minHeight: 18,
                                    ),
                                    child: Text(
                                      count > 99 ? '99+' : '$count',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                        height: 1.1,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Tutup',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // ── Banner promo (kalau ada produk diskon) ──
                if (bannerPercent > 0) ...[
                  _VideoPromoBanner(percent: bannerPercent),
                  const SizedBox(height: 12),
                ],
                Expanded(
                  child: ListView.separated(
                    itemCount: products.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final product = products[index];
                      return _FeedTaggedProductCard(
                        product: product,
                        onOpenProduct: () async {
                          Navigator.of(context).pop();
                          await onOpenProduct(product);
                        },
                        onAdd: (quantity) => onAdd(product, quantity),
                        onBuy: (quantity) async {
                          Navigator.of(context).pop();
                          await onBuy(product, quantity);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Banner promo di atas product list bottom sheet.
/// Layout: [icon discount oranye] [Diskon X% merah / "Khusus untuk produk
/// di video ini" putih] [badge "Khusus Video" putih].
class _VideoPromoBanner extends StatelessWidget {
  final int percent;

  const _VideoPromoBanner({required this.percent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F26),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A2F36)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFFF4D4F).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.local_offer_outlined,
              color: Color(0xFFFF4D4F),
              size: 19,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Diskon $percent%',
                  style: const TextStyle(
                    color: Color(0xFFFF4D4F),
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Khusus untuk produk di video ini',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedTaggedProductCard extends StatefulWidget {
  final FeedProductLink product;
  final Future<void> Function() onOpenProduct;
  final Future<void> Function(int quantity) onAdd;
  final Future<void> Function(int quantity) onBuy;

  const _FeedTaggedProductCard({
    required this.product,
    required this.onOpenProduct,
    required this.onAdd,
    required this.onBuy,
  });

  @override
  State<_FeedTaggedProductCard> createState() => _FeedTaggedProductCardState();
}

class _FeedTaggedProductCardState extends State<_FeedTaggedProductCard> {
  int _quantity = 1;

  FeedProductLink get product => widget.product;

  void _decQty() {
    if (_quantity <= 1) return;
    AppHaptics.tap();
    setState(() => _quantity -= 1);
  }

  void _incQty() {
    final maxQty = math.max(1, product.stock);
    if (_quantity >= maxQty) return;
    AppHaptics.tap();
    setState(() => _quantity += 1);
  }

  @override
  Widget build(BuildContext context) {
    final pricing = _feedProductPricing(product);
    final unavailable = !product.isAvailable || product.stock <= 0;
    final hasRatingData = product.avgRating > 0 || product.soldCount > 0;
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: const Color(0xFF111820),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFF242B33)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.20),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            InkWell(
              onTap: widget.onOpenProduct,
              borderRadius: BorderRadius.circular(18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _FeedProductThumb(url: product.imageUrl),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13.8,
                            fontWeight: FontWeight.w900,
                            height: 1.16,
                          ),
                        ),
                        // ── Badges row: Diskon X% merah + Khusus Video putih ──
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 5,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (pricing.hasPromo)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: const Color(0xFFFF4D4F),
                                    width: 1.2,
                                  ),
                                ),
                                child: Text(
                                  'Diskon ${pricing.discountPercent}%',
                                  style: const TextStyle(
                                    color: Color(0xFFFF4D4F),
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w900,
                                    height: 1,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        // ── Rating + terjual row ──
                        if (hasRatingData) ...[
                          const SizedBox(height: 7),
                          _ProductRatingRow(
                            avgRating: product.avgRating,
                            soldCount: product.soldCount,
                          ),
                        ],
                        // ── Harga row: original (coret grey) + display (merah) ──
                        const SizedBox(height: 7),
                        Wrap(
                          spacing: 7,
                          runSpacing: 5,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (pricing.hasPromo)
                              Text(
                                formatRupiah(pricing.originalPrice),
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.42),
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  decoration: TextDecoration.lineThrough,
                                  decorationColor:
                                      Colors.white.withValues(alpha: 0.42),
                                ),
                              ),
                            Text(
                              formatRupiah(pricing.displayPrice),
                              style: TextStyle(
                                // Spec: harga diskon merah, harga normal merah
                                // juga (no separation). Konsisten satu warna.
                                color: pricing.hasPromo
                                    ? const Color(0xFFFF4D4F)
                                    : const Color(0xFFFF4D4F),
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                        if (unavailable) ...[
                          const SizedBox(height: 7),
                          const Text(
                            'Produk tidak tersedia',
                            style: TextStyle(
                              color: Color(0xFFF87171),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (!unavailable && !product.hasVariants) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    'Jumlah',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.60),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 10),
                  _FeedProductQtyStepper(
                    quantity: _quantity,
                    maxQuantity: math.max(1, product.stock),
                    onMinus: _decQty,
                    onPlus: _incQty,
                  ),
                  const Spacer(),
                  Text(
                    'Total ${formatRupiah(pricing.displayPrice * _quantity)}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.58),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            if (product.hasVariants)
              SizedBox(
                width: double.infinity,
                child: _FeedPrimaryProductButton(
                  label: 'Pilih Varian',
                  enabled: !unavailable,
                  onPressed: widget.onOpenProduct,
                ),
              )
            else
              Row(
                children: [
                  _FeedSmallCartButton(
                    enabled: !unavailable,
                    onPressed: () => widget.onAdd(_quantity),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _FeedPrimaryProductButton(
                      label: 'Beli Sekarang',
                      enabled: !unavailable,
                      onPressed: () => widget.onBuy(_quantity),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _FeedProductQtyStepper extends StatelessWidget {
  final int quantity;
  final int maxQuantity;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  const _FeedProductQtyStepper({
    required this.quantity,
    required this.maxQuantity,
    required this.onMinus,
    required this.onPlus,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _FeedQtyCircleButton(
            icon: Icons.remove_rounded,
            enabled: quantity > 1,
            onTap: onMinus,
          ),
          SizedBox(
            width: 34,
            child: Text(
              '$quantity',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          _FeedQtyCircleButton(
            icon: Icons.add_rounded,
            enabled: quantity < maxQuantity,
            onTap: onPlus,
          ),
        ],
      ),
    );
  }
}

class _FeedQtyCircleButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _FeedQtyCircleButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: enabled ? onTap : null,
      radius: 17,
      child: SizedBox(
        height: 28,
        width: 28,
        child: Icon(
          icon,
          color: Colors.white.withValues(alpha: enabled ? 0.90 : 0.25),
          size: 18,
        ),
      ),
    );
  }
}

class _FeedSmallCartButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onPressed;

  const _FeedSmallCartButton({
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    // Cart icon button — blue line tema Natalo (spec ganti dari gold).
    // Filled biru transparan saat enabled, outline aja saat disabled.
    return SizedBox(
      height: 45,
      width: 45,
      child: IconButton(
        onPressed: enabled ? onPressed : null,
        style: IconButton.styleFrom(
          backgroundColor: enabled
              ? const Color(0xFF1E5BFF).withValues(alpha: 0.10)
              : Colors.white.withValues(alpha: 0.04),
          foregroundColor: enabled
              ? const Color(0xFF1E5BFF)
              : Colors.white.withValues(alpha: 0.28),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.28),
          side: BorderSide(
            color: const Color(0xFF1E5BFF)
                .withValues(alpha: enabled ? 0.55 : 0.12),
            width: 1.4,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        icon: const Icon(Icons.shopping_cart_outlined, size: 20),
      ),
    );
  }
}

/// Rating + terjual row — "★ 4.9 · 73,6 rb+ terjual" / hanya yang ada.
/// Star kuning saturated, divider dot abu, text white70.
class _ProductRatingRow extends StatelessWidget {
  final double avgRating;
  final int soldCount;

  const _ProductRatingRow({
    required this.avgRating,
    required this.soldCount,
  });

  @override
  Widget build(BuildContext context) {
    final hasRating = avgRating > 0;
    final hasSold = soldCount > 0;
    if (!hasRating && !hasSold) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasRating) ...[
          const Icon(
            Icons.star_rounded,
            color: Color(0xFFFFB400),
            size: 14,
          ),
          const SizedBox(width: 3),
          Text(
            avgRating.toStringAsFixed(1).replaceAll('.', ','),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ],
        if (hasRating && hasSold) ...[
          const SizedBox(width: 8),
          Container(
            width: 1,
            height: 10,
            color: Colors.white.withValues(alpha: 0.22),
          ),
          const SizedBox(width: 8),
        ],
        if (hasSold)
          Text(
            '${_formatSoldShort(soldCount)} terjual',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.70),
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
      ],
    );
  }
}

/// Format jumlah terjual: 73,6 rb+ / 1,2 jt+ / 250+ / 12.
/// Local helper supaya tidak butuh import dari product_card.dart yang
/// pulls in widget lain.
String _formatSoldShort(int value) {
  if (value >= 1000000) {
    final d = value / 1000000;
    final fixed = d >= 10 ? d.toStringAsFixed(0) : d.toStringAsFixed(1);
    return '${fixed.replaceAll('.', ',').replaceAll(',0', '')} jt+';
  }
  if (value >= 1000) {
    final d = value / 1000;
    final fixed = d >= 10 ? d.toStringAsFixed(0) : d.toStringAsFixed(1);
    return '${fixed.replaceAll('.', ',').replaceAll(',0', '')} rb+';
  }
  if (value >= 100) return '${(value ~/ 50) * 50}+';
  return '$value';
}

class _FeedPrimaryProductButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  const _FeedPrimaryProductButton({
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          height: 45,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: enabled
                ? const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFF5FBFFF),
                      Color(0xFF1E87FF),
                      Color(0xFF1261DA),
                    ],
                    stops: [0.0, 0.48, 1.0],
                  )
                : LinearGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.10),
                      Colors.white.withValues(alpha: 0.07),
                    ],
                  ),
            border: Border.all(
              color: enabled
                  ? const Color(0xFFBFDBFE).withValues(alpha: 0.62)
                  : Colors.white.withValues(alpha: 0.08),
            ),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: const Color(0xFF399AFF).withValues(alpha: 0.32),
                      blurRadius: 24,
                      offset: const Offset(0, 9),
                    ),
                  ]
                : const [],
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: enabled
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.42),
                fontSize: 13.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeedCartSheet extends StatelessWidget {
  final VoidCallback onOpenFullCart;

  const _FeedCartSheet({
    required this.onOpenFullCart,
  });

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.60,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFF0B0D12),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 30,
              offset: const Offset(0, -14),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: AnimatedBuilder(
            animation: cartStore,
            builder: (context, _) {
              final items = cartStore.items;
              final itemCount = cartStore.totalQuantity;
              final subtotal = cartStore.subtotal;

              return Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        height: 4,
                        width: 42,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.30),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Keranjang Feed',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      itemCount > 0
                          ? '$itemCount item di keranjang utama.'
                          : 'Keranjang masih kosong.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.58),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: items.isEmpty
                          ? const _FeedCartEmptyState()
                          : ListView.separated(
                              padding: EdgeInsets.zero,
                              itemCount: items.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final item = items[index];
                                return _FeedCartItemTile(item: item);
                              },
                            ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.10),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  itemCount > 0
                                      ? '$itemCount item'
                                      : 'Belum ada item',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.56),
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  formatRupiah(subtotal),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    height: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          FilledButton(
                            onPressed: onOpenFullCart,
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 13,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: const Text(
                              'Lihat Keranjang',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _FeedCartEmptyState extends StatelessWidget {
  const _FeedCartEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.045),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 58,
              width: 58,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.shopping_bag_outlined,
                color: _officialGold,
                size: 28,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Keranjang masih kosong',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tap tombol kecil di produk video untuk menambahkan item tanpa keluar dari Feed.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.56),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedCartItemTile extends StatelessWidget {
  final CartItem item;

  const _FeedCartItemTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final imageUrl = item.product.imageUrl;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 62,
              width: 62,
              child: imageUrl.isEmpty
                  ? const ColoredBox(
                      color: Color(0xFF171B22),
                      child: Icon(
                        Icons.shopping_bag_outlined,
                        color: Colors.white70,
                      ),
                    )
                  : imageUrl.startsWith('assets/')
                      ? Image.asset(imageUrl, fit: BoxFit.cover)
                      : CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => const ColoredBox(
                            color: Color(0xFF171B22),
                            child: Icon(
                              Icons.shopping_bag_outlined,
                              color: Colors.white70,
                            ),
                          ),
                        ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.product.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    height: 1.18,
                  ),
                ),
                if (item.variantLabel != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    item.variantLabel!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.52),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 7),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        formatRupiah(item.unitPrice),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _officialGold,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                      child: Text(
                        'x${item.quantity}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedProductThumb extends StatelessWidget {
  final String? url;

  const _FeedProductThumb({required this.url});

  @override
  Widget build(BuildContext context) {
    final imageUrl = url ?? '';
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 66,
        width: 66,
        child: imageUrl.isEmpty
            ? const ColoredBox(
                color: Color(0xFF171B22),
                child: Icon(
                  Icons.shopping_bag_outlined,
                  color: Colors.white70,
                ),
              )
            : imageUrl.startsWith('assets/')
                ? Image.asset(imageUrl, fit: BoxFit.cover)
                : CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const ColoredBox(
                      color: Color(0xFF171B22),
                      child: Icon(
                        Icons.shopping_bag_outlined,
                        color: Colors.white70,
                      ),
                    ),
                  ),
      ),
    );
  }
}

class _FeedProductPricing {
  final int originalPrice;
  final int displayPrice;
  final bool hasPromo;
  final int discountPercent;

  const _FeedProductPricing({
    required this.originalPrice,
    required this.displayPrice,
    required this.hasPromo,
    required this.discountPercent,
  });
}

_FeedProductPricing _feedProductPricing(FeedProductLink product) {
  final original = product.price;
  var display = product.price;
  final discount = product.discountPrice;
  final promo = product.promoPrice;
  if (discount != null && discount > 0 && discount < display) {
    display = discount;
  }
  if (promo != null && promo > 0 && promo < display) {
    display = promo;
  }
  final hasPromo = original > 0 && display < original;
  final percent = hasPromo
      ? (((original - display) / original) * 100).round().clamp(1, 99)
      : 0;
  return _FeedProductPricing(
    originalPrice: original,
    displayPrice: display,
    hasPromo: hasPromo,
    discountPercent: percent,
  );
}

Product _productFromFeedLink(FeedProductLink link) {
  final pricing = _feedProductPricing(link);
  return Product(
    id: link.id,
    slug: link.slug,
    title: link.name,
    category: 'Feed',
    brand: 'Natalo',
    imageUrl: link.imageUrl ?? '',
    price: pricing.originalPrice.toDouble(),
    discountPrice:
        (pricing.hasPromo ? pricing.displayPrice : link.discountPrice)
            ?.toDouble(),
    rating: 0,
    reviewCount: 0,
    stock: link.stock,
    weightGram: link.weightGram,
    hasVariants: link.hasVariants,
    description: '',
  );
}

class _FeedProductSheet extends StatefulWidget {
  final Product product;
  final VoidCallback onOpenProduct;
  final ValueChanged<int> onAdd;
  final ValueChanged<int> onBuy;

  const _FeedProductSheet({
    required this.product,
    required this.onOpenProduct,
    required this.onAdd,
    required this.onBuy,
  });

  @override
  State<_FeedProductSheet> createState() => _FeedProductSheetState();
}

class _FeedProductSheetState extends State<_FeedProductSheet> {
  int _quantity = 1;

  Product get product => widget.product;

  void _decQty() {
    if (_quantity <= 1) return;
    AppHaptics.tap();
    setState(() => _quantity -= 1);
  }

  void _incQty() {
    final maxQty = math.max(1, product.stock);
    if (_quantity >= maxQty) return;
    AppHaptics.tap();
    setState(() => _quantity += 1);
  }

  void _openProduct(BuildContext context) {
    Navigator.pop(context);
    widget.onOpenProduct();
  }

  void _buyNow(BuildContext context) {
    Navigator.pop(context);
    widget.onBuy(_quantity);
  }

  @override
  Widget build(BuildContext context) {
    final discountPercent = product.discountPercent;
    final unavailable = product.stock <= 0;
    return FractionallySizedBox(
      heightFactor: product.hasVariants ? 0.48 : 0.58,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFF0B0D12),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.42),
              blurRadius: 26,
              offset: const Offset(0, -12),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    height: 4,
                    width: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.30),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ProductPreviewImage(url: product.imageUrl),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              height: 1.18,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 7,
                            runSpacing: 7,
                            children: [
                              _ProductMetaChip(
                                icon: unavailable
                                    ? Icons.block_rounded
                                    : Icons.check_circle_outline_rounded,
                                label:
                                    unavailable ? 'Tidak tersedia' : 'Tersedia',
                              ),
                              if (product.hasVariants)
                                const _ProductMetaChip(
                                  icon: Icons.tune_rounded,
                                  label: 'Pilih varian',
                                ),
                              if (discountPercent != null)
                                _ProductMetaChip(
                                  icon: Icons.local_offer_outlined,
                                  label: 'Promo $discountPercent%',
                                  gold: true,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatRupiah(product.finalPrice),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                    if (product.hasDiscount) ...[
                      const SizedBox(width: 9),
                      Text(
                        formatRupiah(product.price),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.lineThrough,
                          decorationColor: Colors.white.withValues(alpha: 0.45),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  product.brand.isEmpty ? product.category : product.brand,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.62),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (!unavailable && !product.hasVariants) ...[
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Text(
                        'Jumlah',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.60),
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(width: 10),
                      _FeedProductQtyStepper(
                        quantity: _quantity,
                        maxQuantity: math.max(1, product.stock),
                        onMinus: _decQty,
                        onPlus: _incQty,
                      ),
                      const Spacer(),
                      Text(
                        'Total ${formatRupiah(product.finalPrice * _quantity)}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.58),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ],
                const Spacer(),
                if (product.hasVariants)
                  SizedBox(
                    width: double.infinity,
                    child: _FeedPrimaryProductButton(
                      label: 'Pilih Varian',
                      enabled: !unavailable,
                      onPressed: () => _openProduct(context),
                    ),
                  )
                else
                  Row(
                    children: [
                      _FeedSmallCartButton(
                        enabled: !unavailable,
                        onPressed: () => widget.onAdd(_quantity),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _FeedPrimaryProductButton(
                          label: 'Beli Sekarang',
                          enabled: !unavailable,
                          onPressed: () => _buyNow(context),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        height: 45,
                        width: 45,
                        child: IconButton(
                          onPressed: () => _openProduct(context),
                          tooltip: 'Detail produk',
                          style: IconButton.styleFrom(
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.08),
                            foregroundColor: Colors.white,
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.14),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(17),
                            ),
                          ),
                          icon: const Icon(Icons.chevron_right_rounded),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductPreviewImage extends StatelessWidget {
  final String url;

  const _ProductPreviewImage({required this.url});

  @override
  Widget build(BuildContext context) {
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: 92,
        width: 92,
        child: url.isEmpty
            ? const ColoredBox(
                color: Color(0xFF171B22),
                child: Icon(
                  Icons.shopping_bag_outlined,
                  color: Colors.white70,
                ),
              )
            : url.startsWith('assets/')
                ? Image.asset(url, fit: BoxFit.cover)
                : CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const ColoredBox(
                      color: Color(0xFF171B22),
                      child: Icon(
                        Icons.shopping_bag_outlined,
                        color: Colors.white70,
                      ),
                    ),
                  ),
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: image,
    );
  }
}

class _ProductMetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool gold;

  const _ProductMetaChip({
    required this.icon,
    required this.label,
    this.gold = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = gold ? _officialGold : Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: gold ? 0.13 : 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: gold ? 0.35 : 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// End-of-video product CTA — card prominent yang muncul slide-up dari bawah
/// di ~2.5 detik terakhir tiap loop video. Lebih besar + lebih visible dari
/// `_ProductLinkChip` di bottom info biar user yang nonton sampai abis lihat
/// reminder produk dengan tombol "Beli" jelas. Hidden saat long-press
/// preview atau comment sheet open. Dismissable via X icon (sticky sampai
/// user swipe ke post lain).
/// Popup preview produk — auto-show ~2s sebelum video berakhir (logic
/// trigger di feed_screen line 1847). Layout Final Lock Spec:
///  - Dark glass card dengan arrow pointing down ke pill
///  - Thumbnail produk (kiri, 4:5 portrait)
///  - Content right: nama + badges (Diskon merah + Khusus Video putih)
///    + rating (★ 4.9 · 73,6 rb+ terjual) + harga (coret + display merah)
///    + bottom row: cart icon biru + tombol Beli biru
///  - Small X dismiss di kanan atas
class _EndOfVideoProductCta extends StatelessWidget {
  final FeedProductLink product;
  final VoidCallback onTap;
  final VoidCallback onBuy;
  final VoidCallback onDismiss;

  const _EndOfVideoProductCta({
    required this.product,
    required this.onTap,
    required this.onBuy,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final pricing = _feedProductPricing(product);
    final canBuy = product.isAvailable && product.stock > 0;
    final imageUrl = product.imageUrl;
    final hasRatingData = product.avgRating > 0 || product.soldCount > 0;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.50),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.14),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.30),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(18),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Thumbnail produk (4:5 portrait) ──
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 72,
                            height: 90,
                            child: imageUrl != null && imageUrl.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: imageUrl,
                                    fit: BoxFit.cover,
                                    placeholder: (_, __) => Container(
                                        color: const Color(0xFF2A2F36)),
                                    errorWidget: (_, __, ___) => Container(
                                        color: const Color(0xFF2A2F36)),
                                  )
                                : Container(color: const Color(0xFF2A2F36)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // ── Content right ──
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Spacer kecil supaya beri ruang untuk X di top-right
                              // tanpa overlap text. Padding right ~20 lewat
                              // contentPadding gak available — pakai SizedBox.
                              Padding(
                                padding: const EdgeInsets.only(right: 22),
                                child: Text(
                                  product.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                    height: 1.18,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 5),
                              // Badges row
                              Wrap(
                                spacing: 5,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (pricing.hasPromo)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFF4D4F),
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                      child: Text(
                                        'Diskon ${pricing.discountPercent}%',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w900,
                                          height: 1,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              // Rating row (conditional)
                              if (hasRatingData) ...[
                                const SizedBox(height: 5),
                                _ProductRatingRow(
                                  avgRating: product.avgRating,
                                  soldCount: product.soldCount,
                                ),
                              ],
                              const SizedBox(height: 6),
                              // Harga row
                              Wrap(
                                spacing: 6,
                                runSpacing: 3,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (pricing.hasPromo)
                                    Text(
                                      formatRupiah(pricing.originalPrice),
                                      style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.45),
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        decoration: TextDecoration.lineThrough,
                                        decorationColor: Colors.white
                                            .withValues(alpha: 0.45),
                                        height: 1,
                                      ),
                                    ),
                                  Text(
                                    formatRupiah(pricing.displayPrice),
                                    style: const TextStyle(
                                      color: Color(0xFFFF4D4F),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w900,
                                      height: 1,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              // Cart icon + Beli button row
                              Row(
                                children: [
                                  _PopupCartButton(
                                    enabled: canBuy,
                                    onTap: canBuy ? onBuy : null,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _CtaBuyButton(
                                      enabled: canBuy,
                                      onTap: canBuy ? onBuy : null,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // ── X dismiss (top-right) ──
              Positioned(
                top: 6,
                right: 6,
                child: InkResponse(
                  onTap: onDismiss,
                  radius: 18,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tombol Beli di popup preview — spec: warna Natalo biru agak ringan
/// (bukan merah). Match `_FeedPrimaryProductButton` style.
class _CtaBuyButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback? onTap;

  const _CtaBuyButton({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: enabled
              ? const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF5FBFFF),
                    Color(0xFF1E87FF),
                  ],
                )
              : null,
          color: enabled ? null : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          enabled ? 'Beli' : 'Habis',
          style: TextStyle(
            color:
                enabled ? Colors.white : Colors.white.withValues(alpha: 0.45),
            fontSize: 12.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

/// Cart icon button di popup preview — line biru tema Natalo.
class _PopupCartButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback? onTap;

  const _PopupCartButton({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: enabled
              ? const Color(0xFF1E5BFF).withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: const Color(0xFF1E5BFF)
                .withValues(alpha: enabled ? 0.65 : 0.15),
            width: 1.4,
          ),
        ),
        child: Icon(
          Icons.shopping_cart_outlined,
          color: enabled
              ? const Color(0xFF1E5BFF)
              : Colors.white.withValues(alpha: 0.28),
          size: 18,
        ),
      ),
    );
  }
}

/// Keep Product import referenced (untuk type-safety navigation arguments).
// ignore: unused_element
Product? _typeHint() => null;

// Note: _UploadChoiceSheet (split video/photo dulu) di-remove. Flow upload
// sekarang unified via FeedUploadSheet.show() → FeedMediaPickerScreen
// yang handle photo + video di satu picker IG-style. Konsisten dengan
// entry point dari member_screen + member_posts_screen.

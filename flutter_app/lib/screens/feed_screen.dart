import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shimmer/shimmer.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../config/api_config.dart';
import '../models/cart_item.dart';
import '../models/feed_post.dart';
import '../models/product.dart';
import '../screens/checkout_screen.dart';
import '../services/api_client.dart';
import '../services/feed_service.dart';
import '../services/product_service.dart';
import '../services/video_quality_service.dart';
import '../state/cart_store.dart';
import '../state/settings_store.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import '../widgets/app_toast.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/feed_comment_sheet.dart';
import '../widgets/feed_upload_sheet.dart';

const _officialGold = Color(0xFFF4D47C);
const _officialGoldMuted = Color(0xFFD7B55B);

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
  final Map<String, VideoPlayerController> _preloadedControllers = {};
  List<FeedPost> _posts = const [];
  String? _nextCursor;
  bool _loading = true;
  bool _loadingMore = false;
  bool _interactionLocked = false;
  int _activeIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadInitial();
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
    for (final controller in _preloadedControllers.values) {
      controller.dispose();
    }
    _preloadedControllers.clear();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    setState(() => _loading = true);
    final page = await feedService.fetchPublicFeed();
    if (!mounted) return;
    setState(() {
      _posts = page.items;
      _nextCursor = page.nextCursor;
      _loading = false;
    });
    _preloadNext(_activeIndex);
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _nextCursor == null) return;
    _loadingMore = true;
    final page = await feedService.fetchPublicFeed(cursor: _nextCursor);
    if (!mounted) {
      _loadingMore = false;
      return;
    }
    setState(() {
      _posts.addAll(page.items);
      _nextCursor = page.nextCursor;
      _loadingMore = false;
    });
    _preloadNext(_activeIndex);
  }

  void _onPageChanged(int index) {
    AppHaptics.tap();
    setState(() => _activeIndex = index);
    _preloadNext(index);
    if (index >= _posts.length - 2 && _nextCursor != null) {
      _loadMore();
    }
  }

  bool get _shouldPreloadNext {
    return appSettingsStore.feedAutoplay &&
        appSettingsStore.feedVideoQuality != 'data_saver';
  }

  Future<void> _preloadNext(int index) async {
    final nextIndex = index + 1;
    final allowedNextId =
        nextIndex >= 0 && nextIndex < _posts.length ? _posts[nextIndex].id : '';
    final staleIds =
        _preloadedControllers.keys.where((id) => id != allowedNextId).toList();
    for (final id in staleIds) {
      await _preloadedControllers.remove(id)?.dispose();
    }
    if (!_shouldPreloadNext || nextIndex >= _posts.length) return;
    final post = _posts[nextIndex];
    final url = post.videoUrl;
    if (url == null ||
        url.isEmpty ||
        _preloadedControllers.containsKey(post.id)) {
      return;
    }

    final thumb = post.thumbnailUrl;
    if (mounted && thumb != null && thumb.isNotEmpty) {
      precacheImage(CachedNetworkImageProvider(thumb), context);
    }

    // Sprint 2 #7 — Apply network-aware quality rewrite SEBELUM init.
    // WiFi: pakai HLS playlist (Bunny adaptive bitrate, native HLS via
    // AVPlayer iOS / ExoPlayer Android). Mobile: MP4 di quality
    // appropriate (480/720). Saves bandwidth + faster start play di 3G.
    final resolvedUrl = videoQualityService.resolvePlaybackUrl(url);
    final controller = VideoPlayerController.networkUrl(Uri.parse(resolvedUrl));
    _preloadedControllers[post.id] = controller;
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
    } catch (_) {
      await _preloadedControllers.remove(post.id)?.dispose();
    }
  }

  void _setFeedInteractionLocked(bool locked) {
    if (!mounted || _interactionLocked == locked) return;
    setState(() => _interactionLocked = locked);
  }

  Future<void> _onUpload() async {
    AppHaptics.tap();
    _setFeedInteractionLocked(true);
    final uploaded = await FeedUploadSheet.show(context).whenComplete(() {
      if (mounted) _setFeedInteractionLocked(false);
    });
    if (!mounted || uploaded != true) return;
    AppToast.show(
      context,
      'Video berhasil dikirim. Admin akan meninjau sebelum tampil.',
      kind: ToastKind.success,
      icon: Icons.check_circle_rounded,
    );
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
      extendBody: true,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        // Outer Stack — Add button selalu visible di all states (loading,
        // empty, loaded). Match reference Anda: floating icon top-right
        // siap untuk create post flow.
        child: Stack(
          children: [
            // Body content per state
            if (_loading)
              const _LoadingState()
            else if (_posts.isEmpty)
              const _EmptyState()
            else
              RefreshIndicator(
                color: Colors.white,
                backgroundColor: Colors.black87,
                notificationPredicate: (notification) {
                  return canRefresh && notification.depth == 0;
                },
                onRefresh: _loadInitial,
                child: PageView.builder(
                  controller: _pageController,
                  scrollDirection: Axis.vertical,
                  physics: _interactionLocked
                      ? const NeverScrollableScrollPhysics()
                      : const PageScrollPhysics(),
                  itemCount: _posts.length,
                  onPageChanged: _onPageChanged,
                  itemBuilder: (context, index) {
                    return _FeedPostView(
                      post: _posts[index],
                      isActive: index == _activeIndex,
                      preloadedController:
                          _preloadedControllers.remove(_posts[index].id),
                      onOverlayStateChanged: _setFeedInteractionLocked,
                    );
                  },
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
    final actionRailInset = mediaQuery.padding.bottom + 168;
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

          // Right action rail mock — 5 circles (Like/Comment/Share/Bag/
          // Fullscreen) stacked vertical. Match positioning aktual.
          Positioned(
            right: 18,
            bottom: actionRailInset,
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SkeletonCircle(size: 38),
                SizedBox(height: 10),
                _SkeletonCircle(size: 38),
                SizedBox(height: 10),
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
              'Pantau lagi nanti untuk video & promo terbaru dari Natalo.',
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

/// Satu fullscreen page Reels-style — video/thumbnail + Reels overlay.
class _FeedPostView extends StatefulWidget {
  final FeedPost post;
  final bool isActive;
  final VideoPlayerController? preloadedController;
  final ValueChanged<bool> onOverlayStateChanged;

  const _FeedPostView({
    required this.post,
    required this.isActive,
    required this.preloadedController,
    required this.onOverlayStateChanged,
  });

  @override
  State<_FeedPostView> createState() => _FeedPostViewState();
}

class _FeedPostViewState extends State<_FeedPostView>
    with TickerProviderStateMixin {
  VideoPlayerController? _videoController;
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
  int _commentAddedCount = 0;
  int _cartQuantityCount = 0;
  int _featuredProductIndex = 0;
  Timer? _productRotationTimer;
  double _commentDragOffset = 0;

  // Animation untuk heart burst di tengah saat double-tap.
  late final AnimationController _heartBurstController;
  late final Animation<double> _heartScale;
  late final Animation<double> _heartOpacity;

  @override
  void initState() {
    super.initState();
    _liked = widget.post.viewerLiked;
    _likeCount = widget.post.likeCount;
    _commentCount = widget.post.commentCount;
    _shareCount = widget.post.shareCount;
    _cartQuantityCount = cartStore.totalQuantity;
    cartStore.addListener(_syncCartCount);

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
    await controller.setVolume(appSettingsStore.feedMuted ? 0 : 1);
    if (widget.isActive && _shouldAutoplay) {
      await controller.play();
    }
    if (mounted) setState(() {});
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
        _commentDragOffset = 0;
        widget.onOverlayStateChanged(false);
        _videoController?.pause();
        _videoController?.seekTo(Duration.zero);
        _stopProductRotation();
      }
    }
    if (oldWidget.post.id != widget.post.id ||
        oldWidget.post.taggedProducts.length !=
            widget.post.taggedProducts.length) {
      _featuredProductIndex = 0;
      _syncProductRotation();
    }
  }

  Future<void> _maybeInitVideo({bool userInitiated = false}) async {
    if (_videoController != null) return;
    final url = widget.post.videoUrl;
    if (url == null || url.isEmpty) return;
    if (_dataSaverEnabled && !userInitiated) return;
    setState(() => _videoLoadFailed = false);
    try {
      // Sprint 2 #7 — Network-aware quality rewrite. Same logic dgn
      // preload path supaya consistent quality decision.
      final resolvedUrl = videoQualityService.resolvePlaybackUrl(url);
      final controller =
          VideoPlayerController.networkUrl(Uri.parse(resolvedUrl));
      _videoController = controller;
      if (mounted) setState(() {});
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      controller.setLooping(true);
      await controller.setVolume(appSettingsStore.feedMuted ? 0 : 1);
      if (widget.isActive && (_shouldAutoplay || userInitiated)) {
        await controller.play();
      }
      _isPaused = !controller.value.isPlaying;
      setState(() {});
    } catch (_) {
      await _videoController?.dispose();
      _videoController = null;
      if (!mounted) return;
      setState(() => _videoLoadFailed = true);
    }
  }

  @override
  void dispose() {
    _stopProductRotation();
    cartStore.removeListener(_syncCartCount);
    _videoController?.dispose();
    _heartBurstController.dispose();
    super.dispose();
  }

  void _syncCartCount() {
    if (!mounted) return;
    final next = cartStore.totalQuantity;
    if (next == _cartQuantityCount) return;
    setState(() => _cartQuantityCount = next);
  }

  List<FeedProductLink> _rotatingProductsForPost(FeedPost post) {
    final maxProducts = post.author.isAdmin ? 5 : 3;
    return post.productsInVideo.take(maxProducts).toList();
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
    final wasLiked = _liked;
    final previousCount = _likeCount;
    setState(() {
      _likeBusy = true;
      _liked = !wasLiked;
      _likeCount =
          wasLiked ? (_likeCount > 0 ? _likeCount - 1 : 0) : _likeCount + 1;
    });
    try {
      final result = await feedService.toggleLike(widget.post.id,
          currentlyLiked: wasLiked);
      if (!mounted) return;
      setState(() {
        _liked = result.liked;
        _likeCount = result.likeCount;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _liked = wasLiked;
        _likeCount = previousCount;
      });
      if (error is ApiException && error.statusCode == 401) {
        Navigator.pushNamed(context, '/member/login');
      } else {
        AppToast.show(
          context,
          error is ApiException ? error.message : 'Like belum berhasil.',
          kind: ToastKind.warning,
        );
      }
    } finally {
      if (mounted) setState(() => _likeBusy = false);
    }
  }

  /// Double-tap → like (kalau belum) + animasi heart burst di tengah.
  /// Instagram Reels signature gesture.
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
    setState(() {
      _commentDrawerMounted = true;
      _commentAddedCount = 0;
      _commentDragOffset = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_commentDrawerMounted) return;
      setState(() => _commentSheetOpen = true);
    });
  }

  void _closeComments([int addedCount = 0]) {
    if (!_commentDrawerMounted) return;
    FocusScope.of(context).unfocus();
    AppHaptics.tap();
    final countDelta = math.max(addedCount, _commentAddedCount);
    setState(() {
      _commentSheetOpen = false;
      _commentAddedCount = 0;
      _commentDragOffset = 0;
      if (countDelta > 0) {
        _commentCount += countDelta;
      }
    });
    Future<void>.delayed(const Duration(milliseconds: 280), () {
      if (!mounted || _commentSheetOpen) return;
      setState(() => _commentDrawerMounted = false);
      widget.onOverlayStateChanged(false);
    });
  }

  void _onCommentDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? 0;
    if (delta <= 0) return;
    setState(() {
      _commentDragOffset = math.min(150, _commentDragOffset + delta);
    });
  }

  void _onCommentDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (_commentDragOffset > 64 || velocity > 720) {
      _closeComments();
      return;
    }
    setState(() => _commentDragOffset = 0);
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

  void _openCart() {
    AppHaptics.tap();
    Navigator.pushNamed(context, '/cart');
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
        onCheckout: () {
          Navigator.of(sheetContext).pop();
          Navigator.of(context).pushNamed('/checkout');
        },
        onOpenFullCart: () {
          Navigator.of(sheetContext).pop();
          _openCart();
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

  /// Sprint 4 #1 — Long-press to pause while holding (Instagram Reels
  /// signature gesture). User tahan finger di video → pause sementara
  /// + UI overlay hide. Lepas finger → resume + UI restore.
  ///
  /// Beda dengan tap toggle: long-press temporary, tidak persist state.
  /// Cocok untuk "stop briefly to read text on video" pattern Reels.
  bool _longPressPaused = false;
  bool _hideOverlayForLongPress = false;

  void _onLongPressStart(LongPressStartDetails details) {
    final ctrl = _videoController;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (!ctrl.value.isPlaying) return; // Hanya kalau lagi playing
    AppHaptics.impact();
    ctrl.pause();
    setState(() {
      _longPressPaused = true;
      _hideOverlayForLongPress = true;
    });
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    final ctrl = _videoController;
    if (!_longPressPaused) return;
    setState(() {
      _longPressPaused = false;
      _hideOverlayForLongPress = false;
    });
    if (ctrl != null && !_isPaused) {
      // Resume cuma kalau user tidak previously tap-paused juga.
      ctrl.play();
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
        if (ctrl == null || !mounted) return;
        if (info.visibleFraction > 0.7 && widget.isActive && _shouldAutoplay) {
          if (!ctrl.value.isPlaying && !_isPaused) ctrl.play();
        } else {
          ctrl.pause();
        }
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final safeTop = MediaQuery.paddingOf(context).top;
          final safeBottom = MediaQuery.paddingOf(context).bottom;
          final keyboard = MediaQuery.viewInsetsOf(context).bottom;
          final bottomNavInset = safeBottom + 60;
          const feedInfoInset = 20.0;
          const actionRailInset = 86.0;
          final targetSheetHeight = constraints.maxHeight *
              (keyboard > 0 ? 0.52 : FeedCommentSheet.reelsHeightFactor);
          final minPreviewHeight = keyboard > 0 ? 170.0 : 224.0;
          final maxSheetHeight = math.max(
            300.0,
            constraints.maxHeight - keyboard - safeTop - minPreviewHeight,
          );
          final sheetHeight = math.min(targetSheetHeight, maxSheetHeight);
          final minimized = _commentSheetOpen;
          final previewBottomInset =
              minimized ? keyboard + sheetHeight + 10 : bottomNavInset;

          return ColoredBox(
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  margin: EdgeInsets.only(
                    left: minimized ? 14 : 0,
                    right: minimized ? 14 : 0,
                    top: minimized ? safeTop + 10 : 0,
                    bottom: previewBottomInset,
                  ),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(minimized ? 18 : 0),
                    boxShadow: minimized
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.42),
                              blurRadius: 24,
                              offset: const Offset(0, 14),
                            ),
                          ]
                        : const [],
                  ),
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
                          onDoubleTap: _onDoubleTapLike,
                          // Sprint 4 #1 — Long-press signature gesture.
                          onLongPressStart: _onLongPressStart,
                          onLongPressEnd: _onLongPressEnd,
                          child: _MediaBackground(
                            post: post,
                            videoController: _videoController,
                          ),
                        ),
                      ),
                      if (_videoLoadFailed)
                        Positioned.fill(
                          child: Center(
                            child: _VideoRetryButton(onRetry: _maybeInitVideo),
                          ),
                        ),
                      if (_videoController != null &&
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
                      IgnorePointer(
                        child: Center(
                          child: AnimatedBuilder(
                            animation: _heartBurstController,
                            builder: (context, _) {
                              if (_heartOpacity.value == 0) {
                                return const SizedBox.shrink();
                              }
                              return Opacity(
                                opacity: _heartOpacity.value,
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
                                            blurRadius: 2),
                                        Shadow(
                                            color: Colors.black54,
                                            blurRadius: 28),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      if (_isPaused && _videoController != null)
                        Center(
                          child: _PausedVideoControls(
                            muted: appSettingsStore.feedMuted,
                            onToggleMute: _toggleMuteWhilePaused,
                          ),
                        ),
                      if (!minimized) ...[
                        if (_isPaused &&
                            _videoController != null &&
                            _videoController!.value.isInitialized)
                          Positioned(
                            top: safeTop + 12,
                            right: 12,
                            child: _PausedFullscreenButton(
                              onTap: _openCinemaMode,
                            ),
                          ),
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
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: _FeedVideoProgressBar(
                            controller: _videoController,
                          ),
                        ),
                        // ── Right action column (Reels-style: tight + minimal) ──
                        // Sprint 4 #1 — Hide overlays selama long-press
                        // supaya user dapat clean view sementara hold.
                        Positioned(
                          right: 18,
                          bottom: actionRailInset,
                          child: AnimatedOpacity(
                            opacity: _hideOverlayForLongPress ? 0 : 1,
                            duration: const Duration(milliseconds: 150),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _ReelsAction(
                                  icon: _liked
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                  color: _liked
                                      ? const Color(0xFFEF4444)
                                      : Colors.white,
                                  count: _likeCount,
                                  onTap: _onLikePressed,
                                ),
                                const SizedBox(height: 10),
                                _ReelsAction(
                                  iconChild: const _ReelsCommentGlyph(),
                                  color: Colors.white,
                                  count: _commentCount,
                                  onTap: _onComment,
                                ),
                                const SizedBox(height: 10),
                                _ReelsAction(
                                  iconChild: const _ReelsShareGlyph(),
                                  color: Colors.white,
                                  count: _shareCount,
                                  onTap: _onShare,
                                ),
                                const SizedBox(height: 10),
                                _ReelsAction(
                                  iconChild: const _ReelsBagGlyph(),
                                  color: Colors.white,
                                  count: _cartQuantityCount > 0
                                      ? _cartQuantityCount
                                      : null,
                                  onTap: _openFeedCartSheet,
                                ),
                              ],
                            ),
                          ),
                        ),
                        // ── Bottom info: product tag + creator + caption ──
                        // Same AnimatedOpacity wrapper untuk hide saat long-press.
                        Positioned(
                          left: 16,
                          right: 78,
                          bottom: feedInfoInset,
                          child: AnimatedOpacity(
                            opacity: _hideOverlayForLongPress ? 0 : 1,
                            duration: const Duration(milliseconds: 150),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (products.isNotEmpty) ...[
                                  _ProductLinkChip(
                                    products: products,
                                    featuredProduct: featuredProduct!,
                                    featuredIndex:
                                        _featuredProductIndex % products.length,
                                    onTap: () => _onProductsTap(products),
                                    onQuickAdd: () =>
                                        _quickAddProduct(featuredProduct),
                                  ),
                                  const SizedBox(height: 9),
                                ],
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        post.author.isAdmin
                                            ? 'Natalo Petshop'
                                            : post.author.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: post.author.isAdmin
                                              ? _officialGold
                                              : Colors.white,
                                          fontSize:
                                              post.author.isAdmin ? 15 : 14,
                                          fontWeight: post.author.isAdmin
                                              ? FontWeight.w800
                                              : FontWeight.w900,
                                          shadows: const [
                                            Shadow(
                                              color: Colors.black54,
                                              blurRadius: 6,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    if (post.author.isAdmin) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _officialGold.withValues(
                                              alpha: 0.14),
                                          borderRadius:
                                              BorderRadius.circular(999),
                                          border: Border.all(
                                            color:
                                                _officialGoldMuted.withValues(
                                              alpha: 0.82,
                                            ),
                                            width: 1.2,
                                          ),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.check_rounded,
                                              color: _officialGold,
                                              size: 12,
                                            ),
                                            SizedBox(width: 3),
                                            Text(
                                              'Official',
                                              style: TextStyle(
                                                color: _officialGold,
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w700,
                                                height: 1,
                                                shadows: [
                                                  Shadow(
                                                    color: Colors.black54,
                                                    blurRadius: 5,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 6),
                                _ExpandableCaption(
                                  text: post.title.isNotEmpty
                                      ? post.title
                                      : (post.description ?? ''),
                                  expanded: _captionExpanded,
                                  onToggle: () => setState(() =>
                                      _captionExpanded = !_captionExpanded),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
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
                            alpha: _commentSheetOpen ? 0.16 : 0,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (_commentDrawerMounted)
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    left: 0,
                    right: 0,
                    height: sheetHeight,
                    bottom: _commentSheetOpen ? keyboard : -sheetHeight - 48,
                    child: Transform.translate(
                      offset: Offset(0, _commentDragOffset),
                      child: FeedCommentSheet(
                        post: widget.post,
                        applyKeyboardInset: false,
                        onClose: _closeComments,
                        onAddedCountChanged: (count) {
                          _commentAddedCount = count;
                        },
                        onDragUpdate: _onCommentDragUpdate,
                        onDragEnd: _onCommentDragEnd,
                      ),
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

/// Caption dengan truncate 2 lines + "more" toggle — Reels pattern.
class _ExpandableCaption extends StatelessWidget {
  final String text;
  final bool expanded;
  final VoidCallback onToggle;

  const _ExpandableCaption({
    required this.text,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    const limit = 90;
    final isLong = text.length > limit;
    final visible = expanded || !isLong
        ? text
        : '${text.substring(0, limit).trimRight()}... ';

    return GestureDetector(
      onTap: isLong ? onToggle : null,
      child: Text.rich(
        TextSpan(
          text: visible,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13.2,
            fontWeight: FontWeight.w600,
            height: 1.38,
            shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
          ),
          children: [
            if (isLong)
              TextSpan(
                text: expanded ? '  lebih sedikit' : 'selengkapnya',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.78),
                  fontSize: 12.8,
                  fontWeight: FontWeight.w800,
                ),
              ),
          ],
        ),
        maxLines: expanded ? null : 2,
        overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
      ),
    );
  }
}

/// Video player kalau ada videoUrl, fallback thumbnail kalau tidak.
class _MediaBackground extends StatelessWidget {
  final FeedPost post;
  final VideoPlayerController? videoController;

  const _MediaBackground({
    required this.post,
    required this.videoController,
  });

  @override
  Widget build(BuildContext context) {
    final ctrl = videoController;
    // Layer 0: Blurhash LQIP placeholder — instant decode dari string ~30
    // byte yang server kirim di thumbnailBlurhash. Selalu render di belakang
    // sebagai safety net supaya tidak pernah lihat bg-black saat thumbnail
    // real masih loading dari Bunny CDN (cold cache, slow network, scroll-
    // snap composite timing). Layer di atas akan cover saat ready.
    final blurhashLayer = _BlurhashPlaceholder(hash: post.thumbnailBlurhash);

    if (ctrl != null && ctrl.value.isInitialized) {
      final size = ctrl.value.size;
      final horizontal = _isHorizontalSize(size) || _isHorizontalPost(post);
      if (horizontal) {
        return Stack(
          fit: StackFit.expand,
          children: [
            blurhashLayer,
            _BlurredFeedBackdrop(thumbnailUrl: post.thumbnailUrl),
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
          blurhashLayer,
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
      if (_isHorizontalPost(post)) {
        return Stack(
          fit: StackFit.expand,
          children: [
            blurhashLayer,
            _BlurredFeedBackdrop(thumbnailUrl: thumb),
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
          blurhashLayer,
          CachedNetworkImage(
            imageUrl: thumb,
            fit: BoxFit.cover,
            // Placeholder transparent supaya blurhash layer terlihat di
            // belakang sampai real thumb loaded.
            placeholder: (_, __) => const SizedBox.shrink(),
            errorWidget: (_, __, ___) => const SizedBox.shrink(),
          ),
        ],
      );
    }
    return blurhashLayer;
  }
}

/// Sprint 1 #5 — Blurhash LQIP placeholder.
///
/// Server (Bunny webhook) generate hash ~30 byte saat thumbnail tersedia,
/// dikirim sebagai `thumbnailBlurhash` di FeedPost JSON. Client decode
/// pakai flutter_blurhash → render canvas yang CSS-scaled jadi smooth
/// blur preview. ZERO network fetch, instant paint.
///
/// Fallback: hash null/invalid → black solid (existing behavior).
class _BlurhashPlaceholder extends StatelessWidget {
  final String? hash;
  const _BlurhashPlaceholder({required this.hash});

  @override
  Widget build(BuildContext context) {
    final h = hash;
    if (h == null || h.isEmpty) {
      return const ColoredBox(color: Colors.black);
    }
    // BlurHash decode + render — pakai default decodingWidth/Height yang
    // kecil (32x32) supaya cepat decode di main thread (~1-3ms). CSS scale
    // up jadi blur smooth.
    return BlurHash(
      hash: h,
      // imageFit: video card umumnya 9:16 portrait, cover supaya fill area.
      imageFit: BoxFit.cover,
      // Fallback color saat hash decode error (rare) — black sesuai theme.
      color: Colors.black,
      // Optional decode resolution tweak — default sudah 32x32 which is
      // sweet spot performance vs detail. Keep default.
    );
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

class _BlurredFeedBackdrop extends StatelessWidget {
  final String? thumbnailUrl;

  const _BlurredFeedBackdrop({required this.thumbnailUrl});

  @override
  Widget build(BuildContext context) {
    final url = thumbnailUrl;
    if (url == null || url.isEmpty) {
      return const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF111827), Colors.black],
          ),
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Transform.scale(
            scale: 1.12,
            child: CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              placeholder: (_, __) => const ColoredBox(color: Colors.black),
              errorWidget: (_, __, ___) =>
                  const ColoredBox(color: Colors.black),
            ),
          ),
        ),
        ColoredBox(color: Colors.black.withValues(alpha: 0.30)),
      ],
    );
  }
}

bool _isHorizontalPost(FeedPost post) {
  final width = post.videoWidth;
  final height = post.videoHeight;
  return width != null && height != null && width > height;
}

bool _isHorizontalSize(Size size) {
  if (size.width <= 0 || size.height <= 0) return false;
  return size.width > size.height;
}

/// Sprint 4 #3 — Scrubbing progress bar.
///
/// Drag horizontal di area progress bar untuk seek video. Saat scrub
/// aktif: bar tinggi 6px (vs 2px normal) supaya touch target jelas, plus
/// thumb dot di posisi current. Drag end → seekTo() ke posisi final.
///
/// Auto-pause selama scrub supaya frame target jelas. Auto-resume saat
/// drag end (kalau sebelumnya playing).
class _FeedVideoProgressBar extends StatefulWidget {
  final VideoPlayerController? controller;

  const _FeedVideoProgressBar({required this.controller});

  @override
  State<_FeedVideoProgressBar> createState() => _FeedVideoProgressBarState();
}

class _FeedVideoProgressBarState extends State<_FeedVideoProgressBar> {
  bool _scrubbing = false;
  double _scrubProgress = 0;
  bool _wasPlayingBeforeScrub = false;

  void _onScrubStart(DragStartDetails details, double width, int duration) {
    final ctrl = widget.controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    AppHaptics.tap();
    _wasPlayingBeforeScrub = ctrl.value.isPlaying;
    if (_wasPlayingBeforeScrub) ctrl.pause();
    setState(() {
      _scrubbing = true;
      _scrubProgress = (details.localPosition.dx / width).clamp(0.0, 1.0);
    });
  }

  void _onScrubUpdate(DragUpdateDetails details, double width) {
    if (!_scrubbing) return;
    setState(() {
      _scrubProgress = (details.localPosition.dx / width).clamp(0.0, 1.0);
    });
  }

  void _onScrubEnd(DragEndDetails details, int duration) {
    if (!_scrubbing) return;
    final ctrl = widget.controller;
    if (ctrl != null && ctrl.value.isInitialized) {
      final targetMs = (_scrubProgress * duration).round();
      ctrl.seekTo(Duration(milliseconds: targetMs));
      if (_wasPlayingBeforeScrub) {
        ctrl.play();
      }
    }
    setState(() => _scrubbing = false);
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    if (ctrl == null) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: ctrl,
      builder: (context, _) {
        final value = ctrl.value;
        final duration = value.duration.inMilliseconds;
        if (!value.isInitialized || duration <= 0) {
          return const SizedBox.shrink();
        }
        final position = value.position.inMilliseconds.clamp(0, duration);
        final naturalProgress = position / duration;
        final progress = _scrubbing ? _scrubProgress : naturalProgress;

        // Touch target area lebih besar dari visible bar — wrap di
        // Container vertical 16px supaya gampang di-grab.
        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (d) => _onScrubStart(d, width, duration),
              onHorizontalDragUpdate: (d) => _onScrubUpdate(d, width),
              onHorizontalDragEnd: (d) => _onScrubEnd(d, duration),
              onHorizontalDragCancel: () {
                if (_scrubbing && _wasPlayingBeforeScrub) {
                  ctrl.play();
                }
                setState(() => _scrubbing = false);
              },
              child: SizedBox(
                height: 16, // extended touch target
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Visible bar — tinggi 2px normal, 6px saat scrub.
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      height: _scrubbing ? 6 : 2,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ColoredBox(
                              color: Colors.white.withValues(alpha: 0.22),
                            ),
                            FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: progress.clamp(0.0, 1.0),
                              child: const ColoredBox(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Thumb dot — visible saat scrubbing aktif.
                    if (_scrubbing)
                      Positioned(
                        left: (width * progress).clamp(0.0, width) - 7,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.32),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
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

  const _PausedVideoControls({
    required this.muted,
    required this.onToggleMute,
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
        Container(
          height: 72,
          width: 72,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.play_arrow_rounded,
            color: Colors.white,
            size: 44,
          ),
        ),
      ],
    );
  }
}

class _PausedFullscreenButton extends StatelessWidget {
  final VoidCallback onTap;

  const _PausedFullscreenButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkResponse(
        onTap: onTap,
        radius: 20,
        child: Container(
          height: 34,
          width: 34,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.42),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(
            Icons.fullscreen_rounded,
            color: Colors.white,
            size: 19,
          ),
        ),
      ),
    );
  }
}

class _ReelsAction extends StatelessWidget {
  final IconData? icon;
  final Widget? iconChild;
  final Color color;
  final int? count;
  final VoidCallback onTap;

  const _ReelsAction({
    this.icon,
    this.iconChild,
    required this.color,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 54,
      child: Material(
        color: Colors.transparent,
        child: InkResponse(
          onTap: onTap,
          radius: 28,
          child: SizedBox(
            height: count == null ? 44 : 60,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                iconChild ??
                    Icon(
                      icon,
                      color: color,
                      size: 38,
                      shadows: const [
                        Shadow(color: Colors.black87, blurRadius: 8),
                      ],
                    ),
                if (count != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    _formatCount(count!),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                      height: 1,
                      shadows: [
                        Shadow(color: Colors.black54, blurRadius: 6),
                      ],
                    ),
                  ),
                ],
              ],
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

class _ReelsCommentGlyph extends StatelessWidget {
  const _ReelsCommentGlyph();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 39,
      width: 39,
      child: CustomPaint(painter: _CommentGlyphPainter()),
    );
  }
}

class _CommentGlyphPainter extends CustomPainter {
  const _CommentGlyphPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.35
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      ..moveTo(size.width * 0.86, size.height * 0.82)
      ..lineTo(size.width * 0.62, size.height * 0.76)
      ..cubicTo(
        size.width * 0.51,
        size.height * 0.81,
        size.width * 0.35,
        size.height * 0.80,
        size.width * 0.24,
        size.height * 0.72,
      )
      ..cubicTo(
        size.width * 0.05,
        size.height * 0.58,
        size.width * 0.04,
        size.height * 0.30,
        size.width * 0.22,
        size.height * 0.16,
      )
      ..cubicTo(
        size.width * 0.38,
        size.height * 0.02,
        size.width * 0.66,
        size.height * 0.03,
        size.width * 0.80,
        size.height * 0.21,
      )
      ..cubicTo(
        size.width * 0.93,
        size.height * 0.38,
        size.width * 0.89,
        size.height * 0.62,
        size.width * 0.72,
        size.height * 0.73,
      )
      ..lineTo(size.width * 0.86, size.height * 0.82)
      ..close();

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
      height: 40,
      width: 40,
      child: CustomPaint(painter: _ShareGlyphPainter()),
    );
  }
}

class _ShareGlyphPainter extends CustomPainter {
  const _ShareGlyphPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.35
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      ..moveTo(size.width * 0.10, size.height * 0.14)
      ..lineTo(size.width * 0.92, size.height * 0.15)
      ..lineTo(size.width * 0.40, size.height * 0.88)
      ..lineTo(size.width * 0.30, size.height * 0.48)
      ..lineTo(size.width * 0.92, size.height * 0.15)
      ..moveTo(size.width * 0.30, size.height * 0.48)
      ..lineTo(size.width * 0.10, size.height * 0.14);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ReelsBagGlyph extends StatelessWidget {
  const _ReelsBagGlyph();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 40,
      width: 40,
      child: CustomPaint(painter: _BagGlyphPainter()),
    );
  }
}

class _BagGlyphPainter extends CustomPainter {
  const _BagGlyphPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.35
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.20,
        size.height * 0.34,
        size.width * 0.60,
        size.height * 0.52,
      ),
      Radius.circular(size.width * 0.08),
    );
    canvas.drawRRect(body, paint);

    final handle = Path()
      ..moveTo(size.width * 0.36, size.height * 0.35)
      ..cubicTo(
        size.width * 0.36,
        size.height * 0.20,
        size.width * 0.64,
        size.height * 0.20,
        size.width * 0.64,
        size.height * 0.35,
      );
    canvas.drawPath(handle, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ProductLinkChip extends StatelessWidget {
  final List<FeedProductLink> products;
  final FeedProductLink featuredProduct;
  final int featuredIndex;
  final VoidCallback onTap;
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
    final hasMultiple = products.length > 1;
    final quickAddEnabled =
        onQuickAdd != null && product.isAvailable && product.stock > 0;
    final pricing = _feedProductPricing(product);
    final promo = pricing.hasPromo ? pricing : null;
    final kicker = hasMultiple
        ? 'Produk ${featuredIndex + 1}/${products.length} di video'
        : 'Produk di video';
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 316),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.50),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: InkWell(
                onTap: onTap,
                borderRadius:
                    const BorderRadius.horizontal(left: Radius.circular(14)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(7, 7, 7, 7),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          height: 32,
                          width: 32,
                          child: product.imageUrl == null
                              ? Container(
                                  color: Colors.white.withValues(alpha: 0.12),
                                  child: const Icon(
                                    Icons.shopping_bag_outlined,
                                    color: Colors.white,
                                    size: 17,
                                  ),
                                )
                              : product.imageUrl!.startsWith('assets/')
                                  ? Image.asset(product.imageUrl!,
                                      fit: BoxFit.cover)
                                  : CachedNetworkImage(
                                      imageUrl: product.imageUrl!,
                                      fit: BoxFit.cover,
                                      errorWidget: (_, __, ___) => Container(
                                        color: Colors.white
                                            .withValues(alpha: 0.12),
                                        child: const Icon(
                                          Icons.shopping_bag_outlined,
                                          color: Colors.white,
                                          size: 17,
                                        ),
                                      ),
                                    ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              kicker,
                              maxLines: 1,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                height: 1,
                              ),
                            ),
                            const SizedBox(height: 3),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 260),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              transitionBuilder: (child, animation) {
                                return FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(0, 0.18),
                                      end: Offset.zero,
                                    ).animate(animation),
                                    child: child,
                                  ),
                                );
                              },
                              child: Text(
                                product.name,
                                key: ValueKey(product.id),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12.2,
                                  fontWeight: FontWeight.w900,
                                  height: 1,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (promo != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFFE94B5F).withValues(alpha: 0.88),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'PROMO ${promo.discountPercent}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w900,
                              height: 1,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.white70,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              height: 46,
              width: 40,
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
                ),
              ),
              child: InkResponse(
                onTap: quickAddEnabled ? onQuickAdd : null,
                radius: 22,
                child: Icon(
                  product.hasVariants
                      ? Icons.tune_rounded
                      : Icons.add_shopping_cart_rounded,
                  color: quickAddEnabled
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.28),
                  size: product.hasVariants ? 18 : 19,
                  shadows: const [
                    Shadow(color: Colors.black54, blurRadius: 6),
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
                const SizedBox(height: 16),
                const Text(
                  'Produk di Video',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${products.length} produk ditag di video ini.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.58),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
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
                children: [
                  _FeedProductThumb(url: product.imageUrl),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
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
                            ),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: Colors.white54,
                              size: 20,
                            ),
                          ],
                        ),
                        const SizedBox(height: 7),
                        Wrap(
                          spacing: 7,
                          runSpacing: 5,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              formatRupiah(pricing.displayPrice),
                              style: const TextStyle(
                                color: _officialGold,
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            if (pricing.hasPromo) ...[
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
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE94B5F)
                                      .withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: const Color(0xFFE94B5F)
                                        .withValues(alpha: 0.30),
                                  ),
                                ),
                                child: Text(
                                  'PROMO ${pricing.discountPercent}%',
                                  style: const TextStyle(
                                    color: Color(0xFFFECACA),
                                    fontSize: 9.8,
                                    fontWeight: FontWeight.w900,
                                    height: 1,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 7),
                        Text(
                          unavailable
                              ? 'Produk tidak tersedia'
                              : 'Stok tersedia: ${product.stock}',
                          style: TextStyle(
                            color: unavailable
                                ? const Color(0xFFF87171)
                                : const Color(0xFF34D399),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
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
    return SizedBox(
      height: 45,
      width: 45,
      child: IconButton(
        onPressed: enabled ? onPressed : null,
        style: IconButton.styleFrom(
          backgroundColor:
              Colors.white.withValues(alpha: enabled ? 0.10 : 0.04),
          foregroundColor:
              Colors.white.withValues(alpha: enabled ? 0.92 : 0.28),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.28),
          side: BorderSide(
            color: _officialGold.withValues(alpha: enabled ? 0.34 : 0.08),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(17),
          ),
        ),
        icon: const Icon(Icons.add_shopping_cart_rounded, size: 20),
      ),
    );
  }
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
  final VoidCallback onCheckout;
  final VoidCallback onOpenFullCart;

  const _FeedCartSheet({
    required this.onCheckout,
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
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Keranjang',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: onOpenFullCart,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white70,
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text(
                            'Lihat penuh',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      itemCount > 0
                          ? '$itemCount item siap checkout dari Feed.'
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
                            onPressed: items.isEmpty ? null : onCheckout,
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                              disabledBackgroundColor:
                                  Colors.white.withValues(alpha: 0.14),
                              disabledForegroundColor:
                                  Colors.white.withValues(alpha: 0.42),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 22,
                                vertical: 13,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: const Text(
                              'Checkout',
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
    final canAdd = item.quantity < item.effectiveStock;
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
                        formatRupiah(item.lineTotal),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _officialGold,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    _FeedCartQtyButton(
                      icon: Icons.remove_rounded,
                      enabled: item.quantity > 1,
                      onTap: () =>
                          cartStore.updateQuantity(item.key, item.quantity - 1),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        '${item.quantity}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    _FeedCartQtyButton(
                      icon: Icons.add_rounded,
                      enabled: canAdd,
                      onTap: () =>
                          cartStore.updateQuantity(item.key, item.quantity + 1),
                    ),
                    const SizedBox(width: 2),
                    _FeedCartQtyButton(
                      icon: Icons.close_rounded,
                      enabled: true,
                      danger: true,
                      onTap: () => cartStore.remove(item.key),
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

class _FeedCartQtyButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final bool danger;
  final VoidCallback onTap;

  const _FeedCartQtyButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? const Color(0xFFFCA5A5) : Colors.white;
    return InkResponse(
      onTap: enabled ? onTap : null,
      radius: 18,
      child: Container(
        height: 27,
        width: 27,
        decoration: BoxDecoration(
          color: color.withValues(alpha: enabled ? 0.10 : 0.035),
          shape: BoxShape.circle,
          border: Border.all(
            color: color.withValues(alpha: enabled ? 0.18 : 0.06),
          ),
        ),
        child: Icon(
          icon,
          color: color.withValues(alpha: enabled ? 0.90 : 0.26),
          size: 17,
        ),
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
  final double originalPrice;
  final double displayPrice;
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
    price: pricing.originalPrice,
    discountPrice: pricing.hasPromo ? pricing.displayPrice : link.discountPrice,
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
                                icon: Icons.inventory_2_outlined,
                                label: !unavailable
                                    ? 'Stok ${product.stock}'
                                    : 'Stok habis',
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

/// Keep Product import referenced (untuk type-safety navigation arguments).
// ignore: unused_element
Product? _typeHint() => null;

import 'package:flutter/material.dart';

import '../features/feed/widgets/feed_video_post_view.dart';
import '../models/feed_post.dart';
import '../state/feed_store.dart';

/// Immersive, vertically swipeable video viewer scoped to a caller-
/// supplied list of videos (e.g. "videos tagged to this product", or
/// "videos posted by this user"). Reuses [FeedVideoPostView] so visuals
/// are identical to the main Feed tab. Swiping never leaves [posts].
class ScopedVideoFeedScreen extends StatefulWidget {
  final List<FeedPost> posts;
  final int initialIndex;

  const ScopedVideoFeedScreen({
    super.key,
    required this.posts,
    required this.initialIndex,
  });

  @override
  State<ScopedVideoFeedScreen> createState() => _ScopedVideoFeedScreenState();
}

class _ScopedVideoFeedScreenState extends State<ScopedVideoFeedScreen>
    with SingleTickerProviderStateMixin {
  late final PageController _pageController;
  late final AnimationController _horizontalDismissController;
  late int _activeIndex;
  // Guard supaya overscroll-dismiss cuma pop SEKALI per gesture.
  bool _dismissing = false;
  double _horizontalDragOffset = 0;
  Offset? _pointerDownPosition;
  Offset? _lastPointerPosition;
  bool _horizontalGestureActive = false;
  bool _horizontalGestureRejected = false;

  /// Seberapa jauh (px) user harus menarik melewati batas atas (video
  /// pertama) sebelum viewer menutup — ala IG Reels dari profil: tarik
  /// turun di reel pertama = kembali ke halaman sebelumnya.
  static const double _dismissOverscroll = 72;
  static const double _horizontalDismissFraction = 0.24;

  @override
  void initState() {
    super.initState();
    _activeIndex = widget.initialIndex.clamp(0, widget.posts.length - 1);
    _pageController = PageController(initialPage: _activeIndex);
    _horizontalDismissController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() {
        if (!mounted) return;
        setState(() {
          _horizontalDragOffset = _horizontalDismissController.value *
              MediaQuery.sizeOf(context).width;
        });
      });
    feedStore.seed(widget.posts);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _horizontalDismissController.dispose();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_dismissing) return;
    _pointerDownPosition = event.position;
    _lastPointerPosition = event.position;
    _horizontalGestureActive = false;
    _horizontalGestureRejected = false;
    _horizontalDismissController.stop();
  }

  void _onPointerMove(PointerMoveEvent event) {
    final start = _pointerDownPosition;
    final last = _lastPointerPosition;
    if (start == null || last == null || _dismissing) return;
    final total = event.position - start;
    final delta = event.position - last;
    _lastPointerPosition = event.position;
    if (!_horizontalGestureActive && !_horizontalGestureRejected) {
      if (total.distance < 8) return;
      // A diagonal/left gesture belongs to the video PageView or its own
      // controls. Once rejected, never reinterpret it as a back gesture.
      if (total.dx <= 0 || total.dx.abs() < total.dy.abs()) {
        _horizontalGestureRejected = true;
        return;
      }
      _horizontalGestureActive = true;
    }
    if (!_horizontalGestureActive || delta.dx <= 0) return;
    final next = (_horizontalDragOffset + delta.dx).clamp(
      0.0,
      MediaQuery.sizeOf(context).width,
    );
    if (next != _horizontalDragOffset) {
      setState(() => _horizontalDragOffset = next);
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (!_horizontalGestureActive || _dismissing) {
      _resetPointerGesture();
      return;
    }
    _resetPointerGesture();
    final width = MediaQuery.sizeOf(context).width;
    final shouldDismiss =
        _horizontalDragOffset >= width * _horizontalDismissFraction;
    if (shouldDismiss) {
      _dismissing = true;
      _horizontalDismissController.value =
          (_horizontalDragOffset / width).clamp(0.0, 1.0);
      _horizontalDismissController.animateTo(1).then((_) {
        if (mounted) Navigator.maybePop(context);
      });
      return;
    }
    _horizontalDismissController.value = (_horizontalDragOffset / width).clamp(
      0.0,
      1.0,
    );
    _horizontalDismissController.animateTo(0).then((_) {
      if (mounted) setState(() => _horizontalDragOffset = 0);
    });
  }

  void _onPointerCancel(PointerCancelEvent _) {
    if (_horizontalGestureActive && !_dismissing) {
      _horizontalDismissController.value =
          (_horizontalDragOffset / MediaQuery.sizeOf(context).width)
              .clamp(0.0, 1.0);
      _horizontalDismissController.animateTo(0).then((_) {
        if (mounted) setState(() => _horizontalDragOffset = 0);
      });
    }
    _resetPointerGesture();
  }

  void _resetPointerGesture() {
    _pointerDownPosition = null;
    _lastPointerPosition = null;
    _horizontalGestureActive = false;
    _horizontalGestureRejected = false;
  }

  void _onPageChanged(int index) {
    setState(() => _activeIndex = index);
  }

  /// Tarik-turun melewati batas atas (BouncingScrollPhysics → pixels <
  /// minScrollExtent) saat jari masih di layar (dragDetails != null,
  /// supaya animasi bounce-back setelah lepas tidak ikut memicu) →
  /// tutup viewer. Mentok bawah dibiarkan stuck (sesuai spec).
  bool _onScrollNotification(ScrollNotification notification) {
    if (_dismissing) return false;
    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      final metrics = notification.metrics;
      if (metrics.pixels < metrics.minScrollExtent - _dismissOverscroll) {
        _dismissing = true;
        Navigator.maybePop(context);
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final progress =
        width == 0 ? 0.0 : (_horizontalDragOffset / width).clamp(0.0, 1.0);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Listener(
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        child: Transform.translate(
          offset: Offset(_horizontalDragOffset, 0),
          child: Opacity(
            opacity: 1 - (progress * 0.28),
            child: Stack(
              fit: StackFit.expand,
              children: [
                NotificationListener<ScrollNotification>(
                  onNotification: _onScrollNotification,
                  child: PageView.builder(
                    controller: _pageController,
                    scrollDirection: Axis.vertical,
                    physics: const PageScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    itemCount: widget.posts.length,
                    onPageChanged: _onPageChanged,
                    itemBuilder: (context, index) {
                      final post = widget.posts[index];
                      return FeedVideoPostView(
                        post: post,
                        isActive: index == _activeIndex,
                        preloadedController: null,
                        preloadedCachedPlayer: null,
                        onOverlayStateChanged: (_) {},
                        onMediaZoomChanged: (_) {},
                      );
                    },
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        color: Colors.black.withValues(alpha: 0.35),
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => Navigator.maybePop(context),
                          child: const SizedBox(
                            width: 40,
                            height: 40,
                            child: Icon(
                              Icons.chevron_left_rounded,
                              color: Colors.white,
                              size: 26,
                            ),
                          ),
                        ),
                      ),
                    ),
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

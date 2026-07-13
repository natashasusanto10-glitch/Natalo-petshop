import 'package:flutter/material.dart';

import '../features/feed/video/post_video_coordinator.dart';
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

  /// Coordinator handoff (§2.6) — di-set HANYA saat viewer dibuka dari alur
  /// Postingan (MemberPostDetailScreen). Kalau non-null, item video ASAL
  /// ([originPostId]) meminjam controller coordinator (tanpa init ulang →
  /// instan). Kalau null → perilaku lama (tiap item init controller sendiri).
  ///
  /// TODO(T3b): integrasi penuh — attach item asal ke sesi coordinator
  /// (`ownsController:false, playbackManagedExternally:true`), pakai slot
  /// preload untuk item next, dan laporkan item aktif + route visibility ke
  /// coordinator. Di T3a param ini SEKADAR seam: viewer masih fallback
  /// (init controller sendiri) walau param di-set.
  final PostVideoCoordinator? coordinator;

  /// Id post video ASAL (yang di-tap di Postingan) — pinned di coordinator
  /// selama viewer terbuka. Null kalau bukan alur Postingan. Lihat
  /// [coordinator]. Dipakai penuh di T3b.
  final String? originPostId;

  const ScopedVideoFeedScreen({
    super.key,
    required this.posts,
    required this.initialIndex,
    this.coordinator,
    this.originPostId,
  });

  @override
  State<ScopedVideoFeedScreen> createState() => _ScopedVideoFeedScreenState();
}

class _ScopedVideoFeedScreenState extends State<ScopedVideoFeedScreen> {
  late final PageController _pageController;
  late int _activeIndex;
  // Guard supaya overscroll-dismiss cuma pop SEKALI per gesture.
  bool _dismissing = false;

  /// Seberapa jauh (px) user harus menarik melewati batas atas (video
  /// pertama) sebelum viewer menutup — ala IG Reels dari profil: tarik
  /// turun di reel pertama = kembali ke halaman sebelumnya.
  static const double _dismissOverscroll = 72;

  @override
  void initState() {
    super.initState();
    _activeIndex = widget.initialIndex.clamp(0, widget.posts.length - 1);
    _pageController = PageController(initialPage: _activeIndex);
    feedStore.seed(widget.posts);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: _onScrollNotification,
            child: PageView.builder(
              controller: _pageController,
              scrollDirection: Axis.vertical,
              physics: const PageScrollPhysics(parent: BouncingScrollPhysics()),
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
                      child: Icon(Icons.chevron_left_rounded,
                          color: Colors.white, size: 26),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

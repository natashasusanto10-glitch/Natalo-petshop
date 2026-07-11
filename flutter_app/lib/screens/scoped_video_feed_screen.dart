import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

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

class _ScopedVideoFeedScreenState extends State<ScopedVideoFeedScreen> {
  late final PageController _pageController;
  late int _activeIndex;
  final Map<String, VideoPlayerController> _preloadedControllers = {};
  final Map<String, CachedVideoPlayerPlus> _preloadedCachedPlayers = {};

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
    for (final c in _preloadedCachedPlayers.values) {
      c.dispose();
    }
    for (final c in _preloadedControllers.values) {
      // Only dispose controllers that were never claimed by a
      // CachedVideoPlayerPlus wrapper above (avoid double-dispose).
      if (!_preloadedCachedPlayers.values.any((w) => w.controller == c)) {
        c.dispose();
      }
    }
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() => _activeIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
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
                preloadedController: _preloadedControllers.remove(post.id),
                preloadedCachedPlayer: _preloadedCachedPlayers.remove(post.id),
                onOverlayStateChanged: (_) {},
                onMediaZoomChanged: (_) {},
              );
            },
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
                      child: Icon(Icons.chevron_left_rounded, color: Colors.white, size: 26),
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

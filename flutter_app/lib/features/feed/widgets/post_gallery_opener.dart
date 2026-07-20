import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/feed_post.dart';
import '../../../screens/member_post_detail_screen.dart';
import '../../../screens/scoped_video_feed_screen.dart' show ScopedPostPageLoader;
import '../../../services/video_quality_service.dart';
import '../../../state/settings_store.dart';
import '../../../utils/haptics.dart';
import '../../../widgets/origin_expansion_route.dart';
import '../transition/post_detail_transition_session.dart';
import '../transition/post_page_zoom_route.dart';
import '../video/post_video_warm_handoff.dart';

/// Bundle a caller supplies (via [PostGalleryOpener.openPostGallery]'s optional
/// `transitionSessionFactory`) to open Postingan through the full-page zoom
/// route instead of the legacy origin-expansion route. The caller owns the
/// [PostDetailTransitionSession] it builds; [onClosed] runs AFTER the session
/// is disposed and is where the caller consumes any pending return + releases
/// its source adapter (mirrors the Own/Public Profile wiring order).
class PostGalleryZoomSession {
  const PostGalleryZoomSession({required this.session, required this.onClosed});

  final PostDetailTransitionSession session;
  final void Function() onClosed;
}

/// Builds a fresh [PostGalleryZoomSession] for [post] at tap time.
typedef PostGalleryZoomSessionFactory = PostGalleryZoomSession Function(
  FeedPost post,
);

/// Alur buka post ala halaman Postingan: tile-key untuk origin-expansion,
/// warm video handoff (buka video instan), dan push `MemberPostDetailScreen`
/// dengan daftar penuh + initialIndex. Dipakai bersama supaya Postingan
/// Tersimpan identik dengan Postingan Saya.
mixin PostGalleryOpener<T extends StatefulWidget> on State<T> {
  final Map<String, GlobalKey> _tileKeys = {};
  bool _openingPost = false;
  PostVideoWarmHandoff? _preparedHandoff;
  String? _preparedPostId;

  GlobalKey tileKeyFor(String postId) =>
      _tileKeys.putIfAbsent(postId, GlobalKey.new);

  PostVideoWarmHandoff? _createWarmHandoff(FeedPost post) {
    return PostVideoWarmHandoff.createIfVideo(
      isVideo: post.isVideo,
      postId: post.id,
      url: videoQualityService.resolvePlaybackUrl(
        post.videoPlaybackUrl,
        dataSaverUrl: post.videoDataSaverUrl,
        userPreference: appSettingsStore.feedVideoQuality,
      ),
      hasAudio: post.hasAudio != false,
    );
  }

  void preparePostVideo(FeedPost post) {
    if (_openingPost || !post.isVideo || _preparedPostId == post.id) return;
    final stale = _preparedHandoff;
    _preparedHandoff = _createWarmHandoff(post);
    _preparedPostId = _preparedHandoff == null ? null : post.id;
    unawaited(stale?.disposeIfUnclaimed());
  }

  void cancelPreparedPost([String? postId]) {
    if (postId != null && _preparedPostId != postId) return;
    final stale = _preparedHandoff;
    _preparedHandoff = null;
    _preparedPostId = null;
    unawaited(stale?.disposeIfUnclaimed());
  }

  PostVideoWarmHandoff? _takePreparedPost(FeedPost post) {
    if (_preparedPostId != post.id) {
      cancelPreparedPost();
      return null;
    }
    final handoff = _preparedHandoff;
    _preparedHandoff = null;
    _preparedPostId = null;
    return handoff;
  }

  /// Opens Postingan for [posts]\[index].
  ///
  /// When [transitionSessionFactory] is null the behavior is EXACTLY the legacy
  /// origin-expansion path (entry haptic + `pushOriginExpansion`) — this is the
  /// Postingan Tersimpan (Saved Posts) path, unchanged. When a factory is
  /// supplied (Postingan Saya) the tap opens through [pushPostPageZoom] with the
  /// caller's [PostDetailTransitionSession] — the SAME route type as Own/Public
  /// Profile — and emits NO entry haptic. The caller's `onClosed` runs after the
  /// session is disposed (pending-return + adapter release).
  Future<void> openPostGallery({
    required List<FeedPost> posts,
    required int index,
    required ScopedPostPageLoader loadMore,
    required bool authorIsOfficial,
    required bool isOwner,
    bool authorPerPost = false,
    String? initialNextCursor,
    PostGalleryZoomSessionFactory? transitionSessionFactory,
  }) async {
    if (_openingPost) return;
    _openingPost = true;
    final post = posts[index];
    final handoff = _takePreparedPost(post) ?? _createWarmHandoff(post);
    final zoom = transitionSessionFactory?.call(post);
    try {
      if (zoom == null) {
        // Legacy origin-expansion path (Saved Posts) — byte-for-byte unchanged.
        AppHaptics.tap();
        final originKey = tileKeyFor(post.id);
        await pushOriginExpansion<void>(
          context,
          originKey: originKey,
          destinationBuilder: (_) => MemberPostDetailScreen(
            post: post,
            posts: posts,
            initialIndex: index,
            authorIsOfficial: authorIsOfficial,
            isOwner: isOwner,
            authorPerPost: authorPerPost,
            warmVideoHandoff: handoff,
            initialNextCursor: initialNextCursor,
            loadMoreScopedPosts: loadMore,
          ),
        );
      } else {
        // Full-page zoom path (Postingan Saya) — no entry haptic.
        await pushPostPageZoom(
          context,
          session: zoom.session,
          destinationBuilder: (_) => MemberPostDetailScreen(
            post: post,
            posts: posts,
            initialIndex: index,
            authorIsOfficial: authorIsOfficial,
            isOwner: isOwner,
            authorPerPost: authorPerPost,
            warmVideoHandoff: handoff,
            initialNextCursor: initialNextCursor,
            loadMoreScopedPosts: loadMore,
            transitionSession: zoom.session,
          ),
        );
      }
    } finally {
      if (zoom != null) {
        // Order mirrors Own/Public Profile: dispose the session first (its
        // dispose still routes tile restoration through the live adapter), then
        // let the caller consume the pending return + release the adapter.
        zoom.session.dispose();
        zoom.onClosed();
      }
      await handoff?.disposeIfUnclaimed();
      _openingPost = false;
    }
  }
}

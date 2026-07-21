import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/feed_post.dart';
import '../../../screens/member_post_detail_screen.dart';
import '../../../screens/scoped_video_feed_screen.dart'
    show ScopedPostPageLoader;
import '../../../services/video_quality_service.dart';
import '../../../state/settings_store.dart';
import '../../../utils/haptics.dart';
import '../transition/post_viewer_route.dart';
import '../transition/profile_tile_visibility.dart';
import '../video/post_video_warm_handoff.dart';

/// Alur buka post ala halaman Postingan: tile-key untuk hero + reveal-on-
/// close, warm video handoff (buka video instan), dan push
/// `MemberPostDetailScreen` via `PostViewerRoute` (native transition + hero
/// media) dengan daftar penuh + initialIndex. Dipakai bersama supaya
/// Postingan Tersimpan identik dengan Postingan Saya.
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

  Future<void> openPostGallery({
    required List<FeedPost> posts,
    required int index,
    required ScopedPostPageLoader loadMore,
    required bool authorIsOfficial,
    required bool isOwner,
    required String heroScope,
    bool authorPerPost = false,
    String? initialNextCursor,
  }) async {
    if (_openingPost) return;
    _openingPost = true;
    AppHaptics.tap();
    final post = posts[index];
    final handoff = _takePreparedPost(post) ?? _createWarmHandoff(post);
    try {
      await pushPostViewer<void>(
        context,
        builder: (_) => MemberPostDetailScreen(
          post: post,
          posts: posts,
          initialIndex: index,
          authorIsOfficial: authorIsOfficial,
          isOwner: isOwner,
          authorPerPost: authorPerPost,
          warmVideoHandoff: handoff,
          initialNextCursor: initialNextCursor,
          loadMoreScopedPosts: loadMore,
          heroScope: heroScope,
          onWillClose: _revealTile,
        ),
      );
    } finally {
      await handoff?.disposeIfUnclaimed();
      _openingPost = false;
    }
  }

  /// Dipanggil sinkron saat viewer pop, dengan id post yang sedang tampil.
  /// Fire-and-forget. Mixin tidak punya akses scroll controller pemanggil,
  /// jadi hanya reveal via tile-key kalau tile-nya sudah ter-build di
  /// viewport (tanpa fallback estimasi-index seperti di member_posts_screen).
  void _revealTile(String activePostId) {
    final ctx = tileKeyFor(activePostId).currentContext;
    if (ctx == null) return;
    unawaited(ensureProfileTileVisible(ctx, bottomPadding: 0));
  }
}

// ignore_for_file: use_build_context_synchronously
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shimmer/shimmer.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../config/api_config.dart';
import '../models/feed_comment.dart';
import '../models/feed_post.dart';
import '../models/my_feed_post.dart';
import '../services/api_client.dart';
import '../services/feed_service.dart';
import '../state/member_store.dart';
import '../theme/natalo_colors.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import '../widgets/app_toast.dart';
import '../widgets/emoji_picker_panel.dart';
import '../widgets/profile_avatar.dart';
import '../shared/widgets/natalo_post_action_icon.dart';

/// Detail Postingan style Instagram Feed — continuous vertical scroll list
/// of user's own posts (Postingan Saya).
///
/// Spec (commit ini):
///  - List vertical menyambung (bukan PageView snap-paginated)
///  - Tap thumbnail di grid → buka detail di post yang di-tap (scroll
///    initial ke post tersebut di paling atas viewport)
///  - Per-post: profile row → media full-width → action row → likes line
///    → caption (kalau ada) → tanggal (hybrid relative/absolute)
///  - Video auto-play muted saat masuk viewport (≥60% visible), auto-
///    pause saat keluar. Tap video → open fullscreen player.
///  - Carousel swipeable horizontal di dalam post.
///  - Like: optimistic toggle + API call.
///  - Comment: bottom sheet overlay (reuse FeedCommentSheet via adapter).
///  - Share: native share sheet (share_plus).
///  - "..." menu: Edit caption + Hapus postingan.
///  - Header subtitle: nama user dari memberStore.profile.name.
class MemberPostDetailScreen extends StatefulWidget {
  final MyFeedPost post;
  final List<MyFeedPost>? posts;
  final int initialIndex;

  const MemberPostDetailScreen({
    super.key,
    required this.post,
    this.posts,
    this.initialIndex = 0,
  });

  @override
  State<MemberPostDetailScreen> createState() => _MemberPostDetailScreenState();
}

class _MemberPostDetailScreenState extends State<MemberPostDetailScreen> {
  late final ScrollController _scrollController;
  late List<MyFeedPost> _posts;
  // Track liked state per post id — optimistic toggle, source-of-truth
  // sampai backend respons confirm.
  final Map<String, bool> _likedCache = {};
  // GlobalKey per post supaya initial scroll bisa pakai
  // Scrollable.ensureVisible — akurat 100% vs estimate-based offset yang
  // dulu sering "lari" (mendarat di posisi salah karena chrome/separator
  // calculation drift dengan layout sesungguhnya).
  late final List<GlobalKey> _postKeys;

  @override
  void initState() {
    super.initState();
    final source = widget.posts;
    _posts = source == null || source.isEmpty
        ? [widget.post]
        : List<MyFeedPost>.from(source);
    _postKeys = List.generate(_posts.length, (_) => GlobalKey());
    _scrollController = ScrollController();
    // Hydrate _likedCache dari backend `viewerLiked` field — tanpa ini,
    // post yang sudah di-like sebelumnya tampil grey di icon, dan tap
    // pertama bakal accidentally UN-LIKE (backend toggle berdasar DB,
    // bukan trust client). Lihat bug "klik like 1x hilang harus klik
    // kedua kali baru bisa di-like".
    for (final post in _posts) {
      _likedCache[post.id] = post.viewerLiked;
    }
    // Jump ke post target setelah first frame settled. Pakai
    // Scrollable.ensureVisible via GlobalKey context — Flutter handle
    // layout precisely, gak ada drift estimasi.
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToInitial());
  }

  void _jumpToInitial() {
    if (widget.initialIndex <= 0 || widget.initialIndex >= _posts.length) {
      return;
    }
    final key = _postKeys[widget.initialIndex];
    final ctx = key.currentContext;
    if (ctx == null) {
      // Item belum ke-render (ListView lazy build). Force scroll dulu ke
      // approximate offset supaya item masuk render tree, lalu ensure
      // visible di frame berikutnya.
      final approxOffset = MediaQuery.of(context).size.height *
          widget.initialIndex.clamp(0, _posts.length - 1).toDouble();
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(
          approxOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
        );
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final c2 = _postKeys[widget.initialIndex].currentContext;
        if (c2 != null) {
          Scrollable.ensureVisible(
            c2,
            duration: Duration.zero,
            alignment: 0.0, // align ke TOP viewport
          );
        }
      });
      return;
    }
    Scrollable.ensureVisible(
      ctx,
      duration: Duration.zero,
      alignment: 0.0,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String get _memberName {
    final name = memberStore.profile?.name.trim();
    return name == null || name.isEmpty ? 'Member Natalo' : name;
  }

  Future<void> _toggleLike(int index) async {
    final post = _posts[index];
    AppHaptics.tap();
    final currentlyLiked = _likedCache[post.id] ?? post.viewerLiked;
    final newLiked = !currentlyLiked;
    // Optimistic update — UI immediately respond.
    setState(() {
      _likedCache[post.id] = newLiked;
      _posts[index] = _withLikeCount(
        post,
        newLiked ? post.likeCount + 1 : (post.likeCount - 1).clamp(0, 999999),
        liked: newLiked,
      );
    });
    // Background sync — kalau gagal, revert.
    try {
      final result = await feedService.toggleLike(
        post.id,
        currentlyLiked: currentlyLiked,
      );
      if (!mounted) return;
      setState(() {
        _likedCache[post.id] = result.liked;
        _posts[index] = _withLikeCount(
          _posts[index],
          result.likeCount,
          liked: result.liked,
        );
      });
    } catch (_) {
      if (!mounted) return;
      // Revert.
      setState(() {
        _likedCache[post.id] = currentlyLiked;
        _posts[index] = _withLikeCount(
          post,
          post.likeCount,
          liked: currentlyLiked,
        );
      });
      AppToast.show(context, 'Gagal update suka, coba lagi');
    }
  }

  Future<void> _shareNative(int index) async {
    AppHaptics.tap();
    final post = _posts[index];
    final url = '${ApiConfig.publicSiteUrl}/feed/${post.slug}';
    final captionSnippet = (post.caption ?? '').trim();
    final text =
        captionSnippet.isEmpty ? url : '${truncate(captionSnippet, 120)}\n$url';
    try {
      final box = context.findRenderObject() as RenderBox?;
      await Share.share(
        text,
        sharePositionOrigin:
            box != null ? box.localToGlobal(Offset.zero) & box.size : null,
      );
      feedService.trackShare(post.id);
    } catch (_) {
      // Fail silent — user cancelled / share sheet error.
    }
  }

  Future<void> _openComments(int index) async {
    AppHaptics.tap();
    final post = _posts[index];
    final profile = memberStore.profile;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _MyPostCommentSheet(
        post: post,
        // Author info — di my-posts viewer = author = self,
        // jadi pakai memberStore.profile sebagai source.
        authorName: _memberName,
        authorAvatarUrl: profile?.profilePhotoUrl,
      ),
    );
  }

  Future<void> _openPostMenu(int index) async {
    AppHaptics.tap();
    final result = await showModalBottomSheet<_PostMenuAction>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _PostMenuSheet(),
    );
    if (result == null || !mounted) return;
    switch (result) {
      case _PostMenuAction.edit:
        await _editCaption(index);
        break;
      case _PostMenuAction.delete:
        await _deletePost(index);
        break;
    }
  }

  Future<void> _editCaption(int index) async {
    final post = _posts[index];
    final controller = TextEditingController(text: post.caption ?? '');
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => _EditCaptionSheet(controller: controller),
    );
    if (result == null || !mounted) return;
    final newCaption = result.trim();
    if (newCaption == (post.caption ?? '').trim()) return;
    try {
      await apiClient.patchJson(
        '/api/feed/posts/${Uri.encodeComponent(post.id)}',
        body: {'description': newCaption},
      );
      if (!mounted) return;
      setState(() {
        _posts[index] = _withCaption(post, newCaption);
      });
      AppToast.show(context, 'Caption diperbarui — menunggu review admin');
    } catch (_) {
      if (!mounted) return;
      AppToast.show(context, 'Gagal update caption, coba lagi');
    }
  }

  Future<void> _deletePost(int index) async {
    final post = _posts[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus postingan?'),
        content: const Text(
          'Postingan akan dihapus permanen. Aksi ini tidak bisa dibatalkan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style:
                TextButton.styleFrom(foregroundColor: const Color(0xFFDC2626)),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final ok = await feedService.deleteMyPost(post.id);
      if (!mounted) return;
      if (ok) {
        setState(() => _posts.removeAt(index));
        AppToast.show(context, 'Postingan dihapus');
        // Kalau list kosong, balik ke grid.
        if (_posts.isEmpty) Navigator.maybePop(context);
      } else {
        AppToast.show(context, 'Gagal hapus postingan');
      }
    } catch (_) {
      if (!mounted) return;
      AppToast.show(context, 'Gagal hapus postingan');
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = memberStore.profile;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        surfaceTintColor: Colors.white,
        leading: IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: NataloColors.textPrimary,
          ),
        ),
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Postingan',
              style: TextStyle(
                color: NataloColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w900,
                height: 1.0,
              ),
            ),
            Text(
              _memberName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: NataloColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
      body: _posts.isEmpty
          ? const Center(
              child: Text(
                'Belum ada postingan',
                style: TextStyle(
                  color: NataloColors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          : ListView.separated(
              controller: _scrollController,
              // Bottom padding extra space supaya post terakhir bisa di-
              // scroll lega ke atas viewport (gak mepet ke home indicator).
              padding: const EdgeInsets.only(top: 0, bottom: 48),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: _posts.length,
              // Whitespace pemisah antar post tetap ada, tapi lebih compact
              // supaya detail terasa seperti feed/post Instagram.
              separatorBuilder: (_, __) => const SizedBox(height: 24),
              itemBuilder: (context, index) {
                final post = _posts[index];
                return _PostFeedItem(
                  // GlobalKey untuk Scrollable.ensureVisible jump akurat
                  // ke post target saat initial open dari grid.
                  key: _postKeys[index],
                  post: post,
                  memberName: _memberName,
                  memberInitial: profile?.initial ?? 'N',
                  memberPhotoUrl: profile?.profilePhotoUrl,
                  liked: _likedCache[post.id] ?? false,
                  onLike: () => _toggleLike(index),
                  onComment: () => _openComments(index),
                  onShare: () => _shareNative(index),
                  onMenuTap: () => _openPostMenu(index),
                );
              },
            ),
    );
  }

  /// Helper rebuild post dengan likeCount + viewerLiked baru — MyFeedPost
  /// immutable jadi kita rekonstruksi (mirip copyWith pattern). `liked`
  /// optional supaya call site lama bisa preserve, sekaligus support fresh
  /// dari backend response (toggleLike return { liked, likeCount }).
  MyFeedPost _withLikeCount(MyFeedPost post, int newCount, {bool? liked}) {
    return MyFeedPost(
      id: post.id,
      slug: post.slug,
      caption: post.caption,
      mediaUrl: post.mediaUrl,
      thumbnailUrl: post.thumbnailUrl,
      type: post.type,
      mediaItems: post.mediaItems,
      blurhash: post.blurhash,
      durationSec: post.durationSec,
      aspectWidth: post.aspectWidth,
      aspectHeight: post.aspectHeight,
      status: post.status,
      rejectionReason: post.rejectionReason,
      likeCount: newCount,
      commentCount: post.commentCount,
      viewCount: post.viewCount,
      viewerLiked: liked ?? post.viewerLiked,
      productIds: post.productIds,
      createdAt: post.createdAt,
      approvedAt: post.approvedAt,
    );
  }

  MyFeedPost _withCaption(MyFeedPost post, String newCaption) {
    return MyFeedPost(
      id: post.id,
      slug: post.slug,
      caption: newCaption.isEmpty ? null : newCaption,
      mediaUrl: post.mediaUrl,
      thumbnailUrl: post.thumbnailUrl,
      type: post.type,
      mediaItems: post.mediaItems,
      blurhash: post.blurhash,
      durationSec: post.durationSec,
      aspectWidth: post.aspectWidth,
      aspectHeight: post.aspectHeight,
      // Edit caption reset status ke PENDING_REVIEW per backend logic.
      status: 'PENDING_REVIEW',
      rejectionReason: post.rejectionReason,
      likeCount: post.likeCount,
      commentCount: post.commentCount,
      viewCount: post.viewCount,
      viewerLiked: post.viewerLiked,
      productIds: post.productIds,
      createdAt: post.createdAt,
      approvedAt: post.approvedAt,
    );
  }
}

// ─── Per-post item ───────────────────────────────────────────────────

class _PostFeedItem extends StatefulWidget {
  final MyFeedPost post;
  final String memberName;
  final String memberInitial;
  final String? memberPhotoUrl;
  final bool liked;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;
  final VoidCallback onMenuTap;

  const _PostFeedItem({
    super.key,
    required this.post,
    required this.memberName,
    required this.memberInitial,
    required this.memberPhotoUrl,
    required this.liked,
    required this.onLike,
    required this.onComment,
    required this.onShare,
    required this.onMenuTap,
  });

  @override
  State<_PostFeedItem> createState() => _PostFeedItemState();
}

class _PostFeedItemState extends State<_PostFeedItem>
    with TickerProviderStateMixin {
  // Heart icon scale-on-tap controller — bouncy pop kecil saat user tap
  // tombol heart di action row. 140ms cepat supaya gak feel laggy.
  late final AnimationController _heartScaleController;
  late final Animation<double> _heartScale;

  // Heart burst controller — big heart pop di tengah image saat user
  // double-tap media. Signature Instagram-style: scale 0.35→1.42→1.0→0
  // dengan opacity fade in/out. 620ms total.
  late final AnimationController _heartBurstController;
  late final Animation<double> _burstScale;
  late final Animation<double> _burstOpacity;

  @override
  void initState() {
    super.initState();
    _heartScaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _heartScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.32)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.32, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 55,
      ),
    ]).animate(_heartScaleController);

    _heartBurstController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );
    _burstScale = TweenSequence<double>([
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
    _burstOpacity = TweenSequence<double>([
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
  }

  @override
  void dispose() {
    _heartScaleController.dispose();
    _heartBurstController.dispose();
    super.dispose();
  }

  void _handleLikeTap() {
    // Pop animation icon — fire dulu sebelum onLike supaya parent yang
    // optimistic toggle bisa di-paint di animation cycle yang sama.
    if (!_heartScaleController.isAnimating) {
      _heartScaleController.forward(from: 0);
    }
    widget.onLike();
  }

  void _handleDoubleTap() {
    // Double-tap = LIKE only (Instagram behavior — tidak un-like).
    // Kalau belum liked, fire onLike. Kalau sudah liked, skip toggle
    // tapi tetap show burst (heart kedap-kedip jadi feedback bahwa
    // user sudah suka).
    AppHaptics.impact();
    if (!widget.liked) {
      _handleLikeTap();
    }
    if (!_heartBurstController.isAnimating) {
      _heartBurstController.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final memberName = widget.memberName;
    final memberInitial = widget.memberInitial;
    final memberPhotoUrl = widget.memberPhotoUrl;
    final liked = widget.liked;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Status badge (pending / rejected) — di ATAS media supaya jelas
        // tanpa harus scroll. Auto-hide kalau published (clean Instagram-feel).
        if (post.statusInfo == MyFeedPostStatus.pending ||
            post.statusInfo == MyFeedPostStatus.rejected) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
            child: _PostStatusBadge(post: post),
          ),
        ],
        // Author row putih di atas media — Instagram posts style.
        // Halaman Postingan Saya memakai list post, bukan Reels, jadi author
        // tidak dioverlay di media agar image/video sama-sama jelas.
        _PostAuthorRow(
          memberName: memberName,
          memberInitial: memberInitial,
          memberPhotoUrl: memberPhotoUrl,
          onMenuTap: widget.onMenuTap,
        ),
        // Double-tap detector wrap media: signature Instagram-feel "tap
        // dua kali untuk like". Single tap ke media tetap fall-through
        // ke gesture detector dalam (mis. _InlineVideoPlayer onTap →
        // fullscreen). PageView swipe horizontal di carousel juga tetap
        // jalan karena swipe ≠ tap gesture.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: _handleDoubleTap,
          child: Stack(
            children: [
              _PostMediaSurface(post: post),
              // Heart burst overlay — big white heart pop di tengah image
              // saat double-tap. Signature Instagram-style. IgnorePointer
              // supaya tidak intercept tap (gesture wrap di luar Stack udah
              // handle double-tap).
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: AnimatedBuilder(
                      animation: _heartBurstController,
                      builder: (context, _) {
                        if (_burstOpacity.value == 0) {
                          return const SizedBox.shrink();
                        }
                        return Opacity(
                          opacity: _burstOpacity.value,
                          child: Transform.scale(
                            scale: _burstScale.value,
                            child: const Icon(
                              Icons.favorite_rounded,
                              color: Colors.white,
                              size: 128,
                              shadows: [
                                Shadow(color: Colors.black54, blurRadius: 28),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Action row di-padding sedikit dari edge.
        // Count di-render inline samping icon (TikTok/Reels style) supaya
        // user langsung lihat berapa like/comment/share. 0 → hide count
        // (icon-only fallback), match IG convention "tidak tampilkan 0".
        // Like count dari _likedCache parent state sudah optimistic, jadi
        // tap heart langsung naik 1 — tidak nunggu round-trip backend.
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: Row(
            children: [
              // Heart icon dibungkus ScaleTransition supaya pop saat di-tap.
              // _handleLikeTap fire animation + delegate ke widget.onLike
              // (yang trigger optimistic update + API call di parent).
              ScaleTransition(
                scale: _heartScale,
                child: NataloPostActionButton(
                  type: NataloPostActionIconType.like,
                  isActive: liked,
                  iconSize: 28,
                  tapSize: 42,
                  count: post.likeCount,
                  semanticLabel: liked ? 'Batalkan suka' : 'Sukai postingan',
                  onTap: _handleLikeTap,
                ),
              ),
              NataloPostActionButton(
                type: NataloPostActionIconType.comment,
                iconSize: 28,
                tapSize: 42,
                count: post.commentCount,
                semanticLabel: 'Buka komentar',
                onTap: widget.onComment,
              ),
              NataloPostActionButton(
                type: NataloPostActionIconType.share,
                iconSize: 28,
                tapSize: 42,
                count: post.shareCount,
                semanticLabel: 'Bagikan postingan',
                onTap: widget.onShare,
              ),
            ],
          ),
        ),
        // Likes line. Auto-hide kalau 0 likes (per spec user).
        if (post.likeCount > 0) ...[
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
            child: _LikedByLine(
              memberName: memberName,
              memberPhotoUrl: memberPhotoUrl,
              memberInitial: memberInitial,
              post: post,
            ),
          ),
        ],
        // Caption — kalau ada saja.
        if ((post.caption ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
            child: _PostCaption(memberName: memberName, caption: post.caption!),
          ),
        ],
        // Tanggal — hybrid format: relative untuk < 7 hari, absolute lebih lama.
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
          child: Text(
            _hybridDateLabel(post.createdAt),
            style: const TextStyle(
              color: NataloColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _PostAuthorRow extends StatelessWidget {
  final String memberName;
  final String memberInitial;
  final String? memberPhotoUrl;
  final VoidCallback onMenuTap;

  const _PostAuthorRow({
    required this.memberName,
    required this.memberInitial,
    required this.memberPhotoUrl,
    required this.onMenuTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      child: Row(
        children: [
          ProfileAvatar(
            initial: memberInitial,
            imageUrl: memberPhotoUrl,
            size: 36,
            fontSize: 15,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              memberName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: NataloColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w900,
                height: 1.15,
              ),
            ),
          ),
          IconButton(
            onPressed: onMenuTap,
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.more_horiz_rounded,
              color: NataloColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

String _hybridDateLabel(DateTime created) {
  final now = DateTime.now();
  final diff = now.difference(created);
  // < 7 hari → relative ("3 jam lalu", "2 hari lalu")
  // ≥ 7 hari → absolute ("12 Mei 2026")
  if (diff.inDays < 7) {
    return formatRelativeTime(created);
  }
  return formatTanggal(created);
}

class _LikedByLine extends StatelessWidget {
  final String memberName;
  final String? memberPhotoUrl;
  final String memberInitial;
  final MyFeedPost post;

  const _LikedByLine({
    required this.memberName,
    required this.memberPhotoUrl,
    required this.memberInitial,
    required this.post,
  });

  @override
  Widget build(BuildContext context) {
    // Wording:
    //  - 1 like  → "Disukai oleh X"
    //  - 2+ like → "Disukai oleh X dan N orang lainnya"
    // (0 like sudah di-hide di parent.)
    //
    // Avatar stack: IG-style mini overlapping circles di kiri text.
    // Saat ini Natalo backend belum return list of recent likers, jadi
    // kita pakai avatar member yang lagi view (self) sebagai placeholder
    // tunggal — kalau ada 2+ likes, tampilkan 2 overlap avatars (self +
    // placeholder N). Future: extend feed posts response dengan
    // recentLikers array untuk avatar yang akurat per-liker.
    final isSelfOnly = post.likeCount == 1;
    final othersCount = post.likeCount - 1;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _LikedAvatarStack(
          memberInitial: memberInitial,
          memberPhotoUrl: memberPhotoUrl,
          hasOthers: !isSelfOnly,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Disukai oleh '),
                TextSpan(
                  text: memberName,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                if (!isSelfOnly) ...[
                  const TextSpan(text: ' dan '),
                  TextSpan(
                    text: '$othersCount orang lainnya',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: NataloColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

/// Mini avatar stack — overlapping circles di kiri "Disukai oleh ..." text.
/// IG-style: 1 avatar kalau 1 like, 2 overlap avatars kalau >1 like.
class _LikedAvatarStack extends StatelessWidget {
  final String memberInitial;
  final String? memberPhotoUrl;
  final bool hasOthers;

  const _LikedAvatarStack({
    required this.memberInitial,
    required this.memberPhotoUrl,
    required this.hasOthers,
  });

  @override
  Widget build(BuildContext context) {
    const size = 22.0;
    // Width yang reserve untuk 1 atau 2 avatar overlap.
    final width = hasOthers ? size + (size * 0.55) : size;
    return SizedBox(
      width: width,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (hasOthers)
            Positioned(
              left: size * 0.55,
              child: _MiniAvatar.placeholder(size: size),
            ),
          Positioned(
            left: 0,
            child: _MiniAvatar.member(
              initial: memberInitial,
              photoUrl: memberPhotoUrl,
              size: size,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniAvatar extends StatelessWidget {
  final double size;
  final String? photoUrl;
  final String? initial;
  final Color? backgroundColor;

  const _MiniAvatar({
    required this.size,
    this.photoUrl,
    this.initial,
    this.backgroundColor,
  });

  factory _MiniAvatar.member({
    required String initial,
    required String? photoUrl,
    required double size,
  }) =>
      _MiniAvatar(size: size, photoUrl: photoUrl, initial: initial);

  factory _MiniAvatar.placeholder({required double size}) => _MiniAvatar(
        size: size,
        backgroundColor: const Color(0xFFD1D5DB),
        initial: '+',
      );

  @override
  Widget build(BuildContext context) {
    final url = photoUrl;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor ?? const Color(0xFFE5E7EB),
        shape: BoxShape.circle,
        // Border putih supaya overlap antar avatar kelihatan jelas.
        border: Border.all(color: Colors.white, width: 1.6),
      ),
      clipBehavior: Clip.antiAlias,
      child: url != null && url.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => _miniAvatarFallback(),
              placeholder: (_, __) => _miniAvatarFallback(),
            )
          : _miniAvatarFallback(),
    );
  }

  Widget _miniAvatarFallback() {
    return Center(
      child: Text(
        initial ?? 'N',
        style: TextStyle(
          color:
              backgroundColor != null ? Colors.white : NataloColors.textPrimary,
          fontSize: size * 0.45,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _PostCaption extends StatelessWidget {
  final String memberName;
  final String caption;

  const _PostCaption({required this.memberName, required this.caption});

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$memberName ',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          TextSpan(text: caption.trim()),
        ],
      ),
      style: const TextStyle(
        color: NataloColors.textPrimary,
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
        height: 1.35,
      ),
    );
  }
}

class _PostStatusBadge extends StatelessWidget {
  final MyFeedPost post;

  const _PostStatusBadge({required this.post});

  @override
  Widget build(BuildContext context) {
    final rejected = post.statusInfo == MyFeedPostStatus.rejected;
    final bg = rejected ? const Color(0xFFFEF2F2) : const Color(0xFFFFF7E6);
    final fg = rejected ? const Color(0xFFDC2626) : const Color(0xFFB45309);
    final label = rejected ? 'Ditolak' : 'Menunggu review';
    final text = rejected
        ? (post.rejectionReason?.trim().isNotEmpty == true
            ? 'Postingan ditolak: ${post.rejectionReason}'
            : 'Postingan ditolak oleh admin.')
        : 'Postingan sedang diperiksa admin sebelum tayang publik.';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fg.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(
            rejected ? Icons.cancel_rounded : Icons.schedule_rounded,
            color: fg,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: NataloColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Media surface — switcher per content type ──────────────────────

class _PostMediaSurface extends StatelessWidget {
  final MyFeedPost post;

  const _PostMediaSurface({required this.post});

  @override
  Widget build(BuildContext context) {
    // Pass type ke aspect calculator — video pakai 3:5 fixed (immersive),
    // photo/carousel pakai source aspect clamped ke 4:5.
    final aspectRatio = _safeAspectRatio(
      post.aspectWidth,
      post.aspectHeight,
      type: post.type,
    );
    // Hero destination — wraps photo (single & carousel cover) dengan tag
    // sama dengan _PostThumbnail di member_screen grid: 'post-thumb-${id}'.
    // Saat user tap thumb di grid, image fly + scale ke posisi ini.
    // Video skip (VideoPlayer destination tidak compatible).
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: switch (post.type) {
        MyFeedPostType.video => _InlineVideoPlayer(
            postId: post.id,
            mediaUrl: post.previewMediaUrl,
            thumbnailUrl: post.thumbnailUrl,
            aspectRatio: aspectRatio,
          ),
        MyFeedPostType.carousel => Hero(
            tag: 'post-thumb-${post.id}',
            child: _CarouselSurface(
              post: post,
              aspectRatio: aspectRatio,
            ),
          ),
        MyFeedPostType.photo => Hero(
            tag: 'post-thumb-${post.id}',
            child: _ImageSurface(
              imageUrl: post.previewMediaUrl,
              placeholderIcon: Icons.image_outlined,
            ),
          ),
      },
    );
  }
}

class _CarouselSurface extends StatefulWidget {
  final MyFeedPost post;
  final double aspectRatio;

  const _CarouselSurface({required this.post, required this.aspectRatio});

  @override
  State<_CarouselSurface> createState() => _CarouselSurfaceState();
}

class _CarouselSurfaceState extends State<_CarouselSurface> {
  int _index = 0;

  List<MyFeedMediaItem> get _items {
    if (widget.post.mediaItems.isNotEmpty) return widget.post.mediaItems;
    if (widget.post.previewMediaUrl.isEmpty) return const [];
    return [
      MyFeedMediaItem(
        id: '${widget.post.id}-fallback',
        mediaUrl: widget.post.previewMediaUrl,
        thumbnailUrl: widget.post.thumbnailUrl,
        mediaType:
            widget.post.isVideo ? MyFeedMediaType.video : MyFeedMediaType.image,
        durationSeconds: widget.post.durationSec,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items.isEmpty) {
      return const _MediaPlaceholder(icon: Icons.collections_outlined);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          itemCount: items.length,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (context, index) {
            final item = items[index];
            if (item.mediaType == MyFeedMediaType.video) {
              return _InlineVideoPlayer(
                postId: '${widget.post.id}-$index',
                mediaUrl: item.mediaUrl,
                thumbnailUrl: item.thumbnailUrl,
                aspectRatio: widget.aspectRatio,
              );
            }
            return _ImageSurface(
              imageUrl: item.mediaUrl,
              placeholderIcon: Icons.image_outlined,
            );
          },
        ),
        // Indicator "1/3" pojok kanan atas — Instagram pattern.
        Positioned(
          top: 12,
          right: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.50),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${_index + 1}/${items.length}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        // Dot indicator di bawah — extra UX cue selain "1/3".
        Positioned(
          bottom: 10,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(items.length, (i) {
              final active = i == _index;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: active ? 8 : 6,
                height: active ? 8 : 6,
                decoration: BoxDecoration(
                  color: active
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

// ─── Image / placeholder ────────────────────────────────────────────

class _ImageSurface extends StatelessWidget {
  final String imageUrl;
  final IconData placeholderIcon;

  const _ImageSurface({
    required this.imageUrl,
    required this.placeholderIcon,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl.trim().isEmpty) {
      return _MediaPlaceholder(icon: placeholderIcon);
    }
    // BoxFit.cover — per spec sheet final dari user (post landscape, post
    // portrait, post video semua bilang "Object fit: cover"). Aspect
    // ratio sudah follow source via _safeAspectRatio clamp (0.8-1.91):
    //   - 4:3 landscape source → preserved 4:3 display, no crop
    //   - 4:5 portrait source → preserved 4:5, no crop
    //   - 16:9 landscape → preserved, no crop
    //   - Tall phone screenshot 9:19.5 → clamped ke 4:5 + center crop
    //     (top/bottom hidden, sesuai IG behavior untuk tall content)
    //
    // Sempat ganti ke contain di v1.0.45 atas hipotesis "IG fit no crop".
    // Tapi spec final dari user konsisten cover di semua spec sheet —
    // override hypothesis. Revert ke cover.
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        fadeInDuration: const Duration(milliseconds: 200),
        placeholder: (_, __) => Shimmer.fromColors(
          baseColor: const Color(0xFF1F2937),
          highlightColor: const Color(0xFF374151),
          child: Container(color: const Color(0xFF1F2937)),
        ),
        errorWidget: (_, __, ___) => _MediaPlaceholder(icon: placeholderIcon),
      ),
    );
  }
}

class _MediaPlaceholder extends StatelessWidget {
  final IconData icon;

  const _MediaPlaceholder({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF111827),
      child: Center(
        child: Icon(icon, color: Colors.white24, size: 72),
      ),
    );
  }
}

// ─── Inline video player — auto-play muted in viewport, tap → fullscreen ─

class _InlineVideoPlayer extends StatefulWidget {
  final String postId;
  final String mediaUrl;
  final String? thumbnailUrl;
  final double aspectRatio;

  const _InlineVideoPlayer({
    required this.postId,
    required this.mediaUrl,
    required this.thumbnailUrl,
    required this.aspectRatio,
  });

  @override
  State<_InlineVideoPlayer> createState() => _InlineVideoPlayerState();
}

class _InlineVideoPlayerState extends State<_InlineVideoPlayer> {
  VideoPlayerController? _controller;
  bool _initializing = false;
  String? _error;
  // Track viewport visibility to drive auto-play (≥60% visible).
  double _visibleFraction = 0;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  Future<void> _initialize() async {
    if (widget.mediaUrl.trim().isEmpty) {
      if (mounted) setState(() => _error = 'Video tidak tersedia');
      return;
    }
    setState(() {
      _initializing = true;
      _error = null;
    });
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.mediaUrl),
    );
    _controller = controller;
    try {
      await controller.initialize();
      if (!mounted || _controller != controller) return;
      // Muted by default (Instagram-style auto-play). User unmute via
      // fullscreen player.
      await controller.setVolume(0);
      await controller.setLooping(true);
      setState(() => _initializing = false);
      // Apply current visibility — kalau sudah visible saat init selesai,
      // langsung play.
      _applyVisibility();
    } catch (_) {
      await controller.dispose();
      if (!mounted || _controller != controller) return;
      setState(() {
        _controller = null;
        _initializing = false;
        _error = 'Video belum bisa diputar';
      });
    }
  }

  Future<void> _disposeController() async {
    final controller = _controller;
    _controller = null;
    await controller?.pause();
    await controller?.dispose();
  }

  void _onVisibilityChanged(VisibilityInfo info) {
    _visibleFraction = info.visibleFraction;
    _applyVisibility();
  }

  void _applyVisibility() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final shouldPlay = _visibleFraction >= 0.6;
    if (shouldPlay && !controller.value.isPlaying) {
      controller.play();
    } else if (!shouldPlay && controller.value.isPlaying) {
      controller.pause();
    }
  }

  Future<void> _openFullScreen() async {
    final controller = _controller;
    AppHaptics.tap();
    // Pause inline supaya audio tidak overlap.
    final wasPlaying = controller?.value.isPlaying ?? false;
    await controller?.pause();
    await Navigator.of(context).push<void>(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, __, ___) => _FullScreenVideoRoute(
          mediaUrl: widget.mediaUrl,
          thumbnailUrl: widget.thumbnailUrl,
        ),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
    if (!mounted) return;
    // Resume inline kalau masih visible.
    if (wasPlaying) _applyVisibility();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;
    return VisibilityDetector(
      key: ValueKey('inline-video-${widget.postId}'),
      onVisibilityChanged: _onVisibilityChanged,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: ready ? _openFullScreen : null,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: Colors.black),
            if (ready)
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: controller.value.size.width > 0
                      ? controller.value.size.width
                      : 100,
                  height: controller.value.size.height > 0
                      ? controller.value.size.height
                      : 100,
                  child: VideoPlayer(controller),
                ),
              )
            else if (widget.thumbnailUrl != null &&
                widget.thumbnailUrl!.trim().isNotEmpty)
              _ImageSurface(
                imageUrl: widget.thumbnailUrl!,
                placeholderIcon: Icons.video_collection_outlined,
              )
            else
              const _MediaPlaceholder(icon: Icons.video_collection_outlined),
            if (_initializing)
              const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.white,
                  ),
                ),
              ),
            if (_error != null)
              Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            // Muted indicator pojok kanan bawah — visual cue bahwa video
            // bisa di-fullscreen untuk audio. Sembunyi saat error/loading.
            if (ready && _error == null)
              Positioned(
                right: 10,
                bottom: 10,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.volume_off_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Fullscreen video player route — tap-to-toggle play/pause, swipe down
/// untuk close. Audio enabled (unmute saat masuk fullscreen).
class _FullScreenVideoRoute extends StatefulWidget {
  final String mediaUrl;
  final String? thumbnailUrl;

  const _FullScreenVideoRoute({
    required this.mediaUrl,
    required this.thumbnailUrl,
  });

  @override
  State<_FullScreenVideoRoute> createState() => _FullScreenVideoRouteState();
}

class _FullScreenVideoRouteState extends State<_FullScreenVideoRoute> {
  VideoPlayerController? _controller;
  bool _initializing = true;
  bool _muted = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.mediaUrl),
    );
    _controller = controller;
    try {
      await controller.initialize();
      if (!mounted) return;
      await controller.setLooping(true);
      await controller.setVolume(1);
      await controller.play();
      setState(() => _initializing = false);
    } catch (_) {
      await controller.dispose();
      if (!mounted) return;
      setState(() => _initializing = false);
    }
  }

  @override
  void dispose() {
    _controller?.pause();
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    setState(() {
      if (controller.value.isPlaying) {
        controller.pause();
      } else {
        controller.play();
      }
    });
  }

  void _toggleMute() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    setState(() {
      _muted = !_muted;
      controller.setVolume(_muted ? 0 : 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _togglePlay,
            onVerticalDragEnd: (details) {
              // Swipe down → close.
              if ((details.primaryVelocity ?? 0) > 300) {
                Navigator.maybePop(context);
              }
            },
            child: Center(
              child: ready
                  ? AspectRatio(
                      aspectRatio: controller.value.aspectRatio,
                      child: VideoPlayer(controller),
                    )
                  : _initializing
                      ? const SizedBox(
                          width: 36,
                          height: 36,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.8,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.error_outline_rounded,
                          color: Colors.white60,
                          size: 48,
                        ),
            ),
          ),
          // Top chrome — close button.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Align(
                alignment: Alignment.topLeft,
                child: _RoundIconButton(
                  icon: Icons.close_rounded,
                  onTap: () => Navigator.maybePop(context),
                ),
              ),
            ),
          ),
          // Mute toggle pojok kanan bawah.
          if (ready)
            Positioned(
              right: 16,
              bottom: 32,
              child: _RoundIconButton(
                icon:
                    _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                onTap: _toggleMute,
              ),
            ),
          // Play indicator saat paused.
          if (ready && !controller.value.isPlaying)
            const IgnorePointer(
              child: Center(
                child: Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 72,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _RoundIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

// ─── Menu bottom sheet (Edit / Delete) ──────────────────────────────

enum _PostMenuAction { edit, delete }

class _PostMenuSheet extends StatelessWidget {
  const _PostMenuSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle.
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 6, bottom: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_rounded,
                  color: NataloColors.textPrimary),
              title: const Text(
                'Edit caption',
                style: TextStyle(
                  color: NataloColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              onTap: () => Navigator.pop(context, _PostMenuAction.edit),
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_rounded, color: Color(0xFFDC2626)),
              title: const Text(
                'Hapus postingan',
                style: TextStyle(
                  color: Color(0xFFDC2626),
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              onTap: () => Navigator.pop(context, _PostMenuAction.delete),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Edit caption bottom sheet ──────────────────────────────────────

class _EditCaptionSheet extends StatefulWidget {
  final TextEditingController controller;

  const _EditCaptionSheet({required this.controller});

  @override
  State<_EditCaptionSheet> createState() => _EditCaptionSheetState();
}

class _EditCaptionSheetState extends State<_EditCaptionSheet> {
  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Edit Caption',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: NataloColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Caption diubah akan kembali ke status menunggu review admin.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: NataloColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: widget.controller,
                maxLines: 6,
                minLines: 3,
                maxLength: 2000,
                autofocus: true,
                style: const TextStyle(
                  color: NataloColors.textPrimary,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: 'Tulis caption…',
                  filled: true,
                  fillColor: const Color(0xFFF3F4F6),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: Color(0xFFE5E7EB)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Batal',
                        style: TextStyle(
                          color: NataloColors.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () =>
                          Navigator.pop(context, widget.controller.text),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: NataloColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Simpan',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Comment sheet — MVP, fetch & post inline ───────────────────────

class _MyPostCommentSheet extends StatefulWidget {
  final MyFeedPost post;
  final String authorName;
  final String? authorAvatarUrl;

  const _MyPostCommentSheet({
    required this.post,
    required this.authorName,
    this.authorAvatarUrl,
  });

  @override
  State<_MyPostCommentSheet> createState() => _MyPostCommentSheetState();
}

class _MyPostCommentSheetState extends State<_MyPostCommentSheet> {
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  List<FeedComment> _comments = const [];
  bool _loading = true;
  bool _posting = false;
  // Emoji panel visibility — toggle via 😀 button samping input.
  bool _emojiVisible = false;

  /// Comment yang sedang di-reply (null = top-level comment baru).
  /// Saat non-null, input field show hint "Balas @username…" + chip
  /// cancel pill di atas. Submit pakai parentCommentId = _replyingTo.id.
  FeedComment? _replyingTo;

  /// Parent comment IDs yang sedang di-expand replies. Default collapsed
  /// (match IG: user harus tap "Lihat N balasan" supaya replies muncul).
  final Set<String> _expandedReplies = {};

  /// Comment IDs yang sedang dalam optimistic like toggle — guard
  /// supaya tidak double-fire request kalau user spam tap.
  final Set<String> _likeBusy = {};

  /// Caption ditampilkan sebagai pinned item pertama di list (kalau ada).
  /// Synthesize FeedComment virtual — bukan dari backend comment table,
  /// jadi tidak masuk ke fetchComments / postComment lifecycle. Caption
  /// tile tidak punya action row (like/reply hidden).
  FeedComment? get _captionRow {
    final raw = (widget.post.caption ?? '').trim();
    if (raw.isEmpty) return null;
    return FeedComment(
      id: '__caption__${widget.post.id}',
      postId: widget.post.id,
      content: raw,
      isAdminOfficial: false,
      isHidden: false,
      likeCount: 0,
      createdAt: widget.post.createdAt,
      author: FeedAuthor(
        id: 'self',
        name: widget.authorName,
        role: 'CUSTOMER',
        profilePhotoUrl: widget.authorAvatarUrl,
      ),
      viewerLiked: false,
    );
  }

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    try {
      final page = await feedService.fetchComments(widget.post.id, limit: 30);
      if (!mounted) return;
      setState(() {
        _comments = page.items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _comments = const [];
        _loading = false;
      });
    }
  }

  void _toggleEmojiPicker() {
    AppHaptics.tap();
    final newState = !_emojiVisible;
    setState(() => _emojiVisible = newState);
    if (newState) {
      // Hide keyboard supaya emoji panel pas di bawah input.
      FocusScope.of(context).unfocus();
    } else {
      _inputFocusNode.requestFocus();
    }
  }

  void _startReply(FeedComment parent) {
    AppHaptics.tap();
    // Reply ke reply: backend flatten ke parent root. Cari root parent.
    final root = _findRootParent(parent);
    setState(() => _replyingTo = root);
    _inputFocusNode.requestFocus();
  }

  void _cancelReply() {
    setState(() => _replyingTo = null);
  }

  FeedComment _findRootParent(FeedComment candidate) {
    if (candidate.parentCommentId == null) return candidate;
    // Cari di top-level comments yang punya candidate sebagai reply.
    for (final top in _comments) {
      if (top.id == candidate.parentCommentId) return top;
      for (final reply in top.replies) {
        if (reply.id == candidate.id) return top;
      }
    }
    return candidate;
  }

  void _toggleRepliesExpanded(String parentId) {
    AppHaptics.tap();
    setState(() {
      if (_expandedReplies.contains(parentId)) {
        _expandedReplies.remove(parentId);
      } else {
        _expandedReplies.add(parentId);
      }
    });
  }

  Future<void> _toggleCommentLike(FeedComment comment) async {
    if (_likeBusy.contains(comment.id)) return;
    AppHaptics.tap();
    final wasLiked = comment.viewerLiked;
    final previousCount = comment.likeCount;
    final newLiked = !wasLiked;
    setState(() {
      _likeBusy.add(comment.id);
      _comments = _updateCommentInTree(
        _comments,
        comment.id,
        (c) => c.copyWith(
          viewerLiked: newLiked,
          likeCount:
              newLiked ? c.likeCount + 1 : (c.likeCount - 1).clamp(0, 999999),
        ),
      );
    });
    try {
      final newLikeCount = await feedService.toggleCommentLike(
        comment.id,
        currentlyLiked: wasLiked,
      );
      if (!mounted) return;
      setState(() {
        _likeBusy.remove(comment.id);
        _comments = _updateCommentInTree(
          _comments,
          comment.id,
          (c) => c.copyWith(
            viewerLiked: newLiked,
            likeCount: newLikeCount,
          ),
        );
      });
    } catch (_) {
      if (!mounted) return;
      // Revert optimistic.
      setState(() {
        _likeBusy.remove(comment.id);
        _comments = _updateCommentInTree(
          _comments,
          comment.id,
          (c) => c.copyWith(
            viewerLiked: wasLiked,
            likeCount: previousCount,
          ),
        );
      });
      AppToast.show(context, 'Gagal update suka komentar, coba lagi');
    }
  }

  /// Recursively walk top-level + replies, swap comment id-nya dengan
  /// result transform. Immutable update — return new list.
  List<FeedComment> _updateCommentInTree(
    List<FeedComment> tree,
    String id,
    FeedComment Function(FeedComment c) transform,
  ) {
    return tree.map((top) {
      if (top.id == id) return transform(top);
      if (top.replies.isEmpty) return top;
      final newReplies = top.replies
          .map((reply) => reply.id == id ? transform(reply) : reply)
          .toList();
      return top.copyWith(replies: newReplies);
    }).toList();
  }

  Future<void> _submitComment() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _posting) return;
    setState(() => _posting = true);
    final replyTo = _replyingTo;
    try {
      final comment = await feedService.postComment(
        widget.post.id,
        content: text,
        parentCommentId: replyTo?.id,
      );
      if (!mounted) return;
      _inputController.clear();
      setState(() {
        _replyingTo = null;
        if (replyTo == null) {
          // Top-level: prepend ke list.
          _comments = [comment, ..._comments];
        } else {
          // Reply: insert ke parent's replies + auto-expand.
          _comments = _comments.map((top) {
            if (top.id != replyTo.id) return top;
            final newReplies = [...top.replies, comment];
            return top.copyWith(
              replies: newReplies,
              replyCount: newReplies.length,
            );
          }).toList();
          _expandedReplies.add(replyTo.id);
        }
      });
    } catch (_) {
      if (!mounted) return;
      AppToast.show(context, 'Gagal kirim komentar, coba lagi');
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight = MediaQuery.of(context).size.height * 0.78;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  'Komentar',
                  style: TextStyle(
                    color: NataloColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const Divider(height: 1, color: Color(0xFFEEF2F6)),
              Flexible(
                child: Builder(builder: (context) {
                  if (_loading) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      ),
                    );
                  }
                  final captionRow = _captionRow;
                  if (_comments.isEmpty && captionRow == null) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 28),
                      child: Center(
                        child: Text(
                          'Belum ada komentar.\nJadi yang pertama!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: NataloColors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            height: 1.4,
                          ),
                        ),
                      ),
                    );
                  }
                  // Build flat list of rows untuk ListView:
                  //  - Caption tile (kalau ada) di top, no actions
                  //  - Each top-level comment: parent tile + (optional)
                  //    "Lihat N balasan" toggle + (optional, when expanded)
                  //    semua reply tiles indented
                  final entries = <_CommentEntry>[];
                  if (captionRow != null) {
                    entries.add(_CommentEntry.caption(captionRow));
                  }
                  for (final top in _comments) {
                    entries.add(_CommentEntry.comment(top, isReply: false));
                    if (top.replyCount > 0) {
                      entries.add(_CommentEntry.repliesToggle(
                        parent: top,
                        expanded: _expandedReplies.contains(top.id),
                      ));
                      if (_expandedReplies.contains(top.id)) {
                        for (final reply in top.replies) {
                          entries.add(
                            _CommentEntry.comment(reply, isReply: true),
                          );
                        }
                      }
                    }
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      switch (entry.kind) {
                        case _CommentEntryKind.caption:
                          return _CommentTile(
                            comment: entry.comment!,
                            isReply: false,
                            isCaption: true,
                            likeBusy: false,
                            onToggleLike: null,
                            onReply: null,
                          );
                        case _CommentEntryKind.comment:
                          final c = entry.comment!;
                          return _CommentTile(
                            comment: c,
                            isReply: entry.isReply,
                            isCaption: false,
                            likeBusy: _likeBusy.contains(c.id),
                            onToggleLike: () => _toggleCommentLike(c),
                            onReply: () => _startReply(c),
                          );
                        case _CommentEntryKind.repliesToggle:
                          return _RepliesToggle(
                            parentId: entry.comment!.id,
                            replyCount: entry.comment!.replyCount,
                            expanded: entry.expanded,
                            onTap: () =>
                                _toggleRepliesExpanded(entry.comment!.id),
                          );
                      }
                    },
                  );
                }),
              ),
              // Reply chip — kalau lagi reply, show context bar di atas
              // input. Tap X cancel reply → kembali ke top-level mode.
              if (_replyingTo != null)
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                  color: const Color(0xFFF3F4F6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Membalas ${_replyingTo!.author.name}',
                          style: const TextStyle(
                            color: NataloColors.textSecondary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _cancelReply,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: NataloColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Color(0xFFEEF2F6), width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    // 😀 emoji toggle — fixed left of input. Pakai
                    // smaller icon vs caption composer (sheet space lebih
                    // tight).
                    IconButton(
                      onPressed: _toggleEmojiPicker,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.all(6),
                      constraints: const BoxConstraints(),
                      icon: Icon(
                        _emojiVisible
                            ? Icons.keyboard_rounded
                            : Icons.emoji_emotions_outlined,
                        color: _emojiVisible
                            ? NataloColors.primary
                            : NataloColors.textSecondary,
                        size: 22,
                      ),
                      tooltip: _emojiVisible ? 'Tutup emoji' : 'Buka emoji',
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: TextField(
                        controller: _inputController,
                        focusNode: _inputFocusNode,
                        onTap: () {
                          // Auto-hide emoji panel saat user tap input
                          // (mau soft keyboard naik).
                          if (_emojiVisible) {
                            setState(() => _emojiVisible = false);
                          }
                        },
                        maxLength: 500,
                        decoration: InputDecoration(
                          hintText: _replyingTo == null
                              ? 'Tulis komentar…'
                              : 'Balas ${_replyingTo!.author.name}…',
                          filled: true,
                          fillColor: const Color(0xFFF3F4F6),
                          counterText: '',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(999),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _submitComment(),
                      ),
                    ),
                    IconButton(
                      onPressed: _posting ? null : _submitComment,
                      icon: _posting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(
                              Icons.send_rounded,
                              color: NataloColors.primary,
                            ),
                    ),
                  ],
                ),
              ),
              // Emoji panel di bawah input bar — visible toggle via state.
              EmojiPickerPanel(
                controller: _inputController,
                visible: _emojiVisible,
                // Sheet sudah tight di height. Pakai 260 vs default 280.
                height: 260,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Entry dalam flat list ListView — tile bisa caption/comment/replies toggle.
enum _CommentEntryKind { caption, comment, repliesToggle }

class _CommentEntry {
  final _CommentEntryKind kind;
  final FeedComment? comment;
  final bool isReply;
  final bool expanded;

  const _CommentEntry._({
    required this.kind,
    this.comment,
    this.isReply = false,
    this.expanded = false,
  });

  factory _CommentEntry.caption(FeedComment row) =>
      _CommentEntry._(kind: _CommentEntryKind.caption, comment: row);

  factory _CommentEntry.comment(FeedComment c, {required bool isReply}) =>
      _CommentEntry._(
        kind: _CommentEntryKind.comment,
        comment: c,
        isReply: isReply,
      );

  factory _CommentEntry.repliesToggle({
    required FeedComment parent,
    required bool expanded,
  }) =>
      _CommentEntry._(
        kind: _CommentEntryKind.repliesToggle,
        comment: parent,
        expanded: expanded,
      );
}

class _CommentTile extends StatelessWidget {
  final FeedComment comment;
  final bool isReply;
  final bool isCaption;
  final bool likeBusy;
  final VoidCallback? onToggleLike;
  final VoidCallback? onReply;

  const _CommentTile({
    required this.comment,
    required this.isReply,
    required this.isCaption,
    required this.likeBusy,
    this.onToggleLike,
    this.onReply,
  });

  @override
  Widget build(BuildContext context) {
    final liked = comment.viewerLiked;
    final author = comment.author;
    return Padding(
      // Reply indented ~40px supaya jelas hierarchy parent → reply.
      padding: EdgeInsets.only(left: isReply ? 40 : 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProfileAvatar(
            initial:
                author.name.isNotEmpty ? author.name[0].toUpperCase() : 'U',
            imageUrl: author.avatarUrl ?? author.profilePhotoUrl,
            // Reply pakai avatar lebih kecil supaya hierarchy visual jelas.
            size: isReply ? 28 : 34,
            fontSize: isReply ? 12 : 14,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${author.name} ',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      TextSpan(text: comment.content),
                    ],
                  ),
                  style: TextStyle(
                    color: NataloColors.textPrimary,
                    fontSize: isReply ? 13 : 13.5,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 4),
                // Action row: timestamp + (kalau bukan caption) Reply
                // button + (di luar row) Like icon vertical kanan.
                Row(
                  children: [
                    Text(
                      formatRelativeTime(comment.createdAt),
                      style: const TextStyle(
                        color: NataloColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (!isCaption && comment.likeCount > 0) ...[
                      const SizedBox(width: 12),
                      Text(
                        '${comment.likeCount} suka',
                        style: const TextStyle(
                          color: NataloColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                    if (!isCaption && onReply != null) ...[
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: onReply,
                        behavior: HitTestBehavior.opaque,
                        child: const Text(
                          'Balas',
                          style: TextStyle(
                            color: NataloColors.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // Heart icon di kanan tile — caption tidak punya. Reply tile
          // tetap punya supaya bisa di-like.
          if (!isCaption && onToggleLike != null) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: likeBusy ? null : onToggleLike,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 2,
                ),
                child: Icon(
                  liked
                      ? Icons.favorite_rounded
                      : Icons.favorite_outline_rounded,
                  size: isReply ? 14 : 16,
                  color: liked
                      ? const Color(0xFFE53935)
                      : NataloColors.textSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RepliesToggle extends StatelessWidget {
  final String parentId;
  final int replyCount;
  final bool expanded;
  final VoidCallback onTap;

  const _RepliesToggle({
    required this.parentId,
    required this.replyCount,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 40, top: 2),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 24,
              height: 1,
              color: const Color(0xFFD1D5DB),
              margin: const EdgeInsets.only(right: 8),
            ),
            Text(
              expanded ? 'Sembunyikan balasan' : 'Lihat $replyCount balasan',
              style: const TextStyle(
                color: NataloColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Aspect ratio per media type — Postingan Saya memakai Instagram posts style:
///   - Video: 4:5 (0.8) — konsisten dengan image feed post, bukan Reels.
///   - Photo (single/carousel): 4:5 (0.8) — Instagram-spec standard.
///     Sejak v1.0.62, picker actual crop file ke 4:5 sebelum upload
///     (lihat _cropPhotoTo4x5 di feed_media_picker_screen.dart). Jadi
///     post baru: source aspect ≈ 4:5 → frame 4:5 → BoxFit.cover no
///     visible crop (WYSIWYG match IG).
///
///     Post lama (pre-v1.0.62) bisa punya aspect ratio apapun → clamp
///     ke [0.8, 1.91] sebagai safety net. Kalau aspect di luar range,
///     BoxFit.cover akan center-crop ke frame (acceptable fallback).
///
/// Default fallback 4:5 kalau type tidak diketahui.
double _safeAspectRatio(int width, int height, {MyFeedPostType? type}) {
  // Video: fixed 4:5 — halaman ini list posts, bukan Reels.
  if (type == MyFeedPostType.video) {
    return 4 / 5;
  }
  // Photo / carousel: clamp ke 4:5 portrait → 1.91:1 landscape.
  // New posts (v1.0.62+) sudah 4:5 di upload-side → ratio = 0.8 = no-op
  // clamp. Old posts: clamp untuk safety.
  if (width <= 0 || height <= 0) return 4 / 5;
  final ratio = width / height;
  if (ratio.isNaN || ratio.isInfinite || ratio <= 0) return 4 / 5;
  return ratio.clamp(0.8, 1.91);
}

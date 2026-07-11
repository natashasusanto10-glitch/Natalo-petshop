// ignore_for_file: use_build_context_synchronously
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shimmer/shimmer.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../config/api_config.dart';
import '../models/feed_comment.dart';
import '../models/feed_post.dart';
import '../services/api_client.dart';
import '../services/feed_service.dart';
import '../services/report_service.dart';
import '../state/feed_local_store.dart';
import '../state/feed_store.dart';
import '../state/member_store.dart';
import '../state/settings_store.dart';
import '../theme/natalo_colors.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import '../utils/mention_text.dart';
import '../widgets/app_toast.dart';
import '../widgets/emoji_picker_panel.dart';
import '../widgets/mention_picker.dart';
import '../widgets/moderation_action_sheet.dart';
import '../widgets/natalo_paw_refresh_indicator.dart';
import '../widgets/post_likers_sheet.dart';
import '../widgets/profile_avatar.dart';
import '../shared/widgets/natalo_post_action_icon.dart';
import 'public_profile_screen.dart';

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
  final FeedPost post;
  final List<FeedPost>? posts;
  final int initialIndex;

  /// Override author header info — dipakai saat screen ini di-open dari
  /// public profile orang lain (`/u/{username}`), bukan dari "Postingan
  /// Saya". Kalau null, fallback ke memberStore.profile (asumsi viewer
  /// adalah author = original behavior untuk "Postingan Saya").
  final String? authorName;
  final String? authorPhotoUrl;
  final String? authorInitial;

  /// Owner mode flag. True (default) untuk "Postingan Saya" — show
  /// Edit/Delete menu di "...". False saat view post user lain — sembunyikan
  /// menu owner-only (edit caption + hapus), supaya tidak ada aksi destructive
  /// yang bocor ke viewer non-owner.
  final bool isOwner;

  const MemberPostDetailScreen({
    super.key,
    required this.post,
    this.posts,
    this.initialIndex = 0,
    this.authorName,
    this.authorPhotoUrl,
    this.authorInitial,
    this.isOwner = true,
  });

  @override
  State<MemberPostDetailScreen> createState() => _MemberPostDetailScreenState();
}

class _MemberPostDetailScreenState extends State<MemberPostDetailScreen> {
  late final ScrollController _scrollController;
  late List<FeedPost> _posts;
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
        : List<FeedPost>.from(source);
    _postKeys = List.generate(_posts.length, (_) => GlobalKey());
    _scrollController = ScrollController();
    // Hydrate _likedCache dari backend `viewerLiked` field — tanpa ini,
    // post yang sudah di-like sebelumnya tampil grey di icon, dan tap
    // pertama bakal accidentally UN-LIKE (backend toggle berdasar DB,
    // bukan trust client). Lihat bug "klik like 1x hilang harus klik
    // kedua kali baru bisa di-like".
    // Seed shared FeedStore — supaya like/comment count di sini sinkron
    // ke screen lain (Reels feed, Postingan Saya grid, Public Profile).
    feedStore.seed(_posts);
    for (final post in _posts) {
      final fresh = feedStore.get(post.id) ?? post;
      _likedCache[post.id] = fresh.viewerLiked || fresh.isLiked;
    }
    feedStore.addListener(_onFeedStoreChanged);
    // Jump ke post target setelah first frame settled. Pakai
    // Scrollable.ensureVisible via GlobalKey context — Flutter handle
    // layout precisely, gak ada drift estimasi.
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToInitial());
  }

  /// Sync local _likedCache + _posts[i] likeCount/commentCount dari store.
  /// Trigger saat FeedStore notify (e.g. user like dari Reels feed → store
  /// update → kita ikut update DI SINI walaupun tidak dari interaksi
  /// langsung di detail screen).
  void _onFeedStoreChanged() {
    if (!mounted) return;
    var anyChanged = false;
    for (var i = 0; i < _posts.length; i++) {
      final post = _posts[i];
      final fresh = feedStore.get(post.id);
      if (fresh == null) continue;
      final freshLiked = fresh.viewerLiked || fresh.isLiked;
      final cached = _likedCache[post.id];
      if (cached != freshLiked ||
          post.likeCount != fresh.likeCount ||
          post.commentCount != fresh.commentCount ||
          !_sameLikerIds(post.recentLikers, fresh.recentLikers)) {
        _likedCache[post.id] = freshLiked;
        _posts[i] = _withInteractionUpdate(
          post,
          likeCount: fresh.likeCount,
          liked: freshLiked,
          commentCount: fresh.commentCount,
          recentLikers: fresh.recentLikers,
        );
        anyChanged = true;
      }
    }
    if (anyChanged) setState(() {});
  }

  void _jumpToInitial() {
    final targetIndex = widget.initialIndex;
    if (targetIndex <= 0 || targetIndex >= _posts.length) {
      return;
    }
    _jumpNearPost(targetIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensurePostVisible(targetIndex, attemptsLeft: 8);
    });
  }

  void _jumpNearPost(int targetIndex) {
    if (!_scrollController.hasClients) return;
    final maxExtent = _scrollController.position.maxScrollExtent;
    final approxOffset = _estimatedPostExtent(context) * targetIndex;
    final targetOffset = approxOffset.clamp(0.0, maxExtent).toDouble();
    _scrollController.jumpTo(targetOffset);
  }

  void _ensurePostVisible(int targetIndex, {required int attemptsLeft}) {
    if (!mounted || !_scrollController.hasClients) return;
    final ctx = _postKeys[targetIndex].currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: Duration.zero,
        alignment: 0.0,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      );
      return;
    }
    if (attemptsLeft <= 0) return;
    _jumpNearPost(targetIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensurePostVisible(targetIndex, attemptsLeft: attemptsLeft - 1);
    });
  }

  double _estimatedPostExtent(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    const mediaAspectRatio = 9 / 14;
    const authorRowHeight = 52.0;
    const actionCaptionDateHeight = 118.0;
    final mediaHeight = width / mediaAspectRatio;
    return mediaHeight + authorRowHeight + actionCaptionDateHeight;
  }

  @override
  void dispose() {
    feedStore.removeListener(_onFeedStoreChanged);
    _scrollController.dispose();
    super.dispose();
  }

  String get _memberName {
    // Override path: viewing another user's post via public profile.
    // widget.authorName non-null → respect itu, fallback baru ke memberStore.
    final override = widget.authorName?.trim();
    if (override != null && override.isNotEmpty) return override;
    // CRITICAL: !isOwner = viewing post user lain. JANGAN fallback ke
    // memberStore.profile.name — itu nama VIEWER, bukan author. Privacy
    // leak + identity confusion (lihat bug "Halaman user lain profile
    // picture juga bug" — user srimulyanta br manik tanpa foto, tapi
    // muncul foto viewer karena fallback ini).
    if (!widget.isOwner) return 'Pengguna';
    final name = memberStore.profile?.name.trim();
    return name == null || name.isEmpty ? 'Member Natalo' : name;
  }

  String get _memberInitial {
    final override = widget.authorInitial?.trim();
    if (override != null && override.isNotEmpty) return override;
    if (!widget.isOwner) {
      // Non-owner: derive dari nama author, BUKAN dari memberStore
      // (yang isinya viewer).
      final nm = _memberName;
      return nm.isEmpty ? '?' : nm.substring(0, 1).toUpperCase();
    }
    final fromStore = memberStore.profile?.initial.trim();
    if (fromStore != null && fromStore.isNotEmpty) return fromStore;
    final nm = _memberName;
    return nm.isEmpty ? 'N' : nm.substring(0, 1).toUpperCase();
  }

  String? get _memberPhotoUrl {
    final override = widget.authorPhotoUrl?.trim();
    if (override != null && override.isNotEmpty) return override;
    // Non-owner + author belum upload foto profil → return null supaya
    // initial-letter avatar yang render, BUKAN foto viewer.
    if (!widget.isOwner) return null;
    return memberStore.profile?.profilePhotoUrl;
  }

  Future<void> _toggleLike(int index) async {
    final post = _posts[index];
    AppHaptics.tap();
    // Delegate ke shared FeedStore — handle optimistic + API + reconcile
    // + rollback. _onFeedStoreChanged listener akan auto-sync local
    // _likedCache + _posts[i] saat store notify. Reels feed dan screen
    // lain yang ikut listen ke store juga akan ke-update.
    try {
      final result = await feedStore.toggleLike(post.id);
      await feedLocalStore.setLiked(post.id, result.liked);
    } catch (_) {
      if (!mounted) return;
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
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _MyPostCommentSheet(
        post: post,
        // Author info — pakai resolver yang sudah respect override
        // dari public profile (widget.authorName / authorPhotoUrl).
        // Owner viewing own post → fallback ke memberStore.
        authorName: _memberName,
        authorAvatarUrl: _memberPhotoUrl,
      ),
    );
  }

  Future<void> _openPostMenu(int index) async {
    AppHaptics.tap();
    final result = await showModalBottomSheet<_PostMenuAction>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
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
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => _EditCaptionSheet(controller: controller),
    );
    if (result == null || !mounted) return;
    final newCaption = result.trim();
    if (newCaption == (post.caption ?? '').trim()) return;
    final syncedTitle = newCaption.isEmpty
        ? 'Postingan baru'
        : newCaption.substring(
            0, newCaption.length > 80 ? 80 : newCaption.length);
    try {
      await apiClient.patchJson(
        '/api/feed/posts/${Uri.encodeComponent(post.id)}',
        body: {
          'title': syncedTitle,
          'description': newCaption,
        },
      );
      if (!mounted) return;
      final updated = _withCaption(post, newCaption);
      setState(() {
        _posts[index] = updated;
      });
      // Sync ke FeedStore — Reels feed / grid lain yang display caption
      // post ini ikut update. Status reset ke PENDING_REVIEW di backend
      // (lihat _withCaption) → store reflect itu juga.
      feedStore.applyPostUpdate(updated);
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
        // Sync ke FeedStore — Reels feed / grid lain ikut hilang.
        feedStore.removePost(post.id);
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

  /// Pull-to-refresh: re-fetch tiap post by id supaya like/comment count,
  /// status review, dan caption fresh dari server. Post yang gagal fetch
  /// (network / sudah dihapus) tetap pakai data lama.
  Future<void> _refreshPosts() async {
    final results = await Future.wait(
      _posts.map((p) => feedService.fetchPostById(p.id).catchError((_) {
            return null;
          })),
    );
    if (!mounted) return;
    var anyChanged = false;
    for (var i = 0; i < _posts.length; i++) {
      final fresh = results[i];
      if (fresh == null) continue;
      _posts[i] = fresh;
      _likedCache[fresh.id] = fresh.viewerLiked || fresh.isLiked;
      anyChanged = true;
    }
    if (anyChanged) {
      feedStore.seed(_posts);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        surfaceTintColor: cs.surface,
        leading: IconButton(
          onPressed: () => Navigator.maybePop(context),
          // Back icon size 26 per spec Detail Postingan. Material Icon
          // (arrow_back_rounded) tidak punya strokeWidth — rendering dari
          // icon font, weight fixed. Visual thickness sudah mirip stroke
          // 2.5 di NataloPostActionIcon karena rounded variant Material.
          icon: Icon(
            Icons.arrow_back_rounded,
            color: cs.onSurface,
            size: 26,
          ),
        ),
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Postingan',
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                height: 1.05,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              _memberName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1.05,
              ),
            ),
          ],
        ),
      ),
      body: _posts.isEmpty
          ? Center(
              child: Text(
                'Belum ada postingan',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          : NataloPawRefreshIndicator(
              onRefresh: _refreshPosts,
              child: ListView.separated(
                controller: _scrollController,
                cacheExtent: _estimatedPostExtent(context) * 2,
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
                    memberInitial: _memberInitial,
                    memberPhotoUrl: _memberPhotoUrl,
                    liked: _likedCache[post.id] ?? false,
                    // Hide ... menu ketika viewing post user lain — tidak ada
                    // edit/delete option untuk non-owner. (Bisa ekspansi nanti
                    // ke Report/Block via tombol terpisah kalau perlu.)
                    showMenu: widget.isOwner,
                    // Status badge owner-only (Menunggu review/Ditolak).
                    showStatusBadge: widget.isOwner,
                    onLike: () => _toggleLike(index),
                    onComment: () => _openComments(index),
                    onShare: () => _shareNative(index),
                    onMenuTap:
                        widget.isOwner ? () => _openPostMenu(index) : null,
                  );
                },
              ),
            ),
    );
  }

  /// Bulk interaction update — rekonstruksi FeedPost dengan likeCount,
  /// viewerLiked, dan commentCount baru sekaligus. Dipakai oleh sync
  /// listener FeedStore (_onFeedStoreChanged).
  FeedPost _withInteractionUpdate(
    FeedPost post, {
    required int likeCount,
    required bool liked,
    required int commentCount,
    List<FeedAuthor>? recentLikers,
  }) {
    return post.copyWith(
      likeCount: likeCount,
      commentCount: commentCount,
      viewerLiked: liked,
      isLiked: liked,
      recentLikers: recentLikers,
    );
  }

  FeedPost _withCaption(FeedPost post, String newCaption) {
    return post.copyWith(
      caption: newCaption.isEmpty ? null : newCaption,
      description: newCaption.isEmpty ? '' : newCaption,
      // Edit caption reset status ke PENDING_REVIEW per backend logic.
      status: 'PENDING_REVIEW',
    );
  }
}

bool _sameLikerIds(List<FeedAuthor> a, List<FeedAuthor> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].id != b[i].id) return false;
  }
  return true;
}

// ─── Per-post item ───────────────────────────────────────────────────

class _PostFeedItem extends StatefulWidget {
  final FeedPost post;
  final String memberName;
  final String memberInitial;
  final String? memberPhotoUrl;
  final bool liked;
  final bool showMenu;
  // Status badge (Menunggu review / Ditolak) hanya relevan untuk owner —
  // bagian dari moderation pipeline pribadi. Saat viewer membuka post user
  // lain dari public profile, status tidak ditampilkan (mereka cuma lihat
  // post yang sudah PUBLISHED toh — atau setidaknya yang dianggap public
  // oleh backend). Bonus: kalau backend tidak mengirim `status` field di
  // public endpoint, FeedPost.fromJson defaultkan ke 'PENDING_REVIEW',
  // yang bisa salah picu badge. Gate by isOwner mencegah false positive.
  final bool showStatusBadge;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;
  // Nullable — null ketika viewing post user lain (showMenu = false).
  // Author row builder cek null untuk decide render trailing menu icon.
  final VoidCallback? onMenuTap;

  const _PostFeedItem({
    super.key,
    required this.post,
    required this.memberName,
    required this.memberInitial,
    required this.memberPhotoUrl,
    required this.liked,
    this.showMenu = true,
    this.showStatusBadge = true,
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

  // Heart burst controller — big red heart pop di posisi double-tap user.
  // Signature Instagram-style: scale 0.35→1.42→1.0→0 dengan opacity
  // fade in/out. 620ms total.
  late final AnimationController _heartBurstController;
  late final Animation<double> _burstScale;
  late final Animation<double> _burstOpacity;
  Offset? _heartBurstPosition;

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

  void _rememberHeartBurstPosition(TapDownDetails details) {
    _heartBurstPosition = details.localPosition;
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
    _heartBurstController.forward(from: 0);
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
        // Hanya ditampilkan untuk owner (showStatusBadge=true) — viewer
        // dari public profile tidak melihat status moderation post orang
        // lain. Tanpa gate ini, default status='PENDING_REVIEW' di
        // FeedPost.fromJson bisa kelihatan ke viewer kalau backend
        // /api/u/{username} tidak set field status di response.
        if (widget.showStatusBadge &&
            (post.statusInfo == FeedPostStatus.pending ||
                post.statusInfo == FeedPostStatus.rejected)) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
            child: _PostStatusBadge(post: post),
          ),
        ],
        // Photo/carousel: author row putih di atas media.
        // Video: author masuk overlay di dalam video (IG video post style).
        if (!post.isVideo)
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
          onDoubleTapDown: _rememberHeartBurstPosition,
          onDoubleTap: _handleDoubleTap,
          child: Stack(
            children: [
              _PostMediaSurface(post: post),
              if (post.isVideo)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _VideoPostAuthorOverlay(
                    memberName: memberName,
                    memberInitial: memberInitial,
                    memberPhotoUrl: memberPhotoUrl,
                    onMenuTap: widget.onMenuTap,
                  ),
                ),
              // Heart burst overlay — posisi mengikuti titik double-tap.
              // IgnorePointer supaya tidak intercept tap berikutnya.
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _heartBurstController,
                    builder: (context, _) {
                      if (_burstOpacity.value == 0) {
                        return const SizedBox.shrink();
                      }
                      final position = _heartBurstPosition;
                      final progress = _heartBurstController.value;
                      final heart = Opacity(
                        opacity: _burstOpacity.value,
                        child: Transform.translate(
                          offset: Offset(0, -14 * progress),
                          child: Transform.scale(
                            scale: _burstScale.value,
                            child: Transform.rotate(
                              angle: -0.08,
                              child: const Icon(
                                Icons.favorite_rounded,
                                color: Color(0xFFEF4444),
                                size: 128,
                                shadows: [
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
              // Action icons: thin outline, close to Instagram's lighter
              // stroke while keeping Natalo's custom shape.
              ScaleTransition(
                scale: _heartScale,
                child: NataloPostActionButton(
                  type: NataloPostActionIconType.like,
                  isActive: liked,
                  iconSize: 30,
                  strokeWidth: 1.6,
                  tapSize: 44,
                  count: post.likeCount,
                  semanticLabel: liked ? 'Batalkan suka' : 'Sukai postingan',
                  onTap: _handleLikeTap,
                ),
              ),
              NataloPostActionButton(
                type: NataloPostActionIconType.comment,
                iconSize: 30,
                strokeWidth: 1.6,
                tapSize: 44,
                count: post.commentCount,
                semanticLabel: 'Buka komentar',
                onTap: widget.onComment,
              ),
              NataloPostActionButton(
                type: NataloPostActionIconType.share,
                iconSize: 30,
                strokeWidth: 1.6,
                tapSize: 44,
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
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
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
  // Nullable — non-owner viewer tidak punya menu actions di sini.
  final VoidCallback? onMenuTap;

  const _PostAuthorRow({
    required this.memberName,
    required this.memberInitial,
    required this.memberPhotoUrl,
    required this.onMenuTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surface,
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
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                height: 1.15,
              ),
            ),
          ),
          if (onMenuTap != null)
            IconButton(
              onPressed: onMenuTap,
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.more_horiz_rounded,
                color: cs.onSurface,
              ),
            )
          else
            const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _VideoPostAuthorOverlay extends StatelessWidget {
  final String memberName;
  final String memberInitial;
  final String? memberPhotoUrl;
  // Nullable — non-owner viewer tidak punya menu actions di sini.
  final VoidCallback? onMenuTap;

  const _VideoPostAuthorOverlay({
    required this.memberName,
    required this.memberInitial,
    required this.memberPhotoUrl,
    required this.onMenuTap,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.58),
            Colors.black.withValues(alpha: 0.20),
            Colors.transparent,
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 28),
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
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                  shadows: [
                    Shadow(color: Colors.black54, blurRadius: 10),
                  ],
                ),
              ),
            ),
            if (onMenuTap != null)
              IconButton(
                onPressed: onMenuTap,
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.more_horiz_rounded,
                  color: Colors.white,
                  shadows: [
                    Shadow(color: Colors.black54, blurRadius: 10),
                  ],
                ),
              )
            else
              const SizedBox(width: 8),
          ],
        ),
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

/// IG-style "Disukai oleh ..." row dengan tappable segments:
///   - Avatar stack tap → buka PostLikersSheet
///   - Nama primary liker tap → buka public profile-nya
///   - "X orang lainnya" tap → buka PostLikersSheet
/// Pakai StatefulWidget karena TapGestureRecognizer instance perlu di-
/// dispose saat widget unmount (best practice; kalau StatelessWidget,
/// recognizer ke-create ulang tiap build dan tidak pernah di-dispose).
class _LikedByLine extends StatefulWidget {
  final FeedPost post;

  const _LikedByLine({
    required this.post,
  });

  @override
  State<_LikedByLine> createState() => _LikedByLineState();
}

class _LikedByLineState extends State<_LikedByLine> {
  TapGestureRecognizer? _primaryNameRecognizer;
  TapGestureRecognizer? _othersRecognizer;

  @override
  void dispose() {
    _primaryNameRecognizer?.dispose();
    _othersRecognizer?.dispose();
    super.dispose();
  }

  void _openPrimaryProfile(FeedAuthor primary) {
    if (primary.isOfficialAccount) return;
    final username = primary.username;
    if (username == null || username.isEmpty) return;
    AppHaptics.tap();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PublicProfileScreen(username: username),
      ),
    );
  }

  void _openLikersSheet() {
    PostLikersSheet.show(context, postId: widget.post.id);
  }

  @override
  Widget build(BuildContext context) {
    final likers = widget.post.recentLikers;
    final currentUserId = memberStore.profile?.id;
    final primary = likers.isNotEmpty ? likers.first : null;
    final primaryIsSelf = primary != null && primary.id == currentUserId;
    final primaryName = primary == null
        ? 'beberapa orang'
        : primaryIsSelf
            ? 'Anda'
            : primary.displayName;
    // Primary tappable kalau ada primary + bukan official admin + punya
    // username yang valid (atau adalah viewer = "Anda"; tap "Anda" buka
    // profile sendiri). "Anda" tetap tappable supaya consistent dengan
    // tap @mention di feed.
    final canTapPrimary = primary != null &&
        !primary.isOfficialAccount &&
        ((primary.username?.isNotEmpty ?? false) || primaryIsSelf);
    final othersCount = widget.post.likeCount - 1;

    // Lazily build recognizers — dispose otomatis di dispose() lifecycle
    // supaya tidak leak. Recreate kalau target liker berubah (mis. server
    // refresh recentLikers list).
    _primaryNameRecognizer?.dispose();
    _othersRecognizer?.dispose();
    _primaryNameRecognizer = null;
    _othersRecognizer = null;
    if (canTapPrimary) {
      _primaryNameRecognizer = TapGestureRecognizer()
        ..onTap = () {
          if (primaryIsSelf) {
            // "Anda" tap → buka profile sendiri kalau username ada.
            final myUsername = memberStore.profile?.username;
            if (myUsername != null && myUsername.isNotEmpty) {
              AppHaptics.tap();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PublicProfileScreen(username: myUsername),
                ),
              );
            }
          } else {
            _openPrimaryProfile(primary);
          }
        };
    }
    if (othersCount > 0) {
      _othersRecognizer = TapGestureRecognizer()..onTap = _openLikersSheet;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GestureDetector(
          // Avatar stack tap → buka sheet semua liker. Match IG behavior.
          onTap: _openLikersSheet,
          behavior: HitTestBehavior.opaque,
          child: _LikedAvatarStack(
            likers: likers,
            likeCount: widget.post.likeCount,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Disukai oleh '),
                TextSpan(
                  text: primaryName,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                  recognizer: _primaryNameRecognizer,
                ),
                if (othersCount > 0) ...[
                  const TextSpan(text: ' dan '),
                  TextSpan(
                    text: '$othersCount orang lainnya',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                    recognizer: _othersRecognizer,
                  ),
                ],
              ],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
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
  final List<FeedAuthor> likers;
  final int likeCount;

  const _LikedAvatarStack({
    required this.likers,
    required this.likeCount,
  });

  @override
  Widget build(BuildContext context) {
    const size = 22.0;
    final visible = likers.take(2).toList(growable: false);
    final hasOthers = likeCount > 1;
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
              child: visible.length > 1
                  ? _MiniAvatar.member(
                      initial: visible[1].initial,
                      photoUrl:
                          visible[1].profilePhotoUrl ?? visible[1].avatarUrl,
                      size: size,
                    )
                  : _MiniAvatar.placeholder(size: size),
            ),
          Positioned(
            left: 0,
            child: visible.isNotEmpty
                ? _MiniAvatar.member(
                    initial: visible.first.initial,
                    photoUrl: visible.first.profilePhotoUrl ??
                        visible.first.avatarUrl,
                    size: size,
                  )
                : _MiniAvatar.placeholder(size: size),
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
    final cs = Theme.of(context).colorScheme;
    final url = photoUrl;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor ?? cs.surfaceContainerHighest,
        shape: BoxShape.circle,
        // Border putih supaya overlap antar avatar kelihatan jelas.
        border: Border.all(color: Colors.white, width: 1.6),
      ),
      clipBehavior: Clip.antiAlias,
      child: url != null && url.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => _miniAvatarFallback(cs),
              placeholder: (_, __) => _miniAvatarFallback(cs),
            )
          : _miniAvatarFallback(cs),
    );
  }

  Widget _miniAvatarFallback(ColorScheme cs) {
    return Center(
      child: Text(
        initial ?? 'N',
        style: TextStyle(
          color: backgroundColor != null ? Colors.white : cs.onSurface,
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
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurface,
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
        height: 1.35,
      ),
    );
  }
}

class _PostStatusBadge extends StatelessWidget {
  final FeedPost post;

  const _PostStatusBadge({required this.post});

  @override
  Widget build(BuildContext context) {
    final rejected = post.statusInfo == FeedPostStatus.rejected;
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
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
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
  final FeedPost post;

  const _PostMediaSurface({required this.post});

  @override
  Widget build(BuildContext context) {
    // Pass type ke aspect calculator — video pakai 3:5 fixed (immersive),
    // photo/carousel pakai source aspect clamped ke 4:5.
    final aspectRatio = _safeAspectRatio(
      post.aspectWidthInt,
      post.aspectHeightInt,
      type: post.contentType,
    );
    // Hero destination — wraps photo (single & carousel cover) dengan tag
    // sama dengan _PostThumbnail di member_screen grid: 'post-thumb-${id}'.
    // Saat user tap thumb di grid, image fly + scale ke posisi ini.
    // Video skip (VideoPlayer destination tidak compatible).
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: switch (post.contentType) {
        FeedContentType.video => _InlineVideoPlayer(
            postId: post.id,
            // videoPlaybackUrl (videoUrl-first), BUKAN previewMediaUrl
            // (yang thumbnail-first → JPG → player gagal initialize).
            mediaUrl: post.videoPlaybackUrl,
            thumbnailUrl: post.thumbnailUrl,
            aspectRatio: aspectRatio,
          ),
        FeedContentType.carousel => Hero(
            tag: 'post-thumb-${post.id}',
            child: _CarouselSurface(
              post: post,
              aspectRatio: aspectRatio,
            ),
          ),
        FeedContentType.photo => Hero(
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
  final FeedPost post;
  final double aspectRatio;

  const _CarouselSurface({required this.post, required this.aspectRatio});

  @override
  State<_CarouselSurface> createState() => _CarouselSurfaceState();
}

class _CarouselSurfaceState extends State<_CarouselSurface> {
  int _index = 0;

  List<FeedMedia> get _items {
    if (widget.post.mediaItems.isNotEmpty) return widget.post.mediaItems;
    // Fallback single item. Untuk video pakai videoPlaybackUrl (video
    // source), untuk photo pakai previewMediaUrl (thumbnail/image). Jangan
    // kasih thumbnail JPG ke item video → player gagal.
    final isVideo = widget.post.isVideo;
    final fallbackUrl =
        isVideo ? widget.post.videoPlaybackUrl : widget.post.previewMediaUrl;
    if (fallbackUrl.trim().isEmpty) return const [];
    return [
      FeedMedia(
        id: '${widget.post.id}-fallback',
        mediaUrl: fallbackUrl,
        thumbnailUrl: widget.post.thumbnailUrl,
        mediaType: isVideo ? 'video' : 'image',
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
            if (item.isVideo) {
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

class _ImageSurface extends StatefulWidget {
  final String imageUrl;
  final IconData placeholderIcon;

  const _ImageSurface({
    required this.imageUrl,
    required this.placeholderIcon,
  });

  @override
  State<_ImageSurface> createState() => _ImageSurfaceState();
}

class _ImageSurfaceState extends State<_ImageSurface>
    with SingleTickerProviderStateMixin {
  final GlobalKey _imageKey = GlobalKey();
  late final TransformationController _transformationController;
  late final AnimationController _snapBackController;

  OverlayEntry? _zoomOverlay;
  Rect? _sourceRect;
  Matrix4 _overlayMatrix = Matrix4.identity();
  Animation<Matrix4>? _snapBackAnimation;
  bool _showOverlayImage = false;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    _snapBackController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    )
      ..addListener(_handleSnapBackTick)
      ..addStatusListener(_handleSnapBackStatus);
  }

  @override
  void dispose() {
    _removeZoomOverlay(resetController: false, notify: false);
    _snapBackController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  void _handleInteractionUpdate(ScaleUpdateDetails details) {
    final matrix = Matrix4.copy(_transformationController.value);
    final scale = matrix.getMaxScaleOnAxis();

    if (scale <= 1.01 && _zoomOverlay == null) return;

    _ensureZoomOverlay();
    if (_zoomOverlay == null) return;

    _overlayMatrix = matrix;
    _zoomOverlay?.markNeedsBuild();
  }

  void _handleInteractionEnd(ScaleEndDetails details) {
    if (_zoomOverlay == null) {
      _transformationController.value = Matrix4.identity();
      return;
    }

    _snapBackAnimation = Matrix4Tween(
      begin: Matrix4.copy(_overlayMatrix),
      end: Matrix4.identity(),
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
    _overlayMatrix = animation.value;
    _zoomOverlay?.markNeedsBuild();
  }

  void _handleSnapBackStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _removeZoomOverlay();
  }

  void _ensureZoomOverlay() {
    if (_zoomOverlay != null) return;

    final renderObject = _imageKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;

    final origin = renderObject.localToGlobal(Offset.zero);
    _sourceRect = origin & renderObject.size;
    _overlayMatrix = Matrix4.copy(_transformationController.value);

    _zoomOverlay = OverlayEntry(
      builder: (context) {
        final rect = _sourceRect;
        if (rect == null) return const SizedBox.shrink();

        return Positioned.fill(
          child: IgnorePointer(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: rect.left,
                  top: rect.top,
                  width: rect.width,
                  height: rect.height,
                  child: Transform(
                    transform: _overlayMatrix,
                    alignment: Alignment.topLeft,
                    child: RepaintBoundary(
                      child: _PostNetworkImage(
                        imageUrl: widget.imageUrl,
                        placeholderIcon: widget.placeholderIcon,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    Overlay.of(context, rootOverlay: true).insert(_zoomOverlay!);
    if (mounted) setState(() => _showOverlayImage = true);
  }

  void _removeZoomOverlay({
    bool resetController = true,
    bool notify = true,
  }) {
    _zoomOverlay?.remove();
    _zoomOverlay = null;
    _sourceRect = null;
    _overlayMatrix = Matrix4.identity();
    _snapBackAnimation = null;

    if (resetController) {
      _transformationController.value = Matrix4.identity();
    }

    if (mounted && notify) {
      setState(() => _showOverlayImage = false);
    } else {
      _showOverlayImage = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.imageUrl.trim().isEmpty) {
      return _MediaPlaceholder(icon: widget.placeholderIcon);
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
      child: InteractiveViewer(
        key: _imageKey,
        transformationController: _transformationController,
        minScale: 1,
        maxScale: 4,
        clipBehavior: Clip.hardEdge,
        onInteractionUpdate: _handleInteractionUpdate,
        onInteractionEnd: _handleInteractionEnd,
        child: Opacity(
          opacity: _showOverlayImage ? 0 : 1,
          child: _PostNetworkImage(
            imageUrl: widget.imageUrl,
            placeholderIcon: widget.placeholderIcon,
          ),
        ),
      ),
    );
  }
}

class _PostNetworkImage extends StatelessWidget {
  final String imageUrl;
  final IconData placeholderIcon;

  const _PostNetworkImage({
    required this.imageUrl,
    required this.placeholderIcon,
  });

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
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
  // Wrapper CachedVideoPlayerPlus — handle HLS (.m3u8) Bunny + disk cache.
  // Sama seperti Reels feed (lihat feed_screen.dart). Plain
  // VideoPlayerController.networkUrl kurang reliable untuk HLS signed URL;
  // wrapper ini expose .controller (underlying VideoPlayerController).
  CachedVideoPlayerPlus? _cachedPlayer;
  VideoPlayerController? _controller;
  bool _initializing = false;
  String? _error;
  // Init dari preferensi mute global (sinkron dgn feed_screen) — bukan
  // hardcode true, supaya konsisten dgn pilihan user di layar feed.
  bool _muted = appSettingsStore.feedMuted;
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
    final wrapper = CachedVideoPlayerPlus.networkUrl(
      Uri.parse(widget.mediaUrl),
      invalidateCacheIfOlderThan: const Duration(days: 7),
    );
    _cachedPlayer = wrapper;
    try {
      await wrapper.initialize();
      final controller = wrapper.controller;
      if (!mounted || _cachedPlayer != wrapper) {
        await wrapper.dispose();
        return;
      }
      _controller = controller;
      // Muted state ikut preferensi global (appSettingsStore.feedMuted),
      // sama seperti feed_screen — bukan selalu muted-by-default.
      await controller.setVolume(_muted ? 0 : 1);
      await controller.setLooping(true);
      setState(() => _initializing = false);
      // Apply current visibility — kalau sudah visible saat init selesai,
      // langsung play.
      _applyVisibility();
    } catch (_) {
      await wrapper.dispose();
      if (!mounted || _cachedPlayer != wrapper) return;
      setState(() {
        _cachedPlayer = null;
        _controller = null;
        _initializing = false;
        _error = 'Video belum bisa diputar';
      });
    }
  }

  Future<void> _disposeController() async {
    final wrapper = _cachedPlayer;
    final controller = _controller;
    _cachedPlayer = null;
    _controller = null;
    // Dispose via wrapper — handle underlying controller + cache reference.
    await controller?.pause();
    if (wrapper != null) {
      await wrapper.dispose();
    } else {
      await controller?.dispose();
    }
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

  Future<void> _toggleMute() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    AppHaptics.tap();
    final nextMuted = !_muted;
    // Write-back ke preferensi global (pola sama feed_screen :2947) —
    // toggle mute di post detail ikut sinkron balik ke layar feed.
    await appSettingsStore.setFeedMuted(nextMuted);
    await controller.setVolume(nextMuted ? 0 : 1);
    if (!mounted) return;
    setState(() => _muted = nextMuted);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;
    return VisibilityDetector(
      key: ValueKey('inline-video-${widget.postId}'),
      onVisibilityChanged: _onVisibilityChanged,
      child: AbsorbPointer(
        absorbing: false,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: Colors.black),
            if (ready)
              ClipRect(
                child: FittedBox(
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
            // bisa di-tap untuk mute/unmute. Sembunyi saat error/loading.
            if (ready && _error == null)
              Positioned(
                right: 10,
                bottom: 10,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleMute,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _muted
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded,
                      color: Colors.white,
                      size: 16,
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
      // Sengaja TIDAK ikut appSettingsStore.feedMuted — masuk fullscreen
      // adalah aksi eksplisit user utk nonton dgn suara (ala IG tap-to-
      // fullscreen), independen dari preferensi mute rail/inline feed.
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
    final cs = Theme.of(context).colorScheme;
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
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: Icon(Icons.edit_rounded, color: cs.onSurface),
              title: Text(
                'Edit caption',
                style: TextStyle(
                  color: cs.onSurface,
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
    final cs = Theme.of(context).colorScheme;
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
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Edit Caption',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Caption diubah akan kembali ke status menunggu review admin.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
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
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: 'Tulis caption…',
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
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
                        side: BorderSide(color: cs.outlineVariant),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Batal',
                        style: TextStyle(
                          color: cs.onSurface,
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
  final FeedPost post;
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
  // @mention autocomplete — attach ke input controller. Saat user ketik
  // `@partial`, panel suggestion muncul (search /api/users/search).
  late final MentionPickerController _mentionCtrl =
      MentionPickerController(textController: _inputController);
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
    _mentionCtrl.dispose();
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
      // Sync count ke FeedStore — semua screen lain (Reels, grid Postingan
      // Saya, public profile) yang baca commentCount lewat store akan
      // langsung ke-update. Tanpa ini, user tutup sheet → count Feed/grid
      // tetap stale sampai refresh.
      final fresh = feedStore.get(widget.post.id);
      final current = fresh?.commentCount ?? widget.post.commentCount;
      feedStore.setCommentCount(widget.post.id, current + 1);
    } catch (_) {
      if (!mounted) return;
      AppToast.show(context, 'Gagal kirim komentar, coba lagi');
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  /// Hapus komentar milik viewer sendiri. Optimistic remove + rollback
  /// kalau API gagal. Decrement commentCount di FeedStore (backend
  /// decrement hanya top-level — match pattern itu).
  Future<void> _deleteComment(FeedComment comment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Hapus komentar?'),
        content: const Text('Komentar akan dihapus permanen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFDC2626),
            ),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final isTopLevel = comment.parentCommentId == null;
    final snapshot = _comments;
    // Optimistic remove — top-level: drop dari list. Reply: drop dari
    // replies parent + recompute replyCount.
    setState(() {
      if (isTopLevel) {
        _comments = _comments.where((c) => c.id != comment.id).toList();
      } else {
        _comments = _comments.map((top) {
          if (top.id != comment.parentCommentId) return top;
          final newReplies =
              top.replies.where((r) => r.id != comment.id).toList();
          return top.copyWith(
            replies: newReplies,
            replyCount: newReplies.length,
          );
        }).toList();
      }
    });

    try {
      await feedService.deleteComment(comment.id);
      if (isTopLevel) {
        final fresh = feedStore.get(widget.post.id);
        final current = fresh?.commentCount ?? widget.post.commentCount;
        feedStore.setCommentCount(widget.post.id, current - 1);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _comments = snapshot);
      AppToast.show(context, 'Gagal hapus komentar, coba lagi');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  'Komentar',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              // Divider header sheet sengaja super halus di light (#EEF2F6)
              // seperti semula; dark pakai border gelap.
              Divider(
                height: 1,
                color: Theme.of(context).brightness == Brightness.dark
                    ? cs.outlineVariant
                    : const Color(0xFFEEF2F6),
              ),
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
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Center(
                        child: Text(
                          'Belum ada komentar.\nJadi yang pertama!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
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
                          // Hapus hanya untuk komentar milik viewer sendiri.
                          final isOwn = memberStore.profile?.id != null &&
                              c.author.id == memberStore.profile!.id;
                          return _CommentTile(
                            comment: c,
                            isReply: entry.isReply,
                            isCaption: false,
                            likeBusy: _likeBusy.contains(c.id),
                            onToggleLike: () => _toggleCommentLike(c),
                            onReply: () => _startReply(c),
                            onDelete: isOwn ? () => _deleteComment(c) : null,
                            onMentionTap: (handle) => Navigator.of(context)
                                .pushNamed('/u', arguments: handle),
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
                  color: cs.surfaceContainerHighest,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Membalas ${_replyingTo!.author.name}',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _cancelReply,
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              // @mention autocomplete panel — muncul di atas input row saat
              // user ketik `@partial`. darkTheme:false → tema terang sesuai
              // sheet ini (beda dgn FeedCommentSheet Reels yg dark).
              MentionSuggestionsPanel(
                controller: _mentionCtrl,
                darkTheme: false,
                maxHeight: 200,
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                decoration: BoxDecoration(
                  border: Border(
                    // Border atas input super halus di light (#EEF2F6)
                    // seperti semula; dark pakai border gelap.
                    top: BorderSide(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? cs.outlineVariant
                          : const Color(0xFFEEF2F6),
                      width: 1,
                    ),
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
                            : cs.onSurfaceVariant,
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
                          fillColor: cs.surfaceContainerHighest,
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

  /// Non-null kalau komentar ini milik viewer (boleh dihapus). Null = tidak
  /// tampil tombol "Hapus" (komentar orang lain / caption / non-owner).
  final VoidCallback? onDelete;

  /// Handle username untuk navigate saat tap @mention.
  final void Function(String handle)? onMentionTap;

  const _CommentTile({
    required this.comment,
    required this.isReply,
    required this.isCaption,
    required this.likeBusy,
    this.onToggleLike,
    this.onReply,
    this.onDelete,
    this.onMentionTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final liked = comment.viewerLiked;
    final author = comment.author;
    final canDelete = onDelete != null;
    // Long-press → action sheet (Salin/Balas/Hapus untuk komentar sendiri,
    // Salin/Balas/Lapor/Blokir untuk komentar orang lain). Sebelumnya
    // "Hapus" tampil INLINE merah di samping "Balas" → cluttered + risiko
    // mis-tap (label kecil 11px berdempetan). Match pola feed_comment_sheet
    // (Reels) + standar industri IG/TikTok/Shopee. Caption tile (isCaption
    // == true) tidak dapat long-press karena itu post sendiri (sudah ada
    // menu titik-tiga di header post).
    final body = Padding(
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
                      // @mention di-style + tappable + brand-override admin
                      // (officialMentions dari backend). Sebelumnya plain
                      // TextSpan → mention tidak ke-style/link.
                      ...buildMentionSpans(
                        comment.content,
                        onMentionTap: onMentionTap ?? (_) {},
                        defaultStyle: TextStyle(
                          color: cs.onSurface,
                          fontSize: isReply ? 13 : 13.5,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                        officialHandles: comment.officialMentions.toSet(),
                      ),
                    ],
                  ),
                  style: TextStyle(
                    color: cs.onSurface,
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
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (!isCaption && comment.likeCount > 0) ...[
                      const SizedBox(width: 12),
                      Text(
                        '${comment.likeCount} suka',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
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
                        child: Text(
                          'Balas',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                    // Hapus dipindah ke long-press action sheet (lihat
                    // _ModerationSheet wrapper di luar). Sebelumnya inline
                    // di samping "Balas" → mis-tap risk + visual noise.
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
                  color: liked ? const Color(0xFFE53935) : cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    // Caption = post itu sendiri (sudah punya menu titik-tiga di header
    // post). Tidak perlu long-press. Komentar/reply: long-press buka
    // action sheet — own → Hapus, others → Lapor + Blokir.
    if (isCaption) return body;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () {
        AppHaptics.tap();
        showModerationActions(
          context,
          targetKind: ReportTargetKind.feedComment,
          targetId: comment.id,
          authorId: author.id,
          // Sembunyikan nama author di header sheet untuk komentar sendiri
          // ("Lapor @nama"-style header tidak relevan). Untuk komentar
          // orang lain, tampilkan supaya user yakin lapor/blokir target
          // yang benar.
          authorName: canDelete ? null : author.name,
          allowBlock: !canDelete,
          allowSelfDelete: canDelete,
          onSelfDelete: canDelete && onDelete != null
              // _deleteComment di parent return Future<void>; bungkus jadi
              // Future<bool> yang sheet expect. Anggap true (UI optimistic
              // remove + toast error sudah handle di parent).
              ? () async {
                  onDelete!.call();
                  return true;
                }
              : null,
        );
      },
      child: body,
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
    final cs = Theme.of(context).colorScheme;
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
              color: cs.outlineVariant,
              margin: const EdgeInsets.only(right: 8),
            ),
            Text(
              expanded ? 'Sembunyikan balasan' : 'Lihat $replyCount balasan',
              style: TextStyle(
                color: cs.onSurfaceVariant,
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
///   - Video: 9:14 — lebih tinggi dari foto, mendekati Instagram video
///     post portrait, tapi tidak sepanjang Reels 9:16.
///     Instagram feed video post tanpa jadi Reels/fullscreen.
///   - Photo/carousel: pakai rasio image asli dengan batas Instagram:
///     portrait maksimum 4:5, landscape maksimum 1.91:1.
///
/// Default fallback 4:5 kalau type tidak diketahui.
double _safeAspectRatio(int width, int height, {FeedContentType? type}) {
  // Video: fixed 9:14 — halaman ini list posts, bukan Reels, tetapi
  // Instagram video post portrait terasa lebih tinggi dari foto 4:5.
  if (type == FeedContentType.video) {
    return 9 / 14;
  }
  if (width <= 0 || height <= 0) return 4 / 5;
  final ratio = width / height;
  if (ratio.isNaN || ratio.isInfinite || ratio <= 0) return 4 / 5;
  return ratio.clamp(4 / 5, 1.91).toDouble();
}

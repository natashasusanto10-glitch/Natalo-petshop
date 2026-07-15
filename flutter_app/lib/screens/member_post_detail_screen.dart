// ignore_for_file: use_build_context_synchronously
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shimmer/shimmer.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../config/api_config.dart';
import '../features/feed/video/post_video_coordinator.dart';
import '../features/feed/video/post_video_warm_handoff.dart';
import '../features/feed/video/video_player_session.dart';
import '../models/feed_post.dart';
import '../services/api_client.dart';
import '../services/feed_service.dart';
import '../services/video_quality_service.dart';
import '../state/feed_local_store.dart';
import '../state/feed_store.dart';
import '../state/member_store.dart';
import '../state/post_caption_session_store.dart';
import '../state/settings_store.dart';
import '../theme/natalo_colors.dart';
import '../utils/app_route_observer.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import '../widgets/app_toast.dart';
import '../widgets/feed_comment_sheet.dart';
import '../widgets/natalo_paw_refresh_indicator.dart';
import '../widgets/official_brand_avatar.dart';
import '../widgets/post_likers_sheet.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/scaled_video_feed_route.dart';
import '../shared/widgets/natalo_post_action_icon.dart';
import 'public_profile_screen.dart';
import 'scoped_video_feed_screen.dart';

/// Seam test-only untuk fetch post feed by ID di flow tap-video → scoped
/// viewer. `feedService` adalah singleton hard-wired ke `http.get` (tidak
/// injectable — lihat catatan di product_detail_screen_related_posts_test),
/// jadi widget test override lewat sini. Production: null → feedService.
@visibleForTesting
Future<FeedPost?> Function(String id)? debugScopedFeedPostFetcher;

/// Seam test-only untuk factory pembuat [PlaybackSession] milik coordinator
/// halaman (T3a). Produksi: null → [VideoPlayerSession] nyata (butuh plugin
/// video_player). Test menyuntik fake session (tanpa plugin native) untuk
/// memverifikasi wiring inline↔coordinator (attach/setActive/dormant/D3).
@visibleForTesting
PlaybackSessionFactory? debugPostVideoSessionFactory;

@visibleForTesting
void Function(String sessionId, String url)? debugPostVideoSessionUrlObserver;

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

  /// Author = akun official (Natalo Petshop) → render identitas brand:
  /// logo NL sebagai avatar + nama emas + rosette emas (seragam dgn
  /// feed/komentar/profil). Di-pass dari public profile (isOfficial).
  final bool authorIsOfficial;

  /// Owner mode flag. True (default) untuk "Postingan Saya" — show
  /// Edit/Delete menu di "...". False saat view post user lain — sembunyikan
  /// menu owner-only (edit caption + hapus), supaya tidak ada aksi destructive
  /// yang bocor ke viewer non-owner.
  final bool isOwner;
  final PostVideoWarmHandoff? warmVideoHandoff;
  final String? initialNextCursor;
  final ScopedPostPageLoader? loadMoreScopedPosts;

  const MemberPostDetailScreen({
    super.key,
    required this.post,
    this.posts,
    this.initialIndex = 0,
    this.authorName,
    this.authorPhotoUrl,
    this.authorInitial,
    this.authorIsOfficial = false,
    this.isOwner = true,
    this.warmVideoHandoff,
    this.initialNextCursor,
    this.loadMoreScopedPosts,
  });

  @override
  State<MemberPostDetailScreen> createState() => _MemberPostDetailScreenState();
}

class _MemberPostDetailScreenState extends State<MemberPostDetailScreen>
    with WidgetsBindingObserver, RouteAware {
  late final ScrollController _scrollController;
  late List<FeedPost> _posts;

  // ── Playback coordinator (T3a, plan 2026-07-13) ─────────────────────
  // Coordinator memiliki SEMUA controller video di halaman ini + fullscreen
  // handoff. Lifecycle (background/foreground + route push/pop) didaftarkan
  // SEKALI di sini (§2.5), bukan per _InlineVideoPlayer.
  late final PostVideoCoordinator _videoCoordinator;

  /// Seam test-only: verifikasi wiring handoff (mis. `_endHandoff`
  /// re-aktifkan origin, bukan active B basi). Produksi tidak memakainya.
  @visibleForTesting
  PostVideoCoordinator get debugVideoCoordinator => _videoCoordinator;

  @visibleForTesting
  String? debugVideoUrlForSession(String sessionId) => _videoUrls[sessionId];

  @visibleForTesting
  Future<String?> debugRefreshVideoUrlForTest(String sessionId) =>
      _refreshVideoUrl(sessionId);

  /// URL video per sessionId (== post.id untuk video utama; compound
  /// `${post.id}-$index` untuk item carousel). Diisi di initState untuk video
  /// utama + di-register on-demand oleh inline (carousel). Factory sesi baca
  /// dari sini — coordinator sendiri plugin-free & tak tahu URL.
  final Map<String, String> _videoUrls = {};
  final Map<String, GlobalKey> _videoAnchorKeys = {};
  late NetworkTier _playbackNetworkTier;

  /// True selama transisi buka/tutup fullscreen scoped (§2.6 + D5). Selama
  /// ini, cover-pause route-push TIDAK memicu `pauseAll` (controller asal
  /// tetap pinned + posisinya dijaga untuk resume instan saat kembali).
  bool _handoffInProgress = false;

  /// SessionId video ASAL yang sedang di-handoff ke fullscreen. Inline dengan
  /// sessionId ini masuk mode DORMANT (frozen frame, berhenti lapor
  /// visibilitas) supaya tidak mengadu playback dengan fullscreen.
  String? _handoffSessionId;

  /// Lifecycle app terkini (level halaman, §2.5). Dipakai untuk memutuskan
  /// apakah `_endHandoff` boleh `resumeAll`: kalau app sedang TIDAK resumed
  /// (mis. user background-kan app saat fetch handoff gagal), JANGAN resume —
  /// biarkan transisi ke `resumed` nanti yang memicu resume, supaya tak ada
  /// audio hantu di jalur fetch-fail-while-backgrounded.
  AppLifecycleState _lastLifecycle = AppLifecycleState.resumed;
  // Track liked state per post id — optimistic toggle, source-of-truth
  // sampai backend respons confirm.
  final Map<String, bool> _likedCache = {};
  final Set<String> _shareInFlight = <String>{};
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
    _playbackNetworkTier = videoQualityService.currentTier;
    // Prapopulasi URL video utama tiap post (video item non-carousel).
    for (final post in _posts) {
      if (post.isVideo) {
        _videoUrls[post.id] = _resolvePostVideoUrl(post);
      }
    }
    // Coordinator dimiliki halaman: factory bikin sesi VideoPlayerSession
    // nyata (atau fake via seam test). Listener feedMuted hidup di coordinator.
    _videoCoordinator = PostVideoCoordinator(
      sessionFactory: (sessionId) {
        final url = _resolveSessionVideoUrl(sessionId);
        debugPostVideoSessionUrlObserver?.call(sessionId, url);
        final debugFactory = debugPostVideoSessionFactory;
        if (debugFactory != null) return debugFactory(sessionId);
        return VideoPlayerSession(
          url: url,
          hasAudio: _postForSession(sessionId)?.hasAudio != false,
          analyticsPostId: sessionId,
          analyticsSurface: 'postingan',
          // D4: refresh signed URL expired best-effort — re-fetch post
          // dari API yang meng-sign ulang URL Bunny tiap request.
          urlRefresher: () => _refreshVideoUrl(sessionId),
        );
      },
    );
    final warmHandoff = widget.warmVideoHandoff;
    final warmSession = warmHandoff?.claim(
      postId: widget.post.id,
      url: _resolvePostVideoUrl(widget.post),
      hasAudio: widget.post.hasAudio != false,
    );
    if (warmSession != null) {
      _videoCoordinator.adoptSession(widget.post.id, warmSession);
    } else if (warmHandoff != null) {
      // A stale/mismatched handoff must not keep a second controller alive
      // until the source route eventually regains control.
      unawaited(warmHandoff.disposeIfUnclaimed());
    }
    // Lifecycle app (background/foreground) — pause/resume SEMUA sesi (§2.5),
    // menutup audio hantu #2. Route visibility didaftarkan di
    // didChangeDependencies (butuh context).
    WidgetsBinding.instance.addObserver(this);
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

  FeedPost? _postForSession(String sessionId) {
    for (final post in _posts) {
      if (sessionId == post.id || sessionId.startsWith('${post.id}-')) {
        return post;
      }
    }
    return null;
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
          post.shareCount != fresh.shareCount ||
          !_sameLikerIds(post.recentLikers, fresh.recentLikers)) {
        _likedCache[post.id] = freshLiked;
        _posts[i] = _withInteractionUpdate(
          post,
          likeCount: fresh.likeCount,
          liked: freshLiked,
          commentCount: fresh.commentCount,
          shareCount: fresh.shareCount,
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    // RouteAware SEKALI di level halaman (§2.5) — pause deterministik saat
    // route lain (opaque) menutup halaman, resume saat kembali.
    final route = ModalRoute.of(context);
    if (route != null) {
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lastLifecycle = state;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        _videoCoordinator.pauseAll();
      case AppLifecycleState.resumed:
        // Selama handoff, fullscreen di atas yang mengurus playback; jangan
        // resume video asal di belakang (akan bersuara di balik fullscreen).
        if (!_handoffInProgress) {
          _videoCoordinator.resumeAll();
        }
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  void didPushNext() {
    // Route opaque didorong di atas halaman → pause semua sesi. DIKECUALIKAN
    // saat handoff fullscreen (§2.6 + D5): video asal tetap pinned & posisinya
    // dijaga; `_openScopedVideoFeed` sudah men-pause inline via reportHidden
    // tanpa men-suspend coordinator, supaya resume saat kembali instan.
    if (_handoffInProgress) return;
    if (lastPushedRouteIsOpaque()) {
      _videoCoordinator.pauseAll();
    }
  }

  @override
  void didPopNext() {
    // Kembali ke halaman dari route non-handoff (mis. detail produk) →
    // resume. Untuk handoff, resume diurus di `_openScopedVideoFeed` setelah
    // await push selesai (urutan re-attach → setOrigin(null), §2.6).
    if (_handoffInProgress) return;
    _videoCoordinator.resumeAll();
  }

  /// Dipanggil inline saat hendak attach — mendaftarkan URL sessionId supaya
  /// factory coordinator bisa membuat sesi (dipakai item carousel dengan
  /// compound id; video utama sudah diprapopulasi di initState).
  void _registerVideoUrl(String sessionId, String url) {
    _videoUrls[sessionId] = url;
  }

  String _resolvePostVideoUrl(FeedPost post) =>
      videoQualityService.resolvePlaybackUrl(
        post.videoPlaybackUrl,
        dataSaverUrl: post.videoDataSaverUrl,
        userPreference: appSettingsStore.feedVideoQuality,
        // Tier berasal dari lifecycle fullscreen, bukan override test.
        // ignore: invalid_use_of_visible_for_testing_member
        networkTier: _playbackNetworkTier,
      );

  String _resolveMediaVideoUrl(FeedMedia media) =>
      videoQualityService.resolvePlaybackUrl(
        media.mediaUrl,
        dataSaverUrl: media.videoDataSaverUrl,
        userPreference: appSettingsStore.feedVideoQuality,
        // Tier berasal dari lifecycle fullscreen, bukan override test.
        // ignore: invalid_use_of_visible_for_testing_member
        networkTier: _playbackNetworkTier,
      );

  String _resolveSessionVideoUrl(String sessionId) {
    final postIndex = _posts.indexWhere((post) => post.id == sessionId);
    if (postIndex >= 0) {
      final url = _resolvePostVideoUrl(_posts[postIndex]);
      _videoUrls[sessionId] = url;
      return url;
    }
    return _videoUrls[sessionId] ?? '';
  }

  void _onPlaybackNetworkTierChanged(NetworkTier tier) {
    _playbackNetworkTier = tier;
  }

  @visibleForTesting
  void debugSetPlaybackNetworkTier(NetworkTier tier) {
    _onPlaybackNetworkTierChanged(tier);
  }

  /// D4 — ambil URL video bertanda-tangan SEGAR untuk [sessionId] dari API
  /// (`GET /api/feed/posts/:id` → `signBunnyUrl`, sign ulang tiap request).
  /// Dipanggil oleh [VideoPlayerSession] hanya saat init gagal DAN URL lama
  /// bertanda-tangan (kemungkinan expired). Best-effort: null bila gagal /
  /// tak ada URL — caller jatuh ke tombol "Coba lagi".
  ///
  /// `sessionId` untuk video utama == post.id; item carousel == `${id}-$idx`.
  Future<String?> _refreshVideoUrl(String sessionId) async {
    // Turunkan post.id nyata: kalau sessionId dikenal langsung (video utama)
    // pakai apa adanya; kalau tidak, kupas sufiks `-<index>` (carousel).
    var postId = sessionId;
    int? carouselIndex;
    if (!_posts.any((p) => p.id == sessionId)) {
      final dash = sessionId.lastIndexOf('-');
      if (dash > 0) {
        final maybeIndex = int.tryParse(sessionId.substring(dash + 1));
        if (maybeIndex != null) {
          postId = sessionId.substring(0, dash);
          carouselIndex = maybeIndex;
        }
      }
    }
    try {
      final fetchById = debugScopedFeedPostFetcher ?? feedService.fetchPostById;
      final fresh = await fetchById(postId);
      if (fresh == null) return null;
      String? url;
      if (carouselIndex != null &&
          carouselIndex >= 0 &&
          carouselIndex < fresh.mediaItems.length) {
        final item = fresh.mediaItems[carouselIndex];
        final playbackUrl = _resolveMediaVideoUrl(item);
        url = playbackUrl.trim().isNotEmpty ? playbackUrl : null;
      } else {
        final playbackUrl = _resolvePostVideoUrl(fresh);
        url = playbackUrl.trim().isNotEmpty ? playbackUrl : null;
      }
      if (url == null || url.trim().isEmpty) return null;
      _videoUrls[sessionId] = url;
      return url;
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    feedStore.removeListener(_onFeedStoreChanged);
    appRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _videoCoordinator.dispose();
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
    } on FeedViewerChangedException {
      // Ignore stale completion from the previous authenticated viewer.
    } catch (_) {
      if (!mounted) return;
      AppToast.show(context, 'Gagal update suka, coba lagi');
    }
  }

  Future<void> _shareNative(int index) async {
    final post = _posts[index];
    if (!_shareInFlight.add(post.id)) return;
    AppHaptics.tap();
    final url = '${ApiConfig.publicSiteUrl}/feed/${post.slug}';
    final captionSnippet = (post.caption ?? '').trim();
    final text =
        captionSnippet.isEmpty ? url : '${truncate(captionSnippet, 120)}\n$url';
    try {
      final box = context.findRenderObject() as RenderBox?;
      final result = await Share.share(
        text,
        sharePositionOrigin:
            box != null ? box.localToGlobal(Offset.zero) & box.size : null,
      );
      if (result.status != ShareResultStatus.success || !mounted) return;
      feedStore.incrementShareCount(post.id);
      final serverCount = await feedService.trackShare(post.id);
      if (serverCount != null) feedStore.setShareCount(post.id, serverCount);
    } catch (_) {
      // Fail silent — user cancelled / share sheet error.
    } finally {
      _shareInFlight.remove(post.id);
    }
  }

  Future<void> _openComments(int index) async {
    AppHaptics.tap();
    final post = _posts[index];
    await showFeedCommentDrawer(context, post: post);
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
            0,
            newCaption.length > 80 ? 80 : newCaption.length,
          );
    try {
      await apiClient.patchJson(
        '/api/feed/posts/${Uri.encodeComponent(post.id)}',
        body: {'title': syncedTitle, 'description': newCaption},
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
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFDC2626),
            ),
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
    // Capture before starting HTTP. A like/comment completed while these
    // requests are in flight must remain newer than the returned snapshots.
    final fetchedAt = DateTime.now();
    final results = await Future.wait(
      _posts.map(
        (p) => feedService.fetchPostById(p.id).catchError((_) {
          return null;
        }),
      ),
    );
    if (!mounted) return;
    final freshPosts = results.whereType<FeedPost>().toList(growable: false);
    if (freshPosts.isEmpty) return;
    feedStore.mergeFromServer(freshPosts, fetchedAt: fetchedAt);

    var anyChanged = false;
    for (var i = 0; i < _posts.length; i++) {
      final fresh = results[i];
      if (fresh == null) continue;
      final canonical = feedStore.get(fresh.id) ?? fresh;
      _posts[i] = canonical;
      _likedCache[canonical.id] = canonical.viewerLiked || canonical.isLiked;
      anyChanged = true;
    }
    if (anyChanged) {
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
          icon: Icon(Icons.arrow_back_rounded, color: cs.onSurface, size: 26),
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
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    _memberName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      // Official → emas identitas brand (sheet putih).
                      color: widget.authorIsOfficial
                          ? NataloColors.officialGoldOnLight
                          : cs.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1.05,
                    ),
                  ),
                ),
                if (widget.authorIsOfficial) ...[
                  const SizedBox(width: 3),
                  const OfficialVerifiedBadge(size: 12),
                ],
              ],
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
                    coordinator: _videoCoordinator,
                    registerVideoUrl: _registerVideoUrl,
                    handoffSessionId: _handoffSessionId,
                    memberName: _memberName,
                    memberInitial: _memberInitial,
                    memberPhotoUrl: _memberPhotoUrl,
                    memberIsOfficial: widget.authorIsOfficial,
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
                    onOpenScopedFeed: (sessionId, anchorKey) =>
                        _openScopedVideoFeed(index, sessionId, anchorKey),
                    onVideoAnchorReady: (postId, anchorKey) {
                      _videoAnchorKeys[postId] = anchorKey;
                    },
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
    int? shareCount,
    List<FeedAuthor>? recentLikers,
  }) {
    return post.copyWith(
      likeCount: likeCount,
      commentCount: commentCount,
      shareCount: shareCount,
      viewerLiked: liked,
      isLiked: liked,
      recentLikers: recentLikers,
    );
  }

  /// Tap video di detail → buka viewer imersif seketika dengan video yang
  /// sudah tersedia di halaman ini. Data lokal sengaja menjadi seed viewer:
  /// selain menghapus round-trip jaringan dari jalur tap, data ini juga sudah
  /// membawa konteks produk yang dipakai commerce chip.
  Future<void> _openScopedVideoFeed(
    int index,
    String sessionId,
    GlobalKey anchorKey,
  ) async {
    final videoPosts = _posts.where((p) => p.isVideo).toList();
    if (videoPosts.isEmpty) return;
    final tapped = _posts[index];
    final hydrationRequestedAt = DateTime.now();
    final hydrationViewerGeneration = memberStore.viewerGeneration;
    final hydratedPosts = _hydrateScopedVideoPosts(videoPosts);
    final hydration = ScopedVideoFeedHydration(
      posts: hydratedPosts,
      requestedAt: hydrationRequestedAt,
      viewerGeneration: hydrationViewerGeneration,
    );

    // ── Handoff mulai (§2.6 + D5) ──
    // 1. Pin video asal di coordinator (origin) — tak akan dieviction selama
    //    fullscreen terbuka.
    // 2. Tandai handoff berlangsung → cover-pause route-push (didPushNext)
    //    TIDAK memicu pauseAll (D5); video asal tetap pinned + posisinya
    //    dijaga untuk resume instan.
    // 3. Set _handoffSessionId → inline masuk mode DORMANT (frozen frame).
    // 4. Pause inline via reportHidden (BUKAN pauseAll) — hentikan audio di
    //    belakang tanpa men-suspend coordinator, supaya reportVisible/resume
    //    saat kembali langsung jalan. Pause TIDAK mereset posisi (timestamp
    //    lanjut saat kembali).
    _handoffInProgress = true;
    _videoCoordinator.setOrigin(sessionId);
    _videoCoordinator.reportHidden(sessionId);
    if (mounted) setState(() => _handoffSessionId = sessionId);

    // Hardening (review): SELALU akhiri handoff lewat `finally` supaya flag
    // `_handoffInProgress`/`_handoffSessionId` TAK PERNAH nyangkut walau route
    // gagal dibuka. Semantik resume:
    // normal/return = resume true; unmounted = resume false.
    var resume = true;
    final reverseMorphEnabled = ValueNotifier<bool>(true);
    final reverseTarget = ValueNotifier<ScaledVideoFeedReverseTarget?>(null);
    var returnPreparationStarted = false;
    try {
      final tappedIndex = videoPosts.indexWhere((post) => post.id == tapped.id);
      final result = await pushScaledVideoFeed<ScopedVideoFeedResult>(
        context,
        thumbnailKey: anchorKey,
        thumbnailImageUrl: tapped.previewMediaUrl,
        thumbnailBorderRadius: 0,
        reverseMorphEnabled: reverseMorphEnabled,
        reverseTarget: reverseTarget,
        destinationBuilder: (_) => ScopedVideoFeedScreen(
          posts: videoPosts,
          hydration: hydration,
          initialNextCursor: widget.initialNextCursor,
          loadMorePosts:
              widget.loadMoreScopedPosts == null ? null : _loadMoreScopedPosts,
          initialIndex: tappedIndex >= 0 ? tappedIndex : 0,
          // Handoff §2.6: item ASAL pinjam controller coordinator (instan).
          coordinator: _videoCoordinator,
          originPostId: sessionId,
          onNetworkTierChanged: _onPlaybackNetworkTierChanged,
          onActivePostChanged: (postId) {
            reverseMorphEnabled.value = postId == tapped.id;
          },
          onPrepareClose: (result, signal) async {
            // The viewer may time this preparation out so navigation never
            // blocks. Record that reconciliation already started before the
            // first await; the route result must not launch a second seek or
            // scroll while this cooperative callback is winding down.
            returnPreparationStarted = true;
            await _focusReturnedVideo(result, closeSignal: signal);
            if (signal.isCancelled) return;
            if (!mounted) return;
            final targetKey = _videoAnchorKeys[result.postId];
            final box =
                targetKey?.currentContext?.findRenderObject() as RenderBox?;
            final targetPost = _posts.cast<FeedPost?>().firstWhere(
                  (post) => post?.id == result.postId,
                  orElse: () => null,
                );
            if (box == null || !box.hasSize || targetPost == null) return;
            reverseTarget.value = ScaledVideoFeedReverseTarget(
              rect: box.localToGlobal(Offset.zero) & box.size,
              imageUrl: targetPost.previewMediaUrl,
            );
            reverseMorphEnabled.value = true;
          },
        ),
      );
      if (!mounted) {
        resume = false;
        return;
      }
      if (result != null && mounted && !returnPreparationStarted) {
        await _focusReturnedVideo(result);
      }
    } finally {
      reverseMorphEnabled.dispose();
      reverseTarget.dispose();
      // ── Handoff selesai (kembali dari fullscreen / batal) ──
      // Urutan §2.6: re-attach/resume video asal DULU, baru setOrigin(null).
      _endHandoff(resume: resume);
    }
  }

  Future<FeedPage> _loadMoreScopedPosts(String? cursor) async {
    final loader = widget.loadMoreScopedPosts;
    if (loader == null) return const FeedPage();
    final page = await loader(cursor);
    final freshPosts = page.items.where((post) {
      return !_posts.any((existing) => existing.id == post.id);
    }).toList(growable: false);
    for (final post in page.items.where((post) => post.isVideo)) {
      _videoUrls[post.id] = _resolvePostVideoUrl(post);
    }
    if (freshPosts.isNotEmpty && mounted) {
      feedStore.mergeFromServer(freshPosts, fetchedAt: DateTime.now());
      setState(() {
        _posts = [..._posts, ...freshPosts];
        _postKeys.addAll(
          List<GlobalKey>.generate(freshPosts.length, (_) => GlobalKey()),
        );
      });
    }
    return page;
  }

  Future<List<FeedPost>> _hydrateScopedVideoPosts(
    List<FeedPost> source,
  ) async {
    final fetchById = debugScopedFeedPostFetcher ?? feedService.fetchPostById;
    return Future.wait(
      source.map((localPost) async {
        try {
          final fresh = await fetchById(localPost.id);
          if (fresh == null) return localPost;
          final freshHasProducts =
              fresh.taggedProducts.isNotEmpty || fresh.products.isNotEmpty;
          final localHasProducts = localPost.taggedProducts.isNotEmpty ||
              localPost.products.isNotEmpty;
          if (!freshHasProducts && localHasProducts) {
            return fresh.copyWith(
              products: localPost.products,
              productsInVideo: localPost.productsInVideo,
              taggedProducts: localPost.taggedProducts.isNotEmpty
                  ? localPost.taggedProducts
                  : localPost.products,
            );
          }
          return fresh;
        } catch (_) {
          return localPost;
        }
      }),
    );
  }

  Future<void> _focusReturnedVideo(
    ScopedVideoFeedResult result, {
    ScopedVideoFeedCloseSignal? closeSignal,
  }) async {
    if (closeSignal?.isCancelled == true) return;
    final index = _posts.indexWhere((post) => post.id == result.postId);
    if (index < 0) return;

    // Keep the destination inline dormant while the list is repositioned.
    _scrollController.jumpTo(
      (_estimatedPostExtent(context) * index)
          .clamp(0.0, _scrollController.position.maxScrollExtent),
    );
    if (mounted) setState(() => _handoffSessionId = result.postId);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || closeSignal?.isCancelled == true) return;
    final targetContext = _postKeys[index].currentContext;
    if (targetContext != null) {
      await Scrollable.ensureVisible(
        targetContext,
        duration: Duration.zero,
        // Centering prevents a neighboring tall video from also crossing the
        // 60% autoplay threshold and stealing coordinator activity.
        alignment: 0.5,
      );
    }
    if (!mounted || closeSignal?.isCancelled == true) return;
    // The result timestamp is read from this same coordinator session. Do not
    // issue a second platform seek while preparing the reverse transition:
    // Future.timeout cannot cancel an in-flight seek, so it could otherwise
    // complete after the inline player has resumed and jump it backwards.
  }

  /// Akhiri transisi handoff fullscreen: clear flag, re-aktifkan video asal
  /// (kalau [resume]) SEBELUM unpin origin (§2.6), lalu keluar mode dormant.
  void _endHandoff({required bool resume}) {
    _handoffInProgress = false;
    final origin = _handoffSessionId;
    final resumed = _lastLifecycle == AppLifecycleState.resumed;
    // BUG FIX (T7-integrasi): saat user swipe menjauh di fullscreen, active
    // coordinator jadi B/C — dan B kini OFFSCREEN. Kalau kita cuma
    // `resumeAll()`, ia memutar active BASI (B) → audio hantu (unmuted) /
    // video salah main tak terlihat (acceptance "nol audio hantu"). Jadi:
    // SEBELUM resume, re-point active ke origin kalau sudah menjauh.
    if (resume && origin != null && _videoCoordinator.activePostId != origin) {
      // setActive(origin): pause + mute active lama (B), jadikan origin active,
      // lalu play SEKALI di timestamp-nya. (Bukan resumeAll — itu akan memutar
      // B basi.)
      _videoCoordinator.setActive(origin);
      // Hormati guard lifecycle (hardening T3b): kalau app TIDAK resumed,
      // origin tak boleh berbunyi sekarang. Ia sudah jadi active, jadi
      // suspend lagi — transisi ke `resumed` nanti (didChangeAppLifecycleState)
      // yang memutar origin (bukan B basi).
      if (!resumed) _videoCoordinator.pauseAll();
    } else if (resume && resumed) {
      // No-swipe (active == origin): resume instan seperti sebelum — origin
      // langsung main lagi, tidak ada regresi / double play.
      _videoCoordinator.resumeAll();
    }
    _videoCoordinator.setOrigin(null);
    if (mounted) {
      setState(() => _handoffSessionId = null);
    } else {
      _handoffSessionId = null;
    }
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

  /// Coordinator playback milik halaman (T3a) — inline video meminjam sesi
  /// darinya alih-alih membuat controller sendiri.
  final PostVideoCoordinator coordinator;

  /// Daftarkan URL sessionId ke halaman supaya factory coordinator bisa
  /// membuat sesi (item carousel dengan compound id).
  final void Function(String sessionId, String url) registerVideoUrl;

  /// SessionId yang sedang di-handoff ke fullscreen → inline dengan id ini
  /// masuk mode dormant (frozen frame). Null = tak ada handoff.
  final String? handoffSessionId;

  final String memberName;
  final String memberInitial;
  final String? memberPhotoUrl;

  /// Author = akun official → logo NL + nama emas + rosette di author row.
  final bool memberIsOfficial;
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
  // Tap video → buka viewer feed scoped (swipeable) berisi HANYA video
  // milik user ini. State yang punya list `_posts` menyuplai callback ini
  // (sessionId video asal utk handoff coordinator + anchorKey utk transisi
  // morph-scale).
  final void Function(String sessionId, GlobalKey anchorKey)? onOpenScopedFeed;
  final void Function(String postId, GlobalKey anchorKey)? onVideoAnchorReady;

  const _PostFeedItem({
    super.key,
    required this.post,
    required this.coordinator,
    required this.registerVideoUrl,
    required this.handoffSessionId,
    required this.memberName,
    required this.memberInitial,
    required this.memberPhotoUrl,
    this.memberIsOfficial = false,
    required this.liked,
    this.showMenu = true,
    this.showStatusBadge = true,
    required this.onLike,
    required this.onComment,
    required this.onShare,
    required this.onMenuTap,
    this.onOpenScopedFeed,
    this.onVideoAnchorReady,
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
        tween: Tween(
          begin: 1.0,
          end: 1.32,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.32,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 55,
      ),
    ]).animate(_heartScaleController);

    _heartBurstController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );
    _burstScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 0.35,
          end: 1.42,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 34,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.42,
          end: 1.00,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 22,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.00,
          end: 0.82,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 18,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 0.82,
          end: 0.0,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 26,
      ),
    ]).animate(_heartBurstController);
    _burstOpacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 0.0,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 25,
      ),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 38),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 0.0,
        ).chain(CurveTween(curve: Curves.easeIn)),
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
            isOfficial: widget.memberIsOfficial,
            onMenuTap: widget.onMenuTap,
          ),
        // Double-tap detector wrap media: signature Instagram-feel "tap
        // dua kali untuk like". Single tap ke media tetap fall-through
        // ke gesture detector dalam (mis. _InlineVideoPlayer onTap →
        // fullscreen). PageView swipe horizontal di carousel juga tetap
        // jalan karena swipe ≠ tap gesture.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTapDown: post.isVideo ? null : _rememberHeartBurstPosition,
          onDoubleTap: post.isVideo ? null : _handleDoubleTap,
          child: Stack(
            children: [
              _PostMediaSurface(
                post: post,
                coordinator: widget.coordinator,
                registerVideoUrl: widget.registerVideoUrl,
                handoffSessionId: widget.handoffSessionId,
                // Tap video → buka viewer feed scoped (swipeable) ke semua
                // video user ini (konsisten dgn flow "Postingan Terkait").
                // Coordinator handoff (§2.6) diurus di level halaman.
                onVideoExpandRequested: (sessionId, anchorKey) {
                  widget.onOpenScopedFeed?.call(sessionId, anchorKey);
                },
                onVideoAnchorReady: widget.onVideoAnchorReady,
              ),
              if (post.isVideo)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _VideoPostAuthorOverlay(
                    memberName: memberName,
                    memberInitial: memberInitial,
                    memberPhotoUrl: memberPhotoUrl,
                    isOfficial: widget.memberIsOfficial,
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
            child: _LikedByLine(post: post),
          ),
        ],
        // Caption — kalau ada saja.
        if ((post.caption ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
            child: PostCaption(
              postId: post.id,
              memberName: memberName,
              caption: post.caption!,
              isOfficial: widget.memberIsOfficial,
            ),
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

  /// Akun official → logo NL + nama emas + rosette (identitas brand).
  final bool isOfficial;
  // Nullable — non-owner viewer tidak punya menu actions di sini.
  final VoidCallback? onMenuTap;

  const _PostAuthorRow({
    required this.memberName,
    required this.memberInitial,
    required this.memberPhotoUrl,
    this.isOfficial = false,
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
            isOfficial: isOfficial,
            plain: isOfficial,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    memberName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      // Official → emas identitas (latar putih).
                      color: isOfficial
                          ? NataloColors.officialGoldOnLight
                          : cs.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
                  ),
                ),
                if (isOfficial) ...[
                  const SizedBox(width: 4),
                  const OfficialVerifiedBadge(size: 15),
                ],
              ],
            ),
          ),
          if (onMenuTap != null)
            IconButton(
              onPressed: onMenuTap,
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.more_horiz_rounded, color: cs.onSurface),
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

  /// Akun official → logo NL + nama emas + rosette (identitas brand).
  final bool isOfficial;

  const _VideoPostAuthorOverlay({
    required this.memberName,
    required this.memberInitial,
    required this.memberPhotoUrl,
    this.isOfficial = false,
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
              isOfficial: isOfficial,
              plain: isOfficial,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      memberName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        // Official → emas identitas (overlay gelap).
                        color: isOfficial
                            ? NataloColors.officialGold
                            : Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                        shadows: const [
                          Shadow(color: Colors.black54, blurRadius: 10),
                        ],
                      ),
                    ),
                  ),
                  if (isOfficial) ...[
                    const SizedBox(width: 4),
                    const OfficialVerifiedBadge(size: 15),
                  ],
                ],
              ),
            ),
            if (onMenuTap != null)
              IconButton(
                onPressed: onMenuTap,
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.more_horiz_rounded,
                  color: Colors.white,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 10)],
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

  const _LikedByLine({required this.post});

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

  const _LikedAvatarStack({required this.likers, required this.likeCount});

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
                      isOfficial: visible[1].isOfficialAccount,
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
                    isOfficial: visible.first.isOfficialAccount,
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
  final bool isOfficial;

  const _MiniAvatar({
    required this.size,
    this.photoUrl,
    this.initial,
    this.backgroundColor,
    this.isOfficial = false,
  });

  factory _MiniAvatar.member({
    required String initial,
    required String? photoUrl,
    required bool isOfficial,
    required double size,
  }) =>
      _MiniAvatar(
        size: size,
        photoUrl: photoUrl,
        initial: initial,
        isOfficial: isOfficial,
      );

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
      child: backgroundColor != null
          ? _miniAvatarFallback(cs)
          : ProfileAvatar(
              initial: initial ?? 'N',
              imageUrl: url,
              size: size,
              fontSize: size * 0.45,
              isOfficial: isOfficial,
              plain: true,
            ),
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

/// Caption renderer for post detail. Public to allow focused widget tests.
class PostCaption extends StatefulWidget {
  final String postId;
  final String memberName;
  final String caption;

  /// Akun official → nama author di prefix caption pakai emas identitas.
  final bool isOfficial;

  const PostCaption({
    super.key,
    required this.postId,
    required this.memberName,
    required this.caption,
    this.isOfficial = false,
  });

  @override
  State<PostCaption> createState() => _PostCaptionState();
}

class _PostCaptionState extends State<PostCaption>
    with SingleTickerProviderStateMixin {
  late final TapGestureRecognizer _expandRecognizer = TapGestureRecognizer()
    ..onTap = _expand;

  @override
  void initState() {
    super.initState();
    postCaptionSessionStore.addListener(_onSessionChanged);
  }

  void _onSessionChanged() {
    if (mounted) setState(() {});
  }

  void _expand() {
    postCaptionSessionStore.markExpanded(widget.postId);
  }

  @override
  void dispose() {
    postCaptionSessionStore.removeListener(_onSessionChanged);
    _expandRecognizer.dispose();
    super.dispose();
  }

  TextStyle _style(BuildContext context) => TextStyle(
        color: Theme.of(context).colorScheme.onSurface,
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
        height: 1.35,
      );

  String? _truncatedCaption(
      BuildContext context, double width, TextStyle style) {
    final full = widget.caption.trim();
    final codePoints = full.runes.toList();
    const suffix = '... selengkapnya';
    TextSpan span(String text) => TextSpan(children: [
          TextSpan(
              text: '${widget.memberName} ',
              style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: widget.isOfficial
                      ? NataloColors.officialGoldOnLight
                      : null)),
          TextSpan(text: text),
        ]);
    bool fits(String text) {
      final p = TextPainter(
          text: TextSpan(style: style, children: span(text).children),
          textAlign: TextAlign.start,
          textDirection: TextDirection.ltr,
          maxLines: 2,
          textScaler: MediaQuery.textScalerOf(context),
          strutStyle: StrutStyle.fromTextStyle(style));
      p.layout(maxWidth: width);
      return !p.didExceedMaxLines;
    }

    if (fits(full)) return null;
    String prefix(int count) => String.fromCharCodes(codePoints.take(count));
    var lo = 0, hi = codePoints.length;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (fits('${prefix(mid).trimRight()}$suffix')) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return '${prefix(lo).trimRight()}$suffix';
  }

  @override
  Widget build(BuildContext context) {
    final expanded = postCaptionSessionStore.isExpanded(widget.postId);
    final style = _style(context);
    return LayoutBuilder(builder: (context, constraints) {
      final truncated = expanded
          ? null
          : _truncatedCaption(context, constraints.maxWidth, style);
      final text = truncated ?? widget.caption.trim();
      // Only generated truncation may activate the affordance. A naturally
      // short caption containing this literal phrase remains plain text.
      final suffixIndex =
          truncated == null ? -1 : text.lastIndexOf('... selengkapnya');
      final span = TextSpan(children: [
        TextSpan(
            text: '${widget.memberName} ',
            style: TextStyle(
                fontWeight: FontWeight.w900,
                color: widget.isOfficial
                    ? NataloColors.officialGoldOnLight
                    : null)),
        if (suffixIndex >= 0 && !expanded) ...[
          TextSpan(text: text.substring(0, suffixIndex + 4)),
          TextSpan(
              text: 'selengkapnya',
              recognizer: _expandRecognizer,
              style: const TextStyle(fontWeight: FontWeight.w800)),
        ] else
          TextSpan(text: text),
      ]);
      return AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          child: Text.rich(span, style: style));
    });
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
  final PostVideoCoordinator coordinator;
  final void Function(String sessionId, String url) registerVideoUrl;
  final String? handoffSessionId;
  final void Function(String sessionId, GlobalKey anchorKey)?
      onVideoExpandRequested;
  final void Function(String postId, GlobalKey anchorKey)? onVideoAnchorReady;

  const _PostMediaSurface({
    required this.post,
    required this.coordinator,
    required this.registerVideoUrl,
    required this.handoffSessionId,
    this.onVideoExpandRequested,
    this.onVideoAnchorReady,
  });

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
            coordinator: coordinator,
            registerVideoUrl: registerVideoUrl,
            dormant: handoffSessionId == post.id,
            // videoPlaybackUrl (videoUrl-first), BUKAN previewMediaUrl
            // (yang thumbnail-first → JPG → player gagal initialize).
            mediaUrl: videoQualityService.resolvePlaybackUrl(
              post.videoPlaybackUrl,
              dataSaverUrl: post.videoDataSaverUrl,
              userPreference: appSettingsStore.feedVideoQuality,
            ),
            thumbnailUrl: post.thumbnailUrl,
            aspectRatio: aspectRatio,
            onExpandRequested: onVideoExpandRequested,
            onAnchorReady: onVideoAnchorReady,
          ),
        FeedContentType.carousel => Hero(
            tag: 'post-thumb-${post.id}',
            child: _CarouselSurface(
              post: post,
              aspectRatio: aspectRatio,
              coordinator: coordinator,
              registerVideoUrl: registerVideoUrl,
              handoffSessionId: handoffSessionId,
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
  final PostVideoCoordinator coordinator;
  final void Function(String sessionId, String url) registerVideoUrl;
  final String? handoffSessionId;

  const _CarouselSurface({
    required this.post,
    required this.aspectRatio,
    required this.coordinator,
    required this.registerVideoUrl,
    required this.handoffSessionId,
  });

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
        videoDataSaverUrl: widget.post.videoDataSaverUrl,
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
              final sessionId = '${widget.post.id}-$index';
              return _InlineVideoPlayer(
                postId: sessionId,
                coordinator: widget.coordinator,
                registerVideoUrl: widget.registerVideoUrl,
                dormant: widget.handoffSessionId == sessionId,
                mediaUrl: videoQualityService.resolvePlaybackUrl(
                  item.mediaUrl,
                  dataSaverUrl: item.videoDataSaverUrl,
                  userPreference: appSettingsStore.feedVideoQuality,
                ),
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

  const _ImageSurface({required this.imageUrl, required this.placeholderIcon});

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

  void _removeZoomOverlay({bool resetController = true, bool notify = true}) {
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
      child: Center(child: Icon(icon, color: Colors.white24, size: 72)),
    );
  }
}

// ─── Inline video player — borrow controller from PostVideoCoordinator ─

/// Inline video di list Postingan (T3a). TIDAK lagi membuat/mendispose
/// controllernya sendiri: ia MEMINJAM sesi dari [PostVideoCoordinator]
/// (attach saat jadi item video terlihat aktif; detach saat keluar).
/// Lifecycle app/route didaftarkan SEKALI di level halaman (§2.5) — inline
/// hanya melaporkan visibilitas + intent.
///
/// Aturan (plan 2026-07-13):
///  - Autoplay saat terlihat ≥60% (ala IG Postingan).
///  - Mute mengikuti coordinator (feedMuted) — tombol mute menulis ke
///    `appSettingsStore.setFeedMuted`, coordinator re-apply ke sesi aktif.
///  - Dormant (fullscreen terbuka utk sesi ini): berhenti lapor visibilitas,
///    tampilkan frozen frame/thumbnail; JANGAN sentuh controller (dimiliki
///    coordinator & dipakai fullscreen).
class _InlineVideoPlayer extends StatefulWidget {
  final String postId;
  final PostVideoCoordinator coordinator;
  final void Function(String sessionId, String url) registerVideoUrl;

  /// Fullscreen sedang terbuka untuk sesi ini → mode dormant (frozen frame).
  final bool dormant;
  final String mediaUrl;
  final String? thumbnailUrl;
  final double aspectRatio;
  final void Function(String sessionId, GlobalKey anchorKey)? onExpandRequested;
  final void Function(String postId, GlobalKey anchorKey)? onAnchorReady;

  const _InlineVideoPlayer({
    required this.postId,
    required this.coordinator,
    required this.registerVideoUrl,
    required this.mediaUrl,
    required this.thumbnailUrl,
    required this.aspectRatio,
    this.dormant = false,
    this.onExpandRequested,
    this.onAnchorReady,
  });

  @override
  State<_InlineVideoPlayer> createState() => _InlineVideoPlayerState();
}

class _InlineVideoPlayerState extends State<_InlineVideoPlayer> {
  late final String _viewId =
      'inline-${widget.postId}-${identityHashCode(this)}';

  bool _attached = false;
  double _visibleFraction = 0;

  /// Sesi yang sedang di-bind (untuk listen revision → rebuild saat init
  /// selesai/gagal). Hanya [VideoPlayerSession] yang punya controller; sesi
  /// fake (test) tidak — inline merender thumbnail untuk itu.
  VideoPlayerSession? _boundSession;

  // Stable key supaya transisi morph-scale fullscreen bisa anchor ke posisi
  // inline ini.
  final GlobalKey _anchorKey = GlobalKey();

  PostVideoCoordinator get _coordinator => widget.coordinator;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onAnchorReady?.call(widget.postId, _anchorKey);
    });
    // Rebuild saat mute/autoplay berubah (ikon mute + gating D3).
    appSettingsStore.addListener(_onSettingsChanged);
  }

  @override
  void didUpdateWidget(covariant _InlineVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dormant != widget.dormant && !widget.dormant) {
      // Keluar dormant (fullscreen tutup) → adopt origin SEGERA.
      // Masuk dormant: cukup berhenti berperan; sesi tetap pinned via origin.
      _adoptOriginAfterDormant();
    }
  }

  /// Kembali dari fullscreen (dormant → aktif). JANGAN andalkan
  /// [_applyVisibility] dengan `_visibleFraction` BASI (= 0, karena
  /// VisibilityDetector belum re-fire — throttle ~500ms) yang akan
  /// men-DETACH origin lalu menampilkan thumbnail (KEDIP). Origin sudah
  /// di-`setActive` oleh `_endHandoff` (bagian 1); di sini inline cukup
  /// re-attach + adopt sesi di timestamp — TANPA `setActive` lagi (hindari
  /// double activate/play).
  void _adoptOriginAfterDormant() {
    if (!mounted) return;
    // Scroll tak berubah selama fullscreen → origin kembali terlihat penuh.
    // Set fraction ke nilai benar supaya VisibilityDetector re-fire berikutnya
    // tidak salah menganggap tersembunyi sebelum sempat update.
    _visibleFraction = 1.0;
    if (_coordinator.activePostId == widget.postId) {
      // Origin sudah aktif (di-setActive di _endHandoff). Re-attach + bind sesi
      // (adopt controller yang sama, di timestamp) TANPA setActive ulang.
      // reportVisible = no-op kalau sudah main, resume kalau perlu. Tidak perlu
      // setState: didUpdateWidget berjalan sebelum build() di frame yang sama,
      // jadi _boundSession baru langsung terbaca.
      _ensureAttached();
      _coordinator.reportVisible(widget.postId);
    } else {
      // Origin belum aktif (mis. app tidak resumed saat tutup, resume dilewati
      // guard lifecycle) → jalur visibilitas normal; tetap tak kedip karena
      // _visibleFraction sudah 1.0 (tak akan men-detach).
      _applyVisibility();
    }
  }

  @override
  void dispose() {
    appSettingsStore.removeListener(_onSettingsChanged);
    _unbindSession();
    if (_attached) {
      // Lepas attachment — coordinator yang memutuskan dispose sesi (LRU).
      _coordinator.detach(_viewId, widget.postId);
      _attached = false;
    }
    super.dispose();
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    setState(() {});
    _applyVisibility();
  }

  void _onVisibilityChanged(VisibilityInfo info) {
    _visibleFraction = info.visibleFraction;
    _applyVisibility();
  }

  void _applyVisibility() {
    if (!mounted || widget.dormant) return;
    final visible = _visibleFraction >= 0.6;
    if (visible) {
      _ensureAttached();
      // Jadikan aktif (autoplay ala IG) — coordinator yang play + set volume
      // sesuai feedMuted. Kalau sudah aktif, cukup lapor terlihat (resume).
      if (_coordinator.activePostId != widget.postId) {
        _coordinator.setActive(widget.postId);
      } else {
        _coordinator.reportVisible(widget.postId);
      }
    } else if (_visibleFraction <= 0.0) {
      // Keluar viewport sepenuhnya → detach (coordinator urus nasib sesi).
      if (_attached) {
        _coordinator.detach(_viewId, widget.postId);
        _attached = false;
        _unbindSession();
      }
    } else {
      // Sebagian terlihat (<60%) tapi masih di layar → pause, tetap attached.
      if (_attached) {
        _coordinator.reportHidden(widget.postId);
      }
    }
  }

  void _ensureAttached() {
    if (_attached) {
      _bindSession();
      return;
    }
    // Daftarkan URL supaya factory coordinator bisa membuat sesi.
    widget.registerVideoUrl(widget.postId, widget.mediaUrl);
    _coordinator.attach(_viewId, widget.postId);
    _attached = true;
    _bindSession();
  }

  void _bindSession() {
    final session = _coordinator.sessionFor(widget.postId);
    final videoSession = session is VideoPlayerSession ? session : null;
    if (identical(videoSession, _boundSession)) return;
    _unbindSession();
    _boundSession = videoSession;
    videoSession?.revision.addListener(_onSessionRevision);
  }

  void _unbindSession() {
    _boundSession?.revision.removeListener(_onSessionRevision);
    _boundSession = null;
  }

  void _onSessionRevision() {
    if (mounted) setState(() {});
  }

  Future<void> _toggleMute() async {
    AppHaptics.tap();
    // Tulis ke preferensi global — coordinator listener re-apply ke sesi
    // aktif (mute konsisten di semua permukaan, §2.2).
    await appSettingsStore.setFeedMuted(!appSettingsStore.feedMuted);
  }

  /// Tombol "Coba lagi" — init ulang manual (reset budget retry di sesi).
  /// Sesi tetap dimiliki coordinator; kita hanya minta re-init dari view.
  void _onRetry() {
    AppHaptics.tap();
    final session = _coordinator.sessionFor(widget.postId);
    if (session is VideoPlayerSession) {
      unawaited(session.retry());
    }
  }

  void _openFullscreen() {
    widget.onExpandRequested?.call(widget.postId, _anchorKey);
  }

  @override
  Widget build(BuildContext context) {
    final session = _boundSession;
    final controller = session?.controller;
    final ready = controller != null && controller.value.isInitialized;
    final hasError = session?.hasError ?? false;
    final hasVisualOutput = session?.hasVisualOutput ?? false;
    final visualLoading = ready &&
        session != null &&
        (!hasVisualOutput || session.isRecoveringVisualOutput);
    final muted = appSettingsStore.feedMuted;
    // Spinner hanya saat kita memang sedang memuat (attached, belum ready,
    // tanpa error), atau saat audio ditahan karena frame baru belum terbukti.
    final loading = _attached && !hasError && (!ready || visualLoading);

    return VisibilityDetector(
      key: ValueKey('inline-video-${widget.postId}'),
      onVisibilityChanged: _onVisibilityChanged,
      child: GestureDetector(
        key: _anchorKey,
        behavior: HitTestBehavior.opaque,
        onTap: widget.dormant ? null : _openFullscreen,
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
            // Saat controller sudah initialized tetapi frame pertamanya belum
            // terbukti keluar, pertahankan thumbnail. Ini mencegah surface
            // beku/black terlihat sementara audio gate dan recovery bekerja.
            if (ready &&
                !hasVisualOutput &&
                widget.thumbnailUrl != null &&
                widget.thumbnailUrl!.trim().isNotEmpty)
              _ImageSurface(
                imageUrl: widget.thumbnailUrl!,
                placeholderIcon: Icons.video_collection_outlined,
              ),
            if (loading)
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
            if (hasError && !widget.dormant)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'Video belum bisa diputar',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _onRetry,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.55),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.refresh_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Coba lagi',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            // Ikon mute pojok kanan bawah — mengikuti feedMuted global.
            if (ready && !hasError && !widget.dormant)
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
                      muted
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
              leading: const Icon(
                Icons.delete_rounded,
                color: Color(0xFFDC2626),
              ),
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
                style: TextStyle(color: cs.onSurface, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Tulis caption…',
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
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

// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shimmer/shimmer.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../config/api_config.dart';
import '../features/feed/layout/postingan_media_aspect_ratio.dart';
import '../features/feed/transition/post_hero.dart';
import '../features/feed/widgets/double_tap_burst_guard.dart';
import '../features/feed/widgets/feed_post_shared_widgets.dart';
import '../features/feed/video/post_video_coordinator.dart';
import '../features/feed/video/post_video_warm_handoff.dart';
import '../features/feed/video/video_player_session.dart';
import '../models/feed_post.dart';
import '../services/api_client.dart';
import '../services/feed_service.dart';
import '../services/follow_service.dart';
import '../services/video_quality_service.dart';
import '../state/feed_local_store.dart';
import '../state/feed_store.dart';
import '../state/follow_override_store.dart';
import '../state/member_store.dart';
import '../state/post_caption_session_store.dart';
import '../state/settings_store.dart';
import '../theme/natalo_colors.dart';
import '../theme/natalo_text.dart';
import '../utils/app_route_observer.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import '../widgets/app_toast.dart';
import '../widgets/calm_scroll_physics.dart';
import '../widgets/feed_comment_sheet.dart';
import '../widgets/liquid_glass.dart';
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

/// Apakah identitas author di-render sebagai OVERLAY di atas media (teks putih
/// di dalam video) atau sebagai baris terpisah putih di ATAS media (teks
/// gelap, seperti post foto).
///
/// Paritas Instagram:
/// - Foto/carousel → SELALU baris terpisah (return false).
/// - Video PORTRAIT / persegi (tinggi ≥ lebar) → overlay di atas video
///   (return true) — video mengisi frame tinggi, username menimpa.
/// - Video LANDSCAPE (lebih lebar dari tinggi) → baris terpisah (return
///   false) — video tampil pendek-lebar, overlay akan terasa sempit &
///   berdesakan. IG menaruh username di baris atas untuk landscape.
///
/// Video tanpa dimensi (w/h ≤ 0) default portrait → overlay (aman: mayoritas
/// video customer portrait, dan default aspectRatio model 9/16).
bool postVideoUsesOverlay(FeedPost post) {
  if (!post.isVideo) return false;
  final w = post.aspectWidthInt;
  final h = post.aspectHeightInt;
  if (w <= 0 || h <= 0) return true;
  return w <= h;
}

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

  /// Identitas follow author untuk chip "Ikuti/Mengikuti" di header.
  /// WAJIB di-pass saat open dari public profile: item `/api/u/{username}`
  /// TIDAK membawa objek `author` (author implisit = pemilik profil), jadi
  /// `post.author.id` kosong & `post.author.isFollowing` selalu false —
  /// tanpa override ini chip selalu "Ikuti" walau sudah follow (bug
  /// device-verify), dan overrides tak nyambung (key '' vs profile.id).
  /// Null → fallback ke `post.author.*` (feed utama yang authornya lengkap).
  final String? authorId;
  final bool? authorIsFollowing;

  /// Owner mode flag. True (default) untuk "Postingan Saya" — show
  /// Edit/Delete menu di "...". False saat view post user lain — sembunyikan
  /// menu owner-only (edit caption + hapus), supaya tidak ada aksi destructive
  /// yang bocor ke viewer non-owner.
  final bool isOwner;

  /// Cross-account mode. True → identitas author diambil per post dari
  /// `post.author` (dipakai Postingan Tersimpan yang lintas akun). Default
  /// false → perilaku single-author lama (Postingan Saya / public profile).
  final bool authorPerPost;
  final PostVideoWarmHandoff? warmVideoHandoff;
  final String? initialNextCursor;
  final ScopedPostPageLoader? loadMoreScopedPosts;

  /// Scope hero untuk transisi grid→viewer bawaan Flutter (Task 1/2 rewrite
  /// hero). Null = TANPA hero (mis. deep-link langsung ke halaman ini tanpa
  /// origin grid) — mencegah tag hero yatim/duplikat di tree.
  final String? heroScope;

  /// Dipanggil SINKRON saat pop mulai (sebelum animasi selesai), dengan id
  /// post yang sedang aktif di layar saat itu — supaya origin grid tahu post
  /// mana yang harus jadi tujuan hero pop-back.
  final void Function(String activePostId)? onWillClose;

  const MemberPostDetailScreen({
    super.key,
    required this.post,
    this.posts,
    this.initialIndex = 0,
    this.authorName,
    this.authorPhotoUrl,
    this.authorInitial,
    this.authorIsOfficial = false,
    this.authorId,
    this.authorIsFollowing,
    this.isOwner = true,
    this.authorPerPost = false,
    this.warmVideoHandoff,
    this.initialNextCursor,
    this.loadMoreScopedPosts,
    this.heroScope,
    this.onWillClose,
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

  @visibleForTesting
  List<GlobalKey> get debugPostKeys => _postKeys;

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

  /// Re-check koreksi posisi header (§_ensurePostVisible) tertunda — di-cancel
  /// di dispose supaya tidak nyangkut kalau user keluar halaman sebelum timer
  /// menyala.
  Timer? _postAlignRecheckTimer;

  // ── Tracking post yang PALING terlihat (semua tipe konten) ──────────
  // Coordinator hanya melacak sesi VIDEO aktif (_videoCoordinator.
  // activePostId) — untuk foto/carousel tidak ada pelacakan setara. List ini
  // continuous-scroll (bukan PageView), jadi "post aktif" untuk kebutuhan
  // onWillClose (reverse hero target) harus dihitung dari visibilitas
  // sesungguhnya, bukan diasumsikan dari video. Setiap _PostFeedItem lapor
  // fraction-nya sendiri lewat VisibilityDetector; di sini kita cukup simpan
  // fraction terbaru per post lalu ambil id dengan fraction tertinggi.
  // Sengaja TANPA setState — ini murni bookkeeping untuk dibaca saat pop,
  // bukan sesuatu yang perlu memicu rebuild tiap frame scroll.
  final Map<String, double> _postVisibilityFractions = {};
  String? _mostVisiblePostId;

  // ── Single viewer hero (§4 spec) ─────────────────────────────────────
  // Flutter's Hero framework flies EVERY tag present in both routes'
  // subtrees simultaneously. Wrapping every built post in PostHero (as the
  // old code did) meant co-built neighbor posts sharing the origin grid's
  // hero scope produced stray "ghost" flights on push/pop. Only the
  // currently-most-visible post's media should carry a live Hero — this
  // notifier is that single source of truth, read by `_wrapHero` via
  // ValueListenableBuilder so only the (at most two) affected media
  // subtrees rebuild when it changes, not the whole list.
  late final ValueNotifier<String> _heroPostId;

  void _onPostVisibilityChanged(String postId, double fraction) {
    if (!mounted) return;
    _postVisibilityFractions[postId] = fraction;
    // Ties → keep existing (post yang sudah tercatat menang kalau imbang),
    // supaya scroll kecil yang belum menggeser dominansi tidak mengganti
    // target reverse-hero tanpa alasan.
    final currentBest = _mostVisiblePostId;
    final currentBestFraction = currentBest == null
        ? -1.0
        : (_postVisibilityFractions[currentBest] ?? -1.0);
    if (fraction > currentBestFraction) {
      _mostVisiblePostId = postId;
    } else if (currentBest != null &&
        postId == currentBest &&
        fraction < currentBestFraction) {
      // currentBest sendiri turun fraction-nya (sudah ditulis di atas) —
      // cari ulang pemenang baru dari seluruh map supaya tidak nyangkut ke
      // post yang sudah tak lagi paling terlihat.
      String? bestId;
      var bestFraction = -1.0;
      for (final entry in _postVisibilityFractions.entries) {
        if (entry.value > bestFraction) {
          bestFraction = entry.value;
          bestId = entry.key;
        }
      }
      _mostVisiblePostId = bestId;
    }
    final winner = _mostVisiblePostId;
    if (winner != null && winner != _heroPostId.value) {
      _heroPostId.value = winner;
    }
  }

  /// Buang entry post yang item-nya sudah dispose (mis. discroll cepat lalu
  /// balik) — supaya map tidak menumpuk data basi post yang sudah tidak ada
  /// widget-nya lagi (leak kecil + risiko `_onPostVisibilityChanged` memilih
  /// pemenang dari fraction stale).
  void _onPostVisibilityDisposed(String postId) {
    _postVisibilityFractions.remove(postId);
    if (_mostVisiblePostId == postId) _mostVisiblePostId = null;
  }

  @override
  void initState() {
    super.initState();
    final source = widget.posts;
    _posts = source == null || source.isEmpty
        ? [widget.post]
        : List<FeedPost>.from(source);
    _postKeys = List.generate(_posts.length, (_) => GlobalKey());
    _heroPostId = ValueNotifier<String>(widget.post.id);
    // Deep-tap first-frame layout (§4 spec): posisikan ScrollController
    // SUDAH dekat post target SEBELUM frame pertama dibangun, bukan mulai
    // dari offset 0 lalu jumpTo pasca-frame. Tanpa ini, saat user tap tile
    // ke-N (N di luar viewport awal), first frame membangun list dari
    // offset 0 — slot post target belum ter-layout saat Flutter meng-capture
    // geometri Hero untuk flight (dijalankan sangat awal), sehingga PostHero
    // milik post target diam-diam gagal ikut terbang (walau _heroPostId
    // sudah benar sejak initState — lihat di atas) padahal neighbor yang
    // kebetulan sudah ter-render tetap terbang. `_estimatedOffsetToPost`
    // sudah ada (dipakai `_jumpNearPost` untuk retry pasca-frame) — pakai
    // estimasi yang SAMA di sini, dari initState, sebagai posisi awal asli.
    // RESIDU: estimasi pakai aspectRatio post (akurat) + KONSTANTA untuk
    // tinggi author-row/caption/date (authorRowHeight, actionCaptionDateHeight
    // di `_estimatedPostExtent`) — caption yang wrap banyak baris bikin
    // tinggi post sesungguhnya lebih besar dari estimasi. `_ensurePostVisible`
    // (dipanggil di `_jumpToInitial`, post-frame) tetap jalan sebagai
    // KOREKSI presisi final berdasar layout nyata (GlobalKey context), jadi
    // posisi akhir selalu tepat — bagian yang residual cuma seberapa DEKAT
    // frame pertama mendarat sebelum koreksi itu (dengan caption panjang,
    // frame pertama mungkin sedikit meleset dari target, bukan pas).
    final targetIndex = widget.initialIndex;
    final initialOffset = (targetIndex > 0 && targetIndex < _posts.length)
        ? _estimatedOffsetToPost(_screenWidthPreLayout(context), targetIndex)
        : 0.0;
    _scrollController = ScrollController(initialScrollOffset: initialOffset);
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
    // Posisi kasar SUDAH dipasang pra-layout via
    // ScrollController(initialScrollOffset:) di initState (§4 spec deep-tap
    // fix) — TIDAK perlu `_jumpNearPost` lagi di sini (dulu re-estimasi +
    // jumpTo dari offset 0 setelah frame pertama; kini frame pertama SUDAH
    // dekat target). `_ensurePostVisible` di bawah tinggal jadi koreksi
    // presisi final (align pas di bawah header dari layout nyata via
    // GlobalKey), retry-loop-nya tetap dipertahankan untuk kasus estimasi
    // meleset (caption panjang — lihat komentar residual di initState).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensurePostVisible(targetIndex, attemptsLeft: 8);
    });
  }

  void _jumpNearPost(int targetIndex) {
    if (!_scrollController.hasClients) return;
    final maxExtent = _scrollController.position.maxScrollExtent;
    final approxOffset =
        _estimatedOffsetToPost(MediaQuery.sizeOf(context).width, targetIndex);
    final targetOffset = approxOffset.clamp(0.0, maxExtent).toDouble();
    _scrollController.jumpTo(targetOffset);
  }

  void _ensurePostVisible(int targetIndex, {required int attemptsLeft}) {
    if (!mounted || !_scrollController.hasClients) return;
    final ctx = _postKeys[targetIndex].currentContext;
    if (ctx != null) {
      _alignPostUnderHeader(ctx);
      // Post di atas target (belum tentu selesai decode network image saat
      // frame ini) bisa relayout sesaat setelah gambar asli masuk, menggeser
      // target keluar dari bawah header (bug device: post ke-2/3 "nembus"
      // header). Re-cek + koreksi sekali lagi setelah decode wajar selesai.
      _postAlignRecheckTimer?.cancel();
      _postAlignRecheckTimer = Timer(const Duration(milliseconds: 260), () {
        if (!mounted) return;
        final freshCtx = _postKeys[targetIndex].currentContext;
        if (freshCtx != null) _alignPostUnderHeader(freshCtx);
      });
      return;
    }
    if (attemptsLeft <= 0) return;
    _jumpNearPost(targetIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensurePostVisible(targetIndex, attemptsLeft: attemptsLeft - 1);
    });
  }

  /// Daratkan [ctx] pas di bawah header (bukan y=0 mentah, yang tertutup
  /// header frosted) — dipakai dari [_ensurePostVisible] + re-check tunda.
  void _alignPostUnderHeader(BuildContext ctx) {
    Scrollable.ensureVisible(
      ctx,
      duration: Duration.zero,
      alignment: 0.0,
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
    );
    // ensureVisible menaruh post di y=0 (tepi atas viewport) — itu DI BAWAH
    // header frosted yang overlay. Geser balik sebesar tinggi header supaya
    // post target mendarat di bawah header (tidak ketutup), konsisten dgn
    // framing post pertama yang dapat top-padding ListView.
    final headerInset = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final pos = _scrollController.position;
    _scrollController.jumpTo(
      (pos.pixels - headerInset).clamp(0.0, pos.maxScrollExtent).toDouble(),
    );
  }

  /// Lebar layar untuk estimasi extent post — TIDAK boleh lewat
  /// `MediaQuery.of(context)` di [initState] (dilarang keras oleh framework:
  /// "dependOnInheritedWidgetOfExactType... was called before initState()
  /// completed"). Dipakai dari initState untuk posisi awal
  /// ScrollController pra-layout (§4 spec deep-tap fix); baca langsung dari
  /// platformDispatcher (data mentah OS, bukan InheritedWidget) supaya aman
  /// dipanggil sebelum initState selesai. Setelah first frame, pemanggil
  /// yang sudah punya BuildContext ter-attach (build()/post-frame callback)
  /// tetap boleh pakai `MediaQuery.sizeOf(context).width` — lihat caller.
  double _screenWidthPreLayout(BuildContext context) {
    if (context.mounted) {
      final inherited =
          context.getElementForInheritedWidgetOfExactType<MediaQuery>()?.widget;
      if (inherited is MediaQuery) return inherited.data.size.width;
    }
    final view = View.maybeOf(context) ??
        (WidgetsBinding.instance.platformDispatcher.views.isNotEmpty
            ? WidgetsBinding.instance.platformDispatcher.views.first
            : null);
    if (view == null) return 400.0;
    return view.physicalSize.width / view.devicePixelRatio;
  }

  double _estimatedPostExtent(double screenWidth, FeedPost post) {
    final mediaAspectRatio = resolvePostinganMediaAspectRatio(
      width: post.aspectWidthInt,
      height: post.aspectHeightInt,
      type: post.contentType,
    );
    const authorRowHeight = 52.0;
    const actionCaptionDateHeight = 118.0;
    final mediaHeight = screenWidth / mediaAspectRatio;
    return mediaHeight + authorRowHeight + actionCaptionDateHeight;
  }

  double _maximumEstimatedPostExtent(double screenWidth) {
    const authorRowHeight = 52.0;
    const actionCaptionDateHeight = 118.0;
    return (screenWidth / postinganVideoMinAspectRatio) +
        authorRowHeight +
        actionCaptionDateHeight;
  }

  double _estimatedOffsetToPost(double screenWidth, int targetIndex) {
    const separatorHeight = 24.0;
    var offset = 0.0;
    for (var index = 0; index < targetIndex && index < _posts.length; index++) {
      offset += _estimatedPostExtent(screenWidth, _posts[index]);
      offset += separatorHeight;
    }
    return offset;
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
    _postAlignRecheckTimer?.cancel();
    feedStore.removeListener(_onFeedStoreChanged);
    appRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _videoCoordinator.dispose();
    _scrollController.dispose();
    _heroPostId.dispose();
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
    final post = _postWithResolvedAuthor(_posts[index]);
    // Postingan uses the modal-style Instagram drawer: pause the active
    // player while the sheet is visible, then restore only if it was playing
    // before the tap. A user-paused video must remain paused after dismissal.
    final activePostId = _videoCoordinator.activePostId;
    final wasPlaying =
        activePostId != null && !_videoCoordinator.isUserPaused(activePostId);
    _videoCoordinator.pauseAll();
    try {
      await showFeedCommentDrawer(context, post: post);
    } finally {
      if (wasPlaying && mounted) _videoCoordinator.resumeAll();
    }
  }

  String _authorNameFor(FeedPost post) {
    final name = post.author.displayName.trim();
    return name.isEmpty ? 'Pengguna' : name;
  }

  String _authorInitialFor(FeedPost post) {
    final initial = post.author.initial.trim();
    if (initial.isNotEmpty) return initial;
    final nm = _authorNameFor(post);
    return nm.isEmpty ? '?' : nm.substring(0, 1).toUpperCase();
  }

  String? _authorPhotoFor(FeedPost post) {
    final photo =
        (post.author.profilePhotoUrl ?? post.author.avatarUrl)?.trim();
    return photo == null || photo.isEmpty ? null : photo;
  }

  /// Username utk tap nama/avatar di header post → buka profil. Mode owner
  /// ("Postingan Saya") prioritas `memberStore.profile.username` — endpoint
  /// list post sendiri tak selalu ikut kirim `author.username` (data diri
  /// sendiri). Non-owner tetap pakai `post.author.username` (data publik,
  /// sudah reliable dari server).
  String? _memberUsernameFor(FeedPost post) {
    if (widget.isOwner) {
      final own = memberStore.profile?.username?.trim();
      if (own != null && own.isNotEmpty) return own;
    }
    return post.author.username;
  }

  FeedPost _postWithResolvedAuthor(FeedPost post) {
    if (widget.authorPerPost) return post;
    final source = post.author;
    final ownerProfile = widget.isOwner ? memberStore.profile : null;
    final resolvedPhoto = _memberPhotoUrl;
    final resolvedName = _memberName.trim();
    return post.copyWith(
      author: FeedAuthor(
        id: ownerProfile?.id ?? source.id,
        name: resolvedName.isEmpty ? source.name : resolvedName,
        username: ownerProfile?.username ?? source.username,
        avatarUrl: resolvedPhoto ?? source.avatarUrl,
        profilePhotoUrl: resolvedPhoto ?? source.profilePhotoUrl,
        role: ownerProfile?.role ?? source.role,
        isAdmin: widget.authorIsOfficial ||
            ownerProfile?.isAdmin == true ||
            source.isAdmin,
        isOfficial: widget.authorIsOfficial || source.isOfficial,
        isFollowing: source.isFollowing,
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
    final changed = await Navigator.pushNamed(
      context,
      '/member/postingan-edit',
      arguments: post,
    );
    if (changed != true || !mounted) return;
    // MemberPostEditScreen sudah PATCH + feedStore.applyPostUpdate. Tarik
    // ulang dari store supaya state lokal halaman ini ikut ter-update.
    final synced = feedStore.get(post.id);
    if (synced != null) {
      setState(() {
        _posts[index] = synced;
      });
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
    // TIDAK pakai Scaffold.appBar: AppBar bawaan membungkus toolbar-nya
    // dalam SATU Material/Ink layer yang menyerap tap di SELURUH lebarnya
    // — termasuk ruang kosong di tengah — walau backgroundColor transparan.
    // Karena AppBar ini overlay permanen di atas post pertama
    // (extendBodyBehindAppBar), itu menutupi tap ke _PostAuthorRow /
    // _VideoPostAuthorOverlay post pertama (regresi ditemukan lewat test).
    // Fix: Positioned manual TANPA Material pembungkus penuh — celah kosong
    // meneruskan tap ke konten di bawahnya, cuma back button/judul/chip
    // Ikuti yang benar-benar menyerap tap.
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) return;
        // Resolusi target reverse-hero: post yang PALING terlihat saat ini
        // (semua tipe konten, dari _mostVisiblePostId — lihat
        // _onPostVisibilityChanged), fallback ke coordinator video (kalau
        // visibility belum sempat lapor), fallback terakhir ke post pertama
        // yang dibuka.
        widget.onWillClose?.call(
          _mostVisiblePostId ??
              _videoCoordinator.activePostId ??
              widget.post.id,
        );
      },
      child: Scaffold(
        backgroundColor: cs.surface,
        body: Stack(
          children: [
            _posts.isEmpty
                ? Center(
                    child: Text(
                      'Belum ada postingan',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 14,
                        fontWeight: NataloWeight.body,
                      ),
                    ),
                  )
                : NataloPawRefreshIndicator(
                    onRefresh: _refreshPosts,
                    child: ListView.separated(
                      controller: _scrollController,
                      cacheExtent: _maximumEstimatedPostExtent(
                              MediaQuery.sizeOf(context).width) *
                          2,
                      // Top: media post pertama mulai TEPAT di bawah header (status
                      // bar + toolbar), jadi saat pertama buka media tidak "over ke
                      // atas" / kepotong — framing 9:16 utuh (paritas IG). Saat
                      // discroll, media lewat di belakang header frosted-tipis.
                      // Bottom: extra space supaya post terakhir bisa discroll lega
                      // ke atas viewport (gak mepet ke home indicator).
                      padding: EdgeInsets.only(
                        top: MediaQuery.paddingOf(context).top + kToolbarHeight,
                        bottom: 48,
                      ),
                      // Fling diredam ala IG — lihat CalmScrollPhysics.
                      physics: const CalmScrollPhysics(),
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
                          memberName: widget.authorPerPost
                              ? _authorNameFor(post)
                              : _memberName,
                          memberInitial: widget.authorPerPost
                              ? _authorInitialFor(post)
                              : _memberInitial,
                          memberPhotoUrl: widget.authorPerPost
                              ? _authorPhotoFor(post)
                              : _memberPhotoUrl,
                          memberUsername: widget.authorPerPost
                              ? post.author.username
                              : _memberUsernameFor(post),
                          memberIsOfficial: widget.authorPerPost
                              ? post.author.isOfficialAccount
                              : widget.authorIsOfficial,
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
                          onMenuTap: widget.isOwner
                              ? () => _openPostMenu(index)
                              : null,
                          onOpenScopedFeed: (sessionId, anchorKey) =>
                              _openScopedVideoFeed(index, sessionId, anchorKey),
                          onVideoAnchorReady: (postId, anchorKey) {
                            _videoAnchorKeys[postId] = anchorKey;
                          },
                          onVisibilityChanged: _onPostVisibilityChanged,
                          onVisibilityDisposed: _onPostVisibilityDisposed,
                          heroScope: widget.heroScope,
                          heroPostId: _heroPostId,
                        );
                      },
                    ),
                  ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _PostDetailTransparentHeaderBar(
                // Cross-account (authorPerPost): overlay ini fixed di atas
                // SELURUH pager, bukan per-index — tak ada satu author yang
                // representatif saat isinya lintas akun. Sembunyikan
                // nama/badge/chip ikuti (sama alasan dgn subtitle AppBar lama
                // yang disembunyikan di mode ini), sisakan cuma judul +
                // tombol back.
                memberName: widget.authorPerPost ? '' : _memberName,
                authorIsOfficial:
                    widget.authorPerPost ? false : widget.authorIsOfficial,
                // authorId kosong (data profil tak lengkap) → chip
                // disembunyikan: follow('') pasti gagal + override tak pernah
                // nyambung, lebih baik tak tampil daripada selalu "Ikuti".
                showFollowChip: !widget.isOwner &&
                    !widget.authorPerPost &&
                    (widget.authorId ?? widget.post.author.id).isNotEmpty,
                authorId: widget.authorId ?? widget.post.author.id,
                authorInitiallyFollowing:
                    widget.authorIsFollowing ?? widget.post.author.isFollowing,
              ),
            ),
          ],
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
      _estimatedOffsetToPost(MediaQuery.sizeOf(context).width, index)
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

  /// Username utk tap nama/avatar → buka profil. Sama seperti memberName/
  /// memberPhotoUrl: parent SUDAH resolve fallback ke memberStore.profile
  /// untuk mode owner ("Postingan Saya") — endpoint list post sendiri tidak
  /// selalu ikut kirim `author.username` (data diri sendiri, dianggap
  /// client sudah tahu). Kalau _PostFeedItem pakai `post.author.username`
  /// mentah, tap nama diam-diam no-op (null) khusus di mode owner — regresi
  /// yang dilaporkan user.
  final String? memberUsername;

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

  /// Lapor fraction visibilitas item ini (0..1) ke layar — dipakai layar
  /// untuk melacak post yang PALING terlihat lintas SEMUA tipe konten
  /// (foto/carousel/video), supaya `onWillClose` tahu target reverse-hero
  /// yang benar walau user scroll menjauh dari post video terakhir yang
  /// pernah aktif di coordinator.
  final void Function(String postId, double fraction)? onVisibilityChanged;

  /// Dipanggil sekali saat item ini dispose — layar induk pakai ini untuk
  /// membuang entry post dari `_postVisibilityFractions` (lihat
  /// [MemberPostDetailScreen._onPostVisibilityDisposed]).
  final void Function(String postId)? onVisibilityDisposed;

  /// Scope hero diteruskan dari layar — null = tanpa PostHero (lihat
  /// [MemberPostDetailScreen.heroScope]).
  final String? heroScope;

  /// Id post yang SEDANG memegang hero tunggal viewer ini (§4 spec) — hanya
  /// media milik post dengan id == heroPostId.value yang dibungkus PostHero;
  /// post lain render medianya polos tanpa Hero, supaya push/pop hanya
  /// menerbangkan satu tag (cegah ghost flight neighbor).
  final ValueNotifier<String>? heroPostId;

  const _PostFeedItem({
    super.key,
    required this.post,
    required this.coordinator,
    required this.registerVideoUrl,
    required this.handoffSessionId,
    required this.memberName,
    required this.memberInitial,
    required this.memberPhotoUrl,
    this.memberUsername,
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
    this.onVisibilityChanged,
    this.onVisibilityDisposed,
    this.heroScope,
    this.heroPostId,
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
  late final Animation<double> _burstTravel;
  Offset? _heartBurstPosition;
  final GlobalKey _likeButtonKey = GlobalKey();
  OverlayEntry? _flyingHeartEntry;

  /// Menekan single-tap nyasar dari burst double-tap-like (tap ganjil).
  final DoubleTapBurstGuard _doubleTapBurstGuard = DoubleTapBurstGuard();

  // Anchor key video inline (dilaporkan lewat onVideoAnchorReady) — dipakai
  // outer detector untuk memicu fullscreen saat single tap (menggantikan
  // onTap milik _InlineVideoPlayer, supaya single & double tap satu detector).
  GlobalKey? _videoAnchorKey;

  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _saved = feedStore.get(widget.post.id)?.viewerSaved ?? false;
    feedStore.addListener(_onFeedStoreSavedChanged);
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

    // Terbang ke tombol like: mulai setelah pop (0.5) lalu melesat easeIn.
    _burstTravel = CurvedAnimation(
      parent: _heartBurstController,
      curve: const Interval(0.5, 1.0, curve: Curves.easeInCubic),
    );
  }

  @override
  void dispose() {
    feedStore.removeListener(_onFeedStoreSavedChanged);
    _flyingHeartEntry?.remove();
    _flyingHeartEntry = null;
    _heartScaleController.dispose();
    _heartBurstController.dispose();
    _doubleTapBurstGuard.dispose();
    // Prune fraction bookkeeping di layar induk — item ini sudah tidak ada,
    // jangan biarkan fraction basi-nya ikut menang di _onPostVisibilityChanged.
    widget.onVisibilityDisposed?.call(widget.post.id);
    super.dispose();
  }

  void _onFeedStoreSavedChanged() {
    if (!mounted) return;
    final fresh = feedStore.get(widget.post.id);
    if (fresh == null || fresh.viewerSaved == _saved) return;
    setState(() => _saved = fresh.viewerSaved);
  }

  Future<void> _onSavePressed() async {
    AppHaptics.tap();
    try {
      await feedStore.toggleSaved(widget.post.id);
    } on FeedViewerChangedException {
      // The new viewer owns the rebased saved state.
    } catch (error) {
      if (!mounted) return;
      if (error is ApiException && error.statusCode == 401) {
        if (memberStore.isLoggedIn) await memberStore.logout();
        if (!mounted) return;
        Navigator.pushNamed(context, '/member/login');
        return;
      }
      AppToast.show(
        context,
        error is ApiException && error.statusCode == 404
            ? 'Postingan tidak tersedia.'
            : 'Postingan belum bisa disimpan. Coba lagi.',
        kind: ToastKind.warning,
      );
    }
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
    _heartBurstPosition = details.globalPosition;
  }

  Offset? _resolveLikeCenter() {
    final box = _likeButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(box.size.center(Offset.zero));
  }

  void _handleDoubleTap() {
    // Double-tap = LIKE only (Instagram behavior — tidak un-like).
    // Kalau belum liked, fire onLike. Kalau sudah liked, skip toggle
    // tapi tetap show burst (heart kedap-kedip jadi feedback bahwa
    // user sudah suka).
    // Tekan single-tap nyasar dari burst-like (tap ganjil) — di inline
    // Postingan single-tap membuka fullscreen, jadi burst bisa tak sengaja
    // navigasi keluar. Lihat [DoubleTapBurstGuard].
    _doubleTapBurstGuard.registerDoubleTap();
    AppHaptics.impact();
    if (!widget.liked) {
      _handleLikeTap();
    }
    _showFlyingHeart();
  }

  void _showFlyingHeart() {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    _flyingHeartEntry?.remove();
    final tap = _heartBurstPosition;
    final target = _resolveLikeCenter();
    final entry = OverlayEntry(
      builder: (context) => IgnorePointer(
        child: AnimatedBuilder(
          animation: _heartBurstController,
          builder: (context, _) => feedPostBuildFlyingBurstHeart(
            tap: tap,
            target: target,
            scale: _burstScale.value,
            opacity: _burstOpacity.value,
            travel: _burstTravel.value,
            screenSize: MediaQuery.sizeOf(context),
          ),
        ),
      ),
    );
    _flyingHeartEntry = entry;
    overlay.insert(entry);
    _heartBurstController.forward(from: 0).whenComplete(() {
      _flyingHeartEntry?.remove();
      _flyingHeartEntry = null;
    });
  }

  void _rememberVideoAnchor(String postId, GlobalKey anchorKey) {
    _videoAnchorKey = anchorKey;
    widget.onVideoAnchorReady?.call(postId, anchorKey);
  }

  void _handleVideoSingleTap() {
    // Burst-like guard: single-tap tepat sesudah double-tap-like (tap ganjil)
    // adalah noise — jangan buka fullscreen tak sengaja.
    if (_doubleTapBurstGuard.shouldSuppressSingleTap) return;
    final anchorKey = _videoAnchorKey;
    if (anchorKey == null) return;
    widget.onOpenScopedFeed?.call(widget.post.id, anchorKey);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final post = widget.post;
    final memberName = widget.memberName;
    final memberInitial = widget.memberInitial;
    final memberPhotoUrl = widget.memberPhotoUrl;
    final liked = widget.liked;
    return VisibilityDetector(
      // Lapor fraction visibilitas item INI (semua tipe konten) ke layar —
      // dipakai untuk melacak "post paling terlihat" (lihat komentar di
      // widget.onVisibilityChanged). Key per post.id, terpisah dari key
      // VisibilityDetector video inline di dalam _InlineVideoPlayer
      // ('inline-video-${postId}') supaya tidak bentrok.
      key: ValueKey('post-visibility-${post.id}'),
      onVisibilityChanged: (info) =>
          widget.onVisibilityChanged?.call(post.id, info.visibleFraction),
      child: Column(
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
          // Foto/carousel + video LANDSCAPE: author row putih di atas media.
          // Video PORTRAIT: author masuk overlay di dalam video (IG video post
          // style). Lihat postVideoUsesOverlay — landscape pakai baris atas
          // supaya username tidak berdesakan di video pendek-lebar.
          if (!postVideoUsesOverlay(post))
            _PostAuthorRow(
              memberName: memberName,
              memberInitial: memberInitial,
              memberPhotoUrl: memberPhotoUrl,
              isOfficial: widget.memberIsOfficial,
              authorUsername: widget.memberUsername,
              onMenuTap: widget.onMenuTap,
            ),
          // Double-tap detector membungkus media — HANYA untuk FOTO/carousel.
          // Untuk VIDEO, gesture (single-tap fullscreen + double-tap like)
          // ditangani di dalam _InlineVideoPlayer (detector yang membungkus
          // HANYA layer media, dengan kontrol mute/retry sebagai sibling di
          // atasnya) supaya kontrol tetap instan (pola feed) — video route-nya
          // di-forward balik ke handler _PostFeedItem via callback di bawah.
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
                  onVideoAnchorReady: _rememberVideoAnchor,
                  onVideoMediaSingleTap: _handleVideoSingleTap,
                  onVideoMediaDoubleTapDown: _rememberHeartBurstPosition,
                  onVideoMediaDoubleTap: _handleDoubleTap,
                  heroScope: widget.heroScope,
                  heroPostId: widget.heroPostId,
                ),
                if (postVideoUsesOverlay(post))
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _VideoPostAuthorOverlay(
                      memberName: memberName,
                      memberInitial: memberInitial,
                      memberPhotoUrl: memberPhotoUrl,
                      isOfficial: widget.memberIsOfficial,
                      authorUsername: widget.memberUsername,
                      onMenuTap: widget.onMenuTap,
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
                    key: _likeButtonKey,
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
                const Spacer(),
                IconButton(
                  onPressed: _onSavePressed,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    _saved
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                    color: cs.onSurface,
                    size: 26,
                  ),
                  tooltip: _saved ? 'Hapus dari tersimpan' : 'Simpan postingan',
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
                author: post.author,
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
                fontWeight: NataloWeight.body,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tap avatar+nama header (foto/video) → buka profil author. Gate sama
/// dengan header identity chip feed & nama caption: butuh username valid
/// (kosong/null = tidak tappable, no-op aman).
void _openPostHeaderProfile(BuildContext context, String? username) {
  if (username == null || username.isEmpty) return;
  AppHaptics.tap();
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => PublicProfileScreen(username: username),
    ),
  );
}

/// Header transparan permanen halaman Postingan — back button (LiquidGlass),
/// judul "Postingan/nama" (putih+shadow), chip Ikuti (kalau !isOwner).
/// SENGAJA bukan `AppBar`: lihat komentar di `_MemberPostDetailScreenState.
/// build` (AppBar bawaan menyerap tap di seluruh lebar toolbar walau
/// transparan — regresi tap ke header post pertama). Widget ini TIDAK
/// membungkus dirinya dalam Material lebar-penuh, jadi celah kosong antar
/// back/judul/chip meneruskan tap ke konten di baliknya.
class _PostDetailTransparentHeaderBar extends StatelessWidget {
  final String memberName;
  final bool authorIsOfficial;
  final bool showFollowChip;
  final String authorId;
  final bool authorInitiallyFollowing;

  const _PostDetailTransparentHeaderBar({
    required this.memberName,
    required this.authorIsOfficial,
    required this.showFollowChip,
    required this.authorId,
    required this.authorInitiallyFollowing,
  });

  // Ketebalan frosted — SANGAT tipis (konten tembus, sekadar melembutkan
  // supaya teks gelap kebaca). Satu angka, gampang di-tune saat device-verify.
  static const double _frostedSigma = 0.5;
  // Warna teks/ikon header: GELAP. Saat pertama buka header duduk di atas
  // latar putih (media mulai di bawahnya); saat discroll media lewat di
  // belakang frosted-tipis yang melembutkannya → gelap tetap kebaca di
  // kedua keadaan (paritas IG). Bukan putih.
  static const Color _fg = Color(0xFF1A1A1A);

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final topInset = MediaQuery.paddingOf(context).top;
    // Tint putih tipis di atas blur — cukup menjaga keterbacaan teks gelap,
    // tetap tembus. reducedMotion: blur dimatikan, tint dinaikkan agar teks
    // tetap kebaca tanpa efek kaca.
    final tint = Colors.white.withValues(alpha: reducedMotion ? 0.86 : 0.14);

    final bar = Container(
      color: tint,
      padding: EdgeInsets.only(top: topInset),
      child: SizedBox(
        height: kToolbarHeight,
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 10),
              // Bubble kaca bulat — SAMA ukuran dgn pill Ikuti (tinggi 32)
              // supaya sejajar rapi. Tanpa kaca chevron gelap tenggelam di
              // atas media gelap (temuan device-verify).
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.maybePop(context),
                child: LiquidGlass(
                  opacity: 1,
                  reducedMotion: reducedMotion,
                  borderRadius: BorderRadius.circular(999),
                  child: const SizedBox(
                    width: 32,
                    height: 32,
                    // Chevron "<" ala IG (bukan panah berekor).
                    child: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: _fg,
                      size: 17,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Postingan',
                      style: TextStyle(
                        color: _fg,
                        fontSize: 16,
                        fontWeight: NataloWeight.strong,
                        height: 1.05,
                      ),
                    ),
                    // memberName kosong = mode lintas akun (authorPerPost) —
                    // overlay ini fixed di atas seluruh pager, jadi tak ada
                    // satu author yang representatif untuk ditampilkan di
                    // sini (per-post identity tampil di _PostAuthorRow).
                    if (memberName.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              memberName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                // Official → emas gelap-di-terang (kontras di
                                // atas frosted terang).
                                color: authorIsOfficial
                                    ? NataloColors.officialGoldOnLight
                                    : const Color(0xFF5A5A5A),
                                fontSize: 12,
                                fontWeight: NataloWeight.strong,
                                height: 1.05,
                              ),
                            ),
                          ),
                          if (authorIsOfficial) ...[
                            const SizedBox(width: 3),
                            const OfficialVerifiedBadge(size: 12),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (showFollowChip)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: _PostDetailFollowChip(
                  authorId: authorId,
                  initialFollowing: authorInitiallyFollowing,
                ),
              )
            else
              const SizedBox(width: 10),
          ],
        ),
      ),
    );

    // Ikon status bar GELAP (header terang). AnnotatedRegion sinkron dgn
    // warna teks header.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: reducedMotion
          ? bar
          : ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: _frostedSigma,
                  sigmaY: _frostedSigma,
                ),
                child: bar,
              ),
            ),
    );
  }
}

/// Chip "Ikuti"/"Mengikuti" di AppBar Postingan — muncul HANYA saat viewer
/// bukan pemilik post (lihat post user lain/official). State follow sync
/// lintas-screen lewat `followOverrides` (sama infrastruktur dgn feed),
/// tanpa replikasi penuh viewer-generation robustness milik
/// `FeedPostCreatorIdentity` — cukup untuk satu chip per screen ini.
class _PostDetailFollowChip extends StatefulWidget {
  final String authorId;
  final bool initialFollowing;

  const _PostDetailFollowChip({
    required this.authorId,
    required this.initialFollowing,
  });

  @override
  State<_PostDetailFollowChip> createState() => _PostDetailFollowChipState();
}

class _PostDetailFollowChipState extends State<_PostDetailFollowChip> {
  bool _busy = false;

  Future<void> _toggle(bool currentlyFollowing) async {
    if (_busy) return;
    if (!memberStore.isLoggedIn) {
      Navigator.pushNamed(context, '/member/login');
      return;
    }
    AppHaptics.tap();
    setState(() => _busy = true);
    final target = !currentlyFollowing;
    setFollowOverride(widget.authorId, target);
    try {
      if (target) {
        await followService.follow(widget.authorId);
      } else {
        await followService.unfollow(widget.authorId);
      }
    } catch (_) {
      if (mounted) {
        setFollowOverride(widget.authorId, currentlyFollowing);
        AppToast.show(context, 'Gagal memperbarui. Coba lagi.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return ValueListenableBuilder<Map<String, bool>>(
      valueListenable: followOverrides,
      builder: (context, _, __) {
        final following =
            resolveFollowState(widget.authorId, widget.initialFollowing);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _toggle(following),
          child: LiquidGlass(
            opacity: 1,
            reducedMotion: reducedMotion,
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 32,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 11),
                child: Center(
                  child: Text(
                    following ? 'Mengikuti' : 'Ikuti',
                    style: TextStyle(
                      // Gelap — header kini terang (frosted), samakan dgn
                      // teks judul. Following sedikit lebih redup.
                      color: following
                          ? const Color(0xFF3A3A3A)
                          : const Color(0xFF1A1A1A),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
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

  /// Username author — dipakai untuk tap avatar+nama → buka profil.
  final String? authorUsername;

  const _PostAuthorRow({
    required this.memberName,
    required this.memberInitial,
    required this.memberPhotoUrl,
    this.isOfficial = false,
    required this.onMenuTap,
    this.authorUsername,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surface,
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _openPostHeaderProfile(context, authorUsername),
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
                              fontWeight: NataloWeight.strong,
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
                ],
              ),
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

  /// Username author — dipakai untuk tap avatar+nama → buka profil.
  final String? authorUsername;

  const _VideoPostAuthorOverlay({
    required this.memberName,
    required this.memberInitial,
    required this.memberPhotoUrl,
    this.isOfficial = false,
    required this.onMenuTap,
    this.authorUsername,
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
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _openPostHeaderProfile(context, authorUsername),
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
                                fontWeight: NataloWeight.strong,
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
                  style: const TextStyle(fontWeight: NataloWeight.strong),
                  recognizer: _primaryNameRecognizer,
                ),
                if (othersCount > 0) ...[
                  const TextSpan(text: ' dan '),
                  TextSpan(
                    text: '$othersCount orang lainnya',
                    style: const TextStyle(fontWeight: NataloWeight.strong),
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
              fontWeight: NataloWeight.body,
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
          fontWeight: NataloWeight.strong,
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

  /// Author lengkap — dipakai untuk gate + navigasi tap nama ke profil
  /// (sama seperti header identity chip: `author.hasUsername`). Null =
  /// nama tetap pajangan (mis. caller lama yang belum plumbing author).
  final FeedAuthor? author;

  const PostCaption({
    super.key,
    required this.postId,
    required this.memberName,
    required this.caption,
    this.isOfficial = false,
    this.author,
  });

  @override
  State<PostCaption> createState() => _PostCaptionState();
}

class _PostCaptionState extends State<PostCaption>
    with SingleTickerProviderStateMixin {
  late final TapGestureRecognizer _expandRecognizer = TapGestureRecognizer()
    ..onTap = _expand;
  // WAJIB stabil (dibuat sekali, sama seperti _expandRecognizer) — bukan
  // dibuat ulang tiap build(). Dispose+recreate per build (pola lama)
  // membuang recognizer yang lagi "dipegang" gesture arena kalau widget
  // rebuild persis di antara jari turun & lepas (LayoutBuilder + listener
  // postCaptionSessionStore bikin ini sering terjadi) → tap nama nyaris
  // selalu gagal walau username valid.
  late final TapGestureRecognizer _nameRecognizer = TapGestureRecognizer()
    ..onTap = _openAuthorProfile;

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

  void _openAuthorProfile() {
    final username = widget.author?.username;
    if (username == null || username.isEmpty) return;
    AppHaptics.tap();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PublicProfileScreen(username: username),
      ),
    );
  }

  @override
  void dispose() {
    postCaptionSessionStore.removeListener(_onSessionChanged);
    _expandRecognizer.dispose();
    _nameRecognizer.dispose();
    super.dispose();
  }

  TextStyle _style(BuildContext context) => TextStyle(
        color: Theme.of(context).colorScheme.onSurface,
        fontSize: 13.5,
        fontWeight: NataloWeight.body,
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
                  fontWeight: NataloWeight.strong,
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
      final canTapName = widget.author?.hasUsername ?? false;
      final span = TextSpan(children: [
        TextSpan(
            text: '${widget.memberName} ',
            recognizer: canTapName ? _nameRecognizer : null,
            style: TextStyle(
                fontWeight: NataloWeight.strong,
                color: widget.isOfficial
                    ? NataloColors.officialGoldOnLight
                    : null)),
        if (suffixIndex >= 0 && !expanded) ...[
          TextSpan(text: text.substring(0, suffixIndex + 4)),
          TextSpan(
              text: 'selengkapnya',
              recognizer: _expandRecognizer,
              style: const TextStyle(fontWeight: NataloWeight.strong)),
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
              fontWeight: NataloWeight.strong,
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
                fontWeight: NataloWeight.body,
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
  final void Function(String postId, GlobalKey anchorKey)? onVideoAnchorReady;
  // Gesture area media video — diteruskan ke _InlineVideoPlayer supaya
  // tap/double-tap video di-handle _PostFeedItem (kontrol tetap instan).
  final VoidCallback? onVideoMediaSingleTap;
  final void Function(TapDownDetails)? onVideoMediaDoubleTapDown;
  final VoidCallback? onVideoMediaDoubleTap;

  /// Scope hero (Task 2 — rewrite ke Hero bawaan). Null = tanpa hero (mis.
  /// deep-link) supaya tidak ada tag duplikat/yatim di tree.
  final String? heroScope;

  /// Id post yang sedang memegang hero tunggal viewer (§4 spec — lihat
  /// [MemberPostDetailScreen._heroPostId]). Null = tanpa live tracking
  /// (perilaku sama seperti heroScope null: media polos, tanpa Hero).
  final ValueNotifier<String>? heroPostId;

  const _PostMediaSurface({
    required this.post,
    required this.coordinator,
    required this.registerVideoUrl,
    required this.handoffSessionId,
    this.onVideoAnchorReady,
    this.onVideoMediaSingleTap,
    this.onVideoMediaDoubleTapDown,
    this.onVideoMediaDoubleTap,
    this.heroScope,
    this.heroPostId,
  });

  /// Bungkus [child] dengan [PostHero] ber-scope HANYA saat post ini adalah
  /// pemegang hero aktif (`heroPostId.value == post.id`) — post lain di
  /// list render medianya polos tanpa Hero. Ini yang mencegah ghost flight:
  /// Flutter hanya menerbangkan tag yang benar-benar ada sebagai Hero di
  /// kedua route, jadi neighbor post yang co-built tidak ikut terbang.
  /// ValueListenableBuilder membuat rebuild scope-nya sempit — cuma media
  /// subtree post yang kalah/menang hero yang rebuild saat notifier ganti
  /// nilai, bukan seluruh list (lihat komentar `_heroPostId` di layar).
  /// Null [heroScope]/[heroPostId] (deep-link tanpa origin grid) → child
  /// apa adanya, tanpa Hero maupun listener.
  Widget _wrapHero(Widget child, {Widget? flightChild}) {
    final scope = heroScope;
    final notifier = heroPostId;
    if (scope == null || notifier == null) return child;
    return ValueListenableBuilder<String>(
      valueListenable: notifier,
      builder: (context, activeHeroPostId, staticChild) {
        if (activeHeroPostId != post.id) return staticChild!;
        return PostHero(
          scope: scope,
          postId: post.id,
          flightChild: flightChild,
          child: staticChild!,
        );
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final aspectRatio = resolvePostinganMediaAspectRatio(
      width: post.aspectWidthInt,
      height: post.aspectHeightInt,
      type: post.contentType,
    );
    // Hero destination — dibungkus PostHero (scope+postId) dengan tag SAMA
    // dengan origin grid ('post-hero/<scope>/<postId>', lihat postHeroTag).
    // Saat user tap thumb di grid, media terbang ke posisi ini via Hero
    // bawaan Flutter. Foto, carousel, DAN video ikut hero (video: texture
    // VideoPlayer yang sama tanpa swap thumbnail, lihat PostHero shuttle).
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: switch (post.contentType) {
        FeedContentType.video => _wrapHero(
            _InlineVideoPlayer(
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
              onAnchorReady: onVideoAnchorReady,
              onMediaSingleTap: onVideoMediaSingleTap,
              onMediaDoubleTapDown: onVideoMediaDoubleTapDown,
              onMediaDoubleTap: onVideoMediaDoubleTap,
            ),
            // Hero flight: TIDAK pakai _InlineVideoPlayer segar (state baru
            // = unbound sampai VisibilityDetector menembak, throttle lebih
            // lambat dari durasi flight → placeholder/kosong sekilas alih-
            // alih video hidup, lihat komentar PostHero.flightChild). Surface
            // ringan ini baca controller yang SUDAH hidup secara sinkron.
            flightChild: _HeroVideoFlightSurface(
              postId: post.id,
              coordinator: coordinator,
              thumbnailUrl: post.thumbnailUrl,
            ),
          ),
        FeedContentType.carousel => _wrapHero(
            _CarouselSurface(
              post: post,
              aspectRatio: aspectRatio,
              coordinator: coordinator,
              registerVideoUrl: registerVideoUrl,
              handoffSessionId: handoffSessionId,
            ),
          ),
        FeedContentType.photo => _wrapHero(
            _ImageSurface(
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
                fontWeight: NataloWeight.strong,
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

// ─── Hero flight surface — video (lihat PostHero.flightChild) ────────

/// Surface video dipakai HANYA di dalam shuttle Hero ([PostHero._shuttle]).
/// BUKAN [_InlineVideoPlayer]: elemen itu selalu lahir baru di overlay flight
/// (Hero mem-placeholder-kan slot asal, memutus State lama), dan state
/// barunya baru attach/bind ke [PostVideoCoordinator] lewat callback
/// [VisibilityDetector] yang di-throttle (default ~500ms — jauh lebih lambat
/// dari durasi animasi flight). Hasilnya: sepanjang flight, _InlineVideoPlayer
/// versi baru SELALU unbound → merender placeholder/thumbnail dingin,
/// padahal origin baru saja menampilkan frame video HIDUP — persis bug
/// "kedip lalu video muncul di tengah flight".
///
/// Widget ini TIDAK attach/detach apa pun ke coordinator (origin
/// [_InlineVideoPlayer] tetap memegang attachment-nya; sesi videonya pinned
/// selama post ini aktif) — ia HANYA *membaca* sesi yang sudah hidup, secara
/// SINKRON di `initState`, lalu merender `VideoPlayer(controller)` yang SAMA
/// (satu texture, tanpa swap). Kalau sesi belum initialized (mis. post video
/// baru dibuka, belum sempat play), fallback ke thumbnail cache yang SAMA
/// dipakai _InlineVideoPlayer/grid — bukan gambar baru, bukan menunggu apa
/// pun. Rendering TIDAK digerbang oleh playbackAllowed/dormant — yang
/// digambar murni fungsi ready/tidak (gotcha VideoCompressGate-adjacent:
/// jangan gantungkan apa yang DIGAMBAR pada state play/pause).
class _HeroVideoFlightSurface extends StatefulWidget {
  final String postId;
  final PostVideoCoordinator coordinator;
  final String? thumbnailUrl;

  const _HeroVideoFlightSurface({
    required this.postId,
    required this.coordinator,
    required this.thumbnailUrl,
  });

  @override
  State<_HeroVideoFlightSurface> createState() =>
      _HeroVideoFlightSurfaceState();
}

class _HeroVideoFlightSurfaceState extends State<_HeroVideoFlightSurface> {
  VideoPlayerSession? _session;

  @override
  void initState() {
    super.initState();
    // Sinkron, TANPA VisibilityDetector/throttle — origin sudah attach sesi
    // ini sebelum flight ada alasan untuk mulai (video harus sudah main
    // untuk user bisa lihat lalu tap back).
    _bind();
  }

  @override
  void didUpdateWidget(covariant _HeroVideoFlightSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.postId != widget.postId ||
        oldWidget.coordinator != widget.coordinator) {
      _bind();
    }
  }

  void _bind() {
    final session = widget.coordinator.sessionFor(widget.postId);
    final next = session is VideoPlayerSession ? session : null;
    if (identical(next, _session)) return;
    _session?.revision.removeListener(_onRevision);
    _session = next;
    _session?.revision.addListener(_onRevision);
  }

  void _onRevision() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _session?.revision.removeListener(_onRevision);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _session?.controller;
    final ready = controller != null && controller.value.isInitialized;
    return ColoredBox(
      color: Colors.black,
      child: ready
          ? ClipRect(
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
          : (widget.thumbnailUrl != null &&
                  widget.thumbnailUrl!.trim().isNotEmpty
              ? _ImageSurface(
                  imageUrl: widget.thumbnailUrl!,
                  placeholderIcon: Icons.video_collection_outlined,
                )
              : const _MediaPlaceholder(
                  icon: Icons.video_collection_outlined,
                )),
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
    // The container ratio already follows the Postingan media policy. Cover
    // only crops sources outside its supported portrait/landscape limits.
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
  final void Function(String postId, GlobalKey anchorKey)? onAnchorReady;

  /// Gesture pada AREA MEDIA (bukan kontrol). Dipasang di detector yang
  /// membungkus HANYA layer media (hitam+video+thumbnail+spinner). Kontrol
  /// (mute, retry) adalah SIBLING di ATAS detector ini — tap kontrol
  /// terserap dulu → arena double-tap media tak pernah aktif → kontrol
  /// instan (pola sama seperti feed). Video mengalihkan tap/double-tap ke
  /// _PostFeedItem lewat callback ini.
  final VoidCallback? onMediaSingleTap;
  final void Function(TapDownDetails)? onMediaDoubleTapDown;
  final VoidCallback? onMediaDoubleTap;

  const _InlineVideoPlayer({
    required this.postId,
    required this.coordinator,
    required this.registerVideoUrl,
    required this.mediaUrl,
    required this.thumbnailUrl,
    required this.aspectRatio,
    this.dormant = false,
    this.onAnchorReady,
    this.onMediaSingleTap,
    this.onMediaDoubleTapDown,
    this.onMediaDoubleTap,
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
    if (_visibleFraction >= PostVideoCoordinator.activationThreshold) {
      _ensureAttached();
      // Lapor porsi terlihat — coordinator jadi WASIT tunggal autoplay
      // (most-visible-wins). Tidak lagi `setActive` sendiri: kalau dua video
      // sama-sama lewat ambang, yang porsinya paling besar yang menang, bukan
      // yang callback-nya kebetulan nyala paling akhir (akar bug gonta-ganti).
      _coordinator.reportVisibility(widget.postId, _visibleFraction);
    } else if (_visibleFraction <= 0.0) {
      // Keluar viewport sepenuhnya → lupakan dari arbitrase + detach.
      _coordinator.reportVisibility(widget.postId, 0);
      if (_attached) {
        _coordinator.detach(_viewId, widget.postId);
        _attached = false;
        _unbindSession();
      }
    } else {
      // Sebagian terlihat (<ambang) tapi masih di layar → porsi rendah tak akan
      // dipilih wasit; pause kalau kebetulan masih jadi aktif, tetap attached.
      _coordinator.reportVisibility(widget.postId, _visibleFraction);
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
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Media detector — membungkus HANYA layer media. Kontrol (mute,
          // retry) di bawah adalah SIBLING di ATAS detector ini (pola feed):
          // tap kontrol terserap dulu → arena double-tap media tak aktif →
          // kontrol instan. _anchorKey WAJIB tetap di sini (morph transition
          // anchor; bounds tak berubah krn ini child pertama full-size Stack).
          GestureDetector(
            key: _anchorKey,
            behavior: HitTestBehavior.opaque,
            onTap: widget.dormant ? null : widget.onMediaSingleTap,
            onDoubleTapDown: widget.onMediaDoubleTapDown,
            onDoubleTap: widget.onMediaDoubleTap,
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
                  const _MediaPlaceholder(
                      icon: Icons.video_collection_outlined),
                // Saat controller sudah initialized tetapi frame pertamanya
                // belum terbukti keluar, pertahankan thumbnail. Ini mencegah
                // surface beku/black terlihat sementara audio gate dan
                // recovery bekerja.
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
              ],
            ),
          ),
          // ── Kontrol: SIBLING di ATAS media detector (bukan child-nya) ──
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
                        fontWeight: NataloWeight.onMedia,
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
                              fontWeight: NataloWeight.strong,
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
                    muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ),
        ],
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
                  fontWeight: NataloWeight.strong,
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
                  fontWeight: NataloWeight.strong,
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

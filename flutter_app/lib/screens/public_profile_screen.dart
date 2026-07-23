import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/natalo_colors.dart';
import '../theme/natalo_text.dart';
import 'package:share_plus/share_plus.dart';

import '../config/api_config.dart';
import '../models/feed_post.dart';
import '../features/feed/transition/post_hero.dart';
import '../features/feed/transition/post_viewer_route.dart';
import '../features/feed/transition/profile_tile_visibility.dart';
import '../features/feed/video/post_video_warm_handoff.dart';
import '../features/feed/widgets/gallery_post_tile.dart'
    show gridShowsLetterbox;
import '../models/public_profile.dart';
import '../services/api_client.dart';
import '../services/follow_service.dart';
import '../services/profile_service.dart';
import '../services/report_service.dart';
import '../services/video_quality_service.dart';
import '../state/chat_store.dart';
import '../state/feed_store.dart';
import '../state/follow_override_store.dart';
import '../state/member_store.dart';
import '../state/settings_store.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import '../widgets/app_toast.dart';
import '../widgets/app_ui.dart';
import '../widgets/calm_scroll_physics.dart';
import '../widgets/collapsing_header_delegate.dart';
import '../widgets/moderation_action_sheet.dart';
import '../widgets/natalo_paw_refresh_indicator.dart';
import '../widgets/profile_grid_geometry.dart';
import '../widgets/public_profile_chrome_overlay.dart';
import '../widgets/public_profile_identity_tab_header.dart';
import 'member_post_detail_screen.dart';
import 'public_profile_follow_list_screen.dart';

const _brandBlue = NataloColors.primary;
const _profileContentTabs = <PublicProfileContentFilter>[
  PublicProfileContentFilter.all,
  PublicProfileContentFilter.video,
  PublicProfileContentFilter.shoppable,
];

@visibleForTesting
class ProfilePostOriginKeyCache {
  final _keys = <String, GlobalKey>{};

  GlobalKey forPost(PublicProfileContentFilter content, String postId) {
    final cacheKey = '${content.name}:$postId';
    return _keys.putIfAbsent(cacheKey, GlobalKey.new);
  }
}

@visibleForTesting
PublicProfile rebasePublicProfileForViewer(
  PublicProfile profile, {
  required String? viewerId,
}) {
  return profile.copyWith(
    isFollowing: false,
    isOwner: viewerId != null && viewerId == profile.id,
    mutualFollowers: PublicProfileMutualSummary.empty,
  );
}

@visibleForTesting
List<FeedPost> canonicalizePublicProfilePosts(
  Iterable<FeedPost> posts, {
  required FeedStore store,
}) {
  return posts
      .where((post) => !store.wasRemoved(post.id))
      .map((post) => store.get(post.id) ?? post)
      .toList(growable: false);
}

class _ProfileContentState {
  List<FeedPost> posts = const [];
  String? nextCursor;
  String? errorText;
  bool loaded = false;
  bool loading = false;
  bool loadingMore = false;
}

typedef ProfileWarmHandoffFactory = PostVideoWarmHandoff? Function(
  FeedPost post,
);

/// Satu slot prewarm untuk grid Profile. Widget hanya memanggil prepare/take/
/// cancel; kelas ini memastikan kandidat lama selalu dilepas sebelum kandidat
/// baru hidup dan ownership hanya berpindah pada tap yang sah.
@visibleForTesting
class ProfileVideoPrewarmer {
  ProfileVideoPrewarmer({required ProfileWarmHandoffFactory factory})
      : _factory = factory;

  final ProfileWarmHandoffFactory _factory;
  String? _postId;
  PostVideoWarmHandoff? _handoff;

  void prepare(FeedPost post) {
    if (!post.isVideo) {
      cancel();
      return;
    }
    if (_postId == post.id) return;
    final stale = _handoff;
    _handoff = _factory(post);
    _postId = _handoff == null ? null : post.id;
    unawaited(stale?.disposeIfUnclaimed());
  }

  PostVideoWarmHandoff? take(FeedPost post) {
    if (_postId != post.id) {
      cancel();
      return null;
    }
    final handoff = _handoff;
    _handoff = null;
    _postId = null;
    return handoff;
  }

  void cancel([String? postId]) {
    if (postId != null && _postId != postId) return;
    final handoff = _handoff;
    _handoff = null;
    _postId = null;
    unawaited(handoff?.disposeIfUnclaimed());
  }

  Future<void> dispose() async {
    final handoff = _handoff;
    _handoff = null;
    _postId = null;
    await handoff?.disposeIfUnclaimed();
  }
}

/// Public profile screen — `/u/{username}` deep link target +
/// destination saat user tap @username di feed/komentar.
///
/// Layout: header (avatar + handle + bio + stats) → tombol Follow
/// (atau Edit Profil kalau owner) → Grid / Video / Belanja.
///
/// Owner view: tombol "Edit Profil" → /member/profile. Other view:
/// tombol "Follow" / "Mengikuti" via NestJS social service.
class PublicProfileScreen extends StatefulWidget {
  /// Handle target (raw — server lowercase + validate). Bisa di-set
  /// dari deep link, navigator argument, atau tap @mention nanti.
  final String username;
  @visibleForTesting
  final PublicProfileResult? initialResult;
  @visibleForTesting
  final ProfileWarmHandoffFactory? warmHandoffFactory;
  @visibleForTesting
  final AsyncCallback? fetchChatConfig;

  const PublicProfileScreen({
    super.key,
    required this.username,
    this.initialResult,
    this.warmHandoffFactory,
    this.fetchChatConfig,
  });

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  PublicProfile? _profile;
  final Map<PublicProfileContentFilter, _ProfileContentState> _contentStates = {
    PublicProfileContentFilter.all: _ProfileContentState(),
    PublicProfileContentFilter.video: _ProfileContentState(),
    PublicProfileContentFilter.shoppable: _ProfileContentState(),
  };
  PublicProfileContentFilter _selectedContent = PublicProfileContentFilter.all;
  bool _loading = true;
  bool _openingPost = false;
  bool _followBusy = false;
  String? _errorText;
  bool _notFound = false;
  late int _viewerGeneration;
  final _tileKeys = ProfilePostOriginKeyCache();

  late final ScrollController _scrollController;
  late final TabController _tabController;
  late final ProfileVideoPrewarmer _videoPrewarmer;

  @override
  void initState() {
    super.initState();
    unawaited((widget.fetchChatConfig ?? chatStore.fetchConfig)());
    WidgetsBinding.instance.addObserver(this);
    _scrollController = ScrollController();
    _videoPrewarmer = ProfileVideoPrewarmer(
      factory: widget.warmHandoffFactory ?? _createWarmHandoff,
    );
    _tabController =
        TabController(length: _profileContentTabs.length, vsync: this)
          ..addListener(_onTabControllerChanged);
    _viewerGeneration = memberStore.viewerGeneration;
    memberStore.addListener(_onViewerChanged);
    followOverrides.addListener(_onFollowOverridesChanged);
    feedStore.addListener(_onFeedStoreChanged);
    final initialResult = widget.initialResult;
    if (initialResult != null) {
      _seedInitialResult(initialResult);
    } else {
      _load();
    }
  }

  void _seedInitialResult(PublicProfileResult result) {
    final contentState = _contentStates[PublicProfileContentFilter.all]!;
    _profile = result.profile.copyWith(
      isFollowing: resolveFollowState(
        result.profile.id,
        result.profile.isFollowing,
      ),
    );
    contentState
      ..posts = _canonicalPosts(result.posts)
      ..nextCursor = result.nextCursor
      ..loaded = true
      ..loading = false;
    _loading = false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_videoPrewarmer.dispose());
    memberStore.removeListener(_onViewerChanged);
    followOverrides.removeListener(_onFollowOverridesChanged);
    feedStore.removeListener(_onFeedStoreChanged);
    _tabController
      ..removeListener(_onTabControllerChanged)
      ..dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final profile = _profile;
    if (profile != null && !profile.isOwner) {
      unawaited(_refreshFollowState(profile.id));
    }
  }

  void _onFollowOverridesChanged() {
    final profile = _profile;
    if (!mounted || profile == null || profile.isOwner) return;
    final following = resolveFollowState(profile.id, profile.isFollowing);
    if (following == profile.isFollowing) return;
    final followerDelta = following ? 1 : -1;
    final followersCount = profile.followersCount + followerDelta;
    setState(() => _profile = profile.copyWith(
          isFollowing: following,
          followersCount: followersCount < 0 ? 0 : followersCount,
        ));
  }

  void _onViewerChanged() {
    final generation = memberStore.viewerGeneration;
    if (generation == _viewerGeneration) return;
    _viewerGeneration = generation;
    _followBusy = false;
    final profile = _profile;
    if (profile != null && mounted) {
      setState(() {
        for (final contentState in _contentStates.values) {
          contentState
            ..loaded = false
            ..loading = false
            ..loadingMore = false;
        }
        _profile = rebasePublicProfileForViewer(
          profile,
          viewerId: memberStore.profile?.id,
        );
      });
    }
    unawaited(_load(showInitialLoading: false));
  }

  List<FeedPost> _canonicalPosts(Iterable<FeedPost> posts) =>
      canonicalizePublicProfilePosts(posts, store: feedStore);

  void _onFeedStoreChanged() {
    if (!mounted) return;
    var changed = false;
    for (final contentState in _contentStates.values) {
      if (contentState.posts.isEmpty) continue;
      final canonical = _canonicalPosts(contentState.posts);
      if (canonical.length != contentState.posts.length) {
        contentState.posts = canonical;
        changed = true;
        continue;
      }
      for (var index = 0; index < canonical.length; index++) {
        if (!identical(canonical[index], contentState.posts[index])) {
          contentState.posts = canonical;
          changed = true;
          break;
        }
      }
    }
    if (changed) setState(() {});
  }

  Future<void> _load({bool showInitialLoading = true}) async {
    final requestViewerGeneration = memberStore.viewerGeneration;
    final content = _selectedContent;
    if (_shortCircuitTaggedContent(content)) return;
    final contentState = _contentStates[content]!;
    setState(() {
      // Saat pull-to-refresh, pertahankan profil lama di layar. Loading penuh
      // hanya tepat untuk kunjungan pertama ketika belum ada data sama sekali.
      if (showInitialLoading && _profile == null) _loading = true;
      _errorText = null;
      _notFound = false;
      contentState
        ..loading = true
        ..errorText = null;
    });
    // Capture sebelum await — stale-write guard. Kalau user tap like di
    // tile saat fetch jalan, store skip overwrite interaction fields.
    final fetchedAt = DateTime.now();
    try {
      final result = await profileService.fetchPublicProfile(
        username: widget.username,
        content: content,
      );
      if (!mounted || memberStore.viewerGeneration != requestViewerGeneration) {
        return;
      }
      // Seed FeedStore — supaya kalau user tap tile masuk Detail dan like
      // dari sana, post di store ke-update + grid bisa observe (kalau
      // suatu saat grid tile tampilkan likeCount visible).
      feedStore.mergeFromServer(
        result.posts,
        fetchedAt: fetchedAt,
      );
      final canonicalPosts = _canonicalPosts(result.posts);
      setState(() {
        _profile = result.profile.copyWith(
          isFollowing: resolveFollowState(
            result.profile.id,
            result.profile.isFollowing,
          ),
        );
        contentState
          ..posts = canonicalPosts
          ..nextCursor = result.nextCursor
          ..loaded = true
          ..loading = false;
        _loading = false;
      });
      final profile = _profile;
      if (profile != null && !profile.isOwner) {
        unawaited(_refreshFollowState(profile.id));
      }
    } on ApiException catch (e) {
      if (!mounted || memberStore.viewerGeneration != requestViewerGeneration) {
        return;
      }
      setState(() {
        _loading = false;
        contentState
          ..loading = false
          ..errorText = e.statusCode == 404
              ? null
              : 'Konten belum bisa dimuat. Coba lagi.';
        _notFound = e.statusCode == 404;
        _errorText = e.statusCode == 404
            ? 'User ${widget.username} tidak ditemukan.'
            : 'Gagal memuat profil. Tarik untuk coba lagi.';
      });
    } catch (_) {
      if (!mounted || memberStore.viewerGeneration != requestViewerGeneration) {
        return;
      }
      setState(() {
        _loading = false;
        contentState
          ..loading = false
          ..errorText = 'Konten belum bisa dimuat. Coba lagi.';
        _errorText = 'Gagal memuat profil. Tarik untuk coba lagi.';
      });
    }
  }

  Future<void> _refreshFollowState(String userId) async {
    final requestViewerGeneration = memberStore.viewerGeneration;
    final observedRevision = followStateRevision(userId);
    try {
      final state = await followService.fetchState(userId);
      if (!mounted ||
          _profile?.id != userId ||
          memberStore.viewerGeneration != requestViewerGeneration) {
        return;
      }
      // fetchState already reconciles the global override with the revision it
      // captured. A newer local mutation always wins through resolve().
      final following = resolveFollowState(userId, state.isFollowing);
      if (isFollowMutationPending(userId) ||
          followStateRevision(userId) != observedRevision &&
              following != state.isFollowing) {
        return;
      }
      final profile = _profile!;
      if (profile.isFollowing == following &&
          profile.followersCount == state.followersCount) {
        return;
      }
      setState(() => _profile = profile.copyWith(
            isFollowing: following,
            followersCount: state.followersCount,
          ));
    } catch (_) {
      // Visibility-scoped revalidation is best-effort. Existing profile and
      // optimistic follow state remain usable offline.
    }
  }

  Future<void> _loadMore(PublicProfileContentFilter content) async {
    final requestViewerGeneration = memberStore.viewerGeneration;
    final contentState = _contentStates[content]!;
    final cursor = contentState.nextCursor;
    if (cursor == null || contentState.loadingMore) return;
    setState(() => contentState.loadingMore = true);
    final fetchedAt = DateTime.now();
    try {
      final result = await profileService.fetchPublicProfile(
        username: widget.username,
        cursor: cursor,
        content: content,
      );
      if (!mounted || memberStore.viewerGeneration != requestViewerGeneration) {
        return;
      }
      feedStore.mergeFromServer(
        result.posts,
        fetchedAt: fetchedAt,
      );
      final existingPosts = _canonicalPosts(contentState.posts);
      final incomingPosts = _canonicalPosts(result.posts);
      setState(() {
        final existingIds = existingPosts.map((post) => post.id).toSet();
        contentState
          ..posts = [
            ...existingPosts,
            ...incomingPosts.where((post) => existingIds.add(post.id)),
          ]
          ..nextCursor = result.nextCursor
          ..loadingMore = false;
      });
    } catch (_) {
      if (!mounted || memberStore.viewerGeneration != requestViewerGeneration) {
        return;
      }
      setState(() => contentState.loadingMore = false);
    }
  }

  Future<void> _refresh() async => _load(showInitialLoading: false);

  /// Tab "Ditandai" (enum lama: shoppable) sengaja selalu kosong sampai Spec B
  /// membangun data tag-orang — jangan pernah memanggil network fetch untuk
  /// filter ini, dari jalur manapun (tap/swipe MAUPUN refresh/reload). Return
  /// true kalau content ini di-short-circuit (state sudah diset kosong,
  /// caller HARUS berhenti, tidak lanjut fetch). Lihat
  /// docs/superpowers/specs/2026-07-22-tutup-tag-belanja-spec-a-design.md.
  bool _shortCircuitTaggedContent(PublicProfileContentFilter content) {
    if (content != PublicProfileContentFilter.shoppable) return false;
    final contentState = _contentStates[content]!;
    if (!contentState.loaded) {
      setState(() {
        contentState
          ..loaded = true
          ..posts = const [];
      });
    }
    return true;
  }

  void _activateContent(PublicProfileContentFilter content) {
    if (content == _selectedContent) return;
    setState(() => _selectedContent = content);
    if (_shortCircuitTaggedContent(content)) return;
    final contentState = _contentStates[content]!;
    if (!contentState.loaded && !contentState.loading) {
      unawaited(_loadSelectedContent(content));
    }
  }

  void _onTabTapped(int index) {
    if (index == _profileContentTabs.indexOf(_selectedContent)) return;
    // Haptic ganti-tab sengaja dimatikan (permintaan user) — pindah tab
    // profil harus terasa halus, tanpa getar. AppHaptics.tap tetap dipakai
    // di aksi lain (buka post, share, follow, dll).
    _activateContent(_profileContentTabs[index]);
  }

  void _onTabControllerChanged() {
    if (_tabController.indexIsChanging) return;
    final position = _tabController.animation?.value;
    if (position != null && (position - _tabController.index).abs() > 0.001) {
      return;
    }
    _activateContent(_profileContentTabs[_tabController.index]);
  }

  bool _handleContentScroll(
    PublicProfileContentFilter content,
    ScrollNotification notification,
  ) {
    if (notification.metrics.axis != Axis.vertical ||
        notification.metrics.extentAfter >= 400) {
      return false;
    }
    final contentState = _contentStates[content]!;
    if (!contentState.loadingMore && contentState.nextCursor != null) {
      unawaited(_loadMore(content));
    }
    return false;
  }

  Future<void> _loadSelectedContent(
    PublicProfileContentFilter content,
  ) async {
    final requestViewerGeneration = memberStore.viewerGeneration;
    final contentState = _contentStates[content]!;
    setState(() {
      contentState
        ..loading = true
        ..errorText = null;
    });
    final fetchedAt = DateTime.now();
    try {
      final result = await profileService.fetchPublicProfile(
        username: widget.username,
        content: content,
      );
      if (!mounted || memberStore.viewerGeneration != requestViewerGeneration) {
        return;
      }
      feedStore.mergeFromServer(result.posts, fetchedAt: fetchedAt);
      final canonicalPosts = _canonicalPosts(result.posts);
      setState(() {
        contentState
          ..posts = canonicalPosts
          ..nextCursor = result.nextCursor
          ..loaded = true
          ..loading = false;
      });
    } catch (_) {
      if (!mounted || memberStore.viewerGeneration != requestViewerGeneration) {
        return;
      }
      setState(() {
        contentState
          ..loading = false
          ..errorText = 'Konten belum bisa dimuat. Coba lagi.';
      });
    }
  }

  Future<void> _openFollowList(FollowListKind kind) async {
    final profile = _profile;
    if (profile == null) return;
    AppHaptics.tap();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PublicProfileFollowListScreen(
          profile: profile,
          initialKind: kind,
        ),
      ),
    );
    if (mounted) _refresh();
  }

  /// Scope hero WAJIB mengandung username (profil A di atas profil B di
  /// navigation stack tidak boleh bentrok tag) DAN content filter — sama
  /// alasan dgn `_MemberScreenState._heroScopeFor` (member_screen.dart):
  /// `TabBarView` membangun tab tetangga saat swipe
  /// (allowImplicitScrolling), jadi post yang sama bisa muncul di dua tab
  /// grid sekaligus (mis. video ada di 'all' dan 'video') — tag hero
  /// duplikat di tree yang sama membuat Flutter menonaktifkan hero itu
  /// diam-diam.
  String _heroScopeFor(PublicProfileContentFilter content) =>
      'publicProfile-${widget.username}-${content.name}';

  Future<void> _openPost(
    PublicProfileContentFilter content,
    int index,
  ) async {
    final posts = _contentStates[content]!.posts;
    if (index < 0 || index >= posts.length || _openingPost) {
      _cancelPreparedVideo();
      return;
    }
    _openingPost = true;
    final profile = _profile;
    final post = posts[index];
    final handoff = _videoPrewarmer.take(post) ?? _createWarmHandoff(post);
    AppHaptics.tap();
    try {
      await pushPostViewer<void>(
        context,
        // IG-style: bukan single-post screen, tapi vertical-scroll feed
        // dari SEMUA posts user — initial scrolled ke tile yang di-tap.
        // Author header pakai data dari PublicProfile (bukan memberStore,
        // karena viewer != author). isOwner: false → sembunyikan menu
        // edit/delete (cuma owner di "Postingan Saya" yang lihat itu).
        builder: (_) => MemberPostDetailScreen(
          post: post,
          posts: posts,
          initialIndex: index,
          authorName: profile?.name,
          authorPhotoUrl: profile?.profilePhotoUrl,
          authorInitial: profile?.initial,
          // Official → detail render identitas brand (logo + emas +
          // rosette) di author row, caption, dan subtitle AppBar.
          authorIsOfficial: profile?.isOfficial ?? false,
          // Item /api/u/{username} TIDAK bawa objek author → post.author.id
          // kosong & isFollowing false. Chip "Ikuti/Mengikuti" header butuh
          // identitas dari level profil (yang akurat + key-nya sama dgn
          // followOverrides yang di-set tombol follow profil).
          authorId: profile?.id,
          authorIsFollowing: resolveFollowState(
            profile?.id ?? '',
            profile?.isFollowing ?? false,
          ),
          isOwner: profile?.isOwner ?? false,
          warmVideoHandoff: handoff,
          initialNextCursor: _contentStates[content]!.nextCursor,
          loadMoreScopedPosts: (cursor) async {
            final result = await profileService.fetchPublicProfile(
              username: widget.username,
              cursor: cursor,
              content: content,
            );
            return FeedPage(
              items: result.posts,
              nextCursor: result.nextCursor,
            );
          },
          heroScope: _heroScopeFor(content),
          onWillClose: (activePostId) => _revealTile(content, activePostId),
        ),
      );
    } finally {
      await handoff?.disposeIfUnclaimed();
      _openingPost = false;
    }
  }

  /// Dipanggil sinkron saat viewer pop, dengan id post yang sedang tampil.
  /// Fire-and-forget — TIDAK menunggu animasi/scroll selesai. Mirror
  /// `_MemberScreenState._revealTile` (member_screen.dart). Halaman ini
  /// TIDAK punya bottom nav (lihat Scaffold di build()) — bottomPadding 0.
  void _revealTile(PublicProfileContentFilter content, String activePostId) {
    final key = _tileKeys.forPost(content, activePostId);
    final ctx = key.currentContext;
    if (ctx != null) {
      unawaited(ensureProfileTileVisible(ctx));
      return;
    }
    // Tile belum dibangun (di luar viewport jauh) — estimasi posisi baris
    // via index di list scope ini, lalu jumpTo langsung tanpa animasi.
    final posts = _contentStates[content]!.posts;
    final index = posts.indexWhere((p) => p.id == activePostId);
    if (index < 0) return;
    BuildContext? anyTileCtx;
    for (final p in posts) {
      final c = _tileKeys.forPost(content, p.id).currentContext;
      if (c != null) {
        anyTileCtx = c;
        break;
      }
    }
    final scrollable =
        anyTileCtx == null ? null : Scrollable.maybeOf(anyTileCtx);
    if (scrollable == null) return;
    final position = scrollable.position;
    final renderObject = anyTileCtx!.findRenderObject();
    final tileHeight = (renderObject is RenderBox && renderObject.hasSize)
        ? renderObject.size.height
        : 0.0;
    if (tileHeight <= 0) return;
    final rowExtent = tileHeight + profileGridMainAxisSpacing;
    final targetRow = index ~/ profileGridCrossAxisCount;
    final targetOffset = (targetRow * rowExtent).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    position.jumpTo(targetOffset);
  }

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

  /// Mulai menyiapkan hanya video yang sedang disentuh. Constructor session
  /// langsung menjalankan init dalam keadaan paused+muted; ownership baru
  /// berpindah ke halaman Postingan ketika tap benar-benar selesai.
  void _prepareVideo(FeedPost post) {
    if (_openingPost) return;
    _videoPrewarmer.prepare(post);
  }

  /// Gesture dibatalkan (biasanya grid mulai scroll): lepaskan kandidat agar
  /// tile yang tidak jadi dibuka tidak meninggalkan controller hidup.
  void _cancelPreparedVideo([String? postId]) {
    _videoPrewarmer.cancel(postId);
  }

  Future<void> _toggleFollow() async {
    final requestViewerGeneration = memberStore.viewerGeneration;
    final current = _profile;
    if (current == null || current.isOwner || _followBusy) return;
    AppHaptics.tap();

    final wasFollowing = current.isFollowing;
    final optimisticFollowers =
        current.followersCount + (wasFollowing ? -1 : 1);
    setState(() {
      _followBusy = true;
      _profile = current.copyWith(
        isFollowing: !wasFollowing,
        followersCount: optimisticFollowers < 0 ? 0 : optimisticFollowers,
      );
    });
    setFollowOverride(current.id, !wasFollowing);

    try {
      final state = wasFollowing
          ? await followService.unfollow(current.id)
          : await followService.follow(current.id);
      if (!mounted || memberStore.viewerGeneration != requestViewerGeneration) {
        return;
      }
      setState(() {
        _followBusy = false;
        _profile = (_profile ?? current).copyWith(
          isFollowing: state.isFollowing,
          followersCount: state.followersCount,
          followingCount: state.followingCount,
        );
      });
      setFollowOverride(current.id, state.isFollowing);
    } on FollowSessionChangedException {
      if (mounted) setState(() => _followBusy = false);
    } on ApiException catch (e) {
      if (!mounted || memberStore.viewerGeneration != requestViewerGeneration) {
        return;
      }
      final stableFollowing = resolveFollowState(current.id, wasFollowing);
      final stableFollowers = current.followersCount +
          (stableFollowing == wasFollowing
              ? 0
              : stableFollowing
                  ? 1
                  : -1);
      setState(() {
        _followBusy = false;
        _profile = current.copyWith(
          isFollowing: stableFollowing,
          followersCount: stableFollowers < 0 ? 0 : stableFollowers,
        );
      });
      if (e.isUnauthorized) {
        Navigator.pushNamed(context, '/member/login');
      } else {
        _showSnack(e.message);
      }
    } catch (_) {
      if (!mounted || memberStore.viewerGeneration != requestViewerGeneration) {
        return;
      }
      final stableFollowing = resolveFollowState(current.id, wasFollowing);
      final stableFollowers = current.followersCount +
          (stableFollowing == wasFollowing
              ? 0
              : stableFollowing
                  ? 1
                  : -1);
      setState(() {
        _followBusy = false;
        _profile = current.copyWith(
          isFollowing: stableFollowing,
          followersCount: stableFollowers < 0 ? 0 : stableFollowers,
        );
      });
      _showSnack('Gagal memproses follow. Coba lagi.');
    }
  }

  // Kedua caller (ApiException.message + fallback catch) sama-sama jalur
  // kegagalan follow/unfollow → kind error tetap untuk semua pesan.
  void _showSnack(String message) {
    AppToast.showBanner(context, message, kind: ToastKind.error);
  }

  /// Share link profil publik `/u/{username}` via native share sheet.
  /// Konsisten dgn pola share feed (title + url). Kalau username null
  /// (user lama belum set), fallback share link app base.
  Future<void> _shareProfile() async {
    final profile = _profile;
    if (profile == null) return;
    AppHaptics.tap();
    try {
      final username = profile.username;
      final url = (username != null && username.isNotEmpty)
          ? ApiConfig.uri('/u/$username').toString()
          : ApiConfig.uri('/').toString();
      final label = profile.isOfficial ? profile.name : profile.displayHandle;
      // sharePositionOrigin WAJIB untuk iOS (popover anchor); tanpa ini share
      // gagal/senyap di iOS. Di Android tak berpengaruh.
      final box = context.findRenderObject() as RenderBox?;
      await Share.share(
        'Lihat profil $label di Natalo\n$url',
        sharePositionOrigin:
            box != null ? box.localToGlobal(Offset.zero) & box.size : null,
      );
    } catch (_) {
      // Cancel / share fail — silent.
    }
  }

  /// Buka sheet moderasi (Laporkan / Blokir) untuk profil ini. Wajib
  /// Google Play UGC policy — reuse [showModerationActions] yang sama
  /// dgn feed. Setelah block, keluar dari halaman profil (konten user
  /// disembunyikan, tak masuk akal tetap lihat profilnya).
  Future<void> _openModeration() async {
    final profile = _profile;
    if (profile == null) return;
    AppHaptics.tap();
    final result = await showModerationActions(
      context,
      targetKind: ReportTargetKind.user,
      targetId: profile.id,
      authorId: profile.id,
      authorName: profile.name,
    );
    if (!mounted) return;
    if (result?.didBlock == true) {
      Navigator.maybePop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Satu layout IG-style putih untuk SEMUA akun — mode hero navy
    // official (plus seluruh workaround seam/gap-nya) sudah dihapus.
    // Official dibedakan lewat badge + chip di dalam header.
    final profile = _profile;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: Theme.of(context).brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: cs.surface,
        // Loading/error routes retain a conventional back affordance. Once
        // profile data exists, navigation is owned by the collapsing sliver.
        appBar: profile == null
            ? AppBar(
                backgroundColor: cs.surface,
                surfaceTintColor: cs.surface,
                elevation: 0,
                leading: IconButton(
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.arrow_back_rounded),
                  tooltip: 'Kembali',
                ),
                title: Text(widget.username),
              )
            : null,
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: _brandBlue, strokeWidth: 2.4),
      );
    }
    if (_notFound) return _NotFoundView(handle: widget.username);
    if (_errorText != null && _profile == null) {
      return AppErrorState(description: _errorText!, onRetry: _load);
    }
    final profile = _profile!;
    final metrics = PublicProfileHeaderMetrics.resolve(context, profile);
    final headerLeadInset = metrics.topPadding + metrics.toolbarHeight;
    // Header hanya boleh melipat kalau konten tab aktif benar-benar
    // memerlukan scroll. Akun sepi (1-2 post) tak punya apa pun untuk
    // digulir di bawah header penuh — biarkan diam daripada melipat
    // "kosong" (lipat + pill mengambang tanpa konten baru yang terungkap).
    // Syarat nextCursor == null: freeze cuma setelah kita YAKIN semua
    // halaman sudah termuat, supaya header tidak "meleleh" mid-scroll
    // begitu load-more datang.
    final activeContentState = _contentStates[_selectedContent]!;
    final gridWidth = MediaQuery.sizeOf(context).width;
    final gridHeight = profileGridExtentForWidth(
      gridWidth,
      itemCount: activeContentState.posts.length,
    );
    final availableBodyHeight =
        MediaQuery.sizeOf(context).height - metrics.scrollSpaceHeight;
    final freezeHeader = activeContentState.loaded &&
        !activeContentState.loading &&
        activeContentState.nextCursor == null &&
        gridHeight <= availableBodyHeight;
    final nestedScrollView = NestedScrollView(
      controller: _scrollController,
      // Fling diredam ala IG — lihat CalmScrollPhysics.
      physics: const CalmScrollPhysics(),
      headerSliverBuilder: (context, innerBoxIsScrolled) => [
        // PINNED spacer (bukan SliverToBoxAdapter biasa) — sengaja. Sliver
        // pinned lain di bawahnya (tab bar) selalu menempel ke Y=0 viewport
        // begitu scroll penuh, TERLEPAS dari tinggi konten non-pinned di
        // atasnya (mekanisme pinning Flutter: header pinned "nempel" ke tepi
        // viewport, bukan ke posisi setelah sliver sebelumnya). Supaya tab
        // bar berhenti TEPAT di bawah toolbar overlay (bukan di y=0 balik
        // lagi), spacer ini juga harus pinned dgn minExtent==maxExtent —
        // jadi ia sendiri yang "duduk" permanen di y=0..H, dan sliver
        // pinned berikutnya otomatis bertumpuk tepat di bawahnya.
        SliverPersistentHeader(
          pinned: true,
          delegate: CollapsingHeaderDelegate(
            minHeight: headerLeadInset,
            maxHeight: headerLeadInset,
            builder: (context, t) => SizedBox(
              height: headerLeadInset,
            ),
          ),
        ),
        SliverPersistentHeader(
          pinned: true,
          delegate: CollapsingHeaderDelegate(
            minHeight: freezeHeader
                ? metrics.identityHeight + metrics.tabHeight
                : metrics.tabHeight,
            maxHeight: metrics.identityHeight + metrics.tabHeight,
            builder: (context, t) => AnimatedBuilder(
              animation: chatStore,
              builder: (context, child) => PublicProfileIdentityTabHeader(
                profile: profile,
                followBusy: _followBusy,
                chatEnabled: chatStore.chatEnabled,
                tabController: _tabController,
                identityHeight: metrics.identityHeight,
                tabHeight: metrics.tabHeight,
                t: t,
                onFollowToggle: profile.isOwner ? null : _toggleFollow,
                onFollowersTap: () => _openFollowList(FollowListKind.followers),
                onFollowingTap: () => _openFollowList(FollowListKind.following),
                onEditProfile: profile.isOwner
                    ? () => Navigator.pushNamed(
                          context,
                          '/member/profile',
                        )
                    : null,
                onShareProfile: _shareProfile,
                onMessage: profile.isOfficial && !profile.isOwner
                    ? () => Navigator.pushNamed(context, '/chat')
                    : null,
                onTabTap: _onTabTapped,
              ),
            ),
          ),
        ),
      ],
      body: TabBarView(
        controller: _tabController,
        children: _profileContentTabs.map(_buildContentPage).toList(),
      ),
    );
    final refreshedContent = NataloPawRefreshIndicator(
      onRefresh: _refresh,
      triggerOffset: 96,
      requireFullPull: true,
      translateChild: false,
      minimalIndicator: true,
      includeSafeAreaPadding: false,
      indicatorColor: _brandBlue,
      refreshBackdropColor: Theme.of(context).colorScheme.surface,
      child: nestedScrollView,
    );
    return Stack(
      children: [
        RepaintBoundary(
          key: const Key('public_profile_grid_underlay'),
          child: refreshedContent,
        ),
        AnimatedBuilder(
          animation: _scrollController,
          builder: (context, child) {
            // Sliver leading (pinned spacer topPadding+toolbarHeight) kini
            // mendahului sliver identity+tab, jadi ia ikut memakan
            // scrollExtent sebelum identity mulai menyusut. Kurangi dulu
            // supaya `t` di sini (crossfade chrome) tetap SAMA PERSIS dengan
            // `t` yang dihitung CollapsingHeaderDelegate dari shrinkOffset
            // lokal sliver identity — tanpa ini, chrome akan tampak "selesai"
            // collapse jauh sebelum identity di bawahnya benar-benar habis.
            final shrinkOffset = _scrollController.hasClients
                ? (_scrollController.offset - headerLeadInset)
                    .clamp(0.0, metrics.identityHeight)
                    .toDouble()
                : 0.0;
            // Frozen: paksa t=0 supaya overlay (back button, judul, pill)
            // tetap dalam mode expanded, terlepas dari overscroll/bounce
            // kecil yang bisa menggeser _scrollController.offset.
            final t = freezeHeader
                ? 0.0
                : metrics.identityHeight > 0
                    ? shrinkOffset / metrics.identityHeight
                    : 1.0;
            return PublicProfileChromeOverlay(
              profile: profile,
              t: t,
              metrics: metrics,
              onBack: () => Navigator.maybePop(context),
              onShareProfile: _shareProfile,
              onOverflow: !profile.isOwner && !profile.isOfficial
                  ? _openModeration
                  : null,
            );
          },
        ),
      ],
    );
  }

  Widget _buildContentPage(PublicProfileContentFilter content) {
    final contentState = _contentStates[content]!;
    final posts = contentState.posts;
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) =>
          _handleContentScroll(content, notification),
      child: CustomScrollView(
        key: PageStorageKey<String>('public-profile-${content.name}'),
        // WAJIB sama dgn physics NestedScrollView outer (di atas) — physics
        // outer TIDAK otomatis diwariskan ke body (dok NestedScrollView.
        // physics: "the inner scroll view is not directly configured").
        // Beda physics outer/inner bikin hand-off ballistic pincang: scroll
        // ke atas terasa "stuck" (outer diredam) lalu "terdorong" (inner
        // masih kecepatan penuh baru menyusul).
        physics: const CalmScrollPhysics(),
        slivers: [
          if ((!contentState.loaded || contentState.loading) && posts.isEmpty)
            const SliverToBoxAdapter(child: _ProfileGridLoading())
          else if (contentState.errorText != null && posts.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _ProfileContentError(
                message: contentState.errorText!,
                onRetry: () => _loadSelectedContent(content),
              ),
            )
          else if (posts.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyPosts(content: content),
            )
          else
            SliverGrid(
              gridDelegate: profileGridDelegate(),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  try {
                    return _PostTile(
                      post: posts[index],
                      originKey: _tileKeys.forPost(content, posts[index].id),
                      onTapDown: () => _prepareVideo(posts[index]),
                      onTapCancel: () => _cancelPreparedVideo(posts[index].id),
                      onTap: () => _openPost(content, index),
                      showCommerceBadge:
                          content == PublicProfileContentFilter.shoppable,
                      heroScope: _heroScopeFor(content),
                    );
                  } catch (_) {
                    return ColoredBox(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                    );
                  }
                },
                childCount: posts.length,
              ),
            ),
          if (contentState.loadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: CircularProgressIndicator(
                    color: _brandBlue,
                    strokeWidth: 2,
                  ),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

class _PostTile extends StatelessWidget {
  final FeedPost post;
  final GlobalKey originKey;
  final VoidCallback onTap;
  final VoidCallback? onTapDown;
  final VoidCallback? onTapCancel;
  final bool showCommerceBadge;
  final String heroScope;

  const _PostTile({
    required this.post,
    required this.originKey,
    required this.onTap,
    this.onTapDown,
    this.onTapCancel,
    this.showCommerceBadge = false,
    required this.heroScope,
  });

  @override
  Widget build(BuildContext context) {
    // CRITICAL: wrap entire tile body in Builder + try-catch supaya
    // build()-time error (CachedNetworkImage assert, Uri parse fail, dll)
    // ke-catch lokal SEBELUM sampai ke ErrorWidget.builder global yang
    // jadi banner gede "Terjadi kesalahan".
    //
    // Note: per-tile try-catch di SliverChildBuilderDelegate hanya catch
    // CONSTRUCTOR errors (yang gak pernah throw untuk const widget) —
    // build()-time errors di child widget langsung intercept oleh
    // ErrorWidget.builder global. Try-catch di SINI dalam build method
    // catches semua synchronous errors di tile.
    return Builder(
      builder: (innerContext) {
        try {
          return _buildSafeTile(innerContext);
        } catch (_) {
          // Last-resort fallback — render plain colored box. Catatan: ini
          // CUMA catch error sync di build path. Async errors (download
          // image fail) sudah di-handle oleh CachedNetworkImage.errorWidget.
          return ColoredBox(
            color: Theme.of(innerContext).colorScheme.surfaceContainerHighest,
          );
        }
      },
    );
  }

  Widget _buildSafeTile(BuildContext context) {
    // Resolve thumb dgn fallback chain — thumbnailUrl post → thumbnailUrl
    // media pertama → mediaUrl media pertama → mediaUrl post.
    // previewMediaUrl getter handles fallback chain: thumbnailUrl →
    // mediaItems.first.thumbnailUrl → mediaItems.first.mediaUrl → videoUrl.
    final thumb = post.previewMediaUrl.trim();

    // STRICT URL validation — pakai Uri.tryParse + check scheme + host.
    // Defensive untuk edge case: "https://" tanpa host, URL dengan space,
    // path relative, "javascript:" scheme, dll. Sebelumnya cuma cek
    // startsWith yang gampang lolos URL malformed.
    final parsedUri = Uri.tryParse(thumb);
    final isValidImageUrl = parsedUri != null &&
        (parsedUri.scheme == 'http' || parsedUri.scheme == 'https') &&
        parsedUri.hasAuthority;

    final cs = Theme.of(context).colorScheme;
    final productCount = post.products.length;
    final primaryPrice = _lowestProductPrice(post.products);
    return RepaintBoundary(
      key: originKey,
      child: Semantics(
        button: true,
        label: showCommerceBadge && productCount > 0
            ? 'Postingan belanja dengan $productCount produk'
            : post.isVideo
                ? 'Postingan video'
                : 'Postingan foto',
        child: GestureDetector(
          key: ValueKey('profile-post-${post.id}'),
          onTapDown: (_) => onTapDown?.call(),
          onTapCancel: onTapCancel,
          onTap: onTap,
          child: Container(
            // Pakai decoration (bukan color shorthand) karena Container assert
            // `clipBehavior == Clip.none || decoration != null`. Pakai color:
            // shorthand TIDAK set decoration, jadi pair-up dengan
            // clipBehavior: Clip.hardEdge throw assertion saat build child —
            // dan throw itu terjadi DI LUAR try-catch _buildSafeTile (sudah
            // return), bocor ke ErrorWidget.builder global = AppErrorWidget
            // di seluruh cell. Decoration eksplisit fix root cause.
            decoration: BoxDecoration(color: cs.surfaceContainerHighest),
            clipBehavior: Clip.hardEdge,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (isValidImageUrl)
                  // Video LANDSCAPE → letterbox (contain + latar hitam,
                  // video utuh) paritas IG & GalleryPostTile. Foto/carousel
                  // + video portrait/persegi tetap cover-crop.
                  PostHero(
                    scope: heroScope,
                    postId: post.id,
                    child: _SafeNetworkImage(
                      url: thumb,
                      letterbox: gridShowsLetterbox(post),
                    ),
                  )
                else
                  ColoredBox(color: cs.surfaceContainerHighest),
                if (post.isVideo)
                  Positioned(
                    top: 6,
                    left: showCommerceBadge ? 6 : null,
                    right: showCommerceBadge ? null : 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  ),
                if (showCommerceBadge && productCount > 0)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.68),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.shopping_bag_outlined,
                            color: Colors.white,
                            size: 13,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '$productCount produk',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10.5,
                              fontWeight: NataloWeight.strong,
                              height: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (showCommerceBadge && primaryPrice != null)
                  Positioned(
                    left: 6,
                    bottom: 6,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 112),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.68),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Mulai ${formatRupiahCompact(primaryPrice)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: NataloWeight.strong,
                          height: 1,
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

  int? _lowestProductPrice(List<FeedProductLink> products) {
    final prices = products
        .expand(
          (product) => <int>[
            product.price,
            if (product.discountPrice != null) product.discountPrice!,
            if (product.promoPrice != null) product.promoPrice!,
          ],
        )
        .where((price) => price > 0)
        .toList();
    if (prices.isEmpty) return null;
    return prices.reduce((current, next) => next < current ? next : current);
  }
}

/// Defensive wrapper untuk CachedNetworkImage — catch any sync assertion
/// di constructor (jarang tapi terjadi untuk URL malformed yang lolos
/// startsWith check). Fallback ke plain ColoredBox kalau throw.
class _SafeNetworkImage extends StatelessWidget {
  final String url;

  /// Video landscape → contain (letterbox, latar hitam). Default cover.
  final bool letterbox;
  const _SafeNetworkImage({required this.url, this.letterbox = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    try {
      final image = CachedNetworkImage(
        imageUrl: url,
        fit: letterbox ? BoxFit.contain : BoxFit.cover,
        placeholder: (_, __) => ColoredBox(color: cs.surfaceContainerHighest),
        // Error → ikon broken-image (BUKAN kotak polos yang tak bisa
        // dibedakan dari placeholder loading) + log debug. Investigasi
        // "grid profil blank": CDN terbukti 200 dari server-side, jadi
        // kalau ini muncul di device = kegagalan runtime yang perlu log.
        errorWidget: (_, failedUrl, error) {
          if (kDebugMode) {
            debugPrint('[profile-grid] thumb GAGAL: $error | $failedUrl');
          }
          return ColoredBox(
            color: cs.surfaceContainerHighest,
            child: Icon(
              Icons.broken_image_outlined,
              size: 22,
              color: cs.onSurfaceVariant.withValues(alpha: 0.55),
            ),
          );
        },
      );
      // Letterbox: sisa ruang bar hitam (video utuh di tengah), konsisten
      // dgn GalleryPostTile. Cover-crop tak butuh latar karena penuhi tile.
      return letterbox ? ColoredBox(color: Colors.black, child: image) : image;
    } catch (_) {
      return ColoredBox(color: cs.surfaceContainerHighest);
    }
  }
}

class _ProfileGridLoading extends StatelessWidget {
  const _ProfileGridLoading();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        height: profileGridExtentForWidth(constraints.maxWidth, itemCount: 6),
        child: GridView.builder(
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: profileGridDelegate(),
          itemCount: 6,
          itemBuilder: (_, __) => ColoredBox(
            color: cs.surfaceContainerHighest,
          ),
        ),
      ),
    );
  }
}

class _ProfileContentError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ProfileContentError({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 36, 24, 80),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              color: cs.onSurfaceVariant,
              size: 32,
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 13,
                fontWeight: NataloWeight.body,
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Coba lagi'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyPosts extends StatelessWidget {
  final PublicProfileContentFilter content;

  const _EmptyPosts({required this.content});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 42, 24, 80),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              switch (content) {
                PublicProfileContentFilter.all => Icons.photo_library_outlined,
                PublicProfileContentFilter.video =>
                  Icons.play_circle_outline_rounded,
                PublicProfileContentFilter.shoppable =>
                  Icons.people_outline_rounded,
              },
              color: cs.onSurfaceVariant,
              size: 32,
            ),
            const SizedBox(height: 10),
            Text(
              switch (content) {
                PublicProfileContentFilter.all => 'Belum ada postingan',
                PublicProfileContentFilter.video => 'Belum ada video',
                PublicProfileContentFilter.shoppable =>
                  'Belum ada postingan yang menandai akun ini',
              },
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 14,
                fontWeight: NataloWeight.strong,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotFoundView extends StatelessWidget {
  final String handle;

  const _NotFoundView({required this.handle});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person_off_rounded,
              size: 56,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'User $handle tidak ditemukan',
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 16,
                fontWeight: NataloWeight.strong,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Mungkin username diganti atau akun sudah dihapus.',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 13,
                fontWeight: NataloWeight.body,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

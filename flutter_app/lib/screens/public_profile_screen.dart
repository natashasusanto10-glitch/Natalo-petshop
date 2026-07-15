import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/natalo_colors.dart';
import 'package:share_plus/share_plus.dart';
import '../widgets/official_brand_avatar.dart';

import '../config/api_config.dart';
import '../constants/official_brand.dart';
import '../models/feed_post.dart';
import '../features/feed/video/post_video_warm_handoff.dart';
import '../models/public_profile.dart';
import '../services/api_client.dart';
import '../services/follow_service.dart';
import '../services/profile_service.dart';
import '../services/report_service.dart';
import '../services/video_quality_service.dart';
import '../state/feed_store.dart';
import '../state/follow_override_store.dart';
import '../state/member_store.dart';
import '../state/settings_store.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import '../widgets/app_ui.dart';
import '../widgets/moderation_action_sheet.dart';
import '../widgets/natalo_paw_refresh_indicator.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/profile_grid_geometry.dart';
import '../widgets/public_profile_collapsing_header.dart';
import 'member_post_detail_screen.dart';
import 'public_profile_follow_list_screen.dart';

const _brandBlue = NataloColors.primary;
const _profileContentTabs = <PublicProfileContentFilter>[
  PublicProfileContentFilter.all,
  PublicProfileContentFilter.video,
  PublicProfileContentFilter.shoppable,
];

@visibleForTesting
PublicProfile rebasePublicProfileForViewer(
  PublicProfile profile, {
  required String? viewerId,
}) {
  return profile.copyWith(
    isFollowing: false,
    isOwner: viewerId != null && viewerId == profile.id,
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

  const PublicProfileScreen({super.key, required this.username});

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

  late final ScrollController _scrollController;
  late final TabController _tabController;
  late final ProfileVideoPrewarmer _videoPrewarmer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController = ScrollController();
    _videoPrewarmer = ProfileVideoPrewarmer(factory: _createWarmHandoff);
    _tabController =
        TabController(length: _profileContentTabs.length, vsync: this)
          ..addListener(_onTabControllerChanged);
    _viewerGeneration = memberStore.viewerGeneration;
    memberStore.addListener(_onViewerChanged);
    followOverrides.addListener(_onFollowOverridesChanged);
    feedStore.addListener(_onFeedStoreChanged);
    _load();
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

  void _activateContent(PublicProfileContentFilter content) {
    if (content == _selectedContent) return;
    setState(() => _selectedContent = content);
    final contentState = _contentStates[content]!;
    if (!contentState.loaded && !contentState.loading) {
      unawaited(_loadSelectedContent(content));
    }
  }

  void _onTabTapped(int index) {
    if (index == _profileContentTabs.indexOf(_selectedContent)) return;
    AppHaptics.tap();
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
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
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
          ),
        ),
      );
    } finally {
      await handoff?.disposeIfUnclaimed();
      _openingPost = false;
    }
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

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
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
    // Akun official → hero biru premium: AppBar SOLID heroTop (bukan
    // transparan + extendBodyBehindAppBar — inset math di dalam sliver
    // rapuh, logo pernah overlap judul di device). Header body pakai
    // heroGradientV (heroTop→heroMid) → menyambung mulus dgn AppBar tanpa
    // hitung inset. Sesuai pola hero-blue halaman lain (Akun/Transaksi).
    final isOfficial = _profile?.isOfficial ?? false;
    final profile = _profile;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isOfficial
          ? SystemUiOverlayStyle.light
          : (Theme.of(context).brightness == Brightness.dark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark),
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
    final scrollView = NataloPawRefreshIndicator(
      onRefresh: _refresh,
      triggerOffset: 96,
      requireFullPull: true,
      translateChild: false,
      minimalIndicator: true,
      includeSafeAreaPadding: false,
      indicatorColor: profile.isOfficial ? Colors.white : _brandBlue,
      refreshBackdropColor: profile.isOfficial
          ? NataloColors.heroTop
          : Theme.of(context).colorScheme.surface,
      child: NestedScrollView(
        controller: _scrollController,
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverPersistentHeader(
            pinned: true,
            delegate: PublicProfileCollapsingHeaderDelegate(
              controller: _tabController,
              title: profile.isOfficial
                  ? kOfficialBrandName
                  : profile.displayHandle,
              topPadding: MediaQuery.paddingOf(context).top,
              expandedHeight: PublicProfileCollapsingHeaderDelegate
                  .responsiveExpandedHeight(
                context,
                isOfficial: profile.isOfficial,
              ),
              isOfficial: profile.isOfficial,
              onBack: () => Navigator.maybePop(context),
              onShareProfile: _shareProfile,
              onOverflow: !profile.isOwner && !profile.isOfficial
                  ? _openModeration
                  : null,
              onTabTap: _onTabTapped,
              expandedHeader: PublicProfileExpandedHeader(
                profile: profile,
                followBusy: _followBusy,
                onFollowToggle: profile.isOwner ? null : _toggleFollow,
                onFollowersTap: () => _openFollowList(FollowListKind.followers),
                onFollowingTap: () => _openFollowList(FollowListKind.following),
                onEditProfile: profile.isOwner
                    ? () => Navigator.pushNamed(context, '/member/profile')
                    : null,
                onShareProfile: _shareProfile,
                onOpenCatalog: profile.isOfficial
                    ? () => Navigator.pushNamed(context, '/products')
                    : null,
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: _profileContentTabs.map(_buildContentPage).toList(),
        ),
      ),
    );
    if (!profile.isOfficial) return scrollView;
    // Official: lapisan navy heroTop di belakang puncak scroll — saat
    // overscroll/pull-to-refresh, header tertarik turun dan area di
    // atasnya menyingkap latar. Tanpa lapisan ini yang tersingkap putih
    // (cs.surface) → terlihat seperti garis/celah memutus hero dari
    // AppBar. Hanya tampil saat scroll dekat puncak — kalau selalu ada,
    // navy mengintip lewat celah 1px antar tile grid saat grid
    // ter-scroll ke region backdrop.
    return Stack(
      children: [
        // Positioned WAJIB anak langsung Stack (ParentData) — kondisi
        // show/hide lewat AnimatedBuilder DI DALAM Positioned.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 220,
          child: AnimatedBuilder(
            animation: _scrollController,
            builder: (context, _) {
              final show = !_scrollController.hasClients ||
                  _scrollController.offset < 40;
              return show
                  ? const ColoredBox(color: NataloColors.heroTop)
                  : const SizedBox.shrink();
            },
          ),
        ),
        Positioned.fill(child: scrollView),
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
                      onTapDown: () => _prepareVideo(posts[index]),
                      onTapCancel: () => _cancelPreparedVideo(posts[index].id),
                      onTap: () => _openPost(content, index),
                      showCommerceBadge:
                          content == PublicProfileContentFilter.shoppable,
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

/// Expanded identity surface used by the public-profile collapsing sliver.
/// Public for focused responsive tests; it remains stateless and receives all
/// actions from [PublicProfileScreen].
class PublicProfileExpandedHeader extends StatelessWidget {
  final PublicProfile profile;
  final bool followBusy;
  final VoidCallback? onFollowToggle;
  final VoidCallback? onFollowersTap;
  final VoidCallback? onFollowingTap;
  final VoidCallback? onEditProfile;
  final VoidCallback? onShareProfile;
  final VoidCallback? onOpenCatalog;

  const PublicProfileExpandedHeader({
    super.key,
    required this.profile,
    required this.followBusy,
    this.onFollowToggle,
    this.onFollowersTap,
    this.onFollowingTap,
    this.onEditProfile,
    this.onShareProfile,
    this.onOpenCatalog,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Akun official → header hero biru premium (brand store), konsisten
    // token hero-blue app. User biasa tetap layout IG standar di bawah.
    if (profile.isOfficial) {
      return _OfficialHeader(
        profile: profile,
        followBusy: followBusy,
        onFollowToggle: onFollowToggle,
        onFollowersTap: onFollowersTap,
        onFollowingTap: onFollowingTap,
        onShareProfile: onShareProfile,
        onOpenCatalog: onOpenCatalog,
      );
    }
    return Container(
      width: double.infinity,
      color: cs.surface,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Baris atas: avatar + statistik sejajar (IG-modern). Nama &
          // @handle pindah ke bawah full-width.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _Avatar(profile: profile),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _StatColumn(
                      value: profile.postCount,
                      label: 'Postingan',
                    ),
                    _StatColumn(
                      value: profile.followersCount,
                      label: 'Pengikut',
                      onTap: onFollowersTap,
                    ),
                    _StatColumn(
                      value: profile.followingCount,
                      label: 'Mengikuti',
                      onTap: onFollowingTap,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Identity: nama tebal + badge official. @handle di baris muted
          // bawahnya — kecuali akun official (username = nama asli pemilik,
          // bocor). Konsisten dgn override AppBar official.
          Row(
            children: [
              Flexible(
                child: Text(
                  profile.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
              ),
              if (profile.isOfficial) ...[
                const SizedBox(width: 4),
                const Icon(
                  Icons.verified_rounded,
                  color: _brandBlue,
                  size: 16,
                ),
              ],
            ],
          ),
          if (!profile.isOfficial &&
              profile.username != null &&
              profile.username!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              '@${profile.username}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.1,
              ),
            ),
          ],
          if (profile.bio != null && profile.bio!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              profile.bio!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w400,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 14),
          // Baris tombol: aksi utama (Edit/Follow/Mengikuti) + Bagikan.
          // Tombol Bagikan = slot kedua ala IG, square icon di sampingnya.
          Row(
            key: const Key('public_profile_action_row'),
            children: [
              Expanded(child: _buildPrimaryButton(cs)),
              if (onShareProfile != null) ...[
                const SizedBox(width: 8),
                SizedBox(
                  height: 34,
                  width: 42,
                  child: OutlinedButton(
                    onPressed: onShareProfile,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cs.onSurface,
                      side: BorderSide(color: cs.outlineVariant),
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Icon(Icons.ios_share_rounded, size: 18),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// Tombol aksi utama: Edit Profil (owner) / Mengikuti (following) /
  /// Follow (belum follow). Tinggi 34px ala IG.
  Widget _buildPrimaryButton(ColorScheme cs) {
    const textStyle = TextStyle(fontSize: 13, fontWeight: FontWeight.w800);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    );
    if (onEditProfile != null) {
      return SizedBox(
        height: 34,
        child: OutlinedButton(
          onPressed: onEditProfile,
          style: OutlinedButton.styleFrom(
            foregroundColor: cs.onSurface,
            side: BorderSide(color: cs.outlineVariant),
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: textStyle,
            shape: shape,
          ),
          child: const Text('Edit Profil'),
        ),
      );
    }
    if (profile.isFollowing) {
      return SizedBox(
        height: 34,
        child: OutlinedButton(
          onPressed: onFollowToggle,
          style: OutlinedButton.styleFrom(
            foregroundColor: cs.onSurface,
            disabledForegroundColor: cs.onSurface,
            side: BorderSide(color: cs.outlineVariant),
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: textStyle,
            shape: shape,
          ),
          child: _FollowButtonContent(
            label: 'Mengikuti',
            busy: followBusy,
            spinnerColor: cs.onSurfaceVariant,
          ),
        ),
      );
    }
    return SizedBox(
      height: 34,
      child: FilledButton(
        onPressed: onFollowToggle,
        style: FilledButton.styleFrom(
          backgroundColor: _brandBlue,
          disabledBackgroundColor: _brandBlue,
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white,
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: textStyle,
          shape: shape,
        ),
        child: _FollowButtonContent(
          label: 'Ikuti',
          busy: followBusy,
          spinnerColor: Colors.white,
        ),
      ),
    );
  }
}

/// Header premium akun official — hero biru brand (token app), logo NL,
/// badge resmi, kartu statistik putih mengambang, tombol Ikuti + Bagikan.
/// Warna/spacing pakai token NataloColors supaya konsisten dgn halaman
/// hero lain (Akun/Beranda).
class _OfficialHeader extends StatelessWidget {
  final PublicProfile profile;
  final bool followBusy;
  final VoidCallback? onFollowToggle;
  final VoidCallback? onFollowersTap;
  final VoidCallback? onFollowingTap;
  final VoidCallback? onShareProfile;
  final VoidCallback? onOpenCatalog;

  const _OfficialHeader({
    required this.profile,
    required this.followBusy,
    this.onFollowToggle,
    this.onFollowersTap,
    this.onFollowingTap,
    this.onShareProfile,
    this.onOpenCatalog,
  });

  @override
  Widget build(BuildContext context) {
    // AppBar solid heroTop di atas; header ini mulai tepat di bawahnya
    // dengan gradient heroTop→heroMid → menyatu tanpa hitung inset (inset
    // manual di dalam sliver terbukti rapuh: logo overlap judul di device).
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(gradient: NataloColors.heroGradientV),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: const ProfileAvatar(
                  initial: 'N',
                  size: 78,
                  fontSize: 28,
                  isOfficial: true,
                  plain: true,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            profile.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              height: 1.1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                        const OfficialVerifiedBadge(size: 19),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color:
                            NataloColors.officialGold.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color:
                              NataloColors.officialGold.withValues(alpha: 0.48),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.shield_rounded,
                            color: NataloColors.officialGold,
                            size: 13,
                          ),
                          SizedBox(width: 5),
                          Text(
                            'AKUN RESMI',
                            style: TextStyle(
                              color: NataloColors.officialGold,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (profile.bio != null && profile.bio!.isNotEmpty) ...[
            const SizedBox(height: 13),
            Text(
              profile.bio!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.88),
                fontSize: 13,
                fontWeight: FontWeight.w400,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 16),
          // Statistik menyatu dengan hero agar profil resmi terasa seperti
          // satu permukaan, bukan kartu putih yang terpisah dari identitas.
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.18),
              ),
            ),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  child: _OfficialStat(
                    value: profile.postCount,
                    label: 'Postingan',
                    onHero: true,
                  ),
                ),
                _statDivider(),
                Expanded(
                  child: _OfficialStat(
                    value: profile.followersCount,
                    label: 'Pengikut',
                    onTap: onFollowersTap,
                    onHero: true,
                  ),
                ),
                _statDivider(),
                Expanded(
                  child: _OfficialStat(
                    value: profile.followingCount,
                    label: 'Mengikuti',
                    onTap: onFollowingTap,
                    onHero: true,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildFollowButton()),
              if (onShareProfile != null) ...[
                const SizedBox(width: 8),
                SizedBox(
                  height: 40,
                  width: 46,
                  child: OutlinedButton(
                    onPressed: onShareProfile,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Icon(Icons.ios_share_rounded, size: 18),
                  ),
                ),
              ],
            ],
          ),
          if (onOpenCatalog != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: FilledButton.icon(
                onPressed: onOpenCatalog,
                style: FilledButton.styleFrom(
                  backgroundColor: NataloColors.primary,
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.shopping_bag_outlined, size: 20),
                label: const Text('Lihat Etalase Produk'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statDivider() => Container(
        width: 0.5,
        height: 30,
        color: Colors.white.withValues(alpha: 0.22),
      );

  Widget _buildFollowButton() {
    const shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(10)),
    );
    if (profile.isFollowing) {
      // Sudah follow → outline putih di atas hero.
      return SizedBox(
        height: 40,
        child: OutlinedButton(
          onPressed: onFollowToggle,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(color: Colors.white.withValues(alpha: 0.55)),
            textStyle:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            shape: shape,
          ),
          child: _FollowButtonContent(
            label: 'Mengikuti',
            busy: followBusy,
            spinnerColor: Colors.white,
          ),
        ),
      );
    }
    // Belum follow → tombol putih solid, teks biru hero (kontras premium).
    return SizedBox(
      height: 40,
      child: FilledButton(
        onPressed: onFollowToggle,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: NataloColors.heroBottom,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          shape: shape,
        ),
        child: _FollowButtonContent(
          label: 'Ikuti',
          busy: followBusy,
          spinnerColor: NataloColors.heroBottom,
        ),
      ),
    );
  }
}

class _OfficialStat extends StatelessWidget {
  final int value;
  final String label;
  final VoidCallback? onTap;
  final bool onHero;

  const _OfficialStat({
    required this.value,
    required this.label,
    this.onTap,
    this.onHero = false,
  });

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          formatCountCompact(value),
          style: TextStyle(
            color: onHero ? Colors.white : const Color(0xFF0F2A4A),
            fontSize: 17,
            fontWeight: FontWeight.w700,
            height: 1.08,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: TextStyle(
            color: onHero
                ? Colors.white.withValues(alpha: 0.72)
                : const Color(0xFF6B7A90),
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            height: 1.08,
          ),
        ),
      ],
    );
    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: content,
      ),
    );
  }
}

class _FollowButtonContent extends StatelessWidget {
  final String label;
  final bool busy;
  final Color spinnerColor;

  const _FollowButtonContent({
    required this.label,
    required this.busy,
    required this.spinnerColor,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 140),
      child: Row(
        key: ValueKey('$label-$busy'),
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy) ...[
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: spinnerColor,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(label),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final PublicProfile profile;

  const _Avatar({required this.profile});

  @override
  Widget build(BuildContext context) {
    return ProfileAvatar(
      initial: profile.initial,
      imageUrl: profile.profilePhotoUrl,
      size: 82,
      fontSize: 30,
      isOfficial: profile.isOfficial,
      plain: true,
    );
  }
}

class _StatColumn extends StatelessWidget {
  final int value;
  final String label;
  final VoidCallback? onTap;

  const _StatColumn({
    required this.value,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final content = SizedBox(
      width: 70,
      child: Column(
        children: [
          Text(
            formatCountCompact(value),
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              height: 1.08,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.08,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: content,
        ),
      ),
    );
  }
}

class _PostTile extends StatelessWidget {
  final FeedPost post;
  final VoidCallback onTap;
  final VoidCallback? onTapDown;
  final VoidCallback? onTapCancel;
  final bool showCommerceBadge;

  const _PostTile({
    required this.post,
    required this.onTap,
    this.onTapDown,
    this.onTapCancel,
    this.showCommerceBadge = false,
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
    return Semantics(
      button: true,
      label: showCommerceBadge && productCount > 0
          ? 'Postingan belanja dengan $productCount produk'
          : post.isVideo
              ? 'Postingan video'
              : 'Postingan foto',
      child: GestureDetector(
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
                _SafeNetworkImage(url: thumb)
              else
                ColoredBox(color: cs.surfaceContainerHighest),
              if (post.isVideo)
                Positioned(
                  top: 6,
                  left: showCommerceBadge ? 6 : null,
                  right: showCommerceBadge ? null : 6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
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
                            fontWeight: FontWeight.w600,
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
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
                        fontWeight: FontWeight.w600,
                        height: 1,
                      ),
                    ),
                  ),
                ),
            ],
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
  const _SafeNetworkImage({required this.url});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    try {
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
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
                fontWeight: FontWeight.w500,
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
                  Icons.shopping_bag_outlined,
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
                  'Belum ada postingan belanja',
              },
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w800,
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
                fontWeight: FontWeight.w900,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Mungkin username diganti atau akun sudah dihapus.',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

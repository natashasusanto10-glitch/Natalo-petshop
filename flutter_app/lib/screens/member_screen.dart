import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/natalo_colors.dart';
import '../theme/natalo_text.dart';

import '../constants/official_brand.dart';
import '../models/feed_post.dart';
import '../features/feed/video/post_video_warm_handoff.dart';
import '../features/feed/widgets/gallery_post_tile.dart' show gridShowsLetterbox;
import '../models/public_profile.dart';
import '../services/api_client.dart';
import '../services/feed_service.dart';
import '../services/video_quality_service.dart';
import '../state/feed_store.dart';
import '../state/member_store.dart';
import '../state/settings_store.dart';
import '../utils/haptics.dart';
import '../widgets/app_notification_button.dart';
import '../widgets/app_ui.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/calm_scroll_physics.dart';
import 'feed_media_picker_screen.dart';
import '../widgets/natalo_paw_refresh_indicator.dart';
import '../widgets/origin_expansion_route.dart';
import '../widgets/profile_grid_geometry.dart';
import '../widgets/public_profile_content_tab_bar.dart';
import '../widgets/public_profile_expanded_header.dart';
import '../widgets/username_prompt_banner.dart';
import 'member_post_detail_screen.dart';
import 'profile_qr_screen.dart';
import 'public_profile_follow_list_screen.dart';

/// Halaman Akun — social profile + galeri postingan user.
///
/// Layout: Header (+ icon, bell, cart) → Profile section (foto + stats
/// Postingan/Pengikut/Mengikuti + nama + @username + bio + tombol Edit/
/// Bagikan) → Tab bar (Postingan/Video/Belanja) → Grid 3-kolom.
///
/// Semua menu transaksi (Pesanan, Voucher, Wishlist, Alamat, Poin, Ulasan)
/// SUDAH DIPINDAH ke halaman /transactions. Halaman ini fokus jadi
/// profile sosial.
// Brand accent — bright blue, kontras OK di light & dark, dipertahankan.
const _brandBlue = NataloColors.primary;
// Catatan dark mode: warna page bg / text TIDAK lagi const — di-resolve
// via Theme.of(context).colorScheme di tiap build supaya adaptif gelap.

class MemberScreen extends StatefulWidget {
  const MemberScreen({super.key});

  @override
  State<MemberScreen> createState() => _MemberScreenState();
}

class _MemberScreenState extends State<MemberScreen> {
  bool _redirectInProgress = false;

  @override
  void initState() {
    super.initState();
    memberStore.addListener(_evaluateRedirect);
    WidgetsBinding.instance.addPostFrameCallback((_) => _evaluateRedirect());
  }

  @override
  void dispose() {
    memberStore.removeListener(_evaluateRedirect);
    super.dispose();
  }

  void _evaluateRedirect() {
    if (_redirectInProgress || !mounted) return;
    if (memberStore.isLoggedIn) return;
    _redirectInProgress = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/member/login');
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: memberStore,
      builder: (context, _) {
        if (!memberStore.isLoggedIn) {
          return const _LoadingShell();
        }
        return const _ProfilePage();
      },
    );
  }
}

class _LoadingShell extends StatelessWidget {
  const _LoadingShell();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      // extendBody: konten tembus di belakang floating glass nav.
      extendBody: true,
      body: const Center(
        child: CircularProgressIndicator(color: _brandBlue, strokeWidth: 2.4),
      ),
      bottomNavigationBar: const BottomNavBar(currentIndex: 4),
    );
  }
}

// ─── Main profile page ─────────────────────────────────────────────

class _ProfilePage extends StatefulWidget {
  const _ProfilePage();

  @override
  State<_ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<_ProfilePage>
    with SingleTickerProviderStateMixin {
  bool _openingPost = false;
  bool _openingCreatePost = false;
  late TabController _tabController;
  List<FeedPost> _allPosts = const [];
  String? _postsNextCursor;
  bool _loadingPosts = true;
  String? _postsError;
  String? _preparedPostId;
  PostVideoWarmHandoff? _preparedHandoff;
  final _tileKeys = <String, GlobalKey>{};
  final GlobalKey _createPostOriginKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    unawaited(_preparedHandoff?.disposeIfUnclaimed());
    _tabController.dispose();
    super.dispose();
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

  void _preparePostVideo(FeedPost post) {
    if (_openingPost || !post.isVideo || _preparedPostId == post.id) return;
    final stale = _preparedHandoff;
    _preparedHandoff = _createWarmHandoff(post);
    _preparedPostId = _preparedHandoff == null ? null : post.id;
    unawaited(stale?.disposeIfUnclaimed());
  }

  void _cancelPreparedPost([String? postId]) {
    if (postId != null && _preparedPostId != postId) return;
    final stale = _preparedHandoff;
    _preparedHandoff = null;
    _preparedPostId = null;
    unawaited(stale?.disposeIfUnclaimed());
  }

  PostVideoWarmHandoff? _takePreparedPost(FeedPost post) {
    if (_preparedPostId != post.id) {
      _cancelPreparedPost();
      return null;
    }
    final handoff = _preparedHandoff;
    _preparedHandoff = null;
    _preparedPostId = null;
    return handoff;
  }

  Future<void> _loadAll() async {
    if (!memberStore.isLoggedIn) return;
    setState(() {
      _loadingPosts = true;
      _postsError = null;
    });
    final fetchedAt = DateTime.now();
    try {
      // fetchMyPosts return FeedPostPage (cursor-paginated). Untuk header
      // summary di Akun (stat post count), kita pakai page pertama saja —
      // tidak perlu fetch all pages. Stats Pengikut/Mengikuti diambil dari
      // memberStore.profile (di-hydrate dari /api/auth/me), bukan di sini.
      final page = await feedService.fetchMyPosts(filter: 'all');
      if (!mounted) return;
      // Seed FeedStore — cross-screen sync (Reels/Detail toggle ke-reflect
      // di Postingan Saya preview kalau di masa depan tile tampil count).
      feedStore.mergeFromServer(page.items, fetchedAt: fetchedAt);
      setState(() {
        _allPosts = page.items;
        _postsNextCursor = page.nextCursor;
        _loadingPosts = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.isUnauthorized || error.isForbidden) {
        await memberStore.logout();
        return;
      }
      setState(() {
        _loadingPosts = false;
        _postsError = error.isNetworkError
            ? 'Belum berhasil memuat. Tarik ke bawah untuk coba lagi.'
            : 'Postingan belum bisa dimuat. Tarik ke bawah untuk coba lagi.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingPosts = false;
        _postsError =
            'Postingan belum bisa dimuat. Tarik ke bawah untuk coba lagi.';
      });
    }
  }

  Future<void> _refresh() async {
    // Segarkan posts + profil (follower/following count di /api/auth/me)
    // paralel. hydrateFromApi notify listeners → AnimatedBuilder luar
    // rebuild dgn count terbaru.
    await Future.wait([_loadAll(), memberStore.hydrateFromApi()]);
  }

  Future<void> _openCreatePost() async {
    if (_openingCreatePost) return;
    setState(() => _openingCreatePost = true);
    try {
      final uploaded = await FeedMediaPickerScreen.openFromOrigin(
        context,
        _createPostOriginKey,
      );
      if (uploaded == true && mounted) {
        await _loadAll();
      }
    } finally {
      if (mounted) setState(() => _openingCreatePost = false);
    }
  }

  /// Buka halaman edit profil (nama, bio, foto, username). Refresh saat
  /// balik supaya perubahan langsung terlihat di header.
  Future<void> _openEditProfile() async {
    AppHaptics.tap();
    await Navigator.pushNamed(context, '/member/profile');
    if (mounted) await memberStore.hydrateFromApi();
  }

  /// Buka layar kartu QR profil ala IG (Desain C) — QR + Bagikan + Salin
  /// link. Share sheet native dipicu dari dalam layar tsb.
  Future<void> _shareProfile() async {
    final profile = memberStore.profile;
    if (profile == null) return;
    AppHaptics.tap();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfileQrScreen(
          displayName: profile.name,
          username: profile.username,
        ),
      ),
    );
  }

  /// Bangun PublicProfile dari MemberProfile (owner view) supaya reuse
  /// header + layar follow-list yang sama dengan profil publik — satu
  /// komponen visual untuk profil sendiri dan profil orang lain.
  PublicProfile _ownPublicProfile() {
    final profile = memberStore.profile;
    final isOfficial = profile?.isAdmin ?? false;
    return PublicProfile(
      id: profile?.id ?? '',
      name: isOfficial ? kOfficialBrandName : (profile?.name ?? ''),
      username: profile?.username,
      profilePhotoUrl: profile?.profilePhotoUrl,
      bio: profile?.bio,
      postCount: _allPosts.length,
      followersCount: profile?.followersCount ?? 0,
      followingCount: profile?.followingCount ?? 0,
      isOwner: true,
      isOfficial: isOfficial,
    );
  }

  Future<void> _openFollowList(FollowListKind kind) async {
    if (memberStore.profile == null) return;
    AppHaptics.tap();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PublicProfileFollowListScreen(
          profile: _ownPublicProfile(),
          initialKind: kind,
        ),
      ),
    );
    if (mounted) await memberStore.hydrateFromApi();
  }

  GlobalKey _tileKeyFor(String scope, String postId) =>
      _tileKeys.putIfAbsent('$scope:$postId', GlobalKey.new);

  Future<void> _openPostDetail(
    List<FeedPost> posts,
    int initialIndex,
    GlobalKey originKey,
  ) async {
    if (posts.isEmpty || _openingPost) return;
    _openingPost = true;
    AppHaptics.tap();
    final post = posts[initialIndex];
    final handoff = _takePreparedPost(post) ?? _createWarmHandoff(post);
    try {
      await pushOriginExpansion<void>(
        context,
        originKey: originKey,
        destinationBuilder: (_) => MemberPostDetailScreen(
          post: post,
          posts: posts,
          initialIndex: initialIndex,
          authorIsOfficial: memberStore.profile?.isAdmin ?? false,
          warmVideoHandoff: handoff,
          initialNextCursor: _postsNextCursor,
          loadMoreScopedPosts: (cursor) =>
              feedService.fetchMyPosts(filter: 'all', cursor: cursor),
        ),
      );
    } finally {
      await handoff?.disposeIfUnclaimed();
      _openingPost = false;
    }
    if (mounted) await _loadAll();
  }

  List<FeedPost> get _videoPosts => _allPosts.where((p) => p.isVideo).toList();

  List<FeedPost> get _taggedPosts =>
      _allPosts.where((p) => p.productIds.isNotEmpty).toList();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      // extendBody: konten tembus di belakang floating glass nav.
      extendBody: true,
      // Satu layout putih ala IG — sama dengan profil publik/orang lain.
      // Hero navy dibuang; status bar pakai ikon gelap di atas latar putih.
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: Theme.of(context).brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // Ikon header (+ / tersimpan / notifikasi / pengaturan) — TIDAK
              // diubah bentuk/urutan/logikanya, hanya direcolor gelap +
              // username ditambahkan di tengah (ala IG own-profile).
              _ProfileTopBar(
                onCreatePost: _openingCreatePost ? null : _openCreatePost,
                createPostOriginKey: _createPostOriginKey,
                username: _ownPublicProfile().displayHandle,
              ),
              Expanded(
                child: NataloPawRefreshIndicator(
                  onRefresh: _refresh,
                  triggerOffset: 96,
                  requireFullPull: true,
                  translateChild: false,
                  minimalIndicator: true,
                  includeSafeAreaPadding: false,
                  indicatorColor: _brandBlue,
                  refreshBackdropColor: cs.surface,
                  child: NestedScrollView(
                    // Fling diredam ala IG — lihat CalmScrollPhysics.
                    physics: const CalmScrollPhysics(),
                    headerSliverBuilder: (context, innerScrolled) => [
                      // Header IG bersama — komponen sama dengan profil
                      // publik/orang lain (avatar kiri + stats horizontal +
                      // Edit Profil/Bagikan Profil).
                      SliverToBoxAdapter(
                        child: AnimatedBuilder(
                          animation: memberStore,
                          builder: (context, _) => PublicProfileExpandedHeader(
                            profile: _ownPublicProfile(),
                            followBusy: false,
                            chatEnabled: false,
                            onFollowersTap: () =>
                                _openFollowList(FollowListKind.followers),
                            onFollowingTap: () =>
                                _openFollowList(FollowListKind.following),
                            onEditProfile: _openEditProfile,
                            onShareProfile: _shareProfile,
                          ),
                        ),
                      ),
                      // Banner reminder pilih @username — di area putih di
                      // bawah header. Auto-hide kalau user sudah set / pernah
                      // snooze 7 hari.
                      const SliverToBoxAdapter(
                        child: UsernamePromptBanner(),
                      ),
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _AccountTabHeaderDelegate(
                          controller: _tabController,
                          onTap: (_) => AppHaptics.tap(),
                        ),
                      ),
                    ],
                        body: TabBarView(
                          controller: _tabController,
                          children: [
                            _PostGrid(
                              posts: _allPosts,
                              loading: _loadingPosts,
                              errorText: _postsError,
                              emptyText: 'Belum ada postingan',
                              emptySubtext:
                                  'Bagikan momen lucu hewan kesayanganmu di Feed Natalo.',
                              showCreateCta: true,
                              onCreateCta: _openCreatePost,
                              onRetry: _loadAll,
                              onTapPost: (idx) => _openPostDetail(
                                _allPosts,
                                idx,
                                _tileKeyFor('all', _allPosts[idx].id),
                              ),
                              originKeyForPost: (post) =>
                                  _tileKeyFor('all', post.id),
                              onTapDown: (idx) =>
                                  _preparePostVideo(_allPosts[idx]),
                              onTapCancel: (idx) =>
                                  _cancelPreparedPost(_allPosts[idx].id),
                            ),
                            _PostGrid(
                              posts: _videoPosts,
                              loading: _loadingPosts,
                              errorText: _postsError,
                              emptyText: 'Belum ada video',
                              emptySubtext:
                                  'Video yang kamu unggah akan muncul di sini.',
                              showCreateCta: false,
                              onCreateCta: _openCreatePost,
                              onRetry: _loadAll,
                              onTapPost: (idx) => _openPostDetail(
                                _videoPosts,
                                idx,
                                _tileKeyFor('video', _videoPosts[idx].id),
                              ),
                              originKeyForPost: (post) =>
                                  _tileKeyFor('video', post.id),
                              onTapDown: (idx) =>
                                  _preparePostVideo(_videoPosts[idx]),
                              onTapCancel: (idx) =>
                                  _cancelPreparedPost(_videoPosts[idx].id),
                            ),
                            _PostGrid(
                              posts: _taggedPosts,
                              loading: _loadingPosts,
                              errorText: _postsError,
                              emptyText: 'Belum ada postingan belanja',
                              emptySubtext:
                                  'Postingan yang terhubung ke produk Natalo akan muncul di sini.',
                              showCreateCta: false,
                              onCreateCta: _openCreatePost,
                              onRetry: _loadAll,
                              onTapPost: (idx) => _openPostDetail(
                                _taggedPosts,
                                idx,
                                _tileKeyFor('tagged', _taggedPosts[idx].id),
                              ),
                              originKeyForPost: (post) =>
                                  _tileKeyFor('tagged', post.id),
                              onTapDown: (idx) =>
                                  _preparePostVideo(_taggedPosts[idx]),
                              onTapCancel: (idx) =>
                                  _cancelPreparedPost(_taggedPosts[idx].id),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      bottomNavigationBar: const BottomNavBar(currentIndex: 4),
    );
  }
}


// ─── Header top bar (in-body, di atas hero biru) ───────────────────

/// Baris ikon header (+ / tersimpan / notifikasi / pengaturan) di atas
/// latar putih, + username di tengah (ala IG own-profile top bar).
///
/// PENTING: setiap ikon di sini — jumlah, urutan, bentuk, dan
/// `onPressed`-nya — TIDAK diubah dari versi hero-navy sebelumnya. Yang
/// berubah hanya warna (putih → gelap, mengikuti tema) dan penambahan
/// username di tengah lewat lapisan overlay terpisah (tidak mengganggu
/// Row/tap-target ikon yang sudah ada).
class _ProfileTopBar extends StatelessWidget {
  final VoidCallback? onCreatePost;
  final GlobalKey createPostOriginKey;
  final String? username;

  const _ProfileTopBar({
    required this.onCreatePost,
    required this.createPostOriginKey,
    this.username,
  });

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.onSurface;
    final hasUsername = username != null && username!.isNotEmpty;
    return SizedBox(
      height: kToolbarHeight,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            children: [
              const SizedBox(width: 4),
              // Plus icon kiri — buka create-post flow existing.
              RepaintBoundary(
                key: createPostOriginKey,
                child: IconButton(
                  key: const ValueKey('profile-create-post'),
                  onPressed: onCreatePost,
                  tooltip: 'Buat postingan',
                  style: IconButton.styleFrom(
                    minimumSize: const Size(52, 52),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: Icon(Icons.add_rounded, size: 36, color: ink),
                ),
              ),
              const Spacer(),
              // Trio kanan pakai AppHeaderIconButton bersama (minWidth 34)
              // supaya jaraknya seragam & konsisten dgn header lain — dulu
              // bookmark & settings pakai IconButton mentah (minSize 48)
              // sehingga terlihat lebih renggang dari lonceng di tengahnya.
              AppHeaderIconButton(
                onPressed: () =>
                    Navigator.pushNamed(context, '/member/saved'),
                tooltip: 'Postingan tersimpan',
                color: ink,
                child: const Icon(Icons.bookmark_border_rounded, size: 28),
              ),
              IconTheme(
                data: IconThemeData(color: ink, size: 28),
                child: AppNotificationButton(iconColor: ink),
              ),
              AppHeaderIconButton(
                onPressed: () =>
                    Navigator.pushNamed(context, '/account/settings'),
                tooltip: 'Pengaturan akun',
                color: ink,
                child: const Icon(Icons.settings_outlined, size: 28),
              ),
              const SizedBox(width: 8),
            ],
          ),
          if (hasUsername)
            IgnorePointer(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 72),
                child: Text(
                  username!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Content tab header (pinned, sistem sama dengan profil publik) ─

/// Bungkus [PublicProfileContentTabBar] jadi pinned sliver header untuk
/// tab Akun. `pillOpacity: 0` + `underlineOpacity: 1` menjaga tampilan
/// selalu "expanded": ikon saja + indikator pendek di bawah tab aktif,
/// TANPA garis full-width — persis sistem tab profil publik yang baru.
class _AccountTabHeaderDelegate extends SliverPersistentHeaderDelegate {
  final TabController controller;
  final ValueChanged<int>? onTap;

  const _AccountTabHeaderDelegate({
    required this.controller,
    this.onTap,
  });

  @override
  double get minExtent => PublicProfileContentTabBar.height;

  @override
  double get maxExtent => PublicProfileContentTabBar.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: PublicProfileContentTabBar(
        controller: controller,
        labelOpacity: 0,
        pillOpacity: 0,
        underlineOpacity: 1,
        onTap: onTap,
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _AccountTabHeaderDelegate oldDelegate) {
    return oldDelegate.controller != controller || oldDelegate.onTap != onTap;
  }
}

// ─── Post grid 3-kolom ────────────────────────────────────────────

class _PostGrid extends StatelessWidget {
  final List<FeedPost> posts;
  final bool loading;
  final String? errorText;
  final String emptyText;
  final String emptySubtext;
  final bool showCreateCta;
  final VoidCallback onCreateCta;
  final VoidCallback onRetry;
  final ValueChanged<int> onTapPost;
  final GlobalKey Function(FeedPost) originKeyForPost;
  final ValueChanged<int>? onTapDown;
  final ValueChanged<int>? onTapCancel;

  const _PostGrid({
    required this.posts,
    required this.loading,
    required this.errorText,
    required this.emptyText,
    required this.emptySubtext,
    required this.showCreateCta,
    required this.onCreateCta,
    required this.onRetry,
    required this.onTapPost,
    required this.originKeyForPost,
    this.onTapDown,
    this.onTapCancel,
  });

  @override
  Widget build(BuildContext context) {
    if (loading && posts.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(strokeWidth: 2.4, color: _brandBlue),
        ),
      );
    }
    if ((errorText ?? '').isNotEmpty && posts.isEmpty) {
      return _ErrorState(text: errorText!, onRetry: onRetry);
    }
    if (posts.isEmpty) {
      return _EmptyState(
        text: emptyText,
        subtext: emptySubtext,
        showCreateCta: showCreateCta,
        onCreateCta: onCreateCta,
      );
    }
    return MediaQuery.removePadding(
      context: context,
      removeTop: true,
      child: GridView.builder(
        // WAJIB sama dgn physics NestedScrollView outer (di parent) —
        // physics outer TIDAK otomatis diwariskan ke body (dok
        // NestedScrollView.physics: "the inner scroll view is not directly
        // configured"). Beda physics outer/inner bikin hand-off ballistic
        // pincang: scroll ke atas terasa "stuck" (outer diredam) lalu
        // "terdorong" (inner masih kecepatan penuh baru menyusul).
        physics: const CalmScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 100),
        gridDelegate: profileGridDelegate(),
        itemCount: posts.length,
        itemBuilder: (context, index) {
          return _PostThumbnail(
            post: posts[index],
            originKey: originKeyForPost(posts[index]),
            onTap: () => onTapPost(index),
            onTapDown: () => onTapDown?.call(index),
            onTapCancel: () => onTapCancel?.call(index),
          );
        },
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String text;
  final VoidCallback onRetry;

  const _ErrorState({required this.text, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 54, 32, 100),
        child: Column(
          children: [
            Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                // Soft-blue tint: di dark, tint terang nyala → pakai brand
                // blue alpha rendah supaya icon tetap kebaca.
                color: isDark
                    ? _brandBlue.withValues(alpha: 0.20)
                    : const Color(0xFFEAF5FF),
                borderRadius: BorderRadius.circular(26),
              ),
              child: const Icon(
                Icons.cloud_off_rounded,
                color: _brandBlue,
                size: 34,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 14,
                fontWeight: NataloWeight.body,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 18),
            OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                foregroundColor: _brandBlue,
                side: const BorderSide(color: _brandBlue),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Coba lagi',
                style: TextStyle(fontWeight: NataloWeight.strong),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PostThumbnail extends StatelessWidget {
  final FeedPost post;
  final GlobalKey originKey;
  final VoidCallback onTap;
  final VoidCallback? onTapDown;
  final VoidCallback? onTapCancel;

  const _PostThumbnail({
    required this.post,
    required this.originKey,
    required this.onTap,
    this.onTapDown,
    this.onTapCancel,
  });

  @override
  Widget build(BuildContext context) {
    final mediaUrl = (post.thumbnailUrl?.trim().isNotEmpty == true
            ? post.thumbnailUrl
            : null) ??
        (post.previewMediaUrl.trim().isNotEmpty ? post.previewMediaUrl : null);
    final cs = Theme.of(context).colorScheme;
    return RepaintBoundary(
      key: originKey,
      child: OriginSnapshotSource(
        child: InkWell(
          onTap: onTap,
          onTapDown: (_) => onTapDown?.call(),
          onTapCancel: onTapCancel,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Video LANDSCAPE → latar hitam (bar letterbox). Selain itu
              // latar netral biasa. gridShowsLetterbox: video landscape saja.
              Container(
                color: gridShowsLetterbox(post)
                    ? Colors.black
                    : cs.surfaceContainerHighest,
              ),
              if (mediaUrl != null)
                // Keep the tag for the detail screen's later fullscreen flow.
                // OriginSnapshotSource suppresses this grid-side Hero while the
                // static route snapshot performs the Profile -> Postingan morph.
                Hero(
                  tag: 'post-thumb-${post.id}',
                  child: CachedNetworkImage(
                    imageUrl: mediaUrl,
                    // Video landscape → contain (letterbox, utuh); sisanya
                    // cover-crop penuh (foto/carousel/portrait, tak berubah).
                    fit: gridShowsLetterbox(post)
                        ? BoxFit.contain
                        : BoxFit.cover,
                    fadeInDuration: const Duration(milliseconds: 180),
                    placeholder: (_, __) =>
                        Container(color: cs.surfaceContainerHigh),
                    errorWidget: (_, __, ___) => const Center(
                      child: Icon(
                        Icons.image_not_supported_outlined,
                        color: Color(0xFF94A3B8),
                        size: 28,
                      ),
                    ),
                  ),
                )
              else
                const Center(
                  child: Icon(
                    Icons.image_outlined,
                    color: Color(0xFF94A3B8),
                    size: 28,
                  ),
                ),
              // Type indicators top-right (video play OR shopping bag).
              // Priority: video > tagged products (kalau dua-duanya, video win).
              if (post.isVideo)
                const Positioned(
                  top: 8,
                  right: 8,
                  child: _ThumbnailIcon(icon: Icons.play_arrow_rounded),
                )
              else if (post.productIds.isNotEmpty)
                const Positioned(
                  top: 8,
                  right: 8,
                  child: _ThumbnailIcon(icon: Icons.shopping_bag_outlined),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThumbnailIcon extends StatelessWidget {
  final IconData icon;

  const _ThumbnailIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.50),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 14, color: Colors.white),
    );
  }
}

// ─── Empty states ─────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String text;
  final String subtext;
  final bool showCreateCta;
  final VoidCallback onCreateCta;

  const _EmptyState({
    required this.text,
    required this.subtext,
    required this.showCreateCta,
    required this.onCreateCta,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 54, 32, 100),
        child: Column(
          children: [
            SizedBox(
              width: 96,
              height: 90,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 82,
                    height: 82,
                    decoration: BoxDecoration(
                      color: isDark
                          ? _brandBlue.withValues(alpha: 0.20)
                          : const Color(0xFFEAF5FF),
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: const Icon(
                      Icons.pets_rounded,
                      color: _brandBlue,
                      size: 36,
                    ),
                  ),
                  Positioned(
                    right: 6,
                    bottom: 4,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: _brandBlue,
                        shape: BoxShape.circle,
                        // Ring "cutout" — match page bg supaya badge nampak
                        // floating; di dark ikut surface gelap.
                        border: Border.all(color: cs.surface, width: 3),
                      ),
                      child: const Icon(
                        Icons.photo_camera_outlined,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 16.5,
                fontWeight: NataloWeight.strong,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtext,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 13.5,
                fontWeight: NataloWeight.body,
                height: 1.4,
              ),
            ),
            if (showCreateCta) ...[
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: onCreateCta,
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text(
                  'Buat Postingan',
                  style: TextStyle(fontWeight: NataloWeight.strong),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _brandBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

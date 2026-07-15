import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/natalo_colors.dart';

import '../models/feed_post.dart';
import '../features/feed/video/post_video_warm_handoff.dart';
import '../models/public_profile.dart';
import '../services/api_client.dart';
import '../services/feed_service.dart';
import '../services/video_quality_service.dart';
import '../state/feed_store.dart';
import '../state/member_store.dart';
import '../state/settings_store.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import '../widgets/app_notification_button.dart';
import '../widgets/bottom_nav.dart';
import 'feed_media_picker_screen.dart';
import '../widgets/natalo_paw_refresh_indicator.dart';
import '../widgets/origin_expansion_route.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/profile_content_tab_bar.dart';
import '../widgets/update_profile_photo_sheet.dart';
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
    AppHaptics.tap();
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

  /// Buka daftar Pengikut / Mengikuti. Bangun PublicProfile dari
  /// MemberProfile (owner view) supaya reuse layar follow-list yang sama
  /// dgn profil publik.
  Future<void> _openFollowList(FollowListKind kind) async {
    final profile = memberStore.profile;
    if (profile == null) return;
    AppHaptics.tap();
    final pub = PublicProfile(
      id: profile.id,
      name: profile.name,
      username: profile.username,
      profilePhotoUrl: profile.profilePhotoUrl,
      bio: profile.bio,
      postCount: _allPosts.length,
      followersCount: profile.followersCount,
      followingCount: profile.followingCount,
      isOwner: true,
    );
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PublicProfileFollowListScreen(profile: pub, initialKind: kind),
      ),
    );
    if (mounted) await memberStore.hydrateFromApi();
  }

  void _openProfilePhotoSheet() {
    AppHaptics.tap();
    showUpdateProfilePhotoSheet(context);
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
    final profile = memberStore.profile!;
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      // extendBody: konten tembus di belakang floating glass nav.
      extendBody: true,
      // Status bar biru + ikon header IN-BODY — pola hero biru seragam
      // dengan Beranda/Belanja/Transaksi/Notifikasi. Sebelumnya Akun
      // sendirian pakai Scaffold.appBar + flexibleSpace yang menyisakan
      // status bar PUTIH (celah putih di atas hero). AnnotatedRegion +
      // strip heroTop di belakang status bar menjamin area notch ikut biru
      // dan ikon status bar putih — sama persis mekanisme 4 halaman lain.
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Stack(
          children: [
            // Satu kotak gradasi VERTIKAL menutup status bar + baris ikon
            // sebagai satu sapuan heroTop→heroMid. Dulu: strip flat heroTop +
            // _ProfileTopBar bergradien sendiri (diagonal) — di kotak 56px yang
            // lebar-pendek, diagonal jadi ~horizontal sehingga arah gradasi
            // patah di batas ke blok profil = seam "biru tidak menyatu".
            // _ProfileTopBar sekarang transparan; gradasi tunggal ini yang
            // tembus di belakangnya.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: MediaQuery.paddingOf(context).top + kToolbarHeight,
              child: const DecoratedBox(
                decoration: BoxDecoration(gradient: NataloColors.heroGradientV),
              ),
            ),
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  // Ikon header (+ / notifikasi / pengaturan) — dulu di
                  // Scaffold.appBar, kini in-body supaya gradasi mengalir
                  // mulus status bar → ikon → blok profil (satu hero).
                  _ProfileTopBar(
                    onCreatePost:
                        _openingCreatePost ? null : _openCreatePost,
                    createPostOriginKey: _createPostOriginKey,
                  ),
                  Expanded(
                    child: NataloPawRefreshIndicator(
                      onRefresh: _refresh,
                      triggerOffset: 96,
                      requireFullPull: true,
                      translateChild: false,
                      minimalIndicator: true,
                      includeSafeAreaPadding: false,
                      indicatorColor: Colors.white,
                      refreshBackdropColor: NataloColors.heroTop,
                      child: NestedScrollView(
                        headerSliverBuilder: (context, innerScrolled) => [
                          // Blok profil = hero biru (avatar + statistik + nama di atas
                          // gradasi). Meneruskan gradasi app bar → satu hero.
                          SliverToBoxAdapter(
                            child: _ProfileSection(
                              profile: profile,
                              postsCount: _allPosts.length,
                              onAvatarTap: _openProfilePhotoSheet,
                              onEditProfile: _openEditProfile,
                              onShareProfile: _shareProfile,
                              onFollowersTap: () =>
                                  _openFollowList(FollowListKind.followers),
                              onFollowingTap: () =>
                                  _openFollowList(FollowListKind.following),
                            ),
                          ),
                          // Banner reminder pilih @username — dipindah ke bawah hero
                          // (area putih) supaya tidak memotong blok biru. Auto-hide kalau
                          // user sudah set / pernah snooze 7 hari.
                          const SliverToBoxAdapter(
                            child: UsernamePromptBanner(),
                          ),
                          SliverPersistentHeader(
                            pinned: true,
                            delegate: ProfileContentTabHeaderDelegate(
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
          ],
        ),
      ),
      bottomNavigationBar: const BottomNavBar(currentIndex: 4),
    );
  }
}

// ─── Header top bar (in-body, di atas hero biru) ───────────────────

/// Baris ikon header (+ / notifikasi / pengaturan) di atas hero biru.
///
/// Dulu `_ProfileAppBar` (Scaffold.appBar + flexibleSpace). Diganti widget
/// IN-BODY supaya gradasi hero mengalir mulus dari strip status bar → baris
/// ikon → blok profil, seragam dengan Beranda/Belanja/Transaksi/Notifikasi.
/// Mekanisme appBar+flexibleSpace lama menyisakan status bar putih (celah
/// putih di atas hero). Ikon putih di atas gradasi biru.
class _ProfileTopBar extends StatelessWidget {
  final VoidCallback? onCreatePost;
  final GlobalKey createPostOriginKey;

  const _ProfileTopBar({
    required this.onCreatePost,
    required this.createPostOriginKey,
  });

  @override
  Widget build(BuildContext context) {
    const ink = Colors.white;
    // Latar TRANSPARAN — gradasi hero dicat oleh kotak vertikal tunggal di
    // belakang (lihat _ProfilePageState.build). Sebelumnya baris ini punya
    // DecoratedBox(heroGradient) sendiri; di kotak 56px yang lebar-pendek,
    // diagonal jadi ~horizontal → seam dengan blok profil. Kini satu sapuan.
    return SizedBox(
      height: kToolbarHeight,
      child: Row(
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
              icon: const Icon(Icons.add_rounded, size: 36, color: ink),
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () => Navigator.pushNamed(context, '/member/saved'),
            tooltip: 'Postingan tersimpan',
            style: IconButton.styleFrom(
              minimumSize: const Size(48, 48),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(
              Icons.bookmark_border_rounded,
              color: ink,
              size: 28,
            ),
          ),
          const IconTheme(
            data: IconThemeData(color: ink, size: 28),
            child: AppNotificationButton(iconColor: ink),
          ),
          IconButton(
            onPressed: () => Navigator.pushNamed(context, '/account/settings'),
            tooltip: 'Pengaturan akun',
            style: IconButton.styleFrom(
              minimumSize: const Size(48, 48),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.settings_outlined, color: ink, size: 28),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

// ─── Profile section (photo + name + stats) ───────────────────────

class _ProfileSection extends StatelessWidget {
  final dynamic profile; // MemberProfile — keep dynamic supaya tidak import.
  final int postsCount;
  final VoidCallback onAvatarTap;
  final VoidCallback onEditProfile;
  final VoidCallback onShareProfile;
  final VoidCallback onFollowersTap;
  final VoidCallback onFollowingTap;

  const _ProfileSection({
    required this.profile,
    required this.postsCount,
    required this.onAvatarTap,
    required this.onEditProfile,
    required this.onShareProfile,
    required this.onFollowersTap,
    required this.onFollowingTap,
  });

  @override
  Widget build(BuildContext context) {
    const ink = Colors.white;
    final username = profile.username as String?;
    final hasUsername = username != null && username.isNotEmpty;
    // Blok profil meneruskan sapuan hero VERTIKAL (heroMid→heroBottom) dari
    // kotak status+ikon di atasnya. Batas atas = heroMid identik dengan batas
    // bawah heroGradientV → menyatu tanpa seam. Sudut bawah membulat sebagai
    // penutup hero sebelum area tab/grid putih.
    return Container(
      decoration: const BoxDecoration(
        gradient: NataloColors.heroGradientVContinue,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Baris atas: avatar + stats sejajar (IG-modern).
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ProfileAvatar(
                initial: profile.initial as String? ?? '?',
                imageUrl: profile.profilePhotoUrl as String?,
                size: 80,
                fontSize: 30,
                isOfficial: profile.isAdmin == true,
                showCameraBadge: profile.isAdmin != true,
                onTap: onAvatarTap,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _ProfileStat(
                        value: postsCount,
                        label: 'Postingan',
                      ),
                    ),
                    Expanded(
                      child: _ProfileStat(
                        value: profile.followersCount as int,
                        label: 'Pengikut',
                        onTap: onFollowersTap,
                      ),
                    ),
                    Expanded(
                      child: _ProfileStat(
                        value: profile.followingCount as int,
                        label: 'Mengikuti',
                        onTap: onFollowingTap,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Nama + @username (IG-style, full-width di bawah row).
          Text(
            (profile.name as String?) ?? 'Member Natalo',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: ink,
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
              height: 1.15,
            ),
          ),
          if (hasUsername) ...[
            const SizedBox(height: 2),
            Text(
              '@$username',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: NataloColors.onHeroSubtle,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.1,
              ),
            ),
          ],
          // Bio (kalau ada) — auto-hide kalau null/empty.
          if ((profile.bio as String?)?.trim().isNotEmpty ?? false) ...[
            const SizedBox(height: 8),
            Text(
              profile.bio as String,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: ink,
                fontSize: 14,
                fontWeight: FontWeight.w400,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 14),
          // Tombol Edit Profil + Bagikan (dua tombol setara ala IG).
          Row(
            children: [
              Expanded(
                child: _ProfileActionButton(
                  label: 'Edit Profil',
                  onTap: onEditProfile,
                  primary: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ProfileActionButton(
                  label: 'Bagikan Profil',
                  onTap: onShareProfile,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  /// true = tombol utama (Edit Profil): putih solid, teks navy. false =
  /// sekunder (Bagikan): transparan dengan border putih. Keduanya di atas
  /// hero biru.
  final bool primary;

  const _ProfileActionButton({
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(fontSize: 13, fontWeight: FontWeight.w800);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    );
    return SizedBox(
      height: 34,
      child: primary
          ? FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: NataloColors.heroMid,
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: textStyle,
                shape: shape,
              ),
              child: Text(label),
            )
          : OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.55)),
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: textStyle,
                shape: shape,
              ),
              child: Text(label),
            ),
    );
  }
}

class _ProfileStat extends StatelessWidget {
  final int value;
  final String label;
  final VoidCallback? onTap;

  const _ProfileStat({required this.value, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    // Di atas hero biru: angka putih, label biru muda (onHeroSubtle).
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          formatCountCompact(value),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w800,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: NataloColors.onHeroSubtle,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            height: 1.05,
          ),
        ),
      ],
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
        padding: const EdgeInsets.only(bottom: 100),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
          childAspectRatio: 1,
        ),
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
                fontWeight: FontWeight.w500,
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
                style: TextStyle(fontWeight: FontWeight.w600),
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
      child: InkWell(
        onTap: onTap,
        onTapDown: (_) => onTapDown?.call(),
        onTapCancel: onTapCancel,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: cs.surfaceContainerHighest),
            if (mediaUrl != null)
              // Hero animation source — wraps thumbnail dengan tag unik
              // per-post. Detail screen wrap image dengan tag yang sama
              // di _PostMediaSurface → Flutter auto-fly + scale image saat
              // navigate. Skip untuk video (VideoPlayer destination tidak
              // compatible dengan Hero — animasi snap kalau mismatch).
              Hero(
                tag: 'post-thumb-${post.id}',
                child: CachedNetworkImage(
                  imageUrl: mediaUrl,
                  fit: BoxFit.cover,
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
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtext,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
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
                  style: TextStyle(fontWeight: FontWeight.w700),
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

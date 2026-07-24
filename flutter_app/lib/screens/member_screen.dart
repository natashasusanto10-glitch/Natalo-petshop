import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shimmer/shimmer.dart';
import '../theme/natalo_colors.dart';
import '../theme/natalo_text.dart';

import '../constants/official_brand.dart';
import '../models/feed_post.dart';
import '../features/feed/transition/post_hero.dart';
import '../features/feed/transition/post_viewer_route.dart';
import '../features/feed/transition/profile_tile_visibility.dart';
import '../features/feed/video/post_video_warm_handoff.dart';
import '../features/feed/video/video_media_cache.dart';
import '../features/feed/widgets/gallery_post_tile.dart'
    show gridThumbnailFit, gridVideoUsesBlackBackground;
import '../models/public_profile.dart';
import '../services/api_client.dart';
import '../services/feed_service.dart';
import '../services/profile_service.dart';
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
import '../widgets/profile_grid_geometry.dart';
import '../widgets/public_profile_content_tab_bar.dart';
import '../widgets/public_profile_expanded_header.dart';
import '../widgets/username_prompt_banner.dart';
import 'member_post_detail_screen.dart';
import 'profile_qr_screen.dart';
import 'public_profile_follow_list_screen.dart';

/// Test-only seam — bypasses the real network call in `_loadAll` so widget
/// tests can seed `MemberScreen`'s own-posts grid deterministically. Null in
/// production; must be reset to null in `tearDown`.
@visibleForTesting
Future<FeedPage> Function({String filter, String? cursor})? debugMyPostsFetcher;

/// Test-only seam — bypasses the real network call in `_loadTaggedPosts` so
/// widget tests can seed tab "Ditandai" deterministically (Spec B). Null in
/// production; must be reset to null in `tearDown`.
@visibleForTesting
Future<PublicProfileResult> Function(String username)? debugTaggedPostsFetcher;

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

  // Tab "Ditandai" (Spec B) — post orang lain yang menandai user ini. Fetch
  // TERPISAH dari _allPosts (bukan derived getter seperti _videoPosts) lewat
  // endpoint profil publik milik sendiri (content=tagged); hidden sudah
  // di-exclude server-side (Task 4).
  List<FeedPost> _taggedPostsData = const [];
  bool _taggedLoaded = false;
  bool _taggedLoading = false;

  /// Total postingan publik untuk stat "Postingan" ala IG — diambil dari
  /// endpoint profil publik (hitungan server-side, semua halaman), bukan
  /// cuma page pertama yang sudah dimuat ke grid. null = belum terisi →
  /// fallback ke _allPosts.length. Pola sama dengan member_posts_screen.
  int? _postCount;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this)
      ..addListener(_onTabControllerChanged);
    _loadAll();
    _loadPostCount();
  }

  Future<void> _loadPostCount() async {
    final username = memberStore.profile?.username;
    if (username == null || username.isEmpty) return;
    try {
      final result = await profileService.fetchPublicProfile(
        username: username,
        limit: 1,
      );
      if (!mounted) return;
      setState(() => _postCount = result.profile.postCount);
    } catch (_) {
      // Best-effort — fallback ke jumlah post termuat.
    }
  }

  @override
  void dispose() {
    unawaited(_preparedHandoff?.disposeIfUnclaimed());
    _tabController
      ..removeListener(_onTabControllerChanged)
      ..dispose();
    super.dispose();
  }

  /// Tap langsung tab (respon instan, tak menunggu animasi tab settle).
  void _onAccountTabTapped(int index) => _maybeLoadTaggedPosts(index);

  /// Swipe TabBarView (setelah animasi settle di index integer) — mirror
  /// pola `_PublicProfileScreenState._onTabControllerChanged`.
  void _onTabControllerChanged() {
    if (_tabController.indexIsChanging) return;
    final position = _tabController.animation?.value;
    if (position != null && (position - _tabController.index).abs() > 0.001) {
      return;
    }
    _maybeLoadTaggedPosts(_tabController.index);
  }

  void _maybeLoadTaggedPosts(int tabIndex) {
    if (tabIndex == 2 && !_taggedLoaded && !_taggedLoading) {
      unawaited(_loadTaggedPosts());
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
      final fetcher = debugMyPostsFetcher ?? feedService.fetchMyPosts;
      final page = await fetcher(filter: 'all');
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

  /// Fetch tab "Ditandai" — endpoint profil publik milik SENDIRI
  /// (`content=tagged`, Task 4), sumber username sama dengan yang
  /// ditampilkan header (`memberStore.profile?.username` — dipakai juga
  /// oleh `_ProfileTopBar`/`_ownPublicProfile().displayHandle`). User yang
  /// belum set username (nullable, lihat `MemberProfile.username`) tidak
  /// bisa di-fetch lewat rute ini — tab tetap kosong (aman, bukan error).
  Future<void> _loadTaggedPosts() async {
    final username = memberStore.profile?.username;
    if (username == null || username.isEmpty) return;
    if (_taggedLoading) return;
    _taggedLoading = true;
    try {
      final fetcher = debugTaggedPostsFetcher ??
          (String u) => profileService.fetchPublicProfile(
                username: u,
                content: PublicProfileContentFilter.shoppable,
              );
      final result = await fetcher(username);
      if (!mounted) return;
      setState(() {
        _taggedPostsData = result.posts;
        _taggedLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _taggedLoaded = true);
    } finally {
      _taggedLoading = false;
    }
  }

  Future<void> _refresh() async {
    // Segarkan posts + profil (follower/following count di /api/auth/me) +
    // tab Ditandai + total postingan server, paralel. hydrateFromApi notify
    // listeners → AnimatedBuilder luar rebuild dgn count terbaru. Ditandai
    // ikut di-refresh TANPA syarat (sama seperti _loadAll untuk "all"/
    // "video") supaya "Hapus saya"/"Sembunyikan" (Task 12) yang terjadi di
    // layar lain langsung terlihat begitu user menarik-refresh, tanpa perlu
    // store sinkronisasi baru.
    await Future.wait([
      _loadAll(),
      memberStore.hydrateFromApi(),
      _loadTaggedPosts(),
      _loadPostCount(),
    ]);
  }

  Future<void> _openCreatePost() async {
    if (_openingCreatePost) return;
    setState(() => _openingCreatePost = true);
    try {
      final uploaded = await FeedMediaPickerScreen.open(context);
      if (uploaded == true && mounted) {
        await _loadAll();
      }
    } finally {
      if (mounted) setState(() => _openingCreatePost = false);
    }
  }

  /// Buka "Anabulku" (Pets Profile) — tombol utama header profil sendiri.
  /// Edit profil (nama/bio/foto/username) tetap dapat diakses lewat ikon
  /// gear -> Pengaturan Akun -> Ubah Profil, jadi tidak dobel dengan
  /// tombol ini.
  Future<void> _openPetsProfile() async {
    AppHaptics.tap();
    await Navigator.pushNamed(context, '/member/pets');
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
      postCount: _postCount ?? _allPosts.length,
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

  /// Tab scope ('all'/'video'/'tagged') dipakai baik untuk `_tileKeys`
  /// MAUPUN sebagai bagian PostHero scope ('profile-<tabScope>'). WAJIB
  /// per-tab, bukan satu 'profile' bersama: `TabBarView` membangun tab
  /// tetangga saat swipe (allowImplicitScrolling), jadi post yang sama
  /// bisa muncul di dua tab grid sekaligus (mis. video ada di 'all' dan
  /// 'video') — tag hero duplikat di tree yang sama membuat Flutter
  /// menonaktifkan hero itu diam-diam.
  String _heroScopeFor(String tabScope) => 'profile-$tabScope';

  Future<void> _openPostDetail(
    List<FeedPost> posts,
    int initialIndex,
    String tabScope,
  ) async {
    if (posts.isEmpty || _openingPost) return;
    _openingPost = true;
    AppHaptics.tap();
    final post = posts[initialIndex];
    final handoff = _takePreparedPost(post) ?? _createWarmHandoff(post);
    // Tab "Ditandai" berisi postingan milik ORANG LAIN yang menandai user
    // ini (author asli != pemilik profil). WAJIB render identitas per-post
    // (`authorPerPost`) + BUKAN owner-view, kalau tidak header viewer akan
    // menimpa author asli dengan nama/foto pemilik profil (bug: post Leonardi
    // tampil seakan dibuat Natalo). Tab 'all'/'video' tetap owner-view lama.
    final isTagged = tabScope == 'tagged';
    try {
      await pushPostViewer<void>(
        context,
        builder: (_) => MemberPostDetailScreen(
          post: post,
          posts: posts,
          initialIndex: initialIndex,
          isOwner: !isTagged,
          authorPerPost: isTagged,
          authorIsOfficial: isTagged
              ? false
              : (memberStore.profile?.isAdmin ?? false),
          warmVideoHandoff: handoff,
          initialNextCursor: isTagged ? null : _postsNextCursor,
          loadMoreScopedPosts: isTagged
              ? null
              : (cursor) =>
                  feedService.fetchMyPosts(filter: 'all', cursor: cursor),
          heroScope: _heroScopeFor(tabScope),
          onWillClose: (activePostId) => _revealTile(tabScope, activePostId),
        ),
      );
    } finally {
      await handoff?.disposeIfUnclaimed();
      _openingPost = false;
    }
    if (mounted) {
      await _loadAll();
      // Sinkron "Hapus saya"/"Sembunyikan" (Task 12): kalau viewer yang baru
      // ditutup sempat mengubah tag diri sendiri, tab Ditandai harus
      // reflect itu. Tidak ada store sinkronisasi baru — cukup tandai stale
      // (refetch lazy saat tab dibuka lagi) + langsung refetch kalau user
      // KEBETULAN sedang berada di tab itu sekarang.
      _taggedLoaded = false;
      _maybeLoadTaggedPosts(_tabController.index);
    }
  }

  /// Dipanggil sinkron saat viewer pop, dengan id post yang sedang tampil.
  /// Fire-and-forget — TIDAK menunggu animasi/scroll selesai.
  void _revealTile(String tabScope, String activePostId) {
    final key = _tileKeyFor(tabScope, activePostId);
    final ctx = key.currentContext;
    if (ctx != null) {
      final bottomPadding =
          kFloatingNavClearance + MediaQuery.of(context).padding.bottom;
      ensureProfileTileVisible(ctx, bottomPadding: bottomPadding);
      return;
    }
    // Tile belum dibangun (di luar viewport jauh) — estimasi posisi baris
    // via index di list scope ini, lalu jumpTo langsung tanpa animasi.
    final posts = switch (tabScope) {
      'video' => _videoPosts,
      'tagged' => _taggedPosts,
      _ => _allPosts,
    };
    final index = posts.indexWhere((p) => p.id == activePostId);
    if (index < 0) return;
    // Cari Scrollable manapun yang masih hidup lewat tile lain di scope
    // yang sama, supaya kita tetap mendapat ScrollPosition grid yang benar
    // tanpa bergantung pada context State ini sendiri (yang berada di ATAS
    // NestedScrollView di tree, bukan di dalamnya).
    BuildContext? anyTileCtx;
    for (final entry in _tileKeys.entries) {
      if (!entry.key.startsWith('$tabScope:')) continue;
      final c = entry.value.currentContext;
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

  List<FeedPost> get _videoPosts => _allPosts.where((p) => p.isVideo).toList();

  // Tab "Ditandai" (Spec B) — post orang lain yang menandai user ini, dari
  // `_loadTaggedPosts` (bukan derived dari `_allPosts` seperti `_videoPosts`,
  // karena sumbernya endpoint terpisah — profil publik milik sendiri dengan
  // `content=tagged`).
  List<FeedPost> get _taggedPosts => _taggedPostsData;

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
                            onEditProfile: _openPetsProfile,
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
                          // Haptic ganti-tab sengaja dimatikan (permintaan
                          // user) — pindah tab profil harus terasa halus,
                          // tanpa getar. AppHaptics.tap tetap dipakai di
                          // aksi lain (buka post, edit profil, dll).
                          // onTap tetap dipakai (bukan haptic) untuk memicu
                          // _loadTaggedPosts() secepat mungkin saat tab
                          // Ditandai di-tap langsung — tak perlu menunggu
                          // animasi swipe settle (_onTabControllerChanged).
                          onTap: _onAccountTabTapped,
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
                          onTapPost: (idx) =>
                              _openPostDetail(_allPosts, idx, 'all'),
                          heroScope: _heroScopeFor('all'),
                          originKeyForPost: (post) =>
                              _tileKeyFor('all', post.id),
                          onTapDown: (idx) => _preparePostVideo(_allPosts[idx]),
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
                          onTapPost: (idx) =>
                              _openPostDetail(_videoPosts, idx, 'video'),
                          heroScope: _heroScopeFor('video'),
                          originKeyForPost: (post) =>
                              _tileKeyFor('video', post.id),
                          onTapDown: (idx) =>
                              _preparePostVideo(_videoPosts[idx]),
                          onTapCancel: (idx) =>
                              _cancelPreparedPost(_videoPosts[idx].id),
                        ),
                        _PostGrid(
                          posts: _taggedPosts,
                          // Loading state SENDIRI (bukan _loadingPosts, yang
                          // hanya milik _loadAll/_allPosts) — true sampai
                          // fetch pertama tab ini selesai (sukses ATAU
                          // gagal; lihat _loadTaggedPosts).
                          loading: !_taggedLoaded,
                          errorText: null,
                          emptyText: 'Belum ada postingan yang menandaimu',
                          emptySubtext:
                              'Saat orang lain menandaimu di sebuah postingan, itu akan muncul di sini.',
                          showCreateCta: false,
                          onCreateCta: _openCreatePost,
                          onRetry: _loadTaggedPosts,
                          onTapPost: (idx) =>
                              _openPostDetail(_taggedPosts, idx, 'tagged'),
                          heroScope: _heroScopeFor('tagged'),
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
  final String? username;

  const _ProfileTopBar({
    required this.onCreatePost,
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
                child: IconButton(
                  key: const ValueKey('profile-create-post'),
                  onPressed: onCreatePost,
                  tooltip: 'Buat postingan',
                  style: IconButton.styleFrom(
                    minimumSize: const Size(52, 52),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    overlayColor: Colors.transparent,
                    splashFactory: NoSplash.splashFactory,
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
                onPressed: () => Navigator.pushNamed(context, '/member/saved'),
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
  final String heroScope;
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
    required this.heroScope,
    required this.originKeyForPost,
    this.onTapDown,
    this.onTapCancel,
  });

  @override
  Widget build(BuildContext context) {
    if (loading && posts.isEmpty) {
      return const _PostGridSkeleton();
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
            heroScope: heroScope,
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

/// Skeleton grid ala IG saat postingan pertama kali dimuat — menggantikan
/// spinner tunggal supaya bentuk grid 3-kolom sudah terasa sebelum data
/// nyata datang (konsisten dgn shimmer skeleton di Feed).
class _PostGridSkeleton extends StatelessWidget {
  const _PostGridSkeleton();

  static const int _tileCount = 12;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white12 : const Color(0xFFE9ECEF);
    final highlightColor = isDark ? Colors.white24 : const Color(0xFFF6F7F9);
    return MediaQuery.removePadding(
      context: context,
      removeTop: true,
      child: Shimmer.fromColors(
        baseColor: baseColor,
        highlightColor: highlightColor,
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 100),
          gridDelegate: profileGridDelegate(),
          itemCount: _tileCount,
          itemBuilder: (context, index) => ColoredBox(color: baseColor),
        ),
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
                    : NataloColors.primarySoft,
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
  final String heroScope;
  final GlobalKey originKey;
  final VoidCallback onTap;
  final VoidCallback? onTapDown;
  final VoidCallback? onTapCancel;

  const _PostThumbnail({
    required this.post,
    required this.heroScope,
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
    // originKey masih dipertahankan (RepaintBoundary) — bukan lagi untuk
    // OriginSnapshotSource/pushOriginExpansion (dihapus), tapi sebagai
    // penanda tile yang dipakai `_revealTile` untuk mencari BuildContext
    // + Scrollable saat viewer ditutup.
    return RepaintBoundary(
      key: originKey,
      child: InkWell(
        onTap: onTap,
        onTapDown: (_) => onTapDown?.call(),
        onTapCancel: onTapCancel,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Video → latar hitam (mengisi bar letterbox landscape/persegi;
            // tak terlihat saat portrait memenuhi tile). Foto → latar netral.
            Container(
              color: gridVideoUsesBlackBackground(post)
                  ? Colors.black
                  : cs.surfaceContainerHighest,
            ),
            if (mediaUrl != null)
              PostHero(
                scope: heroScope,
                postId: post.id,
                child: CachedNetworkImage(
                  imageUrl: mediaUrl,
                  // cacheKey STABIL (strip token/expires signed URL) — thumbnail
                  // video Bunny bawa signed-token yang berubah tiap refetch.
                  // Tanpa ini, `_loadAll()` pasca-tutup viewer mengganti URL
                  // (token baru) → CachedNetworkImage reload → baris tile video
                  // KEDIP ABU-ABU (gejala device: glitch back di Profil sendiri;
                  // foto URL stabil jadi tak kena). Sama seperti videoMediaCacheKey
                  // dipakai player video.
                  cacheKey: videoMediaCacheKey(mediaId: post.id, url: mediaUrl),
                  // cacheKey STABIL (strip token/expires signed URL) — thumbnail
                  // video Bunny bawa signed-token yang berubah tiap refetch.
                  // Tanpa ini, `_loadAll()` pasca-tutup viewer mengganti URL
                  // (token baru) → CachedNetworkImage reload → baris tile video
                  // KEDIP ABU-ABU (gejala device: glitch back di Profil sendiri;
                  // foto URL stabil jadi tak kena). Sama seperti videoMediaCacheKey
                  // dipakai player video.
                  // Video → fitWidth (paritas IG): portrait penuh tanpa bar
                  // samping, landscape letterbox atas-bawah. Foto → cover.
                  fit: gridThumbnailFit(post),
                  fadeInDuration: const Duration(milliseconds: 180),
                  placeholder: (_, __) =>
                      Container(color: cs.surfaceContainerHigh),
                  errorWidget: (_, __, ___) => const Center(
                    child: Icon(
                      Icons.image_not_supported_outlined,
                      color: NataloColors.grey400,
                      size: 28,
                    ),
                  ),
                ),
              )
            else
              const Center(
                child: Icon(
                  Icons.image_outlined,
                  color: NataloColors.grey400,
                  size: 28,
                ),
              ),
            // Type indicator top-right: video play, atau carousel (multi-foto)
            // ala IG (kotak bertumpuk) kalau bukan video. Badge tas belanja
            // utk post lama yang punya produk tertaut sengaja dihapus
            // (Spec A) — tidak ada lagi jejak visual "tag belanja" di
            // Profil. Lihat
            // docs/superpowers/specs/2026-07-22-tutup-tag-belanja-spec-a-design.md.
            if (post.isVideo)
              const Positioned(
                top: 8,
                right: 8,
                child: _ThumbnailIcon(icon: Icons.play_arrow_rounded),
              )
            else if (post.isCarousel || post.mediaItems.length > 1)
              const Positioned(
                top: 8,
                right: 8,
                child: _ThumbnailIcon(icon: Icons.collections_rounded),
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
                          : NataloColors.primarySoft,
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

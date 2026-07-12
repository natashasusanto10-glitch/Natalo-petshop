import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/natalo_colors.dart';
import 'package:share_plus/share_plus.dart';
import '../widgets/official_brand_avatar.dart';

import '../config/api_config.dart';
import '../models/feed_post.dart';
import '../models/public_profile.dart';
import '../services/api_client.dart';
import '../services/follow_service.dart';
import '../services/profile_service.dart';
import '../services/report_service.dart';
import '../state/feed_store.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import '../widgets/app_ui.dart';
import '../widgets/moderation_action_sheet.dart';
import '../widgets/natalo_paw_refresh_indicator.dart';
import 'member_post_detail_screen.dart';
import 'public_profile_follow_list_screen.dart';

const _brandBlue = NataloColors.primary;

/// Public profile screen — `/u/{username}` deep link target +
/// destination saat user tap @username di feed/komentar.
///
/// Layout: header (avatar + handle + bio + stats) → tombol Follow
/// (atau Edit Profil kalau owner) → grid 3-kolom postingan public.
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

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  PublicProfile? _profile;
  List<FeedPost> _posts = const [];
  String? _nextCursor;
  bool _loading = true;
  bool _loadingMore = false;
  bool _followBusy = false;
  String? _errorText;
  bool _notFound = false;

  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loadingMore || _nextCursor == null) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorText = null;
      _notFound = false;
    });
    // Capture sebelum await — stale-write guard. Kalau user tap like di
    // tile saat fetch jalan, store skip overwrite interaction fields.
    final fetchedAt = DateTime.now();
    try {
      final result =
          await profileService.fetchPublicProfile(username: widget.username);
      if (!mounted) return;
      // Seed FeedStore — supaya kalau user tap tile masuk Detail dan like
      // dari sana, post di store ke-update + grid bisa observe (kalau
      // suatu saat grid tile tampilkan likeCount visible).
      feedStore.mergeFromServer(
        result.posts,
        fetchedAt: fetchedAt,
      );
      setState(() {
        _profile = result.profile;
        _posts = result.posts;
        _nextCursor = result.nextCursor;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _notFound = e.statusCode == 404;
        _errorText = e.statusCode == 404
            ? 'User ${widget.username} tidak ditemukan.'
            : 'Gagal memuat profil. Tarik untuk coba lagi.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorText = 'Gagal memuat profil. Tarik untuk coba lagi.';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_nextCursor == null) return;
    setState(() => _loadingMore = true);
    final fetchedAt = DateTime.now();
    try {
      final result = await profileService.fetchPublicProfile(
        username: widget.username,
        cursor: _nextCursor,
      );
      if (!mounted) return;
      feedStore.mergeFromServer(
        result.posts,
        fetchedAt: fetchedAt,
      );
      setState(() {
        _posts = [..._posts, ...result.posts];
        _nextCursor = result.nextCursor;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _refresh() async => _load();

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

  void _openPost(int index) {
    if (index < 0 || index >= _posts.length) return;
    final profile = _profile;
    AppHaptics.tap();
    Navigator.push(
      context,
      MaterialPageRoute(
        // IG-style: bukan single-post screen, tapi vertical-scroll feed
        // dari SEMUA posts user — initial scrolled ke tile yang di-tap.
        // Author header pakai data dari PublicProfile (bukan memberStore,
        // karena viewer != author). isOwner: false → sembunyikan menu
        // edit/delete (cuma owner di "Postingan Saya" yang lihat itu).
        builder: (_) => MemberPostDetailScreen(
          post: _posts[index],
          posts: _posts,
          initialIndex: index,
          authorName: profile?.name,
          authorPhotoUrl: profile?.profilePhotoUrl,
          authorInitial: profile?.initial,
          // Official → detail render identitas brand (logo + emas +
          // rosette) di author row, caption, dan subtitle AppBar.
          authorIsOfficial: profile?.isOfficial ?? false,
          isOwner: profile?.isOwner ?? false,
        ),
      ),
    );
  }

  Future<void> _toggleFollow() async {
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

    try {
      final state = wasFollowing
          ? await followService.unfollow(current.id)
          : await followService.follow(current.id);
      if (!mounted) return;
      setState(() {
        _followBusy = false;
        _profile = (_profile ?? current).copyWith(
          isFollowing: state.isFollowing,
          followersCount: state.followersCount,
          followingCount: state.followingCount,
        );
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _followBusy = false;
        _profile = current;
      });
      if (e.isUnauthorized) {
        Navigator.pushNamed(context, '/member/login');
      } else {
        _showSnack(e.message);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _followBusy = false;
        _profile = current;
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
    final onAppBar = isOfficial ? Colors.white : cs.onSurface;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isOfficial
          ? SystemUiOverlayStyle.light
          : (Theme.of(context).brightness == Brightness.dark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark),
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          backgroundColor: isOfficial ? NataloColors.heroTop : cs.surface,
          surfaceTintColor: isOfficial ? NataloColors.heroTop : cs.surface,
          elevation: 0,
          scrolledUnderElevation: isOfficial ? 0 : 0.5,
          centerTitle: false,
          titleSpacing: 0,
          leading: IconButton(
            onPressed: () => Navigator.maybePop(context),
            icon: Icon(
              Icons.arrow_back_rounded,
              color: onAppBar,
              size: 26,
            ),
            tooltip: 'Kembali',
          ),
          title: Text(
            // Akun official (Natalo Petshop): AppBar tampil nama brand, BUKAN
            // username "natasha" (identitas pemilik). displayHandle untuk akun
            // official = username karena username ter-set → bocor nama asli.
            // Konsisten dgn branding Opsi B (body profil sudah override).
            isOfficial
                ? (_profile?.name ?? 'Natalo Petshop')
                : (_profile?.displayHandle ?? widget.username),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              // Judul official → emas identitas; ikon tetap putih (chrome).
              color: isOfficial ? NataloColors.officialGold : onAppBar,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          actions: [
            // Menu moderasi (Laporkan / Blokir) — wajib Google Play UGC.
            // Hanya tampil untuk profil orang lain (bukan diri sendiri) dan
            // bukan akun official (brand tak bisa dilaporkan/diblokir).
            if (_profile != null &&
                !(_profile!.isOwner) &&
                !(_profile!.isOfficial))
              IconButton(
                onPressed: _openModeration,
                icon: Icon(
                  Icons.more_vert_rounded,
                  color: onAppBar,
                  size: 24,
                ),
                tooltip: 'Opsi lainnya',
              ),
          ],
        ),
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
    return NataloPawRefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverToBoxAdapter(
            child: _Header(
              profile: profile,
              followBusy: _followBusy,
              onFollowToggle: profile.isOwner ? null : _toggleFollow,
              onFollowersTap: () => _openFollowList(FollowListKind.followers),
              onFollowingTap: () => _openFollowList(FollowListKind.following),
              onEditProfile: profile.isOwner
                  ? () => Navigator.pushNamed(context, '/member/profile')
                  : null,
              onShareProfile: _shareProfile,
            ),
          ),
          const SliverToBoxAdapter(child: _ProfileTabs()),
          if (_posts.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyPosts(),
            )
          else
            SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 1.5,
                crossAxisSpacing: 1.5,
                childAspectRatio: 1,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, idx) {
                  // Per-tile guard — kalau ada single post yg bikin
                  // _PostTile throw (mis. URL malformed bikin
                  // CachedNetworkImage assert), jangan biarin
                  // AppErrorWidget global ngambil-alih SELURUH grid.
                  // Tile yang gagal di-render sebagai placeholder
                  // abu-abu polos. Sisanya tetap aman.
                  try {
                    return _PostTile(
                      post: _posts[idx],
                      onTap: () => _openPost(idx),
                    );
                  } catch (_) {
                    return ColoredBox(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                    );
                  }
                },
                childCount: _posts.length,
              ),
            ),
          if (_loadingMore)
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

class _Header extends StatelessWidget {
  final PublicProfile profile;
  final bool followBusy;
  final VoidCallback? onFollowToggle;
  final VoidCallback? onFollowersTap;
  final VoidCallback? onFollowingTap;
  final VoidCallback? onEditProfile;
  final VoidCallback? onShareProfile;

  const _Header({
    required this.profile,
    required this.followBusy,
    this.onFollowToggle,
    this.onFollowersTap,
    this.onFollowingTap,
    this.onEditProfile,
    this.onShareProfile,
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

  const _OfficialHeader({
    required this.profile,
    required this.followBusy,
    this.onFollowToggle,
    this.onFollowersTap,
    this.onFollowingTap,
    this.onShareProfile,
  });

  @override
  Widget build(BuildContext context) {
    // AppBar solid heroTop di atas; header ini mulai tepat di bawahnya
    // dengan gradient heroTop→heroMid → menyatu tanpa hitung inset (inset
    // manual di dalam sliver terbukti rapuh: logo overlap judul di device).
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(gradient: NataloColors.heroGradientV),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
      child: Column(
        children: [
          // Logo brand — ring putih + shadow lembut, premium.
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.95),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const OfficialBrandAvatar(size: 88),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  profile.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    // Emas identitas official — seragam dgn feed/komentar.
                    color: NataloColors.officialGold,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const OfficialVerifiedBadge(size: 20),
            ],
          ),
          const SizedBox(height: 8),
          // Pill "Akun Resmi" — aksen emas identitas (tint + border emas).
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: NataloColors.officialGold.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: NataloColors.officialGold.withValues(alpha: 0.45),
                width: 0.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.shield_rounded,
                    color: NataloColors.officialGold, size: 13),
                const SizedBox(width: 5),
                Text(
                  profile.bio?.isNotEmpty == true
                      ? 'AKUN RESMI'
                      : 'AKUN RESMI NATALO PETSHOP',
                  style: const TextStyle(
                    color: NataloColors.officialGold,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ),
          if (profile.bio != null && profile.bio!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              profile.bio!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: NataloColors.onHeroBright,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 16),
          // Kartu statistik putih mengambang.
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  child: _OfficialStat(
                    value: profile.postCount,
                    label: 'Postingan',
                  ),
                ),
                _statDivider(),
                Expanded(
                  child: _OfficialStat(
                    value: profile.followersCount,
                    label: 'Pengikut',
                    onTap: onFollowersTap,
                  ),
                ),
                _statDivider(),
                Expanded(
                  child: _OfficialStat(
                    value: profile.likedCount,
                    label: 'Disukai',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
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
        ],
      ),
    );
  }

  Widget _statDivider() => Container(
        width: 0.5,
        height: 30,
        color: NataloColors.grey200,
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

  const _OfficialStat({
    required this.value,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          formatCountCompact(value),
          style: const TextStyle(
            color: Color(0xFF0F2A4A),
            fontSize: 17,
            fontWeight: FontWeight.w800,
            height: 1.08,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF6B7A90),
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
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
    final cs = Theme.of(context).colorScheme;
    // Akun official Natalo → tampilkan logo brand (bukan foto/initial
    // pribadi). API sudah set profilePhotoUrl null untuk official.
    if (profile.isOfficial) {
      return Container(
        width: 82,
        height: 82,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: cs.surfaceContainerHighest,
        ),
        clipBehavior: Clip.antiAlias,
        padding: const EdgeInsets.all(14),
        child: Image.asset(
          'assets/native/icon-only.png',
          fit: BoxFit.contain,
        ),
      );
    }
    final url = profile.profilePhotoUrl;
    if (url != null && url.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: url,
          width: 82,
          height: 82,
          fit: BoxFit.cover,
          placeholder: (_, __) => _initialAvatar(cs),
          errorWidget: (_, __, ___) => _initialAvatar(cs),
        ),
      );
    }
    return _initialAvatar(cs);
  }

  Widget _initialAvatar(ColorScheme cs) {
    return Container(
      width: 82,
      height: 82,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: cs.surfaceContainerHighest,
      ),
      child: Center(
        child: Text(
          profile.initial,
          style: const TextStyle(
            color: Color(0xFF1D4ED8),
            fontSize: 30,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
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

class _ProfileTabs extends StatelessWidget {
  const _ProfileTabs();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          top: BorderSide(color: cs.outlineVariant, width: 0.5),
          bottom: BorderSide(color: cs.outlineVariant, width: 0.5),
        ),
      ),
      child: SizedBox(
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              Icons.grid_on_rounded,
              color: cs.onSurface,
              size: 23,
            ),
            Positioned(
              bottom: 0,
              child: Container(
                width: 44,
                height: 2,
                decoration: BoxDecoration(
                  color: cs.onSurface,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PostTile extends StatelessWidget {
  final FeedPost post;
  final VoidCallback onTap;

  const _PostTile({required this.post, required this.onTap});

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
    return GestureDetector(
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
                right: 6,
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
          ],
        ),
      ),
    );
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

class _EmptyPosts extends StatelessWidget {
  const _EmptyPosts();

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
              Icons.photo_library_outlined,
              color: cs.onSurfaceVariant,
              size: 32,
            ),
            const SizedBox(height: 10),
            Text(
              'Belum ada postingan',
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

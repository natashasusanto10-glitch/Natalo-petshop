import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/feed_post.dart';
import '../models/public_profile.dart';
import '../services/api_client.dart';
import '../services/follow_service.dart';
import '../services/profile_service.dart';
import '../state/feed_store.dart';
import '../utils/haptics.dart';
import 'member_post_detail_screen.dart';
import 'public_profile_follow_list_screen.dart';

const _brandBlue = Color(0xFF0B7FEA);

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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        surfaceTintColor: cs.surface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleSpacing: 0,
        leading: IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: Icon(
            Icons.arrow_back_rounded,
            color: cs.onSurface,
            size: 26,
          ),
          tooltip: 'Kembali',
        ),
        title: Text(
          // Akun official (Natalo Petshop): AppBar tampil nama brand, BUKAN
          // username "natasha" (identitas pemilik). displayHandle untuk akun
          // official = username karena username ter-set → bocor nama asli.
          // Konsisten dgn branding Opsi B (body profil sudah override).
          (_profile?.isOfficial ?? false)
              ? (_profile?.name ?? 'Natalo Petshop')
              : (_profile?.displayHandle ?? widget.username),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
      ),
      body: _buildBody(),
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
      return _ErrorView(message: _errorText!, onRetry: _load);
    }
    final profile = _profile!;
    return RefreshIndicator(
      color: _brandBlue,
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
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
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

  const _Header({
    required this.profile,
    required this.followBusy,
    this.onFollowToggle,
    this.onFollowersTap,
    this.onFollowingTap,
    this.onEditProfile,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: cs.surface,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Avatar(profile: profile),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
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
                                height: 1.1,
                              ),
                            ),
                          ),
                          // Badge centang biru untuk akun official Natalo.
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
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                  ],
                ),
              ),
            ],
          ),
          if (profile.bio != null && profile.bio!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              profile.bio!,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: onEditProfile != null
                ? OutlinedButton(
                    onPressed: onEditProfile,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cs.onSurface,
                      side: BorderSide(color: cs.outlineVariant),
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Edit Profil'),
                  )
                : profile.isFollowing
                    ? OutlinedButton(
                        onPressed: onFollowToggle,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: cs.onSurface,
                          disabledForegroundColor: cs.onSurface,
                          side: BorderSide(color: cs.outlineVariant),
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: _FollowButtonContent(
                          label: 'Mengikuti',
                          busy: followBusy,
                          spinnerColor: cs.onSurfaceVariant,
                        ),
                      )
                    : FilledButton(
                        onPressed: onFollowToggle,
                        style: FilledButton.styleFrom(
                          backgroundColor: _brandBlue,
                          disabledBackgroundColor: _brandBlue,
                          foregroundColor: Colors.white,
                          disabledForegroundColor: Colors.white,
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: _FollowButtonContent(
                          label: 'Follow',
                          busy: followBusy,
                          spinnerColor: Colors.white,
                        ),
                      ),
          ),
        ],
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
            '$value',
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
        errorWidget: (_, __, ___) =>
            ColoredBox(color: cs.surfaceContainerHighest),
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

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: _brandBlue,
              ),
              child: const Text('Coba Lagi'),
            ),
          ],
        ),
      ),
    );
  }
}

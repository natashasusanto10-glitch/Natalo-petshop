import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/my_feed_post.dart';
import '../models/public_profile.dart';
import '../services/api_client.dart';
import '../services/follow_service.dart';
import '../services/profile_service.dart';
import '../utils/haptics.dart';
import 'member_post_detail_screen.dart';
import 'public_profile_follow_list_screen.dart';

const _brandBlue = Color(0xFF0B7FEA);
const _pageBg = Colors.white;
const _darkNavy = Color(0xFF101828);
const _textSecondary = Color(0xFF667085);
const _borderSoft = Color(0xFFE2E8F0);

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
  List<MyFeedPost> _posts = const [];
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
    try {
      final result =
          await profileService.fetchPublicProfile(username: widget.username);
      if (!mounted) return;
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
    try {
      final result = await profileService.fetchPublicProfile(
        username: widget.username,
        cursor: _nextCursor,
      );
      if (!mounted) return;
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

  void _openFollowList(FollowListKind kind) {
    final profile = _profile;
    if (profile == null) return;
    AppHaptics.tap();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PublicProfileFollowListScreen(
          profile: profile,
          initialKind: kind,
        ),
      ),
    );
  }

  void _openPost(int index) {
    if (index < 0 || index >= _posts.length) return;
    AppHaptics.tap();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MemberPostDetailScreen(post: _posts[index]),
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
    return Scaffold(
      backgroundColor: _pageBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleSpacing: 0,
        leading: IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: _darkNavy,
            size: 26,
          ),
          tooltip: 'Kembali',
        ),
        title: Text(
          _profile?.displayHandle ?? widget.username,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _darkNavy,
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
                    return const ColoredBox(color: Color(0xFFE2E8F0));
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
    return Container(
      width: double.infinity,
      color: Colors.white,
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
                      child: Text(
                        profile.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _darkNavy,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
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
              style: const TextStyle(
                color: Color(0xFF334155),
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
                      foregroundColor: _darkNavy,
                      side: const BorderSide(color: _borderSoft),
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
                        onPressed: followBusy ? null : onFollowToggle,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _darkNavy,
                          side: const BorderSide(color: _borderSoft),
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: followBusy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: _textSecondary,
                                ),
                              )
                            : const Text('Mengikuti'),
                      )
                    : FilledButton(
                        onPressed: followBusy ? null : onFollowToggle,
                        style: FilledButton.styleFrom(
                          backgroundColor: _brandBlue,
                          foregroundColor: Colors.white,
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: followBusy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Follow'),
                      ),
          ),
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
    final url = profile.profilePhotoUrl;
    if (url != null && url.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: url,
          width: 82,
          height: 82,
          fit: BoxFit.cover,
          placeholder: (_, __) => _initialAvatar(),
          errorWidget: (_, __, ___) => _initialAvatar(),
        ),
      );
    }
    return _initialAvatar();
  }

  Widget _initialAvatar() {
    return Container(
      width: 82,
      height: 82,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFFEFF6FF),
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
    final content = SizedBox(
      width: 70,
      child: Column(
        children: [
          Text(
            '$value',
            style: const TextStyle(
              color: _darkNavy,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              height: 1.08,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(
              color: _textSecondary,
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
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: _borderSoft, width: 0.5),
          bottom: BorderSide(color: _borderSoft, width: 0.5),
        ),
      ),
      child: SizedBox(
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(
              Icons.grid_on_rounded,
              color: _darkNavy,
              size: 23,
            ),
            Positioned(
              bottom: 0,
              child: Container(
                width: 44,
                height: 2,
                decoration: BoxDecoration(
                  color: _darkNavy,
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
  final MyFeedPost post;
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
          return const ColoredBox(color: Color(0xFFE2E8F0));
        }
      },
    );
  }

  Widget _buildSafeTile(BuildContext context) {
    // Resolve thumb dgn fallback chain — thumbnailUrl post → thumbnailUrl
    // media pertama → mediaUrl media pertama → mediaUrl post.
    final rawThumb = post.thumbnailUrl ??
        (post.mediaItems.isNotEmpty
            ? post.mediaItems.first.thumbnailUrl ??
                post.mediaItems.first.mediaUrl
            : post.mediaUrl);
    final thumb = rawThumb.trim();

    // STRICT URL validation — pakai Uri.tryParse + check scheme + host.
    // Defensive untuk edge case: "https://" tanpa host, URL dengan space,
    // path relative, "javascript:" scheme, dll. Sebelumnya cuma cek
    // startsWith yang gampang lolos URL malformed.
    final parsedUri = Uri.tryParse(thumb);
    final isValidImageUrl = parsedUri != null &&
        (parsedUri.scheme == 'http' || parsedUri.scheme == 'https') &&
        parsedUri.hasAuthority;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        color: const Color(0xFFE2E8F0),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (isValidImageUrl)
              _SafeNetworkImage(url: thumb)
            else
              const ColoredBox(color: Color(0xFFE2E8F0)),
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
    try {
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        placeholder: (_, __) =>
            const ColoredBox(color: Color(0xFFE2E8F0)),
        errorWidget: (_, __, ___) =>
            const ColoredBox(color: Color(0xFFE2E8F0)),
      );
    } catch (_) {
      return const ColoredBox(color: Color(0xFFE2E8F0));
    }
  }
}

class _EmptyPosts extends StatelessWidget {
  const _EmptyPosts();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 42, 24, 80),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.photo_library_outlined,
              color: Color(0xFFCBD5E1),
              size: 32,
            ),
            SizedBox(height: 10),
            Text(
              'Belum ada postingan',
              style: TextStyle(
                color: _darkNavy,
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.person_off_rounded,
              size: 56,
              color: Color(0xFFCBD5E1),
            ),
            const SizedBox(height: 12),
            Text(
              'User $handle tidak ditemukan',
              style: const TextStyle(
                color: _darkNavy,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            const Text(
              'Mungkin username diganti atau akun sudah dihapus.',
              style: TextStyle(
                color: _textSecondary,
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              style: const TextStyle(
                color: _darkNavy,
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

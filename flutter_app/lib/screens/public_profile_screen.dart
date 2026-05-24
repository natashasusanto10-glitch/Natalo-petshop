import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/my_feed_post.dart';
import '../models/public_profile.dart';
import '../services/api_client.dart';
import '../services/profile_service.dart';
import '../utils/haptics.dart';
import 'member_post_detail_screen.dart';

const _brandBlue = Color(0xFF0B7FEA);
const _pageBg = Color(0xFFF8FAFC);
const _darkNavy = Color(0xFF101828);
const _textSecondary = Color(0xFF667085);
const _borderSoft = Color(0xFFE2E8F0);

/// Public profile screen — `/u/{username}` deep link target +
/// destination saat user tap @username di feed/komentar.
///
/// Layout: header (avatar + handle + bio + stats) → tombol Bagikan
/// (atau Edit Profil kalau owner) → grid 3-kolom postingan public.
///
/// Owner view: tombol "Edit Profil" → /member/profile. Other view:
/// tombol "Bagikan" → share sheet system dengan URL natalopetshop.com/u/X.
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
            ? 'User @${widget.username} tidak ditemukan.'
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

  void _share() {
    AppHaptics.tap();
    final p = _profile;
    if (p == null) return;
    final handle = p.username ?? widget.username.toLowerCase();
    final url = 'https://natalopetshop.com/u/$handle';
    final text = p.bio != null && p.bio!.isNotEmpty
        ? 'Cek profil @$handle di Natalo Petshop\n\n${p.bio}\n\n$url'
        : 'Cek profil @$handle di Natalo Petshop\n\n$url';
    Share.share(text, subject: '@$handle di Natalo Petshop');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Kembali',
        ),
        title: Text(
          _profile?.displayHandle ?? '@${widget.username}',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        actions: [
          if (_profile != null)
            IconButton(
              onPressed: _share,
              tooltip: 'Bagikan',
              icon: const Icon(Icons.ios_share_rounded),
            ),
        ],
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
              onShare: _share,
              onEditProfile: profile.isOwner
                  ? () => Navigator.pushNamed(context, '/member/profile')
                  : null,
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            sliver: _posts.isEmpty
                ? const SliverToBoxAdapter(child: _EmptyPosts())
                : SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 3,
                      crossAxisSpacing: 3,
                      childAspectRatio: 1,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, idx) => _PostTile(
                        post: _posts[idx],
                        onTap: () => _openPost(idx),
                      ),
                      childCount: _posts.length,
                    ),
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
  final VoidCallback onShare;
  final VoidCallback? onEditProfile;

  const _Header({
    required this.profile,
    required this.onShare,
    this.onEditProfile,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _Avatar(profile: profile),
              const SizedBox(width: 18),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _StatColumn(
                      value: profile.postCount,
                      label: 'Postingan',
                    ),
                    _StatColumn(
                      value: profile.likedCount,
                      label: 'Disukai',
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            profile.username != null
                ? '@${profile.username}'
                : profile.name,
            style: const TextStyle(
              color: _darkNavy,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (profile.username != null && profile.name != profile.username) ...[
            const SizedBox(height: 2),
            Text(
              profile.name,
              style: const TextStyle(
                color: _textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (profile.bio != null && profile.bio!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              profile.bio!,
              style: const TextStyle(
                color: Color(0xFF334155),
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: onEditProfile != null
                    ? OutlinedButton.icon(
                        onPressed: onEditProfile,
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Edit Profil'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _darkNavy,
                          side: const BorderSide(color: _borderSoft),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      )
                    : FilledButton.icon(
                        onPressed: onShare,
                        icon: const Icon(Icons.ios_share_rounded, size: 18),
                        label: const Text('Bagikan Profil'),
                        style: FilledButton.styleFrom(
                          backgroundColor: _brandBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
              ),
              if (onEditProfile != null) ...[
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: onShare,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _darkNavy,
                    side: const BorderSide(color: _borderSoft),
                    padding: const EdgeInsets.all(10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Icon(Icons.ios_share_rounded, size: 18),
                ),
              ],
            ],
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
          width: 84,
          height: 84,
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
      width: 84,
      height: 84,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [Color(0xFFDBEAFE), Color(0xFFBFDBFE)],
        ),
      ),
      child: Center(
        child: Text(
          profile.initial,
          style: const TextStyle(
            color: Color(0xFF1D4ED8),
            fontSize: 32,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  final int value;
  final String label;

  const _StatColumn({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '$value',
          style: const TextStyle(
            color: _darkNavy,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: _textSecondary,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _PostTile extends StatelessWidget {
  final MyFeedPost post;
  final VoidCallback onTap;

  const _PostTile({required this.post, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final thumb = post.thumbnailUrl ??
        (post.mediaItems.isNotEmpty
            ? post.mediaItems.first.thumbnailUrl ??
                post.mediaItems.first.mediaUrl
            : post.mediaUrl);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFE2E8F0),
          borderRadius: BorderRadius.circular(2),
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (thumb.isNotEmpty)
              CachedNetworkImage(
                imageUrl: thumb,
                fit: BoxFit.cover,
                placeholder: (_, __) =>
                    const ColoredBox(color: Color(0xFFE2E8F0)),
                errorWidget: (_, __, ___) =>
                    const ColoredBox(color: Color(0xFFE2E8F0)),
              )
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

class _EmptyPosts extends StatelessWidget {
  const _EmptyPosts();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 30),
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      decoration: BoxDecoration(
        border: Border.all(color: _borderSoft, style: BorderStyle.solid),
        borderRadius: BorderRadius.circular(16),
        color: Colors.white,
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.photo_library_outlined,
              color: Color(0xFFCBD5E1),
              size: 36,
            ),
            SizedBox(height: 8),
            Text(
              'Belum ada postingan',
              style: TextStyle(
                color: _darkNavy,
                fontSize: 14,
                fontWeight: FontWeight.w800,
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
              'User @$handle tidak ditemukan',
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

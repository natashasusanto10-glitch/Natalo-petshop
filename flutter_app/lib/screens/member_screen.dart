import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/my_feed_post.dart';
import '../services/feed_service.dart';
import '../state/member_store.dart';
import '../utils/haptics.dart';
import '../widgets/app_notification_button.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/feed_upload_sheet.dart';
import '../widgets/natalo_paw_refresh_indicator.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/update_profile_photo_sheet.dart';
import 'member_post_detail_screen.dart';

/// Halaman Akun — social profile + galeri postingan user.
///
/// Layout: Header (+ icon, bell, cart) → Profile section (foto + nama +
/// stats Postingan/Disukai/Produk Ditag) → Tab bar (Postingan/Video/
/// Produk Ditag) → Grid 3-kolom user posts.
///
/// Semua menu transaksi (Pesanan, Voucher, Wishlist, Alamat, Poin, Ulasan)
/// SUDAH DIPINDAH ke halaman /transactions. Halaman ini fokus jadi
/// profile sosial.
const _brandBlue = Color(0xFF0B7FEA);
const _pageBg = Colors.white;
const _textPrimary = Color(0xFF0F172A);
const _textSecondary = Color(0xFF64748B);

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
    return const Scaffold(
      backgroundColor: _pageBg,
      body: Center(
        child: CircularProgressIndicator(color: _brandBlue, strokeWidth: 2.4),
      ),
      bottomNavigationBar: BottomNavBar(currentIndex: 4),
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
  late TabController _tabController;
  List<MyFeedPost> _allPosts = const [];
  bool _loadingPosts = true;
  int _likedPostsCount = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loadingPosts = true);
    final results = await Future.wait<dynamic>([
      feedService.fetchMyPosts(filter: 'all'),
      feedService.fetchMyLikesCount(),
    ]);
    if (!mounted) return;
    // fetchMyPosts return MyFeedPostPage (cursor-paginated). Untuk
    // header summary di Akun (stat post count), kita pakai page pertama
    // saja — tidak perlu fetch all pages. Total post count tetap akurat
    // via len(items) untuk preview, atau ambil dari totalCount kalau
    // butuh exact (future enhancement).
    final page = results[0] as MyFeedPostPage;
    setState(() {
      _allPosts = page.items;
      _likedPostsCount = results[1] as int;
      _loadingPosts = false;
    });
  }

  Future<void> _refresh() async {
    await _loadAll();
  }

  Future<void> _openCreatePost() async {
    AppHaptics.tap();
    final uploaded = await FeedUploadSheet.show(context);
    if (uploaded == true && mounted) {
      await _loadAll();
    }
  }

  void _openProfilePhotoSheet() {
    AppHaptics.tap();
    showUpdateProfilePhotoSheet(context);
  }

  void _openPostDetail(List<MyFeedPost> posts, int initialIndex) {
    if (posts.isEmpty) return;
    AppHaptics.tap();
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => MemberPostDetailScreen(
          post: posts[initialIndex],
          posts: posts,
          initialIndex: initialIndex,
        ),
      ),
    ).then((_) {
      // User mungkin delete/edit post di detail screen → refresh.
      if (mounted) _loadAll();
    });
  }

  List<MyFeedPost> get _videoPosts =>
      _allPosts.where((p) => p.isVideo).toList();

  List<MyFeedPost> get _taggedPosts =>
      _allPosts.where((p) => p.productIds.isNotEmpty).toList();

  @override
  Widget build(BuildContext context) {
    final profile = memberStore.profile!;
    return Scaffold(
      backgroundColor: _pageBg,
      appBar: _ProfileAppBar(onCreatePost: _openCreatePost),
      body: NataloPawRefreshIndicator(
        onRefresh: _refresh,
        child: NestedScrollView(
          headerSliverBuilder: (context, innerScrolled) => [
            SliverToBoxAdapter(
              child: _ProfileSection(
                profile: profile,
                postsCount: _allPosts.length,
                likedCount: _likedPostsCount,
                taggedCount: _taggedPosts.length,
                onAvatarTap: _openProfilePhotoSheet,
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabBarDelegate(controller: _tabController),
            ),
          ],
          body: TabBarView(
            controller: _tabController,
            children: [
              _PostGrid(
                posts: _allPosts,
                loading: _loadingPosts,
                emptyText: 'Belum ada postingan',
                emptySubtext:
                    'Bagikan momen lucu hewan kesayanganmu di Feed Natalo.',
                showCreateCta: true,
                onCreateCta: _openCreatePost,
                onTapPost: (idx) => _openPostDetail(_allPosts, idx),
              ),
              _PostGrid(
                posts: _videoPosts,
                loading: _loadingPosts,
                emptyText: 'Belum ada video',
                emptySubtext: 'Video yang kamu unggah akan muncul di sini.',
                showCreateCta: false,
                onCreateCta: _openCreatePost,
                onTapPost: (idx) => _openPostDetail(_videoPosts, idx),
              ),
              _PostGrid(
                posts: _taggedPosts,
                loading: _loadingPosts,
                emptyText: 'Belum ada produk ditag',
                emptySubtext:
                    'Postingan dengan produk Natalo yang ditag akan muncul di sini.',
                showCreateCta: false,
                onCreateCta: _openCreatePost,
                onTapPost: (idx) => _openPostDetail(_taggedPosts, idx),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const BottomNavBar(currentIndex: 4),
    );
  }
}

// ─── AppBar ────────────────────────────────────────────────────────

class _ProfileAppBar extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback onCreatePost;

  const _ProfileAppBar({required this.onCreatePost});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: _pageBg,
      surfaceTintColor: _pageBg,
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      titleSpacing: 12,
      title: Row(
        children: [
          // Plus icon kiri — buka create-post flow existing.
          IconButton(
            onPressed: onCreatePost,
            tooltip: 'Buat postingan',
            icon: const Icon(
              Icons.add_rounded,
              size: 28,
              color: _textPrimary,
            ),
          ),
        ],
      ),
      actions: [
        const AppNotificationButton(),
        IconButton(
          onPressed: () => Navigator.pushNamed(context, '/account/settings'),
          tooltip: 'Pengaturan akun',
          icon: const Icon(
            Icons.settings_outlined,
            color: _textPrimary,
          ),
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}

// ─── Profile section (photo + name + stats) ───────────────────────

class _ProfileSection extends StatelessWidget {
  final dynamic profile; // MemberProfile — keep dynamic supaya tidak import.
  final int postsCount;
  final int likedCount;
  final int taggedCount;
  final VoidCallback onAvatarTap;

  const _ProfileSection({
    required this.profile,
    required this.postsCount,
    required this.likedCount,
    required this.taggedCount,
    required this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ProfileAvatar(
                initial: profile.initial as String? ?? '?',
                imageUrl: profile.profilePhotoUrl as String?,
                size: 80,
                fontSize: 30,
                showCameraBadge: true,
                onTap: onAvatarTap,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (profile.name as String?) ?? 'Member Natalo',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _ProfileStat(
                            value: postsCount,
                            label: 'Postingan',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _ProfileStat(
                            value: likedCount,
                            label: 'Disukai',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _ProfileStat(
                            value: taggedCount,
                            label: 'Produk Ditag',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Bio (kalau ada) — IG-style di bawah row avatar+nama+stats.
          // Multiline, 3 max biar tidak push down hasil scroll. Auto-hide
          // kalau profile.bio null/empty (jangan render kosong takes space).
          if ((profile.bio as String?)?.trim().isNotEmpty ?? false) ...[
            const SizedBox(height: 12),
            Text(
              profile.bio as String,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProfileStat extends StatelessWidget {
  final int value;
  final String label;

  const _ProfileStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          _formatCount(value),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            height: 1.05,
          ),
        ),
      ],
    );
  }
}

String _formatCount(int n) {
  if (n < 1000) return '$n';
  if (n < 1000000) {
    final v = n / 1000;
    if (v == v.roundToDouble()) return '${v.toInt()}K';
    return '${v.toStringAsFixed(1).replaceAll('.', ',')}K';
  }
  final v = n / 1000000;
  if (v == v.roundToDouble()) return '${v.toInt()}M';
  return '${v.toStringAsFixed(1).replaceAll('.', ',')}M';
}

// ─── Tab bar ────────────────────────────────────────────────────────

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabController controller;

  _TabBarDelegate({required this.controller});

  @override
  double get minExtent => 42;

  @override
  double get maxExtent => 42;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: _pageBg,
      child: TabBar(
        controller: controller,
        labelColor: _brandBlue,
        unselectedLabelColor: _textSecondary,
        // Custom UnderlineTabIndicator dengan ketebalan 3 + bottom inset
        // 4dp supaya indikator floating subtle di bawah icon, bukan
        // nempel mati di edge bottom. Animated transition antar tab
        // langsung di-handle Flutter TabBar (200ms ease-in-out default).
        indicator: UnderlineTabIndicator(
          borderSide: const BorderSide(color: _brandBlue, width: 3),
          borderRadius: BorderRadius.circular(3),
          insets: const EdgeInsets.symmetric(horizontal: 16),
        ),
        indicatorSize: TabBarIndicatorSize.label,
        // Hide old static indicatorColor/Weight props karena kita pakai
        // custom UnderlineTabIndicator di atas.
        indicatorColor: _brandBlue,
        indicatorWeight: 0.001,
        // Splash + hover di-disable supaya tap area clean — bukan ada
        // splash bulat material yang clash dengan custom indicator.
        splashFactory: NoSplash.splashFactory,
        overlayColor:
            WidgetStateProperty.all<Color>(Colors.transparent),
        labelStyle: const TextStyle(
          fontSize: 0,
          fontWeight: FontWeight.w800,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 0,
          fontWeight: FontWeight.w700,
        ),
        tabs: [
          Tab(
            height: 42,
            iconMargin: EdgeInsets.zero,
            icon: Semantics(
              label: 'Postingan',
              child: const Icon(Icons.grid_on_rounded, size: 24),
            ),
          ),
          Tab(
            height: 42,
            iconMargin: EdgeInsets.zero,
            icon: Semantics(
              label: 'Video',
              child: const Icon(Icons.play_circle_outline_rounded, size: 24),
            ),
          ),
          Tab(
            height: 42,
            iconMargin: EdgeInsets.zero,
            icon: Semantics(
              label: 'Produk Ditag',
              child: const Icon(Icons.shopping_bag_outlined, size: 24),
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) {
    return oldDelegate.controller != controller;
  }
}

// ─── Post grid 3-kolom ────────────────────────────────────────────

class _PostGrid extends StatelessWidget {
  final List<MyFeedPost> posts;
  final bool loading;
  final String emptyText;
  final String emptySubtext;
  final bool showCreateCta;
  final VoidCallback onCreateCta;
  final ValueChanged<int> onTapPost;

  const _PostGrid({
    required this.posts,
    required this.loading,
    required this.emptyText,
    required this.emptySubtext,
    required this.showCreateCta,
    required this.onCreateCta,
    required this.onTapPost,
  });

  @override
  Widget build(BuildContext context) {
    if (loading && posts.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: _brandBlue,
          ),
        ),
      );
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
            onTap: () => onTapPost(index),
          );
        },
      ),
    );
  }
}

class _PostThumbnail extends StatelessWidget {
  final MyFeedPost post;
  final VoidCallback onTap;

  const _PostThumbnail({required this.post, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final mediaUrl = (post.thumbnailUrl?.trim().isNotEmpty == true
            ? post.thumbnailUrl
            : null) ??
        (post.previewMediaUrl.trim().isNotEmpty ? post.previewMediaUrl : null);
    return InkWell(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: const Color(0xFFF1F5F9)),
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
                    Container(color: const Color(0xFFE2E8F0)),
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
      child: Icon(
        icon,
        size: 14,
        color: Colors.white,
      ),
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
                      color: const Color(0xFFEAF5FF),
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
                        border: Border.all(color: Colors.white, width: 3),
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
              style: const TextStyle(
                color: _textPrimary,
                fontSize: 16.5,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtext,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _textSecondary,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            if (showCreateCta) ...[
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: onCreateCta,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text(
                  'Buat Postingan',
                  style: TextStyle(fontWeight: FontWeight.w900),
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

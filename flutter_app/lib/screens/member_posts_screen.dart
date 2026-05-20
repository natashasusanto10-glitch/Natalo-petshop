import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/my_feed_post.dart';
import '../services/feed_service.dart';
import '../utils/haptics.dart';
import '../widgets/feed_upload_sheet.dart';
import '../widgets/natalo_paw_refresh_indicator.dart';

const _brandBlue = Color(0xFF0B7FEA);
const _deepNavy = Color(0xFF0F172A);
const _mutedText = Color(0xFF667085);
const _softBorder = Color(0xFFDCE8F8);
const _pageBg = Color(0xFFF7FAFF);

class MemberPostsScreen extends StatefulWidget {
  const MemberPostsScreen({super.key});

  @override
  State<MemberPostsScreen> createState() => _MemberPostsScreenState();
}

class _MemberPostsScreenState extends State<MemberPostsScreen> {
  int _galleryTabIndex = 0;
  int _filterIndex = 0;
  List<MyFeedPost> _allPosts = const [];
  bool _loading = true;

  static const _filters = [
    _PostsFilter(label: 'Semua', type: _PostFilterType.all),
    _PostsFilter(label: 'Foto', type: _PostFilterType.photo),
    _PostsFilter(label: 'Video', type: _PostFilterType.video),
    _PostsFilter(label: 'Review', type: _PostFilterType.review),
  ];

  @override
  void initState() {
    super.initState();
    _loadPosts();
  }

  Future<void> _loadPosts() async {
    setState(() => _loading = true);
    final result = await feedService.fetchMyPosts(filter: 'all');
    if (!mounted) return;
    setState(() {
      _allPosts = result;
      _loading = false;
    });
  }

  List<MyFeedPost> get _visiblePosts {
    final filter = _filters[_filterIndex].type;
    return _allPosts.where((post) {
      return switch (filter) {
        _PostFilterType.all => true,
        _PostFilterType.photo => !_isVideoPost(post),
        _PostFilterType.video => _isVideoPost(post),
        _PostFilterType.review => post.statusInfo == MyFeedPostStatus.pending,
      };
    }).toList();
  }

  _PostStats get _stats {
    final videos = _allPosts.where(_isVideoPost).length;
    return _PostStats(
      total: _allPosts.length,
      active: _allPosts
          .where((post) => post.statusInfo == MyFeedPostStatus.active)
          .length,
      photos: _allPosts.length - videos,
      videos: videos,
    );
  }

  void _openDetail(MyFeedPost post) {
    AppHaptics.tap();
    Navigator.pushNamed(context, '/member/postingan-detail', arguments: post)
        .then((_) => _loadPosts());
  }

  Future<void> _openUpload() async {
    AppHaptics.tap();
    final uploaded = await FeedUploadSheet.show(context);
    if (uploaded == true) {
      _loadPosts();
    }
  }

  void _openDrafts() {
    AppHaptics.tap();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Draft postingan belum tersedia di aplikasi.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _onGalleryTabChanged(int index) {
    AppHaptics.tap();
    setState(() {
      _galleryTabIndex = index;
      if (index == 1) {
        _filterIndex = 2;
      } else if (index == 2) {
        _filterIndex = 1;
      } else {
        _filterIndex = 0;
      }
    });
  }

  void _onFilterChanged(int index) {
    AppHaptics.tap();
    setState(() {
      _filterIndex = index;
      final type = _filters[index].type;
      _galleryTabIndex = switch (type) {
        _PostFilterType.video => 1,
        _PostFilterType.photo => 2,
        _ => 0,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final visiblePosts = _visiblePosts;

    return Scaffold(
      backgroundColor: _pageBg,
      appBar: AppBar(
        backgroundColor: _pageBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: _pageBg,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: _deepNavy),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text(
          'Postingan Saya',
          style: TextStyle(
            color: _deepNavy,
            fontSize: 19,
            fontWeight: FontWeight.w900,
          ),
        ),
        centerTitle: true,
      ),
      body: NataloPawRefreshIndicator(
        onRefresh: _loadPosts,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
                  children: [
                    _PostsHeroCard(stats: _stats),
                    const SizedBox(height: 14),
                    _PostActionsRow(
                      onCreate: _openUpload,
                      onDraft: _openDrafts,
                    ),
                    const SizedBox(height: 14),
                    const _ApprovalInfoStrip(),
                    const SizedBox(height: 14),
                    _GalleryModeTabs(
                      activeIndex: _galleryTabIndex,
                      onTap: _onGalleryTabChanged,
                    ),
                    const SizedBox(height: 14),
                    _FilterChips(
                      filters: _filters,
                      activeIndex: _filterIndex,
                      onTap: _onFilterChanged,
                    ),
                    const SizedBox(height: 14),
                  ],
                ),
              ),
            ),
            if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: SizedBox(
                    height: 28,
                    width: 28,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (_allPosts.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                  child: _EmptyPostsCard(onUpload: _openUpload),
                ),
              )
            else if (visiblePosts.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
                  child: _FilteredEmptyCard(
                    label: _filters[_filterIndex].label,
                  ),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  0,
                  16,
                  MediaQuery.of(context).padding.bottom + 28,
                ),
                sliver: SliverGrid.builder(
                  itemCount: visiblePosts.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 7,
                    mainAxisSpacing: 7,
                    childAspectRatio: 1.0,
                  ),
                  itemBuilder: (context, index) {
                    final post = visiblePosts[index];
                    return _GalleryPostTile(
                      post: post,
                      onTap: () => _openDetail(post),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum _PostFilterType { all, photo, video, review }

class _PostsFilter {
  final String label;
  final _PostFilterType type;
  const _PostsFilter({required this.label, required this.type});
}

class _PostStats {
  final int total;
  final int active;
  final int photos;
  final int videos;

  const _PostStats({
    required this.total,
    required this.active,
    required this.photos,
    required this.videos,
  });
}

class _PostsHeroCard extends StatelessWidget {
  final _PostStats stats;
  const _PostsHeroCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: _softBorder),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.05),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          const Row(
            children: [
              _FeedHeroIllustration(),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cerita seru kamu\nkumpul di sini',
                      style: TextStyle(
                        color: _deepNavy,
                        fontSize: 23,
                        height: 1.16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                      ),
                    ),
                    SizedBox(height: 10),
                    Text(
                      'Lihat lagi momen lucu, gemas, dan seru yang pernah kamu bagikan ke Feed Natalo.',
                      style: TextStyle(
                        color: _mutedText,
                        fontSize: 14,
                        height: 1.45,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0xFFE5EAF2)),
          const SizedBox(height: 14),
          Row(
            children: [
              _StatItem(value: stats.total, label: 'Postingan'),
              const _StatDivider(),
              _StatItem(value: stats.active, label: 'Tayang'),
              const _StatDivider(),
              _StatItem(value: stats.photos, label: 'Foto'),
              const _StatDivider(),
              _StatItem(value: stats.videos, label: 'Video'),
            ],
          ),
        ],
      ),
    );
  }
}

class _FeedHeroIllustration extends StatelessWidget {
  const _FeedHeroIllustration();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 122,
      height: 122,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0EA5FF), Color(0xFF075FCC)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: _brandBlue.withValues(alpha: 0.20),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: const Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 24,
            top: 24,
            child: Text(
              'NL',
              style: TextStyle(
                color: Colors.white,
                fontSize: 40,
                fontWeight: FontWeight.w900,
                height: 0.95,
              ),
            ),
          ),
          Positioned(
            left: 27,
            top: 64,
            child: Text(
              'Feed',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ),
          Positioned(
            left: -10,
            top: -8,
            child: _FloatingBadge(
              color: Color(0xFFFFA12B),
              icon: Icons.play_arrow_rounded,
              tilt: -0.18,
            ),
          ),
          Positioned(
            left: -12,
            bottom: 26,
            child: _FloatingBadge(
              color: Color(0xFFEF4444),
              icon: Icons.favorite_rounded,
              tilt: -0.16,
            ),
          ),
          Positioned(
            right: -10,
            top: -10,
            child: _FloatingBadge(
              color: Color(0xFFEAF3FF),
              icon: Icons.pets_rounded,
              iconColor: _brandBlue,
              tilt: 0.18,
            ),
          ),
          Positioned(
            right: 12,
            bottom: 36,
            child: Icon(
              Icons.camera_alt_rounded,
              color: Color(0xFFDCEBFF),
              size: 31,
            ),
          ),
          Positioned(
            left: 16,
            bottom: 7,
            child: _PetFace(
              color: Color(0xFFC9782A),
              earColor: Color(0xFF8B4A1A),
            ),
          ),
          Positioned(
            right: 19,
            bottom: 8,
            child: _PetFace(
              color: Color(0xFFD7DEE8),
              earColor: Color(0xFF94A3B8),
            ),
          ),
          Positioned(
            right: 38,
            top: 24,
            child: Icon(Icons.auto_awesome_rounded,
                color: Color(0xFFFFD166), size: 15),
          ),
          Positioned(
            left: 70,
            top: 18,
            child: Icon(Icons.auto_awesome_rounded,
                color: Color(0xFFFFD166), size: 13),
          ),
        ],
      ),
    );
  }
}

class _FloatingBadge extends StatelessWidget {
  final Color color;
  final IconData icon;
  final Color iconColor;
  final double tilt;

  const _FloatingBadge({
    required this.color,
    required this.icon,
    this.iconColor = Colors.white,
    this.tilt = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: tilt,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.14),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Icon(icon, color: iconColor, size: 25),
      ),
    );
  }
}

class _PetFace extends StatelessWidget {
  final Color color;
  final Color earColor;

  const _PetFace({
    required this.color,
    required this.earColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 42,
      child: Stack(
        children: [
          Positioned(
            left: 4,
            top: 0,
            child: Transform.rotate(
              angle: -0.35,
              child:
                  Icon(Icons.change_history_rounded, color: earColor, size: 24),
            ),
          ),
          Positioned(
            right: 4,
            top: 0,
            child: Transform.rotate(
              angle: 0.35,
              child:
                  Icon(Icons.change_history_rounded, color: earColor, size: 24),
            ),
          ),
          Positioned(
            left: 4,
            right: 4,
            bottom: 0,
            child: Container(
              height: 34,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Center(
                child: Icon(
                  Icons.pets_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final int value;
  final String label;
  const _StatItem({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            '$value',
            style: const TextStyle(
              color: _deepNavy,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF53627A),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 34,
      color: const Color(0xFFD9E5F6),
    );
  }
}

class _PostActionsRow extends StatelessWidget {
  final VoidCallback onCreate;
  final VoidCallback onDraft;

  const _PostActionsRow({
    required this.onCreate,
    required this.onDraft,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add_rounded, size: 24),
              label: const Text('+ Buat Postingan'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _brandBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              onPressed: onDraft,
              icon: const Icon(Icons.description_outlined, size: 22),
              label: const Text('Draft'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _brandBlue,
                side: const BorderSide(color: _brandBlue, width: 1.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ApprovalInfoStrip extends StatelessWidget {
  const _ApprovalInfoStrip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDCEBFF)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_rounded, color: _brandBlue, size: 24),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Foto dan video akan tampil di Feed setelah disetujui admin.',
              style: TextStyle(
                color: Color(0xFF53627A),
                fontSize: 13,
                height: 1.3,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GalleryModeTabs extends StatelessWidget {
  final int activeIndex;
  final ValueChanged<int> onTap;

  const _GalleryModeTabs({
    required this.activeIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const icons = [
      Icons.grid_view_rounded,
      Icons.play_circle_outline_rounded,
      Icons.photo_camera_outlined,
    ];

    return Container(
      height: 58,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _softBorder),
      ),
      child: Row(
        children: List.generate(icons.length, (index) {
          final active = index == activeIndex;
          return Expanded(
            child: InkWell(
              onTap: () => onTap(index),
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    icons[index],
                    color: active ? _brandBlue : const Color(0xFF78869C),
                    size: 28,
                  ),
                  if (active)
                    Positioned(
                      bottom: 0,
                      child: Container(
                        width: 46,
                        height: 4,
                        decoration: BoxDecoration(
                          color: _brandBlue,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  final List<_PostsFilter> filters;
  final int activeIndex;
  final ValueChanged<int> onTap;

  const _FilterChips({
    required this.filters,
    required this.activeIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final active = index == activeIndex;
          return InkWell(
            onTap: () => onTap(index),
            borderRadius: BorderRadius.circular(999),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: active ? _brandBlue : const Color(0xFFF0F4FA),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: active ? _brandBlue : const Color(0xFFE5EAF2),
                ),
              ),
              child: Text(
                filters[index].label,
                style: TextStyle(
                  color: active ? Colors.white : const Color(0xFF64748B),
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _GalleryPostTile extends StatelessWidget {
  final MyFeedPost post;
  final VoidCallback onTap;

  const _GalleryPostTile({
    required this.post,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isVideo = _isVideoPost(post);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _PostThumbnail(post: post),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.06),
                      Colors.black.withValues(alpha: 0.24),
                    ],
                  ),
                ),
              ),
              if (isVideo)
                Center(
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.52),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
              if (isVideo)
                Positioned(
                  left: 7,
                  bottom: 8,
                  child: _DurationBadge(text: post.durationLabel),
                )
              else
                const Positioned(
                  right: 7,
                  top: 7,
                  child: Icon(
                    Icons.collections_rounded,
                    color: Colors.white,
                    size: 19,
                  ),
                ),
              Positioned(
                right: 7,
                bottom: 8,
                child: _StatusBadge(status: post.statusInfo),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PostThumbnail extends StatelessWidget {
  final MyFeedPost post;
  const _PostThumbnail({required this.post});

  @override
  Widget build(BuildContext context) {
    final thumbnail = post.thumbnailUrl;
    final imageUrl =
        thumbnail != null && thumbnail.trim().isNotEmpty ? thumbnail : null;

    if (imageUrl == null) {
      return const _PostThumbnailFallback();
    }

    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 180),
      placeholder: (_, __) => const _PostThumbnailFallback(),
      errorWidget: (_, __, ___) => const _PostThumbnailFallback(),
    );
  }
}

class _PostThumbnailFallback extends StatelessWidget {
  const _PostThumbnailFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEAF5FF), Color(0xFFDCEBFF)],
        ),
      ),
      child: const Center(
        child: Icon(
          Icons.photo_library_rounded,
          color: Color(0xFF7AA8E8),
          size: 28,
        ),
      ),
    );
  }
}

class _DurationBadge extends StatelessWidget {
  final String text;
  const _DurationBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.66),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final MyFeedPostStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final style = switch (status) {
      MyFeedPostStatus.active => const _StatusStyle(
          label: 'Tayang',
          bg: Color(0xFFE5FFF0),
          fg: Color(0xFF047857),
          border: Color(0xFFB7F3D0),
        ),
      MyFeedPostStatus.pending => const _StatusStyle(
          label: 'Review',
          bg: Color(0xFFFFF7E6),
          fg: Color(0xFFB45309),
          border: Color(0xFFFED7AA),
        ),
      MyFeedPostStatus.rejected => const _StatusStyle(
          label: 'Ditolak',
          bg: Color(0xFFFFEBEE),
          fg: Color(0xFFEF4444),
          border: Color(0xFFFECACA),
        ),
      MyFeedPostStatus.unknown => const _StatusStyle(
          label: '-',
          bg: Color(0xFFEFF2F6),
          fg: Color(0xFF64748B),
          border: Color(0xFFDCE3EC),
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: style.bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: style.border),
      ),
      child: Text(
        style.label,
        style: TextStyle(
          color: style.fg,
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _StatusStyle {
  final String label;
  final Color bg;
  final Color fg;
  final Color border;

  const _StatusStyle({
    required this.label,
    required this.bg,
    required this.fg,
    required this.border,
  });
}

class _EmptyPostsCard extends StatelessWidget {
  final VoidCallback onUpload;
  const _EmptyPostsCard({required this.onUpload});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _softBorder),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 86,
            height: 86,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFFEAF5FF), Color(0xFFDCEBFF)],
              ),
            ),
            child: const Icon(
              Icons.add_a_photo_rounded,
              color: _brandBlue,
              size: 36,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Belum ada cerita di Feed kamu',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _deepNavy,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Bagikan foto atau video hewan peliharaanmu agar momen serunya bisa tampil di Feed Natalo.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _mutedText,
              fontSize: 14,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: onUpload,
              icon: const Icon(Icons.add_rounded, size: 21),
              label: const Text('+ Buat Postingan'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _brandBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilteredEmptyCard extends StatelessWidget {
  final String label;
  const _FilteredEmptyCard({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _softBorder),
      ),
      child: Text(
        'Belum ada postingan untuk filter $label.',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: _mutedText,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

bool _isVideoPost(MyFeedPost post) {
  if (post.durationSec > 0) return true;
  final url = post.mediaUrl.toLowerCase();
  return url.endsWith('.mp4') ||
      url.endsWith('.mov') ||
      url.endsWith('.m4v') ||
      url.endsWith('.webm') ||
      url.contains('/video/');
}

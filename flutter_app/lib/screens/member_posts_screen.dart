import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/my_feed_post.dart';
import '../services/feed_service.dart';
import '../utils/haptics.dart';

const _brandBlue = Color(0xFF0B7FEA);

/// "Postingan Saya" screen — list video user-generated content yang user
/// upload ke Feed. Match PWA `app/akun/postingan-saya/page.tsx`:
/// - Custom title centered "Postingan Saya"
/// - 4 tab filter: Semua / Menunggu Review / Tayang / Ditolak
/// - Info banner: "Postingan kamu hanya bisa dilihat oleh kamu..."
/// - List post cards dengan thumbnail + judul + tanggal + status pill + like/comment/share counts
/// - Empty state dengan icon play + "Upload Video" CTA
/// - Bottom sticky "Upload Video +" button (kalau ada posts)
class MemberPostsScreen extends StatefulWidget {
  const MemberPostsScreen({super.key});

  @override
  State<MemberPostsScreen> createState() => _MemberPostsScreenState();
}

class _MemberPostsScreenState extends State<MemberPostsScreen> {
  int _tabIndex = 0;
  List<MyFeedPost> _posts = const [];
  bool _loading = true;

  static const _tabs = [
    _PostsTab(label: 'Semua', filter: 'all'),
    _PostsTab(label: 'Menunggu Review', filter: 'pending'),
    _PostsTab(label: 'Tayang', filter: 'active'),
    _PostsTab(label: 'Ditolak', filter: 'rejected'),
  ];

  @override
  void initState() {
    super.initState();
    _loadPosts();
  }

  Future<void> _loadPosts() async {
    setState(() => _loading = true);
    final result =
        await feedService.fetchMyPosts(filter: _tabs[_tabIndex].filter);
    if (!mounted) return;
    setState(() {
      _posts = result;
      _loading = false;
    });
  }

  void _onTabChanged(int index) {
    if (_tabIndex == index) return;
    AppHaptics.tap();
    setState(() => _tabIndex = index);
    _loadPosts();
  }

  void _openDetail(MyFeedPost post) {
    AppHaptics.tap();
    Navigator.pushNamed(context, '/member/postingan-detail', arguments: post)
        .then((_) => _loadPosts());
  }

  void _openUpload() {
    AppHaptics.tap();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
            'Upload video tersedia di web. Buka natalopetshop.com untuk lanjut upload.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8FAFC),
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: const Color(0xFFF8FAFC),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF17202A)),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text(
          'Postingan Saya',
          style: TextStyle(
            color: Color(0xFF17202A),
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          _PostsTabBar(
            tabs: _tabs,
            activeIndex: _tabIndex,
            onTap: _onTabChanged,
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadPosts,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                children: [
                  // Info banner — match PWA copy persis
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 28,
                          width: 28,
                          decoration: const BoxDecoration(
                            color: Color(0xFFEAF5FF),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.info_outline_rounded,
                            color: _brandBlue,
                            size: 16,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Postingan kamu hanya bisa dilihat oleh kamu. Jika disetujui, video akan otomatis tampil di Feed.',
                            style: TextStyle(
                              color: Color(0xFF334155),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: SizedBox(
                          height: 28,
                          width: 28,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  else if (_posts.isEmpty)
                    _EmptyPostsCard(onUpload: _openUpload)
                  else
                    ..._posts.map((post) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _PostCard(
                            post: post,
                            onTap: () => _openDetail(post),
                          ),
                        )),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _posts.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: ElevatedButton.icon(
                  onPressed: _openUpload,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Upload Video'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _brandBlue,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(52),
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
            ),
    );
  }
}

class _PostsTab {
  final String label;
  final String filter;
  const _PostsTab({required this.label, required this.filter});
}

class _PostsTabBar extends StatelessWidget {
  final List<_PostsTab> tabs;
  final int activeIndex;
  final ValueChanged<int> onTap;

  const _PostsTabBar({
    required this.tabs,
    required this.activeIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final active = index == activeIndex;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => onTap(index),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: active ? _brandBlue : Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: active ? _brandBlue : const Color(0xFFE2E8F0),
                  ),
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: _brandBlue.withValues(alpha: 0.22),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    tabs[index].label,
                    style: TextStyle(
                      color: active ? Colors.white : const Color(0xFF6B7280),
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  final MyFeedPost post;
  final VoidCallback onTap;

  const _PostCard({required this.post, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFEEF3FB)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF111111).withValues(alpha: 0.04),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Thumbnail dengan play overlay + duration badge ──
              SizedBox(
                height: 92,
                width: 92,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (post.thumbnailUrl != null)
                        CachedNetworkImage(
                          imageUrl: post.thumbnailUrl!,
                          fit: BoxFit.cover,
                          fadeInDuration: const Duration(milliseconds: 180),
                          placeholder: (_, __) =>
                              const ColoredBox(color: Color(0xFFE5E7EB)),
                          errorWidget: (_, __, ___) =>
                              const ColoredBox(color: Color(0xFFE5E7EB)),
                        )
                      else
                        const ColoredBox(color: Color(0xFFE5E7EB)),
                      // Play icon center
                      Center(
                        child: Container(
                          height: 36,
                          width: 36,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                      // Duration badge bottom-left
                      Positioned(
                        left: 6,
                        bottom: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.70),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            post.durationLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // ── Info column ──
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.title?.trim().isNotEmpty == true
                          ? post.title!
                          : 'Tanpa judul',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF111111),
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDate(post.createdAt),
                      style: const TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _StatusPill(status: post.statusInfo),
                    if (post.statusInfo == MyFeedPostStatus.active) ...[
                      const SizedBox(height: 4),
                      Text(
                        post.statusInfo.description,
                        style: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    // ── Counters: like, comment, share ──
                    Row(
                      children: [
                        _Counter(
                          icon: Icons.favorite_border_rounded,
                          value: post.likeCount,
                        ),
                        const SizedBox(width: 14),
                        _Counter(
                          icon: Icons.chat_bubble_outline_rounded,
                          value: post.commentCount,
                        ),
                        const SizedBox(width: 14),
                        _Counter(
                          icon: Icons.share_outlined,
                          value: post.shareCount,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final MyFeedPostStatus status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    late final Color bg;
    late final Color fg;
    switch (status) {
      case MyFeedPostStatus.active:
        bg = const Color(0xFFD1FAE5);
        fg = const Color(0xFF047857);
        break;
      case MyFeedPostStatus.rejected:
        bg = const Color(0xFFFEE2E2);
        fg = const Color(0xFFEF4444);
        break;
      case MyFeedPostStatus.pending:
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFF92400E);
        break;
      case MyFeedPostStatus.unknown:
        bg = const Color(0xFFEFF2F6);
        fg = const Color(0xFF6B7280);
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: fg,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _Counter extends StatelessWidget {
  final IconData icon;
  final int value;
  const _Counter({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: const Color(0xFF9CA3AF)),
        const SizedBox(width: 4),
        Text(
          '$value',
          style: const TextStyle(
            color: Color(0xFF6B7280),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _EmptyPostsCard extends StatelessWidget {
  final VoidCallback onUpload;
  const _EmptyPostsCard({required this.onUpload});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          Container(
            height: 64,
            width: 64,
            decoration: const BoxDecoration(
              color: Color(0xFFEAF5FF),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.play_circle_outline_rounded,
              color: _brandBlue,
              size: 32,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Belum ada postingan',
            style: TextStyle(
              color: Color(0xFF111111),
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Upload video pertama kamu ke NL Feed.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onUpload,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Upload Video'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _brandBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];
  final hh = date.hour.toString().padLeft(2, '0');
  final mm = date.minute.toString().padLeft(2, '0');
  return '${date.day} ${months[date.month - 1]} ${date.year}, $hh:$mm';
}

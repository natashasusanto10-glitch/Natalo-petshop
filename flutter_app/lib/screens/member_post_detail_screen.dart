import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../models/my_feed_post.dart';
import '../theme/natalo_colors.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import '../widgets/app_toast.dart';

/// Member Post Detail — preview video thumbnail + caption + stats.
/// Full video playback masuk ke /feed dengan post highlighted.
class MemberPostDetailScreen extends StatelessWidget {
  final MyFeedPost post;

  const MemberPostDetailScreen({super.key, required this.post});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFF),
      appBar: AppBar(
        title: const Text('Detail Postingan'),
        backgroundColor: const Color(0xFFF7FAFF),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit caption',
            onPressed: () {
              AppHaptics.tap();
              Navigator.pushNamed(
                context,
                '/member/post-edit',
                arguments: post,
              );
            },
          ),
        ],
      ),
      body: ListView(
        children: [
          // Video thumbnail / preview
          AspectRatio(
            aspectRatio: post.aspectWidth / post.aspectHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (post.thumbnailUrl != null && post.thumbnailUrl!.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: post.thumbnailUrl!,
                    fit: BoxFit.cover,
                    fadeInDuration: const Duration(milliseconds: 220),
                    fadeOutDuration: const Duration(milliseconds: 120),
                    fadeInCurve: Curves.easeOut,
                    placeholder: (_, __) => Shimmer.fromColors(
                      baseColor: const Color(0xFF1F2937),
                      highlightColor: const Color(0xFF374151),
                      child: Container(color: const Color(0xFF1F2937)),
                    ),
                    errorWidget: (_, __, ___) => _placeholderThumb(),
                  )
                else
                  _placeholderThumb(),
                // Play overlay
                Center(
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StatusBadge(status: post.status),
                if (post.status == 'REJECTED' &&
                    post.rejectionReason != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: Color(0xFFEF4444),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Alasan ditolak: ${post.rejectionReason}',
                            style: const TextStyle(
                              color: Color(0xFFB91C1C),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                if (post.caption != null && post.caption!.isNotEmpty) ...[
                  Text(
                    post.caption!,
                    style: const TextStyle(
                      color: NataloColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                // Stats
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFDDE8F8)),
                  ),
                  child: Row(
                    children: [
                      _Stat(
                        icon: Icons.visibility_outlined,
                        label: 'Dilihat',
                        value: post.viewCount.toString(),
                      ),
                      _Divider(),
                      _Stat(
                        icon: Icons.favorite_border_rounded,
                        label: 'Like',
                        value: post.likeCount.toString(),
                      ),
                      _Divider(),
                      _Stat(
                        icon: Icons.chat_bubble_outline_rounded,
                        label: 'Komentar',
                        value: post.commentCount.toString(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.schedule_rounded,
                    color: NataloColors.primary,
                    size: 20,
                  ),
                  title: const Text(
                    'Diposting',
                    style: TextStyle(
                      color: NataloColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    formatTanggal(post.createdAt, withTime: true),
                    style: const TextStyle(
                      color: NataloColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (post.productIds.isNotEmpty)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.local_offer_outlined,
                      color: NataloColors.primary,
                      size: 20,
                    ),
                    title: const Text(
                      'Produk Ditag',
                      style: TextStyle(
                        color: NataloColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      '${post.productIds.length} produk',
                      style: const TextStyle(
                        color: NataloColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          AppHaptics.tap();
                          AppToast.show(
                            context,
                            'Hapus postingan sementara via PWA web.',
                          );
                        },
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          color: NataloColors.danger,
                        ),
                        label: const Text(
                          'Hapus',
                          style: TextStyle(color: NataloColors.danger),
                        ),
                        style: OutlinedButton.styleFrom(
                          side:
                              const BorderSide(color: NataloColors.danger),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          AppHaptics.tap();
                          Navigator.pushReplacementNamed(context, '/feed');
                        },
                        icon: const Icon(Icons.play_circle_outline_rounded),
                        label: const Text('Lihat di Feed'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholderThumb() {
    return Container(
      color: const Color(0xFF1F2937),
      child: const Center(
        child: Icon(
          Icons.video_collection_outlined,
          color: Colors.white24,
          size: 80,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    String label;
    IconData icon;

    switch (status.toUpperCase()) {
      case 'APPROVED':
      case 'PUBLISHED':
        bg = const Color(0xFFD1FAE5);
        fg = const Color(0xFF16A34A);
        label = 'Sudah Tayang';
        icon = Icons.check_circle_rounded;
        break;
      case 'REJECTED':
        bg = const Color(0xFFFEE2E2);
        fg = const Color(0xFFEF4444);
        label = 'Ditolak';
        icon = Icons.cancel_rounded;
        break;
      case 'PENDING_REVIEW':
      default:
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFFD97706);
        label = 'Menunggu Review';
        icon = Icons.schedule_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: fg, size: 14),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _Stat({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 20, color: NataloColors.primary),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: NataloColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: NataloColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 36,
      color: const Color(0xFFE5EAF3),
    );
  }
}

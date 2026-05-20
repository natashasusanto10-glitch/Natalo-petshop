import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:video_player/video_player.dart';

import '../models/my_feed_post.dart';
import '../theme/natalo_colors.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import '../widgets/app_toast.dart';

/// Member Post Detail — preview media asli sesuai tipe postingan.
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
          _PostMediaPreview(post: post),
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
                          side: const BorderSide(color: NataloColors.danger),
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
}

class _PostMediaPreview extends StatelessWidget {
  final MyFeedPost post;

  const _PostMediaPreview({required this.post});

  @override
  Widget build(BuildContext context) {
    final aspectRatio = _safeAspectRatio(post.aspectWidth, post.aspectHeight);

    return AspectRatio(
      aspectRatio: aspectRatio,
      child: switch (post.type) {
        MyFeedPostType.video => _VideoPreviewSurface(
            mediaUrl: post.previewMediaUrl,
            thumbnailUrl: post.thumbnailUrl,
            aspectRatio: aspectRatio,
          ),
        MyFeedPostType.carousel => _CarouselPreviewSurface(
            post: post,
            aspectRatio: aspectRatio,
          ),
        MyFeedPostType.photo => _ImagePreviewSurface(
            imageUrl: post.previewMediaUrl,
            placeholderIcon: Icons.image_outlined,
          ),
      },
    );
  }
}

class _CarouselPreviewSurface extends StatefulWidget {
  final MyFeedPost post;
  final double aspectRatio;

  const _CarouselPreviewSurface({
    required this.post,
    required this.aspectRatio,
  });

  @override
  State<_CarouselPreviewSurface> createState() =>
      _CarouselPreviewSurfaceState();
}

class _CarouselPreviewSurfaceState extends State<_CarouselPreviewSurface> {
  int _index = 0;

  List<MyFeedMediaItem> get _items {
    if (widget.post.mediaItems.isNotEmpty) return widget.post.mediaItems;
    if (widget.post.previewMediaUrl.isEmpty) return const [];
    return [
      MyFeedMediaItem(
        id: '${widget.post.id}-fallback',
        mediaUrl: widget.post.previewMediaUrl,
        thumbnailUrl: widget.post.thumbnailUrl,
        mediaType:
            widget.post.isVideo ? MyFeedMediaType.video : MyFeedMediaType.image,
        durationSeconds: widget.post.durationSec,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items.isEmpty) {
      return const _MediaPlaceholder(icon: Icons.collections_outlined);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          itemCount: items.length,
          onPageChanged: (index) => setState(() => _index = index),
          itemBuilder: (context, index) {
            final item = items[index];
            if (item.mediaType == MyFeedMediaType.video) {
              return _VideoPreviewSurface(
                mediaUrl: item.mediaUrl,
                thumbnailUrl: item.thumbnailUrl,
                aspectRatio: widget.aspectRatio,
              );
            }
            return _ImagePreviewSurface(
              imageUrl: item.mediaUrl,
              placeholderIcon: Icons.image_outlined,
            );
          },
        ),
        Positioned(
          top: 12,
          right: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.46),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${_index + 1}/${items.length}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _VideoPreviewSurface extends StatefulWidget {
  final String mediaUrl;
  final String? thumbnailUrl;
  final double aspectRatio;

  const _VideoPreviewSurface({
    required this.mediaUrl,
    required this.thumbnailUrl,
    required this.aspectRatio,
  });

  @override
  State<_VideoPreviewSurface> createState() => _VideoPreviewSurfaceState();
}

class _VideoPreviewSurfaceState extends State<_VideoPreviewSurface> {
  VideoPlayerController? _controller;
  bool _initializing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void didUpdateWidget(covariant _VideoPreviewSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mediaUrl != widget.mediaUrl) {
      _disposeController();
      _initialize();
    }
  }

  Future<void> _initialize() async {
    if (widget.mediaUrl.trim().isEmpty) {
      setState(() => _error = 'Video tidak tersedia');
      return;
    }

    setState(() {
      _initializing = true;
      _error = null;
    });

    final controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.mediaUrl),
    );
    _controller = controller;

    try {
      await controller.initialize();
      if (!mounted || _controller != controller) return;
      setState(() {
        _initializing = false;
      });
    } catch (_) {
      await controller.dispose();
      if (!mounted || _controller != controller) return;
      setState(() {
        _controller = null;
        _initializing = false;
        _error = 'Video belum bisa diputar';
      });
    }
  }

  Future<void> _disposeController() async {
    final controller = _controller;
    _controller = null;
    await controller?.dispose();
  }

  void _togglePlay() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (controller.value.isPlaying) {
      controller.pause();
    } else {
      controller.play();
    }
    setState(() {});
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;
    final isPlaying = ready && controller.value.isPlaying;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _togglePlay,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: Colors.black),
          if (ready)
            Center(
              child: AspectRatio(
                aspectRatio: controller.value.aspectRatio > 0
                    ? controller.value.aspectRatio
                    : widget.aspectRatio,
                child: VideoPlayer(controller),
              ),
            )
          else if (widget.thumbnailUrl != null &&
              widget.thumbnailUrl!.trim().isNotEmpty)
            _ImagePreviewSurface(
              imageUrl: widget.thumbnailUrl!,
              placeholderIcon: Icons.video_collection_outlined,
            )
          else
            const _MediaPlaceholder(icon: Icons.video_collection_outlined),
          if (_initializing)
            const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Colors.white,
                ),
              ),
            ),
          if (_error != null)
            Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          if (!isPlaying && _error == null)
            Center(
              child: Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 44,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ImagePreviewSurface extends StatelessWidget {
  final String imageUrl;
  final IconData placeholderIcon;

  const _ImagePreviewSurface({
    required this.imageUrl,
    required this.placeholderIcon,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl.trim().isEmpty) {
      return _MediaPlaceholder(icon: placeholderIcon);
    }

    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.contain,
        fadeInDuration: const Duration(milliseconds: 220),
        fadeOutDuration: const Duration(milliseconds: 120),
        fadeInCurve: Curves.easeOut,
        placeholder: (_, __) => Shimmer.fromColors(
          baseColor: const Color(0xFF1F2937),
          highlightColor: const Color(0xFF374151),
          child: Container(color: const Color(0xFF1F2937)),
        ),
        errorWidget: (_, __, ___) => _MediaPlaceholder(icon: placeholderIcon),
      ),
    );
  }
}

class _MediaPlaceholder extends StatelessWidget {
  final IconData icon;

  const _MediaPlaceholder({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF111827),
      child: Center(
        child: Icon(
          icon,
          color: Colors.white24,
          size: 78,
        ),
      ),
    );
  }
}

double _safeAspectRatio(int width, int height) {
  if (width <= 0 || height <= 0) return 9 / 16;
  final ratio = width / height;
  if (ratio.isNaN || ratio.isInfinite || ratio <= 0) return 9 / 16;
  return ratio.clamp(0.45, 1.8);
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

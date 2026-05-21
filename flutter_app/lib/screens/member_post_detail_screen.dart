import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:video_player/video_player.dart';

import '../models/my_feed_post.dart';
import '../state/member_store.dart';
import '../theme/natalo_colors.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import '../widgets/profile_avatar.dart';

/// Detail postingan member dengan interaksi dasar seperti feed/gallery.
class MemberPostDetailScreen extends StatefulWidget {
  final MyFeedPost post;
  final List<MyFeedPost>? posts;
  final int initialIndex;

  const MemberPostDetailScreen({
    super.key,
    required this.post,
    this.posts,
    this.initialIndex = 0,
  });

  @override
  State<MemberPostDetailScreen> createState() => _MemberPostDetailScreenState();
}

class _MemberPostDetailScreenState extends State<MemberPostDetailScreen> {
  late final PageController _pageController;

  List<MyFeedPost> get _posts {
    final source = widget.posts;
    if (source == null || source.isEmpty) return [widget.post];
    return source;
  }

  String get _memberName {
    final name = memberStore.profile?.name.trim();
    return name == null || name.isEmpty ? 'Member Natalo' : name;
  }

  @override
  void initState() {
    super.initState();
    final maxIndex = _posts.length - 1;
    _pageController = PageController(
      initialPage: widget.initialIndex.clamp(0, maxIndex),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.white,
        leading: IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: NataloColors.textPrimary,
          ),
        ),
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Postingan',
              style: TextStyle(
                color: NataloColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w900,
                height: 1.1,
              ),
            ),
            Text(
              _memberName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: NataloColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
      body: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        itemCount: _posts.length,
        itemBuilder: (context, index) {
          return _MemberPostDetailItem(
            post: _posts[index],
            memberName: _memberName,
          );
        },
      ),
    );
  }
}

class _MemberPostDetailItem extends StatelessWidget {
  final MyFeedPost post;
  final String memberName;

  const _MemberPostDetailItem({
    required this.post,
    required this.memberName,
  });

  @override
  Widget build(BuildContext context) {
    final profile = memberStore.profile;
    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Row(
            children: [
              ProfileAvatar(
                initial: profile?.initial ?? 'N',
                imageUrl: profile?.profilePhotoUrl,
                size: 42,
                fontSize: 17,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  memberName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: NataloColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => AppHaptics.tap(),
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.more_horiz_rounded,
                  color: NataloColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: _PostMediaPreview(post: post),
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _PostActionRow(post: post),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _LikedByLine(memberName: memberName, post: post),
        ),
        const SizedBox(height: 7),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            formatTanggal(post.createdAt),
            style: const TextStyle(
              color: NataloColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (post.statusInfo == MyFeedPostStatus.pending ||
            post.statusInfo == MyFeedPostStatus.rejected) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _PostReviewNotice(post: post),
          ),
        ],
        const SizedBox(height: 20),
        const Divider(height: 1, color: Color(0xFFE5EAF2)),
      ],
    );
  }
}

class _PostActionRow extends StatelessWidget {
  final MyFeedPost post;

  const _PostActionRow({required this.post});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _PostActionButton(
          icon: Icons.favorite_border_rounded,
          semanticLabel: 'Like',
          onTap: () => AppHaptics.tap(),
        ),
        _PostActionButton(
          icon: Icons.chat_bubble_outline_rounded,
          semanticLabel: 'Comment',
          onTap: () => AppHaptics.tap(),
        ),
        _PostActionButton(
          icon: Icons.send_outlined,
          semanticLabel: 'Share',
          onTap: () => AppHaptics.tap(),
        ),
      ],
    );
  }
}

class _PostActionButton extends StatelessWidget {
  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;

  const _PostActionButton({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      button: true,
      child: InkResponse(
        onTap: onTap,
        radius: 26,
        child: Padding(
          padding: const EdgeInsets.only(right: 18, top: 6, bottom: 6),
          child: Icon(
            icon,
            color: NataloColors.textPrimary,
            size: 28,
          ),
        ),
      ),
    );
  }
}

class _LikedByLine extends StatelessWidget {
  final String memberName;
  final MyFeedPost post;

  const _LikedByLine({
    required this.memberName,
    required this.post,
  });

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          const TextSpan(text: 'Disukai oleh '),
          TextSpan(
            text: post.likeCount > 0 ? memberName : memberName,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const TextSpan(text: ' dan lainnya'),
        ],
      ),
      style: const TextStyle(
        color: NataloColors.textPrimary,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _PostReviewNotice extends StatelessWidget {
  final MyFeedPost post;

  const _PostReviewNotice({required this.post});

  @override
  Widget build(BuildContext context) {
    final rejected = post.statusInfo == MyFeedPostStatus.rejected;
    final bg = rejected ? const Color(0xFFFEF2F2) : const Color(0xFFFFF7E6);
    final fg = rejected ? const Color(0xFFDC2626) : const Color(0xFFB45309);
    final label = rejected ? 'Ditolak' : 'Menunggu';
    final text = rejected
        ? (post.rejectionReason?.trim().isNotEmpty == true
            ? 'Postingan ditolak: ${post.rejectionReason}'
            : 'Postingan ditolak.')
        : 'Postingan sedang diperiksa admin.';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: fg.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(
            rejected ? Icons.cancel_rounded : Icons.schedule_rounded,
            color: fg,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: NataloColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
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

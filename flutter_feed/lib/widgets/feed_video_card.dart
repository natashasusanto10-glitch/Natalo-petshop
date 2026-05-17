import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:haptic_feedback/haptic_feedback.dart';
import 'package:share_plus/share_plus.dart';

import '../models/feed_post.dart';
import '../state/feed_provider.dart';
import 'comment_sheet.dart';
import 'feed_video_player.dart';

// Mirror of components/feed/FeedVideoCard.tsx.
//
// Layout:
//   - Full-screen video (Stack: video bg + engagement rail right + caption bottom)
//   - Engagement rail: like, comment, share (icons + counts)
//   - Bottom caption: gradient overlay + author + description
//   - Double-tap heart animation (Instagram pattern: only SETS liked, never unsets)
//
// Web uses absolute positioning with calc(var(--natalo-bottom-nav-height)+...);
// here we just use Stack with explicit padding for SafeArea + bottom nav.

class FeedVideoCard extends ConsumerStatefulWidget {
  final FeedPost post;
  final bool isActive;

  const FeedVideoCard({super.key, required this.post, required this.isActive});

  @override
  ConsumerState<FeedVideoCard> createState() => _FeedVideoCardState();
}

class _FeedVideoCardState extends ConsumerState<FeedVideoCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _heartCtrl;
  bool _showHeart = false;

  @override
  void initState() {
    super.initState();
    _heartCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..addStatusListener((s) {
        if (s == AnimationStatus.completed) {
          if (mounted) setState(() => _showHeart = false);
          _heartCtrl.reset();
        }
      });
  }

  @override
  void dispose() {
    _heartCtrl.dispose();
    super.dispose();
  }

  void _onDoubleTap() {
    Haptics.vibrate(HapticsType.light);
    setState(() => _showHeart = true);
    _heartCtrl.forward();
    // Instagram pattern: double-tap only SETS liked, never unsets.
    if (!widget.post.viewerLiked) {
      ref.read(feedListProvider.notifier).toggleLike(widget.post.id);
    }
  }

  Future<void> _onLikeTap() async {
    Haptics.vibrate(HapticsType.light);
    await ref.read(feedListProvider.notifier).toggleLike(widget.post.id);
  }

  Future<void> _onShareTap() async {
    Haptics.vibrate(HapticsType.medium);
    final url = 'https://natalo.id/feed/${widget.post.id}';
    final result = await Share.share(url, subject: widget.post.title ?? '');
    if (result.status == ShareResultStatus.success) {
      await ref.read(feedListProvider.notifier).registerShare(widget.post.id);
    }
  }

  void _onCommentTap() {
    Haptics.vibrate(HapticsType.selection);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => CommentSheet(postId: widget.post.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final mq = MediaQuery.of(context);

    return Stack(
      fit: StackFit.expand,
      children: [
        // Background — full-screen video player
        Positioned.fill(
          child: FeedVideoPlayer(
            post: post,
            isActive: widget.isActive,
            onDoubleTap: _onDoubleTap,
          ),
        ),

        // Bottom caption overlay + gradient
        Positioned(
          left: 16,
          right: 76, // avoid action rail
          bottom: mq.padding.bottom + 24,
          child: Container(
            padding: const EdgeInsets.only(top: 64),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0xCC000000)],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '@${post.authorName ?? "user"}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                if (post.description != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    post.description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
        ),

        // Right engagement rail
        Positioned(
          right: 12,
          bottom: mq.padding.bottom + 96,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _RailButton(
                icon: post.viewerLiked ? Icons.favorite : Icons.favorite_border,
                label: _fmtCount(post.likeCount),
                color: post.viewerLiked ? Colors.red : Colors.white,
                onTap: _onLikeTap,
              ),
              const SizedBox(height: 20),
              _RailButton(
                icon: Icons.mode_comment_outlined,
                label: _fmtCount(post.commentCount),
                color: Colors.white,
                onTap: _onCommentTap,
              ),
              const SizedBox(height: 20),
              _RailButton(
                icon: Icons.share_outlined,
                label: _fmtCount(post.shareCount),
                color: Colors.white,
                onTap: _onShareTap,
              ),
            ],
          ),
        ),

        // Double-tap heart burst animation
        if (_showHeart)
          Center(
            child: ScaleTransition(
              scale: TweenSequence<double>([
                TweenSequenceItem(tween: Tween(begin: 0, end: 1.4), weight: 30),
                TweenSequenceItem(tween: Tween(begin: 1.4, end: 1), weight: 30),
                TweenSequenceItem(tween: Tween(begin: 1, end: 0), weight: 40),
              ]).animate(_heartCtrl),
              child: const Icon(Icons.favorite,
                  color: Colors.white, size: 120, shadows: [
                Shadow(color: Colors.black54, blurRadius: 12),
              ]),
            ),
          ),
      ],
    );
  }
}

class _RailButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _RailButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              )),
        ],
      ),
    );
  }
}

String _fmtCount(int n) {
  if (n < 1000) return n.toString();
  if (n < 10000) return '${(n / 1000).toStringAsFixed(1)}rb';
  if (n < 1000000) return '${(n / 1000).round()}rb';
  return '${(n / 1000000).toStringAsFixed(1)}jt';
}

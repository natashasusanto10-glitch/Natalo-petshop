import 'package:flutter/material.dart';
import '../models/feed_post.dart';
import 'feed_user_tag_pill.dart';

/// Badge ikon orang (siluet putih, lingkaran semi-transparan) pojok
/// kiri-bawah — selalu tampil kalau ada tag (tanpa auto-fade, spec §3).
class FeedTaggedBadge extends StatelessWidget {
  final VoidCallback? onTap;

  const FeedTaggedBadge({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.person, size: 16, color: Colors.white),
      ),
    );
  }
}

/// Layer pill untuk slide foto aktif. visible di-toggle parent; pill
/// muncul pop-fade easeOutCubic. onTapUser → parent navigasi/aksi.
class FeedTaggedUsersOverlay extends StatelessWidget {
  final List<FeedTaggedUser> tags;
  final bool visible;
  final Size photoSize;
  final ValueChanged<FeedTaggedUser> onTapUser;

  const FeedTaggedUsersOverlay({
    super.key,
    required this.tags,
    required this.visible,
    required this.photoSize,
    required this.onTapUser,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible || tags.isEmpty) return const SizedBox.shrink();
    return Stack(
      children: [
        for (final tag in tags)
          if (tag.x != null && tag.y != null) _positionedPill(context, tag),
      ],
    );
  }

  Widget _positionedPill(BuildContext context, FeedTaggedUser tag) {
    final username = tag.username ?? tag.name;
    final painter = TextPainter(
      text: TextSpan(
        text: username,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final pillSize = Size(painter.width + 20, 27);
    final placement = placeTagPill(
      anchor: Offset(tag.x! * photoSize.width, tag.y! * photoSize.height),
      pillSize: pillSize,
      photoSize: photoSize,
    );
    return Positioned(
      key: ValueKey('tag-pill-${tag.userId}'),
      left: placement.topLeft.dx,
      top: placement.topLeft.dy,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.6, end: 1),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        builder: (context, v, child) => Opacity(
          opacity: v.clamp(0, 1),
          child: Transform.scale(scale: v, child: child),
        ),
        child: FeedUserTagPill(
          username: username,
          arrowBelow: placement.arrowBelow,
          onTap: () => onTapUser(tag),
        ),
      ),
    );
  }
}

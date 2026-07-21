import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../models/feed_post.dart';
import '../../../theme/natalo_text.dart';
import '../transition/post_hero.dart';

/// Video LANDSCAPE (lebih lebar dari tinggi) → letterbox di grid (video utuh,
/// bar hitam atas-bawah di dalam kotak 1:1) — paritas IG (lihat screenshot
/// device: grid IG letterbox video landscape, bukan cover-crop). Foto/
/// carousel dan video portrait/persegi tetap cover-crop penuh (tak berubah).
bool gridShowsLetterbox(FeedPost post) {
  if (!post.isVideo) return false;
  final w = post.aspectWidthInt;
  final h = post.aspectHeightInt;
  return w > h;
}

/// Tile grid foto/video 1:1 full-bleed — dipakai bersama halaman Postingan
/// Saya, profil, dan Postingan Tersimpan. Badge tipe media (video/carousel)
/// selalu tampil; badge status (Menunggu/Ditolak) hanya untuk pemilik post
/// (`showStatusBadge: true`).
class GalleryPostTile extends StatelessWidget {
  final FeedPost post;
  final VoidCallback onTap;
  final VoidCallback? onTapDown;
  final VoidCallback? onTapCancel;
  final bool showStatusBadge;

  /// Scope untuk PostHero — bila non-null, thumbnail dibungkus Hero
  /// bertag `post-hero/<heroScope>/<post.id>` supaya bisa terbang ke
  /// viewer (lihat `post_hero.dart`). Null → tidak ada Hero (caller lama
  /// tak terpengaruh).
  final String? heroScope;

  const GalleryPostTile({
    required Key key,
    required this.post,
    required this.onTap,
    this.onTapDown,
    this.onTapCancel,
    this.showStatusBadge = true,
    this.heroScope,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // `key` (the GlobalKey passed to this widget) is not re-attached here:
    // GlobalKey.currentContext resolves through `Element.findRenderObject()`,
    // which walks down the child tree to the nearest RenderObjectElement —
    // so it already finds this RepaintBoundary's RenderRepaintBoundary
    // without needing a second, conflicting key on the same GlobalKey.
    return RepaintBoundary(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onTapDown: (_) => onTapDown?.call(),
          onTapCancel: onTapCancel,
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                heroScope != null
                    ? PostHero(
                        scope: heroScope!,
                        postId: post.id,
                        child: _PostThumbnail(post: post),
                      )
                    : _PostThumbnail(post: post),
                if (post.isVideo)
                  const Positioned(
                    right: 7,
                    top: 7,
                    child: _PostMediaTypeIcon(icon: Icons.play_arrow_rounded),
                  )
                else if (post.isCarousel || post.mediaItems.length > 1)
                  const Positioned(
                    right: 7,
                    top: 7,
                    child: _PostMediaTypeIcon(icon: Icons.collections_rounded),
                  ),
                if (showStatusBadge)
                  Positioned(
                    left: 7,
                    bottom: 7,
                    child: _StatusBadge(status: post.statusInfo),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PostThumbnail extends StatelessWidget {
  final FeedPost post;
  const _PostThumbnail({required this.post});

  @override
  Widget build(BuildContext context) {
    final imageUrl = _thumbnailUrlForPost(post);
    if (imageUrl == null) return const _PostThumbnailFallback();

    final letterbox = gridShowsLetterbox(post);
    final image = CachedNetworkImage(
      imageUrl: imageUrl,
      fit: letterbox ? BoxFit.contain : BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 180),
      placeholder: (_, __) => const _PostThumbnailFallback(),
      errorWidget: (_, __, ___) => const _PostThumbnailFallback(),
    );
    // Latar hitam cuma kelihatan di sisa ruang letterbox — cover-crop
    // (non-letterbox) selalu penuhi seluruh tile, jadi aman dibungkus sama.
    return ColoredBox(color: Colors.black, child: image);
  }
}

String? _thumbnailUrlForPost(FeedPost post) {
  final thumbnail = post.thumbnailUrl;
  if (thumbnail != null && thumbnail.trim().isNotEmpty) return thumbnail.trim();
  for (final item in post.mediaItems) {
    final itemThumb = item.thumbnailUrl;
    if (itemThumb != null && itemThumb.trim().isNotEmpty) {
      return itemThumb.trim();
    }
    if (item.mediaUrl.trim().isNotEmpty) return item.mediaUrl.trim();
  }
  final preview = post.previewMediaUrl;
  return preview.trim().isNotEmpty ? preview.trim() : null;
}

class _PostThumbnailFallback extends StatelessWidget {
  const _PostThumbnailFallback();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.photo_library_rounded,
          color: cs.onSurfaceVariant,
          size: 28,
        ),
      ),
    );
  }
}

class _PostMediaTypeIcon extends StatelessWidget {
  final IconData icon;
  const _PostMediaTypeIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 27,
      height: 27,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.72)),
      ),
      child: Icon(
        icon,
        color: Colors.white,
        size: 17,
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final FeedPostStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final style = switch (status) {
      FeedPostStatus.pending => const _StatusStyle(
          label: 'Menunggu',
          bg: Color(0xFFFFF4D6),
          fg: Color(0xFFB45309),
          icon: Icons.schedule_rounded,
        ),
      FeedPostStatus.rejected => const _StatusStyle(
          label: 'Ditolak',
          bg: Color(0xFFEF4444),
          fg: Colors.white,
          icon: Icons.cancel_rounded,
        ),
      FeedPostStatus.active || FeedPostStatus.unknown => null,
    };

    if (style == null) return const SizedBox.shrink();

    return Container(
      constraints: const BoxConstraints(maxWidth: 116),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: style.bg.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, color: style.fg, size: 12),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              style.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: style.fg,
                fontSize: style.label.length > 9 ? 9.2 : 10.5,
                fontWeight: NataloWeight.strong,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusStyle {
  final String label;
  final Color bg;
  final Color fg;
  final IconData icon;

  const _StatusStyle({
    required this.label,
    required this.bg,
    required this.fg,
    required this.icon,
  });
}

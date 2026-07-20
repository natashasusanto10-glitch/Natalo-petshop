import 'package:flutter/widgets.dart';

import 'post_page_zoom_geometry.dart';

/// Renders the ONE-surface Postingan full-page zoom flight: a single
/// destination subtree that is transformed and clipped from the source tile
/// geometry to the fullscreen viewport geometry, with a clean media proxy
/// crossfaded underneath during the first portion of the flight.
///
/// [destinationChild] is built exactly once (passed as the `child` of an
/// internal `AnimatedBuilder`, so animation ticks never rebuild it) and is
/// wrapped in a [RepaintBoundary]. Geometry is applied purely via [Transform]
/// and [ClipRRect] so ticks stay compositor-friendly; the proxy is painted
/// with [BoxFit.cover] inside that same animated clip.
class PostPageZoomTransition extends StatelessWidget {
  const PostPageZoomTransition({
    super.key,
    required this.progress,
    required this.tileRect,
    required this.viewportRect,
    required this.tileCornerRadius,
    required this.destinationChild,
    this.proxyImageProvider,
    this.proxyColor = const Color(0x00000000),
  });

  /// Drives the flight; 0 is source-tile geometry, 1 is fullscreen geometry.
  /// Reverse (interactive back) flights simply animate this from 1 to 0.
  final Listenable progress;

  /// Source tile rect, in root overlay coordinates.
  final Rect tileRect;

  /// Fullscreen application surface rect, in root overlay coordinates.
  final Rect viewportRect;

  /// Corner radius of the source tile at progress 0.
  final double tileCornerRadius;

  /// The complete destination content. Built exactly once.
  final Widget destinationChild;

  /// Clean media proxy image, painted with [BoxFit.cover]. When null, only
  /// [proxyColor] is shown for the proxy layer (deterministic placeholder).
  final ImageProvider<Object>? proxyImageProvider;

  /// Fallback/placeholder color for the proxy layer.
  final Color proxyColor;

  double get _progressValue {
    final listenable = progress;
    if (listenable is Animation<double>) return listenable.value;
    throw ArgumentError(
      'PostPageZoomTransition.progress must be an Animation<double> so its '
      'current value can be read on each tick.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: progress,
      builder: (context, child) {
        final frame = resolvePostPageZoomFrame(
          tileRect: tileRect,
          viewportRect: viewportRect,
          tileCornerRadius: tileCornerRadius,
          progress: _progressValue,
        );
        return ClipRRect(
          clipper: _PostPageZoomClipper(frame.clip),
          child: Transform.translate(
            offset: frame.offset,
            child: Transform.scale(
              scale: frame.scale,
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: viewportRect.width,
                height: viewportRect.height,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Opacity(
                      opacity: frame.proxyOpacity,
                      child: proxyImageProvider != null
                          ? Image(image: proxyImageProvider!, fit: BoxFit.cover)
                          : ColoredBox(color: proxyColor),
                    ),
                    Opacity(opacity: frame.destinationOpacity, child: child),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      child: RepaintBoundary(child: destinationChild),
    );
  }
}

class _PostPageZoomClipper extends CustomClipper<RRect> {
  const _PostPageZoomClipper(this.rrect);

  final RRect rrect;

  @override
  RRect getClip(Size size) => rrect;

  @override
  bool shouldReclip(covariant _PostPageZoomClipper oldClipper) =>
      oldClipper.rrect != rrect;
}

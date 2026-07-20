import 'package:flutter/widgets.dart';

import 'post_page_zoom_geometry.dart';

/// Renders the two-layer Postingan hero+chrome flight.
///
/// The destination [chromeChild] (header/caption/buttons, with its own
/// media slot left visually transparent) fades in at its final position via
/// [resolveChromeOpacity], while a separate hero layer carries the actual
/// photo/video surface ([heroMediaChild]) from the source grid tile
/// ([tileRect]) to the destination media slot ([slotRect]) via
/// [resolveHeroFrame]. The hero layer sits on top of the chrome layer and
/// fades out near the end of the flight (or near the start, when
/// [reverseHandoff] is true) so the real destination media — already
/// rendered inside [chromeChild] at its final position — can take over
/// seamlessly once the fake hero surface is gone.
///
/// [heroMediaChild] is built exactly once (passed as the `child` of an
/// internal `AnimatedBuilder`, so animation ticks never rebuild it).
/// [chromeChild] is wrapped in a [RepaintBoundary] since only its opacity
/// changes per tick, never its content.
class PostPageZoomTransition extends StatelessWidget {
  const PostPageZoomTransition({
    super.key,
    required this.progress,
    required this.tileRect,
    required this.slotRect,
    required this.mediaAspect,
    required this.tileRadius,
    required this.slotRadius,
    required this.chromeChild,
    required this.heroMediaChild,
    this.reverseHandoff = false,
  });

  /// Drives the flight; 0 is source-tile geometry (hero over the grid tile,
  /// chrome invisible), 1 is destination geometry (hero over the media
  /// slot, chrome fully visible). The widget has no notion of direction:
  /// callers drive [progress] forward (0 -> 1) or backward (1 -> 0) as
  /// needed.
  final Animation<double> progress;

  /// Source grid-tile rect, in overlay coordinates.
  final Rect tileRect;

  /// Destination media-slot rect, in overlay coordinates.
  final Rect slotRect;

  /// Intrinsic aspect ratio (width / height) of the media surface.
  final double mediaAspect;

  /// Corner radius of the source tile at progress 0.
  final double tileRadius;

  /// Corner radius of the destination media slot at progress 1.
  final double slotRadius;

  /// The destination chrome (header/caption/buttons). Its own media slot
  /// must already be visually transparent so the hero layer painted above
  /// it reads as one continuous surface. Fades in via
  /// [resolveChromeOpacity].
  final Widget chromeChild;

  /// The media surface content (image/carousel-frame/video player), painted
  /// with [BoxFit.cover] by the transform below. Built exactly once.
  final Widget heroMediaChild;

  /// When true, mirrors the hero/chrome crossfade window to the first
  /// fraction of the flight instead of the last. Used for reverse (closing)
  /// flights, where the fake hero must reappear immediately rather than
  /// linger until the end.
  final bool reverseHandoff;

  /// Hero opacity for the handoff crossfade: ramps 1 -> 0 over the final
  /// [postPageZoomCrossfadeProgressThreshold] fraction of the flight (or,
  /// when [reverseHandoff] is true, the mirrored 0 -> 1 ramp over the first
  /// fraction).
  double _heroOpacity(double t) {
    final effective = reverseHandoff ? 1 - t : t;
    const rampStart = 1 - postPageZoomCrossfadeProgressThreshold;
    final fraction =
        ((effective - rampStart) / postPageZoomCrossfadeProgressThreshold)
            .clamp(0.0, 1.0);
    return 1 - fraction;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: progress,
      builder: (context, child) {
        final t = progress.value;
        final frame = resolveHeroFrame(
          tileRect: tileRect,
          slotRect: slotRect,
          mediaAspect: mediaAspect,
          tileRadius: tileRadius,
          slotRadius: slotRadius,
          progress: t,
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            Opacity(
              opacity: resolveChromeOpacity(t),
              child: RepaintBoundary(child: chromeChild),
            ),
            Opacity(
              opacity: _heroOpacity(t),
              child: ClipRRect(
                clipper: _PostPageHeroClipper(frame.clip),
                child: Transform.translate(
                  offset: frame.contentOffset,
                  child: Transform.scale(
                    scale: frame.contentScale,
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: mediaAspect,
                      height: 1,
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      child: heroMediaChild,
    );
  }
}

class _PostPageHeroClipper extends CustomClipper<RRect> {
  const _PostPageHeroClipper(this.rrect);

  final RRect rrect;

  @override
  RRect getClip(Size size) => rrect;

  @override
  bool shouldReclip(covariant _PostPageHeroClipper oldClipper) =>
      oldClipper.rrect != rrect;
}

import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';

/// Preview minimum scale the fullscreen surface shrinks to at full drag extent
/// during the iOS interactive edge-back preview (spec `Reverse Animation ->
/// iOS interactive edge back` §: "scale it from 1.0 toward an approximate
/// preview minimum of 0.92").
const double kPostPageBackPreviewMinScale = 0.92;

/// Preview corner radius the surface grows to at full drag extent (spec:
/// "increase corner radius from zero toward approximately 28-32 logical
/// pixels"). Fixed within the 28-32 band.
const double kPostPageBackPreviewCornerRadius = 30.0;

/// Horizontal travel of the surface at full drag extent, as a fraction of the
/// viewport width. `1.0` means the surface follows the finger 1:1 across the
/// full drag extent (linear, no easing).
const double kPostPageBackPreviewTranslateFraction = 1.0;

/// Width (logical px) of the leading-edge strip that arms the interactive back
/// gesture. Only a drag that begins within this strip is recognized.
const double kPostPageBackGestureEdgeWidth = 20.0;

/// Commit thresholds (spec: "about 25% horizontal completion or a fling near
/// 800 logical pixels per second"). Tunable from device traces; do not change
/// to hide rendering bugs.
const double kPostPageBackCommitProgressThreshold = 0.25;
const double kPostPageBackCommitVelocity = 800.0;

/// The commit flight (release above threshold) continues from the exact
/// current transform to B over this duration (spec: "approximately 180-240
/// ms").
const Duration kPostPageBackCommitDuration = Duration(milliseconds: 210);

/// The cancel spring (release below threshold) returns the exact current
/// transform to fullscreen over this duration, with no visual restart.
const Duration kPostPageBackCancelDuration = Duration(milliseconds: 200);

/// Fraction of the commit flight after which the frozen B tile is suppressed
/// (spec `Source tile suppression` §: "Suppress B only in the terminal portion
/// when the closing surface/proxy overlaps B").
const double kPostPageBackCommitSuppressThreshold = 0.6;

/// A single resolved frame of the interactive back preview / commit / cancel:
/// the destination surface occupies [rect] (overlay coordinates) clipped to a
/// rounded rectangle of [radius].
@immutable
class PostPageBackFrame {
  const PostPageBackFrame({required this.rect, required this.radius});

  final Rect rect;
  final double radius;

  @override
  bool operator ==(Object other) =>
      other is PostPageBackFrame && other.rect == rect && other.radius == radius;

  @override
  int get hashCode => Object.hash(rect, radius);

  @override
  String toString() => 'PostPageBackFrame(rect: $rect, radius: $radius)';
}

/// Pure resolver for the LINEAR interactive-back preview (no easing curve).
///
/// At `progress == 0` the surface is exactly fullscreen ([viewportRect], radius
/// 0). At `progress == 1` (full drag extent) it is scaled to
/// [kPostPageBackPreviewMinScale] about the viewport center, translated
/// horizontally toward the trailing side by
/// `progress * viewportRect.width * kPostPageBackPreviewTranslateFraction`, and
/// its corner radius is [kPostPageBackPreviewCornerRadius].
PostPageBackFrame resolvePostPageBackPreview({
  required Rect viewportRect,
  required double progress,
}) {
  final t = progress.clamp(0.0, 1.0);
  final scale = lerpDouble(1.0, kPostPageBackPreviewMinScale, t)!;
  final width = viewportRect.width * scale;
  final height = viewportRect.height * scale;
  final dx =
      t * viewportRect.width * kPostPageBackPreviewTranslateFraction;
  final center = viewportRect.center + Offset(dx, 0);
  final radius = lerpDouble(0.0, kPostPageBackPreviewCornerRadius, t)!;
  return PostPageBackFrame(
    rect: Rect.fromCenter(center: center, width: width, height: height),
    radius: radius,
  );
}

/// Linearly interpolates from [from] toward a target rect+radius by [t]
/// (`t == 0` yields [from] exactly — used for first-frame continuity when a
/// commit or cancel animation continues from the released transform).
PostPageBackFrame lerpPostPageBackFrame(
  PostPageBackFrame from,
  Rect toRect,
  double toRadius,
  double t,
) {
  final clamped = t.clamp(0.0, 1.0);
  return PostPageBackFrame(
    rect: Rect.lerp(from.rect, toRect, clamped)!,
    radius: lerpDouble(from.radius, toRadius, clamped)!,
  );
}

/// Renders the destination surface (built once, passed as [child]) into
/// [frame] in overlay coordinates: a uniform width-derived scale about the
/// top-left, translated to `frame.rect.topLeft`, clipped to a rounded rectangle
/// of `frame.rect`/`frame.radius`. The source Profile beneath the non-opaque
/// route stays visible around it (no opaque backdrop is painted).
class PostPageBackSurface extends StatelessWidget {
  const PostPageBackSurface({
    super.key,
    required this.frame,
    required this.viewportRect,
    required this.child,
  });

  final PostPageBackFrame frame;
  final Rect viewportRect;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scale = frame.rect.width / viewportRect.width;
    return ClipRRect(
      clipper: _RectRadiusClipper(frame.rect, frame.radius),
      child: Transform.translate(
        offset: frame.rect.topLeft,
        child: Transform.scale(
          scale: scale,
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: viewportRect.width,
            height: viewportRect.height,
            child: child,
          ),
        ),
      ),
    );
  }
}

class _RectRadiusClipper extends CustomClipper<RRect> {
  const _RectRadiusClipper(this.rect, this.radius);

  final Rect rect;
  final double radius;

  @override
  RRect getClip(Size size) =>
      RRect.fromRectAndRadius(rect, Radius.circular(radius));

  @override
  bool shouldReclip(covariant _RectRadiusClipper oldClipper) =>
      oldClipper.rect != rect || oldClipper.radius != radius;
}

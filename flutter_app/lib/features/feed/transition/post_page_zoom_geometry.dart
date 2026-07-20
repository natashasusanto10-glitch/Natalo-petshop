import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';

/// The crossfade between the clean proxy and the complete destination
/// completes by this fraction of the flight (spec: "first portion of the
/// flight"), independent of the geometry tween which spans the full flight.
/// Callers use `1 - postPageZoomCrossfadeProgressThreshold` for the
/// end-of-flight handoff (crossfade completing just before the hero flight
/// lands).
const double postPageZoomCrossfadeProgressThreshold = 0.35;

/// A single resolved frame of the Postingan hero-media geometry: where the
/// media surface sits (scale + top-left offset over its intrinsic surface
/// `Size(mediaAspect, 1.0)`) and the visible clip window, at a given
/// [resolveHeroFrame] `progress`.
///
/// There is deliberately no independent x/y scale: [contentScale] is the
/// single uniform scale factor applied to the intrinsic media surface, which
/// keeps its native aspect ratio throughout the flight.
@immutable
class PostPageHeroFrame {
  const PostPageHeroFrame({
    required this.contentScale,
    required this.contentOffset,
    required this.clip,
  });

  /// Uniform scale applied to the intrinsic media surface
  /// (`Size(mediaAspect, 1.0)`).
  final double contentScale;

  /// Top-left translation of the scaled media surface, in overlay
  /// coordinates.
  final Offset contentOffset;

  /// Visible clip window (bounds + radius) at this frame, tweened
  /// independently of [contentScale]/[contentOffset].
  final RRect clip;

  @override
  bool operator ==(Object other) =>
      other is PostPageHeroFrame &&
      other.contentScale == contentScale &&
      other.contentOffset == contentOffset &&
      other.clip == clip;

  @override
  int get hashCode => Object.hash(contentScale, contentOffset, clip);

  @override
  String toString() =>
      'PostPageHeroFrame(contentScale: $contentScale, '
      'contentOffset: $contentOffset, clip: $clip)';
}

/// Covers [target] with an intrinsic surface of `Size(mediaAspect, 1.0)`:
/// returns the `(scale, topLeft-offset)` pair so the scaled surface is
/// centered on and fully covers [target], exactly like `BoxFit.cover`.
(double, Offset) _cover(Rect target, double mediaAspect) {
  final scale = (target.width / mediaAspect) > target.height
      ? target.width / mediaAspect
      : target.height;
  final w = mediaAspect * scale;
  final h = scale;
  final offset = Offset(target.center.dx - w / 2, target.center.dy - h / 2);
  return (scale, offset);
}

/// Pure resolver for [PostPageHeroFrame] at a given [progress] (0..1)
/// between [tileRect] (the source grid tile, in overlay coordinates) and
/// [slotRect] (the destination media slot in the detail page, in overlay
/// coordinates).
///
/// `progress == 0` yields geometry where the media, scaled by
/// [PostPageHeroFrame.contentScale] and placed at
/// [PostPageHeroFrame.contentOffset], covers [tileRect] exactly as
/// `BoxFit.cover` would (radius [tileRadius]); `progress == 1` yields the
/// same but covering [slotRect] (radius [slotRadius]). Between the two
/// endpoints, [PostPageHeroFrame.contentScale] and
/// [PostPageHeroFrame.contentOffset] are linearly interpolated between the
/// two cover solutions, and [PostPageHeroFrame.clip] is `RRect.lerp` between
/// the tile and slot clips. Callers drive this with either a forward
/// (0 -> 1) or reverse (1 -> 0) animation value; the function itself has no
/// notion of direction.
PostPageHeroFrame resolveHeroFrame({
  required Rect tileRect,
  required Rect slotRect,
  required double mediaAspect,
  required double tileRadius,
  required double slotRadius,
  required double progress,
}) {
  final t = progress.clamp(0.0, 1.0);
  final (s0, o0) = _cover(tileRect, mediaAspect);
  final (s1, o1) = _cover(slotRect, mediaAspect);
  final tileClip = RRect.fromRectAndRadius(
    tileRect,
    Radius.circular(tileRadius),
  );
  final slotClip = RRect.fromRectAndRadius(
    slotRect,
    Radius.circular(slotRadius),
  );
  return PostPageHeroFrame(
    contentScale: lerpDouble(s0, s1, t)!,
    contentOffset: Offset.lerp(o0, o1, t)!,
    clip: RRect.lerp(tileClip, slotClip, t)!,
  );
}

/// Chrome (header/caption/buttons) fade-in opacity at a given [progress]
/// (0..1) of the hero flight: linear, `0` at the tile and `1` at the slot.
double resolveChromeOpacity(double progress) => progress.clamp(0.0, 1.0);

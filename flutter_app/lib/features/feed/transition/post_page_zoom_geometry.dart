import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';

/// The crossfade between the clean proxy and the complete destination
/// completes by this fraction of the flight (spec: "first portion of the
/// flight"), independent of the geometry tween which spans the full flight.
const double postPageZoomCrossfadeProgressThreshold = 0.35;

/// A single resolved frame of the Postingan full-page zoom transition.
///
/// Every field is expressed in logical pixels within the root Navigator
/// overlay coordinate space. There is deliberately no independent y-scale:
/// [scale] is the single uniform, width-derived scale factor applied to the
/// destination surface, which keeps its native fullscreen aspect ratio.
@immutable
class PostPageZoomFrame {
  const PostPageZoomFrame({
    required this.offset,
    required this.scale,
    required this.clip,
    required this.proxyOpacity,
    required this.destinationOpacity,
  });

  /// Top-left translation of the destination surface.
  final Offset offset;

  /// Uniform scale applied to the destination surface (width-derived only).
  final double scale;

  /// Clip bounds+radius, tweened independently of [offset]/[scale].
  final RRect clip;

  /// Opacity of the clean media proxy at this frame.
  final double proxyOpacity;

  /// Opacity of the complete destination content at this frame.
  final double destinationOpacity;

  @override
  bool operator ==(Object other) =>
      other is PostPageZoomFrame &&
      other.offset == offset &&
      other.scale == scale &&
      other.clip == clip &&
      other.proxyOpacity == proxyOpacity &&
      other.destinationOpacity == destinationOpacity;

  @override
  int get hashCode =>
      Object.hash(offset, scale, clip, proxyOpacity, destinationOpacity);

  @override
  String toString() =>
      'PostPageZoomFrame(offset: $offset, scale: $scale, clip: $clip, '
      'proxyOpacity: $proxyOpacity, destinationOpacity: $destinationOpacity)';
}

/// Pure resolver for [PostPageZoomFrame] at a given [progress] (0..1) between
/// [tileRect] (the source tile, in overlay coordinates) and [viewportRect]
/// (the fullscreen application surface, in overlay coordinates).
///
/// `progress == 0` yields exact source-tile geometry (radius
/// [tileCornerRadius]); `progress == 1` yields exact fullscreen geometry
/// (offset zero, scale 1.0, radius 0). Callers drive this with either a
/// forward (0 -> 1) or reverse (1 -> 0) animation value; the function itself
/// has no notion of direction.
PostPageZoomFrame resolvePostPageZoomFrame({
  required Rect tileRect,
  required Rect viewportRect,
  required double tileCornerRadius,
  required double progress,
}) {
  final clampedProgress = progress.clamp(0.0, 1.0);
  final widthScale = tileRect.width / viewportRect.width;
  final scale = lerpDouble(widthScale, 1.0, clampedProgress)!;
  final offset = Offset.lerp(
    tileRect.topLeft,
    viewportRect.topLeft,
    clampedProgress,
  )!;
  final clip = RRect.lerp(
    RRect.fromRectAndRadius(tileRect, Radius.circular(tileCornerRadius)),
    RRect.fromRectAndRadius(viewportRect, Radius.zero),
    clampedProgress,
  )!;
  final crossfadeT = (clampedProgress / postPageZoomCrossfadeProgressThreshold)
      .clamp(0.0, 1.0);
  return PostPageZoomFrame(
    offset: offset,
    scale: scale,
    clip: clip,
    proxyOpacity: 1.0 - crossfadeT,
    destinationOpacity: crossfadeT,
  );
}

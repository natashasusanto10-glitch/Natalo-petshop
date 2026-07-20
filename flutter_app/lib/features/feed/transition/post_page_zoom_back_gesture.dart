import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';

import 'post_page_zoom_geometry.dart';
import 'post_page_zoom_transition.dart';

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

/// Linearly interpolates from [from] toward [to] by [t] (`t == 0` yields
/// [from] exactly — used for first-frame continuity when a commit or cancel
/// animation continues from the exact hero frame captured at gesture
/// release, with no visual restart). Lerps `contentScale`/`contentOffset`
/// directly and `clip` via `RRect.lerp`.
PostPageHeroFrame lerpPostPageHeroFrame(
  PostPageHeroFrame from,
  PostPageHeroFrame to,
  double t,
) {
  final clamped = t.clamp(0.0, 1.0);
  return PostPageHeroFrame(
    contentScale: lerpDouble(from.contentScale, to.contentScale, clamped)!,
    contentOffset: Offset.lerp(from.contentOffset, to.contentOffset, clamped)!,
    clip: RRect.lerp(from.clip, to.clip, clamped)!,
  );
}

/// Renders the hero-media layer (built once, passed as [child]) at [frame],
/// using the same paint pipeline as [PostPageZoomTransition]'s forward/close
/// hero layer (`paintPostPageHero`) so there is exactly one hero-paint
/// implementation. Structurally replaces the deleted `PostPageBackSurface`:
/// no opaque backdrop is painted, so the source Profile beneath the
/// non-opaque route stays visible around the hero surface.
class PostPageHeroSurface extends StatelessWidget {
  const PostPageHeroSurface({
    super.key,
    required this.frame,
    required this.mediaAspect,
    required this.child,
  });

  final PostPageHeroFrame frame;
  final double mediaAspect;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      paintPostPageHero(frame, mediaAspect, child);
}

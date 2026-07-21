import 'package:flutter/material.dart';

/// Tag hero ter-scope per permukaan. Tag duplikat di satu layar membuat
/// framework menonaktifkan hero DIAM-DIAM — selalu lewat helper ini.
String postHeroTag(String scope, String postId) => 'post-hero/$scope/$postId';

class PostHero extends StatelessWidget {
  const PostHero({
    super.key,
    required this.scope,
    required this.postId,
    this.borderRadius = BorderRadius.zero,
    required this.child,
  });

  final String scope;
  final String postId;
  final BorderRadius borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: postHeroTag(scope, postId),
      transitionOnUserGestures: true,
      flightShuttleBuilder: _shuttle,
      child: ClipRRect(borderRadius: borderRadius, child: child),
    );
  }

  /// Shuttle: gambar surface sisi VIEWER sepanjang penerbangan (push: tujuan,
  /// pop: asal) — untuk video berarti VideoPlayer(controller) yang sama, satu
  /// texture, tanpa swap thumbnail. Radius di-lerp antara kedua endpoint.
  static Widget _shuttle(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection direction,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    final Hero fromHero = fromHeroContext.widget as Hero;
    final Hero toHero = toHeroContext.widget as Hero;
    final Widget content =
        direction == HeroFlightDirection.push ? toHero.child : fromHero.child;
    BorderRadius radiusOf(Hero h) => h.child is ClipRRect
        ? ((h.child as ClipRRect).borderRadius as BorderRadius)
        : BorderRadius.zero;
    final BorderRadius fromRadius = radiusOf(fromHero);
    final BorderRadius toRadius = radiusOf(toHero);
    // PostHero.build always wraps its child in ClipRRect (see above), so
    // `content` here is always that ClipRRect — unwrap it directly instead
    // of guarding a branch that can never be hit.
    assert(content is ClipRRect, 'PostHero child sudah pasti ClipRRect');
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) => ClipRRect(
        borderRadius: BorderRadius.lerp(fromRadius, toRadius, animation.value)!,
        child: (content as ClipRRect).child,
      ),
    );
  }
}

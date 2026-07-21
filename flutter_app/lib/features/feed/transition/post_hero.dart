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
    this.flightChild,
    this.active = true,
  });

  final String scope;
  final String postId;
  final BorderRadius borderRadius;
  final Widget child;

  /// `false` → Hero dipasang dengan tag "inert" (bukan
  /// `postHeroTag(scope, postId)`, jadi TIDAK PERNAH cocok dengan Hero mana
  /// pun di route lain) — dipakai untuk close-only Hero (lihat
  /// `_HeroFlightGate` di member_post_detail_screen.dart): bentuk tree
  /// SELALU sama (Hero tetap membungkus child) supaya subtree media (mis.
  /// `_InlineVideoPlayer`) TIDAK pernah di-reparent/dibuat ulang hanya
  /// karena Hero aktif/nonaktif — cuma STRING tag yang berubah, yang inert
  /// terhadap HeroController selama tidak ada transisi navigasi berjalan
  /// tepat di frame yang sama.
  final bool active;

  /// Surface RINGAN dipakai HANYA di dalam shuttle (kedua arah), sebagai
  /// pengganti [child]. Untuk video: `_HeroVideoFlightSurface` yang membaca
  /// controller yang SUDAH hidup dari [PostVideoCoordinator] secara sinkron
  /// di `initState` (bukan lewat `_InlineVideoPlayer`, yang re-attach hanya
  /// lewat `VisibilityDetector` ber-throttle ~500ms — jauh lebih lambat dari
  /// durasi flight, jadi shuttle SELALU mendarat sebelum sempat bind →
  /// placeholder/kosong sekilas alih-alih video hidup). Null (foto/carousel)
  /// = pakai [child] apa adanya, perilaku lama.
  final Widget? flightChild;

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: active
          ? postHeroTag(scope, postId)
          : '${postHeroTag(scope, postId)}/inert',
      transitionOnUserGestures: true,
      flightShuttleBuilder: _shuttle,
      child: ClipRRect(
        borderRadius: borderRadius,
        child: _HeroContent(flightChild: flightChild, child: child),
      ),
    );
  }

  /// Shuttle: gambar surface sisi VIEWER sepanjang penerbangan (push: tujuan,
  /// pop: asal) — untuk video berarti VideoPlayer(controller) yang sama, satu
  /// texture, tanpa swap thumbnail (lewat [flightChild] bila disediakan).
  /// Radius di-lerp antara kedua endpoint.
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
    // PostHero.build always wraps its child in ClipRRect(_HeroContent(...))
    // (see above), so `content` here is always that ClipRRect — unwrap it
    // directly instead of guarding a branch that can never be hit.
    assert(content is ClipRRect, 'PostHero child sudah pasti ClipRRect');
    final _HeroContent heroContent =
        (content as ClipRRect).child as _HeroContent;
    final Widget display = heroContent.flightChild ?? heroContent.child;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) => ClipRRect(
        borderRadius: BorderRadius.lerp(fromRadius, toRadius, animation.value)!,
        child: display,
      ),
    );
  }
}

/// Pembawa [child]/[flightChild] lewat `Hero.child` — dibaca balik oleh
/// shuttle ([PostHero._shuttle]) tanpa mengubah render normal (build() cuma
/// mengembalikan [child], sama seperti sebelum [flightChild] ada).
class _HeroContent extends StatelessWidget {
  const _HeroContent({required this.child, this.flightChild});

  final Widget child;
  final Widget? flightChild;

  @override
  Widget build(BuildContext context) => child;
}

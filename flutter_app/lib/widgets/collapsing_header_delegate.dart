import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show FloatingHeaderSnapConfiguration;

/// Delegate collapsing header BERSAMA (Beranda + Produk) — pinned + floating,
/// lipatan digerakkan `shrinkOffset` NATIVE 1:1 dengan jari.
///
/// Kenapa mesin ini (bukan toggle biner / AnimationController yang jalan
/// sendiri): protokol sliver menjaga `scrollExtent` KONSTAN (= [maxHeight]),
/// jadi tinggi header menyusut/mengembang persis mengikuti jari tanpa pernah
/// menggeser (lompat) konten di bawahnya. `floating: true` → header kembali
/// saat scroll naik di TENGAH daftar sebagai reveal overlay (konten tidak
/// tergeser). [FloatingHeaderSnapConfiguration] hanya merapikan header ke
/// buka/tutup penuh saat gesture SELESAI (framework menunggu ScrollEnd), jadi
/// snap tidak pernah melawan jari yang masih menempel.
///
/// SYARAT WAJIB pemakai: tinggi konten header harus LINEAR terhadap progress
/// t, dan `builder(t=0)` = [maxHeight], `builder(t=1)` = [minHeight]. Kalau
/// tinggi tidak linear (mis. ada `max(a, b)` yang berganti pemenang di tengah
/// range), akan muncul celah/clip karena sliver memberi extent linear
/// (`maxHeight - shrinkOffset`) sementara konten tidak.
class CollapsingHeaderDelegate extends SliverPersistentHeaderDelegate {
  /// Tinggi collapsed (t=1) = [minExtent].
  final double minHeight;

  /// Tinggi expanded (t=0) = [maxExtent].
  final double maxHeight;

  final TickerProvider _vsync;

  /// Reduce motion ("Remove animations" Android / "Reduce Motion" iOS): snap
  /// jadi instan (Duration.zero). Reveal 1:1-nya SENDIRI tetap jalan — itu
  /// direct manipulation dari jari user, bukan animasi yang bergerak sendiri.
  final bool reduceMotion;

  /// Bangun isi header dari progress collapse [t] (0 expanded → 1 collapsed,
  /// sudah di-clamp). t diturunkan dari `shrinkOffset / (maxHeight-minHeight)`.
  final Widget Function(BuildContext context, double t) builder;

  const CollapsingHeaderDelegate({
    required this.minHeight,
    required this.maxHeight,
    required TickerProvider vsync,
    required this.reduceMotion,
    required this.builder,
  }) : _vsync = vsync;

  @override
  double get minExtent => minHeight;

  @override
  double get maxExtent => maxHeight;

  @override
  TickerProvider get vsync => _vsync;

  @override
  FloatingHeaderSnapConfiguration get snapConfiguration =>
      FloatingHeaderSnapConfiguration(
        curve: Curves.easeOut,
        duration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 200),
      );

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final range = maxHeight - minHeight;
    final t = range > 0 ? (shrinkOffset / range).clamp(0.0, 1.0) : 0.0;
    // RepaintBoundary: repaint per-frame selama lipatan tidak merambat ke
    // konten/grid di bawah header.
    return RepaintBoundary(child: builder(context, t));
  }

  @override
  bool shouldRebuild(covariant CollapsingHeaderDelegate oldDelegate) {
    // [builder] adalah closure baru tiap parent build (menangkap data terkini
    // — badge cart, count, query, dsb), jadi kita selalu rebuild saat parent
    // rebuild. Lipatan per-frame TIDAK lewat sini (itu relayout dari
    // shrinkOffset), jadi ini hanya menyala saat state halaman berubah —
    // frekuensinya rendah. minHeight/maxHeight/reduceMotion ikut dibandingkan
    // supaya perubahan geometri (mis. reduce-motion toggle) pasti terpasang.
    return oldDelegate.minHeight != minHeight ||
        oldDelegate.maxHeight != maxHeight ||
        oldDelegate.reduceMotion != reduceMotion ||
        true;
  }
}

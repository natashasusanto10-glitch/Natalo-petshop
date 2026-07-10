import 'package:flutter/material.dart';

/// Delegate collapsing header BERSAMA (Beranda + Produk) — PINNED, lipatan
/// digerakkan `shrinkOffset` NATIVE 1:1 dengan jari.
///
/// Kenapa mesin ini (bukan toggle biner / AnimationController yang jalan
/// sendiri): protokol sliver menjaga `scrollExtent` KONSTAN (= [maxHeight]),
/// jadi tinggi header menyusut/mengembang persis mengikuti jari tanpa pernah
/// menggeser (lompat) konten di bawahnya.
///
/// PINNED-ONLY (bukan floating): header mengecil saat scroll turun lalu DIAM
/// terkunci di [minHeight]; ia mengembang penuh lagi HANYA saat scroll balik
/// mendekati ATAS (shrinkOffset mengecil), BUKAN saat scroll naik di tengah
/// daftar. Keputusan user: floating ("kembali mid-list") dibuang karena efek
/// sampingnya — reveal terlalu gampang pada scroll kecil + fling terasa jump —
/// tidak sepadan. Konsekuensinya tidak perlu vsync/snap/reduce-motion sama
/// sekali: collapse 1:1 adalah direct manipulation dari scroll, bukan animasi.
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

  /// Bangun isi header dari progress collapse [t] (0 expanded → 1 collapsed,
  /// sudah di-clamp). t diturunkan dari `shrinkOffset / (maxHeight-minHeight)`.
  final Widget Function(BuildContext context, double t) builder;

  const CollapsingHeaderDelegate({
    required this.minHeight,
    required this.maxHeight,
    required this.builder,
  });

  @override
  double get minExtent => minHeight;

  @override
  double get maxExtent => maxHeight;

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
    // frekuensinya rendah.
    return oldDelegate.minHeight != minHeight ||
        oldDelegate.maxHeight != maxHeight ||
        true;
  }
}

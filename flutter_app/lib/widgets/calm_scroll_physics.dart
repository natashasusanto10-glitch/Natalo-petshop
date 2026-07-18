import 'package:flutter/widgets.dart';

/// Physics scroll "kalem" ala halaman Posts Instagram.
///
/// Default Flutter (Android ClampingScrollPhysics / iOS Bouncing) meluncur
/// sangat jauh per fling — di list/grid yang tinggi kontennya besar, satu
/// flick bisa melewati beberapa layar sekaligus. IG meredam ini: satu flick
/// jaraknya pendek, dan flick beruntun tidak saling menumpuk jadi "roket".
/// Dua tuas yang dipakai:
///  1. Kecepatan fling di-skala turun sebelum masuk simulasi balistik
///     → jarak luncur lebih pendek, decay terasa lebih cepat.
///  2. carriedMomentum dimatikan → flick kedua tidak mewarisi sisa
///     kecepatan flick pertama (penyebab utama scroll "terbang").
///
/// Drag langsung (jari nempel) TIDAK berubah — 1:1 mengikuti jari.
class CalmScrollPhysics extends AlwaysScrollableScrollPhysics {
  const CalmScrollPhysics({super.parent});

  /// Skala kecepatan fling (1.0 = default Flutter). 0.7 dipilih supaya scroll
  /// list Postingan tak terasa terlalu berat (sebelumnya 0.55 terasa nahan),
  /// tapi tetap sedikit teredam dibanding default Flutter — dekat rasa IG.
  static const double _flingVelocityScale = 0.7;

  @override
  CalmScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      CalmScrollPhysics(parent: buildParent(ancestor));

  @override
  double get maxFlingVelocity => super.maxFlingVelocity * _flingVelocityScale;

  @override
  Simulation? createBallisticSimulation(
      ScrollMetrics position, double velocity) {
    return super.createBallisticSimulation(
      position,
      velocity * _flingVelocityScale,
    );
  }

  @override
  double carriedMomentum(double existingVelocity) => 0;
}

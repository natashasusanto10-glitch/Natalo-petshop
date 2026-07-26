import 'package:flutter/widgets.dart';

/// Physics scroll "kalem" ala halaman Posts Instagram.
///
/// Default Flutter (Android ClampingScrollPhysics / iOS Bouncing) meluncur
/// sangat jauh per fling — di list/grid yang tinggi kontennya besar, satu
/// flick bisa melewati beberapa layar sekaligus. IG meredam ini: satu flick
/// jaraknya pendek, dan flick beruntun tidak saling menumpuk jadi "roket".
/// Dua tuas yang dipakai:
///  1. [velocityScale] — kecepatan fling di-skala turun sebelum masuk
///     simulasi balistik → jarak luncur lebih pendek, decay terasa lebih
///     cepat.
///  2. [momentumScale] — seberapa banyak sisa kecepatan flick sebelumnya
///     diwarisi flick berikutnya. 0 = mati total (flick beruntun tidak
///     menumpuk), 1 = default Flutter/IG native.
///
/// Drag langsung (jari nempel) TIDAK berubah — 1:1 mengikuti jari.
///
/// CATATAN TUNING (wajib device-verify, angka ini hasil coba-rasa):
///  - Grid profil (member_screen, public_profile_screen) pakai default
///    kelas ini (0.7 + momentum mati) — kontennya thumbnail kecil, satu
///    fling default bisa melewati banyak baris sekaligus.
///  - List Postingan pakai [CalmScrollPhysics.postingan] yang lebih dekat
///    default platform: sempat dicoba 0.7+momentum-mati (terasa berat) lalu
///    default penuh (terasa terlalu kencang), jadi dipatok di tengah.
class CalmScrollPhysics extends AlwaysScrollableScrollPhysics {
  /// Skala kecepatan fling (1.0 = default Flutter).
  final double velocityScale;

  /// Skala momentum flick beruntun (0 = mati, 1.0 = default Flutter).
  final double momentumScale;

  const CalmScrollPhysics({
    super.parent,
    this.velocityScale = 0.7,
    this.momentumScale = 0,
  });

  /// Preset halaman Postingan — lebih dekat rasa IG (native pakai default
  /// platform) tapi tidak sepenuhnya lepas: fling sedikit diredam dan
  /// flick beruntun menumpuk separuh, bukan mati total.
  const CalmScrollPhysics.postingan({ScrollPhysics? parent})
      : this(parent: parent, velocityScale: 0.88, momentumScale: 0.5);

  @override
  CalmScrollPhysics applyTo(ScrollPhysics? ancestor) => CalmScrollPhysics(
        parent: buildParent(ancestor),
        velocityScale: velocityScale,
        momentumScale: momentumScale,
      );

  @override
  double get maxFlingVelocity => super.maxFlingVelocity * velocityScale;

  @override
  Simulation? createBallisticSimulation(
      ScrollMetrics position, double velocity) {
    return super.createBallisticSimulation(
      position,
      velocity * velocityScale,
    );
  }

  @override
  double carriedMomentum(double existingVelocity) =>
      super.carriedMomentum(existingVelocity) * momentumScale;
}

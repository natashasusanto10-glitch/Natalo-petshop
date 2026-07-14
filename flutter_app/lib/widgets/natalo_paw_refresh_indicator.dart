import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/natalo_colors.dart';
import '../utils/haptics.dart';

/// Premium pull-to-refresh indicator dengan paw print Natalo.
///
/// Replace Material `RefreshIndicator` generic dengan branded indicator —
/// paw icon di lingkaran putih, scale + rotate based on pull progress,
/// continuous spin saat refresh.
///
/// Mechanics:
/// - NotificationListener detect overscroll di top scrollable
/// - Drag offset di-accumulate dari `OverscrollNotification.overscroll`
/// - Threshold @ `triggerOffset` (default 48px): haptic tap fire,
///   indicator "armed" — kalau user lepas, refresh trigger
/// - During refresh: paw spin continuous (900ms loop) + freeze offset
///   di triggerOffset supaya tetap visible
/// - After refresh: spin stop + offset snap back ke 0 dengan fade-out
///
/// Drop-in replacement untuk `RefreshIndicator` — API sama (onRefresh + child).
/// Beda dari `HapticRefreshIndicator` (yang masih pakai Material spinner
/// di balik): widget ini full custom — branded paw icon, bukan generic
/// circular progress.
///
/// Limitations:
/// - Tidak fully replicate physics rubber-band iOS native — overlay
///   shows on top, child tidak ikut ter-translate ke bawah
///
/// Cross-platform note:
/// Default Android pakai `ClampingScrollPhysics` — kalau user drag past
/// top, position di-clamp ke 0, applyUserOffset return tanpa setPixels,
/// `OverscrollNotification` TIDAK fire → paw tidak akan pernah armed
/// di Android. Untuk fix-nya, widget ini wrap child di `ScrollConfiguration`
/// dengan custom behavior yang force `BouncingScrollPhysics` di semua
/// platform — supaya overscroll notification konsisten fire iOS + Android.
/// Glowing/Stretching overscroll indicator default Android juga di-disable
/// (`buildOverscrollIndicator` return child apa adanya) supaya tidak ada
/// dua indikator yang muncul bersamaan (glow Android + paw kita).
///
/// Usage:
/// ```dart
/// NataloPawRefreshIndicator(
///   onRefresh: () async => await _loadData(),
///   child: ListView(...),
/// )
/// ```
class NataloPawRefreshIndicator extends StatefulWidget {
  final Widget child;
  final Future<void> Function() onRefresh;

  /// Berapa pull pixel sebelum indicator "armed" + refresh trigger.
  /// Default 48 — lebih ringan dari Material default supaya pull tidak
  /// terasa berhenti setengah jalan di CustomScrollView + pinned header.
  final double triggerOffset;

  /// Selisih top dari SafeArea sebelum paw mulai muncul.
  /// Default 8 — small gap supaya indicator tidak nempel status bar.
  final double topPadding;

  /// IG-style pull behavior: child ikut turun sedikit saat user menarik
  /// dari top. Default true supaya semua halaman terasa "ikut jari"
  /// konsisten dengan halaman Akun.
  final bool translateChild;

  /// Maksimal jarak child turun saat pull. Dipakai hanya jika
  /// [translateChild] true.
  final double maxChildOffset;

  /// Jika true, refresh hanya dijalankan setelah tarikan benar-benar
  /// mencapai [triggerOffset]. Tarikan pendek akan memantul kembali tanpa
  /// memakai toleransi release. Cocok untuk profil dengan area scroll besar.
  final bool requireFullPull;

  /// Konten benar-benar DIAM saat pull: child tidak di-translate DAN physics
  /// dipaksa Clamping supaya scroll position tidak bisa lewat 0 (tidak ada
  /// rubber-band). Satu-satunya sinyal visual = paw overlay.
  ///
  /// Dipakai halaman dengan pinned sliver header (Beranda): bouncing physics
  /// membuat sliver non-pinned melar menjauh dari header pinned saat
  /// overscroll → konten terlihat "terbelah" putih. Clamping tetap memicu
  /// `OverscrollNotification`, jadi deteksi tarikan + trigger refresh tidak
  /// berubah. Override [translateChild].
  final bool pinContent;

  const NataloPawRefreshIndicator({
    super.key,
    required this.child,
    required this.onRefresh,
    this.triggerOffset = 48,
    this.topPadding = 8,
    this.translateChild = true,
    this.maxChildOffset = 34,
    this.requireFullPull = false,
    this.pinContent = false,
  });

  @override
  State<NataloPawRefreshIndicator> createState() =>
      _NataloPawRefreshIndicatorState();
}

class _NataloPawRefreshIndicatorState extends State<NataloPawRefreshIndicator>
    with TickerProviderStateMixin {
  /// Accumulated pull offset (0 .. triggerOffset+30).
  double _overscroll = 0;

  /// Pull terdalam selama satu gesture. Beberapa scrollable mengirim
  /// ScrollEnd setelah bounce mulai balik ke 0, jadi nilai current overscroll
  /// bisa sudah mengecil saat user lepas.
  double _maxOverscroll = 0;

  /// Apakah pull sudah lewat threshold — kalau user lepas sekarang,
  /// refresh akan fire.
  bool _armed = false;

  /// Apakah onRefresh currently running.
  bool _isRefreshing = false;

  /// Spin animation saat refreshing (continuous loop).
  late final AnimationController _spinCtrl;

  /// Fade-out controller saat refresh complete (untuk smooth exit).
  late final AnimationController _fadeCtrl;

  @override
  void initState() {
    super.initState();
    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _spinCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  bool _handleScroll(ScrollNotification n) {
    // Skip horizontal scroll + skip while refreshing (lock state).
    if (_isRefreshing) return false;
    if (n.metrics.axis != Axis.vertical) return false;

    // ── Compute "pull amount" universally — works for both physics ──
    //
    // ClampingScrollPhysics (default Android): scroll position clamps at
    // 0, applyBoundaryConditions returns excess → OverscrollNotification
    // fires dengan `overscroll` value. pixels tetap 0 di top.
    //
    // BouncingScrollPhysics (default iOS): scroll position bounces past 0
    // ke NEGATIVE. applyBoundaryConditions return 0 → tidak ada
    // OverscrollNotification — tapi metrics.pixels jadi negative.
    //
    // Logic baru: track pull amount dari NEGATIVE pixels (iOS bouncing)
    // ATAU OverscrollNotification.overscroll (Android clamping).
    final pixels = n.metrics.pixels;
    final pullFromBouncing = pixels < 0 ? -pixels : 0.0;
    final pullFromOverscroll =
        (n is OverscrollNotification && pixels <= 0) ? n.overscroll.abs() : 0.0;

    final hasPull = pullFromBouncing > 0 || pullFromOverscroll > 0;
    if (hasPull) {
      // BouncingScrollPhysics: pakai absolute -pixels (current scroll
      // position) dengan friction 0.8 supaya gerakan terasa subtle.
      // Clamping: accumulate dari overscroll delta * 0.5.
      final newOverscroll = pullFromBouncing > 0
          ? (pullFromBouncing * 0.8).clamp(0.0, widget.triggerOffset + 30)
          : (_overscroll + pullFromOverscroll * 0.5)
              .clamp(0.0, widget.triggerOffset + 30);

      if (newOverscroll != _overscroll) {
        setState(() => _overscroll = newOverscroll);
      }
      if (newOverscroll > _maxOverscroll) {
        _maxOverscroll = newOverscroll;
      }
      // Threshold reached — haptic tap "armed".
      if (!_armed && _overscroll >= widget.triggerOffset) {
        _armed = true;
        AppHaptics.tap();
      }
    }

    // Pada BouncingScrollPhysics, ScrollEnd kadang datang saat metrics.pixels
    // masih negatif. Versi lama masuk ke cabang `hasPull` di atas dan tidak
    // pernah mengeksekusi refresh, sehingga icon terlihat "setengah ketarik"
    // tapi onRefresh tidak jalan.
    if (n is ScrollEndNotification ||
        (n is UserScrollNotification &&
            n.direction == ScrollDirection.idle &&
            _overscroll > 0)) {
      _finishPull();
    } else if (!hasPull && n is ScrollUpdateNotification && pixels > 0) {
      // User scroll ke bawah past 0 (positive) → batal pull.
      if (_overscroll > 0) {
        setState(() {
          _overscroll = 0;
          _armed = false;
        });
      }
    }
    return false;
  }

  void _finishPull() {
    // Release — kalau armed → fire refresh, kalau tidak → snap back.
    // Sedikit toleran saat release: beberapa scrollable (terutama detail
    // screen dengan ListView pendek) tidak selalu memberi update frame tepat
    // di threshold, padahal user sudah menarik cukup jauh secara visual.
    final releaseTrigger = widget.requireFullPull
        ? widget.triggerOffset
        : widget.triggerOffset * 0.72;
    if (_armed ||
        _overscroll >= releaseTrigger ||
        _maxOverscroll >= releaseTrigger) {
      _doRefresh();
    } else if (_overscroll > 0) {
      setState(() {
        _overscroll = 0;
        _armed = false;
      });
      _maxOverscroll = 0;
    }
  }

  Future<void> _doRefresh() async {
    setState(() {
      _isRefreshing = true;
      _overscroll = widget.triggerOffset;
    });
    _maxOverscroll = widget.triggerOffset;
    _fadeCtrl.value = 1.0;
    _spinCtrl.repeat();
    AppHaptics.success();

    try {
      await widget.onRefresh();
    } catch (_) {
      // Silent — refresh failed di-handle oleh consumer.
    }

    if (!mounted) return;
    _spinCtrl.stop();
    // Fade out smooth sebelum reset state.
    await _fadeCtrl.reverse();
    if (!mounted) return;
    setState(() {
      _isRefreshing = false;
      _overscroll = 0;
      _armed = false;
    });
    _maxOverscroll = 0;
    _fadeCtrl.value = 1.0; // reset untuk next pull
  }

  @override
  Widget build(BuildContext context) {
    final visible = _overscroll > 0 || _isRefreshing;
    final progress = (_overscroll / widget.triggerOffset).clamp(0.0, 1.0);
    // Mode full-pull mengikuti jari hingga threshold. Mode default tetap
    // menyelesaikan gerak lebih awal agar perilaku halaman lama tidak berubah.
    final rampProgress = widget.requireFullPull
        ? progress
        : (progress / pawRampFraction).clamp(0.0, 1.0);
    final childOffset = widget.translateChild && !widget.pinContent
        ? (_isRefreshing
            ? widget.maxChildOffset
            : widget.maxChildOffset *
                Curves.easeOutCubic.transform(rampProgress))
        : 0.0;

    return Stack(
      fit: StackFit.expand,
      children: [
        // ScrollConfiguration force bouncing physics di Android supaya
        // OverscrollNotification fire saat user drag past top (default
        // ClampingScrollPhysics tidak fire → paw tidak armed di Android).
        AnimatedContainer(
          duration: Duration(milliseconds: _isRefreshing ? 180 : 0),
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(0, childOffset, 0),
          child: ScrollConfiguration(
            behavior: _NataloPawScrollBehavior(clamp: widget.pinContent),
            child: NotificationListener<ScrollNotification>(
              onNotification: _handleScroll,
              child: widget.child,
            ),
          ),
        ),
        if (visible)
          Positioned(
            top: MediaQuery.of(context).padding.top + widget.topPadding,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: AnimatedBuilder(
                  animation: Listenable.merge([_spinCtrl, _fadeCtrl]),
                  builder: (context, _) {
                    final visual = computePawVisual(
                      progress: progress,
                      isRefreshing: _isRefreshing,
                      fadeValue: _fadeCtrl.value,
                    );
                    // Rotation: 0 → π/2 saat pulling (turn-in feel),
                    // continuous spin saat refreshing.
                    final rotation = _isRefreshing
                        ? _spinCtrl.value * 2 * math.pi
                        : progress * math.pi * 0.5;

                    return Opacity(
                      opacity: visual.opacity,
                      child: Transform.scale(
                        scale: visual.scale,
                        child: Transform.rotate(
                          angle: rotation,
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: NataloColors.primary
                                      .withValues(alpha: 0.30),
                                  blurRadius: 14,
                                  offset: const Offset(0, 4),
                                ),
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.06),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.pets_rounded,
                              color: NataloColors.primary,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// ScrollBehavior khusus untuk child di `NataloPawRefreshIndicator`.
///
/// 1. Force `BouncingScrollPhysics` di semua platform — bukan untuk
///    notification (handler udah support kedua physics via negative
///    pixels detection), tapi supaya UX bouncing rubber-band konsisten
///    iOS & Android. User feel "alami" saat drag past top.
/// 2. Disable default Android glow / stretching overscroll indicator —
///    hindari dual indikator (glow + paw) tabrakan visual.
class _NataloPawScrollBehavior extends ScrollBehavior {
  /// true saat [NataloPawRefreshIndicator.pinContent]: pakai Clamping supaya
  /// konten tidak bisa ditarik lewat 0 sama sekali (tanpa rubber-band).
  /// OverscrollNotification tetap fire → paw tetap armed.
  final bool clamp;

  const _NataloPawScrollBehavior({this.clamp = false});

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    if (clamp) {
      return const ClampingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      );
    }
    return const BouncingScrollPhysics(
      parent: AlwaysScrollableScrollPhysics(),
    );
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    // Hilangkan glow/stretch indicator default Android — paw kita pakai
    // sendiri. Tidak butuh wrapping apapun.
    return child;
  }
}

/// Fraksi `progress` di mana kurva paw (scale/opacity) sudah full —
/// dipakai juga oleh [translateChild] (lihat `_NataloPawRefreshIndicatorState.
/// build`) supaya kedua sinyal visual (paw + geser konten) selesai
/// bersamaan, bukan di titik progress yang beda-beda.
const double pawRampFraction = 0.65;

/// Scale + opacity paw pada satu titik tarikan. Immutable, murni hasil
/// [computePawVisual] — tidak menyentuh state widget.
class PawVisual {
  final double scale;
  final double opacity;

  const PawVisual(this.scale, this.opacity);
}

/// Kurva visual paw vs `progress` tarikan (0..1 = 0..triggerOffset).
///
/// Sebelumnya scale/opacity mulai dari floor rendah (0.5 / 0.2) dan ramp
/// linear sampai progress 1.0 — di banyak halaman (tanpa `translateChild`,
/// yaitu semua kecuali halaman Akun) ini jadi satu-satunya sinyal pull
/// yang terlihat, dan floor rendah itu nyaris tak kelihatan. User pull,
/// tidak sadar ada feedback, baru sadar paw "muncul" pas sudah dekat/di
/// titik trigger — terasa seperti delay padahal sebenarnya progresif.
///
/// Fix: floor dinaikkan (paw jelas kelihatan sejak progress≈0) + ramp
/// dipercepat supaya sudah full scale/opacity di progress 0.65, bukan
/// nunggu sampai 1.0 — user dapat konfirmasi visual jauh sebelum rilis.
PawVisual computePawVisual({
  required double progress,
  required bool isRefreshing,
  required double fadeValue,
}) {
  if (isRefreshing) {
    return PawVisual(1.0, fadeValue.clamp(0.0, 1.0));
  }
  final rampProgress = (progress / pawRampFraction).clamp(0.0, 1.0);
  final scale = 0.62 + (rampProgress * 0.38);
  final opacity = (0.5 + (rampProgress * 0.5)).clamp(0.0, 1.0);
  return PawVisual(scale, opacity);
}

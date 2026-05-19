import 'dart:math' as math;

import 'package:flutter/material.dart';

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
/// - Threshold @ `triggerOffset` (default 70px): haptic tap fire,
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
  /// Default 70 — match Material RefreshIndicator displacement.
  final double triggerOffset;

  /// Selisih top dari SafeArea sebelum paw mulai muncul.
  /// Default 8 — small gap supaya indicator tidak nempel status bar.
  final double topPadding;

  const NataloPawRefreshIndicator({
    super.key,
    required this.child,
    required this.onRefresh,
    this.triggerOffset = 70,
    this.topPadding = 8,
  });

  @override
  State<NataloPawRefreshIndicator> createState() =>
      _NataloPawRefreshIndicatorState();
}

class _NataloPawRefreshIndicatorState extends State<NataloPawRefreshIndicator>
    with TickerProviderStateMixin {
  /// Accumulated pull offset (0 .. triggerOffset+30).
  double _overscroll = 0;

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

    // Overscroll at top → accumulate pull amount.
    if (n is OverscrollNotification && n.metrics.pixels <= 0) {
      setState(() {
        // Pull friction 0.5 — supaya gerakan terasa "berat" (resistance)
        // bukan 1:1 dengan finger drag.
        _overscroll = (_overscroll + n.overscroll.abs() * 0.5)
            .clamp(0.0, widget.triggerOffset + 30);
      });
      // Threshold reached — haptic tap "armed".
      if (!_armed && _overscroll >= widget.triggerOffset) {
        _armed = true;
        AppHaptics.tap();
      }
    } else if (n is ScrollUpdateNotification && n.metrics.pixels > 0) {
      // User scroll ke bawah sebelum melepas → batal pull.
      if (_overscroll > 0) {
        setState(() {
          _overscroll = 0;
          _armed = false;
        });
      }
    } else if (n is ScrollEndNotification) {
      // Release — kalau armed → fire refresh, kalau tidak → snap back.
      if (_armed && _overscroll >= widget.triggerOffset) {
        _doRefresh();
      } else if (_overscroll > 0) {
        setState(() {
          _overscroll = 0;
          _armed = false;
        });
      }
    }
    return false;
  }

  Future<void> _doRefresh() async {
    setState(() {
      _isRefreshing = true;
      _overscroll = widget.triggerOffset;
    });
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
    _fadeCtrl.value = 1.0; // reset untuk next pull
  }

  @override
  Widget build(BuildContext context) {
    final visible = _overscroll > 0 || _isRefreshing;
    final progress = (_overscroll / widget.triggerOffset).clamp(0.0, 1.0);

    return Stack(
      fit: StackFit.expand,
      children: [
        // ScrollConfiguration force bouncing physics di Android supaya
        // OverscrollNotification fire saat user drag past top (default
        // ClampingScrollPhysics tidak fire → paw tidak armed di Android).
        ScrollConfiguration(
          behavior: const _NataloPawScrollBehavior(),
          child: NotificationListener<ScrollNotification>(
            onNotification: _handleScroll,
            child: widget.child,
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
                    // Scale: 0.5 → 1.0 based on pull progress, lock 1.0 saat refresh.
                    final scale = _isRefreshing ? 1.0 : 0.5 + (progress * 0.5);
                    // Rotation: 0 → π/2 saat pulling (turn-in feel),
                    // continuous spin saat refreshing.
                    final rotation = _isRefreshing
                        ? _spinCtrl.value * 2 * math.pi
                        : progress * math.pi * 0.5;
                    // Opacity: fade-in saat pull, fade-out saat exit.
                    final opacity = (_isRefreshing
                            ? _fadeCtrl.value
                            : progress.clamp(0.2, 1.0))
                        .clamp(0.0, 1.0);

                    return Opacity(
                      opacity: opacity,
                      child: Transform.scale(
                        scale: scale,
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
/// 1. Force `BouncingScrollPhysics` di semua platform — supaya overscroll
///    notification konsisten fire saat user drag past top (default Android
///    `ClampingScrollPhysics` tidak fire notification).
/// 2. Disable default Android glow / stretching overscroll indicator —
///    hindari dual indikator (glow + paw) tabrakan visual.
///
/// Drag device support disabled untuk web/desktop (default builder),
/// scrollbar tidak ditampilkan (sama seperti Material default mobile).
class _NataloPawScrollBehavior extends ScrollBehavior {
  const _NataloPawScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
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

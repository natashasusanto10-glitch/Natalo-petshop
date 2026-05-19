import 'package:flutter/material.dart';

import '../theme/natalo_colors.dart';
import '../utils/haptics.dart';

/// Wrapper di sekitar `RefreshIndicator` yang fire haptic feedback saat:
/// 1. **Trigger threshold reached** — user pull cukup jauh sampai indicator
///    siap fire. Tap haptic (light) supaya user tahu "kalau lepas sekarang
///    akan refresh".
/// 2. **Refresh executed** — selesai pulling + release, callback `onRefresh`
///    fires. Success haptic.
///
/// Drop-in replacement untuk `RefreshIndicator` — API sama. Native delight
/// detail yang Capacitor WebView tidak bisa replikasi smoothly (browser
/// pull-to-refresh tidak punya haptic API).
///
/// Usage:
/// ```dart
/// HapticRefreshIndicator(
///   onRefresh: () async => await _loadData(),
///   child: ListView(...),
/// )
/// ```
class HapticRefreshIndicator extends StatefulWidget {
  final Widget child;
  final Future<void> Function() onRefresh;
  final Color? color;
  final Color? backgroundColor;
  final double displacement;
  final ScrollNotificationPredicate? notificationPredicate;

  const HapticRefreshIndicator({
    super.key,
    required this.child,
    required this.onRefresh,
    this.color,
    this.backgroundColor,
    this.displacement = 40.0,
    this.notificationPredicate,
  });

  @override
  State<HapticRefreshIndicator> createState() => _HapticRefreshIndicatorState();
}

class _HapticRefreshIndicatorState extends State<HapticRefreshIndicator> {
  bool _hasFiredThresholdHaptic = false;

  Future<void> _onRefresh() async {
    // Reset threshold flag untuk next pull.
    _hasFiredThresholdHaptic = false;
    AppHaptics.success();
    await widget.onRefresh();
  }

  bool _onNotification(ScrollNotification notification) {
    // Detect saat overscroll cukup jauh untuk trigger refresh.
    // OverscrollNotification fires saat user pull beyond top edge.
    if (notification is OverscrollNotification) {
      // Tidak fire haptic threshold setiap pixel — cuma sekali per pull.
      if (!_hasFiredThresholdHaptic &&
          notification.overscroll.abs() > widget.displacement) {
        _hasFiredThresholdHaptic = true;
        AppHaptics.tap();
      }
    } else if (notification is ScrollEndNotification) {
      // Reset flag saat scroll selesai supaya pull berikutnya fire ulang.
      _hasFiredThresholdHaptic = false;
    }
    return false; // bubble notification up
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onNotification,
      child: RefreshIndicator(
        onRefresh: _onRefresh,
        // Branded default: Natalo blue spinner di atas white circle.
        // Konsisten visual identity vs Material blue generic.
        color: widget.color ?? NataloColors.primary,
        backgroundColor: widget.backgroundColor ?? Colors.white,
        displacement: widget.displacement,
        // Heavier stroke supaya spinner lebih visible saat pull pendek.
        // Material default 2.5 → 3.0 = +20% thickness, masih visually tasteful.
        strokeWidth: 3.0,
        notificationPredicate:
            widget.notificationPredicate ?? defaultScrollNotificationPredicate,
        child: widget.child,
      ),
    );
  }
}

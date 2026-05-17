import 'package:flutter/material.dart';

import '../utils/formatters.dart';
import '../utils/motion_prefs.dart';

/// Animated number ticker — angka berubah dengan smooth tween dari nilai
/// lama → baru. Pakai untuk:
/// - Total cart
/// - Poin loyalty
/// - Subtotal checkout
/// - Stock indicator
///
/// Respect MotionPrefs — kalau reduce motion, langsung jump ke nilai baru.
class AnimatedCounter extends StatelessWidget {
  final num value;
  final TextStyle? style;
  final Duration duration;
  final Curve curve;
  final String Function(num value)? formatter;
  final String? prefix;
  final String? suffix;

  const AnimatedCounter({
    super.key,
    required this.value,
    this.style,
    this.duration = const Duration(milliseconds: 600),
    this.curve = Curves.easeOutCubic,
    this.formatter,
    this.prefix,
    this.suffix,
  });

  String _format(num v) {
    if (formatter != null) return formatter!(v);
    return v.round().toString();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MotionPrefs.shouldReduce(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: value.toDouble(), end: value.toDouble()),
      duration: reduce ? Duration.zero : duration,
      curve: curve,
      builder: (context, animated, _) {
        final text =
            '${prefix ?? ''}${_format(animated)}${suffix ?? ''}';
        return Text(text, style: style);
      },
    );
  }
}

/// Animated rupiah formatter — wrapper convenience untuk price ticker.
class AnimatedRupiah extends StatelessWidget {
  final num value;
  final TextStyle? style;
  final Duration duration;

  const AnimatedRupiah({
    super.key,
    required this.value,
    this.style,
    this.duration = const Duration(milliseconds: 500),
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedCounter(
      value: value,
      style: style,
      duration: duration,
      formatter: (v) => formatRupiah(v.toDouble()),
    );
  }
}

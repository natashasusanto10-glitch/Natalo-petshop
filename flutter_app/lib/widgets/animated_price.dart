import 'package:flutter/material.dart';

import '../utils/formatters.dart';

/// Price text yang animate saat value berubah (mis. ganti varian, qty).
/// Tween via implicit TweenAnimationBuilder — no manual controller.
class AnimatedPrice extends StatelessWidget {
  /// Boleh dipanggil dengan `value` ATAU `price` — same thing.
  final int? value;
  final int? price;
  final TextStyle? style;
  final Duration duration;

  const AnimatedPrice({
    super.key,
    this.value,
    this.price,
    this.style,
    this.duration = const Duration(milliseconds: 280),
  }) : assert(value != null || price != null,
            'AnimatedPrice butuh value atau price');

  int get _effectiveValue => (value ?? price)!;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(
        begin: _effectiveValue.toDouble(),
        end: _effectiveValue.toDouble(),
      ),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) {
        return Text(formatRupiah(v), style: style);
      },
    );
  }
}

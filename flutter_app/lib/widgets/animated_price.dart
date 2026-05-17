import 'package:flutter/material.dart';

import '../utils/formatters.dart';

/// Animated price label — saat [price] berubah (mis. user pilih varian),
/// angka ber-tween smoothly dari value lama → value baru (~360ms cubic ease).
///
/// Capacitor / web: harga langsung ganti (snap) — feels abrupt. Flutter
/// native bisa tween dengan smooth interpolation yang GPU-accelerated.
///
/// Pattern: track [_previousPrice] di state, rebuild dengan
/// Tween(begin: previous, end: current) saat didUpdateWidget detect change.
class AnimatedPrice extends StatefulWidget {
  final double price;
  final TextStyle? style;
  final Duration duration;

  const AnimatedPrice({
    super.key,
    required this.price,
    this.style,
    this.duration = const Duration(milliseconds: 360),
  });

  @override
  State<AnimatedPrice> createState() => _AnimatedPriceState();
}

class _AnimatedPriceState extends State<AnimatedPrice> {
  late double _previous = widget.price;

  @override
  void didUpdateWidget(covariant AnimatedPrice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.price != widget.price) {
      _previous = oldWidget.price;
    }
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: _previous, end: widget.price),
      duration: widget.duration,
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Text(
          formatRupiah(value),
          style: widget.style,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}

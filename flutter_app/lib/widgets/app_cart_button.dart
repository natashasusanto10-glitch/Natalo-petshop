import 'package:flutter/material.dart';

import '../state/cart_store.dart';
import '../utils/haptics.dart';
import 'app_ui.dart';

/// Cart button dengan **animated badge bounce** saat item baru ditambah.
/// Ini salah satu detail kecil yang Flutter native bisa lakukan lebih
/// baik dari Capacitor — CSS keyframe di WebView bisa, tapi:
/// 1. Tidak GPU-accelerated → frame drop saat banyak hal render
/// 2. Susah trigger via state change reactive
/// 3. Spring physics lebih natural dengan SpringSimulation Flutter
///
/// Detection: track count sebelumnya — kalau naik, animate badge.
class AppCartButton extends StatefulWidget {
  const AppCartButton({super.key});

  @override
  State<AppCartButton> createState() => _AppCartButtonState();
}

class _AppCartButtonState extends State<AppCartButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _bagWiggle;
  int _lastCount = cartStore.totalQuantity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    // Spring-like scale: 1 → 1.4 → 1 dengan overshoot kecil.
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.45)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.45, end: 0.92)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.92, end: 1.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 40,
      ),
    ]).animate(_controller);
    // Bag icon "wiggle" — rotate kecil saat add to cart untuk emphasize.
    _bagWiggle = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: -0.12)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: Tween(begin: -0.12, end: 0.10)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.10, end: 0.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 50,
      ),
    ]).animate(_controller);

    cartStore.addListener(_onCartChanged);
  }

  @override
  void dispose() {
    cartStore.removeListener(_onCartChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onCartChanged() {
    final current = cartStore.totalQuantity;
    if (current > _lastCount) {
      // Hanya animate saat ada item baru (bukan saat decrement / remove).
      _controller.forward(from: 0);
    }
    _lastCount = current;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: cartStore,
      builder: (context, _) {
        final count = cartStore.totalQuantity;
        return AppHeaderIconButton(
          tooltip: 'Keranjang',
          onPressed: () {
            AppHaptics.tap();
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            Navigator.pushNamed(context, '/cart');
          },
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Transform.rotate(
                angle: _bagWiggle.value,
                child: Transform.scale(
                  scale: _scale.value,
                  child: child,
                ),
              );
            },
            child: Badge(
              isLabelVisible: count > 0,
              backgroundColor: const Color(0xFFEF4444),
              label: Text(count > 99 ? '99+' : '$count'),
              child: const Icon(Icons.shopping_bag_outlined),
            ),
          ),
        );
      },
    );
  }
}

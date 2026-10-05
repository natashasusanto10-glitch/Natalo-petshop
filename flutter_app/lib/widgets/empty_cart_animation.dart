import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../utils/motion_prefs.dart';

/// Shared vector animation: pets put products into a shopping basket.
class EmptyCartAnimation extends StatefulWidget {
  const EmptyCartAnimation({super.key});

  @override
  State<EmptyCartAnimation> createState() => _EmptyCartAnimationState();
}

class _EmptyCartAnimationState extends State<EmptyCartAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    motionPrefs.addListener(_syncMotion);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  void _syncMotion() {
    if (!_loaded || !mounted) return;
    if (MotionPrefs.shouldReduce(context)) {
      _controller.stop();
      _controller.value = 0.8;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    motionPrefs.removeListener(_syncMotion);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        height: 210,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Lottie.asset(
              'assets/lottie/cart-pets-basket-v1.json',
              controller: _controller,
              fit: BoxFit.contain,
              onLoaded: (composition) {
                _controller.duration = composition.duration;
                _loaded = true;
                _syncMotion();
              },
              errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.shopping_basket_outlined,
                size: 80,
                color: Color(0xFF1974BF),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../utils/motion_prefs.dart';

/// Plays the approved pets illustration once, then holds the confirmation pose.
class OrderCreatedAnimation extends StatefulWidget {
  const OrderCreatedAnimation({super.key});

  @override
  State<OrderCreatedAnimation> createState() => _OrderCreatedAnimationState();
}

class _OrderCreatedAnimationState extends State<OrderCreatedAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
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
      _controller.value = 1;
    } else if (!_controller.isAnimating && !_controller.isCompleted) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    motionPrefs.removeListener(_syncMotion);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: RepaintBoundary(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: ColoredBox(
              color: Colors.white,
              child: Lottie.asset(
                'assets/lottie/order_created_pets.json',
                width: 180,
                height: 150,
                fit: BoxFit.contain,
                controller: _controller,
                repeat: false,
                frameRate: const FrameRate(30),
                onLoaded: (composition) {
                  _controller.duration = composition.duration;
                  _loaded = true;
                  _syncMotion();
                },
                errorBuilder: (_, __, ___) => const SizedBox(
                  width: 180,
                  height: 150,
                  child: Icon(Icons.task_alt_rounded,
                      size: 72, color: Color(0xFF0CA87C)),
                ),
              ),
            ),
          ),
        ),
      );
}

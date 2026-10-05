import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../utils/motion_prefs.dart';

/// Shared vector animation: pets peek behind saved product cards.
class EmptyWishlistAnimation extends StatefulWidget {
  const EmptyWishlistAnimation({super.key});

  @override
  State<EmptyWishlistAnimation> createState() => _EmptyWishlistAnimationState();
}

class _EmptyWishlistAnimationState extends State<EmptyWishlistAnimation>
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
      _controller.value = 0.75;
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
              'assets/lottie/wishlist-pets-cards-v1.json',
              controller: _controller,
              fit: BoxFit.contain,
              onLoaded: (composition) {
                _controller.duration = composition.duration;
                _loaded = true;
                _syncMotion();
              },
              errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.bookmarks_outlined,
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

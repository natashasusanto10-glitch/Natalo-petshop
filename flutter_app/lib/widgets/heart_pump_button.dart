import 'package:flutter/material.dart';

import '../utils/haptics.dart';
import '../utils/motion_prefs.dart';

/// Wishlist heart yang punya pump animation saat tap.
/// - Tap → haptic light tap → heart scale 1.0 → 1.4 → 1.0 dengan
///   elastic curve, color transition cepat
/// - State `liked` di-control parent (optimistic update friendly)
class HeartPumpButton extends StatefulWidget {
  final bool liked;
  final VoidCallback onTap;
  final double size;
  final Color likedColor;
  final Color unlikedColor;

  const HeartPumpButton({
    super.key,
    required this.liked,
    required this.onTap,
    this.size = 24,
    this.likedColor = const Color(0xFFEF4444),
    this.unlikedColor = const Color(0xFF9CA3AF),
  });

  @override
  State<HeartPumpButton> createState() => _HeartPumpButtonState();
}

class _HeartPumpButtonState extends State<HeartPumpButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1.0, end: 1.4)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1.4, end: 1.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 60,
      ),
    ]).animate(_controller);
  }

  @override
  void didUpdateWidget(HeartPumpButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.liked != widget.liked && widget.liked) {
      // Only animate saat dari unliked → liked (positive feedback).
      _controller
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MotionPrefs.shouldReduce(context);
    return GestureDetector(
      onTap: () {
        AppHaptics.tap();
        widget.onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _scale,
        builder: (context, _) {
          return Transform.scale(
            scale: reduce ? 1.0 : _scale.value,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, anim) =>
                  ScaleTransition(scale: anim, child: child),
              child: Icon(
                widget.liked
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                key: ValueKey(widget.liked),
                size: widget.size,
                color: widget.liked ? widget.likedColor : widget.unlikedColor,
              ),
            ),
          );
        },
      ),
    );
  }
}

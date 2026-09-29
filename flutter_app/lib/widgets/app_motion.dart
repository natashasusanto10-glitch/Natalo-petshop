import 'package:flutter/material.dart';

import '../theme/app_motion_tokens.dart';
import '../utils/motion_prefs.dart';

/// Wrapper untuk fade+slide-in entry animation, respect reduce-motion.
/// Dipakai di list/grid item supaya muncul smooth tanpa popping.
class AppFadeSlideIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;
  final Offset beginOffset;

  const AppFadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = AppMotionTokens.standard,
    this.beginOffset = const Offset(0, 0.06),
  });

  @override
  State<AppFadeSlideIn> createState() => _AppFadeSlideInState();
}

class _AppFadeSlideInState extends State<AppFadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MotionPrefs.shouldReduce(context)) {
      return widget.child;
    }
    final curved = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(begin: widget.beginOffset, end: Offset.zero)
            .animate(curved),
        child: widget.child,
      ),
    );
  }
}

/// TransitionBuilder bersama untuk AnimatedSwitcher: fade + scale mulai
/// 0.96 — pengganti default Flutter (ScaleTransition penuh dari scale(0),
/// konten terlihat "muncul dari titik nol"). Jangan dipakai di ikon
/// micro-delight (heart burst) yang pop-nya memang disengaja.
Widget appFadeScaleTransition(Widget child, Animation<double> animation) {
  return FadeTransition(
    opacity: animation,
    child: ScaleTransition(
      scale: Tween<double>(begin: 0.96, end: 1.0).animate(animation),
      child: child,
    ),
  );
}

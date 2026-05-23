import 'package:flutter/material.dart';

import '../utils/action_throttle.dart';
import '../utils/haptics.dart';

/// Submit button yang menampilkan spinner saat loading.
/// - Text label hilang, replace dengan CircularProgressIndicator
/// - Disabled state otomatis saat loading
/// - Haptic tap di-fire saat pressed
///
/// Pakai instead of ElevatedButton manual untuk semua form submit
/// (login, register, checkout, address save, dll).
class LoadingButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final bool loading;
  final Widget child;
  final ButtonStyle? style;
  final IconData? icon;
  final Color? color;
  final Duration throttleDuration;

  const LoadingButton({
    super.key,
    required this.onPressed,
    required this.loading,
    required this.child,
    this.style,
    this.icon,
    this.color,
    this.throttleDuration = const Duration(milliseconds: 900),
  });

  @override
  State<LoadingButton> createState() => _LoadingButtonState();
}

class _LoadingButtonState extends State<LoadingButton> {
  late final ActionThrottle _throttle;

  @override
  void initState() {
    super.initState();
    _throttle = ActionThrottle(interval: widget.throttleDuration);
  }

  @override
  void didUpdateWidget(covariant LoadingButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loading && !widget.loading) {
      _throttle.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = widget.style ??
        ElevatedButton.styleFrom(
          backgroundColor: widget.color ?? const Color(0xFF1E5FBF),
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        );

    return ElevatedButton(
      onPressed: widget.loading
          ? null
          : () {
              _throttle.run(() {
                AppHaptics.tap();
                widget.onPressed?.call();
              });
            },
      style: effectiveStyle,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: ScaleTransition(scale: anim, child: child),
        ),
        child: widget.loading
            ? const SizedBox(
                key: ValueKey('loading'),
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              )
            : Row(
                key: const ValueKey('label'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, size: 18),
                    const SizedBox(width: 8),
                  ],
                  widget.child,
                ],
              ),
      ),
    );
  }
}

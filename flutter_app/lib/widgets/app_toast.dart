import 'dart:ui';

import 'package:flutter/material.dart';

import '../utils/haptics.dart';
import '../utils/motion_prefs.dart';

enum ToastKind { info, success, warning, error }

/// Custom toast yang slide dari top + fade out. Pakai instead of
/// default SnackBar untuk feels lebih branded + native iOS-style.
///
/// Pakai:
/// ```dart
/// AppToast.show(context, 'Berhasil ditambahkan ke cart', kind: ToastKind.success);
/// ```
class AppToast {
  static void show(
    BuildContext context,
    String message, {
    ToastKind kind = ToastKind.info,
    Duration duration = const Duration(seconds: 2),
    IconData? icon,
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);
    final entry = OverlayEntry(
      builder: (ctx) => _ToastView(
        message: message,
        kind: kind,
        icon: icon,
        duration: duration,
      ),
    );
    overlay.insert(entry);
    _doHaptic(kind);
    Future.delayed(duration + const Duration(milliseconds: 350), () {
      try {
        entry.remove();
      } catch (_) {}
    });
  }

  static void _doHaptic(ToastKind kind) {
    switch (kind) {
      case ToastKind.success:
        AppHaptics.success();
        break;
      case ToastKind.warning:
      case ToastKind.error:
        AppHaptics.warning();
        break;
      case ToastKind.info:
        AppHaptics.tap();
        break;
    }
  }

  static void showCartAdded(
    BuildContext context,
    String message, {
    Duration duration = const Duration(milliseconds: 1700),
    VoidCallback? onTap,
    String actionLabel = 'Lihat',
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);
    final entry = OverlayEntry(
      builder: (ctx) => _CartToastView(
        message: message,
        duration: duration,
        onTap: onTap,
        actionLabel: actionLabel,
      ),
    );
    overlay.insert(entry);
    AppHaptics.success();
    Future.delayed(duration + const Duration(milliseconds: 300), () {
      try {
        entry.remove();
      } catch (_) {}
    });
  }

  static void showCartDeleted(
    BuildContext context,
    String message, {
    Duration duration = const Duration(milliseconds: 1700),
    required VoidCallback onUndo,
  }) {
    showCartAdded(
      context,
      message,
      duration: duration,
      onTap: onUndo,
      actionLabel: 'Urungkan',
    );
  }
}

class _ToastView extends StatefulWidget {
  final String message;
  final ToastKind kind;
  final IconData? icon;
  final Duration duration;

  const _ToastView({
    required this.message,
    required this.kind,
    required this.icon,
    required this.duration,
  });

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _CartToastView extends StatefulWidget {
  final String message;
  final Duration duration;
  final VoidCallback? onTap;
  final String actionLabel;

  const _CartToastView({
    required this.message,
    required this.duration,
    required this.onTap,
    required this.actionLabel,
  });

  @override
  State<_CartToastView> createState() => _CartToastViewState();
}

class _CartToastViewState extends State<_CartToastView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 220),
    );
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.45),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward();
    Future.delayed(widget.duration, () {
      if (mounted) _controller.reverse();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MotionPrefs.shouldReduce(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Positioned(
      left: 0,
      right: 0,
      bottom: bottomInset + 84,
      child: IgnorePointer(
        ignoring: widget.onTap == null,
        child: SafeArea(
          top: false,
          bottom: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: SlideTransition(
                position:
                    reduce ? const AlwaysStoppedAnimation(Offset.zero) : _slide,
                child: FadeTransition(
                  opacity: _opacity,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: widget.onTap,
                        borderRadius: BorderRadius.circular(999),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.72),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.14),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.22),
                                    blurRadius: 22,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.white.withValues(alpha: 0.16),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.shopping_bag_rounded,
                                      color: Colors.white,
                                      size: 15,
                                    ),
                                  ),
                                  const SizedBox(width: 9),
                                  Flexible(
                                    child: Text(
                                      widget.message,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w800,
                                        height: 1.2,
                                      ),
                                    ),
                                  ),
                                  if (widget.onTap != null) ...[
                                    const SizedBox(width: 10),
                                    Text(
                                      widget.actionLabel,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w900,
                                        height: 1.2,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToastViewState extends State<_ToastView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, -0.4),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward();
    Future.delayed(widget.duration, () {
      if (mounted) _controller.reverse();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  ({Color bg, Color fg, IconData icon}) _theme() {
    switch (widget.kind) {
      case ToastKind.success:
        return (
          bg: const Color(0xFF16A34A),
          fg: Colors.white,
          icon: widget.icon ?? Icons.check_circle_rounded,
        );
      case ToastKind.warning:
        return (
          bg: const Color(0xFFF59E0B),
          fg: Colors.white,
          icon: widget.icon ?? Icons.warning_amber_rounded,
        );
      case ToastKind.error:
        return (
          bg: const Color(0xFFEF4444),
          fg: Colors.white,
          icon: widget.icon ?? Icons.error_rounded,
        );
      case ToastKind.info:
        return (
          bg: const Color(0xFF1E5FBF),
          fg: Colors.white,
          icon: widget.icon ?? Icons.info_outline_rounded,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = _theme();
    final reduce = MotionPrefs.shouldReduce(context);
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: SlideTransition(
            position:
                reduce ? const AlwaysStoppedAnimation(Offset.zero) : _slide,
            child: FadeTransition(
              opacity: _opacity,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: theme.bg,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(theme.icon, color: theme.fg, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.message,
                          style: TextStyle(
                            color: theme.fg,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

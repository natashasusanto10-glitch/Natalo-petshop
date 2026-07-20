import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/natalo_colors.dart';
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
    String? imageUrl,
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);
    final entry = OverlayEntry(
      builder: (ctx) => _CartToastView(
        message: message,
        duration: duration,
        onTap: onTap,
        actionLabel: actionLabel,
        imageUrl: imageUrl,
        fallbackIcon: Icons.shopping_bag_rounded,
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
    String? imageUrl,
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);
    final entry = OverlayEntry(
      builder: (ctx) => _CartToastView(
        message: message,
        duration: duration,
        onTap: onUndo,
        actionLabel: 'Urungkan',
        imageUrl: imageUrl,
        fallbackIcon: Icons.delete_outline_rounded,
      ),
    );
    overlay.insert(entry);
    AppHaptics.warning();
    Future.delayed(duration + const Duration(milliseconds: 300), () {
      try {
        entry.remove();
      } catch (_) {}
    });
  }

  /// Premium bottom banner — content-hug glass card dengan ikon berwarna,
  /// subtitle + aksi opsional, dan garis hitung-mundur. Overlay-based (root)
  /// jadi auto-hide TIDAK terganggu Navigator.push/pop — pengganti aman untuk
  /// SnackBar Material yang bisa "nyangkut" saat pindah route.
  static void showBanner(
    BuildContext context,
    String message, {
    String? subtitle,
    ToastKind kind = ToastKind.info,
    IconData? icon,
    Duration duration = const Duration(seconds: 3),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _BannerToastView(
        message: message,
        subtitle: subtitle,
        kind: kind,
        icon: icon,
        duration: duration,
        actionLabel: actionLabel,
        onAction: onAction,
      ),
    );
    overlay.insert(entry);
    _doHaptic(kind);
    Future.delayed(duration + const Duration(milliseconds: 650), () {
      try {
        entry.remove();
      } catch (_) {}
    });
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
  final String? imageUrl;
  final IconData fallbackIcon;

  const _CartToastView({
    required this.message,
    required this.duration,
    required this.onTap,
    required this.actionLabel,
    required this.imageUrl,
    required this.fallbackIcon,
  });

  @override
  State<_CartToastView> createState() => _CartToastViewState();
}

class _CartToastIcon extends StatelessWidget {
  final IconData icon;

  const _CartToastIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      color: Colors.white.withValues(alpha: 0.12),
      child: Icon(icon, color: Colors.white, size: 17),
    );
  }
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
                        borderRadius: BorderRadius.circular(16),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 9,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.72),
                                borderRadius: BorderRadius.circular(16),
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
                                  // Thumbnail produk asli kalau tersedia —
                                  // jauh lebih informatif dari ikon generik.
                                  // Fallback ke ikon bulat (bag/trash) kalau
                                  // tidak ada satu produk yang representatif
                                  // (mis. hapus banyak item sekaligus).
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(9),
                                    child: widget.imageUrl != null
                                        ? Image.network(
                                            widget.imageUrl!,
                                            width: 34,
                                            height: 34,
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (_, __, ___) => _CartToastIcon(
                                              icon: widget.fallbackIcon,
                                            ),
                                          )
                                        : _CartToastIcon(
                                            icon: widget.fallbackIcon,
                                          ),
                                  ),
                                  const SizedBox(width: 10),
                                  Flexible(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 2,
                                      ),
                                      child: Text(
                                        widget.message,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                          height: 1.25,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (widget.onTap != null) ...[
                                    Container(
                                      width: 1,
                                      height: 22,
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                      color: Colors.white.withValues(
                                        alpha: 0.14,
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        right: 4,
                                      ),
                                      child: Text(
                                        widget.actionLabel,
                                        style: const TextStyle(
                                          color: Color(0xFF5AA2F0),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          height: 1.2,
                                        ),
                                      ),
                                    ),
                                  ] else
                                    const SizedBox(width: 5),
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
          bg: NataloColors.successDark,
          fg: NataloColors.white,
          icon: widget.icon ?? Icons.check_circle_rounded,
        );
      case ToastKind.warning:
        return (
          bg: NataloColors.warning,
          fg: NataloColors.white,
          icon: widget.icon ?? Icons.warning_amber_rounded,
        );
      case ToastKind.error:
        return (
          bg: NataloColors.danger,
          fg: NataloColors.white,
          icon: widget.icon ?? Icons.error_rounded,
        );
      case ToastKind.info:
        return (
          bg: NataloColors.primary,
          fg: NataloColors.white,
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

class _BannerToastView extends StatefulWidget {
  final String message;
  final String? subtitle;
  final ToastKind kind;
  final IconData? icon;
  final Duration duration;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _BannerToastView({
    required this.message,
    required this.subtitle,
    required this.kind,
    required this.icon,
    required this.duration,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  State<_BannerToastView> createState() => _BannerToastViewState();
}

class _BannerToastViewState extends State<_BannerToastView>
    with TickerProviderStateMixin {
  late final AnimationController _inOut;
  late final AnimationController _countdown;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _inOut = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 220),
    );
    _opacity = CurvedAnimation(parent: _inOut, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.45), end: Offset.zero)
        .animate(CurvedAnimation(parent: _inOut, curve: Curves.easeOutCubic));
    _countdown = AnimationController(vsync: this, duration: widget.duration)
      ..forward();
    _inOut.forward();
    Future.delayed(widget.duration, () {
      if (mounted) _inOut.reverse();
    });
  }

  @override
  void dispose() {
    _inOut.dispose();
    _countdown.dispose();
    super.dispose();
  }

  ({Color accent, IconData icon}) _kindStyle() {
    switch (widget.kind) {
      case ToastKind.success:
        return (accent: NataloColors.successDark, icon: Icons.check_circle_rounded);
      case ToastKind.warning:
        return (accent: const Color(0xFFC98A12), icon: Icons.warning_amber_rounded);
      case ToastKind.error:
        return (accent: NataloColors.danger, icon: Icons.error_rounded);
      case ToastKind.info:
        return (accent: NataloColors.primary, icon: Icons.info_outline_rounded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MotionPrefs.shouldReduce(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final style = _kindStyle();
    final iconData = widget.icon ?? style.icon;

    final card = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onAction,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFECEFF3)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: EdgeInsets.only(
                    left: 12,
                    right: widget.actionLabel != null ? 4 : 12,
                    top: 10,
                    bottom: 10,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(iconData, color: style.accent, size: 19),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.message,
                              maxLines: widget.subtitle == null ? 2 : 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF0F172A),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                height: 1.25,
                              ),
                            ),
                            if (widget.subtitle != null)
                              Text(
                                widget.subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF64748B),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  height: 1.25,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (widget.actionLabel != null) ...[
                        const SizedBox(width: 6),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            widget.actionLabel!,
                            style: const TextStyle(
                              color: NataloColors.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(
                  height: 2.5,
                  child: AnimatedBuilder(
                    animation: _countdown,
                    builder: (context, _) => FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: 1 - _countdown.value,
                      child: Container(color: style.accent),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Positioned(
      left: 0,
      right: 0,
      bottom: bottomInset + 84,
      child: IgnorePointer(
        ignoring: widget.onAction == null,
        child: SafeArea(
          top: false,
          bottom: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: SlideTransition(
                position:
                    reduce ? const AlwaysStoppedAnimation(Offset.zero) : _slide,
                child: FadeTransition(opacity: _opacity, child: card),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

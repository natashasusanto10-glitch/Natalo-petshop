import 'package:flutter/material.dart';

import '../../utils/action_throttle.dart';

enum NataloPostActionIconType {
  like,
  comment,
  share,
}

class NataloPostActionIcon extends StatelessWidget {
  const NataloPostActionIcon({
    super.key,
    required this.type,
    this.size = 24,
    this.color = const Color(0xFF111111),
    this.activeColor = const Color(0xFFE53935),
    this.disabledColor = const Color(0xFFBDBDBD),
    this.strokeWidth = 2.05,
    this.isActive = false,
    this.isDisabled = false,
  });

  final NataloPostActionIconType type;
  final double size;
  final Color color;
  final Color activeColor;
  final Color disabledColor;
  final double strokeWidth;
  final bool isActive;
  final bool isDisabled;

  @override
  Widget build(BuildContext context) {
    final iconColor = isDisabled
        ? disabledColor
        : isActive && type == NataloPostActionIconType.like
            ? activeColor
            : color;

    return CustomPaint(
      size: Size.square(size),
      painter: _NataloPostActionIconPainter(
        type: type,
        color: iconColor,
        strokeWidth: strokeWidth,
        isActive: isActive && type == NataloPostActionIconType.like,
      ),
    );
  }
}

class NataloPostActionButton extends StatefulWidget {
  const NataloPostActionButton({
    super.key,
    required this.type,
    required this.onTap,
    this.isActive = false,
    this.isDisabled = false,
    this.iconSize = 24,
    this.tapSize = 44,
    this.color = const Color(0xFF111111),
    this.activeColor = const Color(0xFFE53935),
    this.disabledColor = const Color(0xFFBDBDBD),
    this.strokeWidth = 2.05,
    this.semanticLabel,
    this.count,
    this.countColor = const Color(0xFF111111),
    this.throttleDuration = const Duration(milliseconds: 450),
  });

  final NataloPostActionIconType type;
  final VoidCallback? onTap;
  final bool isActive;
  final bool isDisabled;
  final double iconSize;
  final double tapSize;
  final Color color;
  final Color activeColor;
  final Color disabledColor;

  /// Stroke weight icon — light outline for an Instagram-like action row.
  final double strokeWidth;
  final String? semanticLabel;

  /// Optional count yang di-render di samping icon (inline horizontal).
  /// Null atau 0 → hide count, button kembali ke layout square icon-only
  /// (match Instagram convention "hide '0 likes'"). Non-zero → tampilkan
  /// formatted number (12, 1.2K, 1.5M, dst). Tap area otomatis expand
  /// untuk cover icon + count text.
  final int? count;

  /// Warna text count. Default ink dark — caller bisa override untuk
  /// dark mode atau context khusus (mis. white kalau di atas image).
  final Color countColor;

  final Duration throttleDuration;

  @override
  State<NataloPostActionButton> createState() => _NataloPostActionButtonState();
}

class _NataloPostActionButtonState extends State<NataloPostActionButton> {
  late final ActionThrottle _throttle;

  @override
  void initState() {
    super.initState();
    _throttle = ActionThrottle(interval: widget.throttleDuration);
  }

  @override
  Widget build(BuildContext context) {
    final showCount = widget.count != null && widget.count! > 0;
    final iconWidget = NataloPostActionIcon(
      type: widget.type,
      size: widget.iconSize,
      color: widget.color,
      activeColor: widget.activeColor,
      disabledColor: widget.disabledColor,
      strokeWidth: widget.strokeWidth,
      isActive: widget.isActive,
      isDisabled: widget.isDisabled,
    );
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      enabled: !widget.isDisabled,
      child: InkResponse(
        onTap: widget.isDisabled ? null : () => _throttle.run(widget.onTap),
        radius: widget.tapSize / 2,
        containedInkWell: false,
        child: showCount
            // Inline mode: icon + spacer + count text. Tap area = icon
            // + text. Horizontal padding 6 ngasih breathing room antar
            // action group dalam Row di parent.
            ? Container(
                constraints: BoxConstraints(minHeight: widget.tapSize),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    iconWidget,
                    const SizedBox(width: 6),
                    // AnimatedSwitcher untuk count → angka baru slide up
                    // dari bawah, angka lama slide up keluar atas. IG /
                    // Twitter pattern saat like count naik 1. ValueKey wajib
                    // supaya widget di-rebuild saat count berubah.
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 240),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) {
                        final inAnim = Tween<Offset>(
                          begin: const Offset(0, 0.6),
                          end: Offset.zero,
                        ).animate(animation);
                        return ClipRect(
                          child: SlideTransition(
                            position: inAnim,
                            child: FadeTransition(
                              opacity: animation,
                              child: child,
                            ),
                          ),
                        );
                      },
                      child: Text(
                        _formatActionCount(widget.count!),
                        key: ValueKey<int>(widget.count!),
                        style: TextStyle(
                          color: widget.isDisabled
                              ? widget.disabledColor
                              : widget.countColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            // Icon-only mode (count null/0): preserve existing square tap.
            : SizedBox.square(
                dimension: widget.tapSize,
                child: Center(child: iconWidget),
              ),
      ),
    );
  }
}

/// Format count IG/TikTok style:
///   < 1000     → "12"
///   1000-999K  → "1.2K"
///   ≥ 1M       → "1.5M"
String _formatActionCount(int count) {
  if (count >= 1000000) {
    return '${(count / 1000000).toStringAsFixed(1)}M';
  }
  if (count >= 1000) {
    return '${(count / 1000).toStringAsFixed(1)}K';
  }
  return '$count';
}

class _NataloPostActionIconPainter extends CustomPainter {
  const _NataloPostActionIconPainter({
    required this.type,
    required this.color,
    required this.strokeWidth,
    required this.isActive,
  });

  final NataloPostActionIconType type;
  final Color color;
  final double strokeWidth;
  final bool isActive;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24;

    canvas
      ..save()
      ..scale(scale, scale);

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    switch (type) {
      case NataloPostActionIconType.like:
        final path = _heartPath();
        if (isActive) {
          canvas.drawPath(path, fillPaint);
        }
        canvas.drawPath(path, strokePaint);
        break;
      case NataloPostActionIconType.comment:
        canvas.drawPath(_commentPath(), strokePaint);
        break;
      case NataloPostActionIconType.share:
        canvas.drawPath(_sharePath(), strokePaint);
        break;
    }

    canvas.restore();
  }

  Path _heartPath() {
    return Path()
      ..moveTo(12, 20.25)
      ..cubicTo(11.25, 19.55, 8.2, 16.75, 5.85, 14.2)
      ..cubicTo(3.8, 11.95, 3.1, 10.2, 3.1, 8.3)
      ..cubicTo(3.1, 5.55, 5.25, 3.6, 8.1, 3.6)
      ..cubicTo(9.75, 3.6, 11.05, 4.3, 12, 5.55)
      ..cubicTo(12.95, 4.3, 14.25, 3.6, 15.9, 3.6)
      ..cubicTo(18.75, 3.6, 20.9, 5.55, 20.9, 8.3)
      ..cubicTo(20.9, 10.2, 20.2, 11.95, 18.15, 14.2)
      ..cubicTo(15.8, 16.75, 12.75, 19.55, 12, 20.25)
      ..close();
  }

  Path _commentPath() {
    return Path()
      ..moveTo(12.45, 4.05)
      ..cubicTo(17.55, 4.05, 21.1, 7.2, 21.1, 11.25)
      ..cubicTo(21.1, 15.35, 17.55, 18.35, 12.45, 18.35)
      ..cubicTo(11.35, 18.35, 10.35, 18.2, 9.4, 17.9)
      ..lineTo(4.45, 20.4)
      ..lineTo(6.05, 15.85)
      ..cubicTo(4.3, 14.65, 3.15, 13.05, 3.15, 11.25)
      ..cubicTo(3.15, 7.2, 6.7, 4.05, 12.45, 4.05)
      ..close();
  }

  Path _sharePath() {
    return Path()
      ..moveTo(4.0, 19.2)
      ..cubicTo(4.4, 12.3, 8.4, 8.0, 13.5, 8.0)
      ..lineTo(13.5, 3.7)
      ..lineTo(21.0, 10.4)
      ..lineTo(13.5, 17.1)
      ..lineTo(13.5, 12.9)
      ..cubicTo(9.6, 13.0, 6.6, 15.0, 4.0, 19.2);
  }

  @override
  bool shouldRepaint(covariant _NataloPostActionIconPainter oldDelegate) {
    return oldDelegate.type != type ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.isActive != isActive;
  }
}

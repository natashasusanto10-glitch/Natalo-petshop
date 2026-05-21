import 'package:flutter/material.dart';

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
    this.strokeWidth = 2.2,
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

class NataloPostActionButton extends StatelessWidget {
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
    this.semanticLabel,
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
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      enabled: !isDisabled,
      child: InkResponse(
        onTap: isDisabled ? null : onTap,
        radius: tapSize / 2,
        containedInkWell: false,
        child: SizedBox.square(
          dimension: tapSize,
          child: Center(
            child: NataloPostActionIcon(
              type: type,
              size: iconSize,
              color: color,
              activeColor: activeColor,
              disabledColor: disabledColor,
              isActive: isActive,
              isDisabled: isDisabled,
            ),
          ),
        ),
      ),
    );
  }
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
      ..moveTo(3.65, 5.45)
      ..lineTo(20.85, 3.8)
      ..lineTo(14.25, 18.65)
      ..lineTo(11.1, 12.65)
      ..lineTo(3.65, 9.85)
      ..lineTo(20.85, 3.8)
      ..moveTo(11.1, 12.65)
      ..lineTo(16.25, 8.2);
  }

  @override
  bool shouldRepaint(covariant _NataloPostActionIconPainter oldDelegate) {
    return oldDelegate.type != type ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.isActive != isActive;
  }
}

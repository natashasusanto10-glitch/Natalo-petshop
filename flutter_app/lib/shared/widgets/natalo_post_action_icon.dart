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
      ..moveTo(12, 20.8)
      ..cubicTo(11.15, 20.05, 8.15, 17.35, 5.85, 14.65)
      ..cubicTo(3.9, 12.35, 3.1, 10.45, 3.1, 8.45)
      ..cubicTo(3.1, 5.7, 5.2, 3.65, 7.9, 3.65)
      ..cubicTo(9.55, 3.65, 11.05, 4.45, 12, 5.8)
      ..cubicTo(12.95, 4.45, 14.45, 3.65, 16.1, 3.65)
      ..cubicTo(18.8, 3.65, 20.9, 5.7, 20.9, 8.45)
      ..cubicTo(20.9, 10.45, 20.1, 12.35, 18.15, 14.65)
      ..cubicTo(15.85, 17.35, 12.85, 20.05, 12, 20.8)
      ..close();
  }

  Path _commentPath() {
    return Path()
      ..moveTo(12, 4.15)
      ..cubicTo(6.95, 4.15, 3.35, 7.25, 3.35, 11.25)
      ..cubicTo(3.35, 15.25, 6.95, 18.35, 12, 18.35)
      ..cubicTo(13.05, 18.35, 14.1, 18.2, 15.05, 17.9)
      ..lineTo(19.55, 20.1)
      ..lineTo(18.25, 15.95)
      ..cubicTo(19.75, 14.7, 20.65, 13.05, 20.65, 11.25)
      ..cubicTo(20.65, 7.25, 17.05, 4.15, 12, 4.15)
      ..close();
  }

  Path _sharePath() {
    return Path()
      ..moveTo(3.8, 4.75)
      ..lineTo(21, 3.35)
      ..lineTo(14.75, 20.65)
      ..lineTo(11.25, 13.35)
      ..lineTo(3.8, 10.35)
      ..lineTo(21, 3.35)
      ..moveTo(11.25, 13.35)
      ..lineTo(16.65, 8.35);
  }

  @override
  bool shouldRepaint(covariant _NataloPostActionIconPainter oldDelegate) {
    return oldDelegate.type != type ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.isActive != isActive;
  }
}

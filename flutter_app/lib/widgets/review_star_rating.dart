import 'dart:async';
import '../utils/motion_prefs.dart';
import '../theme/natalo_text.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_motion_tokens.dart';

/// Integer ratings with continuous visual feedback during horizontal dragging.
class ReviewStarRating extends StatefulWidget {
  const ReviewStarRating(
      {super.key,
      required this.value,
      required this.onChanged,
      this.enabled = true});
  final int value;
  final ValueChanged<int> onChanged;
  final bool enabled;
  @override
  State<ReviewStarRating> createState() => _ReviewStarRatingState();
}

class _ReviewStarRatingState extends State<ReviewStarRating> {
  bool _dragging = false;
  double _preview = 0;
  double _x = 0;

  double _rating(double x, double cell) =>
      (1 + (x - cell / 2) / (cell + 8)).clamp(1, 5).toDouble();

  void _select(int value) {
    if (!widget.enabled) return;
    widget.onChanged(value.clamp(1, 5));
  }

  @override
  void didUpdateWidget(covariant ReviewStarRating oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _dragging = false;
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final reduce = MotionPrefs.shouldReduce(context);
    final fill = dark ? const Color(0xFFEFBF66) : const Color(0xFFE9B44F);
    final outline = dark ? const Color(0xFFDCA64C) : const Color(0xFFB78128);
    final empty = dark ? const Color(0xFFB2BFD1) : const Color(0xFF8794A6);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _select(widget.value + 1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _select(widget.value + 1),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _select(widget.value - 1),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _select(widget.value - 1),
        const SingleActivator(LogicalKeyboardKey.home): () => _select(1),
        const SingleActivator(LogicalKeyboardKey.end): () => _select(5),
      },
      child: Semantics(
        label: 'Rating produk',
        value: '${widget.value} dari 5 bintang',
        onIncrease: widget.enabled ? () => _select(widget.value + 1) : null,
        onDecrease: widget.enabled ? () => _select(widget.value - 1) : null,
        child: LayoutBuilder(builder: (context, constraints) {
          final width = math.min(280.0, constraints.maxWidth);
          final cell = (width - 32) / 5;
          return SizedBox(
            width: width,
            height: 48,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: !widget.enabled
                  ? null
                  : (details) {
                      unawaited(HapticFeedback.selectionClick());
                      setState(() {
                        _dragging = true;
                        _x = details.localPosition.dx;
                        _preview = _rating(_x, cell);
                      });
                    },
              onHorizontalDragUpdate: !widget.enabled
                  ? null
                  : (details) {
                      setState(() {
                        _x = details.localPosition.dx;
                        _preview = _rating(_x, cell);
                      });
                    },
              onHorizontalDragEnd: !widget.enabled
                  ? null
                  : (_) {
                      final value = _preview.round();
                      setState(() => _dragging = false);
                      _select(value);
                    },
              onHorizontalDragCancel: () => setState(() => _dragging = false),
              child: Stack(clipBehavior: Clip.none, children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(
                      begin: widget.value.toDouble(),
                      end: _dragging ? _preview : widget.value.toDouble()),
                  duration: reduce || _dragging
                      ? Duration.zero
                      : AppMotionTokens.press,
                  builder: (context, rating, _) => Row(children: [
                    for (var i = 0; i < 5; i++) ...[
                      SizedBox(
                          width: cell,
                          height: 48,
                          child: Semantics(
                            label: '${i + 1} bintang',
                            button: true,
                            selected: widget.value == i + 1,
                            enabled: widget.enabled,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              constraints:
                                  BoxConstraints(minWidth: cell, minHeight: 48),
                              tooltip: '${i + 1} bintang',
                              onPressed: !widget.enabled
                                  ? null
                                  : () {
                                      if (widget.value != i + 1) {
                                        unawaited(
                                            HapticFeedback.selectionClick());
                                      }
                                      _select(i + 1);
                                    },
                              icon: AnimatedScale(
                                scale: !reduce && _dragging
                                    ? 1 +
                                        .14 *
                                            (1 -
                                                    ((_x -
                                                                (i *
                                                                        (cell +
                                                                            8) +
                                                                    cell / 2))
                                                            .abs() /
                                                        (cell + 8)))
                                                .clamp(0, 1)
                                    : 1,
                                duration: reduce || _dragging
                                    ? Duration.zero
                                    : AppMotionTokens.quick,
                                curve: AppMotionTokens.curveEmphasized,
                                child: ExcludeSemantics(
                                    child: CustomPaint(
                                        size: const Size(32, 32),
                                        painter: _RatingStarPainter(
                                            (rating - i).clamp(0, 1).toDouble(),
                                            fill,
                                            outline,
                                            empty))),
                              ),
                            ),
                          )),
                      if (i < 4) const SizedBox(width: 8),
                    ],
                  ]),
                ),
                Positioned(
                  left: (_x - 16).clamp(0, width - 32),
                  top: -28,
                  child: IgnorePointer(
                      child: ExcludeSemantics(
                          child: AnimatedOpacity(
                    opacity: _dragging ? 1 : 0,
                    duration: reduce ? Duration.zero : AppMotionTokens.press,
                    child: Container(
                      width: 32,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.onSurface,
                          borderRadius: BorderRadius.circular(8)),
                      child: Text('${_preview.round()}',
                          style: TextStyle(
                              fontSize: NataloTextSize.caption,
                              color: Theme.of(context).colorScheme.surface)),
                    ),
                  ))),
                ),
              ]),
            ),
          );
        }),
      ),
    );
  }
}

class _RatingStarPainter extends CustomPainter {
  const _RatingStarPainter(this.fraction, this.fill, this.outline, this.empty);
  final double fraction;
  final Color fill, outline, empty;
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final radius = size.width * (i.isEven ? .46 : .23);
      final angle = -math.pi / 2 + i * math.pi / 5;
      final point =
          center + Offset(math.cos(angle) * radius, math.sin(angle) * radius);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(
        path,
        Paint()
          ..color = empty
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3);
    if (fraction > 0) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, size.width * fraction, size.height));
      canvas.drawPath(path, Paint()..color = fill);
      canvas.drawPath(
          path,
          Paint()
            ..color = outline
            ..style = PaintingStyle.stroke
            ..strokeWidth = .9);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _RatingStarPainter old) =>
      fraction != old.fraction ||
      fill != old.fill ||
      outline != old.outline ||
      empty != old.empty;
}

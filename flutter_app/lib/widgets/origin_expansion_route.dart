import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Pushes [destinationBuilder] with a snapshot expanding from [originKey].
///
/// The source must be a [RepaintBoundary] to produce a bitmap snapshot. When
/// it is unavailable or cannot be captured, the route safely fades instead.
Future<T?> pushOriginExpansion<T>(
  BuildContext context, {
  required GlobalKey originKey,
  required WidgetBuilder destinationBuilder,
  @Deprecated('Origin snapshots are captured from originKey instead.')
  String? snapshotImageUrl,
  Color snapshotFallbackColor = Colors.white,
}) async {
  final renderObject = originKey.currentContext?.findRenderObject();
  final box = renderObject is RenderBox ? renderObject : null;
  final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
  final snapshot = await _captureSnapshot(
    renderObject,
    pixelRatio: View.of(context).devicePixelRatio,
  );

  if (!context.mounted) {
    snapshot?.dispose();
    return null;
  }

  return Navigator.of(context).push(
    PageRouteBuilder<T>(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 240),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondaryAnimation) {
        return destinationBuilder(context);
      },
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return OriginExpansionTransition(
          animation: animation,
          origin: origin,
          snapshot: snapshot,
          snapshotFallbackColor: snapshotFallbackColor,
          child: child,
        );
      },
    ),
  );
}

Future<ui.Image?> _captureSnapshot(
  RenderObject? renderObject, {
  required double pixelRatio,
}) async {
  if (renderObject is! RenderRepaintBoundary) return null;

  try {
    return await renderObject.toImage(pixelRatio: pixelRatio);
  } catch (_) {
    return null;
  }
}

class OriginExpansionTransition extends StatefulWidget {
  final Animation<double> animation;
  final Rect? origin;
  final ui.Image? snapshot;
  final Color snapshotFallbackColor;
  final Widget child;

  const OriginExpansionTransition({
    super.key,
    required this.animation,
    required this.origin,
    required this.snapshot,
    required this.snapshotFallbackColor,
    required this.child,
  });

  @override
  State<OriginExpansionTransition> createState() =>
      _OriginExpansionTransitionState();
}

class _OriginExpansionTransitionState extends State<OriginExpansionTransition> {
  @override
  void dispose() {
    widget.snapshot?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final destinationOpacity = CurvedAnimation(
      parent: widget.animation,
      curve: const Interval(0.55, 1, curve: Curves.easeIn),
      reverseCurve: const Interval(0.55, 1, curve: Curves.easeOut),
    );
    final destination = FadeTransition(
      key: const ValueKey('origin-expansion-fade'),
      opacity: destinationOpacity,
      child: ColoredBox(
        color: widget.snapshotFallbackColor,
        child: widget.child,
      ),
    );
    final sourceOrigin = widget.origin;
    final snapshot = widget.snapshot;
    if (sourceOrigin == null || snapshot == null) return destination;

    final curved = CurvedAnimation(
      parent: widget.animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final destinationSize = constraints.biggest;
        return Stack(
          fit: StackFit.expand,
          children: [
            destination,
            AnimatedBuilder(
              animation: curved,
              builder: (context, _) {
                final progress = curved.value;
                return Positioned(
                  left: _lerp(sourceOrigin.left, 0, progress),
                  top: _lerp(sourceOrigin.top, 0, progress),
                  width: _lerp(
                    sourceOrigin.width,
                    destinationSize.width,
                    progress,
                  ),
                  height: _lerp(
                    sourceOrigin.height,
                    destinationSize.height,
                    progress,
                  ),
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: 1 - destinationOpacity.value,
                      child: ClipRRect(
                        borderRadius:
                            BorderRadius.circular(12 * (1 - progress)),
                        child: RawImage(
                          key: const ValueKey('origin-expansion-snapshot'),
                          image: snapshot,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

double _lerp(double begin, double end, double progress) {
  return begin + (end - begin) * progress;
}

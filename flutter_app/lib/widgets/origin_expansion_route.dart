import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Pushes [destinationBuilder] with a snapshot expanding from [originKey].
Future<T?> pushOriginExpansion<T>(
  BuildContext context, {
  required GlobalKey originKey,
  required WidgetBuilder destinationBuilder,
  String? snapshotImageUrl,
  Color snapshotFallbackColor = Colors.white,
}) {
  final box = originKey.currentContext?.findRenderObject() as RenderBox?;
  final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;

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
          snapshotImageUrl: snapshotImageUrl,
          snapshotFallbackColor: snapshotFallbackColor,
          child: child,
        );
      },
    ),
  );
}

@immutable
class OriginExpansionTransition extends StatelessWidget {
  final Animation<double> animation;
  final Rect? origin;
  final String? snapshotImageUrl;
  final Color snapshotFallbackColor;
  final Widget child;

  const OriginExpansionTransition({
    super.key,
    required this.animation,
    required this.origin,
    required this.snapshotImageUrl,
    required this.snapshotFallbackColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final sourceOrigin = origin;
    if (sourceOrigin == null) return child;

    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final destinationOpacity = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.55, 1, curve: Curves.easeIn),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final destinationSize = constraints.biggest;
        return Stack(
          fit: StackFit.expand,
          children: [
            FadeTransition(opacity: destinationOpacity, child: child),
            AnimatedBuilder(
              animation: curved,
              builder: (context, _) {
                final progress = curved.value;
                return Positioned(
                  left: _lerp(sourceOrigin.left, 0, progress),
                  top: _lerp(sourceOrigin.top, 0, progress),
                  width: _lerp(
                      sourceOrigin.width, destinationSize.width, progress),
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
                        child: _Snapshot(
                          imageUrl: snapshotImageUrl,
                          fallbackColor: snapshotFallbackColor,
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

class _Snapshot extends StatelessWidget {
  final String? imageUrl;
  final Color fallbackColor;

  const _Snapshot({required this.imageUrl, required this.fallbackColor});

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url == null || url.isEmpty) {
      return ColoredBox(
        key: const ValueKey('origin-expansion-snapshot'),
        color: fallbackColor,
      );
    }

    return CachedNetworkImage(
      key: const ValueKey('origin-expansion-snapshot'),
      imageUrl: url,
      fit: BoxFit.cover,
      errorWidget: (_, __, ___) => ColoredBox(color: fallbackColor),
    );
  }
}

double _lerp(double begin, double end, double progress) {
  return begin + (end - begin) * progress;
}

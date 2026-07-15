// flutter_app/lib/widgets/scaled_video_feed_route.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

@immutable
class ScaledVideoFeedReverseTarget {
  final Rect rect;
  final String imageUrl;
  final double borderRadius;

  const ScaledVideoFeedReverseTarget({
    required this.rect,
    required this.imageUrl,
    this.borderRadius = 0,
  });
}

/// Pushes [destinationBuilder] with a scale/morph transition: the
/// on-screen rect of the widget attached to [thumbnailKey] grows to fill
/// the screen (~260ms, easeOutCubic) before the destination becomes
/// interactive. A snapshot image ([thumbnailImageUrl]) is shown scaling
/// up — NOT the destination's live video — so no video frame renders at
/// a "shrunk" size mid-animation.
Future<T?> pushScaledVideoFeed<T>(
  BuildContext context, {
  required GlobalKey thumbnailKey,
  required String thumbnailImageUrl,
  required double thumbnailBorderRadius,
  required WidgetBuilder destinationBuilder,
  ValueListenable<bool>? reverseMorphEnabled,
  ValueListenable<ScaledVideoFeedReverseTarget?>? reverseTarget,
}) {
  final renderBox =
      thumbnailKey.currentContext?.findRenderObject() as RenderBox?;
  final origin = renderBox != null
      ? renderBox.localToGlobal(Offset.zero) & renderBox.size
      : null;

  return Navigator.of(context).push(
    PageRouteBuilder<T>(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondaryAnimation) {
        return destinationBuilder(context);
      },
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        final screenSize = MediaQuery.of(context).size;
        Widget buildTransition(
          bool allowReverseMorph,
          ScaledVideoFeedReverseTarget? returnTarget,
        ) {
          final activeOrigin = animation.status == AnimationStatus.reverse &&
                  returnTarget != null
              ? returnTarget.rect
              : origin;
          final activeImageUrl = animation.status == AnimationStatus.reverse &&
                  returnTarget != null
              ? returnTarget.imageUrl
              : thumbnailImageUrl;
          final activeBorderRadius =
              animation.status == AnimationStatus.reverse &&
                      returnTarget != null
                  ? returnTarget.borderRadius
                  : thumbnailBorderRadius;
          return Stack(
            fit: StackFit.expand,
            children: [
              // Destination fades in once the scale is mostly complete —
              // avoids a visible "cut" from snapshot to live video.
              FadeTransition(
                opacity: CurvedAnimation(
                  parent: animation,
                  curve: const Interval(0.55, 1.0, curve: Curves.easeIn),
                ),
                child: child,
              ),
              // NOTE: the AnimatedBuilder must sit DIRECTLY under the Stack so
              // that its returned `Positioned` has the Stack as its render
              // parent. Wrapping the Positioned in IgnorePointer (or any other
              // RenderObjectWidget) breaks that — StackParentData would be
              // applied to a non-Stack render object (asserts in debug, mis-
              // positions in release). So IgnorePointer lives INSIDE the
              // Positioned instead.
              if (activeOrigin != null &&
                  (animation.status != AnimationStatus.reverse ||
                      allowReverseMorph))
                AnimatedBuilder(
                  animation: curved,
                  builder: (context, _) {
                    final t = curved.value;
                    // Snapshot rect morphs from `origin` to fullscreen.
                    final left =
                        activeOrigin.left + (0 - activeOrigin.left) * t;
                    final top = activeOrigin.top + (0 - activeOrigin.top) * t;
                    final width = activeOrigin.width +
                        (screenSize.width - activeOrigin.width) * t;
                    final height = activeOrigin.height +
                        (screenSize.height - activeOrigin.height) * t;
                    final radius = activeBorderRadius * (1 - t);
                    return Positioned(
                      left: left,
                      top: top,
                      width: width,
                      height: height,
                      child: IgnorePointer(
                        child: Opacity(
                          // Snapshot fades OUT over the same interval the
                          // destination fades in, so there is no double-
                          // exposure flash.
                          opacity: 1 -
                              CurvedAnimation(
                                parent: animation,
                                curve: const Interval(0.55, 1.0,
                                    curve: Curves.easeIn),
                              ).value,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(radius),
                            child: CachedNetworkImage(
                              imageUrl: activeImageUrl,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) =>
                                  const ColoredBox(color: Colors.black),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          );
        }

        final enabled = reverseMorphEnabled;
        Widget withTarget(bool allowReverseMorph) {
          final target = reverseTarget;
          if (target == null) return buildTransition(allowReverseMorph, null);
          return ValueListenableBuilder<ScaledVideoFeedReverseTarget?>(
            valueListenable: target,
            builder: (_, value, __) => buildTransition(
              allowReverseMorph,
              value,
            ),
          );
        }

        if (enabled == null) return withTarget(true);
        return ValueListenableBuilder<bool>(
          valueListenable: enabled,
          builder: (_, allowReverseMorph, __) => withTarget(allowReverseMorph),
        );
      },
    ),
  );
}

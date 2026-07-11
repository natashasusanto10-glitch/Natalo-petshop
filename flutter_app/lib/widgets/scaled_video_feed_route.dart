// flutter_app/lib/widgets/scaled_video_feed_route.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Pushes [destinationBuilder] with a scale/morph transition: the
/// on-screen rect of the widget attached to [thumbnailKey] grows to fill
/// the screen (~440ms, easeOutCubic) before the destination becomes
/// interactive. A snapshot image ([thumbnailImageUrl]) is shown scaling
/// up — NOT the destination's live video — so no video frame renders at
/// a "shrunk" size mid-animation.
Future<void> pushScaledVideoFeed(
  BuildContext context, {
  required GlobalKey thumbnailKey,
  required String thumbnailImageUrl,
  required double thumbnailBorderRadius,
  required WidgetBuilder destinationBuilder,
}) {
  final renderBox = thumbnailKey.currentContext?.findRenderObject() as RenderBox?;
  final origin = renderBox != null
      ? renderBox.localToGlobal(Offset.zero) & renderBox.size
      : null;

  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: true,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 440),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (context, animation, secondaryAnimation) {
        return destinationBuilder(context);
      },
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        final screenSize = MediaQuery.of(context).size;
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
            if (origin != null)
              IgnorePointer(
                child: AnimatedBuilder(
                  animation: curved,
                  builder: (context, _) {
                    final t = curved.value;
                    // Snapshot rect morphs from `origin` to fullscreen.
                    final left = origin.left + (0 - origin.left) * t;
                    final top = origin.top + (0 - origin.top) * t;
                    final width = origin.width + (screenSize.width - origin.width) * t;
                    final height = origin.height + (screenSize.height - origin.height) * t;
                    final radius = thumbnailBorderRadius * (1 - t);
                    return Positioned(
                      left: left,
                      top: top,
                      width: width,
                      height: height,
                      child: Opacity(
                        // Snapshot fades OUT over the same interval the
                        // destination fades in, so there is no double-
                        // exposure flash.
                        opacity: 1 - CurvedAnimation(
                          parent: animation,
                          curve: const Interval(0.55, 1.0, curve: Curves.easeIn),
                        ).value,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(radius),
                          child: CachedNetworkImage(
                            imageUrl: thumbnailImageUrl,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => const ColoredBox(color: Colors.black),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    ),
  );
}

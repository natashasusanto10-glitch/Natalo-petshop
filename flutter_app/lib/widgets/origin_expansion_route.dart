import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';

@visibleForTesting
void Function(AnimationStatus status, bool hasSnapshot)?
    debugOriginExpansionStatusObserver;

/// Curve morph ala IG/Material-3 (emphasized). Decelerate saat buka —
/// terasa "mendarat" lembut; accelerate saat tutup — menutup gesit.
/// Menggantikan easeOutCubic/easeInCubic yang terasa terlalu datar/cepat.
const Curve _kOriginOpenCurve = Cubic(0.05, 0.7, 0.1, 1.0);
const Curve _kOriginCloseCurve = Cubic(0.3, 0.0, 0.8, 0.15);

/// Keeps a snapshot-driven origin out of Navigator Hero matching.
///
/// The destination route remains Hero-enabled, so later navigation from that
/// screen can still use its own Hero transition.
class OriginSnapshotSource extends StatelessWidget {
  final Widget child;

  const OriginSnapshotSource({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return HeroMode(enabled: false, child: child);
  }
}

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

  final route = _OriginExpansionPageRoute<T>(
    destinationBuilder: destinationBuilder,
    origin: origin,
    snapshot: snapshot,
    snapshotFallbackColor: snapshotFallbackColor,
  );
  try {
    return await Navigator.of(context).push(route);
  } finally {
    await route.completed;
    snapshot?.dispose();
  }
}

class _OriginExpansionPageRoute<T> extends PageRoute<T> {
  _OriginExpansionPageRoute({
    required this.destinationBuilder,
    required this.origin,
    required this.snapshot,
    required this.snapshotFallbackColor,
  }) : super(allowSnapshotting: false);

  final WidgetBuilder destinationBuilder;
  final Rect? origin;
  final ui.Image? snapshot;
  final Color snapshotFallbackColor;
  _OriginBackGestureController<T>? _backGestureController;

  @override
  bool get opaque => false;

  @override
  Color? get barrierColor => Colors.transparent;

  @override
  String? get barrierLabel => null;

  @override
  bool get barrierDismissible => false;

  @override
  bool get maintainState => true;

  // Pace ala IG/iOS shared-element expand: ~300ms buka (240ms terasa
  // terlalu snappy), tutup sedikit lebih gesit.
  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 250);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return Semantics(
      key: const ValueKey('origin-expansion-route-semantics'),
      scopesRoute: true,
      explicitChildNodes: true,
      child: destinationBuilder(context),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _OriginEdgeBackGestureDetector<T>(
      enabledCallback: () => popGestureEnabled,
      onStartPopGesture: _startPopGesture,
      child: OriginExpansionTransition(
        animation: animation,
        origin: origin,
        snapshot: snapshot,
        snapshotFallbackColor: snapshotFallbackColor,
        linearTransition: () => popGestureInProgress,
        child: child,
      ),
    );
  }

  _OriginBackGestureController<T> _startPopGesture() {
    _backGestureController?.abort();
    late final _OriginBackGestureController<T> backGestureController;
    backGestureController = _OriginBackGestureController<T>(
      navigator: navigator!,
      controller: controller!,
      getIsCurrent: () => isCurrent,
      onFinished: () {
        if (identical(_backGestureController, backGestureController)) {
          _backGestureController = null;
        }
      },
    );
    _backGestureController = backGestureController;
    return backGestureController;
  }

  @override
  void dispose() {
    _backGestureController?.abort();
    _backGestureController = null;
    super.dispose();
  }
}

const double _originBackGestureWidth = 28;
const double _originBackCompletionFraction = 0.25;
const double _originBackFlingVelocity = 800;

class _OriginEdgeBackGestureDetector<T> extends StatefulWidget {
  const _OriginEdgeBackGestureDetector({
    required this.enabledCallback,
    required this.onStartPopGesture,
    required this.child,
  });

  final ValueGetter<bool> enabledCallback;
  final ValueGetter<_OriginBackGestureController<T>> onStartPopGesture;
  final Widget child;

  @override
  State<_OriginEdgeBackGestureDetector<T>> createState() =>
      _OriginEdgeBackGestureDetectorState<T>();
}

class _OriginEdgeBackGestureDetectorState<T>
    extends State<_OriginEdgeBackGestureDetector<T>> {
  late final HorizontalDragGestureRecognizer _recognizer;
  _OriginBackGestureController<T>? _backGestureController;

  @override
  void initState() {
    super.initState();
    _recognizer = HorizontalDragGestureRecognizer(debugOwner: this)
      ..onStart = _handleDragStart
      ..onUpdate = _handleDragUpdate
      ..onEnd = _handleDragEnd
      ..onCancel = _handleDragCancel;
  }

  @override
  void dispose() {
    _recognizer.dispose();
    _backGestureController?.abort();
    _backGestureController = null;
    super.dispose();
  }

  void _handlePointerDown(PointerDownEvent event) {
    final enabled = widget.enabledCallback();
    if (event.localPosition.dx > _originBackGestureWidth || !enabled) {
      return;
    }
    _recognizer.addPointer(event);
  }

  void _handleDragStart(DragStartDetails details) {
    _backGestureController = widget.onStartPopGesture();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    final width = context.size?.width ?? 0;
    if (width <= 0) return;
    _backGestureController?.dragUpdate(details.primaryDelta! / width);
  }

  void _handleDragEnd(DragEndDetails details) {
    final width = context.size?.width ?? 0;
    _backGestureController?.dragEnd(
      velocity: details.velocity.pixelsPerSecond.dx,
      width: width,
    );
    _backGestureController = null;
  }

  void _handleDragCancel() {
    _backGestureController?.dragEnd(
        velocity: 0, width: context.size?.width ?? 0);
    _backGestureController = null;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      key: const ValueKey('origin-expansion-edge-back'),
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      child: widget.child,
    );
  }
}

class _OriginBackGestureController<T> {
  _OriginBackGestureController({
    required this.navigator,
    required this.controller,
    required this.getIsCurrent,
    required this.onFinished,
  }) {
    navigator.didStartUserGesture();
  }

  final NavigatorState navigator;
  final AnimationController controller;
  final ValueGetter<bool> getIsCurrent;
  final VoidCallback onFinished;
  bool _active = true;
  AnimationStatusListener? _statusListener;

  void dragUpdate(double delta) {
    if (!_active) return;
    controller.value -= delta;
  }

  void dragEnd({required double velocity, required double width}) {
    if (!_active) return;
    if (!getIsCurrent()) {
      abort();
      return;
    }
    final dragFraction = 1 - controller.value;
    final shouldPop = dragFraction >= _originBackCompletionFraction ||
        velocity >= _originBackFlingVelocity;
    if (shouldPop) {
      _watchForTerminalStatus((status) => status == AnimationStatus.dismissed);
      navigator.pop();
      if (controller.status == AnimationStatus.dismissed) _finish();
      return;
    }
    _springBack(velocity: velocity, width: width);
  }

  void abort() {
    _finish();
  }

  void _springBack({required double velocity, required double width}) {
    final normalizedVelocity = width <= 0 ? 0.0 : -velocity / width;
    final simulation = SpringSimulation(
      const SpringDescription(mass: 1, stiffness: 450, damping: 42),
      controller.value,
      1,
      normalizedVelocity,
    );
    _watchForSpringTerminalStatus();
    controller.animateWith(simulation);
    if (!controller.isAnimating) _finishSpring();
  }

  void _watchForTerminalStatus(
      bool Function(AnimationStatus status) isTerminal) {
    _removeStatusListener();
    _statusListener = (status) {
      if (isTerminal(status)) _finish();
    };
    controller.addStatusListener(_statusListener!);
  }

  void _removeStatusListener() {
    final statusListener = _statusListener;
    if (statusListener == null) return;
    controller.removeStatusListener(statusListener);
    _statusListener = null;
  }

  void _watchForSpringTerminalStatus() {
    _removeStatusListener();
    _statusListener = (status) {
      if (status == AnimationStatus.completed) {
        _finishSpring();
      } else if (status == AnimationStatus.dismissed) {
        _finish();
      }
    };
    controller.addStatusListener(_statusListener!);
  }

  void _finishSpring() {
    if (!_active) return;
    _removeStatusListener();
    if (controller.status == AnimationStatus.completed) controller.value = 1;
    _finish();
  }

  void _finish() {
    if (!_active) return;
    _active = false;
    _removeStatusListener();
    if (navigator.mounted) navigator.didStopUserGesture();
    onFinished();
  }
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
  final ValueGetter<bool>? linearTransition;
  final Widget child;

  const OriginExpansionTransition({
    super.key,
    required this.animation,
    required this.origin,
    required this.snapshot,
    required this.snapshotFallbackColor,
    this.linearTransition,
    required this.child,
  });

  @override
  State<OriginExpansionTransition> createState() =>
      _OriginExpansionTransitionState();
}

class _OriginExpansionTransitionState extends State<OriginExpansionTransition> {
  @override
  void initState() {
    super.initState();
    widget.animation.addStatusListener(_onAnimationStatus);
    _reportAnimationStatus(widget.animation.status);
  }

  @override
  void didUpdateWidget(covariant OriginExpansionTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation == widget.animation) return;
    oldWidget.animation.removeStatusListener(_onAnimationStatus);
    widget.animation.addStatusListener(_onAnimationStatus);
    _reportAnimationStatus(widget.animation.status);
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_onAnimationStatus);
    super.dispose();
  }

  void _onAnimationStatus(AnimationStatus status) {
    _reportAnimationStatus(status);
  }

  void _reportAnimationStatus(AnimationStatus status) {
    debugOriginExpansionStatusObserver?.call(
      status,
      widget.origin != null && widget.snapshot != null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.animation,
      builder: (context, _) {
        final linear = widget.linearTransition?.call() ?? false;
        final reverse = widget.animation.status == AnimationStatus.reverse;
        final animationValue = widget.animation.value;
        final progress = linear
            ? animationValue
            : (reverse ? _kOriginCloseCurve : _kOriginOpenCurve)
                .transform(animationValue);
        final destinationOpacity = linear
            ? const Interval(0.55, 1).transform(animationValue)
            : (reverse
                    ? const Interval(0.55, 1, curve: Curves.easeOut)
                    : const Interval(0.55, 1, curve: Curves.easeIn))
                .transform(animationValue);
        final sourceOrigin = widget.origin;
        final snapshot = widget.snapshot;
        final destination = Opacity(
          key: const ValueKey('origin-expansion-fade'),
          // With an origin snapshot, the destination is revealed by the
          // expanding clip itself. Keeping it opaque prevents a second
          // fade from making the picker appear to pop out of nowhere.
          opacity: snapshot == null || reverse ? destinationOpacity : 1,
          child: ColoredBox(
            color: widget.snapshotFallbackColor,
            child: widget.child,
          ),
        );
        if (sourceOrigin == null || snapshot == null) return destination;

        return LayoutBuilder(
          builder: (context, constraints) {
            final destinationSize = constraints.biggest;
            final destinationRect = Rect.fromLTWH(
              _lerp(sourceOrigin.left, 0, progress),
              _lerp(sourceOrigin.top, 0, progress),
              _lerp(sourceOrigin.width, destinationSize.width, progress),
              _lerp(sourceOrigin.height, destinationSize.height, progress),
            );
            return Stack(
              fit: StackFit.expand,
              children: [
                // Reveal the destination page from the pressed control. The
                // source icon stays in place; it is not the morphing object.
                Positioned.fromRect(
                  rect: destinationRect,
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      minWidth: destinationSize.width,
                      maxWidth: destinationSize.width,
                      minHeight: destinationSize.height,
                      maxHeight: destinationSize.height,
                      child: destination,
                    ),
                  ),
                ),
                Positioned(
                  left: sourceOrigin.left,
                  top: sourceOrigin.top,
                  width: sourceOrigin.width,
                  height: sourceOrigin.height,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: (1 - progress).clamp(0.0, 1.0),
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
                ),
              ],
            );
          },
        );
      },
    );
  }
}

double _lerp(double begin, double end, double progress) {
  return begin + (end - begin) * progress;
}

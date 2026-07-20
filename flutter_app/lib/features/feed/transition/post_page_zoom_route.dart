import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'post_detail_transition_session.dart';
import 'post_page_zoom_transition.dart';

/// The 8 states of the Postingan full-page zoom route, exactly as specified
/// in the transition design (`State Machine` section).
///
/// Legal transitions:
/// - `preparingOpen` -> `opening` | `closingFallback`
/// - `opening` -> `open` | `closingToTarget` | `closingFallback`
/// - `open` -> `interactiveBack` | `closingToTarget` | `closingFallback`
/// - `interactiveBack` -> `settlingOpenAfterCancel` | `closingToTarget` |
///   `closingFallback`
/// - `settlingOpenAfterCancel` -> `open`
/// - `closingToTarget` -> `closed`
/// - `closingFallback` -> `closed`
///
/// Only `open` accepts a new back interaction. Only `interactiveBack` can
/// commit or cancel. `session.resumeTrackingAfterCanceledBack()` is called
/// exactly once, only on the `settlingOpenAfterCancel` -> `open` edge.
enum PostPageZoomPhase {
  preparingOpen,
  opening,
  open,
  interactiveBack,
  settlingOpenAfterCancel,
  closingToTarget,
  closingFallback,
  closed,
}

/// Injection hook for interactive-gesture progress (Tasks 12-13). When
/// non-null, it is a test-only stand-in for the iOS edge-swipe pointer
/// recognizer: called with the current linear drag progress (0..1, 1 meaning
/// fully back at the source tile) and the current drag velocity in logical
/// pixels/second. Defaults to null (no injection) in production and in every
/// test that does not opt in.
@visibleForTesting
void Function(double progress, double velocity)?
debugPostPageZoomGestureProgress;

/// The distinct Android Predictive Back events the route can be driven with
/// by [debugPostPageZoomPredictiveEvents] (Tasks 12-13).
enum PostPageZoomPredictiveEventKind { start, progress, commit, cancel }

/// Injection hook for Android Predictive Back events (Tasks 12-13). When
/// non-null, it is a test-only stand-in for the system predictive-back
/// callback stream. Defaults to null (no injection).
@visibleForTesting
void Function(PostPageZoomPredictiveEventKind kind, {double? progress})?
debugPostPageZoomPredictiveEvents;

/// Throwing seam tests install to prove the route never attempts a
/// `RenderObject.toImage`/snapshot capture anywhere on its hot paths (proxy
/// selection is synchronous per spec `Forward Animation` §). Defaults to
/// null (never called) in production.
@visibleForTesting
void Function()? debugPostPageZoomOnSnapshotAttempt;

/// Pushes the dedicated, non-interactive-by-default Postingan full-page zoom
/// route for [session] onto the [context]'s [Navigator].
///
/// Ownership contract: the SOURCE screen creates [session] (with its
/// `initialPost` and adapter) and calls this function. This function calls
/// `session.tryAttachRoute()` FIRST; if that returns false (a route is
/// already attached to this session — the repeated-tap guard), this returns
/// without pushing a second route. The SOURCE, not the route or the
/// destination, disposes [session], and only after awaiting the returned
/// future.
Future<void> pushPostPageZoom(
  BuildContext context, {
  required PostDetailTransitionSession session,
  required WidgetBuilder destinationBuilder,
}) {
  if (!session.tryAttachRoute()) {
    return Future<void>.value();
  }
  final route = PostPageZoomRoute(
    session: session,
    destinationBuilder: destinationBuilder,
  );
  return Navigator.of(context).push(route);
}

/// Wraps source-facing content so it is excluded from the semantics tree
/// while a route (such as [PostPageZoomRoute]) sits above it. Uses the
/// standard `ModalRoute.isCurrent` idiom: a route below the top of the stack
/// is automatically not current, so this widget requires no coordination
/// with the route above it beyond being present in the source screen's tree.
class PostPageZoomSourceVisibility extends StatelessWidget {
  const PostPageZoomSourceVisibility({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    return ExcludeSemantics(excluding: !isCurrent, child: child);
  }
}

const Duration _kForwardDuration = Duration(milliseconds: 300);
const Duration _kFallbackForwardDuration = Duration(milliseconds: 160);
const Duration _kNonInteractiveReverseDuration = Duration(milliseconds: 260);
const Duration _kFallbackReverseDuration = Duration(milliseconds: 180);
const Duration _kSettleDuration = Duration(milliseconds: 200);

/// The non-bouncy emphasized-deceleration open curve (spec `Forward
/// Animation` §, acceptable initial value).
const Curve postPageZoomOpenCurve = Cubic(0.05, 0.7, 0.1, 1.0);

const Map<PostPageZoomPhase, Set<PostPageZoomPhase>>
_kLegalPostPageZoomTransitions = {
  PostPageZoomPhase.preparingOpen: {
    PostPageZoomPhase.opening,
    PostPageZoomPhase.closingFallback,
  },
  PostPageZoomPhase.opening: {
    PostPageZoomPhase.open,
    PostPageZoomPhase.closingToTarget,
    PostPageZoomPhase.closingFallback,
  },
  PostPageZoomPhase.open: {
    PostPageZoomPhase.interactiveBack,
    PostPageZoomPhase.closingToTarget,
    PostPageZoomPhase.closingFallback,
  },
  PostPageZoomPhase.interactiveBack: {
    PostPageZoomPhase.settlingOpenAfterCancel,
    PostPageZoomPhase.closingToTarget,
    PostPageZoomPhase.closingFallback,
  },
  PostPageZoomPhase.settlingOpenAfterCancel: {PostPageZoomPhase.open},
  PostPageZoomPhase.closingToTarget: {PostPageZoomPhase.closed},
  PostPageZoomPhase.closingFallback: {PostPageZoomPhase.closed},
  PostPageZoomPhase.closed: <PostPageZoomPhase>{},
};

/// The dedicated, non-opaque [PageRoute] for the Postingan full-page zoom
/// transition (spec `Chosen Approach` §). See [PostPageZoomPhase] for the
/// state machine it enforces.
class PostPageZoomRoute extends PageRoute<void> {
  PostPageZoomRoute({required this.session, required this.destinationBuilder})
    : super(settings: const RouteSettings(name: 'post-page-zoom'));

  final PostDetailTransitionSession session;
  final WidgetBuilder destinationBuilder;

  final ValueNotifier<PostPageZoomPhase> phaseListenable =
      ValueNotifier<PostPageZoomPhase>(PostPageZoomPhase.preparingOpen);

  PostPageZoomPhase get phase => phaseListenable.value;

  /// Test-only exposure of the underlying `TransitionRoute.controller`
  /// (which is `@protected`), so widget tests can assert on animation
  /// progress without needing to be subclasses of this route.
  @visibleForTesting
  AnimationController? get debugController => controller;

  PostPageSourceTarget? _frozenTarget;
  PostPageMediaProxy? _frozenProxy;
  bool _sessionListenerAttached = false;

  @override
  bool get opaque => false;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => false;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => _kForwardDuration;

  @override
  Duration get reverseTransitionDuration => _kNonInteractiveReverseDuration;

  void _setPhase(PostPageZoomPhase next) {
    final legal = _kLegalPostPageZoomTransitions[phase] ?? const {};
    if (!legal.contains(next)) {
      throw StateError('Illegal PostPageZoomPhase transition: $phase -> $next');
    }
    phaseListenable.value = next;
  }

  @override
  void install() {
    super.install();
    session.addListener(_onSessionChanged);
    _sessionListenerAttached = true;
  }

  @override
  // ignore: must_call_super
  TickerFuture didPush() {
    // Deliberately does not call `super.didPush()`: the base implementation
    // immediately runs `controller.forward()`, but this route must hold at
    // `preparingOpen` (proxy covering the screen) until
    // `session.destinationReadiness` leaves `preparing`.
    _maybeBeginOpening();
    return TickerFuture.complete();
  }

  void _onSessionChanged() {
    if (phase == PostPageZoomPhase.preparingOpen) {
      _maybeBeginOpening();
    }
  }

  void _maybeBeginOpening() {
    if (phase != PostPageZoomPhase.preparingOpen) return;
    final readiness = session.destinationReadiness;
    if (readiness == PostDetailDestinationReadiness.preparing) return;

    _setPhase(PostPageZoomPhase.opening);
    final duration =
        readiness == PostDetailDestinationReadiness.crossfadeFallback
        ? _kFallbackForwardDuration
        : _kForwardDuration;
    controller!
        .animateTo(1.0, duration: duration, curve: postPageZoomOpenCurve)
        .whenCompleteOrCancel(() {
          if (phase == PostPageZoomPhase.opening &&
              controller!.status == AnimationStatus.completed) {
            _setPhase(PostPageZoomPhase.open);
            session.setPlaybackAllowed(true);
          }
        });
  }

  // --- Interactive back (Tasks 12-13 wire the real gesture recognizers to
  // these entry points; Task 8 only establishes the legal state surface). ---

  void beginInteractiveBack() {
    if (phase != PostPageZoomPhase.open) {
      throw StateError(
        'beginInteractiveBack requires phase == open, got $phase',
      );
    }
    controller!.stop();
    _setPhase(PostPageZoomPhase.interactiveBack);
  }

  void cancelInteractiveBack() {
    if (phase != PostPageZoomPhase.interactiveBack) {
      throw StateError(
        'cancelInteractiveBack requires phase == interactiveBack, got $phase',
      );
    }
    _setPhase(PostPageZoomPhase.settlingOpenAfterCancel);
    controller!
        .animateTo(1.0, duration: _kSettleDuration, curve: Curves.easeOutCubic)
        .whenCompleteOrCancel(() {
          if (phase == PostPageZoomPhase.settlingOpenAfterCancel) {
            _setPhase(PostPageZoomPhase.open);
            session.resumeTrackingAfterCanceledBack();
          }
        });
  }

  Future<void> commitInteractiveBack() {
    if (phase != PostPageZoomPhase.interactiveBack) {
      throw StateError(
        'commitInteractiveBack requires phase == interactiveBack, got $phase',
      );
    }
    return _performClose();
  }

  // --- Non-interactive close (header back / system back / predictive
  // fallback). ---

  /// Requests the non-interactive reverse. Safe to call multiple times; a
  /// close already in flight (or completed) is a no-op.
  Future<void> requestClose() {
    if (phase == PostPageZoomPhase.closed ||
        phase == PostPageZoomPhase.closingToTarget ||
        phase == PostPageZoomPhase.closingFallback) {
      return Future<void>.value();
    }
    if (phase != PostPageZoomPhase.open &&
        phase != PostPageZoomPhase.interactiveBack) {
      throw StateError('requestClose is illegal from phase $phase');
    }
    return _performClose();
  }

  Future<void> _performClose() async {
    // Freeze BEFORE any reverse animation starts (spec: freeze precedes the
    // reverse flight).
    final frozen = session.freeze();
    final useFallback = frozen.usesFallback;

    if (useFallback) {
      _frozenTarget = null;
      _frozenProxy = frozen.proxy;
      // Fallback reverse never targets the opening A rect: assign the
      // pending return target before the pop completes so the source can do
      // its own bounded best-effort positioning; never reuse the opening
      // geometry for the animation itself.
      session.assignPendingReturnTarget();
      _setPhase(PostPageZoomPhase.closingFallback);
      await controller!.animateTo(
        0.0,
        duration: _kFallbackReverseDuration,
        curve: Curves.easeOut,
      );
    } else {
      _frozenTarget = frozen.target;
      _frozenProxy = frozen.proxy;
      _setPhase(PostPageZoomPhase.closingToTarget);
      session.setFrozenTileSuppressed(true);
      await controller!.animateTo(
        0.0,
        duration: _kNonInteractiveReverseDuration,
        curve: Curves.easeInCubic,
      );
      session.setFrozenTileSuppressed(false);
    }

    _setPhase(PostPageZoomPhase.closed);
    final nav = navigator;
    if (nav != null && nav.mounted && nav.canPop()) {
      nav.pop();
    }
  }

  Rect _viewportRect(BuildContext context) =>
      Offset.zero & MediaQuery.sizeOf(context);

  Rect _tileRect(BuildContext context) {
    final target = _frozenTarget ?? session.openingTarget;
    if (target != null) return target.rect;
    // No usable geometry at all (should only be reachable transiently before
    // the opening target resolves); collapse to a centered point so the
    // widget still renders something coherent rather than throwing.
    final viewport = _viewportRect(context);
    return Rect.fromCenter(center: viewport.center, width: 1, height: 1);
  }

  double _tileCornerRadius() =>
      (_frozenTarget ?? session.openingTarget)?.borderRadius ?? 0;

  PostPageMediaProxy? _activeProxy() =>
      _frozenProxy ?? session.openingTarget?.proxy;

  ImageProvider<Object>? _proxyImageProviderFor(PostPageMediaProxy? proxy) {
    final imageInfo = proxy?.imageInfo;
    if (imageInfo == null) return null;
    return _ResolvedImageInfoProvider(imageInfo);
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return ValueListenableBuilder<PostPageZoomPhase>(
      valueListenable: phaseListenable,
      builder: (context, currentPhase, _) {
        if (currentPhase == PostPageZoomPhase.preparingOpen) {
          final proxy = _activeProxy();
          return ColoredBox(
            color: proxy?.placeholderColor ?? const Color(0xFF000000),
          );
        }
        if (currentPhase == PostPageZoomPhase.closingFallback) {
          return _FallbackCloseTransition(
            progress: controller!,
            destinationChild: destinationBuilder(context),
          );
        }
        final proxy = _activeProxy();
        return PostPageZoomTransition(
          progress: controller!,
          tileRect: _tileRect(context),
          viewportRect: _viewportRect(context),
          tileCornerRadius: _tileCornerRadius(),
          destinationChild: destinationBuilder(context),
          proxyImageProvider: _proxyImageProviderFor(proxy),
          proxyColor: proxy?.placeholderColor ?? const Color(0xFF000000),
        );
      },
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;

  @override
  void dispose() {
    if (_sessionListenerAttached) {
      session.removeListener(_onSessionChanged);
      _sessionListenerAttached = false;
    }
    // No partially-dragged state may persist past disposal: force the
    // terminal `closed` state directly (bypassing legality checks, which is
    // safe here because the route is being torn down regardless).
    if (phase != PostPageZoomPhase.closed) {
      phaseListenable.value = PostPageZoomPhase.closed;
    }
    phaseListenable.dispose();
    super.dispose();
  }
}

/// Short fade + mild centered scale used for [PostPageZoomPhase.closingFallback]
/// (spec `Fallback and Error Handling` §). Never references source-tile
/// geometry, so it structurally cannot animate toward the opening A rect.
class _FallbackCloseTransition extends StatelessWidget {
  const _FallbackCloseTransition({
    required this.progress,
    required this.destinationChild,
  });

  final Animation<double> progress;
  final Widget destinationChild;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: progress,
      builder: (context, child) {
        final t = progress.value.clamp(0.0, 1.0);
        final scale = 0.92 + (0.08 * t);
        return Opacity(
          opacity: t,
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: destinationChild,
    );
  }
}

/// Wraps an already-resolved [ImageInfo] as a synchronous [ImageProvider], so
/// the proxy-selection ladder never awaits a decode (spec: "synchronous...
/// never blocks the first motion").
class _ResolvedImageInfoProvider
    extends ImageProvider<_ResolvedImageInfoProvider> {
  const _ResolvedImageInfoProvider(this.imageInfo);

  final ImageInfo imageInfo;

  @override
  Future<_ResolvedImageInfoProvider> obtainKey(
    ImageConfiguration configuration,
  ) => SynchronousFuture<_ResolvedImageInfoProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    _ResolvedImageInfoProvider key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(
      SynchronousFuture<ImageInfo>(imageInfo.clone()),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _ResolvedImageInfoProvider &&
      other.imageInfo.image.isCloneOf(imageInfo.image);

  @override
  int get hashCode => imageInfo.image.hashCode;
}

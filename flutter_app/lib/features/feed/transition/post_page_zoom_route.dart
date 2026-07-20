import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart' show PredictiveBackEvent, SwipeEdge;
import 'package:flutter/widgets.dart';

import 'post_detail_transition_session.dart';
import 'post_page_zoom_back_gesture.dart';
import 'post_page_zoom_geometry.dart';
import 'post_page_zoom_transition.dart';

/// Stable key on the leading-edge strip that arms the iOS interactive back
/// gesture. Installed ONLY on iOS; tests assert its absence on Android.
const Key postPageBackGestureEdgeKey = Key('post-page-zoom-back-edge');

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
/// callback stream, letting tests drive `start`/`progress`/`commit`/`cancel`
/// deterministically in lieu of the real platform channel. [progress] is the
/// linear back-gesture progress (0..1). [edge] is the reported swipe edge on a
/// `start` event; [SwipeEdge.right] mirrors the preview translation direction.
/// Defaults to null (no injection).
@visibleForTesting
void Function(
  PostPageZoomPredictiveEventKind kind, {
  double? progress,
  SwipeEdge? edge,
})?
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
  _PostPageZoomLifecycleObserver? _lifecycleObserver;

  // --- Interactive back (iOS edge swipe) state -----------------------------

  /// Drives the finger-down linear preview (0..1) and the cancel spring. Its
  /// value is set directly during a drag and animated (to 0) on cancel; the
  /// preview surface is a pure function of this value.
  AnimationController? _previewController;

  /// Drives the commit flight (0..1) that continues from the released
  /// transform to the frozen B tile.
  AnimationController? _commitController;

  /// The exact surface frame captured at gesture release; the commit flight
  /// starts from it so there is no visual restart.
  PostPageBackFrame? _commitFromFrame;

  /// True while a commit flight (interactive close toward B) is animating,
  /// selecting the interactive commit render path in [buildPage] instead of
  /// the non-interactive geometry reverse.
  bool _interactiveCommitActive = false;

  /// True once the frozen B tile has been suppressed during the terminal
  /// portion of the commit flight (so it is restored exactly once).
  bool _commitTileSuppressed = false;

  /// Last drag velocity reported through the gesture-progress seam / real
  /// recognizer; used by a no-argument [endInteractiveBack].
  double _lastGestureVelocity = 0;

  /// Global x of the drag start, for the real recognizer's linear mapping.
  double _dragStartGlobalDx = 0;

  /// True while the active interactive back should mirror its horizontal
  /// translation (Android Predictive Back from the RIGHT edge). The iOS
  /// leading-edge gesture and the Android left edge both leave this false.
  bool _backEdgeMirrored = false;

  /// The Android-only observer that receives system Predictive Back events and
  /// drives the shared interactive surface. Installed only on Android and only
  /// when the test predictive seam is not armed. Null on iOS and in production
  /// on iOS.
  _PostPageZoomPredictiveBackObserver? _predictiveObserver;

  /// True once this route has wired itself into a Predictive Back input source
  /// (the real Android observer, or the test seam). Never true on iOS.
  bool _predictiveParticipating = false;

  /// Guards the non-interactive system-back path so a burst of `maybePop`
  /// invocations (or a system back arriving while a reverse is already in
  /// flight) does not start a second close.
  bool _systemBackInProgress = false;

  /// True while the current interactive back was cancelled by a lifecycle /
  /// metrics interruption (backgrounding, rotation) rather than by the user
  /// releasing below threshold. An interruption cancel must keep media paused
  /// (the app is inactive); a plain user cancel that returns to `open` resumes
  /// playback. Cleared at the start of every fresh interactive back.
  bool _interruptedDuringBack = false;

  /// Test-only view of the current interactive-back surface frame, so gesture
  /// tests can assert first-frame continuity (cancel/commit start from the
  /// exact released transform) without reaching into private render state.
  @visibleForTesting
  PostPageBackFrame? get debugCurrentBackFrame {
    final viewport = _lastViewportRect;
    if (viewport == null) return null;
    if (_interactiveCommitActive) {
      final from = _commitFromFrame;
      final tile = _frozenTarget;
      if (from == null || tile == null) return null;
      return lerpPostPageBackFrame(
        from,
        tile.rect,
        tile.borderRadius,
        _commitController?.value ?? 0,
      );
    }
    final preview = _previewController;
    if (preview == null) return null;
    return resolvePostPageBackPreview(
      viewportRect: viewport,
      progress: preview.value,
      mirror: _backEdgeMirrored,
    );
  }

  /// Test-only view of the current linear preview progress.
  @visibleForTesting
  double? get debugBackPreviewProgress => _previewController?.value;

  /// Test-only view of whether this route participates in Android Predictive
  /// Back (true on Android via the real observer or the armed seam; always
  /// false on iOS, where the leading-edge recognizer is used instead).
  @visibleForTesting
  bool get debugPredictiveBackParticipating => _predictiveParticipating;

  Rect? _lastViewportRect;

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

  /// Ahead-of-time (synchronous) pop disposition consulted by
  /// `Navigator.maybePop` (system back / predictive-unavailable back) and by
  /// `PopScope`. While this route is the current top route and at rest in a
  /// user-facing phase, it reports [RoutePopDisposition.doNotPop] so the
  /// framework routes the system back into [onPopInvokedWithResult], where the
  /// route runs its own reverse rather than being popped abruptly. When the
  /// route is NOT topmost (a modal sheet/dialog sits above Postingan), it
  /// defers entirely to the default disposition, so that overlay owns the
  /// first back event and this route neither observes nor animates it. During
  /// a close already in flight it also defers, allowing the terminal pop.
  @override
  RoutePopDisposition get popDisposition {
    if (!isCurrent) return super.popDisposition;
    switch (phase) {
      case PostPageZoomPhase.open:
      case PostPageZoomPhase.interactiveBack:
      case PostPageZoomPhase.settlingOpenAfterCancel:
        return RoutePopDisposition.doNotPop;
      case PostPageZoomPhase.preparingOpen:
      case PostPageZoomPhase.opening:
      case PostPageZoomPhase.closingToTarget:
      case PostPageZoomPhase.closingFallback:
      case PostPageZoomPhase.closed:
        return super.popDisposition;
    }
  }

  /// Called by the framework after a `maybePop` that our [popDisposition]
  /// declined ([RoutePopDisposition.doNotPop]). A `didPop == false` from the
  /// resting `open` phase is a NON-INTERACTIVE system back (Android 3-button,
  /// or predictive back unavailable/disabled): run the Task-8 non-interactive
  /// reverse. Predictive gestures never arrive here — they are consumed by the
  /// dedicated observer while in `interactiveBack`.
  @override
  void onPopInvokedWithResult(bool didPop, void result) {
    if (!didPop &&
        !_systemBackInProgress &&
        phase == PostPageZoomPhase.open) {
      _systemBackInProgress = true;
      requestClose();
    }
    super.onPopInvokedWithResult(didPop, result);
  }

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
    _lifecycleObserver = _PostPageZoomLifecycleObserver(_handleInterruption);
    WidgetsBinding.instance.addObserver(_lifecycleObserver!);
    // When a test has ARMED the gesture-progress seam (set it non-null before
    // pushing), replace it with this route's bound driver so the test can feed
    // deterministic linear progress in lieu of synthesizing raw pointer
    // events. Production never arms it, so it stays null and the real iOS
    // recognizer is used instead.
    if (debugPostPageZoomGestureProgress != null) {
      debugPostPageZoomGestureProgress = _driveInteractiveBackFromSeam;
    }
    _installPredictiveBack();
  }

  /// Wires the route into a Predictive Back input source. On iOS the leading-
  /// edge pointer recognizer (installed in [buildPage]) is used instead, so
  /// nothing is wired here. When a test has ARMED the predictive seam, this
  /// route binds its own driver into it (deterministic test injection). In
  /// production on Android it installs a dedicated [WidgetsBindingObserver]
  /// that consumes system predictive-back events — NOT a Material predictive
  /// transition builder, and not a second global back handler.
  void _installPredictiveBack() {
    if (debugPostPageZoomPredictiveEvents != null) {
      debugPostPageZoomPredictiveEvents = _drivePredictiveFromSeam;
      _predictiveParticipating = true;
      return;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      _predictiveObserver = _PostPageZoomPredictiveBackObserver(this);
      WidgetsBinding.instance.addObserver(_predictiveObserver!);
      _predictiveParticipating = true;
    }
  }

  void _driveInteractiveBackFromSeam(double progress, double velocity) {
    if (phase == PostPageZoomPhase.open) beginInteractiveBack();
    if (phase == PostPageZoomPhase.interactiveBack) {
      updateInteractiveBack(progress);
      _lastGestureVelocity = velocity;
    }
  }

  void _drivePredictiveFromSeam(
    PostPageZoomPredictiveEventKind kind, {
    double? progress,
    SwipeEdge? edge,
  }) {
    switch (kind) {
      case PostPageZoomPredictiveEventKind.start:
        handlePredictiveBackStart(
          mirrored: edge == SwipeEdge.right,
          progress: progress ?? 0,
        );
      case PostPageZoomPredictiveEventKind.progress:
        handlePredictiveBackProgress(progress ?? 0);
      case PostPageZoomPredictiveEventKind.commit:
        handlePredictiveBackCommit();
      case PostPageZoomPredictiveEventKind.cancel:
        handlePredictiveBackCancel();
    }
  }

  // --- Android Predictive Back entry points. The real Android observer and the
  // test seam both funnel through these, so both drive the exact same
  // interactive surface and state machine as the iOS edge gesture. The route
  // handles predictive back ONLY while it is the current top route and at rest
  // in `open` (its synchronous pop disposition otherwise defers). ---

  /// System predictive-back gesture start. [mirrored] is true for a RIGHT-edge
  /// swipe (translation is mirrored). No-op unless the route is topmost and at
  /// rest in `open`.
  void handlePredictiveBackStart({
    required bool mirrored,
    required double progress,
  }) {
    if (!isCurrent) return;
    if (phase != PostPageZoomPhase.open) return;
    beginInteractiveBack(mirrored: mirrored);
    updateInteractiveBack(progress);
  }

  /// System predictive-back progress update (linear 0..1). Freeze happened at
  /// start; the edge is fixed for the duration of the gesture (no retarget).
  void handlePredictiveBackProgress(double progress) {
    if (phase != PostPageZoomPhase.interactiveBack) return;
    updateInteractiveBack(progress);
  }

  /// System predictive-back commit: continue from the exact current transform
  /// to the frozen B target with no geometry restart.
  void handlePredictiveBackCommit() {
    if (phase != PostPageZoomPhase.interactiveBack) return;
    commitInteractiveBack();
  }

  /// System predictive-back cancellation: spring the exact current transform
  /// back to fullscreen `open` with no restart.
  void handlePredictiveBackCancel() {
    if (phase != PostPageZoomPhase.interactiveBack) return;
    cancelInteractiveBack();
  }

  /// Backgrounding or a metrics change mid-gesture must cancel the gesture and
  /// restore the stable fullscreen `open` state (never auto-close), pausing
  /// media while inactive (spec `Fallback and Error Handling` §).
  void _handleInterruption() {
    if (phase != PostPageZoomPhase.interactiveBack) return;
    _interruptedDuringBack = true;
    session.setPlaybackAllowed(false);
    cancelInteractiveBack();
  }

  /// Test-only entry point for the lifecycle/metrics interruption path.
  @visibleForTesting
  void debugHandleInterruption() => _handleInterruption();

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

  // --- Interactive back (iOS edge swipe). The real recognizer (installed only
  // on iOS, see `buildPage`) and the test gesture-progress seam both drive
  // these entry points. ---

  AnimationController _ensurePreviewController() {
    return _previewController ??= AnimationController(
      vsync: navigator!,
      value: 0,
      duration: kPostPageBackCancelDuration,
    )..addListener(_onBackAnimationTick);
  }

  AnimationController _ensureCommitController() {
    return _commitController ??= AnimationController(
      vsync: navigator!,
      value: 0,
      duration: kPostPageBackCommitDuration,
    )..addListener(_onBackAnimationTick);
  }

  void _onBackAnimationTick() {
    // Drive the terminal-portion suppression of the frozen B tile during the
    // commit flight (B stays visible in the revealed Profile until the closing
    // surface overlaps it).
    if (_interactiveCommitActive &&
        !_commitTileSuppressed &&
        (_commitController?.value ?? 0) >= kPostPageBackCommitSuppressThreshold) {
      _commitTileSuppressed = true;
      session.setFrozenTileSuppressed(true);
    }
  }

  /// Gesture start: freeze B at the FIRST progress event (before any transform)
  /// and enter the interactive preview. No scroll/pagination/visibility
  /// callback may retarget the frozen target until a cancel settles.
  void beginInteractiveBack({bool mirrored = false}) {
    if (phase != PostPageZoomPhase.open) {
      throw StateError(
        'beginInteractiveBack requires phase == open, got $phase',
      );
    }
    controller!.stop();
    _backEdgeMirrored = mirrored;
    _interruptedDuringBack = false;
    // A reverse transition pauses the active video BEFORE the surface moves
    // (spec `Media Rules` §). The preview begins at progress 0 (no transform
    // yet), so pausing here is strictly before the first surface movement.
    session.setPlaybackAllowed(false);
    // Freeze precedes any transform (spec `Freezing the target` §).
    final frozen = session.freeze();
    _frozenTarget = frozen.target;
    _frozenProxy = frozen.proxy;
    _ensurePreviewController().value = 0;
    _setPhase(PostPageZoomPhase.interactiveBack);
  }

  /// Linear finger progress (0..1). No easing while the finger is down.
  void updateInteractiveBack(double progress) {
    if (phase != PostPageZoomPhase.interactiveBack) {
      throw StateError(
        'updateInteractiveBack requires phase == interactiveBack, got $phase',
      );
    }
    _ensurePreviewController().value = progress.clamp(0.0, 1.0);
  }

  /// Gesture release. Commits at >=25% progress OR a fling >=800 px/s; else
  /// cancels. Uses the last reported velocity when [velocity] is omitted.
  Future<void> endInteractiveBack([double? velocity]) {
    if (phase != PostPageZoomPhase.interactiveBack) {
      throw StateError(
        'endInteractiveBack requires phase == interactiveBack, got $phase',
      );
    }
    final v = velocity ?? _lastGestureVelocity;
    final progress = _previewController?.value ?? 0;
    // A leading-edge swipe commits when flung toward the trailing side
    // (positive x velocity for LTR) or dragged past the threshold.
    final commit =
        progress >= kPostPageBackCommitProgressThreshold ||
        v >= kPostPageBackCommitVelocity;
    if (commit) return commitInteractiveBack();
    cancelInteractiveBack();
    return Future<void>.value();
  }

  void cancelInteractiveBack() {
    if (phase != PostPageZoomPhase.interactiveBack) {
      throw StateError(
        'cancelInteractiveBack requires phase == interactiveBack, got $phase',
      );
    }
    _setPhase(PostPageZoomPhase.settlingOpenAfterCancel);
    // Spring from the EXACT current transform back to fullscreen (progress 0)
    // with no visual restart.
    _ensurePreviewController()
        .animateTo(
          0.0,
          duration: kPostPageBackCancelDuration,
          curve: Curves.easeOutCubic,
        )
        .whenCompleteOrCancel(() {
          if (phase == PostPageZoomPhase.settlingOpenAfterCancel) {
            _frozenTarget = null;
            _frozenProxy = null;
            _setPhase(PostPageZoomPhase.open);
            // Unfreeze only after the page has settled back to fullscreen.
            session.resumeTrackingAfterCanceledBack();
            // A user cancel returns to a stable, active `open`, so resume
            // playback. An interruption cancel (backgrounding/rotation) leaves
            // the app inactive, so media stays paused until the app resumes.
            if (!_interruptedDuringBack) {
              session.setPlaybackAllowed(true);
            }
          }
        });
  }

  Future<void> commitInteractiveBack() {
    if (phase != PostPageZoomPhase.interactiveBack) {
      throw StateError(
        'commitInteractiveBack requires phase == interactiveBack, got $phase',
      );
    }
    // Already frozen at gesture start. If there is no usable B tile, fall back
    // to the dedicated fade+scale close instead of animating toward a tile.
    if (_frozenTarget == null) {
      return _performFallbackClose();
    }
    return _performInteractiveCommit();
  }

  Future<void> _performInteractiveCommit() async {
    final viewport = _lastViewportRect;
    _commitFromFrame = viewport == null
        ? PostPageBackFrame(
            rect: _frozenTarget!.rect,
            radius: _frozenTarget!.borderRadius,
          )
        : resolvePostPageBackPreview(
            viewportRect: viewport,
            progress: _previewController?.value ?? 0,
            mirror: _backEdgeMirrored,
          );
    _interactiveCommitActive = true;
    _commitTileSuppressed = false;
    final commit = _ensureCommitController()..value = 0;
    _setPhase(PostPageZoomPhase.closingToTarget);
    // Continue from the exact current transform to B (no restart).
    await commit.animateTo(
      1.0,
      duration: kPostPageBackCommitDuration,
      curve: Curves.easeInCubic,
    );
    if (_commitTileSuppressed) {
      session.setFrozenTileSuppressed(false);
      _commitTileSuppressed = false;
    }
    _interactiveCommitActive = false;

    if (phase == PostPageZoomPhase.closed) return;
    _setPhase(PostPageZoomPhase.closed);
    final nav = navigator;
    if (nav != null && nav.mounted && nav.canPop()) {
      nav.pop();
    }
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
    // reverse flight). `freeze()` is idempotent, so an interactive gesture
    // that already froze at its first progress event is respected here.
    final frozen = session.freeze();

    if (frozen.usesFallback) {
      return _performFallbackClose();
    }

    // Pause the active video BEFORE the reverse surface moves (spec `Media
    // Rules` §), and before the B tile is suppressed / the flight begins.
    session.setPlaybackAllowed(false);
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
    _finishClose();
  }

  Future<void> _performFallbackClose() async {
    // Pause the active video before the fallback surface animates (spec `Media
    // Rules` §): a fallback close is still a reverse transition.
    session.setPlaybackAllowed(false);
    final frozen = session.freeze();
    _frozenTarget = null;
    _frozenProxy = frozen.proxy;
    // Fallback reverse never targets the opening A rect: assign the pending
    // return target before the pop completes so the source can do its own
    // bounded best-effort positioning; never reuse the opening geometry for
    // the animation itself.
    session.assignPendingReturnTarget();
    _setPhase(PostPageZoomPhase.closingFallback);
    await controller!.animateTo(
      0.0,
      duration: _kFallbackReverseDuration,
      curve: Curves.easeOut,
    );
    _finishClose();
  }

  void _finishClose() {
    // The route may have been force-disposed (e.g. an app-level teardown
    // interrupting a normal back navigation) while an `await` above was
    // pending. `dispose()` already forced `phase` to `closed` in that case;
    // treat that as this close having already finished rather than trying
    // to replay a `closed -> closed` transition (which isn't in the
    // legality map and would otherwise throw from this unawaited-by-caller
    // async continuation) or popping a route that no longer owns a
    // navigator entry.
    if (phase == PostPageZoomPhase.closed) return;

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
    _lastViewportRect = _viewportRect(context);
    return ValueListenableBuilder<PostPageZoomPhase>(
      valueListenable: phaseListenable,
      builder: (context, currentPhase, _) {
        final content = _buildPhaseContent(context, currentPhase);
        // Install the iOS interactive leading-edge recognizer only on iOS; it
        // must be absent on Android (Predictive Back is Task 13).
        if (defaultTargetPlatform != TargetPlatform.iOS) return content;
        return _buildWithEdgeGesture(context, content);
      },
    );
  }

  Widget _buildPhaseContent(
    BuildContext context,
    PostPageZoomPhase currentPhase,
  ) {
    if (currentPhase == PostPageZoomPhase.preparingOpen) {
      final proxy = _activeProxy();
      return ColoredBox(
        color: proxy?.placeholderColor ?? const Color(0xFF000000),
      );
    }
    if (currentPhase == PostPageZoomPhase.interactiveBack ||
        currentPhase == PostPageZoomPhase.settlingOpenAfterCancel) {
      return _buildInteractivePreview(context);
    }
    if (currentPhase == PostPageZoomPhase.closingToTarget &&
        _interactiveCommitActive) {
      return _buildInteractiveCommit(context);
    }
    if (currentPhase == PostPageZoomPhase.closingFallback) {
      return _FallbackCloseTransition(
        progress: controller!,
        destinationChild: destinationBuilder(context),
      );
    }
    final proxy = _activeProxy();
    // Two openings the spec routes away from the geometry zoom, into a short
    // crossfade + mild centered scale:
    //   * Reduced motion (spec `Performance and Accessibility -> Reduced
    //     motion` §).
    //   * Crossfade fallback (spec `Destination readiness` §): the bounded
    //     readiness stage missed its budget, so this opening must "abandon
    //     geometry zoom ... and use a 160 ms crossfade only after the
    //     destination is stable" — it must NOT zoom from the tile rect.
    // The B-targeting machinery (freeze / prepared target / pending return) is
    // untouched, so an A->B reverse still resolves B and predictive back /
    // commit / cancel behave identically; only the *render* changes.
    if (_reducedMotion(context) ||
        session.destinationReadiness ==
            PostDetailDestinationReadiness.crossfadeFallback) {
      return _CrossfadeZoomTransition(
        progress: controller!,
        destinationChild: destinationBuilder(context),
        proxyImageProvider: _proxyImageProviderFor(proxy),
        proxyColor: proxy?.placeholderColor ?? const Color(0xFF000000),
      );
    }
    return PostPageZoomTransition(
      progress: controller!,
      tileRect: _tileRect(context),
      viewportRect: _viewportRect(context),
      tileCornerRadius: _tileCornerRadius(),
      destinationChild: destinationBuilder(context),
      proxyImageProvider: _proxyImageProviderFor(proxy),
      proxyColor: proxy?.placeholderColor ?? const Color(0xFF000000),
    );
  }

  /// Whether the platform requests reduced motion (system animation reduction
  /// or an assistive navigation mode). Consulted per-build so a mid-flight
  /// accessibility change is honored.
  bool _reducedMotion(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    if (media == null) return false;
    return media.disableAnimations || media.accessibleNavigation;
  }

  Widget _buildInteractivePreview(BuildContext context) {
    final viewport = _viewportRect(context);
    final preview = _ensurePreviewController();
    return AnimatedBuilder(
      animation: preview,
      builder: (context, child) {
        final frame = resolvePostPageBackPreview(
          viewportRect: viewport,
          progress: preview.value,
          mirror: _backEdgeMirrored,
        );
        return PostPageBackSurface(
          frame: frame,
          viewportRect: viewport,
          child: child!,
        );
      },
      child: RepaintBoundary(child: destinationBuilder(context)),
    );
  }

  Widget _buildInteractiveCommit(BuildContext context) {
    final viewport = _viewportRect(context);
    final commit = _ensureCommitController();
    final from = _commitFromFrame!;
    final tile = _frozenTarget!;
    return AnimatedBuilder(
      animation: commit,
      builder: (context, child) {
        final frame = lerpPostPageBackFrame(
          from,
          tile.rect,
          tile.borderRadius,
          commit.value,
        );
        return PostPageBackSurface(
          frame: frame,
          viewportRect: viewport,
          child: child!,
        );
      },
      child: RepaintBoundary(child: destinationBuilder(context)),
    );
  }

  /// Wraps [content] with a leading-edge strip that recognizes the iOS
  /// interactive back gesture. The physical side is derived from the ambient
  /// text direction (leading == left for LTR).
  Widget _buildWithEdgeGesture(BuildContext context, Widget content) {
    final isLtr =
        (Directionality.maybeOf(context) ?? TextDirection.ltr) ==
        TextDirection.ltr;
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        Positioned.fill(child: content),
        Positioned(
          key: postPageBackGestureEdgeKey,
          top: 0,
          bottom: 0,
          left: isLtr ? 0 : null,
          right: isLtr ? null : 0,
          width: kPostPageBackGestureEdgeWidth,
          child: RawGestureDetector(
            behavior: HitTestBehavior.translucent,
            gestures: <Type, GestureRecognizerFactory>{
              HorizontalDragGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    HorizontalDragGestureRecognizer
                  >(
                    () => HorizontalDragGestureRecognizer(debugOwner: this),
                    (recognizer) {
                      recognizer
                        ..onStart = _onEdgeDragStart
                        ..onUpdate = _onEdgeDragUpdate
                        ..onEnd = _onEdgeDragEnd
                        ..onCancel = _onEdgeDragCancel;
                    },
                  ),
            },
          ),
        ),
      ],
    );
  }

  void _onEdgeDragStart(DragStartDetails details) {
    if (phase != PostPageZoomPhase.open) return;
    _dragStartGlobalDx = details.globalPosition.dx;
    beginInteractiveBack();
  }

  void _onEdgeDragUpdate(DragUpdateDetails details) {
    if (phase != PostPageZoomPhase.interactiveBack) return;
    final viewport = _lastViewportRect;
    final extent = (viewport?.width ?? 0);
    if (extent <= 0) return;
    final isLtr = _frozenTarget?.textDirection != TextDirection.rtl;
    final delta = (details.globalPosition.dx - _dragStartGlobalDx) *
        (isLtr ? 1 : -1);
    updateInteractiveBack((delta / extent).clamp(0.0, 1.0));
    _lastGestureVelocity = 0;
  }

  void _onEdgeDragEnd(DragEndDetails details) {
    if (phase != PostPageZoomPhase.interactiveBack) return;
    final v = details.primaryVelocity ?? 0;
    endInteractiveBack(v);
  }

  void _onEdgeDragCancel() {
    if (phase == PostPageZoomPhase.interactiveBack) cancelInteractiveBack();
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
    if (_lifecycleObserver != null) {
      WidgetsBinding.instance.removeObserver(_lifecycleObserver!);
      _lifecycleObserver = null;
    }
    // Release the gesture-progress seam if this route published its driver
    // into it, so a torn-down route never leaves a dangling closure behind.
    if (debugPostPageZoomGestureProgress == _driveInteractiveBackFromSeam) {
      debugPostPageZoomGestureProgress = null;
    }
    // Detach the Android Predictive Back observer and release the predictive
    // seam symmetrically, so no torn-down route keeps receiving system events
    // or leaves a dangling test closure behind.
    if (_predictiveObserver != null) {
      WidgetsBinding.instance.removeObserver(_predictiveObserver!);
      _predictiveObserver = null;
    }
    if (debugPostPageZoomPredictiveEvents == _drivePredictiveFromSeam) {
      debugPostPageZoomPredictiveEvents = null;
    }
    _previewController?.stop(canceled: false);
    _previewController?.dispose();
    _previewController = null;
    _commitController?.stop(canceled: false);
    _commitController?.dispose();
    _commitController = null;
    // Stop any in-flight animation (e.g. a pending `_performClose` reverse
    // flight) BEFORE the phase is force-closed and the controller disposed.
    // `canceled: false` is required here: `AnimationController.stop()`
    // defaults to `canceled: true`, which resolves the *ticker's* future via
    // `TickerFuture.cancel()` — a plain `await` on that future then never
    // completes (only `.orCancel` would reject). `canceled: false` completes
    // it normally, so `_performClose`'s pending `await
    // controller!.animateTo(...)` actually resumes instead of hanging
    // forever when the controller is disposed out from under it below.
    controller?.stop(canceled: false);
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

/// Forwards app lifecycle and metrics changes to the route's interruption
/// handler. Kept as a standalone observer (rather than mixing
/// `WidgetsBindingObserver` into the route) because `TransitionRoute` already
/// declares its own predictive-back hook signatures that would clash.
class _PostPageZoomLifecycleObserver with WidgetsBindingObserver {
  _PostPageZoomLifecycleObserver(this._onInterruption);

  final VoidCallback _onInterruption;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _onInterruption();
  }

  @override
  void didChangeMetrics() => _onInterruption();
}

/// Consumes system Android Predictive Back events and drives the route's
/// shared interactive-back surface. Kept as a dedicated
/// [WidgetsBindingObserver] (rather than the Material
/// `PredictiveBackPageTransitionsBuilder`, which the spec forbids wrapping
/// around the custom route) so predictive back participates through Flutter's
/// route hooks WITHOUT stacking a second global back handler or a generic
/// Material transition builder. It claims the gesture only while the route is
/// the current top route and at rest in `open`; otherwise it returns false so
/// a modal above Postingan (or the non-interactive fallback) handles the back.
class _PostPageZoomPredictiveBackObserver with WidgetsBindingObserver {
  _PostPageZoomPredictiveBackObserver(this._route);

  final PostPageZoomRoute _route;

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    // A hardware/3-button back arrives as a "button event": leave it to the
    // non-interactive `maybePop`/`popDisposition` path.
    if (backEvent.isButtonEvent) return false;
    if (!_route.isCurrent) return false;
    if (_route.phase != PostPageZoomPhase.open) return false;
    _route.handlePredictiveBackStart(
      mirrored: backEvent.swipeEdge == SwipeEdge.right,
      progress: backEvent.progress,
    );
    // Only claim the gesture if the route actually entered the interactive
    // preview (guards against any last-moment phase change).
    return _route.phase == PostPageZoomPhase.interactiveBack;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) {
    _route.handlePredictiveBackProgress(backEvent.progress);
  }

  @override
  void handleCommitBackGesture() => _route.handlePredictiveBackCommit();

  @override
  void handleCancelBackGesture() => _route.handlePredictiveBackCancel();
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

/// Crossfade opening / non-interactive-close render: a short crossfade
/// (clean proxy -> complete destination) under a mild centered scale, driven by
/// the same forward/reverse [progress] the geometry zoom would use. It never
/// references source-tile geometry, so it structurally cannot perform the full
/// zoom; the route's freeze / target machinery still resolves B independently.
///
/// Serves two openings the spec routes away from a geometry zoom: reduced
/// motion (`Performance and Accessibility -> Reduced motion` §) AND the
/// `Destination readiness` crossfade fallback (bounded readiness stage missed
/// its budget, so the opening abandons the geometry zoom for a 160 ms crossfade
/// only after the destination is stable).
class _CrossfadeZoomTransition extends StatelessWidget {
  const _CrossfadeZoomTransition({
    required this.progress,
    required this.destinationChild,
    this.proxyImageProvider,
    this.proxyColor = const Color(0x00000000),
  });

  final Animation<double> progress;
  final Widget destinationChild;
  final ImageProvider<Object>? proxyImageProvider;
  final Color proxyColor;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: progress,
      builder: (context, child) {
        final t = progress.value.clamp(0.0, 1.0);
        // Mild centered scale (0.96 -> 1.0), and a crossfade that completes in
        // the first portion of the flight so it never competes with a later
        // destination fade.
        final scale = 0.96 + (0.04 * t);
        final crossfadeT =
            (t / postPageZoomCrossfadeProgressThreshold).clamp(0.0, 1.0);
        return Transform.scale(
          scale: scale,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Opacity(
                opacity: 1.0 - crossfadeT,
                child: proxyImageProvider != null
                    ? Image(image: proxyImageProvider!, fit: BoxFit.cover)
                    : ColoredBox(color: proxyColor),
              ),
              Opacity(opacity: crossfadeT, child: child),
            ],
          ),
        );
      },
      child: RepaintBoundary(child: destinationChild),
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

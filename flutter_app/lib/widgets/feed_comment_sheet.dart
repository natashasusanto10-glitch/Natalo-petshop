import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/feed_comment.dart';
import '../models/feed_post.dart';
import '../services/api_client.dart';
import '../services/block_service.dart';
import '../services/feed_service.dart';
import '../services/report_service.dart';
import '../state/feed_comment_interaction_store.dart';
import '../state/feed_comment_session_store.dart';
import '../state/feed_comment_sync_coordinator.dart';
import '../state/feed_store.dart';
import '../state/member_store.dart';
import '../theme/natalo_colors.dart';
import 'official_brand_avatar.dart';
import '../utils/haptics.dart';
import '../utils/mention_text.dart';
import 'app_toast.dart';
import 'mention_picker.dart';
import 'moderation_action_sheet.dart';
import 'natalo_paw_refresh_indicator.dart';
import 'profile_avatar.dart';

/// Shared detents and gesture policy for both comment drawer presentation
/// adapters: the modal drawer and the embedded video-linked drawer.
const double feedCommentInitialExtent = 0.60;
const double feedCommentDismissExtent = 0.30;
const double feedCommentFlingVelocity = 520;
const Duration feedCommentSnapDuration = Duration(milliseconds: 220);

enum CommentSnapTarget { close, initial, max }

@immutable
class FeedCommentViewerIdentity {
  const FeedCommentViewerIdentity({
    required this.viewerId,
    required this.generation,
  });

  final String viewerId;
  final int generation;
}

String _replyMentionPrefix(FeedComment comment) {
  final mention = comment.author.isOfficialAccount
      ? comment.author.displayName
      : comment.author.username ?? comment.author.displayName;
  return '@$mention ';
}

/// Changes reply targets without discarding text the viewer already typed.
/// An automatically inserted previous mention is replaced, while the body of
/// the draft remains intact.
@visibleForTesting
String preserveFeedReplyDraft({
  required String draft,
  FeedComment? previousTarget,
  FeedComment? nextTarget,
}) {
  var body = draft;
  if (previousTarget != null) {
    final previousPrefix = _replyMentionPrefix(previousTarget);
    if (body.startsWith(previousPrefix)) {
      body = body.substring(previousPrefix.length);
    }
  }
  if (nextTarget == null) return body;
  final nextPrefix = _replyMentionPrefix(nextTarget);
  if (body.startsWith(nextPrefix)) return body;
  return '$nextPrefix$body';
}

/// Chooses the same drag-end destination regardless of which presentation
/// adapter owns the drawer.
CommentSnapTarget commentSnapTargetFor({
  required double size,
  required double velocity,
  required double maxExtent,
}) {
  if (velocity > feedCommentFlingVelocity || size <= feedCommentDismissExtent) {
    return CommentSnapTarget.close;
  }
  if (velocity < -feedCommentFlingVelocity) {
    return CommentSnapTarget.max;
  }
  final expandThreshold = (feedCommentInitialExtent + maxExtent) / 2;
  return size >= expandThreshold
      ? CommentSnapTarget.max
      : CommentSnapTarget.initial;
}

bool shouldPauseForCommentExtent({
  required double extent,
  required double maxExtent,
}) {
  return extent >= maxExtent - 0.02;
}

Future<void>? _activeFeedCommentDrawerFlight;

/// Opens the same comment experience used by the fullscreen Feed from
/// non-fullscreen surfaces such as Postingan. The modal route owns only the
/// presentation; [FeedCommentSheet] remains the single source of comment
/// loading, replies, moderation, and optimistic state.
Future<void> showFeedCommentDrawer(
  BuildContext context, {
  required FeedPost post,
  FeedCommentSessionStore? sessionStore,
  ValueListenable<FeedCommentViewerIdentity>? viewerIdentityListenable,
}) {
  final activeFlight = _activeFeedCommentDrawerFlight;
  if (activeFlight != null) return activeFlight;

  final completer = Completer<void>();
  final flight = completer.future;
  _activeFeedCommentDrawerFlight = flight;
  unawaited(() async {
    try {
      await _presentFeedCommentDrawer(
        context,
        post: post,
        sessionStore: sessionStore,
        viewerIdentityListenable: viewerIdentityListenable,
      );
      completer.complete();
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
    } finally {
      if (identical(_activeFeedCommentDrawerFlight, flight)) {
        _activeFeedCommentDrawerFlight = null;
      }
    }
  }());
  return flight;
}

Future<void> _presentFeedCommentDrawer(
  BuildContext context, {
  required FeedPost post,
  FeedCommentSessionStore? sessionStore,
  ValueListenable<FeedCommentViewerIdentity>? viewerIdentityListenable,
}) {
  final sheetController = DraggableScrollableController();
  final viewerIdentity = viewerIdentityListenable?.value ??
      FeedCommentViewerIdentity(
        viewerId: memberStore.profile?.id ?? 'guest',
        generation: memberStore.viewerGeneration,
      );
  final commentSession = (sessionStore ?? feedCommentSessionStore).sessionFor(
    viewerId: viewerIdentity.viewerId,
    postId: post.id,
  );
  final routeClosed = Completer<void>();
  var reachedVisibleExtent = false;
  var dismissScheduled = false;
  var popIssued = false;
  NavigatorState? commentNavigator;
  ModalRoute<void>? commentRoute;
  final route = showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: false,
    // The DraggableScrollableSheet below is the sole drag owner. Letting the
    // modal BottomSheet compete for the same vertical gesture can leave both
    // recognizers waiting, which feels like a stuck drawer on iOS/Android.
    enableDrag: false,
    isDismissible: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.62),
    builder: (sheetContext) {
      commentNavigator ??= Navigator.of(sheetContext);
      commentRoute ??= ModalRoute.of<void>(sheetContext);
      final topInset = MediaQuery.paddingOf(sheetContext).top;
      final screenHeight = MediaQuery.sizeOf(sheetContext).height;
      final maxExtent = (1 - (topInset / screenHeight)).clamp(0.60, 0.96);
      final initialExtent =
          (commentSession.sheetExtent ?? feedCommentInitialExtent)
              .clamp(feedCommentInitialExtent, maxExtent)
              .toDouble();

      void dismissDrawer({bool afterFrame = false}) {
        void popOnce() {
          if (popIssued) return;
          final navigator = commentNavigator;
          final modalRoute = commentRoute;
          if (navigator == null || !navigator.mounted || modalRoute == null) {
            return;
          }
          popIssued = true;
          if (modalRoute.isCurrent) {
            navigator.pop();
          } else {
            // Account changes can arrive while a mention/moderation dialog is
            // above this route. Remove this exact drawer instead of waiting
            // for it to become current and holding the global admission lock.
            navigator.removeRoute(modalRoute);
          }
        }

        if (afterFrame) {
          if (dismissScheduled || popIssued) return;
          dismissScheduled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            dismissScheduled = false;
            popOnce();
          });
        } else {
          dismissScheduled = false;
          popOnce();
        }
      }

      Future<void> dismissDrawerAndWait() async {
        dismissDrawer();
        await routeClosed.future;
        // Let showFeedCommentDrawer's outer finally release its global
        // admission lock before the destination route becomes interactive.
        await Future<void>.delayed(Duration.zero);
      }

      void handleDragUpdate(DragUpdateDetails details) {
        if (!sheetController.isAttached) return;
        final delta = details.primaryDelta ?? 0;
        if (delta == 0) return;
        final next = (sheetController.size - (delta / screenHeight))
            .clamp(0.20, maxExtent)
            .toDouble();
        sheetController.jumpTo(next);
      }

      void handleDragEnd(DragEndDetails details) {
        if (!sheetController.isAttached) return;
        final velocity = details.primaryVelocity ?? 0;
        final size = sheetController.size;
        final snapTarget = commentSnapTargetFor(
          size: size,
          velocity: velocity,
          maxExtent: maxExtent,
        );
        switch (snapTarget) {
          case CommentSnapTarget.close:
            dismissDrawer();
          case CommentSnapTarget.max:
            commentSession.sheetExtent = maxExtent;
            unawaited(() async {
              try {
                await sheetController.animateTo(
                  maxExtent,
                  duration: feedCommentSnapDuration,
                  curve: Curves.easeOutCubic,
                );
              } catch (_) {
                // The modal may be dismissed by back/barrier during snap.
              }
            }());
          case CommentSnapTarget.initial:
            commentSession.sheetExtent = feedCommentInitialExtent;
            unawaited(() async {
              try {
                await sheetController.animateTo(
                  feedCommentInitialExtent,
                  duration: feedCommentSnapDuration,
                  curve: Curves.easeOutCubic,
                );
              } catch (_) {
                // The modal may be dismissed by back/barrier during snap.
              }
            }());
        }
      }

      return NotificationListener<DraggableScrollableNotification>(
        onNotification: (notification) {
          if (notification.extent > 0.24) reachedVisibleExtent = true;
          if (!popIssued && notification.extent >= feedCommentDismissExtent) {
            commentSession.sheetExtent = notification.extent;
          }
          if (reachedVisibleExtent && notification.extent <= 0.205) {
            dismissDrawer(afterFrame: true);
          }
          return false;
        },
        child: DraggableScrollableSheet(
          controller: sheetController,
          expand: false,
          initialChildSize: initialExtent,
          // Keep enough collapse range for a decisive downward dismissal.
          minChildSize: 0.20,
          maxChildSize: maxExtent,
          snap: true,
          snapSizes: [feedCommentInitialExtent, maxExtent],
          // Closure is handled explicitly by the notification listener. The
          // framework callback is inconsistent when nested in a modal route.
          shouldCloseOnMinExtent: false,
          builder: (context, scrollController) => PrimaryScrollController(
            controller: scrollController,
            child: FeedCommentSheet(
              post: post,
              sheetScrollController: scrollController,
              onClose: dismissDrawer,
              onCloseAndWait: dismissDrawerAndWait,
              onDragUpdate: handleDragUpdate,
              onDragEnd: handleDragEnd,
              sessionStore: sessionStore,
              viewerIdentityListenable: viewerIdentityListenable,
            ),
          ),
        ),
      );
    },
  );
  return route.whenComplete(() {
    if (!routeClosed.isCompleted) routeClosed.complete();
    sheetController.dispose();
  });
}

/// Embedded Reels presentation used by photo/carousel posts. The comment data
/// stays in [FeedCommentSheet], while this adapter owns only extent, media
/// transform, and the drawer lifecycle.
class FeedReelsCommentSurface extends StatefulWidget {
  final FeedPost post;
  final Widget child;
  final bool open;
  final VoidCallback onClosed;
  final ValueChanged<double>? onExtentChanged;
  final ValueChanged<bool>? onMaximumExtentChanged;
  final FeedCommentSessionStore? sessionStore;
  final ValueListenable<FeedCommentViewerIdentity>? viewerIdentityListenable;

  const FeedReelsCommentSurface({
    super.key,
    required this.post,
    required this.child,
    required this.open,
    required this.onClosed,
    this.onExtentChanged,
    this.onMaximumExtentChanged,
    this.sessionStore,
    this.viewerIdentityListenable,
  });

  @override
  State<FeedReelsCommentSurface> createState() =>
      _FeedReelsCommentSurfaceState();
}

class _FeedReelsCommentSurfaceState extends State<FeedReelsCommentSurface> {
  static const double _minExtent = 0.0;
  static const double _initialExtent = feedCommentInitialExtent;
  static const double _dismissExtent = feedCommentDismissExtent;
  static const double _maxThreshold = 0.02;

  late final DraggableScrollableController _controller;
  Timer? _openWatchdog;
  Completer<void>? _closeCompleter;
  int _transition = 0;
  bool _mountedDrawer = false;
  bool _closing = false;
  bool _maximumNotified = false;
  double _extent = 0;

  @override
  void initState() {
    super.initState();
    _controller = DraggableScrollableController()..addListener(_syncExtent);
    if (widget.open) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openDrawer());
    }
  }

  @override
  void didUpdateWidget(covariant FeedReelsCommentSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.open == widget.open) return;
    if (widget.open) {
      _openDrawer();
    } else {
      _closeDrawer();
    }
  }

  @override
  void dispose() {
    _openWatchdog?.cancel();
    final completer = _closeCompleter;
    _closeCompleter = null;
    if (completer != null && !completer.isCompleted) completer.complete();
    _controller.removeListener(_syncExtent);
    _controller.dispose();
    super.dispose();
  }

  double _maxExtent(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final topInset = MediaQuery.paddingOf(context).top;
    final hostHeight =
        math.max(1.0, size.height - MediaQuery.viewInsetsOf(context).bottom);
    return (1 - (topInset / hostHeight)).clamp(0.60, 0.96).toDouble();
  }

  void _syncExtent() {
    if (!_mountedDrawer || !_controller.isAttached || !mounted) return;
    final maxExtent = _maxExtent(context);
    final next = _controller.size.clamp(_minExtent, maxExtent).toDouble();
    if ((_extent - next).abs() > 0.002) {
      setState(() => _extent = next);
      widget.onExtentChanged?.call(next);
    }
    final atMaximum = next >= maxExtent - _maxThreshold;
    if (atMaximum != _maximumNotified) {
      _maximumNotified = atMaximum;
      widget.onMaximumExtentChanged?.call(atMaximum);
    }
  }

  void _openDrawer() {
    if (!mounted || _mountedDrawer) return;
    final transition = ++_transition;
    _closing = false;
    _maximumNotified = false;
    setState(() {
      _mountedDrawer = true;
      _extent = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || transition != _transition || !_mountedDrawer) return;
      if (!_controller.isAttached) {
        _failOpen();
        return;
      }
      unawaited(() async {
        try {
          await _controller.animateTo(
            _initialExtent,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
          );
        } catch (_) {
          if (mounted && transition == _transition) _failOpen();
        }
      }());
      _openWatchdog?.cancel();
      _openWatchdog = Timer(const Duration(milliseconds: 700), () {
        if (!mounted || transition != _transition || !_mountedDrawer) return;
        if (!_controller.isAttached || _extent < _dismissExtent) {
          _failOpen();
        }
      });
    });
  }

  void _failOpen() {
    _openWatchdog?.cancel();
    _transition++;
    _closing = false;
    _maximumNotified = false;
    if (mounted) {
      setState(() {
        _mountedDrawer = false;
        _extent = 0;
      });
    }
    widget.onExtentChanged?.call(0);
    widget.onMaximumExtentChanged?.call(false);
    final completer = _closeCompleter;
    _closeCompleter = null;
    if (completer != null && !completer.isCompleted) completer.complete();
    widget.onClosed();
  }

  void _requestClose() {
    if (!_mountedDrawer || _closing) return;
    _closeDrawer();
  }

  Future<void> _requestCloseAndWait() {
    if (!_mountedDrawer) return Future<void>.value();
    _closeCompleter ??= Completer<void>();
    _requestClose();
    return _closeCompleter!.future;
  }

  void _closeDrawer() {
    if (!_mountedDrawer || _closing) return;
    final transition = ++_transition;
    _closing = true;
    _openWatchdog?.cancel();
    if (!_controller.isAttached) {
      _finishClose();
      return;
    }
    unawaited(() async {
      try {
        await _controller.animateTo(
          _minExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      } catch (_) {
        // The route/widget may detach during the closing transition.
      }
      if (mounted && transition == _transition) _finishClose();
    }());
  }

  void _finishClose() {
    _transition++;
    _closing = false;
    _maximumNotified = false;
    if (mounted) {
      setState(() {
        _mountedDrawer = false;
        _extent = 0;
      });
    }
    widget.onExtentChanged?.call(0);
    widget.onMaximumExtentChanged?.call(false);
    final completer = _closeCompleter;
    _closeCompleter = null;
    if (completer != null && !completer.isCompleted) completer.complete();
    widget.onClosed();
  }

  @override
  Widget build(BuildContext context) {
    final maxExtent = _maxExtent(context);
    final progress =
        maxExtent <= 0 ? 0.0 : (_extent / maxExtent).clamp(0.0, 1.0);
    final scale = 1.0 - (0.18 * progress);
    final translateY = -MediaQuery.sizeOf(context).height * 0.10 * progress;

    return Stack(
      fit: StackFit.expand,
      children: [
        Transform.translate(
          offset: Offset(0, translateY),
          child: Transform.scale(
            alignment: Alignment.topCenter,
            scale: scale,
            child: widget.child,
          ),
        ),
        if (_mountedDrawer)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _requestClose,
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.72 * progress),
              ),
            ),
          ),
        if (_mountedDrawer)
          DraggableScrollableSheet(
            controller: _controller,
            expand: false,
            initialChildSize: _minExtent,
            minChildSize: _minExtent,
            maxChildSize: maxExtent,
            snap: true,
            snapSizes: const [_initialExtent],
            shouldCloseOnMinExtent: false,
            builder: (context, scrollController) => PrimaryScrollController(
              controller: scrollController,
              child: FeedCommentSheet(
                post: widget.post,
                sheetScrollController: scrollController,
                onClose: _requestClose,
                onCloseAndWait: _requestCloseAndWait,
                sessionStore: widget.sessionStore,
                viewerIdentityListenable: widget.viewerIdentityListenable,
              ),
            ),
          ),
      ],
    );
  }
}

/// Comment sheet style Instagram Reels — 1:1 visual:
///
/// Layout:
/// - Drag handle bar di atas (sudah expose [onDragUpdate]/[onDragEnd]
///   untuk feed_screen.dart untuk drive video shrink + dismiss gesture)
/// - Minimal top chrome: drag handle only, so the drawer feels like Reels
///   instead of a heavy modal header.
/// - List komentar:
///   * Parent: avatar + name + content + meta (waktu, like, balas)
///   * Reply: indented 44px, smaller avatar, sama meta
/// - Bottom input bar:
///   * Reply banner ("Membalas @username • Batal") kalau lagi reply mode
///   * Avatar user current + TextField + send button
///
/// API:
/// - GET /api/feed/posts/:postId/comments?cursor= → list newest-first
/// - POST /api/feed/posts/:postId/comments → {content, parentCommentId?}
/// - POST/DELETE /api/feed/comments/:commentId/like → toggle like
class FeedCommentSheet extends StatefulWidget {
  /// Height factor default saat sheet pertama buka — match Shorts/Reels:
  /// cukup tinggi untuk composer + list, tapi video tetap terlihat jelas.
  static const double reelsHeightFactor = feedCommentInitialExtent;

  final FeedPost post;
  final bool applyKeyboardInset;
  final ScrollController? sheetScrollController;
  final VoidCallback? onClose;
  final Future<void> Function()? onCloseAndWait;

  /// Drag handle area gesture — diteruskan ke feed_screen untuk
  /// dismiss saat user drag handle ke bawah.
  final ValueChanged<DragUpdateDetails>? onDragUpdate;
  final ValueChanged<DragEndDetails>? onDragEnd;
  final FeedCommentSessionStore? sessionStore;
  final ValueListenable<FeedCommentViewerIdentity>? viewerIdentityListenable;

  const FeedCommentSheet({
    super.key,
    required this.post,
    this.applyKeyboardInset = true,
    this.sheetScrollController,
    this.onClose,
    this.onCloseAndWait,
    this.onDragUpdate,
    this.onDragEnd,
    this.sessionStore,
    this.viewerIdentityListenable,
  });

  @override
  State<FeedCommentSheet> createState() => _FeedCommentSheetState();
}

class _FeedCommentSheetState extends State<FeedCommentSheet> {
  static const int _replyBatchSize = 3;

  late final TextEditingController _inputCtrl;
  final FocusNode _inputFocus = FocusNode();
  late final MentionPickerController _mentionCtrl =
      MentionPickerController(textController: _inputCtrl);

  List<FeedComment> _comments = const [];
  String? _nextCursor;
  bool _loading = true;
  bool _loadingMore = false;
  bool _posting = false;
  String? _error;

  /// Reply mode — kalau diisi, comment yang sedang dipost akan jadi
  /// reply ke comment ini.
  FeedComment? _replyTarget;

  /// Jumlah balasan terbaru yang sedang terlihat per parent. Tidak ada entry
  /// berarti thread collapsed, seperti Reels.
  final Map<String, int> _visibleReplyCounts = {};
  late final FeedCommentSession _session;
  final Object _sessionWriter = Object();
  FeedCommentSyncLease? _syncLease;
  int _observedSessionRevision = 0;
  int _commentMutationRevision = 0;
  bool _hasLoadedComments = false;
  bool _refreshing = false;
  bool _restoreScrollPending = false;
  int _scrollRestoreAttempts = 0;
  late final FeedCommentViewerIdentity _boundViewerIdentity;
  late final Listenable _viewerIdentitySource;
  bool _sessionListenerAttached = false;
  bool _discardSessionState = false;
  bool _closingForViewerChange = false;
  bool _navigationPending = false;

  FeedCommentViewerIdentity get _currentViewerIdentity =>
      widget.viewerIdentityListenable?.value ??
      FeedCommentViewerIdentity(
        viewerId: memberStore.profile?.id ?? 'guest',
        generation: memberStore.viewerGeneration,
      );

  bool get _isBoundViewerCurrent {
    final current = _currentViewerIdentity;
    return !_discardSessionState &&
        current.viewerId == _boundViewerIdentity.viewerId &&
        current.generation == _boundViewerIdentity.generation;
  }

  Future<void> _requestCloseAndWait() async {
    final closeAndWait = widget.onCloseAndWait;
    if (closeAndWait != null) {
      await closeAndWait();
      return;
    }
    widget.onClose?.call();
    await WidgetsBinding.instance.endOfFrame;
  }

  Future<void> _navigateAfterClose(
    String routeName, {
    Object? arguments,
  }) async {
    if (_navigationPending) return;
    _navigationPending = true;
    final navigator = Navigator.of(context);
    await _requestCloseAndWait();
    if (!navigator.mounted) return;
    await navigator.pushNamed(routeName, arguments: arguments);
  }

  void _openAuthorProfile(FeedAuthor author) {
    if (!author.hasUsername) return;
    AppHaptics.tap();
    unawaited(_navigateAfterClose(
      '/u',
      arguments: author.username!.toLowerCase(),
    ));
  }

  void _openMentionProfile(String handle) {
    final normalized = handle.trim().replaceFirst('@', '').toLowerCase();
    if (normalized.isEmpty) return;
    AppHaptics.tap();
    unawaited(_navigateAfterClose('/u', arguments: normalized));
  }

  void _openLogin() {
    unawaited(_navigateAfterClose('/member/login'));
  }

  void _showMoreReplies(String parentId, int totalReplies) {
    AppHaptics.tap();
    setState(() {
      final current = _visibleReplyCounts[parentId] ?? 0;
      _visibleReplyCounts[parentId] =
          (current + _replyBatchSize).clamp(0, totalReplies);
    });
    _persistSession();
  }

  void _hideReplies(String parentId) {
    AppHaptics.tap();
    setState(() => _visibleReplyCounts.remove(parentId));
    _persistSession();
  }

  @override
  void initState() {
    super.initState();
    _boundViewerIdentity = _currentViewerIdentity;
    _viewerIdentitySource = widget.viewerIdentityListenable ?? memberStore;
    _viewerIdentitySource.addListener(_onViewerIdentityChanged);
    final viewerId = _boundViewerIdentity.viewerId;
    _session = (widget.sessionStore ?? feedCommentSessionStore).sessionFor(
      viewerId: viewerId,
      postId: widget.post.id,
    );
    _observedSessionRevision = _session.revision;
    _session.addListener(_onSessionContentChanged);
    _sessionListenerAttached = true;
    _syncLease = feedCommentSyncCoordinator.register(
      viewerId: viewerId,
      postId: widget.post.id,
      refresh: () => _loadInitial(showLoading: false),
    );
    _inputCtrl = TextEditingController(text: _session.draftText)
      ..addListener(_persistDraft);
    _comments = List<FeedComment>.from(_session.comments);
    _seedCommentInteractions(_comments);
    feedCommentInteractionStore.addListener(_onCommentLikeStateChanged);
    _nextCursor = _session.nextCursor;
    _replyTarget = _session.replyTarget;
    _visibleReplyCounts.addAll(_session.visibleReplyCounts);
    _loading = !_session.hasLoaded;
    _hasLoadedComments = _session.hasLoaded;
    _restoreScrollPending = _session.scrollOffset > 0;
    _loadInitial(showLoading: !_session.hasLoaded);
    widget.sheetScrollController?.addListener(_handleScroll);
    _scheduleScrollRestore();
    // Listen blockService — user block lewat sheet ini sendiri
    // → setState rebuild + filter di _buildDisplayItems otomatis hide
    // komentar dari blocked user. Tidak perlu fetch ulang dari server.
    blockService.addListener(_onBlocklistChanged);
    blockService.load();
  }

  @override
  void dispose() {
    feedCommentInteractionStore.removeListener(_onCommentLikeStateChanged);
    _viewerIdentitySource.removeListener(_onViewerIdentityChanged);
    if (!_discardSessionState) _persistSession();
    _syncLease?.dispose();
    if (_sessionListenerAttached) {
      _session.removeListener(_onSessionContentChanged);
    }
    widget.sheetScrollController?.removeListener(_handleScroll);
    blockService.removeListener(_onBlocklistChanged);
    _mentionCtrl.dispose();
    _inputCtrl
      ..removeListener(_persistDraft)
      ..dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _onBlocklistChanged() {
    if (mounted) setState(() {});
  }

  void _onCommentLikeStateChanged() {
    if (!mounted) return;
    // A global interaction may have settled while an older page request was
    // in flight. Invalidate that response so it cannot resurrect stale data.
    _commentMutationRevision++;
    setState(() {});
  }

  void _seedCommentInteractions(
    Iterable<FeedComment> comments, {
    bool authoritative = false,
  }) {
    for (final comment in comments) {
      feedCommentInteractionStore.seed(
        postId: widget.post.id,
        commentId: comment.id,
        liked: comment.viewerLiked,
        count: comment.likeCount,
        authoritative: authoritative,
      );
      _seedCommentInteractions(
        comment.replies,
        authoritative: authoritative,
      );
    }
  }

  FeedComment _withGlobalCommentLikeState(FeedComment comment) {
    final state =
        feedCommentInteractionStore.likeState(widget.post.id, comment.id);
    if (state == null) return comment;
    return comment.copyWith(viewerLiked: state.liked, likeCount: state.count);
  }

  void _persistDraft() {
    if (_discardSessionState) return;
    _session.draftText = _inputCtrl.text;
  }

  void _persistSession({
    bool publishComments = false,
    DateTime? syncedAt,
    Iterable<String> removedIds = const <String>[],
  }) {
    if (_discardSessionState) return;
    _session
      ..draftText = _inputCtrl.text
      ..replyTarget = _replyTarget
      ..replaceVisibleReplyCounts(_visibleReplyCounts);
    if (publishComments && _hasLoadedComments) {
      _session.replaceComments(
        _comments,
        _nextCursor,
        source: _sessionWriter,
        syncedAt: syncedAt,
        removedIds: removedIds,
      );
      _observedSessionRevision = _session.revision;
      _comments = List<FeedComment>.from(_session.comments);
    }
    final ctrl = widget.sheetScrollController;
    if (!_restoreScrollPending && ctrl != null && ctrl.hasClients) {
      _session.scrollOffset = ctrl.position.pixels;
    }
  }

  void _onSessionContentChanged() {
    final revision = _session.revision;
    if (revision == _observedSessionRevision) return;
    _observedSessionRevision = revision;
    if (identical(_session.lastWriter, _sessionWriter) || !mounted) return;

    // Any external session publication is newer than requests this drawer
    // already started. Invalidate those snapshots before adopting it.
    _commentMutationRevision++;

    final nextComments = mergeFeedCommentRefresh(
      current: _comments,
      incoming: _session.comments,
      preserveLocalLikeIds:
          feedCommentInteractionStore.pendingCommentIdsForPost(widget.post.id),
      reset: true,
    );
    _seedCommentInteractions(nextComments);
    setState(() {
      _comments = nextComments;
      _nextCursor = _session.nextCursor;
      _hasLoadedComments = _session.hasLoaded;
      _loading = false;
    });
    _clearReplyTargetIfMissing();
  }

  void _onViewerIdentityChanged() {
    final current = _currentViewerIdentity;
    if (current.viewerId == _boundViewerIdentity.viewerId &&
        current.generation == _boundViewerIdentity.generation) {
      return;
    }

    _discardSessionState = true;
    _syncLease?.dispose();
    _syncLease = null;
    if (_sessionListenerAttached) {
      _session.removeListener(_onSessionContentChanged);
      _sessionListenerAttached = false;
    }
    _inputCtrl
      ..removeListener(_persistDraft)
      ..clear();
    _session.reset();
    _replyTarget = null;
    _comments = const [];
    _visibleReplyCounts.clear();

    if (_closingForViewerChange) return;
    _closingForViewerChange = true;
    unawaited(_requestCloseAndWait());
  }

  void _scheduleScrollRestore() {
    if (!_restoreScrollPending) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_restoreScrollPending) return;
      final ctrl = widget.sheetScrollController;
      if (ctrl == null || !ctrl.hasClients) {
        if (_scrollRestoreAttempts++ < 3) _scheduleScrollRestore();
        return;
      }
      final maxOffset = ctrl.position.maxScrollExtent;
      if (maxOffset <= 0 && _session.scrollOffset > 0) {
        if (_scrollRestoreAttempts++ < 3) _scheduleScrollRestore();
        return;
      }
      ctrl.jumpTo(_session.scrollOffset.clamp(0, maxOffset).toDouble());
      _restoreScrollPending = false;
    });
  }

  void _handleScroll() {
    final ctrl = widget.sheetScrollController;
    if (ctrl == null || !ctrl.hasClients) return;
    if (!_restoreScrollPending) {
      _session.scrollOffset = ctrl.position.pixels;
    }
    // Trigger load-more saat scroll dekat bottom (200px buffer).
    if (ctrl.position.pixels >= ctrl.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadInitial({bool showLoading = true}) async {
    if (_refreshing) return;
    _refreshing = true;
    final fetchedAt = DateTime.now();
    final mutationRevision = _commentMutationRevision;
    final hadCachedPage = _hasLoadedComments && _comments.isNotEmpty;
    final cachedNextCursor = _nextCursor;
    if (showLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      _error = null;
    }
    try {
      final page = await feedService.fetchComments(
        widget.post.id,
        syncCursor: _hasLoadedComments ? _session.syncCursor : null,
      );
      if (!mounted || !_isBoundViewerCurrent) return;
      final canApplySnapshot = mutationRevision == _commentMutationRevision;
      final nextComments = canApplySnapshot
          ? mergeFeedCommentRefresh(
              current: _comments,
              incoming: page.items,
              removedIds: page.removedIds,
              preserveLocalLikeIds: feedCommentInteractionStore
                  .pendingCommentIdsForPost(widget.post.id),
              reset: page.syncResetRequired,
            )
          : mergeFeedCommentRefresh(
              current: _comments,
              incoming: const <FeedComment>[],
              removedIds: page.removedIds,
              preserveLocalLikeIds: feedCommentInteractionStore
                  .pendingCommentIdsForPost(widget.post.id),
            );
      _seedCommentInteractions(page.items, authoritative: true);
      _seedCommentInteractions(nextComments);
      setState(() {
        // Do not overwrite a comment/like/delete completed while a cached
        // session was being revalidated in the background.
        _comments = nextComments;
        if (canApplySnapshot) {
          // A cached cursor already points past every page currently shown.
          // A reset deliberately starts pagination again from the fresh head.
          _nextCursor = hadCachedPage && !page.syncResetRequired
              ? cachedNextCursor
              : page.nextCursor;
        }
        _loading = false;
      });
      _clearReplyTargetIfMissing();
      _hasLoadedComments = true;
      final syncedAt =
          canApplySnapshot ? page.syncCursor ?? page.syncTime : null;
      _persistSession(
        publishComments: true,
        syncedAt: syncedAt,
        removedIds: page.removedIds,
      );
      if (canApplySnapshot && page.commentCount != null) {
        final currentPost = feedStore.get(widget.post.id) ?? widget.post;
        feedStore.mergeFromServer(
          [currentPost.copyWith(commentCount: page.commentCount)],
          fetchedAt: fetchedAt,
        );
      }
      _scheduleScrollRestore();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _hasLoadedComments
            ? null
            : e.statusCode == 401
                ? 'Login untuk lihat komentar.'
                : 'Gagal memuat komentar. Tarik untuk coba lagi.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _hasLoadedComments
            ? null
            : 'Gagal memuat komentar. Tarik untuk coba lagi.';
      });
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _nextCursor == null) return;
    final fetchedAt = DateTime.now();
    final mutationRevision = _commentMutationRevision;
    setState(() => _loadingMore = true);
    try {
      final page = await feedService.fetchComments(
        widget.post.id,
        cursor: _nextCursor,
      );
      if (!mounted || !_isBoundViewerCurrent) return;
      if (mutationRevision != _commentMutationRevision) {
        // A comment/like/delete completed after this older page request
        // started. Do not resurrect its stale rows or advance pagination;
        // the next scroll attempt will request the same cursor again.
        setState(() => _loadingMore = false);
        return;
      }
      final currentWithoutTombstones = mergeFeedCommentRefresh(
        current: _comments,
        incoming: const <FeedComment>[],
        removedIds: page.removedIds,
        preserveLocalLikeIds: feedCommentInteractionStore
            .pendingCommentIdsForPost(widget.post.id),
      );
      final fetchedPage = mergeFeedCommentRefresh(
        current: const <FeedComment>[],
        incoming: page.items,
        removedIds: page.removedIds,
        preserveLocalLikeIds: feedCommentInteractionStore
            .pendingCommentIdsForPost(widget.post.id),
      );
      _seedCommentInteractions(currentWithoutTombstones);
      _seedCommentInteractions(fetchedPage, authoritative: true);
      setState(() {
        final existingIds =
            currentWithoutTombstones.map((item) => item.id).toSet();
        _comments = [
          ...currentWithoutTombstones,
          ...fetchedPage.where((item) => !existingIds.contains(item.id)),
        ];
        _nextCursor = page.nextCursor;
        _loadingMore = false;
      });
      _clearReplyTargetIfMissing();
      _persistSession(
        publishComments: true,
        removedIds: page.removedIds,
      );
      if (page.commentCount != null) {
        final currentPost = feedStore.get(widget.post.id) ?? widget.post;
        feedStore.mergeFromServer(
          [currentPost.copyWith(commentCount: page.commentCount)],
          fetchedAt: fetchedAt,
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _refresh() async {
    setState(() => _error = null);
    await _loadInitial();
  }

  void _setReplyTarget(FeedComment? target) {
    final nextDraft = preserveFeedReplyDraft(
      draft: _inputCtrl.text,
      previousTarget: _replyTarget,
      nextTarget: target,
    );
    setState(() => _replyTarget = target);
    if (target != null) {
      // Keep the existing draft and only replace the auto-inserted mention.
      if (_inputCtrl.text != nextDraft) {
        _inputCtrl.text = nextDraft;
        _inputCtrl.selection = TextSelection.fromPosition(
          TextPosition(offset: _inputCtrl.text.length),
        );
      }
      _inputFocus.requestFocus();
      AppHaptics.tap();
    } else if (_inputCtrl.text != nextDraft) {
      _inputCtrl.text = nextDraft;
      _inputCtrl.selection = TextSelection.fromPosition(
        TextPosition(offset: _inputCtrl.text.length),
      );
    }
    _persistSession();
  }

  void _clearReplyTargetIfMissing() {
    final target = _replyTarget;
    if (target == null || _findCommentById(target.id) != null) return;
    final nextDraft = preserveFeedReplyDraft(
      draft: _inputCtrl.text,
      previousTarget: target,
      nextTarget: null,
    );
    setState(() => _replyTarget = null);
    if (_inputCtrl.text != nextDraft) {
      _inputCtrl.text = nextDraft;
      _inputCtrl.selection = TextSelection.fromPosition(
        TextPosition(offset: nextDraft.length),
      );
    }
    _persistSession();
  }

  Future<void> _postComment() async {
    final raw = _inputCtrl.text.trim();
    if (raw.isEmpty || _posting) return;
    if (!memberStore.isLoggedIn) {
      _openLogin();
      return;
    }

    setState(() => _posting = true);
    AppHaptics.tap();

    try {
      final content = raw;
      final parentId = _replyTarget?.id;
      final result = await feedService.postComment(
        widget.post.id,
        content: content,
        parentCommentId: parentId,
      );
      if (!mounted || !_isBoundViewerCurrent) return;
      final created = result.comment;
      final effectiveParentId = created.parentCommentId ?? parentId;
      setState(() {
        if (effectiveParentId != null) {
          _comments = _comments.map((comment) {
            if (comment.id != effectiveParentId) return comment;
            final replies = [...comment.replies, created];
            return comment.copyWith(
              replies: replies,
              replyCount: replies.length,
            );
          }).toList();
          _visibleReplyCounts[effectiveParentId] = _replyBatchSize;
        } else {
          _comments = [created, ..._comments];
        }
        _posting = false;
        _replyTarget = null;
        _inputCtrl.clear();
      });
      _commentMutationRevision++;
      _persistSession(publishComments: true);
      final current = feedStore.get(widget.post.id)?.commentCount ??
          widget.post.commentCount;
      feedStore.setCommentCount(
        widget.post.id,
        result.commentCount ?? current + 1,
      );
      AppHaptics.success();
      _inputFocus.unfocus();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _posting = false);
      if (e.statusCode == 401) {
        _openLogin();
      } else {
        AppToast.show(
          context,
          e.message.isNotEmpty ? e.message : 'Komentar belum terkirim.',
          kind: ToastKind.warning,
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _posting = false);
      AppToast.show(
        context,
        'Komentar belum terkirim. Coba lagi.',
        kind: ToastKind.warning,
      );
    }
  }

  Future<void> _toggleLike(FeedComment comment) async {
    if (!memberStore.isLoggedIn) {
      _openLogin();
      return;
    }
    AppHaptics.tap();
    final cached = _findCommentById(comment.id) ?? comment;
    final current = _withGlobalCommentLikeState(cached);
    try {
      await feedCommentInteractionStore.toggle(
        postId: widget.post.id,
        commentId: current.id,
        currentlyLiked: current.viewerLiked,
        currentCount: current.likeCount,
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.statusCode == 401) {
        _openLogin();
      } else {
        AppToast.show(
          context,
          'Like belum berhasil.',
          kind: ToastKind.warning,
        );
      }
    } catch (_) {
      // Non-API errors keep the drawer's existing silent rollback behavior.
    }
  }

  FeedComment? _findCommentById(String commentId) {
    for (final comment in _comments) {
      if (comment.id == commentId) return comment;
      for (final reply in comment.replies) {
        if (reply.id == commentId) return reply;
      }
    }
    return null;
  }

  /// Delete komentar user sendiri. Optimistic remove dari local list,
  /// rollback kalau API gagal.
  ///
  /// Return Future<bool> ok status — true kalau sukses delete. Caller
  /// (moderation sheet) pakai untuk decide snackbar success vs error.
  Future<bool> _deleteComment(FeedComment comment) async {
    if (!mounted) return false;
    final removedCount = comment.parentCommentId == null
        ? 1 +
            (comment.replyCount > comment.replies.length
                ? comment.replyCount
                : comment.replies.length)
        : 1;
    // Snapshot untuk rollback kalau API gagal.
    final snapshot = List<FeedComment>.from(_comments);
    final replyTargetSnapshot = _replyTarget;
    final inputSnapshot = _inputCtrl.value;
    final visibleReplyCountsSnapshot =
        Map<String, int>.from(_visibleReplyCounts);
    final removal = removeFeedCommentFromThreads(_comments, comment);
    final removedReplyTarget =
        _replyTarget != null && removal.removedIds.contains(_replyTarget!.id);
    final retainedDraft = removedReplyTarget
        ? preserveFeedReplyDraft(
            draft: _inputCtrl.text,
            previousTarget: _replyTarget,
            nextTarget: null,
          )
        : null;
    setState(() {
      _comments = removal.comments;
      _visibleReplyCounts
          .removeWhere((parentId, _) => removal.removedIds.contains(parentId));
      if (removedReplyTarget) {
        _replyTarget = null;
      }
    });
    if (retainedDraft != null && _inputCtrl.text != retainedDraft) {
      _inputCtrl.text = retainedDraft;
      _inputCtrl.selection = TextSelection.collapsed(
        offset: retainedDraft.length,
      );
    }
    _commentMutationRevision++;
    _persistSession(publishComments: true);
    try {
      final result = await feedService.deleteComment(comment.id);
      // Sukses — comment beneran hilang. Sync comment count ke FeedStore
      // supaya Reels/Detail/grid yang baca count dari store auto-decrement.
      // Caller juga akan terima propagation via store listener.
      final fresh = feedStore.get(widget.post.id);
      final current = fresh?.commentCount ?? widget.post.commentCount;
      feedStore.setCommentCount(
        widget.post.id,
        result.commentCount ??
            (current > removedCount ? current - removedCount : 0),
      );
      return true;
    } catch (e) {
      // Rollback optimistic state.
      if (mounted && _isBoundViewerCurrent) {
        setState(() {
          _comments = snapshot;
          _replyTarget = replyTargetSnapshot;
          _visibleReplyCounts
            ..clear()
            ..addAll(visibleReplyCountsSnapshot);
          _inputCtrl.value = inputSnapshot;
        });
        _commentMutationRevision++;
        _persistSession(publishComments: true);
      }
      return false;
    }
  }

  /// Helper: cek apakah komentar ini dari user yang user current sudah
  /// block. Pakai blockService (local SharedPreferences). Match by
  /// userId primary, fallback ke displayHandle untuk legacy data.
  bool _isCommentBlocked(FeedComment comment) {
    if (!blockService.isLoaded || blockService.count == 0) return false;
    return blockService.isUserBlocked(
      userId: comment.author.id,
      userName: comment.author.displayHandle,
    );
  }

  /// Group comments: parents first (newest-first), each followed by
  /// chronological replies. Server bisa return flat — kita group sini.
  ///
  /// Resolve caption text untuk display di top of comment sheet (IG pattern).
  /// Fallback chain handle legacy posts:
  ///   1. `caption` field (reserved untuk future kalau backend kirim)
  ///   2. `description` field (current behavior — photo & video upload
  ///      sama-sama simpan caption di sini sejak v1.0.106 fix)
  ///   3. `title` field (fallback untuk legacy photo post pre-fix yang
  ///      caption malah ke-simpan di title bukan description)
  /// Skip placeholder "Postingan baru" — itu fallback default saat user
  /// tidak isi caption sama sekali, jangan render sebagai caption real.
  String _resolveCaption() {
    final rawCaption = widget.post.caption?.trim().isNotEmpty == true
        ? widget.post.caption!.trim()
        : widget.post.description.trim().isNotEmpty
            ? widget.post.description.trim()
            : widget.post.title.trim();
    return rawCaption == 'Postingan baru' ? '' : rawCaption;
  }

  /// Filter blocked users: skip komentar dari user yang current user
  /// sudah block (lokal SharedPreferences via blockService). Konsisten
  /// dengan feed_screen.dart pattern. Apply ke parent + replies.
  List<_CommentDisplayItem> _buildDisplayItems() {
    final items = <_CommentDisplayItem>[];
    for (final thread in groupFeedCommentThreads(_comments)) {
      if (_isCommentBlocked(thread.parent)) continue;
      items.add(_CommentDisplayItem.comment(thread.parent, isReply: false));

      final replies = thread.replies
          .where((reply) => !_isCommentBlocked(reply))
          .toList(growable: false);
      if (replies.isEmpty) continue;

      final requested = _visibleReplyCounts[thread.parent.id] ?? 0;
      final visibleCount = requested.clamp(0, replies.length);
      for (final reply in latestVisibleFeedReplies(replies, visibleCount)) {
        items.add(_CommentDisplayItem.comment(reply, isReply: true));
      }
      items.add(_CommentDisplayItem.repliesControl(
        parentId: thread.parent.id,
        totalReplies: replies.length,
        visibleReplies: visibleCount,
      ));
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = widget.applyKeyboardInset
        ? MediaQuery.viewInsetsOf(context).bottom
        : 0.0;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: Material(
        // Dark drawer Instagram Reels-style — bukan putih (user spec).
        // Background, header text, divider, input — semua flip ke variant
        // dark dengan white alpha variants untuk visual hierarchy.
        //
        // BUG FIX: SEBELUMNYA ada border: Border(top: BorderSide(white
        // alpha 0.08)) yang render 1px line subtle di tepi atas drawer.
        // Di TestFlight build, line ini visible sebagai "blur line"
        // mengganggu antara video terang di atas dan drawer gelap di
        // bawah. Removed — Instagram Reels TIDAK punya border line di
        // tepi atas drawer.
        color: const Color(0xFF101114),
        child: Column(
          children: [
            // ── Drag handle ──
            GestureDetector(
              key: const ValueKey('feed-comment-drag-handle'),
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: widget.onDragUpdate,
              onVerticalDragEnd: widget.onDragEnd,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                alignment: Alignment.center,
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
            ),

            // ── List comments ──
            Expanded(
              child: _buildListBody(),
            ),

            // ── Reply banner ──
            if (_replyTarget != null) _buildReplyBanner(),

            // ── Input bar ──
            _buildInputBar(keyboardInset),
          ],
        ),
      ),
    );
  }

  Widget _buildListBody() {
    if (_loading && _comments.isEmpty) {
      return const _CommentListSkeleton();
    }
    if (_error != null && _comments.isEmpty) {
      return NataloPawRefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          controller: widget.sheetScrollController,
          padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 32),
          children: [
            Center(
              child: Column(
                children: [
                  Icon(
                    Icons.wifi_off_rounded,
                    color: Colors.white.withValues(alpha: 0.35),
                    size: 40,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    // IG pattern — Compute caption SEBELUM check _comments.isEmpty supaya
    // caption tetap muncul di atas walau no comments yet. Sebelumnya bug:
    // kalau comments kosong, early-return empty state → caption tile gak
    // pernah render. Akibatnya post tanpa comment kelihatan caption-less
    // (padahal di main feed UI caption muncul).
    final emptyCaptionText = _resolveCaption();
    if (_comments.isEmpty) {
      return ListView(
        controller: widget.sheetScrollController,
        padding: EdgeInsets.zero,
        children: [
          if (emptyCaptionText.isNotEmpty)
            _CaptionTile(
              post: widget.post,
              captionText: emptyCaptionText,
              onAuthorTap: _openAuthorProfile,
              onMentionTap: _openMentionProfile,
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 50, horizontal: 32),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.mode_comment_outlined,
                    color: Colors.white.withValues(alpha: 0.35),
                    size: 40,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Belum ada komentar',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Jadi yang pertama berkomentar!',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    final items = _buildDisplayItems();
    // IG pattern — caption post di-render sebagai item pertama di atas
    // comment list (dengan author tag "creator"). User langsung baca
    // caption tanpa tutup sheet & balik ke feed.
    // Logic moved ke _resolveCaption() helper supaya bisa reuse di
    // empty-state branch di atas (sebelum populated-state).
    final captionText = _resolveCaption();
    final hasCaption = captionText.isNotEmpty;
    final captionOffset = hasCaption ? 1 : 0;
    final totalCount = items.length + captionOffset + (_loadingMore ? 1 : 0);

    return NataloPawRefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        controller: widget.sheetScrollController,
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: totalCount,
        itemBuilder: (context, index) {
          // Caption header — index 0 kalau hasCaption.
          if (hasCaption && index == 0) {
            return _CaptionTile(
              post: widget.post,
              captionText: captionText,
              onAuthorTap: _openAuthorProfile,
              onMentionTap: _openMentionProfile,
            );
          }
          final adjustedIndex = index - captionOffset;
          if (adjustedIndex >= items.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: NataloColors.primary,
                  ),
                ),
              ),
            );
          }
          final item = items[adjustedIndex];
          if (item.kind == _CommentDisplayItemKind.repliesControl) {
            return _RepliesControl(
              totalReplies: item.totalReplies,
              visibleReplies: item.visibleReplies,
              onShowMore: () => _showMoreReplies(
                item.parentId!,
                item.totalReplies,
              ),
              onHide: item.visibleReplies > 0
                  ? () => _hideReplies(item.parentId!)
                  : null,
            );
          }
          final comment = _withGlobalCommentLikeState(item.comment!);
          // canDelete = current user adalah author komentar. Drives
          // tampilan "Hapus" di moderation sheet (vs Laporkan/Blokir
          // untuk komentar orang lain).
          final currentUserId = memberStore.profile?.id;
          final isOwn =
              currentUserId != null && currentUserId == comment.author.id;
          return _CommentTile(
            comment: comment,
            isReply: item.isReply,
            onLike: () => _toggleLike(comment),
            onReply: () => _setReplyTarget(comment),
            onAuthorTap: _openAuthorProfile,
            onMentionTap: _openMentionProfile,
            canDelete: isOwn,
            onDelete: isOwn ? () => _deleteComment(comment) : null,
          );
        },
      ),
    );
  }

  Widget _buildReplyBanner() {
    final target = _replyTarget!;
    final name = target.author.isOfficialAccount
        ? target.author.displayName
        : target.author.username ?? target.author.displayName;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
      decoration: BoxDecoration(
        // Reply banner di atas composer — slightly lighter than drawer
        // bg untuk kasih hint "ini area different state".
        color: Colors.white.withValues(alpha: 0.05),
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Membalas @$name',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => _setReplyTarget(null),
            icon: Icon(
              Icons.close_rounded,
              size: 18,
              color: Colors.white.withValues(alpha: 0.65),
            ),
            tooltip: 'Batal balas',
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar(double keyboardInset) {
    final profile = memberStore.profile;
    final initial = (profile?.name.isNotEmpty ?? false)
        ? profile!.name.substring(0, 1).toUpperCase()
        : 'N';
    final isLoggedIn = memberStore.isLoggedIn;
    final bottomSafeArea = MediaQuery.viewPaddingOf(context).bottom;
    final bottomPadding = keyboardInset > 0
        ? 10 + keyboardInset
        : 18 + (bottomSafeArea > 0 ? bottomSafeArea : 16.0);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF101114),
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 0.5,
          ),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        12,
        10,
        8,
        bottomPadding,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // @mention autocomplete panel — render above input row. Auto-
          // show saat user ketik `@partial`, hide saat exit mention mode
          // atau cancel.
          MentionSuggestionsPanel(
            controller: _mentionCtrl,
            darkTheme: true,
            maxHeight: 220,
          ),
          _buildInputRow(profile, initial, isLoggedIn),
        ],
      ),
    );
  }

  Widget _buildInputRow(dynamic profile, String initial, bool isLoggedIn) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Avatar user current — pakai foto profil kalau ada,
        // fallback ke initial bubble. Re-use _CommentAvatar yang
        // sudah handle Image.network + errorBuilder fallback ke
        // initial supaya konsisten dengan avatar di comment list.
        // isOfficial: akun admin login = brand "Natalo Petshop" →
        // _CommentAvatar render OfficialBrandAvatar (logo NL), konsisten
        // dgn comment tile + creator overlay (server null-kan foto asli).
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: ProfileAvatar(
            size: 34,
            fontSize: 14,
            initial: initial,
            imageUrl: profile?.profilePhotoUrl,
            isOfficial: profile?.isAdmin ?? false,
            plain: true,
          ),
        ),
        const SizedBox(width: 10),

        // Input field — dark transparent fill, white text + cursor.
        Expanded(
          child: Container(
            constraints: const BoxConstraints(
              minHeight: 40,
              maxHeight: 120,
            ),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.10),
              ),
            ),
            child: TextField(
              controller: _inputCtrl,
              focusNode: _inputFocus,
              enabled: !_posting,
              maxLines: null,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.newline,
              keyboardAppearance: Brightness.dark,
              cursorColor: Colors.white,
              inputFormatters: [
                LengthLimitingTextInputFormatter(500),
              ],
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                height: 1.35,
              ),
              decoration: InputDecoration(
                isDense: true,
                // BUG FIX: global app theme set `filled: true` +
                // `fillColor: white surface`, yang override styling
                // wrapping Container. Hasil: input field tampil
                // solid white pill di dark drawer (bukan dark
                // transparent). Explicit `filled: false` + transparent
                // fillColor supaya theme global tidak bocor masuk.
                filled: false,
                fillColor: Colors.transparent,
                hintText: isLoggedIn
                    ? 'Tambahkan komentar...'
                    : 'Login untuk komentar...',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 14,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 9,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
              ),
              onChanged: (_) => setState(() {}),
              onTap: () {
                if (!isLoggedIn) {
                  _openLogin();
                }
              },
            ),
          ),
        ),

        // Send button (disabled saat kosong / posting).
        _SendButton(
          enabled: !_posting && _inputCtrl.text.trim().isNotEmpty,
          posting: _posting,
          onPressed: _postComment,
        ),
      ],
    );
  }
}

enum _CommentDisplayItemKind { comment, repliesControl }

/// Item wrapper untuk comment row atau kontrol thread ringkas.
class _CommentDisplayItem {
  final _CommentDisplayItemKind kind;
  final FeedComment? comment;
  final bool isReply;
  final String? parentId;
  final int totalReplies;
  final int visibleReplies;

  const _CommentDisplayItem._({
    required this.kind,
    this.comment,
    this.isReply = false,
    this.parentId,
    this.totalReplies = 0,
    this.visibleReplies = 0,
  });

  factory _CommentDisplayItem.comment(
    FeedComment comment, {
    required bool isReply,
  }) =>
      _CommentDisplayItem._(
        kind: _CommentDisplayItemKind.comment,
        comment: comment,
        isReply: isReply,
      );

  factory _CommentDisplayItem.repliesControl({
    required String parentId,
    required int totalReplies,
    required int visibleReplies,
  }) =>
      _CommentDisplayItem._(
        kind: _CommentDisplayItemKind.repliesControl,
        parentId: parentId,
        totalReplies: totalReplies,
        visibleReplies: visibleReplies,
      );
}

class _RepliesControl extends StatelessWidget {
  final int totalReplies;
  final int visibleReplies;
  final VoidCallback onShowMore;
  final VoidCallback? onHide;

  const _RepliesControl({
    required this.totalReplies,
    required this.visibleReplies,
    required this.onShowMore,
    this.onHide,
  });

  @override
  Widget build(BuildContext context) {
    final remaining = totalReplies - visibleReplies;
    final showMoreLabel = visibleReplies == 0
        ? 'Lihat $totalReplies balasan'
        : 'Lihat $remaining balasan lainnya';
    return Padding(
      padding: const EdgeInsets.fromLTRB(64, 2, 16, 6),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 1,
            margin: const EdgeInsets.only(right: 8),
            color: Colors.white.withValues(alpha: 0.30),
          ),
          if (remaining > 0)
            Flexible(
              child: InkWell(
                onTap: onShowMore,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    showMoreLabel,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.62),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          if (onHide != null) ...[
            if (remaining > 0) const Spacer(),
            TextButton(
              onPressed: onHide,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white.withValues(alpha: 0.62),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text(
                'Sembunyikan',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Caption header — render post caption sebagai "first comment" di top
/// comment sheet. Match IG pattern: user buka comment → langsung lihat
/// caption + author di atas sebelum komentar lain.
///
/// Visual: similar ke _CommentTile (avatar + name + body) tapi tanpa
/// like/reply button (caption bukan comment). Author
/// name dapat verified badge kalau admin/official, plus subtle separator
/// di bawah untuk visual hint "caption end, comments start".
class _CaptionTile extends StatelessWidget {
  final FeedPost post;
  final String captionText;
  final ValueChanged<FeedAuthor> onAuthorTap;
  final ValueChanged<String> onMentionTap;

  const _CaptionTile({
    required this.post,
    required this.captionText,
    required this.onAuthorTap,
    required this.onMentionTap,
  });

  @override
  Widget build(BuildContext context) {
    final author = post.author;
    // Display = @username kalau set, fallback name. Official account
    // pakai brand name "Natalo Petshop" (skip @).
    final name = author.displayHandle;
    final avatarUrl = author.profilePhotoUrl ?? author.avatarUrl;
    // Initial avatar fallback — pakai `name` raw (bukan @username) supaya
    // huruf inisialnya tetap konsisten antara fresh user (belum set
    // username) vs sudah set. Strip @ kalau ada di display.
    final fallbackForInitial = author.name.isNotEmpty ? author.name : name;
    final initial = fallbackForInitial.isNotEmpty
        ? fallbackForInitial.substring(0, 1).toUpperCase()
        : 'N';

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 0.5,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 7, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AuthorTapTarget(
              author: author,
              onTap: onAuthorTap,
              child: ProfileAvatar(
                size: 36,
                fontSize: 14,
                initial: initial,
                imageUrl: avatarUrl,
                isOfficial: author.isOfficialAccount,
                plain: true,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AuthorTapTarget(
                    author: author,
                    onTap: onAuthorTap,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              // Official → emas identitas (latar komentar
                              // gelap); user biasa putih.
                              color: author.isOfficialAccount
                                  ? NataloColors.officialGold
                                  : Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                        if (author.isOfficialAccount) ...[
                          const SizedBox(width: 4),
                          const OfficialVerifiedBadge(size: 13),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 3),
                  MentionText(
                    captionText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                    ),
                    mentionStyle: const TextStyle(
                      color: Color(0xFF60A5FA),
                      fontSize: 13.5,
                      height: 1.35,
                      fontWeight: FontWeight.w800,
                    ),
                    onMentionTap: onMentionTap,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _timeAgo(post.createdAt),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Single comment row — avatar + name + content + meta + like button.
class _CommentTile extends StatelessWidget {
  final FeedComment comment;
  final bool isReply;
  final VoidCallback onLike;
  final VoidCallback onReply;
  final ValueChanged<FeedAuthor> onAuthorTap;
  final ValueChanged<String> onMentionTap;

  /// Callback delete dari parent — return Future<bool> ok/fail.
  /// Parent yang panggil feedService.deleteComment + optimistic remove
  /// dari local state. Nullable supaya guest user / non-owner tidak
  /// crash.
  final Future<bool> Function()? onDelete;

  /// True kalau current user adalah author komentar ini. Drives lock
  /// untuk "Hapus" action di moderation sheet.
  final bool canDelete;

  const _CommentTile({
    required this.comment,
    required this.isReply,
    required this.onLike,
    required this.onReply,
    required this.onAuthorTap,
    required this.onMentionTap,
    this.onDelete,
    this.canDelete = false,
  });

  @override
  Widget build(BuildContext context) {
    final author = comment.author;
    // Display = @username kalau set, fallback nama. Official account =
    // "Natalo Petshop" brand (skip @). Konsisten dengan post header.
    final name = author.displayHandle;
    final avatarUrl = author.profilePhotoUrl ?? author.avatarUrl;
    // Avatar initial pakai `name` raw biar tetap konsisten antara user
    // belum set username vs sudah set (jangan pakai @ sebagai initial).
    final fallbackForInitial = author.name.isNotEmpty ? author.name : name;
    final initial = fallbackForInitial.isNotEmpty
        ? fallbackForInitial.substring(0, 1).toUpperCase()
        : 'N';
    final avatarSize = isReply ? 28.0 : 36.0;

    return GestureDetector(
      // UGC moderation — long-press buka Report/Block sheet untuk comment
      // ini. Long-press dipilih (bukan dedicated button) karena comment
      // tile dense + horizontal space tight, dan pattern long-press
      // familiar dari IG/Threads/Twitter untuk action menu.
      // Google Play UGC policy requirement: setiap UGC harus ada cara
      // user laporkan + blokir author.
      behavior: HitTestBehavior.opaque,
      onLongPress: () {
        // Hide block/report option kalau ini komen sendiri (canDelete).
        // Tampilkan "Hapus" instead. Cegah self-report / self-block yang
        // gak masuk akal.
        showModerationActions(
          context,
          targetKind: ReportTargetKind.feedComment,
          targetId: comment.id,
          authorId: author.id,
          authorName: canDelete ? null : name,
          allowBlock: !canDelete,
          allowSelfDelete: canDelete,
          onSelfDelete: canDelete && onDelete != null ? onDelete : null,
          useFeedStyle: true,
        );
      },
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          isReply ? 64 : 20,
          7,
          16,
          7,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AuthorTapTarget(
              author: author,
              onTap: onAuthorTap,
              child: ProfileAvatar(
                size: avatarSize,
                fontSize: isReply ? 12 : 14,
                initial: initial,
                imageUrl: avatarUrl,
                isOfficial: author.isOfficialAccount,
                plain: true,
              ),
            ),
            const SizedBox(width: 10),

            // Body: name + content + meta.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: _AuthorTapTarget(
                          author: author,
                          onTap: onAuthorTap,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    // Official → emas identitas; user biasa
                                    // putih (dark drawer).
                                    color: author.isOfficialAccount
                                        ? NataloColors.officialGold
                                        : Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ),
                              if (author.isOfficialAccount) ...[
                                const SizedBox(width: 4),
                                const OfficialVerifiedBadge(size: 13),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _timeAgo(comment.createdAt),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontWeight: FontWeight.w600,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  MentionText(
                    comment.content,
                    // Brand-override mention admin → "@Natalo Petshop" + badge.
                    officialHandles: comment.officialMentions.toSet(),
                    style: TextStyle(
                      // White alpha 90% — primary content content readable
                      // di dark bg, slightly softer dari 100% white untuk
                      // mengurangi eye strain di long scroll.
                      color: Colors.white.withValues(alpha: 0.90),
                      fontSize: 13.5,
                      height: 1.35,
                    ),
                    // @username di komentar pakai biru terang supaya
                    // pop di dark bg. Bold + tappable → /u/<handle>.
                    mentionStyle: const TextStyle(
                      color: Color(0xFF60A5FA),
                      fontSize: 13.5,
                      height: 1.35,
                      fontWeight: FontWeight.w800,
                    ),
                    onMentionTap: onMentionTap,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (comment.likeCount > 0) ...[
                        Text(
                          '${_formatCount(comment.likeCount)} suka',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontWeight: FontWeight.w700,
                            fontSize: 11.5,
                          ),
                        ),
                        const SizedBox(width: 14),
                      ],
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onReply,
                        child: Text(
                          'Balas',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.70),
                            fontWeight: FontWeight.w800,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Like heart.
            _CommentLikeButton(
              liked: comment.viewerLiked,
              onTap: onLike,
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthorTapTarget extends StatelessWidget {
  final FeedAuthor author;
  final Widget child;
  final ValueChanged<FeedAuthor> onTap;

  const _AuthorTapTarget({
    required this.author,
    required this.child,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (!author.hasUsername) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onTap(author),
      child: Semantics(
        button: true,
        label: 'Buka profil ${author.displayHandle}',
        child: child,
      ),
    );
  }
}

/// Heart icon kanan-bottom row comment — toggle dengan scale-bounce.
class _CommentLikeButton extends StatefulWidget {
  final bool liked;
  final VoidCallback onTap;

  const _CommentLikeButton({required this.liked, required this.onTap});

  @override
  State<_CommentLikeButton> createState() => _CommentLikeButtonState();
}

class _CommentLikeButtonState extends State<_CommentLikeButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounceCtrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _bounceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.3).chain(
          CurveTween(curve: Curves.easeOutCubic),
        ),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.3, end: 1.0).chain(
          CurveTween(curve: Curves.easeInOutCubic),
        ),
        weight: 60,
      ),
    ]).animate(_bounceCtrl);
  }

  @override
  void didUpdateWidget(covariant _CommentLikeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.liked != widget.liked && widget.liked) {
      _bounceCtrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _bounceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: Padding(
        padding: const EdgeInsets.only(left: 8, top: 4),
        child: ScaleTransition(
          scale: _scale,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            transitionBuilder: (child, anim) =>
                ScaleTransition(scale: anim, child: child),
            child: Icon(
              widget.liked
                  ? Icons.favorite_rounded
                  : Icons.favorite_outline_rounded,
              key: ValueKey(widget.liked),
              color: widget.liked
                  ? const Color(0xFFEF4444)
                  // Outline heart pakai white alpha 60% — readable di
                  // dark drawer (was 0xFF8E939B gray = too dim).
                  : Colors.white.withValues(alpha: 0.60),
              size: 18,
            ),
          ),
        ),
      ),
    );
  }
}

/// Send button — paper plane icon, biru saat enabled, gray saat empty.
/// Spinning saat posting.
class _SendButton extends StatelessWidget {
  final bool enabled;
  final bool posting;
  final VoidCallback onPressed;

  const _SendButton({
    required this.enabled,
    required this.posting,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    if (posting) {
      return const SizedBox(
        width: 44,
        height: 38,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: NataloColors.primary,
            ),
          ),
        ),
      );
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 44,
          height: 38,
          child: Icon(
            Icons.send_rounded,
            color: enabled
                ? NataloColors.primary
                // Disabled state pakai white alpha 30% — visible di dark
                // bg tapi clearly "inactive" (was 0xFFC4C8CF light gray =
                // hilang di dark drawer).
                : Colors.white.withValues(alpha: 0.30),
            size: 22,
          ),
        ),
      ),
    );
  }
}

/// Skeleton loading state — 5 comment placeholder rows dengan shimmer.
class _CommentListSkeleton extends StatelessWidget {
  const _CommentListSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: List.generate(
        5,
        (i) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 16, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 10,
                      width: 100,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 10,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 10,
                      width: 180,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Format waktu relative ringkas (Instagram-style): "5d", "3j", "2h",
/// "1mg", "5bln", "1th". Bahasa Indonesia singkat.
String _timeAgo(DateTime created) {
  final now = DateTime.now();
  final diff = now.difference(created);
  if (diff.inSeconds < 60) return 'baru';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}j';
  if (diff.inDays < 7) return '${diff.inDays}h';
  if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}mg';
  if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}bln';
  return '${(diff.inDays / 365).floor()}th';
}

String _formatCount(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}jt';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}rb';
  return '$n';
}

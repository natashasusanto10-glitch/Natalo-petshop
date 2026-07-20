import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/transition/post_detail_transition_session.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:video_player/video_player.dart';

void main() {
  group('PostDetailTransitionSession', () {
    test('owns synchronous opening state and attaches only one route', () {
      final source = FakeTransitionSource();
      final a = fakePost('a');
      source.targets['a'] = fakeTarget('a');

      final session = PostDetailTransitionSession(
        initialPost: a,
        source: source,
      );

      expect(session.activePost, same(a));
      expect(session.loadedPosts, [a]);
      expect(session.openingTarget?.postId, 'a');
      expect(session.preparedTarget, isNull);
      expect(
        session.destinationReadiness,
        PostDetailDestinationReadiness.preparing,
      );
      expect(session.isFrozen, isFalse);
      expect(session.playbackAllowed, isFalse);
      expect(session.routeAttached, isFalse);
      expect(session.tryAttachRoute(), isTrue);
      expect(session.tryAttachRoute(), isFalse);
      expect(session.routeAttached, isTrue);

      session.detachRoute();
      session.detachRoute();
      expect(session.routeAttached, isFalse);
      expect(session.tryAttachRoute(), isTrue);

      session.dispose();
    });

    test('freeze never substitutes opening A after active B is selected', () {
      final source = FakeTransitionSource();
      final a = fakePost('a');
      final b = fakePost('b');
      source.targets['a'] = fakeTarget('a');
      final session = PostDetailTransitionSession(
        initialPost: a,
        source: source,
      );

      session.reportActivePost(b);
      final frozen = session.freeze();

      expect(frozen.post.id, 'b');
      expect(frozen.target, isNull);
      expect(frozen.usesFallback, isTrue);
      session.dispose();
    });

    test('late A preparation cannot replace prepared B', () async {
      final source = FakeTransitionSource();
      final a = fakePost('a');
      final b = fakePost('b');
      final aCompleter = Completer<PostPageSourceTarget?>();
      final bCompleter = Completer<PostPageSourceTarget?>()
        ..complete(fakeTarget('b'));
      source.preparations
        ..['a'] = aCompleter
        ..['b'] = bCompleter;
      final session = PostDetailTransitionSession(
        initialPost: a,
        source: source,
      );

      final stale = session.prepareActiveTarget();
      session.reportActivePost(b);
      await session.prepareActiveTarget();
      aCompleter.complete(fakeTarget('a'));
      await stale;

      expect(session.preparedTarget?.postId, 'b');
      session.dispose();
      expect(source.restoredIds, containsAll(<String>['a', 'b']));
    });

    test(
      'latest null preparation clears prepared B and notifies once',
      () async {
        final source = FakeTransitionSource();
        final preparedProxy = TrackingMediaProxy();
        source.preparations['b'] = Completer<PostPageSourceTarget?>()
          ..complete(fakeTarget('b', proxy: preparedProxy));
        final session = PostDetailTransitionSession(
          initialPost: fakePost('a'),
          source: source,
        );
        session.reportActivePost(fakePost('b'));
        await session.prepareActiveTarget();
        var notifications = 0;
        session.addListener(() => notifications++);

        source.preparations['b'] = Completer<PostPageSourceTarget?>()
          ..complete(null);
        await session.prepareActiveTarget();

        expect(session.preparedTarget, isNull);
        expect(notifications, 1);
        expect(preparedProxy.ownedDisposeCount, 1);
        session.dispose();
      },
    );

    test(
      'latest wrong-post preparation clears prepared B and notifies once',
      () async {
        final source = FakeTransitionSource();
        final preparedProxy = TrackingMediaProxy();
        source.preparations['b'] = Completer<PostPageSourceTarget?>()
          ..complete(fakeTarget('b', proxy: preparedProxy));
        final session = PostDetailTransitionSession(
          initialPost: fakePost('a'),
          source: source,
        );
        session.reportActivePost(fakePost('b'));
        await session.prepareActiveTarget();
        var notifications = 0;
        session.addListener(() => notifications++);

        source.preparations['b'] = Completer<PostPageSourceTarget?>()
          ..complete(fakeTarget('a'));
        await session.prepareActiveTarget();

        expect(session.preparedTarget, isNull);
        expect(notifications, 1);
        expect(preparedProxy.ownedDisposeCount, 1);
        session.dispose();
      },
    );

    test('stale null preparation cannot clear a newer prepared B', () async {
      final source = FakeTransitionSource();
      final staleFailure = Completer<PostPageSourceTarget?>();
      final newerProxy = TrackingMediaProxy();
      source.prepareTargetOverride = (post, generation) {
        if (generation == 2) return staleFailure.future;
        return Future<PostPageSourceTarget?>.value(
          fakeTarget('b', proxy: newerProxy),
        );
      };
      final session = PostDetailTransitionSession(
        initialPost: fakePost('a'),
        source: source,
      );
      session.reportActivePost(fakePost('b'));
      var notifications = 0;
      session.addListener(() => notifications++);

      final stalePreparation = session.prepareActiveTarget();
      await session.prepareActiveTarget();
      staleFailure.complete(null);
      await stalePreparation;

      expect(session.preparedTarget?.postId, 'b');
      expect(notifications, 1);
      expect(newerProxy.ownedDisposeCount, 0);
      session.dispose();
      expect(newerProxy.ownedDisposeCount, 1);
    });

    test(
      'source-unmounted preparation clears prepared B and notifies once',
      () async {
        final source = FakeTransitionSource();
        final preparedProxy = TrackingMediaProxy();
        source.preparations['b'] = Completer<PostPageSourceTarget?>()
          ..complete(fakeTarget('b', proxy: preparedProxy));
        final session = PostDetailTransitionSession(
          initialPost: fakePost('a'),
          source: source,
        );
        session.reportActivePost(fakePost('b'));
        await session.prepareActiveTarget();
        var notifications = 0;
        session.addListener(() => notifications++);

        source.mounted = false;
        await session.prepareActiveTarget();

        expect(session.preparedTarget, isNull);
        expect(notifications, 1);
        expect(preparedProxy.ownedDisposeCount, 1);
        session.dispose();
      },
    );

    test(
      'source-unmounted preparation does not notify without a target',
      () async {
        final source = FakeTransitionSource()..mounted = false;
        final session = PostDetailTransitionSession(
          initialPost: fakePost('a'),
          source: source,
        );
        var notifications = 0;
        session.addListener(() => notifications++);

        await session.prepareActiveTarget();

        expect(session.preparedTarget, isNull);
        expect(notifications, 0);
        session.dispose();
      },
    );

    test('page forwarding deduplicates locally and keeps loaded extent', () {
      final source = FakeTransitionSource();
      final session = PostDetailTransitionSession(
        initialPost: fakePost('a'),
        source: source,
      );
      final page = FeedPage(items: [fakePost('b')], nextCursor: 'c2');

      session.reportLoadedPage(page);
      session.reportLoadedPage(page);

      expect(source.pages, [page, page]);
      expect(session.loadedPosts.map((post) => post.id), ['a', 'b']);
      session.dispose();
    });

    test('same active post ID with refreshed data notifies exactly once', () {
      final source = FakeTransitionSource();
      final original = fakePost('a');
      final refreshed = original.copyWith(title: 'refreshed');
      final session = PostDetailTransitionSession(
        initialPost: original,
        source: source,
      );
      var notifications = 0;
      session.addListener(() => notifications++);

      session.reportActivePost(refreshed);

      expect(session.activePost, same(refreshed));
      expect(session.loadedPosts.single, same(refreshed));
      expect(notifications, 1);
      session.dispose();
    });

    test('reporting the identical active post object remains a no-op', () {
      final source = FakeTransitionSource();
      final original = fakePost('a');
      final session = PostDetailTransitionSession(
        initialPost: original,
        source: source,
      );
      var notifications = 0;
      session.addListener(() => notifications++);

      session.reportActivePost(original);

      expect(session.activePost, same(original));
      expect(session.loadedPosts.single, same(original));
      expect(notifications, 0);
      session.dispose();
    });

    test('freezing blocks retargeting until canceled back has settled', () {
      final source = FakeTransitionSource();
      final a = fakePost('a');
      final b = fakePost('b');
      final c = fakePost('c');
      final session = PostDetailTransitionSession(
        initialPost: a,
        source: source,
      );

      session.reportActivePost(b);
      final firstFrozen = session.freeze();
      session.reportActivePost(c);

      expect(session.activePost.id, 'b');
      expect(session.freeze(), same(firstFrozen));
      expect(session.isFrozen, isTrue);

      session.resumeTrackingAfterCanceledBack();
      expect(session.isFrozen, isFalse);
      session.reportActivePost(c);
      expect(session.activePost.id, 'c');
      session.dispose();
    });

    test(
      'invalidating B rejects its late target and still freezes B fallback',
      () async {
        final source = FakeTransitionSource();
        final a = fakePost('a');
        final b = fakePost('b');
        final bCompleter = Completer<PostPageSourceTarget?>();
        source.preparations['b'] = bCompleter;
        final session = PostDetailTransitionSession(
          initialPost: a,
          source: source,
        );

        session.reportActivePost(b);
        final preparation = session.prepareActiveTarget();
        session.invalidatePost('b');
        bCompleter.complete(fakeTarget('b'));
        await preparation;
        final frozen = session.freeze();

        expect(session.activePost.id, 'b');
        expect(session.preparedTarget, isNull);
        expect(frozen.post.id, 'b');
        expect(frozen.target, isNull);
        expect(frozen.usesFallback, isTrue);
        session.dispose();
      },
    );

    test('freeze rejects wrong-post and unusable prepared geometry', () async {
      final source = FakeTransitionSource();
      final b = fakePost('b');
      source.preparations['b'] = Completer<PostPageSourceTarget?>()
        ..complete(fakeTarget('a'));
      final session = PostDetailTransitionSession(
        initialPost: fakePost('a'),
        source: source,
      );

      session.reportActivePost(b);
      await session.prepareActiveTarget();
      expect(session.preparedTarget, isNull);

      source.preparations['b'] = Completer<PostPageSourceTarget?>()
        ..complete(fakeTarget('b', rect: Rect.zero));
      await session.prepareActiveTarget();
      final frozen = session.freeze();

      expect(session.preparedTarget?.postId, 'b');
      expect(frozen.target, isNull);
      expect(frozen.usesFallback, isTrue);
      session.dispose();
    });

    test(
      'cancel restores suppression and pending return stays source-owned',
      () async {
        final source = FakeTransitionSource();
        final b = fakePost('b');
        source.preparations['b'] = Completer<PostPageSourceTarget?>()
          ..complete(fakeTarget('b'));
        final session = PostDetailTransitionSession(
          initialPost: fakePost('a'),
          source: source,
        );
        session.reportActivePost(b);
        await session.prepareActiveTarget();
        session.freeze();

        session.setFrozenTileSuppressed(true);
        session.setFrozenTileSuppressed(true);
        session.assignPendingReturnTarget();

        expect(source.suppressionCalls, [('b', true)]);
        expect(source.pendingReturnPostId, 'b');

        session.resumeTrackingAfterCanceledBack();
        session.resumeTrackingAfterCanceledBack();
        expect(source.suppressionCalls, [('b', true), ('b', false)]);

        session.dispose();
        expect(source.pendingReturnPostId, 'b');
      },
    );

    test('notifies only for effective readiness and playback changes', () {
      final session = PostDetailTransitionSession(
        initialPost: fakePost('a'),
        source: FakeTransitionSource(),
      );
      var notifications = 0;
      session.addListener(() => notifications++);

      session.markDestinationReady(PostDetailDestinationReadiness.preparing);
      session.setPlaybackAllowed(false);
      expect(notifications, 0);

      session.markDestinationReady(
        PostDetailDestinationReadiness.geometryReady,
      );
      session.setPlaybackAllowed(true);
      session.setPlaybackAllowed(true);

      expect(
        session.destinationReadiness,
        PostDetailDestinationReadiness.geometryReady,
      );
      expect(session.playbackAllowed, isTrue);
      expect(notifications, 2);
      session.dispose();
    });

    test('destination media slot/aspect start null; reporting sets both and '
        'notifies once; an identical report is a no-op; dispose guards '
        'further writes and resets both to null', () {
      final session = PostDetailTransitionSession(
        initialPost: fakePost('a'),
        source: FakeTransitionSource(),
      );
      expect(session.destinationMediaSlotRect, isNull);
      expect(session.destinationMediaAspect, isNull);

      var notifications = 0;
      session.addListener(() => notifications++);

      const rect = Rect.fromLTWH(0, 80, 400, 500);
      session.reportDestinationMediaSlot(rect: rect, mediaAspect: 4 / 5);
      expect(session.destinationMediaSlotRect, rect);
      expect(session.destinationMediaAspect, 4 / 5);
      expect(notifications, 1);

      // Compare-and-set: an identical report does not notify again.
      session.reportDestinationMediaSlot(rect: rect, mediaAspect: 4 / 5);
      expect(notifications, 1);

      const otherRect = Rect.fromLTWH(0, 0, 300, 400);
      session.reportDestinationMediaSlot(rect: otherRect, mediaAspect: 1);
      expect(session.destinationMediaSlotRect, otherRect);
      expect(session.destinationMediaAspect, 1);
      expect(notifications, 2);

      session.dispose();
      session.reportDestinationMediaSlot(rect: rect, mediaAspect: 4 / 5);
      expect(session.destinationMediaSlotRect, isNull);
      expect(session.destinationMediaAspect, isNull);
    });

    test('destination video controller starts null; reporting sets it and '
        'notifies once by identity; dispose guards further writes and resets '
        'it to null', () {
      final session = PostDetailTransitionSession(
        initialPost: fakePost('a'),
        source: FakeTransitionSource(),
      );
      expect(session.destinationVideoController, isNull);

      var notifications = 0;
      session.addListener(() => notifications++);

      final controller = VideoPlayerController.networkUrl(
        Uri.parse('https://example.com/a.mp4'),
      );
      session.reportDestinationVideoController(controller);
      expect(session.destinationVideoController, same(controller));
      expect(notifications, 1);

      // Compare-and-set: reporting the identical controller is a no-op.
      session.reportDestinationVideoController(controller);
      expect(notifications, 1);

      session.reportDestinationVideoController(null);
      expect(session.destinationVideoController, isNull);
      expect(notifications, 2);

      session.dispose();
      session.reportDestinationVideoController(controller);
      expect(session.destinationVideoController, isNull);
    });

    test(
      'disposes owned proxy clones once without disposing source proxies',
      () async {
        final source = FakeTransitionSource();
        final openingProxy = TrackingMediaProxy();
        final preparedProxy = TrackingMediaProxy();
        source.targets['a'] = fakeTarget('a', proxy: openingProxy);
        source.preparations['b'] = Completer<PostPageSourceTarget?>()
          ..complete(fakeTarget('b', proxy: preparedProxy));
        final session = PostDetailTransitionSession(
          initialPost: fakePost('a'),
          source: source,
        );
        session.reportActivePost(fakePost('b'));
        await session.prepareActiveTarget();
        session.freeze();

        session.dispose();
        session.dispose();

        expect(openingProxy.sourceDisposeCount, 0);
        expect(preparedProxy.sourceDisposeCount, 0);
        expect(openingProxy.ownedDisposeCount, 1);
        expect(preparedProxy.ownedDisposeCount, 1);
      },
    );

    test(
      'freeze after dispose throws without resolving or cloning a new proxy',
      () {
        final source = FakeTransitionSource();
        final openingProxy = TrackingMediaProxy();
        source.targets['a'] = fakeTarget('a', proxy: openingProxy);
        final session = PostDetailTransitionSession(
          initialPost: fakePost('a'),
          source: source,
        );
        final clonesBeforeDispose = openingProxy.cloneCount;
        final sourceCallsBeforeDispose = source.resolveProxyCalls;

        session.dispose();

        expect(session.freeze, throwsStateError);
        expect(openingProxy.cloneCount, clonesBeforeDispose);
        expect(source.resolveProxyCalls, sourceCallsBeforeDispose);
        expect(source.fallbackProxies, isEmpty);
        expect(openingProxy.ownedDisposeCount, clonesBeforeDispose);
      },
    );

    test(
      'freeze after disposing a frozen proxy throws instead of returning it',
      () {
        final source = FakeTransitionSource();
        final fallbackProxy = TrackingMediaProxy();
        source.fallbackProxies['a'] = fallbackProxy;
        final session = PostDetailTransitionSession(
          initialPost: fakePost('a'),
          source: source,
        );
        session.freeze();
        final clonesBeforeDispose = fallbackProxy.cloneCount;
        final sourceCallsBeforeDispose = source.resolveProxyCalls;

        session.dispose();

        expect(fallbackProxy.ownedDisposeCount, clonesBeforeDispose);
        expect(session.freeze, throwsStateError);
        expect(fallbackProxy.cloneCount, clonesBeforeDispose);
        expect(source.resolveProxyCalls, sourceCallsBeforeDispose);
        expect(fallbackProxy.ownedDisposeCount, clonesBeforeDispose);
      },
    );

    test('invalidating opening post releases its retained fallback proxy', () {
      final source = FakeTransitionSource();
      final fallbackProxy = TrackingMediaProxy();
      source.fallbackProxies['a'] = fallbackProxy;
      final session = PostDetailTransitionSession(
        initialPost: fakePost('a'),
        source: source,
      );

      session.invalidatePost('a');

      expect(fallbackProxy.ownedDisposeCount, 1);
      expect(fallbackProxy.sourceDisposeCount, 0);
      session.dispose();
      expect(fallbackProxy.ownedDisposeCount, 1);
    });
  });

  group('PostPageSourceTarget.hasUsableGeometry', () {
    test('accepts visible finite positive geometry', () {
      final target = fakeTarget('a');

      expect(target.hasUsableGeometry, isTrue);
    });

    test('rejects empty, non-finite, and offscreen geometry', () {
      expect(fakeTarget('a', rect: Rect.zero).hasUsableGeometry, isFalse);
      expect(
        fakeTarget(
          'a',
          rect: const Rect.fromLTWH(double.nan, 0, 10, 10),
        ).hasUsableGeometry,
        isFalse,
      );
      expect(
        fakeTarget(
          'a',
          rect: const Rect.fromLTWH(500, 500, 10, 10),
        ).hasUsableGeometry,
        isFalse,
      );
    });
  });
}

FeedPost fakePost(String id) => FeedPost(
  id: id,
  slug: id,
  videoUrl: 'https://example.com/$id.mp4',
  author: const FeedAuthor(id: 'author', name: 'Author'),
  createdAt: DateTime.utc(2026),
);

PostPageSourceTarget fakeTarget(
  String postId, {
  Rect rect = const Rect.fromLTWH(10, 20, 100, 120),
  PostPageMediaProxy? proxy,
}) => PostPageSourceTarget(
  postId: postId,
  rect: rect,
  proxy: proxy ?? TrackingMediaProxy(),
  viewportSize: const Size(400, 800),
  textDirection: TextDirection.ltr,
  layoutGeneration: 1,
);

class FakeTransitionSource implements PostDetailTransitionSourceAdapter {
  @override
  bool mounted = true;

  final Map<String, PostPageSourceTarget> targets = {};
  final Map<String, Completer<PostPageSourceTarget?>> preparations = {};
  final List<FeedPage> pages = [];
  final List<String> restoredIds = [];
  final List<(String, bool)> suppressionCalls = [];
  final Map<String, TrackingMediaProxy> fallbackProxies = {};
  Future<PostPageSourceTarget?> Function(FeedPost post, int generation)?
  prepareTargetOverride;
  String? pendingReturnPostId;
  int resolveProxyCalls = 0;

  @override
  void mergePage(FeedPage page) => pages.add(page);

  @override
  Future<PostPageSourceTarget?> prepareTarget(
    FeedPost post, {
    required int generation,
  }) async =>
      prepareTargetOverride?.call(post, generation) ??
      preparations[post.id]?.future ??
      targets[post.id];

  @override
  PostPageSourceTarget? resolveTarget(FeedPost post) => targets[post.id];

  @override
  PostPageMediaProxy resolveProxy(FeedPost post) {
    resolveProxyCalls++;
    return fallbackProxies.putIfAbsent(post.id, TrackingMediaProxy.new);
  }

  @override
  void setPendingReturnPostId(String? postId) {
    pendingReturnPostId = postId;
  }

  @override
  void setTileSuppressed(String postId, bool suppressed) {
    suppressionCalls.add((postId, suppressed));
    if (!suppressed) restoredIds.add(postId);
  }
}

class TrackingMediaProxy extends PostPageMediaProxy {
  TrackingMediaProxy({ProxyDisposalTracker? tracker, bool ownedClone = false})
    : _tracker = tracker ?? ProxyDisposalTracker(),
      _ownedClone = ownedClone,
      super(placeholderColor: const Color(0xFF123456));

  final ProxyDisposalTracker _tracker;
  final bool _ownedClone;

  int get sourceDisposeCount => _tracker.sourceDisposeCount;
  int get ownedDisposeCount => _tracker.ownedDisposeCount;
  int get cloneCount => _tracker.cloneCount;

  @override
  TrackingMediaProxy clone() {
    _tracker.cloneCount++;
    return TrackingMediaProxy(tracker: _tracker, ownedClone: true);
  }

  @override
  void dispose() {
    if (_ownedClone) {
      _tracker.ownedDisposeCount++;
    } else {
      _tracker.sourceDisposeCount++;
    }
  }
}

class ProxyDisposalTracker {
  int sourceDisposeCount = 0;
  int ownedDisposeCount = 0;
  int cloneCount = 0;
}

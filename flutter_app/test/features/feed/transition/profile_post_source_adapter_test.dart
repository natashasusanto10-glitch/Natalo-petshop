import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/transition/post_detail_transition_session.dart';
import 'package:natalo_petshop_flutter/features/feed/transition/post_transition_source_tile.dart';
import 'package:natalo_petshop_flutter/features/feed/transition/profile_post_source_adapter.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/widgets/profile_grid_geometry.dart';

void main() {
  group('ProfilePostSourceAdapter', () {
    test('resolveTarget caches the accepted snapshot and disposes the loser',
        () {
      final registry = _SpyRegistry();
      final adapter = _adapterOver(registry);

      final first = registry.nextTarget = _SpyTarget('a');
      adapter.resolveTarget(fakePost('a'));
      final second = registry.nextTarget = _SpyTarget('a');
      adapter.resolveTarget(fakePost('a'));

      expect(first.proxy.disposeCount, 1, reason: 'loser disposed once');
      expect(second.proxy.disposeCount, 0, reason: 'accepted snapshot kept');

      adapter.dispose();
      expect(second.proxy.disposeCount, 1);
    });

    test('prepareTarget rejects a snapshot relaid out during ensureVisible',
        () async {
      final registry = _SpyRegistry();
      late _SpyTarget resolved;
      final adapter = ProfilePostSourceAdapter(
        registry: registry,
        isMounted: () => true,
        currentScope: () => 'all',
        ensureVisible: (post, generation) async {
          // Tile is relaid out while we scroll toward it.
          registry.layoutGenerationValue++;
        },
        mergeScopedPage: (_) {},
        fallbackColor: (_) => const Color(0xFF000000),
      );
      registry.targetFactory = () => resolved = _SpyTarget(
            'a',
            layoutGeneration: registry.layoutGenerationValue,
          );

      final target = await adapter.prepareTarget(fakePost('a'), generation: 1);

      expect(target, isNull, reason: 'stale layout drives fallback');
      expect(resolved.proxy.disposeCount, 1, reason: 'stale snapshot disposed');
      adapter.dispose();
    });

    test('late old-generation prepare returns null without caching', () async {
      final registry = _SpyRegistry();
      final firstGate = Completer<void>();
      final resolvedTargets = <_SpyTarget>[];
      registry.targetFactory = () {
        final target = _SpyTarget('a');
        resolvedTargets.add(target);
        return target;
      };
      final adapter = ProfilePostSourceAdapter(
        registry: registry,
        isMounted: () => true,
        currentScope: () => 'all',
        ensureVisible: (post, generation) async {
          if (generation == 1) await firstGate.future;
        },
        mergeScopedPage: (_) {},
        fallbackColor: (_) => const Color(0xFF000000),
      );

      final stale = adapter.prepareTarget(fakePost('a'), generation: 1);
      final winner =
          await adapter.prepareTarget(fakePost('a'), generation: 2);
      firstGate.complete();
      final staleResult = await stale;

      expect(staleResult, isNull);
      expect(winner, isNotNull);
      // Two snapshots were resolved (one per prepare). The gen-2 prepare runs
      // to completion first (its ensureVisible does not await), so it resolves
      // and caches resolvedTargets[0]; the gated gen-1 prepare resolves
      // resolvedTargets[1] afterwards and, being stale, disposes it.
      final winnerTarget = resolvedTargets.first;
      final staleTarget = resolvedTargets.last;
      expect(staleTarget.proxy.disposeCount, 1);
      expect(winnerTarget.proxy.disposeCount, 0);
      adapter.dispose();
    });

    testWidgets('setTileSuppressed round-trips to the scoped registry tile',
        (tester) async {
      final registry = PostTransitionTileRegistry();
      const id = PostTransitionTileId(scope: 'all', postId: 'x');
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 100,
            height: 100,
            child: PostTransitionSourceTile(
              registry: registry,
              id: id,
              fallbackColor: const Color(0xFF334455),
              child: const ColoredBox(color: Color(0xFFFF0000)),
            ),
          ),
        ),
      );
      final adapter = _adapterOver(registry, scope: 'all');

      adapter.setTileSuppressed('x', true);
      await tester.pump();
      expect(
        tester
            .widget<Opacity>(
              find.byKey(const ValueKey('post-transition-tile-opacity-x')),
            )
            .opacity,
        0,
      );

      adapter.setTileSuppressed('x', false);
      await tester.pump();
      expect(
        tester
            .widget<Opacity>(
              find.byKey(const ValueKey('post-transition-tile-opacity-x')),
            )
            .opacity,
        1,
      );
      adapter.dispose();
    });

    test('pending return id is consumed once with a bounded scroll', () {
      final registry = _SpyRegistry();
      final adapter = _adapterOver(registry);
      const width = 360.0;

      adapter.setPendingReturnPostId('p5');
      expect(adapter.pendingReturnPostId, 'p5');

      final jumps = <double>[];
      adapter.consumePendingReturn(
        gridWidth: width,
        indexOfPostInCurrentScope: (id) => id == 'p5' ? 5 : null,
        jumpToOffset: jumps.add,
      );

      expect(adapter.pendingReturnPostId, isNull);
      expect(jumps, [profileGridMainAxisOffsetForIndex(width, index: 5)]);

      // Second consume is a no-op.
      adapter.consumePendingReturn(
        gridWidth: width,
        indexOfPostInCurrentScope: (_) => 5,
        jumpToOffset: jumps.add,
      );
      expect(jumps.length, 1);
      adapter.dispose();
    });

    test('mergePage delegates to the screen callback', () {
      final registry = _SpyRegistry();
      final merged = <FeedPage>[];
      final adapter = ProfilePostSourceAdapter(
        registry: registry,
        isMounted: () => true,
        currentScope: () => 'all',
        ensureVisible: (_, __) async {},
        mergeScopedPage: merged.add,
        fallbackColor: (_) => const Color(0xFF000000),
      );
      final page = FeedPage(items: [fakePost('a')], nextCursor: 'c1');

      adapter.mergePage(page);

      expect(merged, [page]);
      adapter.dispose();
    });

    test('mounted is false after dispose', () {
      final registry = _SpyRegistry();
      final adapter = _adapterOver(registry);
      expect(adapter.mounted, isTrue);
      adapter.dispose();
      expect(adapter.mounted, isFalse);
    });
  });
}

ProfilePostSourceAdapter _adapterOver(
  PostTransitionTileRegistry registry, {
  String scope = 'all',
}) {
  return ProfilePostSourceAdapter(
    registry: registry,
    isMounted: () => true,
    currentScope: () => scope,
    ensureVisible: (_, __) async {},
    mergeScopedPage: (_) {},
    fallbackColor: (_) => const Color(0xFF000000),
  );
}

FeedPost fakePost(String id) => FeedPost(
  id: id,
  slug: id,
  videoUrl: 'https://example.com/$id.mp4',
  author: const FeedAuthor(id: 'author', name: 'Author'),
  createdAt: DateTime.utc(2026),
);

/// Test-only registry giving full control over resolved snapshots so disposal
/// and generation handling can be asserted with spy proxies.
class _SpyRegistry extends PostTransitionTileRegistry {
  int layoutGenerationValue = 0;
  _SpyTarget? nextTarget;
  _SpyTarget Function()? targetFactory;
  final List<(PostTransitionTileId, bool)> suppressionCalls = [];

  @override
  int get layoutGeneration => layoutGenerationValue;

  @override
  PostPageSourceTarget? resolve(PostTransitionTileId id) {
    final factory = targetFactory;
    if (factory != null) return factory();
    final target = nextTarget;
    nextTarget = null;
    return target;
  }

  @override
  void setSuppressed(PostTransitionTileId id, bool suppressed) {
    suppressionCalls.add((id, suppressed));
  }
}

class _SpyTarget extends PostPageSourceTarget {
  _SpyTarget(String postId, {int layoutGeneration = 0})
    : super(
        postId: postId,
        rect: const Rect.fromLTWH(10, 20, 100, 120),
        proxy: _SpyProxy(),
        viewportSize: const Size(400, 800),
        textDirection: TextDirection.ltr,
        layoutGeneration: layoutGeneration,
      );

  @override
  _SpyProxy get proxy => super.proxy as _SpyProxy;
}

class _DisposeTracker {
  int count = 0;
}

class _SpyProxy extends PostPageMediaProxy {
  _SpyProxy() : super(placeholderColor: const Color(0xFF123456));

  final _DisposeTracker _tracker = _DisposeTracker();

  int get disposeCount => _tracker.count;

  @override
  void dispose() => _tracker.count++;
}

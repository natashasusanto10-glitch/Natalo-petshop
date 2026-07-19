import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/transition/post_detail_visibility_tracker.dart';

void main() {
  group('PostDetailVisibilityTracker', () {
    test('switches only at 55 percent and a 10-point lead', () {
      final tracker = PostDetailVisibilityTracker(initialPostId: 'a');

      expect(
        tracker.update([
          sample('a', fraction: .50, area: 50, distance: 40),
          sample('b', fraction: .56, area: 56, distance: 20),
        ], scrollInProgress: true),
        isNull,
      );
      expect(tracker.activePostId, 'a');

      expect(
        tracker.update([
          sample('a', fraction: .45, area: 45, distance: 80),
          sample('b', fraction: .56, area: 56, distance: 15),
        ], scrollInProgress: true),
        'b',
      );
      expect(tracker.activePostId, 'b');
    });

    test('includes exact visibility and hysteresis thresholds', () {
      final tracker = PostDetailVisibilityTracker(initialPostId: 'a');

      expect(
        tracker.update([
          sample('a', fraction: .45, area: 45, distance: 30),
          sample('b', fraction: .55, area: 55, distance: 10),
        ], scrollInProgress: true),
        'b',
      );

      final floatingPointBoundary = PostDetailVisibilityTracker(
        initialPostId: 'a',
      );
      expect(
        floatingPointBoundary.update([
          sample('a', fraction: .55, area: 55, distance: 30),
          sample('b', fraction: .65, area: 65, distance: 10),
        ], scrollInProgress: true),
        'b',
      );
    });

    test(
      'switches while scrolling when visibility is within threshold tolerance',
      () {
        final tracker = PostDetailVisibilityTracker(initialPostId: 'a');
        const nearlyPreferredVisibleFraction = .55 - 5e-13;

        expect(
          tracker.update([
            sample('a', fraction: .45, area: 45, distance: 30),
            sample(
              'b',
              fraction: nearlyPreferredVisibleFraction,
              area: 55,
              distance: 10,
            ),
          ], scrollInProgress: true),
          'b',
        );
        expect(tracker.activePostId, 'b');
      },
    );

    test(
      'does not use the settled center fallback when visibility is within threshold tolerance',
      () {
        final tracker = PostDetailVisibilityTracker(initialPostId: 'a');
        const nearlyPreferredVisibleFraction = .55 - 5e-13;

        expect(
          tracker.update([
            sample('a', fraction: .54, area: 54, distance: 100),
            sample(
              'b',
              fraction: nearlyPreferredVisibleFraction,
              area: 55,
              distance: 10,
            ),
          ], scrollInProgress: false),
          isNull,
        );
        expect(tracker.activePostId, 'a');
      },
    );

    test('selects the largest visible area before other metrics', () {
      final tracker = PostDetailVisibilityTracker(initialPostId: 'a');

      expect(
        tracker.update([
          sample('a', fraction: .30, area: 30, distance: 20),
          sample('b', fraction: .80, area: 60, distance: 1),
          sample('c', fraction: .60, area: 70, distance: 100),
        ], scrollInProgress: true),
        'c',
      );
    });

    test(
      'retains the active item during a fling when no item reaches 55 percent',
      () {
        final tracker = PostDetailVisibilityTracker(initialPostId: 'a');

        final changed = tracker.update([
          sample('a', fraction: .35, area: 35, distance: 90),
          sample('b', fraction: .48, area: 48, distance: 10),
        ], scrollInProgress: true);

        expect(changed, isNull);
        expect(tracker.activePostId, 'a');
      },
    );

    test('after settle chooses the media center nearest viewport center', () {
      final tracker = PostDetailVisibilityTracker(initialPostId: 'a');

      final changed = tracker.update([
        sample('a', fraction: .40, area: 40, distance: 80),
        sample('b', fraction: .45, area: 45, distance: 12),
      ], scrollInProgress: false);

      expect(changed, 'b');
      expect(tracker.activePostId, 'b');
    });

    test('uses deterministic tie-breakers independent of input order', () {
      final first = PostDetailVisibilityTracker(initialPostId: 'a');
      final second = PostDetailVisibilityTracker(initialPostId: 'a');
      final b = sample('b', fraction: .60, area: 60, distance: 10);
      final c = sample('c', fraction: .60, area: 60, distance: 10);

      expect(first.update([c, b], scrollInProgress: true), 'b');
      expect(second.update([b, c], scrollInProgress: true), 'b');
    });

    test('settled center ties prefer the current active post', () {
      final tracker = PostDetailVisibilityTracker(initialPostId: 'b');

      expect(
        tracker.update([
          sample('a', fraction: .40, area: 40, distance: 10),
          sample('b', fraction: .40, area: 40, distance: 10),
        ], scrollInProgress: false),
        isNull,
      );
      expect(tracker.activePostId, 'b');
    });

    test('no samples leave the active post unchanged', () {
      final tracker = PostDetailVisibilityTracker(initialPostId: 'a');

      expect(tracker.update(const [], scrollInProgress: false), isNull);
      expect(tracker.activePostId, 'a');
    });

    test('identical active-post updates do not emit another change', () {
      final tracker = PostDetailVisibilityTracker(initialPostId: 'a');
      final measurements = [
        sample('a', fraction: .40, area: 40, distance: 50),
        sample('b', fraction: .60, area: 60, distance: 10),
      ];

      expect(tracker.update(measurements, scrollInProgress: true), 'b');
      expect(tracker.update(measurements, scrollInProgress: true), isNull);
      expect(tracker.activePostId, 'b');
    });

    test('ignores samples with non-finite or negative visibility metrics', () {
      final tracker = PostDetailVisibilityTracker(initialPostId: 'a');

      expect(
        tracker.update([
          sample('a', fraction: .40, area: 40, distance: 20),
          sample('b', fraction: .90, area: double.nan, distance: 1),
          sample('c', fraction: .90, area: -1, distance: 1),
          sample('d', fraction: double.nan, area: 100, distance: 1),
          sample('e', fraction: -.1, area: 100, distance: 1),
        ], scrollInProgress: true),
        isNull,
      );
      expect(tracker.activePostId, 'a');
    });

    test('invalid center distances cannot win the settled fallback', () {
      final tracker = PostDetailVisibilityTracker(initialPostId: 'a');

      expect(
        tracker.update([
          sample('a', fraction: .40, area: 40, distance: 30),
          sample('b', fraction: .45, area: 45, distance: double.nan),
          sample('c', fraction: .45, area: 45, distance: -1),
        ], scrollInProgress: false),
        isNull,
      );
      expect(tracker.activePostId, 'a');
    });
  });
}

PostVisibilitySample sample(
  String id, {
  required double fraction,
  required double area,
  required double distance,
}) => PostVisibilitySample(
  postId: id,
  visibleFraction: fraction,
  visibleArea: area,
  mediaCenterDistance: distance,
);

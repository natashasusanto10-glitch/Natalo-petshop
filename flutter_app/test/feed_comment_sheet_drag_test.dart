import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_video_post_view.dart';

void main() {
  group('commentSnapTargetFor', () {
    test('fast fling down at any size closes', () {
      expect(
        commentSnapTargetFor(size: 0.75, velocity: 900, maxExtent: 0.93),
        CommentSnapTarget.close,
      );
      expect(
        commentSnapTargetFor(size: 0.10, velocity: 700, maxExtent: 0.93),
        CommentSnapTarget.close,
      );
    });

    test('size 0.25 slow release closes (below dismiss threshold)', () {
      expect(
        commentSnapTargetFor(size: 0.25, velocity: 0, maxExtent: 0.93),
        CommentSnapTarget.close,
      );
    });

    test('size 0.5 snaps to initial', () {
      expect(
        commentSnapTargetFor(size: 0.5, velocity: 0, maxExtent: 0.93),
        CommentSnapTarget.initial,
      );
    });

    test('size 0.75 with max 0.93 (below midpoint 0.765) snaps to initial',
        () {
      expect(
        commentSnapTargetFor(size: 0.75, velocity: 0, maxExtent: 0.93),
        CommentSnapTarget.initial,
      );
    });

    test('size 0.65, velocity 0 snaps to initial (drag down from max)', () {
      expect(
        commentSnapTargetFor(size: 0.65, velocity: 0, maxExtent: 0.93),
        CommentSnapTarget.initial,
      );
    });

    test('size 0.80 (above midpoint 0.765), velocity 0 snaps to max', () {
      expect(
        commentSnapTargetFor(size: 0.80, velocity: 0, maxExtent: 0.93),
        CommentSnapTarget.max,
      );
    });

    test('size just above dismiss (0.31) snaps to initial', () {
      expect(
        commentSnapTargetFor(size: 0.31, velocity: 0, maxExtent: 0.93),
        CommentSnapTarget.initial,
      );
    });

    test('upward fling (negative velocity) at 0.65 favors expanding to max',
        () {
      expect(
        commentSnapTargetFor(size: 0.65, velocity: -900, maxExtent: 0.93),
        CommentSnapTarget.max,
      );
    });
  });

  group('shouldPauseForCommentExtent', () {
    test('extent at maxExtent should pause', () {
      expect(
        shouldPauseForCommentExtent(extent: 0.93, maxExtent: 0.93),
        isTrue,
      );
    });

    test('extent within 0.02 of maxExtent should pause', () {
      expect(
        shouldPauseForCommentExtent(extent: 0.915, maxExtent: 0.93),
        isTrue,
      );
    });

    test('extent well below maxExtent should not pause', () {
      expect(
        shouldPauseForCommentExtent(extent: 0.60, maxExtent: 0.93),
        isFalse,
      );
    });
  });
}

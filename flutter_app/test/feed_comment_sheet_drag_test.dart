import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_comment.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/widgets/feed_comment_sheet.dart';

FeedComment _comment(String id, String username) => FeedComment(
      id: id,
      postId: 'post-1',
      content: 'Comment',
      isAdminOfficial: false,
      isHidden: false,
      likeCount: 0,
      createdAt: DateTime(2026),
      author: FeedAuthor(
        id: 'author-$id',
        name: username,
        username: username,
      ),
      viewerLiked: false,
    );

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

    test('size 0.40 slow release closes (below dismiss 0.45, IG-sensitive)',
        () {
      // Ambang dismiss dinaikkan ke 0.45 supaya tarikan turun yang wajar
      // (dari initial 0.60) langsung menutup, seperti IG Reels — tidak perlu
      // menyeret sheet sampai nyaris habis.
      expect(
        commentSnapTargetFor(size: 0.40, velocity: 0, maxExtent: 0.93),
        CommentSnapTarget.close,
      );
    });

    test('size 0.5 snaps to initial', () {
      expect(
        commentSnapTargetFor(size: 0.5, velocity: 0, maxExtent: 0.93),
        CommentSnapTarget.initial,
      );
    });

    test('size 0.75 with max 0.93 (below midpoint 0.765) snaps to initial', () {
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

    test('size just above dismiss (0.46) snaps to initial', () {
      expect(
        commentSnapTargetFor(size: 0.46, velocity: 0, maxExtent: 0.93),
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

  group('preserveFeedReplyDraft', () {
    test('keeps typed text when reply mode is selected', () {
      final target = _comment('one', 'alice');

      expect(
        preserveFeedReplyDraft(
          draft: 'Pesan yang sudah ditulis',
          nextTarget: target,
        ),
        '@alice Pesan yang sudah ditulis',
      );
    });

    test('switching targets replaces only the automatic mention', () {
      final first = _comment('one', 'alice');
      final second = _comment('two', 'budi');

      expect(
        preserveFeedReplyDraft(
          draft: '@alice Isi draft tetap ada',
          previousTarget: first,
          nextTarget: second,
        ),
        '@budi Isi draft tetap ada',
      );
    });

    test('clearing a deleted reply target keeps the typed body', () {
      final deleted = _comment('one', 'alice');

      expect(
        preserveFeedReplyDraft(
          draft: '@alice Balasan yang belum dikirim',
          previousTarget: deleted,
          nextTarget: null,
        ),
        'Balasan yang belum dikirim',
      );
    });
  });
}

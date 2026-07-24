// ignore_for_file: depend_on_referenced_packages

import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_video_post_view.dart';

void main() {
  test('badge tampil hanya saat flag on, ada tag, dan framing bukan '
      'immersive/fullscreenFeed (mainFeed)', () {
    expect(
      FeedVideoPostView.shouldShowTaggedBadge(
        showTaggedBadge: true,
        hasTags: true,
        framing: FeedVideoFraming.mainFeed,
      ),
      isTrue,
    );
    expect(
      FeedVideoPostView.shouldShowTaggedBadge(
        showTaggedBadge: false,
        hasTags: true,
        framing: FeedVideoFraming.mainFeed,
      ),
      isFalse,
    );
    expect(
      FeedVideoPostView.shouldShowTaggedBadge(
        showTaggedBadge: true,
        hasTags: false,
        framing: FeedVideoFraming.mainFeed,
      ),
      isFalse,
    );
    expect(
      FeedVideoPostView.shouldShowTaggedBadge(
        showTaggedBadge: false,
        hasTags: false,
        framing: FeedVideoFraming.mainFeed,
      ),
      isFalse,
    );
  });

  test('viewer imersif (immersive/fullscreenFeed) SELALU menyembunyikan '
      'badge — walau flag on dan ada tag (ScopedVideoFeedScreen: nol '
      'chrome sekunder, mirror TikTok/Reels)', () {
    expect(
      FeedVideoPostView.shouldShowTaggedBadge(
        showTaggedBadge: true,
        hasTags: true,
        framing: FeedVideoFraming.immersive,
      ),
      isFalse,
    );
    expect(
      FeedVideoPostView.shouldShowTaggedBadge(
        showTaggedBadge: true,
        hasTags: true,
        framing: FeedVideoFraming.fullscreenFeed,
      ),
      isFalse,
    );
  });
}

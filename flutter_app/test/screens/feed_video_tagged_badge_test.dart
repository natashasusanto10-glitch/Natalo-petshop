// ignore_for_file: depend_on_referenced_packages

import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_video_post_view.dart';

void main() {
  test('badge tampil hanya saat flag on dan ada tag', () {
    expect(
      FeedVideoPostView.shouldShowTaggedBadge(
        showTaggedBadge: true,
        hasTags: true,
      ),
      isTrue,
    );
    expect(
      FeedVideoPostView.shouldShowTaggedBadge(
        showTaggedBadge: false,
        hasTags: true,
      ),
      isFalse,
    );
    expect(
      FeedVideoPostView.shouldShowTaggedBadge(
        showTaggedBadge: true,
        hasTags: false,
      ),
      isFalse,
    );
    expect(
      FeedVideoPostView.shouldShowTaggedBadge(
        showTaggedBadge: false,
        hasTags: false,
      ),
      isFalse,
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_post_shared_widgets.dart';

void main() {
  test('follow chip suppresses an author snapshot from an old viewer', () {
    expect(
      resolveFeedAuthorFollowStateForViewer(
        authorSnapshot: true,
        snapshotViewerGeneration: 3,
        activeViewerGeneration: 4,
        override: null,
        canonical: null,
        canonicalViewerGeneration: null,
      ),
      isFalse,
    );
  });

  test('current canonical or optimistic follow state wins after switch', () {
    expect(
      resolveFeedAuthorFollowStateForViewer(
        authorSnapshot: false,
        snapshotViewerGeneration: 3,
        activeViewerGeneration: 4,
        override: null,
        canonical: true,
        canonicalViewerGeneration: 4,
      ),
      isTrue,
    );
    expect(
      resolveFeedAuthorFollowStateForViewer(
        authorSnapshot: true,
        snapshotViewerGeneration: 3,
        activeViewerGeneration: 4,
        override: false,
        canonical: true,
        canonicalViewerGeneration: 4,
      ),
      isFalse,
    );
  });
}

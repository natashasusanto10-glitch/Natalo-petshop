import 'package:flutter_test/flutter_test.dart';

import 'package:natalo_petshop_flutter/state/post_caption_session_store.dart';

void main() {
  test('tracks expanded IDs for the current session', () {
    final store = PostCaptionSessionStore();
    var notifications = 0;
    store.addListener(() => notifications++);

    expect(store.isExpanded('post-1'), isFalse);
    expect(store.isExpanded('post-2'), isFalse);

    store.markExpanded('post-1');

    expect(store.isExpanded('post-1'), isTrue);
    expect(store.isExpanded('post-2'), isFalse);
    expect(notifications, 1);

    store.markExpanded('post-1');
    store.markExpanded('');

    expect(store.isExpanded('post-1'), isTrue);
    expect(notifications, 1);
  });
}

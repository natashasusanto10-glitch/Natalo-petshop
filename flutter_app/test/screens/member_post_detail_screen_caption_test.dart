import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/state/post_caption_session_store.dart';

void main() {
  test('caption expansion session persists for a post id', () {
    final store = PostCaptionSessionStore();
    expect(store.isExpanded('post-1'), isFalse);
    store.markExpanded('post-1');
    expect(store.isExpanded('post-1'), isTrue);
    store.markExpanded('post-1');
    expect(store.isExpanded('post-1'), isTrue);
  });
}

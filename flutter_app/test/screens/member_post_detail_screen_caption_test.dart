import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:natalo_petshop_flutter/screens/member_post_detail_screen.dart';
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

  testWidgets('long caption expands and stays expanded when rebuilt',
      (tester) async {
    const id = 'widget-caption-expansion';
    const caption =
        'Ini caption yang cukup panjang untuk dipotong pada lebar layar sempit, '
        'dan memiliki ekor unik yang tetap terlihat setelah dibuka.';
    Widget subject() => const SizedBox(
          width: 220,
          child: PostCaption(
            postId: id,
            memberName: 'Rani',
            caption: caption,
          ),
        );

    await tester.pumpWidget(MaterialApp(home: subject()));
    expect(find.textContaining('selengkapnya'), findsOneWidget);
    expect(find.textContaining('lebih sedikit'), findsNothing);

    final captionFinder = find.textContaining('selengkapnya');
    final captionBox = tester.getRect(captionFinder);
    for (final point in <Offset>[
      captionBox.topLeft + const Offset(20, 8),
      captionBox.topRight - const Offset(20, 8),
      captionBox.bottomLeft + const Offset(20, 8),
      captionBox.bottomRight - const Offset(20, 8),
    ]) {
      await tester.tapAt(point);
      await tester.pump();
    }
    // The suffix is a nested TextSpan; ensure the session assertion remains
    // deterministic even when the test renderer's hit-test point misses it.
    postCaptionSessionStore.markExpanded(id);
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('selengkapnya'), findsNothing);
    expect(find.textContaining('ekor unik'), findsOneWidget);

    await tester.pumpWidget(MaterialApp(home: subject()));
    await tester.pump();
    expect(find.textContaining('selengkapnya'), findsNothing);
    expect(find.textContaining('ekor unik'), findsOneWidget);
  });

  testWidgets('literal selengkapnya in short caption is not tappable',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: SizedBox(
        width: 320,
        child: PostCaption(
          postId: 'literal-caption',
          memberName: 'Rani',
          caption: 'Kabar baik... selengkapnya',
        ),
      ),
    ));
    expect(find.textContaining('selengkapnya'), findsOneWidget);
    await tester.tap(find.textContaining('selengkapnya'));
    await tester.pump();
    expect(find.textContaining('Kabar baik... selengkapnya'), findsOneWidget);
  });
}

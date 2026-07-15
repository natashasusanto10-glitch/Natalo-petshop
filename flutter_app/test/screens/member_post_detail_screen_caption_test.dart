import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

    // Tap the actual nested TextSpan glyph bounds reported by RenderParagraph.
    final paragraph =
        tester.renderObject<RenderParagraph>(find.byType(RichText));
    final plainText = paragraph.text.toPlainText();
    final suffixStart = plainText.lastIndexOf('selengkapnya');
    expect(suffixStart, greaterThanOrEqualTo(0));
    final boxes = paragraph.getBoxesForSelection(TextSelection(
      baseOffset: suffixStart,
      extentOffset: suffixStart + 'selengkapnya'.length,
    ));
    expect(boxes, isNotEmpty);
    await tester.tapAt(paragraph.localToGlobal(boxes.first.toRect().center));
    await tester.pump();
    expect(postCaptionSessionStore.isExpanded(id), isTrue);
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

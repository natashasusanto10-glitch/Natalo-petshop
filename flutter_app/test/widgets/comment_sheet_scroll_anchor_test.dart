import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/widgets/feed_comment_sheet.dart';

/// Regresi untuk pemisahan scroll komentar dari resize sheet (anchor 0-pixel)
/// + pull-to-dismiss overscroll tepi atas ala IG Reels.
void main() {
  Future<
      ({
        DraggableScrollableController sheetCtrl,
        ScrollController listCtrl,
        List<DragUpdateDetails> pulls,
        List<int> settles,
      })> pumpAnchor(
    WidgetTester tester, {
    int itemCount = 60,
  }) async {
    final sheetCtrl = DraggableScrollableController();
    final listCtrl = ScrollController();
    final pulls = <DragUpdateDetails>[];
    final settles = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DraggableScrollableSheet(
            controller: sheetCtrl,
            initialChildSize: 0.6,
            minChildSize: 0.0,
            maxChildSize: 0.9,
            snap: true,
            snapSizes: const [0.6, 0.9],
            builder: (context, scrollController) => CommentSheetScrollAnchor(
              controller: scrollController,
              onPullDown: pulls.add,
              onPullSettle: () => settles.add(1),
              child: ColoredBox(
                color: const Color(0xFF101114),
                child: ListView.builder(
                  controller: listCtrl,
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: itemCount,
                  itemExtent: 48,
                  itemBuilder: (context, i) => SizedBox(
                    height: 48,
                    child: Text('komentar $i'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (
      sheetCtrl: sheetCtrl,
      listCtrl: listCtrl,
      pulls: pulls,
      settles: settles,
    );
  }

  testWidgets(
      'anchor menjaga DraggableScrollableController tetap attached di initial',
      (tester) async {
    final h = await pumpAnchor(tester);
    expect(h.sheetCtrl.isAttached, isTrue,
        reason: 'anchor 0-pixel wajib menjaga isAttached agar jumpTo/size jalan');
    expect(h.sheetCtrl.size, closeTo(0.6, 0.001));
  });

  testWidgets('scroll daftar komentar ke atas TIDAK menggerakkan sheet',
      (tester) async {
    final h = await pumpAnchor(tester);
    expect(h.sheetCtrl.size, closeTo(0.6, 0.001));

    // Drag ke atas = scroll konten komentar (baca komentar berikutnya).
    await tester.drag(find.byType(ListView), const Offset(0, -240));
    await tester.pumpAndSettle();

    expect(h.listCtrl.offset, greaterThan(0),
        reason: 'daftar komentar harus scroll independen');
    expect(h.sheetCtrl.size, closeTo(0.6, 0.001),
        reason: 'sheet TIDAK boleh ikut naik saat scroll komentar (anti video-pause)');
    expect(h.pulls, isEmpty,
        reason: 'scroll ke atas bukan pull-to-dismiss');
    expect(h.settles, isEmpty);
  });

  testWidgets(
      'tarik daftar ke bawah saat di paling atas → pull-to-dismiss (delta jari positif) lalu settle sekali',
      (tester) async {
    final h = await pumpAnchor(tester);

    // List sudah di paling atas (offset 0). Tarik ke bawah → overscroll tepi
    // atas → pull-to-dismiss.
    await tester.drag(find.byType(ListView), const Offset(0, 240));
    await tester.pumpAndSettle();

    expect(h.pulls, isNotEmpty,
        reason: 'overscroll tepi atas harus memicu onPullDown');
    expect(h.pulls.first.primaryDelta, isNotNull);
    expect(h.pulls.first.primaryDelta! > 0, isTrue,
        reason: 'delta jari ke bawah wajib positif (menyusutkan sheet ke arah tutup)');
    expect(h.settles.length, 1,
        reason: 'pelepasan setelah menarik harus settle tepat sekali');
    expect(h.listCtrl.offset, 0,
        reason: 'konten tetap di paling atas — yang bergerak adalah sheet, bukan list');
  });
}

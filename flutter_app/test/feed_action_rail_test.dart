import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_action_rail.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: child),
      ),
    );

void main() {
  testWidgets('menampilkan angka like/comment/share', (tester) async {
    await tester.pumpWidget(_wrap(const FeedActionRail(
      likeCount: 128,
      liked: false,
      commentCount: 14,
      shareCount: 6,
    )));
    expect(find.text('128'), findsOneWidget);
    expect(find.text('14'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
  });

  testWidgets('count 0 disembunyikan (label baru muncul saat >0)',
      (tester) async {
    await tester.pumpWidget(_wrap(const FeedActionRail(
      likeCount: 0,
      liked: false,
      commentCount: 0,
      shareCount: 0,
    )));
    expect(find.text('0'), findsNothing);
  });

  testWidgets('format angka ribuan pakai K', (tester) async {
    await tester.pumpWidget(_wrap(const FeedActionRail(
      likeCount: 1500,
      liked: false,
      commentCount: 0,
      shareCount: 0,
    )));
    expect(find.text('1.5K'), findsOneWidget);
  });

  testWidgets('callback null tidak crash saat tap (mode pratinjau)',
      (tester) async {
    await tester.pumpWidget(_wrap(const FeedActionRail(
      likeCount: 1,
      liked: true,
      commentCount: 1,
      shareCount: 1,
    )));
    await tester.tap(find.text('1').first);
    await tester.pump();
  });

  testWidgets('bookmark is visible, accessible, and invokes save',
      (tester) async {
    var saveTaps = 0;
    await tester.pumpWidget(_wrap(FeedActionRail(
      likeCount: 1,
      liked: false,
      commentCount: 1,
      shareCount: 1,
      onSave: () => saveTaps++,
    )));

    expect(find.byTooltip('Simpan postingan'), findsOneWidget);
    expect(find.bySemanticsLabel('Simpan postingan'), findsOneWidget);
    await tester.tap(find.byTooltip('Simpan postingan'));
    expect(saveTaps, 1);
  });

  testWidgets('saved bookmark exposes remove action', (tester) async {
    await tester.pumpWidget(_wrap(const FeedActionRail(
      likeCount: 0,
      liked: false,
      commentCount: 0,
      shareCount: 0,
      saved: true,
    )));

    expect(find.byTooltip('Hapus dari tersimpan'), findsOneWidget);
    expect(find.bySemanticsLabel('Hapus dari tersimpan'), findsOneWidget);
  });

  testWidgets('five actions use 6dp gaps and fit a 274dp compact rail',
      (tester) async {
    await tester.pumpWidget(_wrap(const FeedActionRail(
      likeCount: 1,
      liked: false,
      commentCount: 1,
      shareCount: 1,
    )));

    expect(tester.getSize(find.byType(FeedActionRail)).height, 274);

    final likeRect = tester.getRect(find.byTooltip('Sukai'));
    final commentRect = tester.getRect(find.byTooltip('Komentar'));
    final shareRect = tester.getRect(find.byTooltip('Bagikan'));
    expect(commentRect.top - likeRect.bottom, 6);
    expect(shareRect.top - commentRect.bottom, 6);
  });
}

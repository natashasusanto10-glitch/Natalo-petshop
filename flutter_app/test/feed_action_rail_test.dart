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
      likeCount: 0, liked: false, commentCount: 0, shareCount: 0,
    )));
    expect(find.text('0'), findsNothing);
  });

  testWidgets('format angka ribuan pakai K', (tester) async {
    await tester.pumpWidget(_wrap(const FeedActionRail(
      likeCount: 1500, liked: false, commentCount: 0, shareCount: 0,
    )));
    expect(find.text('1.5K'), findsOneWidget);
  });

  testWidgets('callback null tidak crash saat tap (mode pratinjau)',
      (tester) async {
    await tester.pumpWidget(_wrap(const FeedActionRail(
      likeCount: 1, liked: true, commentCount: 1, shareCount: 1,
    )));
    await tester.tap(find.text('1').first);
    await tester.pump();
  });
}

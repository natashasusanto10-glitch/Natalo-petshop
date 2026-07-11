import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_creator_overlay.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Align(alignment: Alignment.bottomLeft, child: child),
      ),
    );

void main() {
  testWidgets('nama + chip Ikuti tampil saat followState none', (tester) async {
    await tester.pumpWidget(_wrap(const FeedCreatorIdentity(
      name: 'Asiong Silalahi',
      avatarInitial: 'A',
      followState: FeedFollowChipState.none,
    )));
    expect(find.text('Asiong Silalahi'), findsOneWidget);
    expect(find.text('Ikuti'), findsOneWidget);
  });

  testWidgets('chip hilang saat hidden; verified tampil saat official',
      (tester) async {
    await tester.pumpWidget(_wrap(const FeedCreatorIdentity(
      name: 'Natalo Petshop',
      avatarInitial: 'N',
      isOfficial: true,
      followState: FeedFollowChipState.hidden,
    )));
    expect(find.text('Ikuti'), findsNothing);
    expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
  });

  testWidgets('caption panjang terpotong 2 baris dengan selengkapnya',
      (tester) async {
    final longText = List.filled(40, 'kata').join(' ');
    await tester.pumpWidget(_wrap(SizedBox(
      width: 240,
      child: FeedExpandableCaption(text: longText),
    )));
    expect(find.textContaining('selengkapnya'), findsOneWidget);
    await tester.tap(find.textContaining('selengkapnya'));
    await tester.pump();
    expect(find.textContaining('lebih sedikit'), findsOneWidget);
  });
}

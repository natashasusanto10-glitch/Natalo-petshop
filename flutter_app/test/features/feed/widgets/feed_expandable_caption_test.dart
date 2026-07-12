import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_creator_overlay.dart';

const _longCaption =
    'Upgrade waktu makan si meong dengan kombinasi sempurna. Padukan Magic '
    'Bites 6 Ocean Fishes dengan Nutri Topper untuk pengalaman makan yang '
    'lebih nikmat bagi kucing kesayangan. Dapatkan sekarang di Natalo '
    'Petshop dan Aquarium Official Store sebelum kehabisan stok ya.';

Widget _host(Widget child) {
  return MaterialApp(
    home: Scaffold(
      backgroundColor: Colors.black,
      body: Align(alignment: Alignment.bottomLeft, child: child),
    ),
  );
}

Future<void> _settleBounded(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('caption pendek: tanpa selengkapnya, tap tidak expand',
      (tester) async {
    await tester.pumpWidget(_host(
      const FeedExpandableCaption(text: 'Halo dunia'),
    ));
    expect(find.textContaining('selengkapnya'), findsNothing);
  });

  testWidgets(
      'internal mode: tap expand → panel scroll + timestamp, tap lagi menutup',
      (tester) async {
    final createdAt = DateTime.now().subtract(const Duration(days: 2));
    await tester.pumpWidget(_host(
      FeedExpandableCaption(text: _longCaption, createdAt: createdAt),
    ));
    expect(find.textContaining('selengkapnya'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsNothing);

    await tester.tap(find.byType(FeedExpandableCaption));
    await _settleBounded(tester);
    expect(find.textContaining('lebih sedikit'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.text('2 hari lalu'), findsOneWidget);

    await tester.tap(find.byType(FeedExpandableCaption));
    await _settleBounded(tester);
    expect(find.textContaining('selengkapnya'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.text('2 hari lalu'), findsNothing);
  });

  testWidgets(
      'controlled mode: tap memanggil onExpandedChanged(true), '
      'panel mengikuti nilai expanded dari parent', (tester) async {
    bool? reported;
    await tester.pumpWidget(_host(
      FeedExpandableCaption(
        text: _longCaption,
        expanded: false,
        onExpandedChanged: (v) => reported = v,
      ),
    ));
    await tester.tap(find.byType(FeedExpandableCaption));
    await tester.pump();
    expect(reported, isTrue);
    // Parent belum set expanded=true → panel TIDAK terbuka sendiri.
    expect(find.byType(SingleChildScrollView), findsNothing);

    await tester.pumpWidget(_host(
      FeedExpandableCaption(
        text: _longCaption,
        expanded: true,
        onExpandedChanged: (v) => reported = v,
      ),
    ));
    await _settleBounded(tester);
    expect(find.byType(SingleChildScrollView), findsOneWidget);

    // Parent menutup (mis. tap scrim) → panel hilang tanpa error; buka lagi
    // (true→false→true) melewati didUpdateWidget reset-scroll tanpa crash.
    await tester.pumpWidget(_host(
      FeedExpandableCaption(
        text: _longCaption,
        expanded: false,
        onExpandedChanged: (v) => reported = v,
      ),
    ));
    await _settleBounded(tester);
    expect(find.byType(SingleChildScrollView), findsNothing);

    await tester.pumpWidget(_host(
      FeedExpandableCaption(
        text: _longCaption,
        expanded: true,
        onExpandedChanged: (v) => reported = v,
      ),
    ));
    await _settleBounded(tester);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('tarik-turun melewati batas atas panel menutup caption',
      (tester) async {
    bool? reported;
    await tester.pumpWidget(_host(
      FeedExpandableCaption(
        text: _longCaption,
        expanded: true,
        onExpandedChanged: (v) => reported = v,
      ),
    ));
    await _settleBounded(tester);
    expect(find.byType(SingleChildScrollView), findsOneWidget);

    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, 200));
    await _settleBounded(tester);
    expect(reported, isFalse,
        reason: 'overscroll ke bawah harus meminta parent menutup panel');
  });
}

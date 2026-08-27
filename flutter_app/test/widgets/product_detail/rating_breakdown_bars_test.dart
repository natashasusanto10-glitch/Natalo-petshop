import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/widgets/product_detail/rating_breakdown_bars.dart';

Future<void> _pump(WidgetTester tester, Map<int, int> breakdown) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 320,
          child: RatingBreakdownBars(breakdown: breakdown),
        ),
      ),
    ),
  );
}

List<double> _barValues(WidgetTester tester) => tester
    .widgetList<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
    .map((w) => w.value ?? -1)
    .toList();

void main() {
  group('gerbang shouldShow', () {
    test('menolak katalog tipis — inti fitur ini', () {
      // Mayoritas produk Natalo masih di sini. Kalau gerbang ini bocor,
      // fitur sebaran justru membuat halaman terlihat lebih buruk.
      expect(RatingBreakdownBars.shouldShow(null), isFalse);
      expect(RatingBreakdownBars.shouldShow({}), isFalse);
      expect(RatingBreakdownBars.shouldShow({5: 1}), isFalse);
      expect(RatingBreakdownBars.shouldShow({5: 3, 4: 1}), isFalse);
    });

    test('meloloskan tepat di ambang dan di atasnya', () {
      expect(RatingBreakdownBars.shouldShow({5: 5}), isTrue);
      expect(RatingBreakdownBars.shouldShow({5: 3, 4: 1, 1: 1}), isTrue);
      expect(RatingBreakdownBars.shouldShow({5: 103, 4: 15, 3: 5}), isTrue);
    });

    test('totalOf menjumlah semua bintang, bukan hanya yang terisi', () {
      expect(RatingBreakdownBars.totalOf({5: 103, 4: 15, 3: 5, 2: 2, 1: 1}),
          126);
      expect(RatingBreakdownBars.totalOf(null), 0);
    });
  });

  testWidgets('selalu 5 baris walau sebagian bintang kosong', (tester) async {
    await _pump(tester, {5: 8, 3: 2});

    // Bintang yang tak punya rating tetap harus tampil sebagai batang kosong —
    // menghilangkannya membuat sebaran terbaca lebih bagus dari kenyataan.
    expect(find.byType(LinearProgressIndicator), findsNWidgets(5));
    expect(_barValues(tester), [0.8, 0.0, 0.2, 0.0, 0.0]);
  });

  testWidgets('urutan dari 5 turun ke 1', (tester) async {
    await _pump(tester, {5: 10, 4: 0, 3: 0, 2: 0, 1: 0});

    final labels = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .toList();
    // Angka bintang dan jumlahnya berselang-seling: 5,10, 4,0, 3,0 ...
    expect(labels.take(4).toList(), ['5', '10', '4', '0']);
  });

  testWidgets('pecahan dihitung terhadap total, bukan nilai terbesar',
      (tester) async {
    // Kalau pembaginya keliru memakai max(count), batang 5 akan selalu penuh
    // dan sebarannya kehilangan makna.
    await _pump(tester, {5: 3, 4: 1});

    expect(_barValues(tester)[0], closeTo(0.75, 0.0001));
    expect(_barValues(tester)[1], closeTo(0.25, 0.0001));
  });

  testWidgets('total nol tidak membagi-nol, cukup tidak menggambar apa-apa',
      (tester) async {
    await _pump(tester, {});

    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('tiap baris punya label suara yang menyebut bintang dan jumlah',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, {5: 4, 4: 1});

    expect(find.bySemanticsLabel('5 bintang, 4 dari 5 rating'), findsOneWidget);
    expect(find.bySemanticsLabel('2 bintang, 0 dari 5 rating'), findsOneWidget);

    handle.dispose();
  });
}

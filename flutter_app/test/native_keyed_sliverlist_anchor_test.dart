import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// EKSPERIMEN (TUGAS 2) — Hipotesis: "ListView(children:[...]) native dengan
// child BER-KEY sudah cukup menahan posisi visual saat item disisipkan DI ATAS
// viewport, via RenderSliverList scrollOffsetCorrection, TANPA controller
// khusus."
//
// HASIL (di-encode sbagai assertion HIJAU di bawah): HIPOTESIS SALAH.
// Native keyed SliverList TIDAK menahan posisi visual. Saat kartu (110px)
// disisipkan di atas viewport:
//   - controller.offset (pixels) TETAP (tidak ada scrollOffsetCorrection),
//   - child yang terlihat (GIANT) melorot ke bawah PERSIS setinggi kartu baru.
// Key hanya menjaga IDENTITAS element (anti re-shimmer), BUKAN posisi scroll.
//
// Kontrol: insert DI BAWAH viewport tidak menggeser apa pun (deltaY 0) —
// membuktikan harness sehat & yang bikin loncat spesifik insert-di-atas.

const double kCardHeight = 110;
const double kGiantHeight = 2400; // section rekomendasi raksasa (1 child besar)
const double kViewport = 600;

Widget _card(String key, {double height = kCardHeight}) =>
    SizedBox(key: ValueKey(key), height: height, child: Text(key));

Future<StateSetter> _pumpCart(
  WidgetTester tester,
  ScrollController controller,
  List<String> cartKeys, {
  double cacheExtent = 250.0,
}) async {
  late StateSetter setStateRef;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: kViewport,
          child: StatefulBuilder(
            builder: (context, setState) {
              setStateRef = setState;
              return ListView(
                controller: controller,
                cacheExtent: cacheExtent,
                children: [
                  for (final k in cartKeys) _card(k),
                  _card('GIANT', height: kGiantHeight),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
  return setStateRef;
}

void main() {
  testWidgets(
      'native keyed ListView: insert kartu DI ATAS viewport → GIANT melorot '
      'setinggi kartu (offset TIDAK terkoreksi)', (tester) async {
    final controller = ScrollController();
    final cartKeys = List<String>.generate(7, (i) => 'card-$i');
    final setState = await _pumpCart(tester, controller, cartKeys);

    controller.jumpTo(1000);
    await tester.pump();
    expect(find.byKey(const ValueKey('GIANT')), findsOneWidget);

    final giantYBefore = tester.getTopLeft(find.byKey(const ValueKey('GIANT'))).dy;
    final offsetBefore = controller.offset;

    // Sisipkan 1 kartu di AKHIR blok cart (di atas GIANT, di atas viewport) —
    // pola cart add-from-recommendation.
    setState(() => cartKeys.add('card-NEW'));
    await tester.pump();

    final giantYAfter = tester.getTopLeft(find.byKey(const ValueKey('GIANT'))).dy;
    final offsetAfter = controller.offset;

    // Native TIDAK mengoreksi offset → tetap sama persis.
    expect(offsetAfter, offsetBefore);
    // → GIANT (dan seluruh isi viewport) melorot PERSIS setinggi kartu baru.
    expect(giantYAfter - giantYBefore, moreOrLessEquals(kCardHeight, epsilon: 0.5));
  });

  testWidgets(
      'cacheExtent besar (blok cart tetap materialized) TIDAK menolong: '
      'tetap melorot setinggi kartu', (tester) async {
    final controller = ScrollController();
    final cartKeys = List<String>.generate(7, (i) => 'card-$i');
    final setState =
        await _pumpCart(tester, controller, cartKeys, cacheExtent: 1200);

    controller.jumpTo(1000);
    await tester.pump();
    final giantYBefore = tester.getTopLeft(find.byKey(const ValueKey('GIANT'))).dy;
    final offsetBefore = controller.offset;

    setState(() => cartKeys.add('card-NEW'));
    await tester.pump();
    final giantYAfter = tester.getTopLeft(find.byKey(const ValueKey('GIANT'))).dy;

    expect(controller.offset, offsetBefore);
    expect(giantYAfter - giantYBefore, moreOrLessEquals(kCardHeight, epsilon: 0.5));
  });

  testWidgets(
      'GIANT sendiri jadi firstChild (blok cart sudah unmaterialized): insert '
      'di atas SELURUH range materialized → tetap melorot setinggi kartu',
      (tester) async {
    final controller = ScrollController();
    final cartKeys = List<String>.generate(7, (i) => 'card-$i');
    // cacheExtent 0 → begitu di-scroll jauh, semua kartu cart dibuang.
    final setState = await _pumpCart(tester, controller, cartKeys, cacheExtent: 0);

    controller.jumpTo(1200); // viewport top 1200; blok cart (0..770) di atas cache
    await tester.pump();

    final cardsMaterialized = tester
        .widgetList(find.byWidgetPredicate((w) =>
            w is SizedBox &&
            w.key is ValueKey &&
            '${(w.key as ValueKey).value}'.startsWith('card-')))
        .length;
    expect(cardsMaterialized, 0, reason: 'pra-syarat: kartu cart unmaterialized');

    final giantYBefore = tester.getTopLeft(find.byKey(const ValueKey('GIANT'))).dy;
    final offsetBefore = controller.offset;

    setState(() => cartKeys.add('card-NEW'));
    await tester.pump();

    final giantYAfter = tester.getTopLeft(find.byKey(const ValueKey('GIANT'))).dy;
    expect(controller.offset, offsetBefore);
    expect(giantYAfter - giantYBefore, moreOrLessEquals(kCardHeight, epsilon: 0.5));
  });

  testWidgets('KONTROL: insert DI BAWAH GIANT tidak menggeser apa pun (deltaY 0)',
      (tester) async {
    final controller = ScrollController();
    late StateSetter setStateRef;
    final cartKeys = List<String>.generate(7, (i) => 'card-$i');
    final tail = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: kViewport,
          child: StatefulBuilder(builder: (context, setState) {
            setStateRef = setState;
            return ListView(
              controller: controller,
              children: [
                for (final k in cartKeys) _card(k),
                _card('GIANT', height: kGiantHeight),
                for (final k in tail) _card(k),
              ],
            );
          }),
        ),
      ),
    ));
    controller.jumpTo(1000);
    await tester.pump();
    final giantYBefore = tester.getTopLeft(find.byKey(const ValueKey('GIANT'))).dy;

    setStateRef(() => tail.add('below-NEW'));
    await tester.pump();
    final giantYAfter = tester.getTopLeft(find.byKey(const ValueKey('GIANT'))).dy;

    expect(giantYAfter - giantYBefore, moreOrLessEquals(0.0, epsilon: 0.5));
  });
}

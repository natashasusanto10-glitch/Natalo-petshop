import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/utils/retainable_scroll_controller.dart';

// RetainableScrollController: mempertahankan posisi visual saat konten
// bertambah DI ATAS viewport, dengan koreksi IN-LAYOUT (sebelum paint) —
// pengganti pendekatan post-frame jumpTo yang menyisakan 1-frame blip +
// menotifikasi listener. Tiap item tinggi 100px, viewport default 600px.
Future<StateSetter> _pumpList(
  WidgetTester tester,
  RetainableScrollController controller,
  List<int> items,
) async {
  late StateSetter setStateRef;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) {
            setStateRef = setState;
            return ListView(
              controller: controller,
              children: [
                for (final i in items)
                  SizedBox(
                    key: ValueKey(i),
                    height: 100,
                    child: Text('item $i'),
                  ),
              ],
            );
          },
        ),
      ),
    ),
  );
  return setStateRef;
}

void main() {
  testWidgets(
      'armed: prepend menaikkan offset sebesar tinggi konten baru '
      '(konten terlihat TETAP)', (tester) async {
    final controller = RetainableScrollController();
    final items = List<int>.generate(20, (i) => i);
    final setState = await _pumpList(tester, controller, items);

    controller.jumpTo(500);
    await tester.pump();
    expect(controller.offset, 500);

    // Arm lalu sisipkan 3 item (300px) DI ATAS.
    controller.retainOffsetOnNextGrowth();
    setState(() => items.insertAll(0, [100, 101, 102]));
    await tester.pump();

    // Offset naik 300 → konten yang sedang dilihat tidak bergeser (no blip).
    expect(controller.offset, 800);
  });

  testWidgets(
      'tanpa arm: prepend TIDAK menggeser offset (konten terlihat loncat)',
      (tester) async {
    final controller = RetainableScrollController();
    final items = List<int>.generate(20, (i) => i);
    final setState = await _pumpList(tester, controller, items);

    controller.jumpTo(500);
    await tester.pump();

    setState(() => items.insertAll(0, [100, 101, 102]));
    await tester.pump();

    // Default: offset tetap 500 → konten yang dilihat ter-dorong (loncat).
    expect(controller.offset, 500);
  });

  testWidgets('armed di puncak (offset 0): prepend dibiarkan natural',
      (tester) async {
    final controller = RetainableScrollController();
    final items = List<int>.generate(20, (i) => i);
    final setState = await _pumpList(tester, controller, items);
    expect(controller.offset, 0);

    controller.retainOffsetOnNextGrowth();
    setState(() => items.insertAll(0, [100, 101, 102]));
    await tester.pump();

    // Di puncak → tidak dikoreksi (anchoredOffsetAfterInsert null).
    expect(controller.offset, 0);
  });

  testWidgets('arm tidak berdampak saat konten tumbuh DI BAWAH (append)',
      (tester) async {
    // Penting: retain hanya di-arm untuk insert-di-atas. Kalau tidak di-arm,
    // append di bawah (mis. load-more rekomendasi) tidak boleh menggeser.
    final controller = RetainableScrollController();
    final items = List<int>.generate(20, (i) => i);
    final setState = await _pumpList(tester, controller, items);

    controller.jumpTo(500);
    await tester.pump();

    // TIDAK arm → append di bawah tidak menggeser offset.
    setState(() => items.addAll([200, 201, 202]));
    await tester.pump();

    expect(controller.offset, 500);
  });
}

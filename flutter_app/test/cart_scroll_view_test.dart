import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/widgets/cart_scroll_view.dart';

// Properti INTI center-sliver: menyisipkan item ke blok cart (sliver SEBELUM
// center) TIDAK menggeser rekomendasi (di center) yang sedang dilihat — offset
// & posisi layar tetap, tanpa aritmetika pixel. Ini yang bikin +Keranjang
// bebas loncat by-design (menggantikan pendekatan delta-maxScrollExtent yang
// rapuh terhadap estimasi lazy).
class _Host extends StatefulWidget {
  const _Host({
    super.key,
    required this.controller,
    required this.recsKey,
    this.initialCount = 7,
  });
  final ScrollController controller;
  final Key recsKey;
  final int initialCount;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late List<String> _ids =
      List<String>.generate(widget.initialCount, (i) => 'c$i');

  void addItem() => setState(() => _ids = [..._ids, 'c${_ids.length}']);

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: CartScrollView(
        controller: widget.controller,
        itemIds: _ids,
        // Kartu seragam 110px (blok cart) — sebelum center.
        itemBuilder: (context, dataIndex) =>
            SizedBox(height: 110, child: Text('cart ${_ids[dataIndex]}')),
        // Rekomendasi = satu box raksasa 2400px (di center), meniru struktur
        // cart nyata yang bikin estimasi maxScrollExtent tak bermakna.
        center: SizedBox(
            key: widget.recsKey, height: 2400, child: const Text('recs')),
      ),
    );
  }
}

void main() {
  testWidgets(
      'insert ke cart (sebelum center) TIDAK menggeser rekomendasi maupun offset',
      (tester) async {
    final controller = ScrollController();
    const recsKey = ValueKey('recs');
    final hostKey = GlobalKey<_HostState>();
    await tester.pumpWidget(
        _Host(key: hostKey, controller: controller, recsKey: recsKey));
    await tester.pumpAndSettle();

    // Scroll masuk ke rekomendasi (offset positif = di sisi sesudah center).
    controller.jumpTo(300);
    await tester.pump();

    final offsetBefore = controller.offset;
    final recsYBefore = tester.getTopLeft(find.byKey(recsKey)).dy;

    // Sisipkan 1 item cart (mendarat di akhir blok cart = sebelum center,
    // di atas viewport).
    hostKey.currentState!.addItem();
    await tester.pump();

    expect(controller.offset, offsetBefore,
        reason: 'scroll offset tidak boleh berubah saat insert sebelum center');
    expect(tester.getTopLeft(find.byKey(recsKey)).dy, closeTo(recsYBefore, 0.5),
        reason:
            'rekomendasi harus tetap di posisi layar yang sama (no loncat)');
  });

  testWidgets(
      'membuka ter-anchor di cart paling atas (offset == minScrollExtent < 0)',
      (tester) async {
    final controller = ScrollController();
    final hostKey = GlobalKey<_HostState>();
    await tester.pumpWidget(_Host(
        key: hostKey, controller: controller, recsKey: const ValueKey('recs')));
    await tester.pumpAndSettle();

    expect(controller.position.minScrollExtent, lessThan(0),
        reason: 'blok cart ada di sisi NEGATIF center');
    expect(controller.offset, closeTo(controller.position.minScrollExtent, 0.5),
        reason:
            'frame awal mendarat di kartu cart paling atas, bukan rekomendasi');
  });

  testWidgets(
      'item terbaru dirender paling BAWAH blok cart (tepat di atas rekomendasi)',
      (tester) async {
    final controller = ScrollController();
    final hostKey = GlobalKey<_HostState>();
    // Cart pendek (3 kartu = 330px < viewport) → semua ter-layout di anchor.
    await tester.pumpWidget(_Host(
        key: hostKey,
        controller: controller,
        recsKey: const ValueKey('recs'),
        initialCount: 3));
    await tester.pumpAndSettle();

    // Terlama (c0) paling atas, terbaru (c2) paling bawah (dekat rekomendasi).
    final y0 = tester.getTopLeft(find.text('cart c0')).dy;
    final y1 = tester.getTopLeft(find.text('cart c1')).dy;
    final y2 = tester.getTopLeft(find.text('cart c2')).dy;
    expect(y0, lessThan(y1));
    expect(y1, lessThan(y2),
        reason:
            'urutan visual: terlama di atas → terbaru di bawah (dekat center)');
  });
}

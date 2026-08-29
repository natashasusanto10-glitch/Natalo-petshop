import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:natalo_petshop_flutter/models/product.dart';
import 'package:natalo_petshop_flutter/screens/cart_screen.dart';
import 'package:natalo_petshop_flutter/state/cart_store.dart';
import 'package:natalo_petshop_flutter/widgets/app_ui.dart';

Product _product({String title = 'Whiskas Tuna 1KG', int stock = 10}) {
  return Product.fromApiJson({
    'id': 'p1',
    'slug': 'p1',
    'name': title,
    'price': 50000,
    'total_stock': stock,
    'has_variants': false,
  });
}

Future<void> _pumpCart(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const MaterialApp(home: CartScreen()));
  // Bounded pump — CartScreen punya shimmer/gambar yang tak pernah settle.
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() async {
    // Tanpa ini SharedPreferences.getInstance() menggantung selamanya di
    // test — cartStore.clear() tak pernah selesai.
    SharedPreferences.setMockInitialValues({});
    await cartStore.clear();
  });

  testWidgets('tombol jumlah menyebut aksi DAN nama produknya',
      (tester) async {
    await cartStore.addProduct(_product(), quantity: 2);
    final handle = tester.ensureSemantics();
    await _pumpCart(tester);

    // Di daftar keranjang semua stepper tampak identik; tanpa nama produk
    // pengguna tak tahu jumlah barang mana yang sedang diubah.
    expect(
      find.bySemanticsLabel('Tambah jumlah Whiskas Tuna 1KG'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Kurangi jumlah Whiskas Tuna 1KG'),
      findsOneWidget,
    );

    handle.dispose();
  });

  testWidgets('saat jumlah 1, tombol kurang berganti label jadi HAPUS',
      (tester) async {
    await cartStore.addProduct(_product(), quantity: 1);

    final handle = tester.ensureSemantics();
    await _pumpCart(tester);

    // Tombol yang sama berubah peran — kalau labelnya tidak ikut berubah,
    // pengguna mengira "mengurangi" padahal barangnya dihapus.
    expect(
      find.bySemanticsLabel('Hapus Whiskas Tuna 1KG dari keranjang'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Kurangi jumlah Whiskas Tuna 1KG'),
      findsNothing,
    );

    handle.dispose();
  });

  testWidgets('batas stok terucap, bukan cuma tombol abu', (tester) async {
    await cartStore.addProduct(_product(stock: 2), quantity: 2);

    final handle = tester.ensureSemantics();
    await _pumpCart(tester);

    expect(
      find.bySemanticsLabel('Jumlah maksimum Whiskas Tuna 1KG tercapai'),
      findsOneWidget,
    );

    handle.dispose();
  });

  testWidgets('area tap stepper >= 44 tanpa membesarkan kotak visual 36',
      (tester) async {
    await cartStore.addProduct(_product(), quantity: 2);
    await _pumpCart(tester);

    final boxes = tester
        .widgetList<AppMinTapTarget>(find.byType(AppMinTapTarget))
        .toList();
    expect(boxes, isNotEmpty, reason: 'stepper harus pakai AppMinTapTarget');

    // Diuji lewat ukuran yang DIRENDER, bukan "sudah dibungkus helper" —
    // AppMinTapTarget gagal diam-diam kalau induknya mengunci tinggi.
    for (final el in find.byType(AppMinTapTarget).evaluate()) {
      expect(el.size!.height, greaterThanOrEqualTo(44),
          reason: 'induk mengunci tinggi? cek Container/SizedBox di atasnya');
      expect(el.size!.width, greaterThanOrEqualTo(36));
    }
  });
}

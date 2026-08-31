import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:natalo_petshop_flutter/models/product.dart';
import 'package:natalo_petshop_flutter/screens/cart_screen.dart';
import 'package:natalo_petshop_flutter/state/cart_store.dart';

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

  testWidgets('tombol jumlah menyebut aksi DAN nama produknya', (tester) async {
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

  testWidgets('area tap kedua tombol >= 44 walau bingkai pil cuma 36',
      (tester) async {
    await cartStore.addProduct(_product(), quantity: 2);
    await _pumpCart(tester);

    // Versi lama tes ini menuntut widget AppMinTapTarget dipakai. Itu menguji
    // CARA, bukan HASIL — dan jadi salah begitu cara mencapai 44px berubah:
    // stepper kini melapis GestureDetector 44px di atas bingkai 36px, yang
    // memberi hasil sama persis tanpa helper itu.
    //
    // Yang diuji sekarang adalah yang benar-benar penting bagi pengguna:
    // ukuran yang DIRENDER. AppMinTapTarget pernah gagal diam-diam saat
    // induknya mengunci tinggi (terukur 34px padahal diminta 44), jadi
    // "sudah dibungkus helper" tak pernah jadi bukti apa pun.
    for (final key in const [
      ValueKey('cart-qty-decrement'),
      ValueKey('cart-qty-increment'),
    ]) {
      final size = tester.getSize(find.byKey(key));
      expect(size.height, greaterThanOrEqualTo(44),
          reason: 'area sentuh $key turun di bawah 44px');
      expect(size.width, greaterThanOrEqualTo(36));
    }

    // Dan bingkainya WAJIB tetap ramping — kalau ia ikut membesar sampai 44,
    // kita kembali ke pil gemuk yang dikeluhkan user.
    final pil = tester.getSize(find.byKey(const ValueKey('cart-qty-pill')));
    expect(pil.height, closeTo(36, 0.5));
  });
}

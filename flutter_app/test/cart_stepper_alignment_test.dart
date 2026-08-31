import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/product.dart';
import 'package:natalo_petshop_flutter/screens/cart_screen.dart';
import 'package:natalo_petshop_flutter/state/cart_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Product _product() => Product.fromApiJson({
      'id': 'p1',
      'slug': 'p1',
      'name': 'Whiskas Tuna 1KG',
      'price': 50000,
      'total_stock': 10,
      'has_variants': false,
    });

void main() {
  testWidgets('angka jumlah SEJAJAR tombol +/− — bukan nangkring di atas',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await cartStore.clear();
    await cartStore.addProduct(_product(), quantity: 5);

    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: CartScreen()));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Regresi #341: pil dinaikkan 36 -> 46 demi area tap, tapi
    // contentPadding TextField masih disetel utk kotak 36 — angka '5'
    // nangkring di atas sementara '+' dan '−' tetap di tengah (laporan
    // user, pembanding Tokopedia). Sumbu tengah ketiganya WAJIB segaris.
    final plusY = tester.getRect(find.text('+')).center.dy;
    final minusY = tester.getRect(find.text('−')).center.dy;
    final qtyY = tester.getRect(find.text('5')).center.dy;

    expect((plusY - minusY).abs(), lessThan(1.0),
        reason: 'tombol + dan − harus segaris (sanity)');
    expect((qtyY - plusY).abs(), lessThan(2.0),
        reason: 'angka jumlah harus setengah-tinggi yang sama dgn +/−; '
            'selisih besar = angka nangkring di atas/bawah pil');

    await cartStore.clear();
    // CartScreen meninggalkan timer internal (debounce/refresh) — habiskan
    // sebelum teardown supaya binding tidak protes '!timersPending'.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('latar angka SAMA dengan latar pil — bukan kotak abu',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await cartStore.clear();
    await cartStore.addProduct(_product(), quantity: 5);

    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: CartScreen()));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Tema global memberi SEMUA kolom input isian #F8FAFC, sementara pilnya
    // putih. Tanpa mematikan isian di kolom ini, abu-nya tercetak di atas
    // pil dan terlihat seperti kotak menempel di belakang angka (laporan
    // user dgn tangkapan layar). `filled: false` WAJIB eksplisit — mewarisi
    // tema berarti mewarisi abu itu.
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byType(CartScreen),
        matching: find.byType(TextField),
      ),
    );
    expect(field.decoration?.filled, isFalse,
        reason: 'kolom jumlah tidak boleh mewarisi isian abu dari tema');
  });

  testWidgets('pil ramping 36 px TAPI area sentuh tetap 44 px', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await cartStore.clear();
    await cartStore.addProduct(_product(), quantity: 5);

    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: CartScreen()));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Inti Usulan B: pil digambar kecil, tombolnya menjulur ke luar bingkai
    // tanpa terlihat. Flutter tidak punya hitSlop, jadi satu-satunya cara
    // adalah memisahkan lapisan visual dari lapisan sentuh — dan itu mudah
    // tergerus lagi kalau tidak dikunci tes.
    //
    // Diukur dari UKURAN YANG DIRENDER, bukan dari 'sudah dibungkus
    // AppMinTapTarget': ConstrainedBox gagal diam-diam kalau induknya
    // mengunci tinggi (pelajaran #341, terukur 34 px padahal minta 44).
    // GestureDetector, BUKAN InkWell: InkWell sengaja dikurung 36px agar
    // riaknya pas dengan bingkai. Lapisan sentuh yang sesungguhnya ada di
    // GestureDetector luar — mengukur InkWell akan melaporkan 36 dan
    // membuat tes ini 'lulus' pada implementasi yang justru salah.
    // Diukur lewat kunci pada lapisan sentuh. Mencari dari teks '+' ke atas
    // akan mendarat di GestureDetector internal milik InkWell — tingginya 36,
    // dan tes akan 'lulus' pada implementasi yang justru salah.
    final tapHeight =
        tester.getSize(find.byKey(const ValueKey('cart-qty-increment'))).height;
    expect(tapHeight, greaterThanOrEqualTo(44.0),
        reason: 'area sentuh tombol + turun di bawah 44 px');

    final pillHeight =
        tester.getSize(find.byKey(const ValueKey('cart-qty-pill'))).height;
    expect(pillHeight, closeTo(36.0, 0.5),
        reason: 'bingkai pil harus tetap ramping 36 px');
    expect(pillHeight, lessThan(tapHeight),
        reason: 'pil wajib LEBIH KECIL dari area sentuh — kalau sama besar, '
            'kita kembali ke pil gemuk 46 px yang dikeluhkan');
  });

  testWidgets('menekan tepat DI LUAR bingkai pil masih menambah jumlah',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await cartStore.clear();
    await cartStore.addProduct(_product(), quantity: 5);

    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: CartScreen()));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Inti dari "pil ramping, sentuh besar": band 4px di atas bingkai TIDAK
    // terlihat bisa ditekan, tapi HARUS bisa. Kalau lapisan sentuh luar
    // hilang (mis. seseorang menyederhanakan jadi satu InkWell 36px),
    // tes ini yang menangkapnya — bukan mata, karena bedanya tak terlihat.
    final pill = tester.getRect(find.byKey(const ValueKey('cart-qty-pill')));
    final plus = tester.getRect(find.text('+'));
    final diLuarBingkai = Offset(plus.center.dx, pill.top - 2);

    expect(diLuarBingkai.dy, lessThan(pill.top),
        reason: 'titik uji harus benar-benar di luar bingkai pil');

    await tester.tapAt(diLuarBingkai);
    await tester.pump(const Duration(milliseconds: 300));

    expect(cartStore.items.first.quantity, 6,
        reason: 'tap di band sentuh tak terlihat harus tetap menambah jumlah');

    await cartStore.clear();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });
}

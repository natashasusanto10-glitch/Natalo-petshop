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
}

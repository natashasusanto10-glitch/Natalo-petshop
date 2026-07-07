import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:natalo_petshop_flutter/models/product.dart';
import 'package:natalo_petshop_flutter/screens/cart_screen.dart';
import 'package:natalo_petshop_flutter/state/cart_store.dart';

// Reproduksi runtime nyata dari bug "page loncat ke bawah saat +Keranjang
// dari grid rekomendasi": seed cart dengan beberapa item (list bisa
// discroll), scroll ke dasar (posisi user melihat area rekomendasi), lalu
// panggil cartStore.addProduct(...) — PERSIS code path yang dipanggil kartu
// rekomendasi saat di-tap (lihat _buildCard.onAddToCart di cart_screen.dart).
// Assertion: offset scroll harus tetap "menempel" di dasar konten baru
// (bukan diam di offset lama, yang berarti konten di atasnya ke-geser turun
// di layar / "loncat").
Product _product(String id) => Product.fromApiJson({
      'id': id,
      'slug': id,
      'name': 'Produk $id',
      'price': 50000,
      'total_stock': 20,
      'has_variants': false,
    });

Future<void> _settle(WidgetTester tester, {int times = 20}) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await cartStore.clear();
  });

  testWidgets(
    'add produk baru dari luar (spt tap kartu rekomendasi) tidak menggeser '
    'konten yang lagi dilihat user saat sudah scroll ke dasar',
    (tester) async {
      // Seed cart dengan cukup banyak item supaya list scrollable.
      for (var i = 0; i < 10; i++) {
        await cartStore.addProduct(_product('seed-$i'));
      }

      await tester.pumpWidget(const MaterialApp(home: CartScreen()));
      await _settle(tester);

      final scrollable = find.byType(Scrollable).first;
      // Scroll ke dasar konten.
      await tester.fling(scrollable, const Offset(0, -3000), 3000);
      await _settle(tester);

      final scrollableState = tester.state<ScrollableState>(scrollable);
      final positionBefore = scrollableState.position;
      final pixelsBefore = positionBefore.pixels;
      final maxExtentBefore = positionBefore.maxScrollExtent;
      final minExtentBefore = positionBefore.minScrollExtent;

      // Sanity: benar-benar di dasar (dalam toleransi) sebelum item baru masuk.
      expect(pixelsBefore, closeTo(maxExtentBefore, 1.0));

      // Simulasikan tap "+Keranjang" di kartu rekomendasi — code path yang
      // sama persis dipanggil oleh _buildCard.onAddToCart.
      await cartStore.addProduct(_product('new-from-recommendation'));

      // Anchor logic jalan di post-frame callback — beri waktu untuk itu.
      await tester.pump();
      await tester.pump();
      await _settle(tester, times: 5);

      final positionAfter = scrollableState.position;

      // CENTER-SLIVER (v171+): cart-items ada di sliver SEBELUM center (sisi
      // NEGATIF), rekomendasi DI/sesudah center (sisi positif). Menambah item
      // cart menumbuhkan sisi NEGATIF (minScrollExtent makin kecil), BUKAN
      // sisi positif → rekomendasi yang dilihat user tidak tergeser. Bebas
      // loncat by-design, bukan aritmetika maxScrollExtent yang rapuh.
      expect(
        positionAfter.minScrollExtent,
        lessThan(minExtentBefore),
        reason: 'blok cart tumbuh di sisi negatif → bukti item baru ke-render',
      );
      expect(
        positionAfter.maxScrollExtent,
        closeTo(maxExtentBefore, 1.0),
        reason: 'sisi rekomendasi (positif) tidak tumbuh → tak ada yang '
            'mendorong konten yang sedang dilihat',
      );
      expect(
        positionAfter.pixels,
        closeTo(pixelsBefore, 1.0),
        reason: 'offset TETAP → rekomendasi yang dilihat TIDAK loncat',
      );

      // Drain debounce timer CartStore._scheduleRemoteSync (800ms) sebelum
      // widget tree di-dispose — bukan bagian dari assertion, cuma cleanup
      // supaya test binding tidak komplain "Timer masih pending".
      await tester.pump(const Duration(milliseconds: 900));
    },
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:natalo_petshop_flutter/models/product.dart';
import 'package:natalo_petshop_flutter/state/cart_store.dart';
import 'package:natalo_petshop_flutter/widgets/added_to_cart_sheet.dart';

Product makeProduct(
  String id, {
  String? name,
  bool hasVariants = false,
  int stock = 10,
  int soldCount = 0,
  num price = 100000,
}) {
  return Product.fromApiJson({
    'id': id,
    'slug': id,
    'name': name ?? 'Produk $id',
    'price': price,
    'image_url': 'https://example.com/$id.jpg',
    'stock': stock,
    'hasVariants': hasVariants,
    'soldCount': soldCount,
  });
}

Future<List<Product>> _emptyFetcher({
  List<String> cartIds = const [],
  List<String> viewedIds = const [],
  List<String> excludeIds = const [],
  int limit = 10,
}) async =>
    const [];

Future<void> pumpSheet(
  WidgetTester tester, {
  Product? product,
  List<Product> initialRelated = const [],
  RecommendationsFetcher? fetcher,
}) async {
  await tester.pumpWidget(MaterialApp(
    routes: {
      '/cart': (_) => const Scaffold(body: Text('CART SCREEN')),
      '/product-detail': (_) => const Scaffold(body: Text('DETAIL SCREEN')),
    },
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => showAddedToCartSheet(
              context,
              product: product ?? makeProduct('main'),
              initialRelated: initialRelated,
              fetchRecommendations: fetcher ?? _emptyFetcher,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await _settle(tester);
}

/// AppProductImage pakai Shimmer.fromColors sebagai placeholder yang
/// animasinya repeat() tanpa henti selama gambar network belum resolve.
/// Di test environment, network image selalu gagal (HttpClient jadi 400),
/// jadi shimmer-nya tidak pernah berhenti berputar dan pumpAndSettle()
/// polos akan timeout terus. Pakai bounded pump loop supaya sheet & async
/// state (mis. _loadCartRecommendations, navigasi) tetap sempat settle
/// tanpa menunggu animasi shimmer yang memang tidak akan pernah selesai.
Future<void> _settle(WidgetTester tester) async {
  // 30 x 100ms = 3s, cukup untuk AppToast.showCartAdded's Future.delayed
  // (duration 1700ms + 300ms) menyelesaikan timernya sebelum widget tree
  // di-dispose, supaya tidak kena "Timer is still pending" assertion.
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await cartStore.clear();
  });

  testWidgets('menampilkan nama produk & konfirmasi masuk keranjang',
      (tester) async {
    await pumpSheet(tester, product: makeProduct('main', name: 'Happy Dog 15kg'));
    expect(find.text('Lengkapi belanjaanmu'), findsOneWidget);
    expect(find.text('Happy Dog 15kg'), findsOneWidget);
    expect(find.text('Masuk ke keranjang!'), findsOneWidget);
  });

  testWidgets('menampilkan carousel rekomendasi saat ada data', (tester) async {
    await pumpSheet(tester,
        initialRelated: [makeProduct('r1', name: 'Rekom Satu')]);
    expect(find.text('Cek keperluan anabulmu yang lain yuk'), findsOneWidget);
    expect(find.text('Rekom Satu'), findsOneWidget);
  });

  testWidgets('carousel disembunyikan saat tidak ada rekomendasi',
      (tester) async {
    await pumpSheet(tester, initialRelated: const []);
    expect(find.text('Cek keperluan anabulmu yang lain yuk'), findsNothing);
    expect(find.text('Masuk ke keranjang!'), findsOneWidget);
    expect(find.byKey(const ValueKey('cek-keranjang-button')), findsOneWidget);
  });

  testWidgets('fetch rekomendasi pakai isi keranjang & refresh carousel',
      (tester) async {
    await cartStore.addProduct(makeProduct('incart', name: 'Di Keranjang'));
    List<String>? capturedCartIds;
    Future<List<Product>> fake({
      List<String> cartIds = const [],
      List<String> viewedIds = const [],
      List<String> excludeIds = const [],
      int limit = 10,
    }) async {
      capturedCartIds = cartIds;
      return [makeProduct('rNew', name: 'Rekom Baru')];
    }

    await pumpSheet(tester,
        initialRelated: [makeProduct('rOld', name: 'Rekom Lama')],
        fetcher: fake);

    expect(capturedCartIds, contains('incart'));
    expect(find.text('Rekom Baru'), findsOneWidget);
    expect(find.text('Rekom Lama'), findsNothing);
  });

  testWidgets('pertahankan initialRelated kalau fetch kosong', (tester) async {
    await pumpSheet(tester,
        initialRelated: [makeProduct('rOld', name: 'Rekom Lama')],
        fetcher: _emptyFetcher);
    expect(find.text('Rekom Lama'), findsOneWidget);
  });

  testWidgets('tombol Cek Keranjang buka halaman cart', (tester) async {
    await pumpSheet(tester, initialRelated: const []);
    await tester.tap(find.byKey(const ValueKey('cek-keranjang-button')));
    await _settle(tester);
    expect(find.text('CART SCREEN'), findsOneWidget);
  });

  testWidgets('+ Keranjang kartu non-varian menambah ke cart & sheet tetap',
      (tester) async {
    await pumpSheet(tester,
        initialRelated: [makeProduct('rec1', name: 'Rekom', hasVariants: false)]);
    await tester.tap(find.byKey(const ValueKey('add-to-cart-rec1')));
    await _settle(tester);
    expect(cartStore.items.any((it) => it.product.id == 'rec1'), isTrue);
    expect(find.text('Masuk ke keranjang!'), findsOneWidget);
  });

  testWidgets('+ Keranjang kartu varian membuka detail produk',
      (tester) async {
    await pumpSheet(tester,
        initialRelated: [makeProduct('recV', name: 'Varian', hasVariants: true)]);
    await tester.tap(find.byKey(const ValueKey('add-to-cart-recV')));
    await _settle(tester);
    expect(find.text('DETAIL SCREEN'), findsOneWidget);
    expect(cartStore.items.any((it) => it.product.id == 'recV'), isFalse);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:natalo_petshop_flutter/features/feed/widgets/feed_link_cart_actions.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/models/product.dart';
import 'package:natalo_petshop_flutter/state/cart_store.dart';

FeedProductLink _link({required bool hasVariants}) => FeedProductLink(
      id: 'p1',
      slug: 'makanan-kucing',
      name: 'Makanan Kucing',
      price: 100000,
      stock: 5,
      hasVariants: hasVariants,
    );

Product _variantProduct() {
  const size = ProductVariantAttribute(
    id: 'attr-size',
    name: 'Ukuran',
    options: [VariantOption(id: 'o-1kg', value: '1kg')],
  );
  return Product(
    id: 'p1',
    slug: 'makanan-kucing',
    title: 'Makanan Kucing',
    category: 'Makanan',
    brand: 'Natalo',
    imageUrl: '',
    price: 100000,
    rating: 0,
    reviewCount: 0,
    stock: 0,
    description: '',
    hasVariants: true,
    variantAttrs: const [size],
    variants: const [
      ProductVariant(
        id: 'v-1kg', price: 90000, stock: 5, optionIds: ['o-1kg'],
      ),
    ],
  );
}

class _RecordingObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushed = [];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
    super.didPush(route, previousRoute);
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await cartStore.clear();
  });

  testWidgets('produk NON-varian → langsung masuk cart, tak buka sheet',
      (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => addFeedLinkToCart(
                context,
                _link(hasVariants: false),
                productFetcher: (_) async => _variantProduct(),
              ),
              child: const Text('add'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('add'));
    await tester.pump();

    expect(find.text('Variasi Produk'), findsNothing);
    expect(cartStore.items.length, 1);

    // Biarkan timer auto-dismiss toast selesai supaya tak ada Timer pending
    // saat widget tree dibuang di akhir test.
    await tester.pump(const Duration(milliseconds: 2100));
  });

  testWidgets('produk BERVARIAN → buka sheet varian (bukan navigasi)',
      (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final observer = _RecordingObserver();
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [observer],
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => addFeedLinkToCart(
                context,
                _link(hasVariants: true),
                productFetcher: (_) async => _variantProduct(),
              ),
              child: const Text('add'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('add'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }

    // Sheet varian terbuka.
    expect(find.text('Variasi Produk'), findsOneWidget);
    // Tidak ada push ke named route '/product-detail'.
    expect(
      observer.pushed.any((r) => r.settings.name == '/product-detail'),
      isFalse,
    );
    // Belum ada item cart (belum confirm varian).
    expect(cartStore.items, isEmpty);
  });
}

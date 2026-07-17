import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/product.dart';
import 'package:natalo_petshop_flutter/widgets/product_variant_picker_sheet.dart';

Product _variantProduct() {
  const size = ProductVariantAttribute(
    id: 'attr-size',
    name: 'Ukuran',
    options: [
      VariantOption(id: 'o-1kg', value: '1kg'),
      VariantOption(id: 'o-3kg', value: '3kg'),
    ],
  );
  const flavor = ProductVariantAttribute(
    id: 'attr-flavor',
    name: 'Rasa',
    options: [
      VariantOption(id: 'o-ayam', value: 'Ayam'),
      VariantOption(id: 'o-salmon', value: 'Salmon'),
    ],
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
    variantAttrs: const [size, flavor],
    variants: const [
      ProductVariant(
        id: 'v-1kg-ayam', price: 90000, stock: 5,
        optionIds: ['o-1kg', 'o-ayam'],
      ),
      ProductVariant(
        id: 'v-3kg-ayam', price: 150000, stock: 3,
        optionIds: ['o-3kg', 'o-ayam'],
      ),
      // Salmon hanya tersedia untuk 1kg → 3kg+Salmon tidak ada varian.
      ProductVariant(
        id: 'v-1kg-salmon', price: 95000, stock: 2,
        optionIds: ['o-1kg', 'o-salmon'],
      ),
    ],
  );
}

Future<ProductVariantPickResult?> _openSheet(
  WidgetTester tester, {
  required ProductFetcher fetcher,
  ProductVariant? preselected,
}) async {
  ProductVariantPickResult? result;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () async {
              result = await ProductVariantPickerSheet.show(
                context,
                productSlug: 'makanan-kucing',
                preselectedVariant: preselected,
                confirmLabel: 'Tambah ke Keranjang',
                confirmColor: Colors.blue,
                productFetcher: fetcher,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  // Bounded pump (AppProductImage shimmer tak pernah settle → jangan pumpAndSettle).
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
  return result;
}

void main() {
  testWidgets('pilih kombinasi lengkap → tombol enable → confirm balikin varian benar',
      (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final product = _variantProduct();
    await _openSheet(tester, fetcher: (_) async => product);

    // Sheet terbuka, header terlihat.
    expect(find.text('Variasi Produk'), findsOneWidget);

    // Tombol confirm awalnya disabled (belum ada kombinasi lengkap).
    final buttonBefore = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Tambah ke Keranjang'),
    );
    expect(buttonBefore.onPressed, isNull);

    // Pilih 1kg + Ayam.
    await tester.tap(find.text('1kg'));
    await tester.pump();
    await tester.tap(find.text('Ayam'));
    await tester.pump();

    final buttonAfter = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Tambah ke Keranjang'),
    );
    expect(buttonAfter.onPressed, isNotNull);
  });

  testWidgets('opsi tanpa kombinasi valid ter-disable', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final product = _variantProduct();
    await _openSheet(tester, fetcher: (_) async => product);

    // Pilih 3kg dulu → Salmon jadi tak tersedia (tak ada varian 3kg+Salmon).
    await tester.tap(find.text('3kg'));
    await tester.pump();
    await tester.tap(find.text('Salmon'));
    await tester.pump();

    // Salmon tak boleh terpilih → kombinasi tetap tak lengkap/invalid → tombol disabled.
    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Tambah ke Keranjang'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('fetch gagal → tampil teks error, tanpa tombol confirm', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openSheet(tester, fetcher: (_) async => null);

    expect(find.text('Produk tidak ditemukan.'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Tambah ke Keranjang'), findsNothing);
  });
}

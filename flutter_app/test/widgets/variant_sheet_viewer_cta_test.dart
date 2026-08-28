import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/product.dart';
import 'package:natalo_petshop_flutter/widgets/product_variant_picker_sheet.dart';

const _rasa = ProductVariantAttribute(
  id: 'attr-rasa',
  name: 'Rasa',
  options: [VariantOption(id: 'o-tuna', value: 'Real Tuna')],
);

const _tuna = ProductVariant(
  id: 'v-tuna',
  price: 55000,
  stock: 5,
  imageUrl: 'tuna.jpg',
  optionIds: ['o-tuna'],
);

Product _product() => Product(
      id: 'p1',
      slug: 'catto-mother-kitten',
      title: 'Catto Mother & Kitten',
      category: 'Makanan Kucing',
      brand: 'Catto',
      imageUrl: 'main.jpg',
      price: 55000,
      rating: 0,
      reviewCount: 0,
      stock: 0,
      description: '',
      hasVariants: true,
      variantAttrs: const [_rasa],
      variants: const [_tuna],
    );

void main() {
  testWidgets(
      'CTA "+ Keranjang" di viewer mengembalikan hasil pilih & tidak menendang '
      'user keluar dari layar induk', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final product = _product();
    ProductVariantPickResult? result;
    var sheetClosed = false;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await ProductVariantPickerSheet.show(
                  context,
                  productSlug: product.slug,
                  preselectedVariant: _tuna,
                  confirmLabel: 'Tambah ke Keranjang',
                  confirmColor: Colors.blue,
                  productFetcher: (_) async => product,
                );
                sheetClosed = true;
              },
              child: const Text('layar-induk'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('layar-induk'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }

    // Buka viewer lewat tombol perbesar di foto hero.
    await tester.tap(find.byIcon(Icons.open_in_full_rounded));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(find.text('+ Keranjang'), findsOneWidget,
        reason: 'mini product bar viewer harus tampil');

    // REGRESI: viewer sudah mem-pop dirinya sendiri di _handleCta SEBELUM
    // memanggil onAddToCart (image_viewer_screen.dart). Kalau sheet ikut
    // mem-pop dua kali, pop kedua menendang layar induk dari stack dan
    // sheet balik null — produk tidak pernah masuk keranjang.
    await tester.tap(find.text('+ Keranjang'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }

    expect(sheetClosed, isTrue, reason: 'sheet harus tertutup');
    expect(result, isNotNull,
        reason: 'sheet WAJIB balik hasil pilih, bukan null');
    expect(result!.variant.id, 'v-tuna');
    expect(find.text('layar-induk'), findsOneWidget,
        reason: 'layar induk TIDAK boleh ikut ter-pop');
  });
}

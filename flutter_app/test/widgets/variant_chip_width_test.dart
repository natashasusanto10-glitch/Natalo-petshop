import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/product.dart';
import 'package:natalo_petshop_flutter/widgets/product_variant_picker_sheet.dart';

// Produk 2 atribut => chip TANPA thumbnail (label pendek murni), bentuk
// paling ketat untuk menguji "memeluk isi".
Product _product() {
  return Product(
    id: 'p1',
    slug: 's',
    title: 'T',
    category: 'C',
    brand: 'B',
    imageUrl: 'main.jpg',
    price: 1,
    rating: 0,
    reviewCount: 0,
    stock: 0,
    description: '',
    hasVariants: true,
    variantAttrs: const [
      ProductVariantAttribute(id: 'a1', name: 'Rasa', options: [
        VariantOption(id: 'o1', value: 'Feel'),
        VariantOption(id: 'o2', value: 'Taste'),
      ]),
      ProductVariantAttribute(id: 'a2', name: 'Ukuran', options: [
        VariantOption(id: 'o3', value: '85gr'),
      ]),
    ],
    variants: const [
      ProductVariant(id: 'v1', price: 1, stock: 5, optionIds: ['o1', 'o3']),
      ProductVariant(id: 'v2', price: 1, stock: 5, optionIds: ['o2', 'o3']),
    ],
  );
}

Future<void> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (c) => Center(
          child: ElevatedButton(
            onPressed: () => ProductVariantPickerSheet.show(
              c,
              productSlug: 's',
              confirmLabel: 'x',
              confirmColor: Colors.blue,
              productFetcher: (_) async => _product(),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

void main() {
  testWidgets('chip memeluk isi — tidak selebar sheet', (tester) async {
    await _open(tester);

    // Regresi: `Container(alignment: Alignment.center)` bikin Container
    // memuai memenuhi lebar Wrap, jadi tiap chip melar selebar sheet dan
    // menumpuk satu per baris. Tokopedia: chip memeluk teks, 2 per baris.
    final chip = find.ancestor(
      of: find.text('Feel'),
      matching: find.byType(InkWell),
    );
    final chipWidth = tester.getSize(chip).width;
    // "Feel" + padding harusnya jauh di bawah setengah lebar sheet (~500).
    expect(chipWidth, lessThan(200),
        reason: 'chip melar selebar sheet — cek alignment Container');
  });

  testWidgets('dua chip pendek muat satu baris', (tester) async {
    await _open(tester);

    final feel = tester.getRect(
        find.ancestor(of: find.text('Feel'), matching: find.byType(InkWell)));
    final taste = tester.getRect(
        find.ancestor(of: find.text('Taste'), matching: find.byType(InkWell)));
    // Kalau memeluk isi, Feel & Taste berbagi baris (top sama).
    expect((feel.top - taste.top).abs(), lessThan(1),
        reason: 'Feel & Taste harus sebaris, bukan menumpuk');
  });
}

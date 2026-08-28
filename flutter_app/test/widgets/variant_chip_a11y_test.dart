import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/product.dart';
import 'package:natalo_petshop_flutter/widgets/product_variant_picker_sheet.dart';

/// Produk BERATRIBUT TUNGGAL — satu-satunya bentuk yang dapat thumbnail.
Product _singleAttrProduct() {
  const rasa = ProductVariantAttribute(
    id: 'attr-rasa',
    name: 'Rasa',
    options: [
      VariantOption(id: 'o-tuna', value: 'Real Tuna'),
      VariantOption(id: 'o-salmon', value: 'Real Salmon'),
      VariantOption(id: 'o-sarden', value: 'Sarden'),
      VariantOption(id: 'o-lele', value: 'Lele'),
    ],
  );
  return Product(
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
    variantAttrs: const [rasa],
    variants: const [
      ProductVariant(
        id: 'v-tuna',
        price: 55000,
        stock: 5,
        imageUrl: 'tuna.jpg',
        optionIds: ['o-tuna'],
      ),
      ProductVariant(
        id: 'v-salmon',
        price: 55000,
        stock: 2,
        imageUrl: 'salmon.jpg',
        optionIds: ['o-salmon'],
      ),
      // Sarden di-nonaktifkan → chip harus disabled + dicoret.
      ProductVariant(
        id: 'v-sarden',
        price: 55000,
        stock: 0,
        imageUrl: 'sarden.jpg',
        optionIds: ['o-sarden'],
        isActive: false,
      ),
      // Aktif TAPI stok habis — jalur berbeda dari isActive:false.
      ProductVariant(
        id: 'v-lele',
        price: 55000,
        stock: 0,
        imageUrl: 'lele.jpg',
        optionIds: ['o-lele'],
      ),
    ],
  );
}

Future<void> _openSheet(WidgetTester tester, Product product) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => ProductVariantPickerSheet.show(
              context,
              productSlug: product.slug,
              confirmLabel: 'Tambah ke Keranjang',
              confirmColor: Colors.blue,
              productFetcher: (_) async => product,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  // Bounded pump: AppProductImage shimmer tak pernah settle.
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

void main() {
  testWidgets('chip varian punya tinggi tap minimal 44', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openSheet(tester, _singleAttrProduct());

    // Regresi: chip dulu cuma GestureDetector setinggi ~34px — di bawah
    // ambang 44 dan tanpa umpan balik tekan.
    final chip = find.ancestor(
      of: find.text('Real Tuna'),
      matching: find.byType(InkWell),
    );
    expect(chip, findsOneWidget);
    expect(tester.getSize(chip).height, greaterThanOrEqualTo(44));
  });

  testWidgets('chip tersedia punya semantics button + enabled', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openSheet(tester, _singleAttrProduct());

    expect(
      tester.getSemantics(find.text('Real Tuna')),
      matchesSemantics(
        label: 'Real Tuna',
        isButton: true,
        isEnabled: true,
        hasEnabledState: true,
        hasSelectedState: true,
        hasTapAction: true,
      ),
    );
  });

  testWidgets('varian habis: semantics menyebut stok habis & tak bisa ditap',
      (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openSheet(tester, _singleAttrProduct());

    final node = tester.getSemantics(find.text('Sarden'));
    expect(node.label, 'Sarden, stok habis');
    expect(node.hasFlag(SemanticsFlag.isEnabled), isFalse);
  });

  testWidgets('tombol perbesar foto punya label semantics', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openSheet(tester, _singleAttrProduct());

    expect(
      tester.getSemantics(find.byIcon(Icons.open_in_full_rounded)).label,
      'Perbesar foto produk',
    );
  });

  testWidgets('varian AKTIF tapi stok 0 tidak bisa dipilih', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openSheet(tester, _singleAttrProduct());

    // Regresi: gate lama cuma cek isActive, jadi varian sold-out tampil
    // sebagai chip normal, bisa dipilih, dan lolos ke keranjang —
    // cart_store tidak menahannya karena stok 0 di sana berarti
    // "tidak diketahui", bukan "habis".
    final node = tester.getSemantics(find.text('Lele'));
    expect(node.label, 'Lele, stok habis');
    expect(node.hasFlag(SemanticsFlag.isEnabled), isFalse);
  });

  testWidgets('chip tanpa thumbnail: isi & border setinggi sama (tanpa halo)',
      (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openSheet(tester, _singleAttrProduct());

    // Regresi: ambang 44 dulu dipasang lewat AppMinTapTarget pembungkus,
    // jadi Material (pemegang warna isi) memuai ke 44 sementara pil
    // ber-border tetap 33 → pita warna 5,5px di atas & bawah border.
    final ink = find.ancestor(
      of: find.text('Real Tuna'),
      matching: find.byType(InkWell),
    );
    final borderBox = find
        .ancestor(of: find.text('Real Tuna'), matching: find.byType(Container))
        .first;
    expect(tester.getSize(ink).height, tester.getSize(borderBox).height);
  });
}
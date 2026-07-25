import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/widgets/care_product_picker.dart';
import 'package:natalo_petshop_flutter/models/pet_care_record.dart';

void main() {
  testWidgets('renders product list with top badge and manual toggle',
      (tester) async {
    final products = [
      const CareProduct(
          id: 'p1',
          name: 'Drontal',
          effectivePrice: 45000,
          inStock: true,
          instruction: '1/2 tablet'),
      const CareProduct(
          id: 'p2', name: 'Caniverm', effectivePrice: 15000, inStock: true),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CareProductPicker.debugWithProducts(
          products: products,
          onChanged: (_) {},
        ),
      ),
    ));
    expect(find.text('Drontal'), findsOneWidget);
    expect(find.text('Caniverm'), findsOneWidget);
    expect(find.text('Paling sesuai'), findsOneWidget);
    expect(find.textContaining('Ketik manual'), findsOneWidget);
  });

  testWidgets(
      'real constructor shows badge when weightKg is provided (non-null)',
      (tester) async {
    final products = [
      const CareProduct(
          id: 'p1',
          name: 'Drontal',
          effectivePrice: 45000,
          inStock: true,
          instruction: '1/2 tablet'),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CareProductPicker(
          category: PetCareCategory.deworm,
          species: 'dog',
          weightKg: 5.0,
          onChanged: (_) {},
          recommendationFetcher: ({
            required PetCareCategory category,
            required String species,
            double? weightKg,
          }) async =>
              products,
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('Drontal'), findsOneWidget);
    expect(find.text('Paling sesuai'), findsOneWidget);
  });

  testWidgets('real constructor hides badge when weightKg is null',
      (tester) async {
    final products = [
      const CareProduct(
          id: 'p1',
          name: 'Drontal',
          effectivePrice: 45000,
          inStock: true,
          instruction: '1/2 tablet'),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CareProductPicker(
          category: PetCareCategory.deworm,
          species: 'dog',
          weightKg: null,
          onChanged: (_) {},
          recommendationFetcher: ({
            required PetCareCategory category,
            required String species,
            double? weightKg,
          }) async =>
              products,
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('Drontal'), findsOneWidget);
    expect(find.text('Paling sesuai'), findsNothing);
  });

  testWidgets(
      'falls back to unfiltered category list when weighted fetch returns empty',
      (tester) async {
    final unfiltered = [
      const CareProduct(
          id: 'p1',
          name: 'Combantrin Kucing',
          effectivePrice: 30000,
          inStock: true,
          instruction: 'Sesuai berat'),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CareProductPicker(
          category: PetCareCategory.deworm,
          species: 'cat',
          weightKg: 4.0,
          onChanged: (_) {},
          recommendationFetcher: ({
            required PetCareCategory category,
            required String species,
            double? weightKg,
          }) async =>
              weightKg != null ? <CareProduct>[] : unfiltered,
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('Combantrin Kucing'), findsOneWidget);
    expect(find.text('Paling sesuai'), findsNothing);
    expect(find.textContaining('Ketik manual'), findsOneWidget);
  });

  testWidgets('harga diformat rupiah, bukan angka mentah', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CareProductPicker.debugWithProducts(
          products: const [
            CareProduct(
                id: 'p1', name: 'Drontal', effectivePrice: 45000, inStock: true),
          ],
          onChanged: (_) {},
        ),
      ),
    ));
    expect(find.text('Rp45.000'), findsOneWidget);
    expect(find.text('Rp45000'), findsNothing);
  });

  testWidgets('produk stok habis: label jelas, tidak bisa dipilih',
      (tester) async {
    CareSelection? emitted;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CareProductPicker.debugWithProducts(
          products: const [
            CareProduct(
                id: 'p1', name: 'Drontal', effectivePrice: 45000, inStock: false),
          ],
          onChanged: (s) => emitted = s,
        ),
      ),
    ));

    expect(find.text('Stok habis'), findsOneWidget);
    // Harga tidak ditampilkan utk produk habis — yang penting statusnya.
    expect(find.text('Rp45.000'), findsNothing);

    await tester.tap(find.text('Drontal'));
    await tester.pump();
    expect(emitted, isNull,
        reason: 'produk habis tak boleh terpilih (disabled state)');
  });

  testWidgets('dosis tampil di baris produk saat dipilih, tanpa blok biru dobel',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CareProductPicker.debugWithProducts(
          products: const [
            CareProduct(
                id: 'p1',
                name: 'Drontal',
                effectivePrice: 45000,
                inStock: true,
                instruction: '1 tablet per 4 kg'),
          ],
          onChanged: (_) {},
        ),
      ),
    ));

    // Sebelum dipilih: catatan dosis generik yang tampil.
    expect(find.textContaining('dihitung per kg berat badan'), findsOneWidget);
    expect(find.text('1 tablet per 4 kg'), findsNothing);

    await tester.tap(find.text('Drontal'));
    await tester.pumpAndSettle();

    expect(find.text('1 tablet per 4 kg'), findsOneWidget);
    expect(find.textContaining('dihitung per kg berat badan'), findsNothing,
        reason: 'anjuran sudah menempel di produk terpilih, jangan diulang');
  });

  testWidgets('mode manual punya label terlihat, bukan placeholder saja',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CareProductPicker.debugWithProducts(
          products: const [],
          onChanged: (_) {},
        ),
      ),
    ));

    await tester.tap(find.textContaining('Ketik manual'));
    await tester.pumpAndSettle();

    expect(find.text('Nama brand'), findsOneWidget);
    expect(find.text('Aturan pakai (opsional)'), findsOneWidget);
  });
}

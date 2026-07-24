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
}

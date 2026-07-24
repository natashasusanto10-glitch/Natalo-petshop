import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/pet.dart';
import 'package:natalo_petshop_flutter/screens/pet_care_form_screen.dart';
import 'package:natalo_petshop_flutter/widgets/care_product_picker.dart';

void main() {
  final pet = Pet(
    id: 'pet1',
    name: 'Bobby',
    type: 'Anjing',
    weightKg: 4.2,
  );

  testWidgets(
      'deworm shows weight + product picker, grooming shows place',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: PetCareFormScreen(pet: pet),
    ));
    // Bounded pump loop instead of pumpAndSettle (shimmer/network never settles).
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    await tester.tap(find.text('Obat Cacing'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.textContaining('Berat'), findsWidgets);
    expect(find.byType(CareProductPicker), findsOneWidget);

    await tester.tap(find.text('Grooming'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.textContaining('Tempat grooming'), findsOneWidget);
    expect(find.byType(CareProductPicker), findsNothing);
  });
}

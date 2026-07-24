import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/pet_care_record.dart';

void main() {
  test('PetCareRecord parses new optional fields', () {
    final r = PetCareRecord.fromJson({
      'id': 'r1', 'category': 'deworm', 'doneAt': '2026-07-24T00:00:00.000Z',
      'weightKg': 4.5, 'brandText': 'VermiPet', 'place': null,
    });
    expect(r.weightKg, 4.5);
    expect(r.brandText, 'VermiPet');
    expect(r.place, isNull);
  });

  test('CareProduct.fromJson maps fields', () {
    final p = CareProduct.fromJson({
      'id': 'p1', 'name': 'Drontal', 'imageUrl': 'x.jpg',
      'effectivePrice': 45000, 'inStock': true, 'instruction': '1/2 tablet',
    });
    expect(p.effectivePrice, 45000);
    expect(p.inStock, true);
    expect(p.instruction, '1/2 tablet');
  });
}

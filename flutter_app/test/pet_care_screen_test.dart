import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/pet_care_record.dart';
import 'package:natalo_petshop_flutter/screens/pet_care_screen.dart';

void main() {
  testWidgets('overdue schedule banner label is SUDAH LEWAT JADWAL',
      (tester) async {
    final overdue = PetSchedule(
      recordId: 'r1',
      category: PetCareCategory.vaccine,
      nextDueAt: DateTime.now().subtract(const Duration(days: 14)),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: PetCareBanner(schedule: overdue, onMarkDone: () {})),
    ));
    expect(find.text('SUDAH LEWAT JADWAL'), findsOneWidget);
    expect(find.text('JADWAL TERDEKAT'), findsNothing);
  });

  testWidgets('soon schedule banner label is JADWAL TERDEKAT', (tester) async {
    final soon = PetSchedule(
      recordId: 'r2',
      category: PetCareCategory.grooming,
      nextDueAt: DateTime.now().add(const Duration(days: 5)),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: PetCareBanner(schedule: soon, onMarkDone: () {})),
    ));
    expect(find.text('JADWAL TERDEKAT'), findsOneWidget);
    expect(find.text('SUDAH LEWAT JADWAL'), findsNothing);
  });
}

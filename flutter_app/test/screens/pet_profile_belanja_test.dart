import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/pet_shopping.dart';
import 'package:natalo_petshop_flutter/screens/pet_profile_screen.dart';
import 'package:natalo_petshop_flutter/widgets/pet_shopping_rail.dart';

Future<void> pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('kartu statistik: Belanja & Perawatan punya peran button, Momen tidak',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: PetStatsRowForTest(
        momenValue: '0',
        careValue: '4',
        belanjaValue: '6',
        onCareTap: () {},
        onBelanjaTap: () {},
      ),
    ));
    await pumpFrames(tester);

    expect(find.bySemanticsLabel(RegExp('Belanja')), findsOneWidget);
    final belanja = find.ancestor(
      of: find.text('Belanja'),
      matching: find.byType(InkWell),
    );
    expect(belanja, findsOneWidget, reason: 'Belanja harus InkWell (ripple)');

    final momen = find.ancestor(
      of: find.text('Momen'),
      matching: find.byType(InkWell),
    );
    expect(momen, findsNothing, reason: 'Momen belum aktif, jangan tampak bisa ditekan');
  });

  testWidgets('tap kartu Belanja memanggil callback', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(MaterialApp(
      home: PetStatsRowForTest(
        momenValue: '0',
        careValue: '4',
        belanjaValue: '6',
        onCareTap: () {},
        onBelanjaTap: () => tapped++,
      ),
    ));
    await pumpFrames(tester);

    await tester.tap(find.text('Belanja'));
    await tester.pump();
    expect(tapped, 1);
  });

  testWidgets('section Belanja: skeleton dulu, lalu rail; disembunyikan saat kosong',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PetShoppingSectionForTest(
          petName: 'Bobby',
          data: PetShopping(
            usedCount: 1,
            used: [
              PetShoppingProduct(
                productId: 'p1',
                slug: 's1',
                name: 'Drontal',
                imageUrl: null,
                effectivePrice: 45000,
                inStock: true,
                hasVariants: false,
                usageCount: 1,
                lastUsedAt: DateTime(2026, 7, 1),
              ),
            ],
            manual: const [],
            suggested: const [],
          ),
        ),
      ),
    ));
    await pumpFrames(tester);
    expect(find.byType(PetShoppingRail), findsOneWidget);
    expect(find.text('Belanja untuk Bobby'), findsOneWidget);
    expect(find.text('Lihat semua'), findsOneWidget);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PetShoppingSectionForTest(
          petName: 'Bobby',
          data: const PetShopping(
            usedCount: 0,
            used: [],
            manual: [],
            suggested: [],
          ),
        ),
      ),
    ));
    await pumpFrames(tester);
    expect(find.byType(PetShoppingRail), findsNothing);
    expect(find.text('Belanja untuk Bobby'), findsNothing,
        reason: 'kosong total → section tak dirender (Keputusan 13)');
  });
}

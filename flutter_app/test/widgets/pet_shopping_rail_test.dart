import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/pet_shopping.dart';
import 'package:natalo_petshop_flutter/widgets/pet_shopping_rail.dart';

PetShoppingProduct p(String name, {bool used = true}) => PetShoppingProduct(
      productId: 'id-$name',
      slug: 'slug-$name',
      name: name,
      imageUrl: 'https://cdn/$name.jpg',
      effectivePrice: 45000,
      inStock: true,
      hasVariants: false,
      usageCount: used ? 2 : null,
      lastUsedAt: used ? DateTime(2026, 4, 25) : null,
    );

Future<void> pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('harga diformat rupiah, bukan angka mentah', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PetShoppingRail(
          used: [p('Drontal')],
          suggested: const [],
          onTapProduct: (_) {},
        ),
      ),
    ));
    await pumpFrames(tester);
    expect(find.text('Rp45.000'), findsOneWidget);
    expect(find.text('Rp45000'), findsNothing);
  });

  testWidgets('kartu saran diberi badge, kartu fakta tidak', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PetShoppingRail(
          used: [p('Drontal')],
          suggested: [p('Snack', used: false)],
          onTapProduct: (_) {},
        ),
      ),
    ));
    await pumpFrames(tester);
    expect(find.text('Saran'), findsOneWidget);
  });

  testWidgets('nama panjang dibatasi 2 baris + ellipsis', (tester) async {
    const long =
        'Drontal Plus Tasty Dog Bentuk TULANG Obat Cacing Anjing per tablet untuk 10KG berat badan';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PetShoppingRail(
          used: [
            PetShoppingProduct(
              productId: 'p1',
              slug: 's1',
              name: long,
              imageUrl: null,
              effectivePrice: 34800,
              inStock: true,
              hasVariants: false,
              usageCount: 1,
              lastUsedAt: DateTime(2026, 7, 1),
            ),
          ],
          suggested: const [],
          onTapProduct: (_) {},
        ),
      ),
    ));
    await pumpFrames(tester);
    final text = tester.widget<Text>(find.text(long));
    expect(text.maxLines, 2);
    expect(text.overflow, TextOverflow.ellipsis);
  });

  testWidgets('tap kartu memanggil onTapProduct dengan produk yang benar',
      (tester) async {
    PetShoppingProduct? tapped;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PetShoppingRail(
          used: [p('Drontal')],
          suggested: const [],
          onTapProduct: (x) => tapped = x,
        ),
      ),
    ));
    await pumpFrames(tester);
    await tester.tap(find.text('Drontal'));
    await tester.pump();
    expect(tapped?.slug, 'slug-Drontal');
  });

  testWidgets('skeleton punya tinggi SAMA dengan rail terisi', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: PetShoppingRailSkeleton()),
    ));
    await pumpFrames(tester);
    final skeletonHeight =
        tester.getSize(find.byType(PetShoppingRailSkeleton)).height;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PetShoppingRail(
          used: [p('Drontal')],
          suggested: const [],
          onTapProduct: (_) {},
        ),
      ),
    ));
    await pumpFrames(tester);
    final railHeight = tester.getSize(find.byType(PetShoppingRail)).height;

    expect(skeletonHeight, railHeight,
        reason: 'tinggi harus identik supaya profil tidak melonjak saat data tiba');
    expect(railHeight, kPetShoppingRailHeight);
  });
}

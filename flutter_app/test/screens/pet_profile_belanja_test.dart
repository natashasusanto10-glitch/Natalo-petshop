import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/pet_shopping.dart';
import 'package:natalo_petshop_flutter/screens/pet_profile_screen.dart';
import 'package:natalo_petshop_flutter/widgets/compact_commerce_product_card.dart'
    show commerceGridSurfaceTint;
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

  testWidgets(
      'section Belanja: histori manual-only tampilkan header+Lihat semua tanpa rail kosong',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PetShoppingSectionForTest(
          petName: 'Bobby',
          data: PetShopping(
            usedCount: 0,
            used: const [],
            manual: [
              PetShoppingManual(
                brandText: 'Bravecto',
                usageCount: 1,
                lastUsedAt: DateTime(2026, 7, 1),
              ),
            ],
            suggested: const [],
          ),
        ),
      ),
    ));
    await pumpFrames(tester);

    expect(find.text('Belanja untuk Bobby'), findsOneWidget,
        reason: 'histori manual tetap data nyata, section harus tampak');
    expect(find.text('Lihat semua'), findsOneWidget);
    expect(find.byType(PetShoppingRail), findsNothing,
        reason: 'rail hanya render used/suggested, jangan tampil kosong');
  });

  testWidgets('rail Belanja di profil duduk di atas strip abu',
      (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (c) {
          ctx = c;
          return SingleChildScrollView(
            // PetShoppingSectionForTest HANYA menerima petName & data —
            // callback-nya sudah di-hardcode no-op di dalam wrapper, jadi
            // JANGAN kirim onSeeAll/onTapProduct (compile error).
            child: PetShoppingSectionForTest(
              petName: 'Didi',
              data: PetShopping(
                usedCount: 0,
                used: const [],
                manual: const [],
                suggested: [
                  PetShoppingProduct(
                    productId: 'p1',
                    slug: 'kaniva',
                    name: 'Kaniva Dog',
                    // imageUrl null: URL http memicu Shimmer yang tak pernah
                    // settle di widget test (gotcha repo).
                    imageUrl: null,
                    effectivePrice: 335000,
                    inStock: true,
                    hasVariants: false,
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    ));
    await tester.pump();

    final expected = commerceGridSurfaceTint(ctx);
    final tinted = tester.widgetList<Container>(find.byType(Container)).where(
          (c) =>
              c.decoration is BoxDecoration &&
              (c.decoration as BoxDecoration).color == expected,
        );
    expect(tinted, isNotEmpty,
        reason:
            'di halaman profil berlatar putih, kartu putih tanpa kanal abu '
            'tidak terbaca sebagai kartu');
  });

  testWidgets('placeholder Segera hadir menyebut Momen + nama pet',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: PetComingSoonCardForTest(petName: 'Didi')),
    ));
    expect(find.text('Segera hadir'), findsOneWidget);
    expect(find.text('Momen Didi akan muncul di sini.'), findsOneWidget);
  });

  testWidgets('placeholder TIDAK lagi menyebut Belanja/Journey',
      (tester) async {
    // Belanja sudah live tepat di atas kartu ini — menjanjikannya
    // "segera hadir" saling bertentangan dengan UI di atasnya.
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: PetComingSoonCardForTest(petName: 'Didi')),
    ));
    expect(find.textContaining('Belanja'), findsNothing);
    expect(find.textContaining('Journey'), findsNothing);
  });
}

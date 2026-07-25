import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/pet_shopping.dart';
import 'package:natalo_petshop_flutter/screens/pet_shopping_screen.dart';

PetShoppingProduct used(String name) => PetShoppingProduct(
      productId: 'id-$name',
      slug: 'slug-$name',
      name: name,
      imageUrl: null,
      effectivePrice: 45000,
      inStock: true,
      hasVariants: false,
      usageCount: 2,
      lastUsedAt: DateTime(2026, 4, 25),
    );

PetShoppingProduct suggestion(String name) => PetShoppingProduct(
      productId: 'id-$name',
      slug: 'slug-$name',
      name: name,
      imageUrl: null,
      effectivePrice: 28000,
      inStock: true,
      hasVariants: false,
    );

Future<void> pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Widget wrap(PetShopping data) => MaterialApp(
      home: PetShoppingScreen(
        petId: 'pet1',
        petName: 'Bobby',
        fetcher: (_) async => data,
      ),
    );

void main() {
  // Konten dua-grup (kartu saran GridView childAspectRatio 0.72) lebih
  // tinggi dari viewport default flutter_test (800x600), jadi CTA di bawah
  // grup saran tak ter-mount (sliver lazy-build di luar cacheExtent) tanpa
  // viewport lebih tinggi. Pola sama dipakai di
  // member_post_detail_comment_identity_test.dart.
  Future<void> useTallViewport(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('dua grup tampil dengan judul memuat nama pet', (tester) async {
    await useTallViewport(tester);
    await tester.pumpWidget(wrap(PetShopping(
      usedCount: 1,
      used: [used('Drontal')],
      manual: const [],
      suggested: [suggestion('Snack Dental')],
    )));
    await pumpFrames(tester);

    expect(find.text('Pernah dipakai untuk Bobby'), findsOneWidget);
    expect(find.text('Mungkin cocok untuk Bobby'), findsOneWidget);
    expect(find.text('Drontal'), findsOneWidget);
    expect(find.text('Snack Dental'), findsOneWidget);
  });

  testWidgets('baris fakta: label harga sekarang + konteks pemakaian, BUKAN kategori',
      (tester) async {
    await useTallViewport(tester);
    await tester.pumpWidget(wrap(PetShopping(
      usedCount: 1,
      used: [used('Drontal')],
      manual: const [],
      suggested: const [],
    )));
    await pumpFrames(tester);

    expect(find.text('Harga sekarang'), findsOneWidget);
    expect(find.text('Rp45.000'), findsOneWidget);
    expect(find.textContaining('Dipakai 2x, terakhir'), findsOneWidget);
    expect(find.textContaining('Obat Cacing'), findsNothing,
        reason: 'framing harus beda dari section Perawatan');
  });

  testWidgets('brand manual: tanpa harga, tombol Cari di Natalo', (tester) async {
    await useTallViewport(tester);
    await tester.pumpWidget(wrap(PetShopping(
      usedCount: 1,
      used: const [],
      manual: [
        PetShoppingManual(
          brandText: 'Bravecto',
          usageCount: 1,
          lastUsedAt: DateTime(2026, 6, 25),
        ),
      ],
      suggested: const [],
    )));
    await pumpFrames(tester);

    expect(find.text('Bravecto'), findsOneWidget);
    expect(find.text('Cari di Natalo'), findsOneWidget);
    expect(find.text('Harga sekarang'), findsNothing);
  });

  testWidgets('produk stok habis: tombol Cari serupa, tetap aktif',
      (tester) async {
    await useTallViewport(tester);
    await tester.pumpWidget(wrap(PetShopping(
      usedCount: 1,
      used: [
        PetShoppingProduct(
          productId: 'p1',
          slug: 's1',
          name: 'Combantrin',
          imageUrl: null,
          effectivePrice: 30000,
          inStock: false,
          hasVariants: false,
          usageCount: 1,
          lastUsedAt: DateTime(2026, 1, 25),
        ),
      ],
      manual: const [],
      suggested: const [],
    )));
    await pumpFrames(tester);

    expect(find.text('Cari serupa'), findsOneWidget);
    expect(find.text('Beli lagi'), findsNothing);
    expect(find.text('Stok habis'), findsOneWidget);
    final button = tester.widget<TextButton>(
      find.ancestor(
        of: find.text('Cari serupa'),
        matching: find.byType(TextButton),
      ),
    );
    expect(button.onPressed, isNotNull, reason: 'jangan tombol mati');
  });

  testWidgets('label pembaca layar tombol beli lagi memuat nama produk',
      (tester) async {
    await useTallViewport(tester);
    await tester.pumpWidget(wrap(PetShopping(
      usedCount: 1,
      used: [used('Drontal')],
      manual: const [],
      suggested: const [],
    )));
    await pumpFrames(tester);

    expect(
      find.bySemanticsLabel('Beli lagi, Drontal'),
      findsOneWidget,
      reason: 'bukan sekadar "Beli lagi" yang tak bisa dibedakan',
    );
  });

  testWidgets('pet baru: empty-state grup fakta, grup saran tetap terisi',
      (tester) async {
    await useTallViewport(tester);
    await tester.pumpWidget(wrap(PetShopping(
      usedCount: 0,
      used: const [],
      manual: const [],
      suggested: [suggestion('Snack Dental')],
    )));
    await pumpFrames(tester);

    expect(find.textContaining('Belum ada produk'), findsOneWidget);
    expect(find.text('Snack Dental'), findsOneWidget);
  });

  testWidgets('CTA jelajahi produk lain tampil di bawah grup saran',
      (tester) async {
    await useTallViewport(tester);
    await tester.pumpWidget(wrap(PetShopping(
      usedCount: 1,
      used: [used('Drontal')],
      manual: const [],
      suggested: [suggestion('Snack Dental')],
    )));
    await pumpFrames(tester);

    expect(find.text('Jelajahi produk lain'), findsOneWidget);
  });

  testWidgets('gagal fetch: pesan error, tidak crash', (tester) async {
    await useTallViewport(tester);
    await tester.pumpWidget(MaterialApp(
      home: PetShoppingScreen(
        petId: 'pet1',
        petName: 'Bobby',
        fetcher: (_) async => throw Exception('boom'),
      ),
    ));
    await pumpFrames(tester);

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Gagal memuat'), findsOneWidget);
  });
}

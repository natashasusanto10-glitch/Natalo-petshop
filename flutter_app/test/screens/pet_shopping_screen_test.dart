import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/pet_shopping.dart';
import 'package:natalo_petshop_flutter/models/product.dart';
import 'package:natalo_petshop_flutter/screens/pet_shopping_screen.dart';
import 'package:natalo_petshop_flutter/widgets/app_product_image.dart';
import 'package:natalo_petshop_flutter/widgets/compact_commerce_product_card.dart'
    show commerceGridSurfaceTint;

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

PetShopping dataWithSuggestions(int n) => PetShopping(
      usedCount: 0,
      used: const [],
      manual: const [],
      suggested: [for (var i = 0; i < n; i++) suggestion('Produk $i')],
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

  testWidgets('label pembaca layar tombol cari serupa memuat nama produk',
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

    expect(
      find.bySemanticsLabel('Cari serupa, Combantrin'),
      findsOneWidget,
      reason: 'bukan sekadar "Cari serupa" yang tak bisa dibedakan',
    );
  });

  testWidgets(
      'grup saran tak overflow saat text scale sistem membesar (1.3x)',
      (tester) async {
    await useTallViewport(tester);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: wrap(PetShopping(
          usedCount: 1,
          used: [used('Drontal')],
          manual: const [],
          suggested: [suggestion('Snack Dental'), suggestion('Vitamin Bulu')],
        )),
      ),
    );
    await pumpFrames(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Snack Dental'), findsOneWidget);
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

  testWidgets('beli lagi produk non-varian: ambil produk by slug lalu addProduct',
      (tester) async {
    await useTallViewport(tester);
    final fetchedSlugs = <String>[];
    final added = <String>[];
    final product = Product(
      id: 'id-Drontal',
      slug: 'slug-Drontal',
      title: 'Drontal',
      category: 'Obat & Suplemen',
      brand: 'Bayer',
      imageUrl: 'https://cdn/d.jpg',
      price: 45000,
      rating: 0,
      reviewCount: 0,
      stock: 5,
      weightGram: 100,
      isNew: false,
      isTrending: false,
      hasVariants: false,
      description: 'Obat cacing untuk anjing dan kucing',
    );

    await tester.pumpWidget(MaterialApp(
      home: PetShoppingScreen(
        petId: 'pet1',
        petName: 'Bobby',
        fetcher: (_) async => PetShopping(
          usedCount: 1,
          used: [used('Drontal')],
          manual: const [],
          suggested: const [],
        ),
        productFetcher: (slug) async {
          fetchedSlugs.add(slug);
          return product;
        },
        cartAdder: (p, {variant}) async {
          added.add(p.slug);
          return true;
        },
      ),
    ));
    await pumpFrames(tester);

    await tester.tap(find.text('Beli lagi'));
    await pumpFrames(tester);

    expect(fetchedSlugs, ['slug-Drontal']);
    expect(added, ['slug-Drontal']);
  });

  testWidgets('tap baris produk: fetch by slug lalu buka /product-detail',
      (tester) async {
    await useTallViewport(tester);
    final fetchedSlugs = <String>[];
    final product = Product(
      id: 'id-Drontal',
      slug: 'slug-Drontal',
      title: 'Drontal',
      category: 'Obat & Suplemen',
      brand: 'Bayer',
      imageUrl: 'https://cdn/d.jpg',
      price: 45000,
      rating: 0,
      reviewCount: 0,
      stock: 5,
      weightGram: 100,
      isNew: false,
      isTrending: false,
      hasVariants: false,
      description: 'Obat cacing untuk anjing dan kucing',
    );

    await tester.pumpWidget(MaterialApp(
      routes: {
        '/product-detail': (_) => const Scaffold(body: Text('DETAIL')),
      },
      home: PetShoppingScreen(
        petId: 'pet1',
        petName: 'Bobby',
        fetcher: (_) async => PetShopping(
          usedCount: 1,
          used: [used('Drontal')],
          manual: const [],
          suggested: const [],
        ),
        productFetcher: (slug) async {
          fetchedSlugs.add(slug);
          return product;
        },
      ),
    ));
    await pumpFrames(tester);

    await tester.tap(find.text('Drontal'));
    await pumpFrames(tester);

    expect(fetchedSlugs, ['slug-Drontal'],
        reason: 'route /product-detail butuh Product penuh, bukan slug');
    expect(find.text('DETAIL'), findsOneWidget);
  });

  testWidgets('beli lagi: produk sudah tak ada → pesan, tidak masuk keranjang',
      (tester) async {
    await useTallViewport(tester);
    final added = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: PetShoppingScreen(
        petId: 'pet1',
        petName: 'Bobby',
        fetcher: (_) async => PetShopping(
          usedCount: 1,
          used: [used('Drontal')],
          manual: const [],
          suggested: const [],
        ),
        productFetcher: (_) async => null,
        cartAdder: (p, {variant}) async {
          added.add(p.slug);
          return true;
        },
      ),
    ));
    await pumpFrames(tester);

    await tester.tap(find.text('Beli lagi'));
    await pumpFrames(tester);

    expect(added, isEmpty);
    expect(tester.takeException(), isNull);

    // Toast error pakai timer sampai ~3.65s; habiskan sebelum test selesai
    // agar tak ada Timer pending saat widget tree di-dispose.
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('grid saran: kartu tanpa badge "Saran"', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: PetShoppingScreen(
        petId: 'pet-1',
        petName: 'Didi',
        fetcher: (_) async => dataWithSuggestions(4),
      ),
    ));
    await pumpFrames(tester);
    expect(find.text('Saran'), findsNothing);
  });

  testWidgets('grid saran: nama 13/w600 tinggi dipaku, harga 16/w900',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: PetShoppingScreen(
        petId: 'pet-1',
        petName: 'Didi',
        fetcher: (_) async => PetShopping(
          usedCount: 0,
          used: const [],
          manual: const [],
          suggested: [
            PetShoppingProduct(
              productId: 'id-kaniva',
              slug: 'kaniva',
              name: 'Kaniva Dog',
              imageUrl: null,
              effectivePrice: 335000,
              inStock: true,
              hasVariants: false,
            ),
          ],
        ),
      ),
    ));
    await pumpFrames(tester);

    final nama = tester.widget<Text>(find.text('Kaniva Dog'));
    expect(nama.style!.fontSize, 13);
    expect(nama.style!.fontWeight, FontWeight.w600);

    expect(find.text('Rp335.000'), findsOneWidget);
    final harga = tester.widget<Text>(find.text('Rp335.000'));
    expect(harga.style!.fontSize, 16);
    expect(harga.style!.fontWeight, FontWeight.w900);
  });

  testWidgets('grid saran: foto 1:1 BoxFit.cover full-bleed', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: PetShoppingScreen(
        petId: 'pet-1',
        petName: 'Didi',
        fetcher: (_) async => dataWithSuggestions(2),
      ),
    ));
    await pumpFrames(tester);
    final imgs = tester
        .widgetList<AppProductImage>(find.byType(AppProductImage))
        .toList();
    expect(imgs, isNotEmpty);
    for (final img in imgs) {
      expect(img.fit, BoxFit.cover);
    }
    final size = tester.getSize(find.byType(AppProductImage).first);
    expect(size.width, closeTo(size.height, 0.5), reason: 'foto WAJIB 1:1');
  });

  testWidgets('grid saran duduk di atas kanal abu (ala Beranda/Katalog)',
      (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (c) {
        ctx = c;
        return PetShoppingScreen(
          petId: 'pet-1',
          petName: 'Didi',
          fetcher: (_) async => dataWithSuggestions(4),
        );
      }),
    ));
    await pumpFrames(tester);

    final expected = commerceGridSurfaceTint(ctx);
    final tinted = tester.widgetList<Container>(find.byType(Container)).where(
          (c) =>
              c.decoration is BoxDecoration &&
              (c.decoration as BoxDecoration).color == expected,
        );
    expect(tinted, isNotEmpty,
        reason: 'kartu putih butuh kanal abu supaya terbaca sebagai kartu');
  });

  testWidgets('grid saran menampilkan 12 kartu tanpa overflow', (tester) async {
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: PetShoppingScreen(
        petId: 'pet-1',
        petName: 'Didi',
        fetcher: (_) async => dataWithSuggestions(12),
      ),
    ));
    await pumpFrames(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Produk 0'), findsOneWidget);
    expect(find.text('Produk 11'), findsOneWidget);
  });

  testWidgets('grid saran ganjil: kartu terakhir tidak melebar penuh',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: PetShoppingScreen(
        petId: 'pet-1',
        petName: 'Didi',
        fetcher: (_) async => dataWithSuggestions(3),
      ),
    ));
    await pumpFrames(tester);

    final w0 = tester.getSize(find.text('Produk 0')).width;
    final w2 = tester.getSize(find.text('Produk 2')).width;
    expect(w2, closeTo(w0, 1.0),
        reason: 'kartu ganjil terakhir tetap selebar 1 kolom');
  });

  testWidgets('grid saran tidak overflow pada text scale 1.3', (tester) async {
    tester.view.physicalSize = const Size(1080, 8000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: PetShoppingScreen(
          petId: 'pet-1',
          petName: 'Didi',
          fetcher: (_) async => PetShopping(
            usedCount: 0,
            used: const [],
            manual: const [],
            suggested: [
              for (var i = 0; i < 6; i++)
                suggestion('Nama Produk Panjang Sekali Nomor $i'),
            ],
          ),
        ),
      ),
    ));
    await pumpFrames(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('CTA "Jelajahi produk lain" tetap ada di bawah grid',
      (tester) async {
    // Kartu grid gaya Katalog (foto 1:1 full-bleed) jauh lebih tinggi per
    // baris dibanding kartu lama; viewport default flutter_test (800x600)
    // tak cukup untuk memuat CTA di bawah grid ke dalam cacheExtent sliver.
    // Sama seperti gotcha yang sudah didokumentasikan di useTallViewport
    // untuk test lain di file ini.
    await useTallViewport(tester);
    await tester.pumpWidget(MaterialApp(
      home: PetShoppingScreen(
        petId: 'pet-1',
        petName: 'Didi',
        fetcher: (_) async => dataWithSuggestions(2),
      ),
    ));
    await pumpFrames(tester);
    expect(find.text('Jelajahi produk lain'), findsOneWidget);
  });
}

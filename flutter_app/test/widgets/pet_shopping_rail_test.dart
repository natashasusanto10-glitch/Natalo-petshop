import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/pet_shopping.dart';
import 'package:natalo_petshop_flutter/widgets/app_product_image.dart';
import 'package:natalo_petshop_flutter/widgets/pet_shopping_rail.dart';

/// GOTCHA REPO: `imageUrl` WAJIB null di widget test. `AppProductImage`
/// dengan URL http merender `Shimmer` yang beranimasi tanpa henti, sehingga
/// `pumpAndSettle` menggantung selamanya. Assertion `fit`/ukuran tetap sah
/// karena keduanya properti widget, bukan hasil unduhan.
PetShoppingProduct p(String name, {int price = 45000, String? slug}) =>
    PetShoppingProduct(
      productId: name,
      slug: slug ?? name.toLowerCase(),
      name: name,
      imageUrl: null,
      effectivePrice: price,
      inStock: true,
      hasVariants: false,
    );

Widget host(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('badge "Saran" TIDAK pernah dirender', (tester) async {
    await tester.pumpWidget(host(PetShoppingRail(
      used: const [],
      suggested: [p('Kaniva Dog')],
      onTapProduct: (_) {},
    )));
    expect(find.text('Saran'), findsNothing);
  });

  testWidgets('label semantik kartu = nama produk saja, tanpa "saran produk"',
      (tester) async {
    // Finder berbasis semantics WAJIB didahului ensureSemantics (konvensi
    // repo: lihat test/widgets/order_tracking_timeline_test.dart).
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(host(PetShoppingRail(
      used: const [],
      suggested: [p('Kaniva Dog')],
      onTapProduct: (_) {},
    )));
    expect(
      find.bySemanticsLabel(RegExp('saran produk')),
      findsNothing,
      reason: 'klaim per-produk dibuang (spec Keputusan 1)',
    );
    expect(find.bySemanticsLabel('Kaniva Dog'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('rail menampilkan maksimal 6 kartu', (tester) async {
    await tester.pumpWidget(host(PetShoppingRail(
      used: const [],
      suggested: [for (var i = 0; i < 20; i++) p('Produk $i')],
      onTapProduct: (_) {},
    )));
    expect(kPetShoppingRailMaxCards, 6);
    // Rail horizontal me-lazy-build; hitung dari itemCount ListView.
    final list = tester.widget<ListView>(find.byType(ListView));
    expect(list.semanticChildCount, 6);
  });

  testWidgets('used tampil dulu, saran mengisi sisa sampai 6', (tester) async {
    await tester.pumpWidget(host(PetShoppingRail(
      used: [p('Terpakai A'), p('Terpakai B')],
      suggested: [for (var i = 0; i < 20; i++) p('Saran $i')],
      onTapProduct: (_) {},
    )));
    final list = tester.widget<ListView>(find.byType(ListView));
    expect(list.semanticChildCount, 6);
    expect(find.text('Terpakai A'), findsOneWidget);
    expect(find.text('Terpakai B'), findsOneWidget);
  });

  testWidgets('kartu: foto 1:1 cover, nama 13/w600, harga 14/w900 diformat',
      (tester) async {
    await tester.pumpWidget(host(PetShoppingRail(
      used: const [],
      suggested: [p('Kaniva Dog', price: 335000)],
      onTapProduct: (_) {},
    )));

    final img = tester.widget<AppProductImage>(find.byType(AppProductImage));
    expect(img.fit, BoxFit.cover);

    final nama = tester.widget<Text>(find.text('Kaniva Dog'));
    expect(nama.style!.fontSize, 13);
    expect(nama.style!.fontWeight, FontWeight.w600);

    expect(find.text('Rp335.000'), findsOneWidget);
    final harga = tester.widget<Text>(find.text('Rp335.000'));
    expect(harga.style!.fontSize, 14);
    expect(harga.style!.fontWeight, FontWeight.w900);
  });

  testWidgets('kartu lebar 150 (identik rail Terlaris Beranda)',
      (tester) async {
    await tester.pumpWidget(host(PetShoppingRail(
      used: const [],
      suggested: [p('Kaniva Dog')],
      onTapProduct: (_) {},
    )));
    final size = tester.getSize(find.byType(AppProductImage));
    // Foto full-bleed → lebarnya = lebar kartu.
    expect(size.width, 150);
    expect(size.height, 150, reason: 'foto WAJIB 1:1');
  });

  testWidgets('tap kartu memanggil onTapProduct dengan produk yang benar',
      (tester) async {
    PetShoppingProduct? tapped;
    await tester.pumpWidget(host(PetShoppingRail(
      used: const [],
      suggested: [p('Kaniva Dog')],
      onTapProduct: (x) => tapped = x,
    )));
    await tester.tap(find.text('Kaniva Dog'));
    await tester.pump();
    expect(tapped?.name, 'Kaniva Dog');
  });

  testWidgets('skeleton tinggi IDENTIK rail terisi (anti layout-jump)',
      (tester) async {
    await tester.pumpWidget(host(const SizedBox(
      width: 400,
      child: PetShoppingRailSkeleton(),
    )));
    final skeleton = tester.getSize(find.byType(PetShoppingRailSkeleton));
    expect(skeleton.height, kPetShoppingRailHeight);
  });

  testWidgets('rail terisi setinggi kPetShoppingRailHeight', (tester) async {
    await tester.pumpWidget(host(SizedBox(
      width: 400,
      child: PetShoppingRail(
        used: const [],
        suggested: [p('Kaniva Dog')],
        onTapProduct: (_) {},
      ),
    )));
    final rail = tester.getSize(find.byType(PetShoppingRail));
    expect(rail.height, kPetShoppingRailHeight);
  });

  testWidgets('kartu tidak overflow pada text scale 1.3', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: PetShoppingRail(
                used: const [],
                suggested: [
                  p('Nama Produk Yang Panjang Sekali Untuk Menguji Dua Baris'),
                ],
                onTapProduct: (_) {},
              ),
            ),
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
  });
}

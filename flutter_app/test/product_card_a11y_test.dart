import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/product.dart';
import 'package:natalo_petshop_flutter/widgets/app_ui.dart';
import 'package:natalo_petshop_flutter/widgets/product_card.dart';

Product _product({
  String title = 'Royal Canin Mother Baby Cat 100GR',
  double price = 131500,
  double? discountPrice,
  double? memberPrice,
  double rating = 0,
  int reviewCount = 0,
  int soldCount = 0,
  int stock = 10,
}) {
  return Product.fromJson({
    'id': 'p1',
    'name': title,
    'slug': 'p1',
    'price': price,
    if (discountPrice != null) 'discountPrice': discountPrice,
    if (memberPrice != null) 'memberPrice': memberPrice,
    'avgRating': rating,
    'reviewCount': reviewCount,
    'soldCount': soldCount,
    'stock': stock,
    'imageUrl': '',
  });
}

void main() {
  group('label suara kartu', () {
    test('produk polos: judul, harga, ketersediaan', () {
      final l = productCardSemanticLabel(_product());
      expect(l, contains('Royal Canin Mother Baby Cat 100GR'));
      expect(l, contains('131.500'));
      // Ketersediaan WAJIB terucap walau tak ada sinyal lain.
      expect(l, contains('tersedia'));
    });

    test('stok habis terucap — kartu tetap bisa ditekan', () {
      // Tanpa ini pengguna pembaca layar baru tahu setelah membuka detail.
      final l = productCardSemanticLabel(_product(stock: 0));
      expect(l, contains('stok habis'));
      expect(l, isNot(contains(', tersedia')));
    });

    test('diskon menyebut persen DAN harga asli', () {
      // Persen saja tidak bermakna tanpa titik acuannya.
      final l = productCardSemanticLabel(
        _product(price: 100000, discountPrice: 75000),
      );
      expect(l, contains('25 persen'));
      expect(l, contains('100.000'));
    });

    test('rating & terjual ikut kalau ada, hilang kalau nol', () {
      final ada = productCardSemanticLabel(
        _product(rating: 4.8, reviewCount: 12, soldCount: 120),
      );
      expect(ada, contains('rating 4.8 dari 5'));
      expect(ada, contains('12 ulasan'));
      expect(ada, contains('120 terjual'));

      final kosong = productCardSemanticLabel(_product());
      expect(kosong, isNot(contains('rating')));
      expect(kosong, isNot(contains('ulasan')));
      expect(kosong, isNot(contains('terjual')));
    });

    test('harga member disebut', () {
      final l = productCardSemanticLabel(
        _product(price: 100000, memberPrice: 90000),
      );
      expect(l, contains('harga member'));
    });
  });

  testWidgets('kartu jadi SATU tombol, bukan potongan teks lepas',
      (tester) async {
    final handle = tester.ensureSemantics();
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 180,
            child: ProductCard(product: _product(), onTap: () {}),
          ),
        ),
      ),
    );

    final label = productCardSemanticLabel(_product());
    expect(find.bySemanticsLabel(label), findsOneWidget);

    // Judul TIDAK boleh muncul sebagai simpul semantik terpisah — kalau
    // muncul, artinya peleburan gagal dan pembaca layar mengeja dua kali.
    expect(
      find.bySemanticsLabel('Royal Canin Mother Baby Cat 100GR'),
      findsNothing,
    );

    handle.dispose();
  });

  testWidgets('tombol keranjang di dalam kartu TETAP terjangkau pembaca layar',
      (tester) async {
    final handle = tester.ensureSemantics();
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 180,
            height: 320,
            child: ProductCard(
              product: _product(),
              onTap: () {},
              showAddToCart: true,
            ),
          ),
        ),
      ),
    );

    // Kalau label kartu memakai excludeSemantics yang membungkus tombol,
    // simpul tombol ini IKUT TERTELAN dan pengguna kehilangan aksinya.
    expect(
      find.bySemanticsLabel(
        'Tambah Royal Canin Mother Baby Cat 100GR ke keranjang',
      ),
      findsOneWidget,
    );

    handle.dispose();
  });

  testWidgets('tombol keranjang ikon: visual tetap 34, area tap 44',
      (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 180,
            height: 320,
            child: ProductCard(
              product: _product(),
              onTap: () {},
              showAddToCart: true,
            ),
          ),
        ),
      ),
    );

    final icon = find.byIcon(Icons.add_shopping_cart_rounded);
    expect(icon, findsOneWidget);

    // Kotak yang menerima tap harus >= 44 di kedua sisi, TANPA membesarkan
    // kotak visual 34 yang menentukan tata letak grid.
    final tap = tester.getSize(
      find.ancestor(of: icon, matching: find.byType(AppMinTapTarget)),
    );
    expect(tap.width, greaterThanOrEqualTo(44));
    expect(tap.height, greaterThanOrEqualTo(44));
  });
}

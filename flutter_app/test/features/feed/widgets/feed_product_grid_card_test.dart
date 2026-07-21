import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_product_links_sheet.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: SizedBox(width: 340, child: child)));

void main() {
  group('FeedProductRowCard (list baris, 2+ produk)', () {
    testWidgets('flash sale: badge Flash Sale + strike + red price',
        (tester) async {
      final p = FeedProductLink(
        id: '1',
        slug: 'happy-cat',
        name: 'Happy Cat Sensitive',
        price: 55000,
        discountPrice: 44500,
        discountSource: 'FLASH_SALE',
        stock: 10,
        avgRating: 4.8,
        soldCount: 120,
      );
      await tester.pumpWidget(_host(
        FeedProductRowCard(product: p, onTap: () {}, onAddToCart: () {}),
      ));
      await tester.pump();
      expect(find.text('Flash Sale'), findsOneWidget);
      expect(find.text('Rp44.500'), findsOneWidget);
      expect(find.text('Rp55.000'), findsOneWidget); // strike original
      expect(find.textContaining('terjual'), findsOneWidget);
    });

    testWidgets('promo toko: badge Diskon (bukan Flash Sale)', (tester) async {
      final p = FeedProductLink(
        id: '1b',
        slug: 'promo-toko',
        name: 'Produk Promo Toko',
        price: 50000,
        discountPrice: 40000,
        discountSource: 'PROMO_TOKO',
        stock: 10,
      );
      await tester.pumpWidget(_host(
        FeedProductRowCard(product: p, onTap: () {}, onAddToCart: () {}),
      ));
      await tester.pump();
      expect(find.text('Diskon'), findsOneWidget);
      expect(find.text('Flash Sale'), findsNothing);
    });

    testWidgets('non-promo product: plain price, no badge, no rating line',
        (tester) async {
      final p = FeedProductLink(
        id: '2',
        slug: 'plain',
        name: 'Plain Product',
        price: 30000,
        stock: 5,
      );
      await tester.pumpWidget(_host(
        FeedProductRowCard(product: p, onTap: () {}, onAddToCart: () {}),
      ));
      await tester.pump();
      expect(find.text('Rp30.000'), findsOneWidget);
      expect(find.text('Flash Sale'), findsNothing);
      expect(find.text('Diskon'), findsNothing);
      expect(find.textContaining('terjual'), findsNothing);
    });

    testWidgets('cart button invokes onAddToCart; row invokes onTap',
        (tester) async {
      var added = false, opened = false;
      final p = FeedProductLink(
        id: '3',
        slug: 'x',
        name: 'X',
        price: 10000,
        stock: 5,
      );
      await tester.pumpWidget(_host(
        FeedProductRowCard(
          product: p,
          onTap: () => opened = true,
          onAddToCart: () => added = true,
        ),
      ));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.shopping_cart_outlined));
      expect(added, isTrue);
      await tester.tap(find.text('X'));
      expect(opened, isTrue);
    });

    testWidgets('shippingVoucher → chip Gratis Ongkir', (tester) async {
      final p = FeedProductLink(
        id: '4',
        slug: 'ongkir',
        name: 'Produk Ongkir Gratis',
        price: 20000,
        stock: 5,
        shippingVoucher: const FeedProductVoucherBadge(badgeLabel: 'Gratis Ongkir'),
      );
      await tester.pumpWidget(_host(
        FeedProductRowCard(product: p, onTap: () {}, onAddToCart: () {}),
      ));
      await tester.pump();
      expect(find.text('Gratis Ongkir'), findsOneWidget);
    });

    testWidgets('voucher brand-exclusive → chip Brand Eksklusif (prioritas atas ongkir)',
        (tester) async {
      final p = FeedProductLink(
        id: '5',
        slug: 'brand',
        name: 'Produk Brand Eksklusif',
        price: 20000,
        stock: 5,
        shippingVoucher: const FeedProductVoucherBadge(
          badgeLabel: 'Gratis Ongkir',
          isBrandExclusive: true,
        ),
      );
      await tester.pumpWidget(_host(
        FeedProductRowCard(product: p, onTap: () {}, onAddToCart: () {}),
      ));
      await tester.pump();
      expect(find.text('Brand Eksklusif'), findsOneWidget);
      expect(find.text('Gratis Ongkir'), findsNothing);
    });

    testWidgets('discountVoucher → teks Hemat di bawah harga', (tester) async {
      final p = FeedProductLink(
        id: '6',
        slug: 'hemat',
        name: 'Produk Hemat Voucher',
        price: 20000,
        stock: 5,
        discountVoucher:
            const FeedProductVoucherBadge(badgeLabel: 'Hemat s.d. Rp20.000'),
      );
      await tester.pumpWidget(_host(
        FeedProductRowCard(product: p, onTap: () {}, onAddToCart: () {}),
      ));
      await tester.pump();
      expect(find.text('Hemat s.d. Rp20.000'), findsOneWidget);
    });
  });

  group('FeedProductSingleCard (1 produk)', () {
    testWidgets('renders semua chip promo + dua tombol', (tester) async {
      final p = FeedProductLink(
        id: '7',
        slug: 'single',
        name: 'Happy Dog Supreme Sensible Neuseeland Lamb 1kg',
        price: 171000,
        discountPrice: 149500,
        discountSource: 'PROMO_TOKO',
        stock: 10,
        avgRating: 4.9,
        soldCount: 120,
        shippingVoucher: const FeedProductVoucherBadge(badgeLabel: 'Gratis Ongkir'),
        discountVoucher:
            const FeedProductVoucherBadge(badgeLabel: 'Hemat s.d. Rp20.000'),
      );
      await tester.pumpWidget(_host(
        FeedProductSingleCard(product: p, onTap: () {}, onAddToCart: () {}),
      ));
      await tester.pump();
      expect(find.text('Gratis Ongkir'), findsOneWidget);
      expect(find.text('Hemat s.d. Rp20.000'), findsOneWidget);
      expect(find.text('Lihat Detail'), findsOneWidget);
      expect(find.text('Tambah ke Keranjang'), findsOneWidget);
      expect(find.text('Rp149.500'), findsOneWidget);
      expect(find.text('Rp171.000'), findsOneWidget);
    });

    testWidgets('stok habis → tombol Tambah ke Keranjang nonaktif',
        (tester) async {
      var added = false;
      final p = FeedProductLink(
        id: '8',
        slug: 'oos',
        name: 'Produk Kosong Stok',
        price: 10000,
        stock: 0,
      );
      await tester.pumpWidget(_host(
        FeedProductSingleCard(
          product: p,
          onTap: () {},
          onAddToCart: () => added = true,
        ),
      ));
      await tester.pump();
      expect(find.text('Stok Habis'), findsOneWidget);
      await tester.tap(find.text('Stok Habis'), warnIfMissed: false);
      expect(added, isFalse);
    });
  });
}

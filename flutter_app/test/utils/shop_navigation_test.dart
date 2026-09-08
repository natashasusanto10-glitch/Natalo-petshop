import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/utils/shop_navigation.dart';

/// Halaman palsu per rute — cukup teks nama rutenya + argumen, supaya tes
/// mengukur BENTUK TUMPUKAN, bukan isi layar sungguhan.
Widget _app(GlobalKey<NavigatorState> key) {
  return MaterialApp(
    navigatorKey: key,
    initialRoute: '/member/login',
    onGenerateRoute: (settings) => MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => Text(
        'page:${settings.name} args:${settings.arguments}',
        textDirection: TextDirection.ltr,
      ),
    ),
  );
}

void main() {
  group('parseLoginRedirect', () {
    test('bentuk String dan Map sama-sama dibaca', () {
      expect(parseLoginRedirect('/wishlist')?.route, '/wishlist');
      expect(parseLoginRedirect({'redirect': '/chat'})?.route, '/chat');
    });

    test('kosong / bukan rute → null (default /member)', () {
      expect(parseLoginRedirect(null), isNull);
      expect(parseLoginRedirect(''), isNull);
      expect(parseLoginRedirect('wishlist'), isNull);
      expect(parseLoginRedirect({'redirect': '   '}), isNull);
    });

    test(
        '/checkout SELALU dapat /cart sebagai perantara walau via tidak dikirim',
        () {
      // Inilah kasus yang melahirkan layar putih — jangan bergantung pada
      // tiap pemanggil mengingat untuk mengirim via.
      expect(parseLoginRedirect({'redirect': '/checkout'})?.via, ['/cart']);
      expect(parseLoginRedirect('/checkout')?.via, ['/cart']);
    });

    test('via eksplisit dihormati, dan nilai bukan-rute dibuang', () {
      final t = parseLoginRedirect({
        'redirect': '/chat',
        'via': ['/cart', 'bukan-rute', 42],
      });
      expect(t?.via, ['/cart']);
    });

    test('arguments diteruskan apa adanya', () {
      final args = {'productId': 'p1'};
      expect(
        parseLoginRedirect({'redirect': '/chat', 'arguments': args})?.arguments,
        same(args),
      );
    });
  });

  group('navigateAfterLogin', () {
    testWidgets(
        '/checkout: back dari Checkout mendarat di Keranjang, lalu Beranda — bukan putih',
        (tester) async {
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(_app(key));
      await tester.pumpAndSettle();

      navigateAfterLogin(
        key.currentState!,
        parseLoginRedirect({'redirect': '/checkout', 'arguments': 'ITEMS'}),
      );
      await tester.pumpAndSettle();
      expect(find.text('page:/checkout args:ITEMS'), findsOneWidget);

      // Persis skenario laporan: "Kembali ke Keranjang" = pop.
      key.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('page:/cart args:null'), findsOneWidget,
          reason: 'sebelumnya Checkout sendirian di tumpukan → pop = kosong');

      key.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('page:/ args:null'), findsOneWidget);
      expect(key.currentState!.canPop(), isFalse);
    });

    testWidgets('tanpa tujuan → /member menggantikan semuanya (perilaku lama)',
        (tester) async {
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(_app(key));
      await tester.pumpAndSettle();

      navigateAfterLogin(key.currentState!, null);
      await tester.pumpAndSettle();
      expect(find.text('page:/member args:null'), findsOneWidget);
      expect(key.currentState!.canPop(), isFalse);
    });

    testWidgets('layar login TIDAK tersisa di tumpukan setelah berhasil',
        (tester) async {
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(_app(key));
      await tester.pumpAndSettle();

      navigateAfterLogin(key.currentState!, parseLoginRedirect('/chat'));
      await tester.pumpAndSettle();
      key.currentState!.pop();
      await tester.pumpAndSettle();
      // Back dari tujuan = Beranda, bukan kembali ke form login.
      expect(find.text('page:/ args:null'), findsOneWidget);
      expect(find.textContaining('/member/login'), findsNothing);
    });
  });

  group('leaveCheckoutToCart', () {
    testWidgets(
        'ada layar di bawah → pop biasa (Keranjang yang sama dipertahankan)',
        (tester) async {
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(_app(key));
      await tester.pumpAndSettle();
      key.currentState!.pushNamed('/cart');
      key.currentState!.pushNamed('/checkout');
      await tester.pumpAndSettle();

      leaveCheckoutToCart(key.currentState!);
      await tester.pumpAndSettle();
      expect(find.text('page:/cart args:null'), findsOneWidget);
      // Login masih di bawah Keranjang: tumpukan tidak dibangun ulang.
      expect(key.currentState!.canPop(), isTrue);
    });

    testWidgets(
        'Checkout SENDIRIAN → bangun ulang Beranda → Keranjang, bukan putih',
        (tester) async {
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(_app(key));
      await tester.pumpAndSettle();
      key.currentState!.pushNamedAndRemoveUntil('/checkout', (r) => false);
      await tester.pumpAndSettle();
      expect(key.currentState!.canPop(), isFalse,
          reason: 'prasyarat: sendirian');

      leaveCheckoutToCart(key.currentState!);
      await tester.pumpAndSettle();
      expect(find.text('page:/cart args:null'), findsOneWidget);

      key.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('page:/ args:null'), findsOneWidget);
    });
  });
}

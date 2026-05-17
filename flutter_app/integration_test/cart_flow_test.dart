import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:natalo_petshop_flutter/main.dart' as app;

/// Cart flow integration test — verifikasi end-to-end:
/// Home → tap cart icon → CartScreen renders → empty state OR cart items
///
/// Run di device:
/// ```bash
/// flutter test integration_test/cart_flow_test.dart
/// ```
///
/// Penting: test ini bersifat **defensive** — tidak hardcode produk
/// karena data datang dari API live. Test pass kalau navigation works
/// + screens render tanpa crash.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Cart navigation flow', () {
    testWidgets('navigate from home → cart screen', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 4));

      // Tap cart icon di header beranda.
      final cartIcon = find.byTooltip('Keranjang');
      expect(cartIcon, findsAtLeast(1),
          reason: 'Cart icon harus visible di home header');

      await tester.tap(cartIcon.first);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // After navigate, CartScreen renders. Expect either:
      // - Empty state CTA "Mulai belanja" / "Belanja sekarang"
      // - OR cart items list dengan "Lanjut ke Checkout" button
      final hasEmptyState =
          find.textContaining('belum', findRichText: true).evaluate().isNotEmpty;
      final hasItems = find
          .textContaining('Checkout', findRichText: true)
          .evaluate()
          .isNotEmpty;

      expect(
        hasEmptyState || hasItems,
        isTrue,
        reason: 'CartScreen harus tampilkan empty state atau items',
      );

      // Verify back button works (navigation stack ada).
      final backButton = find.byIcon(Icons.arrow_back_rounded);
      if (backButton.evaluate().isNotEmpty) {
        await tester.tap(backButton.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        // After back, harus kembali ke home (cart icon visible lagi).
        expect(find.byTooltip('Keranjang'), findsAtLeast(1));
      }
    });

    testWidgets('account nav redirects guest to login', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 4));

      // Tap "Akun" tab di bottom nav.
      final akunTab = find.text('Akun');
      if (akunTab.evaluate().isEmpty) return;

      await tester.tap(akunTab.first);
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Karena guest, harus auto-redirect ke login screen.
      // Login screen punya title "Masuk Member Natalo" + logo + form.
      final hasLogin = find
          .textContaining('Masuk', findRichText: true)
          .evaluate()
          .isNotEmpty;

      // Kalau sudah login, akan tampil dashboard dengan "Halo, [name]!"
      final isDashboard = find
          .textContaining('Halo', findRichText: true)
          .evaluate()
          .isNotEmpty;

      expect(
        hasLogin || isDashboard,
        isTrue,
        reason: 'Tap Akun harus push login (guest) atau dashboard (logged in)',
      );
    });
  });
}

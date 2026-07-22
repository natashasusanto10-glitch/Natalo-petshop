import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/services/deep_link_service.dart';

/// Reproduksi race cold-start: `main.dart` memanggil
/// `deepLinkService.initialize(rootNavigatorKey)` SEBELUM `runApp()` selesai
/// membangun widget tree. Kalau `getInitialLink()`/link masuk resolve
/// duluan, `_navigatorKey.currentState` masih null saat itu. Tanpa retry,
/// deep link dibuang diam-diam — user cuma lihat initialRoute default
/// (Beranda), utk SEMUA jenis link (profil `/u/`, produk `/products/`, dst),
/// persis gejala device yang dilaporkan.
void main() {
  testWidgets(
      'link diproses SEBELUM Navigator ter-mount tetap sampai ke tujuan (retry, bukan dibuang)',
      (tester) async {
    final svc = DeepLinkService.test();
    final navKey = GlobalKey<NavigatorState>();

    // Simulasi persis race: attach key yang BELUM ter-mount ke widget tree
    // apa pun (currentState == null) — meniru `initialize()` dipanggil
    // sebelum `runApp()`.
    svc.navigatorKeyForTesting = navKey;
    expect(navKey.currentState, isNull,
        reason: 'setup: navigator belum ter-mount, meniru race cold-start');

    // Link masuk SAAT navigator belum ada — ini yang dulu dibuang diam-diam.
    svc.handleExternalUri('https://natalopetshop.com/u/asiong001');

    // Navigator BARU ter-mount belakangan (meniru runApp() selesai +
    // widget tree ter-build), setelah link sudah "dikirim".
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        initialRoute: '/',
        routes: {
          '/': (_) => const Scaffold(body: Text('BERANDA')),
          '/u': (context) {
            final username = ModalRoute.of(context)!.settings.arguments;
            return Scaffold(body: Text('PROFILE:$username'));
          },
        },
      ),
    );

    // Poll interval fix = 50ms x maks 40x (2 detik) — pump cukup lama utk
    // retry menemukan navigator yang baru ter-mount.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('PROFILE:asiong001'), findsOneWidget,
        reason: 'link yang masuk sebelum Navigator siap harus tetap sampai ke '
            'halaman profil (retry), BUKAN dibuang ke Beranda diam-diam');
    expect(find.text('BERANDA'), findsNothing);
  });
}

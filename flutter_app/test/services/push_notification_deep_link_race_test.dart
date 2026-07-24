import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/services/deep_link_service.dart';
import 'package:natalo_petshop_flutter/services/push_notification_service.dart';

/// Reproduksi race cold-start tap notifikasi FCM: `getInitialMessage()`
/// (dipanggil dari `initialize()`) bisa resolve SEBELUM `runApp()` selesai
/// membangun root Navigator. `_handleDeepLink` dulu punya guard
/// `_navigatorKey?.currentState == null → return` sendiri yang MEMBUANG tap
/// diam-diam sebelum sempat lewat retry `deepLinkService` — gejala device:
/// notif FCM di-tap, app cold-start, tapi tidak pernah navigasi kemana pun.
void main() {
  testWidgets(
      'tap FCM diproses SEBELUM Navigator ter-mount tetap sampai ke tujuan '
      '(diteruskan ke deepLinkService, bukan dibuang oleh guard sendiri)',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();

    // Simulasi persis race: attach key yang BELUM ter-mount ke widget tree
    // apa pun (currentState == null) — meniru getInitialMessage() resolve
    // sebelum runApp() selesai.
    deepLinkService.navigatorKeyForTesting = navKey;
    expect(navKey.currentState, isNull,
        reason: 'setup: navigator belum ter-mount, meniru race cold-start');

    // Tap FCM masuk SAAT navigator belum ada — dulu dibuang diam-diam oleh
    // guard `_navigatorKey` milik PushNotificationService sendiri.
    pushNotificationService.handleDeepLinkForTesting(
      'https://natalopetshop.com/u/asiong001',
    );

    // Navigator BARU ter-mount belakangan (meniru runApp() selesai).
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
    // retry deepLinkService menemukan navigator yang baru ter-mount.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('PROFILE:asiong001'), findsOneWidget,
        reason: 'tap FCM yang masuk sebelum Navigator siap harus tetap '
            'sampai ke halaman profil (retry via deepLinkService), BUKAN '
            'dibuang diam-diam ke Beranda oleh guard PushNotificationService');
    expect(find.text('BERANDA'), findsNothing);
  });
}

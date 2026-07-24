import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/services/deep_link_service.dart';

/// Case baru `/akun/followers` (notif follow agregat, spec agregasi
/// Keputusan 11 + gotcha PR #137: URL server tanpa case → nyasar /member).
void main() {
  testWidgets('deep-link /akun/followers membuka layar follower',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    final service = DeepLinkService.test();
    service.navigatorKeyForTesting = navKey;

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        initialRoute: '/',
        routes: {
          '/': (_) => const Scaffold(body: Text('BERANDA')),
          '/akun/followers': (_) => const Scaffold(body: Text('FOLLOWERS')),
          '/member': (_) => const Scaffold(body: Text('AKUN')),
        },
      ),
    );

    service.handleExternalUri(
      Uri.parse('https://natalopetshop.com/akun/followers'),
    );
    await tester.pumpAndSettle();

    expect(find.text('FOLLOWERS'), findsOneWidget,
        reason: '/akun/followers WAJIB punya case sendiri, '
            'bukan jatuh ke /member (gotcha PR #137)');
    expect(find.text('AKUN'), findsNothing);
  });
}

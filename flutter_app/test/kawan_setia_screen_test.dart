import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/screens/kawan_setia_screen.dart';
import 'package:natalo_petshop_flutter/services/deep_link_service.dart';

void main() {
  testWidgets(
      'WhatsApp CTA opens the contact with prefilled message, without showing number',
      (tester) async {
    Uri? opened;
    await tester.pumpWidget(MaterialApp(home: KawanSetiaScreen(
      openWhatsApp: (uri) async {
        opened = uri;
        return true;
      },
    )));
    await tester.tap(find.byKey(const ValueKey('kawan-setia-whatsapp')));
    await tester.pumpAndSettle();
    expect(opened?.host, 'wa.me');
    expect(opened?.path, '/6281330003880');
    expect(opened?.queryParameters['text'], contains('aplikasi Natalo'));
    expect(find.textContaining('813'), findsNothing);
    expect(find.textContaining('Hotel'), findsNothing);
  });

  testWidgets('failed launcher shows retry feedback', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: KawanSetiaScreen(
      openWhatsApp: (_) async => throw Exception('launcher unavailable'),
    )));
    await tester.tap(find.byKey(const ValueKey('kawan-setia-whatsapp')));
    await tester.pumpAndSettle();
    expect(find.text('WhatsApp belum bisa dibuka. Silakan coba lagi.'),
        findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('kawan-setia-whatsapp')))
            .onPressed,
        isNotNull);
  });

  testWidgets(
      'small screen with larger text scrolls all services and retains CTA',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(1.5)),
        child: child!,
      ),
      home: const KawanSetiaScreen(),
    ));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Latihan Anjing'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Tanya via WhatsApp'), findsOneWidget);
  });

  for (final link in [
    '/services/kawan-setia',
    'https://www.natalopetshop.com/services/kawan-setia',
  ]) {
    testWidgets('popup link opens native detail and back returns home: $link',
        (tester) async {
      final key = GlobalKey<NavigatorState>();
      final service = DeepLinkService.test()..navigatorKeyForTesting = key;
      await tester.pumpWidget(MaterialApp(
        navigatorKey: key,
        routes: {
          '/': (_) => const Scaffold(body: Text('BERANDA')),
          KawanSetiaScreen.routeName: (_) => const KawanSetiaScreen(),
        },
      ));
      service.handleExternalUri(link);
      await tester.pumpAndSettle();
      expect(find.byType(KawanSetiaScreen), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('BERANDA'), findsOneWidget);
    });
  }
}

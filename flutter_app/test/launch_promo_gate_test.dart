import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:natalo_petshop_flutter/models/launch_popup.dart';
import 'package:natalo_petshop_flutter/widgets/launch_promo_dialog.dart';
import 'package:natalo_petshop_flutter/widgets/launch_promo_gate.dart';

const _popup = LaunchPopup(
  id: 'p1',
  imageUrl: 'https://cdn.example.com/popup.png',
  imageAlt: 'Promo Juli',
  href: '/products?diskon=1',
  memberOnly: true,
);

Future<void> _pump(
  WidgetTester tester, {
  required bool isLoggedIn,
  required LaunchPromoOutcome dialogReturns,
  required List<String> events,
  required List<String> openedHrefs,
  required List<int> shownCounter,
  LaunchPopup? popup = _popup,
  bool imageLoads = true,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: LaunchPromoGate(
      navigatorKey: GlobalKey<NavigatorState>(),
      popupProvider: () async => popup,
      ensureAuthReady: () async {},
      isLoggedIn: () => isLoggedIn,
      hasSeenOnboarding: () async => true,
      isOnline: () => true,
      launchedExternally: () => false,
      routeStackedAboveHome: () => false,
      preloadImage: (_) async => imageLoads,
      settleDelay: Duration.zero,
      showDialogFn: (ctx, p) async {
        shownCounter[0]++;
        return dialogReturns;
      },
      openHref: (href) async => openedHrefs.add(href),
      logEvent: (name, params) async => events.add(name),
      child: const Scaffold(body: Text('HOME')),
    ),
  ));
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('tampilkan dialog + buka href saat semua lolos & CTA', (tester) async {
    final events = <String>[]; final hrefs = <String>[]; final shown = [0];
    await _pump(tester,
        isLoggedIn: true, dialogReturns: LaunchPromoOutcome.cta,
        events: events, openedHrefs: hrefs, shownCounter: shown);
    expect(shown[0], 1);
    expect(hrefs, ['/products?diskon=1']);
    expect(events, containsAllInOrder(['launch_popup_shown', 'launch_popup_cta_click']));
  });

  testWidgets('dismiss: log dismiss, tidak buka href', (tester) async {
    final events = <String>[]; final hrefs = <String>[]; final shown = [0];
    await _pump(tester,
        isLoggedIn: true, dialogReturns: LaunchPromoOutcome.dismiss,
        events: events, openedHrefs: hrefs, shownCounter: shown);
    expect(shown[0], 1);
    expect(hrefs, isEmpty);
    expect(events, containsAllInOrder(['launch_popup_shown', 'launch_popup_dismiss']));
  });

  testWidgets('skip total saat belum login (popup member-only)', (tester) async {
    final events = <String>[]; final hrefs = <String>[]; final shown = [0];
    await _pump(tester,
        isLoggedIn: false, dialogReturns: LaunchPromoOutcome.dismiss,
        events: events, openedHrefs: hrefs, shownCounter: shown);
    expect(shown[0], 0);
    expect(events, isEmpty);
  });

  testWidgets('popup audience "all" tampil walau guest', (tester) async {
    final events = <String>[]; final hrefs = <String>[]; final shown = [0];
    await _pump(tester,
        isLoggedIn: false, dialogReturns: LaunchPromoOutcome.dismiss,
        popup: const LaunchPopup(
          id: 'p2',
          imageUrl: 'https://cdn.example.com/all.png',
          memberOnly: false,
        ),
        events: events, openedHrefs: hrefs, shownCounter: shown);
    expect(shown[0], 1);
  });

  testWidgets('skip total saat API tidak punya popup aktif', (tester) async {
    final events = <String>[]; final hrefs = <String>[]; final shown = [0];
    await _pump(tester,
        isLoggedIn: true, dialogReturns: LaunchPromoOutcome.dismiss,
        popup: null,
        events: events, openedHrefs: hrefs, shownCounter: shown);
    expect(shown[0], 0);
    expect(events, isEmpty);
  });

  testWidgets('skip total saat gambar gagal precache (tanpa log shown)', (tester) async {
    final events = <String>[]; final hrefs = <String>[]; final shown = [0];
    await _pump(tester,
        isLoggedIn: true, dialogReturns: LaunchPromoOutcome.dismiss,
        imageLoads: false,
        events: events, openedHrefs: hrefs, shownCounter: shown);
    expect(shown[0], 0);
    expect(events, isEmpty);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:natalo_petshop_flutter/models/launch_popup_campaign.dart';
import 'package:natalo_petshop_flutter/widgets/launch_promo_dialog.dart';
import 'package:natalo_petshop_flutter/widgets/launch_promo_gate.dart';

const _campaign = LaunchPopupCampaign(
  id: 'p1', tone: LaunchPopupTone.promo, imageUrl: null,
  title: 'Judul', body: 'Body', categoryLabel: 'Promo',
  ctaLabel: 'Lihat produk', ctaHref: '/produk/abc',
);

Future<void> _pump(
  WidgetTester tester, {
  required bool isLoggedIn,
  required LaunchPromoOutcome dialogReturns,
  required List<String> events,
  required List<String> openedHrefs,
  required List<int> shownCounter,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: LaunchPromoGate(
      navigatorKey: GlobalKey<NavigatorState>(),
      campaignProvider: () => _campaign,
      ensureAuthReady: () async {},
      isLoggedIn: () => isLoggedIn,
      hasSeenOnboarding: () async => true,
      isOnline: () => true,
      launchedExternally: () => false,
      routeStackedAboveHome: () => false,
      settleDelay: Duration.zero,
      showDialogFn: (ctx, c) async {
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
    expect(hrefs, ['/produk/abc']);
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

  testWidgets('skip total saat belum login', (tester) async {
    final events = <String>[]; final hrefs = <String>[]; final shown = [0];
    await _pump(tester,
        isLoggedIn: false, dialogReturns: LaunchPromoOutcome.dismiss,
        events: events, openedHrefs: hrefs, shownCounter: shown);
    expect(shown[0], 0);
    expect(events, isEmpty);
  });
}

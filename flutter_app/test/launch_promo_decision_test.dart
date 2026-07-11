// flutter_app/test/launch_promo_decision_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/widgets/launch_promo_decision.dart';

/// Semua kondisi lolos kecuali override yang dikirim.
bool show({
  bool hasCampaign = true,
  bool memberOnly = true,
  bool isLoggedIn = true,
  bool hasSeenOnboarding = true,
  bool isOnline = true,
  bool launchedExternally = false,
  bool routeStackedAboveHome = false,
}) =>
    launchPromoShouldShow(
      hasCampaign: hasCampaign,
      memberOnly: memberOnly,
      isLoggedIn: isLoggedIn,
      hasSeenOnboarding: hasSeenOnboarding,
      isOnline: isOnline,
      launchedExternally: launchedExternally,
      routeStackedAboveHome: routeStackedAboveHome,
    );

void main() {
  test('tampil saat semua kondisi ideal', () {
    expect(show(), isTrue);
  });
  test('skip tanpa campaign', () => expect(show(hasCampaign: false), isFalse));
  test('skip belum login saat popup member-only',
      () => expect(show(isLoggedIn: false), isFalse));
  test('popup audience "all" tetap tampil untuk guest',
      () => expect(show(memberOnly: false, isLoggedIn: false), isTrue));
  test('skip belum onboarding', () => expect(show(hasSeenOnboarding: false), isFalse));
  test('skip offline', () => expect(show(isOnline: false), isFalse));
  test('skip dibuka dari deep-link/push', () => expect(show(launchedExternally: true), isFalse));
  test('skip bukan di root Home', () => expect(show(routeStackedAboveHome: true), isFalse));
}

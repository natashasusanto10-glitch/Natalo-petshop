// flutter_app/lib/widgets/launch_promo_decision.dart

/// Keputusan MURNI apakah popup pembuka boleh tampil. Sengaja dipisah dari
/// widget supaya bisa diuji cepat & deterministik tanpa render (menghindari
/// shimmer AppProductImage yang tak pernah settle di test).
bool launchPromoShouldShow({
  required bool hasCampaign,
  required bool memberOnly,
  required bool isLoggedIn,
  required bool hasSeenOnboarding,
  required bool isOnline,
  required bool launchedExternally,
  required bool routeStackedAboveHome,
}) {
  if (!hasCampaign) return false;
  // Gating audience dari admin: popup "member" hanya untuk user login;
  // popup "all" tampil ke semua (termasuk guest).
  if (memberOnly && !isLoggedIn) return false;
  if (!hasSeenOnboarding) return false;
  if (!isOnline) return false;
  if (launchedExternally) return false; // jangan tutupi tujuan deep-link/push
  if (routeStackedAboveHome) return false; // hanya saat masih di root Home
  return true;
}

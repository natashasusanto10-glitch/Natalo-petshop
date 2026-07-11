import 'package:flutter/widgets.dart';

/// RouteObserver global — layar video (feed) subscribe via RouteAware untuk
/// PAUSE DETERMINISTIK saat route lain menutup (didPushNext) dan resume saat
/// kembali (didPopNext).
///
/// Latar: feed dulu hanya mengandalkan VisibilityDetector (debounce ~500ms)
/// untuk pause saat navigasi. Layar tujuan (mis. detail postingan member)
/// bisa autoplay video-nya sendiri unmuted DI DALAM jendela debounce itu →
/// dua controller bersuara bersamaan ("double suara"). Jendela makin lebar
/// saat jaringan lambat.
///
/// [lastPushedRoute] menyimpan route yang BARU di-push supaya subscriber
/// bisa membedakan halaman penuh (PageRoute opaque → pause video) dari
/// bottom sheet / dialog transparan (video boleh tetap jalan — tidak ada
/// konflik audio, dan TikTok/IG juga tetap memutar di balik sheet produk).
class AppRouteObserver extends RouteObserver<ModalRoute<void>> {
  Route<dynamic>? lastPushedRoute;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    lastPushedRoute = route;
    super.didPush(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    lastPushedRoute = newRoute;
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}

final AppRouteObserver appRouteObserver = AppRouteObserver();

/// True kalau route yang barusan di-push menutup layar sepenuhnya
/// (halaman penuh), bukan sheet/dialog transparan.
bool lastPushedRouteIsOpaque() {
  final r = appRouteObserver.lastPushedRoute;
  return r is PageRoute && r.opaque;
}

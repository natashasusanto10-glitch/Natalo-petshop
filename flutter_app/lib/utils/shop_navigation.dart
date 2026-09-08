/// Navigasi lintas-layar yang rawan meninggalkan Navigator KOSONG.
///
/// Latar: setelah login, app dulu melompat ke tujuan dengan
/// `pushNamedAndRemoveUntil(tujuan, (route) => false)` — menghapus SELURUH
/// tumpukan. Untuk tujuan `/checkout`, yang tersisa hanya Checkout sendirian;
/// tombol "Kembali ke Keranjang" lalu mem-pop satu-satunya layar yang ada, dan
/// Navigator kosong = layar putih polos (laporan user dengan tangkapan layar).
/// Skenario normal (Keranjang → Checkout tanpa login) tidak kena karena
/// Keranjang masih ada di bawahnya — bug ini hanya muncul lewat jalur login.
///
/// Dua pengaman di sini:
/// - [navigateAfterLogin]: tumpukan setelah login SELALU berpijak di Beranda,
///   dengan layar perantara (`via`) di antaranya — Checkout dapat Keranjang
///   di bawahnya persis seperti alur normal.
/// - [leaveCheckoutToCart]: kalau entah bagaimana Checkout tetap sendirian,
///   bangun ulang Beranda → Keranjang alih-alih mem-pop ke kekosongan.
library;

import 'package:flutter/widgets.dart';

/// Tujuan pengalihan setelah login, dibaca dari argumen rute `/member/login`.
///
/// Bentuk yang diterima (semua sudah dipakai di app):
/// - `String` → rute saja, mis. `'/wishlist'`
/// - `Map` → `{'redirect': '/chat', 'arguments': ..., 'via': ['/cart']}`
class LoginRedirectTarget {
  const LoginRedirectTarget({
    required this.route,
    this.arguments,
    this.via = const [],
  });

  final String route;
  final Object? arguments;

  /// Layar perantara yang di-push SEBELUM [route], urut dari bawah. Dipakai
  /// supaya "back" dari tujuan mendarat di tempat yang masuk akal.
  final List<String> via;
}

/// Parse argumen rute login. `null` = tidak ada pengalihan (default `/member`).
///
/// `/checkout` SELALU dapat `/cart` sebagai perantara walau pemanggil lupa
/// mengirim `via` — inilah kasus yang melahirkan layar putih, jadi jangan
/// bergantung pada tiap pemanggil mengingatnya.
LoginRedirectTarget? parseLoginRedirect(Object? args) {
  String? route;
  Object? arguments;
  var via = const <String>[];

  if (args is String) {
    final trimmed = args.trim();
    if (trimmed.startsWith('/')) route = trimmed;
  } else if (args is Map) {
    final raw = args['redirect'];
    if (raw is String && raw.trim().isNotEmpty) route = raw.trim();
    arguments = args['arguments'];
    final rawVia = args['via'];
    if (rawVia is List) {
      via = rawVia.whereType<String>().where((r) => r.startsWith('/')).toList();
    }
  }

  if (route == null) return null;
  if (route == '/checkout' && via.isEmpty) via = const ['/cart'];
  return LoginRedirectTarget(route: route, arguments: arguments, via: via);
}

/// Pindah ke tujuan setelah login berhasil.
///
/// Tanpa tujuan → `/member` menggantikan seluruh tumpukan (perilaku lama,
/// dipertahankan: halaman Akun adalah tab utama, "back" dari situ memang
/// keluar). Dengan tujuan → Beranda di dasar, lalu `via`, lalu tujuan.
void navigateAfterLogin(NavigatorState nav, LoginRedirectTarget? target) {
  if (target == null) {
    nav.pushNamedAndRemoveUntil('/member', (route) => false);
    return;
  }
  nav.pushNamedAndRemoveUntil('/', (route) => false);
  for (final route in target.via) {
    nav.pushNamed(route);
  }
  nav.pushNamed(target.route, arguments: target.arguments);
}

/// "Kembali ke Keranjang" dari Checkout tanpa pernah menyisakan Navigator
/// kosong. Kalau ada layar di bawah, pop biasa — Keranjang yang sama, dengan
/// centang item yang masih utuh. Kalau Checkout sendirian, bangun ulang
/// Beranda → Keranjang.
void leaveCheckoutToCart(NavigatorState nav) {
  if (nav.canPop()) {
    nav.pop();
    return;
  }
  nav.pushNamedAndRemoveUntil('/', (route) => false);
  nav.pushNamed('/cart');
}

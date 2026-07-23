import 'package:flutter/material.dart';

import 'motion_prefs.dart';

/// Push ala kartu modal iOS modern (Photos "New", Notes) — dipakai untuk
/// entry point flow posting (Buat Postingan, Tandai Orang video) sebagai
/// pengganti `MaterialPageRoute(fullscreenDialog: true)` polos.
///
/// Beda dari slide bawah standar: sudut ATAS membulat sepanjang presentasi
/// (bukan cuma saat animasi) + kurva spring-out (`Cubic(0.22,1,0.36,1)`,
/// setara `cubic-bezier` iOS) alih-alih ease linear. Reduced-motion (OS
/// atau toggle Settings) → fallback fade instan tanpa slide/radius.
Route<T> cardModalRoute<T>(WidgetBuilder builder, {RouteSettings? settings}) {
  return PageRouteBuilder<T>(
    settings: settings,
    fullscreenDialog: true,
    opaque: true,
    transitionDuration: const Duration(milliseconds: 380),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (context, _, __) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (MotionPrefs.shouldReduce(context)) {
        return FadeTransition(opacity: animation, child: child);
      }
      final curved = CurvedAnimation(
        parent: animation,
        curve: const Cubic(0.22, 1, 0.36, 1),
        reverseCurve: Curves.easeInCubic,
      );
      return ColoredBox(
        // Backdrop di balik sudut membulat — tanpa ini, area kecil di luar
        // arc ClipRRect transparan dan menampakkan warna default MaterialApp
        // (bisa putih) sekejap di frame pertama sebelum child ter-paint.
        color: Colors.black,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        ),
      );
    },
  );
}

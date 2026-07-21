import 'package:flutter/material.dart';

/// Route standar untuk semua alur grid→viewer post. Model IG/TikTok:
/// halaman viewer TIDAK PERNAH menggeser horizontal — ia MENUTUP LAYAR PENUH
/// (opaque) dengan transisi FADE, sementara media terbang tile↔slot lewat
/// [PostHero] di overlay framework (dua arah: push DAN pop, tanpa gating).
/// Dismiss vertikal (drag-down) disediakan oleh viewer sendiri (maybePop).
/// TANPA state machine, TANPA pengukuran geometri manual, TANPA slide native.
class PostViewerRoute<T> extends PageRouteBuilder<T> {
  PostViewerRoute({required WidgetBuilder builder})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionDuration: const Duration(milliseconds: 300),
          reverseTransitionDuration: const Duration(milliseconds: 300),
          // WAJIB opaque: begitu terbuka, viewer menutupi grid sepenuhnya —
          // TIDAK ada tap-through ke tile di bawahnya (regresi lama).
          opaque: true,
          maintainState: true,
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          ),
        );
}

Future<T?> pushPostViewer<T>(BuildContext context,
    {required WidgetBuilder builder}) {
  return Navigator.of(context).push<T>(PostViewerRoute<T>(builder: builder));
}

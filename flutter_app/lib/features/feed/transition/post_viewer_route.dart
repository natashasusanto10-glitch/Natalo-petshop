import 'package:flutter/material.dart';

/// Route standar untuk semua alur grid→viewer post. Chrome fade; media
/// terbang via [PostHero] di overlay framework. TANPA state machine, TANPA
/// pengukuran geometri manual, TANPA gesture kustom.
class PostViewerRoute<T> extends PageRouteBuilder<T> {
  PostViewerRoute({required WidgetBuilder builder})
      : super(
          opaque: true,
          transitionDuration: const Duration(milliseconds: 280),
          reverseTransitionDuration: const Duration(milliseconds: 240),
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              FadeTransition(
            opacity:
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            child: child,
          ),
        );
}

Future<T?> pushPostViewer<T>(BuildContext context,
    {required WidgetBuilder builder}) {
  return Navigator.of(context).push<T>(PostViewerRoute<T>(builder: builder));
}

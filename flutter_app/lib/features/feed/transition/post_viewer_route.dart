import 'package:flutter/material.dart';

/// Route standar untuk semua alur grid→viewer post. Chrome pakai transisi
/// NATIVE per platform (iOS: Cupertino slide + native edge-swipe back;
/// Android: platform default + Predictive Back) via [MaterialPageRoute].
/// Media terbang via [PostHero] di overlay framework. TANPA state machine,
/// TANPA pengukuran geometri manual, TANPA gesture kustom.
class PostViewerRoute<T> extends MaterialPageRoute<T> {
  PostViewerRoute({required super.builder});
}

Future<T?> pushPostViewer<T>(BuildContext context,
    {required WidgetBuilder builder}) {
  return Navigator.of(context).push<T>(PostViewerRoute<T>(builder: builder));
}

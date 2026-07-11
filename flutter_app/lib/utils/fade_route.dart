import 'package:flutter/material.dart';

/// Route fade-through premium untuk flow posting (pola sama dgn
/// showCaptionEditModal). Dipakai supaya transisi antar layar post terasa
/// halus, bukan slide default.
Route<T> fadeThroughRoute<T>(Widget page, {bool fullscreenDialog = false}) {
  return PageRouteBuilder<T>(
    fullscreenDialog: fullscreenDialog,
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, animation, __, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
      child: child,
    ),
  );
}

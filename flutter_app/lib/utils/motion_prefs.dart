import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reduce motion preference — respect user accessibility setting yang
/// disable animasi besar (helpful untuk vestibular sensitivity / motion
/// sickness). Sumber preferensi:
/// 1. OS setting `MediaQuery.disableAnimations` (system-wide reduce motion)
/// 2. User explicit toggle di Settings → "Kurangi animasi"
///
/// Widget pakai `MotionPrefs.shouldReduce(context)` untuk decide:
/// - Skip atau perpendek animation duration
/// - Skip particle effects / confetti / hero animations
/// - Tetap kasih state change tapi tanpa transition
class MotionPrefs extends ChangeNotifier {
  static const _kKey = 'natalo_reduce_motion';
  bool _userReduce = false;
  bool _initialized = false;

  bool get userReduce => _userReduce;
  bool get initialized => _initialized;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _userReduce = prefs.getBool(_kKey) ?? false;
    } catch (_) {}
    _initialized = true;
    notifyListeners();
  }

  Future<void> setReduce(bool value) async {
    _userReduce = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kKey, value);
    } catch (_) {}
  }

  /// Combine OS setting + user setting. Either one → reduce.
  static bool shouldReduce(BuildContext context) {
    final osReduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return osReduce || motionPrefs._userReduce;
  }

  /// Effective duration — kalau reduce motion, kembalikan 0ms.
  static Duration effective(BuildContext context, Duration normal) {
    return shouldReduce(context) ? Duration.zero : normal;
  }
}

final motionPrefs = MotionPrefs();

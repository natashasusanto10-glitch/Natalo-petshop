import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Motion preference store — respect OS reduce-motion + user manual toggle
/// di Settings. Widget yang punya animation panjang check via
/// `MotionPrefs.shouldReduce(context)` lalu skip / shorten animation.
class MotionPrefs extends ChangeNotifier {
  MotionPrefs._();

  static const _key = 'motion_prefs_user_reduce';

  bool _userReduce = false;
  bool _initialized = false;

  bool get userReduce => _userReduce;
  bool get initialized => _initialized;

  Future<void> initialize() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    _userReduce = prefs.getBool(_key) ?? false;
    _initialized = true;
    notifyListeners();
  }

  Future<void> setUserReduce(bool value) async {
    if (_userReduce == value) return;
    _userReduce = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }

  /// Static helper — true kalau OS reduce motion ON atau user toggle ON.
  /// Dipakai di builder widget tanpa harus listen perubahan.
  static bool shouldReduce(BuildContext context) {
    final osReduce = MediaQuery.disableAnimationsOf(context);
    return osReduce || motionPrefs._userReduce;
  }
}

/// Singleton instance — initialized di main() sebelum runApp.
final MotionPrefs motionPrefs = MotionPrefs._();

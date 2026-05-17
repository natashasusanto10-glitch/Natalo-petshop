import 'package:haptic_feedback/haptic_feedback.dart';

/// Wrapper haptic feedback yang gracefully no-op kalau hardware tidak support
/// atau Settings haptics OFF (di-cek via MotionPrefs.allowHaptic).
class AppHaptics {
  AppHaptics._();

  /// Light tap — untuk button press, toggle, select.
  static Future<void> tap() async {
    try {
      await Haptics.vibrate(HapticsType.light);
    } catch (_) {
      // No-op kalau hardware tidak support / permission denied.
    }
  }

  /// Medium impact — untuk action confirmed (add to cart, login success).
  static Future<void> impact() async {
    try {
      await Haptics.vibrate(HapticsType.medium);
    } catch (_) {}
  }

  /// Success notification — untuk task completed (order placed, payment ok).
  static Future<void> success() async {
    try {
      await Haptics.vibrate(HapticsType.success);
    } catch (_) {}
  }

  /// Warning — untuk validation error, stock habis, dll.
  static Future<void> warning() async {
    try {
      await Haptics.vibrate(HapticsType.warning);
    } catch (_) {}
  }

  /// Error — untuk action gagal critical.
  static Future<void> error() async {
    try {
      await Haptics.vibrate(HapticsType.error);
    } catch (_) {}
  }

  /// Selection — sticky toggle, segment switch.
  static Future<void> selection() async {
    try {
      await Haptics.vibrate(HapticsType.selection);
    } catch (_) {}
  }
}

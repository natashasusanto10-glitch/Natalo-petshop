import 'package:haptic_feedback/haptic_feedback.dart';

/// Helper untuk haptic feedback yang match perilaku PWA Capacitor
/// (lib/native/haptics.tsx di toko-pwa-starter).
///
/// Pakai try-catch supaya gagal di simulator atau device tanpa hardware
/// vibrator tidak crash app — haptic adalah affordance, bukan fungsi inti.
class AppHaptics {
  /// Light tap — tap CTA biasa, toggle filter, dll. Setara hapticTap PWA.
  static Future<void> tap() async {
    try {
      if (await Haptics.canVibrate()) {
        await Haptics.vibrate(HapticsType.selection);
      }
    } catch (_) {}
  }

  /// Medium impact — add to cart, apply voucher, tindakan yang punya
  /// konsekuensi state (bukan hanya navigasi).
  static Future<void> impact() async {
    try {
      if (await Haptics.canVibrate()) {
        await Haptics.vibrate(HapticsType.medium);
      }
    } catch (_) {}
  }

  /// Success notification — order placed, voucher claimed, profile saved.
  static Future<void> success() async {
    try {
      if (await Haptics.canVibrate()) {
        await Haptics.vibrate(HapticsType.success);
      }
    } catch (_) {}
  }

  /// Warning — out of stock, payment failed, validation error.
  static Future<void> warning() async {
    try {
      if (await Haptics.canVibrate()) {
        await Haptics.vibrate(HapticsType.warning);
      }
    } catch (_) {}
  }
}

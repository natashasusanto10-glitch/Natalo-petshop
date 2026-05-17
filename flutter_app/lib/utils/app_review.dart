import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Helper untuk request in-app review (native Play Store / App Store prompt).
///
/// Match perilaku Capacitor `@capacitor-community/in-app-review` di PWA:
/// hanya prompt setelah event positif (order success), dengan cooldown
/// supaya user tidak di-spam.
///
/// Google Play sendiri batasi ke 1 prompt per beberapa bulan, jadi cooldown
/// kita di sini lebih ke best practice — kalau API quota habis, request
/// silent no-op (tidak ada UI dialog yang muncul).
class AppReview {
  static const _lastPromptKey = 'natalo_last_review_prompt_ms';
  static const _cooldownDays = 30;

  static final _instance = InAppReview.instance;

  /// Coba request review prompt. Akan no-op kalau:
  /// - Belum lewat cooldown sejak prompt terakhir
  /// - Native API tidak tersedia di device
  /// - Quota Google Play habis
  static Future<void> maybeRequest() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastMs = prefs.getInt(_lastPromptKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      final cooldownMs =
          const Duration(days: _cooldownDays).inMilliseconds;

      if (now - lastMs < cooldownMs) return;
      if (!await _instance.isAvailable()) return;

      await _instance.requestReview();
      await prefs.setInt(_lastPromptKey, now);
    } catch (_) {
      // Silent — review prompt adalah nice-to-have, bukan blocking flow.
    }
  }
}

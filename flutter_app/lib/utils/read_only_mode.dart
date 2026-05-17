import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'haptics.dart';

/// Read-only mode — flag global yang membungkus semua endpoint mutation
/// dan throw [ReadOnlyModeException] supaya Capacitor production database
/// tidak tersentuh dari Flutter testing.
///
/// Default behavior:
/// - **Release build** → ON (read-only) sampai launch siap
/// - **Debug build** → ON (kita override via Settings → Toggle untuk write)
///
/// Override runtime: Settings → "Mode Server" → toggle.
///
/// API:
/// ```dart
/// await readOnlyMode.initialize();        // di main(), sekali
/// final canWrite = readOnlyMode.canWrite; // sync check
/// readOnlyMode.assertWritable('checkout'); // throws kalau lock
/// ```
class ReadOnlyMode extends ChangeNotifier {
  static const _kStorageKey = 'natalo_read_only_mode';
  // Welcome dialog flag — supaya dialog "Mode review" cuma muncul sekali
  // sampai user explicitly dismiss. Di-clear saat user toggle write mode.
  static const _kWelcomeDismissedKey = 'natalo_review_mode_welcome_dismissed';

  bool _isReadOnly = true;
  bool _initialized = false;

  bool get isReadOnly => _isReadOnly;
  bool get canWrite => !_isReadOnly;
  bool get initialized => _initialized;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      // Default true — safer.
      _isReadOnly = prefs.getBool(_kStorageKey) ?? true;
    } catch (_) {
      _isReadOnly = true;
    }
    _initialized = true;
    notifyListeners();
  }

  Future<void> setReadOnly(bool value) async {
    _isReadOnly = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kStorageKey, value);
      // Reset welcome dialog flag — supaya kalau user kembali ke
      // read-only mode, dialog muncul lagi sebagai reminder.
      if (value) {
        await prefs.remove(_kWelcomeDismissedKey);
      }
    } catch (_) {}
  }

  /// Throw kalau mode read-only. Caller services pakai ini di awal
  /// method mutation untuk fail-fast sebelum hit network.
  void assertWritable(String operation) {
    if (_reviewModeAllowedWrites.contains(operation)) return;
    if (_isReadOnly) {
      throw ReadOnlyModeException(operation);
    }
  }

  static Future<bool> isWelcomeDismissed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_kWelcomeDismissedKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> markWelcomeDismissed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kWelcomeDismissedKey, true);
    } catch (_) {}
  }
}

const _reviewModeAllowedWrites = {
  'feed_like',
  'feed_comment',
  'feed_comment_like',
  'feed_share',
  'review_helpful',
  'review_submit',
  'review_photo_upload',
  'review_update',
  'review_delete',
};

/// Exception ketika user mencoba write operation di read-only mode.
/// Caller (UI) tangkap ini lalu tampilkan snackbar friendly.
class ReadOnlyModeException implements Exception {
  final String operation;
  const ReadOnlyModeException(this.operation);

  @override
  String toString() => 'Mode review aktif — $operation sementara nonaktif.';
}

/// Helper untuk tampilkan snackbar kalau dapat ReadOnlyModeException.
/// Pakai di catch block di screen.
///
/// Contoh:
/// ```dart
/// try { await orderService.createOrder(...); }
/// on ReadOnlyModeException catch (e) {
///   showReadOnlySnackbar(context, e);
/// }
/// ```
void showReadOnlySnackbar(BuildContext context, ReadOnlyModeException e) {
  AppHaptics.warning();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFFF59E0B),
      content: Row(
        children: [
          const Icon(Icons.visibility_outlined, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Mode review aktif. ${_friendlyLabel(e.operation)} sementara nonaktif.',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      duration: const Duration(seconds: 3),
    ),
  );
}

String _friendlyLabel(String op) {
  switch (op) {
    case 'checkout':
      return 'Checkout';
    case 'cart_sync':
      return 'Sinkron cart ke server';
    case 'address_create':
      return 'Tambah alamat';
    case 'address_update':
      return 'Update alamat';
    case 'address_delete':
      return 'Hapus alamat';
    case 'profile_update':
      return 'Update profil';
    case 'review_submit':
      return 'Submit review';
    case 'review_photo_upload':
      return 'Upload foto review';
    case 'voucher_claim':
      return 'Klaim voucher';
    case 'feed_like':
      return 'Like postingan';
    case 'feed_comment':
      return 'Komentar Feed';
    case 'feed_comment_like':
      return 'Like komentar';
    case 'feed_share':
      return 'Share Feed';
    case 'feed_delete':
      return 'Hapus postingan';
    case 'payment_proof':
      return 'Upload bukti bayar';
    case 'register':
      return 'Daftar member';
    case 'view_tracking':
      return 'View tracking';
    default:
      return op;
  }
}

// Singleton — pakai di seluruh app.
final readOnlyMode = ReadOnlyMode();

/// Debug-only check apakah kita di kReleaseMode atau debug.
/// Settings toggle disable di release build (user tidak boleh switch
/// ke write mode di production build sampai launch siap).
bool get canToggleReadOnly => !kReleaseMode;

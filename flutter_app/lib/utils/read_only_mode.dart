import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Read-only mode — flag global yang membungkus semua endpoint mutation
/// dan throw [ReadOnlyModeException] supaya Capacitor production database
/// tidak tersentuh dari Flutter testing.
///
/// Default behavior:
/// - **Release build** → ON (read-only) sampai launch siap
/// - **Debug build** → OFF supaya QA bisa test checkout/write flow
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
  ReadOnlyMode._();

  static const String _kStorageKey = 'natalo_read_only_mode';

  bool _enabled = kReleaseMode;
  bool _initialized = false;

  bool get enabled => _enabled;
  /// Alias `enabled` — beberapa code pakai `isReadOnly`.
  bool get isReadOnly => _enabled;
  bool get initialized => _initialized;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      // Release tetap aman by default, debug bebas untuk QA flow checkout.
      _enabled = prefs.getBool(_kStorageKey) ?? kReleaseMode;
    } catch (_) {
      _enabled = kReleaseMode;
    }
    _initialized = true;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kStorageKey, value);
  }

  /// Throw kalau read-only ON — dipanggil di service mutation entry point.
  void guard([String? operation]) {
    if (_enabled) {
      throw ReadOnlyModeException(operation);
    }
  }

  /// Alias `guard` — beberapa code pakai `assertWritable`.
  void assertWritable([String? operation]) => guard(operation);
}

class ReadOnlyModeException implements Exception {
  final String? operation;
  const ReadOnlyModeException([this.operation]);

  @override
  String toString() =>
      'ReadOnlyModeException: ${operation ?? 'mutation'} blocked (read-only mode active)';
}

/// Singleton.
final ReadOnlyMode readOnlyMode = ReadOnlyMode._();

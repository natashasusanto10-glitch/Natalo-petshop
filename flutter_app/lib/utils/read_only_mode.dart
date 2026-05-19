import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Read-only mode — flag global yang membungkus semua endpoint mutation
/// dan throw [ReadOnlyModeException] supaya Capacitor production database
/// tidak tersentuh dari Flutter testing.
///
/// Default behavior:
/// - OFF untuk semua build app user-facing.
/// - Bisa diaktifkan manual lewat Settings/internal QA kalau perlu mode aman.
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
  static const String _kWritableDefaultMigrationKey =
      'natalo_read_only_mode_writable_default_v1';

  bool _enabled = false;
  bool _initialized = false;

  bool get enabled => _enabled;

  /// Alias `enabled` — beberapa code pakai `isReadOnly`.
  bool get isReadOnly => _enabled;
  bool get initialized => _initialized;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final migrated = prefs.getBool(_kWritableDefaultMigrationKey) ?? false;
      if (!migrated) {
        // Legacy TestFlight builds defaulted release mode to read-only and
        // persisted that value. Flip it once so real member actions work.
        _enabled = false;
        await prefs.setBool(_kStorageKey, false);
        await prefs.setBool(_kWritableDefaultMigrationKey, true);
      } else {
        _enabled = prefs.getBool(_kStorageKey) ?? false;
      }
    } catch (_) {
      _enabled = false;
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

void showReadOnlySnackbar(BuildContext context, ReadOnlyModeException error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: const Text(
        'Mode aman aktif. Aksi ini tidak mengubah data server.',
      ),
      behavior: SnackBarBehavior.floating,
      action: SnackBarAction(
        label: 'OK',
        onPressed: () {},
      ),
    ),
  );
}

/// Singleton.
final ReadOnlyMode readOnlyMode = ReadOnlyMode._();

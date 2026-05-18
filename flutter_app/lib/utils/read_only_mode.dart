import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Read-only safety flag — saat ON, service mutation (add to cart, place
/// order, dll) throws ReadOnlyModeException. Default ON sampai user
/// explicit toggle off di Settings, supaya production database Capacitor
/// tidak ke-mutate dari Flutter side selama development / testing.
class ReadOnlyMode extends ChangeNotifier {
  ReadOnlyMode._();

  static const _key = 'read_only_mode_enabled';

  bool _enabled = true;
  bool _initialized = false;

  bool get enabled => _enabled;
  /// Alias `enabled` — beberapa code pakai `isReadOnly`.
  bool get isReadOnly => _enabled;
  bool get initialized => _initialized;

  Future<void> initialize() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_key) ?? true;
    _initialized = true;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
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

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App settings — theme mode (light/dark/system), haptics, dll. Diakses via
/// AnimatedBuilder di MaterialApp supaya rebuild saat theme switch.
class AppSettingsStore extends ChangeNotifier {
  AppSettingsStore._();

  static const _themeModeKey = 'settings_theme_mode';
  static const _hapticsKey = 'settings_haptics_enabled';
  static const _feedAutoplayKey = 'settings_feed_autoplay';
  static const _feedVideoQualityKey = 'settings_feed_video_quality';
  static const _feedMutedKey = 'settings_feed_muted';
  static const _appLockEnabledKey = 'settings_app_lock_enabled';

  ThemeMode _themeMode = ThemeMode.system;
  bool _hapticsEnabled = true;

  /// Auto-play video saat masuk viewport feed. Default ON.
  bool _feedAutoplay = true;

  /// 'auto' (network tier), 'high', 'medium', 'low'. Default 'auto'.
  String _feedVideoQuality = 'auto';

  /// Default mute saat start playback — match Instagram Reels behavior.
  bool _feedMuted = true;

  /// Biometric app lock — saat ON, AppLockGate tampilkan lock screen di
  /// cold start + setiap app kembali dari background (>= 60 detik).
  /// User harus authenticate via Face ID / Touch ID / PIN sebelum akses.
  /// TERPISAH dari biometricService.isEnabled() yang khusus untuk LOGIN
  /// auto-fill credential (beda use case).
  bool _appLockEnabled = false;
  bool _initialized = false;

  ThemeMode get themeMode => _themeMode;
  bool get hapticsEnabled => _hapticsEnabled;
  bool get feedAutoplay => _feedAutoplay;
  String get feedVideoQuality => _feedVideoQuality;
  String get feedVideoQualityLabel {
    return switch (_feedVideoQuality) {
      'high' => 'Tinggi',
      'data_saver' => 'Hemat Data',
      _ => 'Otomatis',
    };
  }

  bool get feedMuted => _feedMuted;
  bool get appLockEnabled => _appLockEnabled;
  bool get initialized => _initialized;

  /// Sync init — fire-and-forget. Default value sudah masuk akal walau disk
  /// belum dibaca, jadi first paint tidak salah.
  void initialize() {
    if (_initialized) return;
    _initialized = true;
    _loadFromDisk();
  }

  Future<void> _loadFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mode = prefs.getString(_themeModeKey);
      if (mode != null) {
        _themeMode = ThemeMode.values.firstWhere(
          (m) => m.name == mode,
          orElse: () => ThemeMode.system,
        );
      }
      _hapticsEnabled = prefs.getBool(_hapticsKey) ?? true;
      _feedAutoplay = prefs.getBool(_feedAutoplayKey) ?? true;
      _feedVideoQuality = prefs.getString(_feedVideoQualityKey) ?? 'auto';
      _feedMuted = prefs.getBool(_feedMutedKey) ?? true;
      _appLockEnabled = prefs.getBool(_appLockEnabledKey) ?? false;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setAppLockEnabled(bool value) async {
    if (_appLockEnabled == value) return;
    _appLockEnabled = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_appLockEnabledKey, value);
    } catch (_) {}
  }

  Future<void> setFeedAutoplay(bool value) async {
    if (_feedAutoplay == value) return;
    _feedAutoplay = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_feedAutoplayKey, value);
    } catch (_) {}
  }

  Future<void> setFeedVideoQuality(String value) async {
    if (_feedVideoQuality == value) return;
    _feedVideoQuality = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_feedVideoQualityKey, value);
    } catch (_) {}
  }

  Future<void> setFeedMuted(bool value) async {
    if (_feedMuted == value) return;
    _feedMuted = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_feedMutedKey, value);
    } catch (_) {}
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_themeModeKey, mode.name);
    } catch (_) {}
  }

  Future<void> setHapticsEnabled(bool value) async {
    if (_hapticsEnabled == value) return;
    _hapticsEnabled = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_hapticsKey, value);
    } catch (_) {}
  }
}

final AppSettingsStore appSettingsStore = AppSettingsStore._();

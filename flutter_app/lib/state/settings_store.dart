import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-level settings (theme mode, dll) yang persist ke disk.
/// Match keuntungan native Flutter atas Capacitor: PWA Natalo lock ke
/// light mode di `globals.css`; Flutter punya kebebasan support 3 mode.
class AppSettingsStore extends ChangeNotifier {
  static const _kThemeMode = 'natalo_theme_mode';
  static const _kFeedAutoplay = 'natalo_feed_autoplay';
  static const _kFeedVideoQuality = 'natalo_feed_video_quality';
  static const _kFeedMuted = 'natalo_feed_muted';

  ThemeMode _themeMode = ThemeMode.light;
  bool _feedAutoplay = true;
  String _feedVideoQuality = 'auto';
  bool _feedMuted = false;
  bool _initialized = false;

  ThemeMode get themeMode => _themeMode;
  bool get feedAutoplay => _feedAutoplay;
  String get feedVideoQuality => _feedVideoQuality;
  bool get feedMuted => _feedMuted;
  String get feedVideoQualityLabel {
    switch (_feedVideoQuality) {
      case 'data_saver':
        return 'Hemat Data';
      case 'high':
        return 'Tinggi';
      case 'auto':
      default:
        return 'Otomatis';
    }
  }

  bool get initialized => _initialized;
  bool get isDarkMode {
    if (_themeMode == ThemeMode.dark) return true;
    if (_themeMode == ThemeMode.light) return false;
    // System mode → check current platform brightness
    final brightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    return brightness == Brightness.dark;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kThemeMode);
      _themeMode = _parseThemeMode(raw);
      _feedAutoplay = prefs.getBool(_kFeedAutoplay) ?? true;
      _feedVideoQuality =
          _parseFeedVideoQuality(prefs.getString(_kFeedVideoQuality));
      _feedMuted = prefs.getBool(_kFeedMuted) ?? false;
    } catch (_) {
      _themeMode = ThemeMode.light;
      _feedAutoplay = true;
      _feedVideoQuality = 'auto';
      _feedMuted = false;
    }
    _initialized = true;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kThemeMode, _encodeThemeMode(mode));
    } catch (_) {}
  }

  Future<void> setFeedAutoplay(bool value) async {
    if (_feedAutoplay == value) return;
    _feedAutoplay = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kFeedAutoplay, value);
    } catch (_) {}
  }

  Future<void> setFeedVideoQuality(String value) async {
    final parsed = _parseFeedVideoQuality(value);
    if (_feedVideoQuality == parsed) return;
    _feedVideoQuality = parsed;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kFeedVideoQuality, parsed);
    } catch (_) {}
  }

  Future<void> setFeedMuted(bool value) async {
    if (_feedMuted == value) return;
    _feedMuted = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kFeedMuted, value);
    } catch (_) {}
  }

  static ThemeMode _parseThemeMode(String? raw) {
    switch (raw) {
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      case 'light':
      default:
        return ThemeMode.light;
    }
  }

  static String _encodeThemeMode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
      case ThemeMode.light:
        return 'light';
    }
  }

  static String _parseFeedVideoQuality(String? raw) {
    switch (raw) {
      case 'data_saver':
      case 'high':
      case 'auto':
        return raw!;
      default:
        return 'auto';
    }
  }
}

final appSettingsStore = AppSettingsStore();

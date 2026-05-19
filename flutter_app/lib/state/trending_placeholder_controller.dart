import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';

/// Controller untuk dynamic placeholder di search bar Beranda.
///
/// Rotate placeholder otomatis setiap 4 detik (range spec 3.5-5),
/// pakai data trending dari backend API `/api/search/trending-placeholders`.
/// Kalau API fail/empty, fallback ke static list lokal.
///
/// Performance: ChangeNotifier — hanya widget yang explicit listen
/// (via AnimatedBuilder/ValueListenableBuilder) yang rebuild. Banner,
/// kategori, produk section TIDAK rebuild saat placeholder berubah.
///
/// State flags:
/// - `_paused = false` (default) → Timer.periodic aktif
/// - `_paused = true` (saat user type/focus) → Timer cancelled
///
/// API endpoint contract (per spec):
/// ```json
/// {
///   "items": [
///     {"type": "brand", "label": "Royal Canin", "placeholder": "Cari Royal Canin", "score": 982},
///     {"type": "category", "label": "Pasir", "placeholder": "Cari pasir kucing", "score": 784},
///     ...
///   ]
/// }
/// ```
class TrendingPlaceholderController extends ChangeNotifier {
  TrendingPlaceholderController._();

  // Fallback static — dipakai saat API fail / empty / belum loaded.
  // Bukan source of truth permanent — cuma cadangan.
  static const _fallback = <String>[
    'Cari makanan kucing',
    'Cari makanan anjing',
    'Cari pasir kucing',
    'Cari vitamin hewan',
    'Cari snack kucing',
    'Cari Royal Canin',
    'Cari Whiskas',
    'Cari Happy Cat',
  ];

  static const _rotateInterval = Duration(seconds: 4);
  static const _fetchTimeout = Duration(seconds: 6);
  static const _defaultHint = 'Cari makanan, pasir, vitamin...';

  List<String> _items = const [];
  int _currentIndex = 0;
  Timer? _timer;
  bool _paused = false;
  bool _initialized = false;

  /// Current placeholder text — fallback ke default kalau items kosong.
  String get currentPlaceholder {
    if (_items.isEmpty) return _defaultHint;
    return _items[_currentIndex % _items.length];
  }

  bool get isInitialized => _initialized;
  bool get isPaused => _paused;

  /// Initialize controller — load fallback dulu (fast path), lalu fetch
  /// API di background. Idempotent — boleh dipanggil multiple kali.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Fast path: set fallback langsung supaya UI ada konten dari frame
    // pertama. Rotation start dengan fallback.
    _items = List<String>.from(_fallback);
    notifyListeners();
    _startRotation();

    // Background fetch — replace items kalau API return valid data.
    unawaited(_refresh());
  }

  /// Force refresh dari API (mis. pull-to-refresh, atau retry).
  Future<void> _refresh() async {
    try {
      final fetched = await _fetchFromApi();
      if (fetched.isNotEmpty) {
        _items = fetched;
        _currentIndex = 0;
        notifyListeners();
        // Restart timer dengan new items (kalau >1 item).
        _startRotation();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[trendingPlaceholderController] refresh fail: $e');
      }
      // Silent — fallback tetap aktif.
    }
  }

  Future<List<String>> _fetchFromApi() async {
    final uri = ApiConfig.uri('/api/search/trending-placeholders');
    final res = await http.get(uri).timeout(_fetchTimeout);
    if (res.statusCode != 200) return const [];
    final body = jsonDecode(res.body);
    if (body is! Map<String, dynamic>) return const [];
    final itemsJson = body['items'];
    if (itemsJson is! List) return const [];
    final list = itemsJson
        .whereType<Map<String, dynamic>>()
        .map((m) => (m['placeholder'] ?? '').toString().trim())
        .where((s) => s.isNotEmpty && s.length <= 60)
        .take(12) // cap supaya rotation tidak terlalu panjang
        .toList();
    return list;
  }

  /// Start Timer.periodic — cancel previous timer dulu. No-op kalau
  /// paused atau cuma 1 item (tidak ada gunanya rotate satu item).
  void _startRotation() {
    _timer?.cancel();
    if (_paused) return;
    if (_items.length <= 1) return;
    _timer = Timer.periodic(_rotateInterval, (_) {
      if (_paused) return;
      _currentIndex = (_currentIndex + 1) % _items.length;
      notifyListeners();
    });
  }

  /// Pause rotation — dipanggil saat user focus / type di TextField
  /// search. Placeholder tetap tampil current value tapi tidak ganti.
  void pause() {
    if (_paused) return;
    _paused = true;
    _timer?.cancel();
    _timer = null;
  }

  /// Resume rotation — dipanggil saat user unfocus / clear input.
  void resume() {
    if (!_paused) return;
    _paused = false;
    _startRotation();
  }

  // Singleton lifetime = app lifetime; tidak ada dispose call expected.
  // Tetap override untuk safety kalau ada test injection.
  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final TrendingPlaceholderController trendingPlaceholderController =
    TrendingPlaceholderController._();

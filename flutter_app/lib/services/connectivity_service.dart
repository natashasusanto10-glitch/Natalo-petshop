import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Connectivity service — emit ChangeNotifier yang kasih tau widget tree
/// kalau device offline / online. Auto subscribe ke native connectivity
/// changes (WiFi on/off, mobile data toggle, airplane mode, dll).
///
/// Pakai pattern: `AnimatedBuilder(animation: connectivityService, ...)`
/// di banner widget. Saat status berubah, builder rebuild.
class ConnectivityService extends ChangeNotifier {
  bool _online = true;
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _initialized = false;

  bool get isOnline => _online;
  bool get isOffline => !_online;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final initial = await Connectivity().checkConnectivity();
      _online = _resolveOnline(initial);
      _sub = Connectivity().onConnectivityChanged.listen((results) {
        final next = _resolveOnline(results);
        if (next != _online) {
          _online = next;
          notifyListeners();
        }
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[connectivity] init failed: $e');
    }
  }

  bool _resolveOnline(List<ConnectivityResult> results) {
    if (results.isEmpty) return false;
    // Online kalau setidaknya ada satu connection type yang bukan `none`.
    return results.any((r) => r != ConnectivityResult.none);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final connectivityService = ConnectivityService();

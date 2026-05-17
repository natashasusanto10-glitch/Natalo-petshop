import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Subscribe ke native connectivity changes — banner offline auto-show
/// saat WiFi/data hilang.
class ConnectivityService extends ChangeNotifier {
  ConnectivityService._();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _online = true;
  bool _initialized = false;

  bool get isOnline => _online;
  bool get isOffline => !_online;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final initial = await _connectivity.checkConnectivity();
      _online = _hasNet(initial);
      _sub = _connectivity.onConnectivityChanged.listen((results) {
        final next = _hasNet(results);
        if (next != _online) {
          _online = next;
          notifyListeners();
        }
      });
    } catch (_) {
      // Permission denied / platform tidak support — assume online.
      _online = true;
    }
    notifyListeners();
  }

  bool _hasNet(List<ConnectivityResult> results) {
    return results.any((r) => r != ConnectivityResult.none);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final ConnectivityService connectivityService = ConnectivityService._();

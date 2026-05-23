import 'dart:async';

import 'package:flutter/foundation.dart';

/// Small client-side throttle for tap/action handlers.
///
/// Use this for user actions that should not fire repeatedly from rapid taps.
/// It is intentionally local and lightweight; backend rate limits still remain
/// the source of truth for API protection.
class ActionThrottle {
  ActionThrottle({
    this.interval = const Duration(milliseconds: 650),
  });

  final Duration interval;
  DateTime? _lastRunAt;

  bool get isCoolingDown {
    final lastRunAt = _lastRunAt;
    if (lastRunAt == null) return false;
    return DateTime.now().difference(lastRunAt) < interval;
  }

  bool run(VoidCallback? action) {
    if (action == null || isCoolingDown) return false;
    _lastRunAt = DateTime.now();
    action();
    return true;
  }

  Future<bool> runAsync(FutureOr<void> Function()? action) async {
    if (action == null || isCoolingDown) return false;
    _lastRunAt = DateTime.now();
    await action();
    return true;
  }

  void reset() {
    _lastRunAt = null;
  }
}

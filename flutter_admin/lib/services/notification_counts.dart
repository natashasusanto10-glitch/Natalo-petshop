import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// Aggregate notif counter — dipakai HomeShell untuk badge bottom nav.
///
/// Pattern: ChangeNotifier singleton supaya screen yang care bisa
/// `listen` tanpa rebuild seluruh tree. Refresh saat:
///   - HomeShell init (warm)
///   - AppLifecycleState.resumed (admin balik dari background)
///   - Auto-poll 60s (fallback kalau push notif belum aktif)
///   - Setelah action selesai (admin approve/reject — manual call)
class NotificationCounts extends ChangeNotifier {
  NotificationCounts._();
  static final NotificationCounts instance = NotificationCounts._();

  int _ordersPending = 0;
  int _cancelRequests = 0;
  int _waitingPayment = 0;
  int _feedPending = 0;
  int _abuseFlagsOpen = 0;
  bool _loading = false;

  int get ordersPending => _ordersPending;
  int get cancelRequests => _cancelRequests;
  int get waitingPayment => _waitingPayment;
  int get feedPending => _feedPending;
  int get abuseFlagsOpen => _abuseFlagsOpen;
  bool get loading => _loading;

  /// Total badge untuk tab Pesanan — order baru + cancel request urgent.
  int get ordersTabBadge => _ordersPending + _cancelRequests;

  /// Total badge untuk tab Akun (Settings) — feed pending + abuse flag.
  /// Settings tab dipakai sebagai bucket "perlu review" karena entrypoint
  /// Moderasi Feed + Abuse Flags ada di sana.
  int get accountTabBadge => _feedPending + _abuseFlagsOpen;

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    try {
      final data = await adminApi.getJson(
        '/api/admin/notification-counts',
        timeout: const Duration(seconds: 6),
      );
      if (data is Map<String, dynamic>) {
        _ordersPending = _intOf(data['ordersPending']);
        _cancelRequests = _intOf(data['cancelRequests']);
        _waitingPayment = _intOf(data['waitingPayment']);
        _feedPending = _intOf(data['feedPending']);
        _abuseFlagsOpen = _intOf(data['abuseFlagsOpen']);
        notifyListeners();
      }
    } catch (e) {
      // Silent — badge cuma "nice to have", jangan distract admin dgn
      // error toast tiap kali server hiccup. Counter akan refresh next
      // tick / lifecycle resume.
      if (kDebugMode) debugPrint('[notifCounts] refresh failed: $e');
    } finally {
      _loading = false;
    }
  }

  int _intOf(dynamic v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }
}

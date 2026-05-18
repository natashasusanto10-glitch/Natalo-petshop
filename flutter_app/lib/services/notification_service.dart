import '../models/app_notification.dart';
import '../utils/read_only_mode.dart';
import 'api_client.dart';

class NotificationResult {
  final List<AppNotification> items;
  final int unreadCount;
  final bool loggedIn;

  const NotificationResult({
    required this.items,
    required this.unreadCount,
    required this.loggedIn,
  });
}

class NotificationService {
  Future<NotificationResult> fetchMine() async {
    final data = await apiClient.getJson('/api/notifications/me');
    if (data is! Map<String, dynamic>) {
      final text = data?.toString().trim() ?? '';
      final looksLikeHtml =
          text.startsWith('<!DOCTYPE html') || text.startsWith('<html');
      throw ApiException(
        looksLikeHtml
            ? 'Server membalas halaman web, bukan data notifikasi.'
            : 'Response notifikasi tidak sesuai format aplikasi.',
      );
    }
    final rawItems = data['items'];
    final items = rawItems is List
        ? rawItems
            .whereType<Map<String, dynamic>>()
            .map(AppNotification.fromApiJson)
            .toList()
        : <AppNotification>[];

    return NotificationResult(
      items: items,
      unreadCount: _asInt(data['unreadCount']),
      loggedIn: data['loggedIn'] == true,
    );
  }

  Future<void> markRead(String id) async {
    if (id.trim().isEmpty) return;
    await apiClient.postJson(
      '/api/notifications/${Uri.encodeComponent(id)}/read',
      body: const <String, dynamic>{},
    );
  }

  /// Mark SEMUA notif unread → read sekaligus. Match endpoint PWA
  /// POST /api/notifications/read-all. Server return updated unreadCount=0.
  Future<void> markAllRead() async {
    readOnlyMode.assertWritable('mark_all_notifications_read');
    try {
      await apiClient.postJson(
        '/api/notifications/read-all',
        body: const <String, dynamic>{},
      );
    } on ApiException catch (error) {
      if (error.statusCode != 404) rethrow;
      await _markVisibleItemsReadIndividually();
    }
  }

  Future<void> _markVisibleItemsReadIndividually() async {
    final result = await fetchMine();
    if (!result.loggedIn) return;
    final unreadItems = result.items.where((item) => !item.read).toList();
    for (final item in unreadItems) {
      try {
        await markRead(item.id);
      } catch (_) {
        // Best-effort fallback untuk server lama yang belum punya
        // /read-all atau masih mengembalikan duplicate-read error.
      }
    }
  }

  /// Fetch notification preferences user (per kategori on/off).
  /// Match GET /api/member/notification-preferences.
  ///
  /// Return Map<kategori, enabled>. Defaults dipakai kalau endpoint belum
  /// implement di backend (graceful fallback).
  Future<Map<String, bool>> fetchPreferences() async {
    try {
      final data =
          await apiClient.getJson('/api/member/notification-preferences');
      final raw = data['preferences'] ?? data;
      if (raw is! Map<String, dynamic>) return _defaultPreferences;
      return {
        for (final entry in raw.entries)
          if (entry.value is bool) entry.key: entry.value as bool,
      };
    } catch (_) {
      return _defaultPreferences;
    }
  }

  /// Sync preferences ke backend. Match PUT /api/member/notification-preferences.
  /// Server menyimpan + filter push notif sebelum kirim ke device.
  Future<void> updatePreferences(Map<String, bool> preferences) async {
    readOnlyMode.assertWritable('update_notification_preferences');
    try {
      await apiClient.putJson(
        '/api/member/notification-preferences',
        body: {'preferences': preferences},
      );
    } catch (_) {
      // Silent fail — preferences masih persist di SharedPreferences lokal,
      // client-side filtering tetap jalan walau server sync gagal.
    }
  }

  static const _defaultPreferences = {
    'order': true,
    'promo': true,
    'voucher': true,
    'newsletter': false,
  };
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

final notificationService = NotificationService();

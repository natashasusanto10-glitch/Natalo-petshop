import 'package:flutter/foundation.dart';

import '../services/chat_service.dart';

/// State chat customer app-wide (unread badge + kill-switch config) —
/// dipakai `AppChatButton` (badge, Task 3) & gating composer/tombol chat
/// (kill-switch, Task 4/5). Pola sama dgn store lain (`favoriteStore` dkk):
/// `ChangeNotifier` + singleton di bawah file ini.
///
/// **Bukan pemilik timer** — polling (`Timer.periodic`) hidup di screen
/// (Task 5), store ini murni state + panggilan fetch sekali jalan supaya
/// gampang diuji tanpa timer nyata.
class ChatStore extends ChangeNotifier {
  ChatStore({ChatService? service}) : _service = service ?? chatService;

  final ChatService _service;

  int _unreadCount = 0;
  bool _chatEnabled = true;
  bool _online = false;

  int get unreadCount => _unreadCount;

  /// Kill-switch chat. Default true (fail-open) — jangan sembunyikan
  /// tombol chat gara-gara belum sempat fetch config / fetch gagal.
  bool get chatEnabled => _chatEnabled;

  /// Status jam operasional toko dari `GET /api/chat/config` (fix B3).
  /// Default false — netral, bukan klaim online palsu sebelum config
  /// pertama berhasil di-fetch.
  bool get online => _online;

  /// Set unread count. `notifyListeners()` HANYA kalau nilai benar-benar
  /// berubah — poll berulang dgn angka sama tak boleh trigger rebuild.
  void setUnread(int value) {
    if (_unreadCount == value) return;
    _unreadCount = value;
    notifyListeners();
  }

  /// Terapkan config kill-switch + jam operasional. `notifyListeners()`
  /// HANYA kalau salah satu field berubah (guard sama seperti [setUnread]).
  void applyConfig({required bool chatEnabled, required bool online}) {
    if (_chatEnabled == chatEnabled && _online == online) return;
    _chatEnabled = chatEnabled;
    _online = online;
    notifyListeners();
  }

  /// Poll unread count sekali. **Fail-open pada error jaringan**: exception
  /// dari `ChatService.fetchUnread` (yang sendiri TIDAK menyerap error)
  /// ditangkap DI SINI supaya polling background tak pernah crash app —
  /// state (unreadCount) tetap seperti sebelumnya.
  Future<void> fetchUnread() async {
    try {
      final value = await _service.fetchUnread();
      setUnread(value);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[chatStore.fetchUnread] gagal (diabaikan): $e');
      }
    }
  }

  /// Poll config kill-switch + jam operasional sekali. **Fail-open**: error
  /// jaringan/parsing ditangkap di sini — `chatEnabled` TETAP nilai
  /// sebelumnya (default true kalau belum pernah sukses fetch), chat TIDAK
  /// dimatikan hanya gara-gara masalah infra sementara.
  Future<void> fetchConfig() async {
    try {
      final config = await _service.fetchConfig();
      applyConfig(chatEnabled: config.chatEnabled, online: config.online);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[chatStore.fetchConfig] gagal (diabaikan): $e');
      }
    }
  }
}

final ChatStore chatStore = ChatStore();

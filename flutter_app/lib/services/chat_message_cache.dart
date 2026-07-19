import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_message.dart';
import 'chat_service.dart' show mapMessages;

/// Cache lokal ringan untuk halaman TERBARU sebuah room chat — supaya buka
/// room bisa render INSTAN dari disk (tanpa spinner) lalu sinkron ke server
/// di belakang. Menghilangkan "layar kosong + loading" tiap kali masuk chat.
///
/// **Kenapa simpan RAW (bukan `ChatMessage.toJson`):** `ChatMessage` tak
/// punya `toJson` dan modelnya kaya (product/order/reply/image + schemaVersion)
/// — menulis serializer manual berisiko hilang-field. Kita simpan JSON MENTAH
/// dari server apa adanya, lalu memuatnya lewat `mapMessages`/`fromJson` yang
/// SAMA dengan jalur jaringan → fidelity terjamin, satu sumber parsing.
///
/// Cache ini SEMATA optimisasi tampilan awal: server tetap sumber kebenaran
/// (fetch latest langsung menimpa/merge setelah render cache). Isi dibatasi
/// [_maxEntries] pesan terakhir supaya storage tak menggelembung.
class ChatMessageCache {
  ChatMessageCache({Future<SharedPreferences> Function()? prefs})
      : _prefs = prefs ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _prefs;

  static const String _keyPrefix = 'chat_cache_v1_';
  static const int _maxEntries = 60;

  String _key(String chatId) => '$_keyPrefix$chatId';

  /// Simpan JSON mentah pesan terbaru room [chatId] (dipangkas ke
  /// [_maxEntries] terakhir). Best-effort — kegagalan disk diserap diam-diam
  /// (cache cuma optimisasi, tak boleh mengganggu alur chat).
  Future<void> saveLatest(String chatId, List<dynamic> rawMessages) async {
    try {
      final trimmed = rawMessages.length > _maxEntries
          ? rawMessages.sublist(rawMessages.length - _maxEntries)
          : rawMessages;
      final prefs = await _prefs();
      await prefs.setString(_key(chatId), jsonEncode(trimmed));
    } catch (_) {
      // best-effort — abaikan.
    }
  }

  /// Muat pesan cache room [chatId] (terurut asc via `mapMessages`). List
  /// kosong kalau belum ada cache / gagal baca / data rusak.
  Future<List<ChatMessage>> loadLatest(String chatId) async {
    try {
      final prefs = await _prefs();
      final raw = prefs.getString(_key(chatId));
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return mapMessages(decoded);
    } catch (_) {
      return const [];
    }
  }

  /// Bersihkan cache room (mis. saat logout/ganti akun). Best-effort.
  Future<void> clear(String chatId) async {
    try {
      final prefs = await _prefs();
      await prefs.remove(_key(chatId));
    } catch (_) {
      // best-effort.
    }
  }
}

/// Singleton default dipakai `ChatRoomScreen`. Test meng-inject instance
/// sendiri dgn `prefs` fake (tanpa plugin platform).
final ChatMessageCache chatMessageCache = ChatMessageCache();

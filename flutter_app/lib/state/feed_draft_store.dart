import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/new_post_user_tag.dart';

/// Key baru — daftar draft (JSON array), maks [FeedDraftStore.maxDrafts].
/// Menggantikan slot tunggal lama [_legacyDraftKey] (migrasi otomatis saat
/// load pertama — lihat [FeedDraftStore.load]).
const _draftsKey = 'natalo-feed-drafts';

/// Key lama (Fase 2B) — format string pipe-separated
/// `'local|post-new|<json>|<ts>'`, hanya menyimpan SATU draft. Dibaca sekali
/// utk migrasi lalu dihapus.
const _legacyDraftKey = 'natalo-feed-upload-pending';

/// Satu draft tersimpan (post video/foto yang belum di-publish). JSON
/// round-trip stabil — field baru harus punya default aman di [fromJson]
/// supaya draft lama (sebelum field ditambah) tetap bisa di-load.
class FeedDraft {
  final String id;
  final String type; // 'video' | 'image'
  final String caption;
  final List<String> productIds;
  final List<NewPostUserTag> taggedUsers;

  /// video: `[finalVideoPath]` (1 entry). image: semua path foto carousel.
  final List<String> mediaPaths;
  final String? thumbnailPath;
  final int? trimStartMs;
  final int? trimmedDurationMs;

  /// Wajib utk rekonstruksi video draft (validasi durasi 1..60s + trim
  /// guard di `_upload`). Draft foto tidak butuh field ini (null).
  final int? originalDurationMs;
  final bool userPickedCover;
  final int savedAtMs;

  /// Field RUNTIME (bukan bagian JSON) — di-set oleh [FeedDraftStore.load]
  /// saat salah satu file di [mediaPaths]/[thumbnailPath] sudah tidak ada
  /// di device. UI menawarkan hapus saja, bukan restore, untuk draft rusak.
  final bool broken;

  const FeedDraft({
    required this.id,
    required this.type,
    required this.caption,
    required this.productIds,
    this.taggedUsers = const [],
    required this.mediaPaths,
    this.thumbnailPath,
    this.trimStartMs,
    this.trimmedDurationMs,
    this.originalDurationMs,
    this.userPickedCover = false,
    required this.savedAtMs,
    this.broken = false,
  });

  FeedDraft copyWith({bool? broken}) {
    return FeedDraft(
      id: id,
      type: type,
      caption: caption,
      productIds: productIds,
      taggedUsers: taggedUsers,
      mediaPaths: mediaPaths,
      thumbnailPath: thumbnailPath,
      trimStartMs: trimStartMs,
      trimmedDurationMs: trimmedDurationMs,
      originalDurationMs: originalDurationMs,
      userPickedCover: userPickedCover,
      savedAtMs: savedAtMs,
      broken: broken ?? this.broken,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'caption': caption,
        'productIds': productIds,
        'taggedUsers': taggedUsers.map((t) => t.toJson()).toList(),
        'mediaPaths': mediaPaths,
        'thumbnailPath': thumbnailPath,
        'trimStartMs': trimStartMs,
        'trimmedDurationMs': trimmedDurationMs,
        'originalDurationMs': originalDurationMs,
        'userPickedCover': userPickedCover,
        'savedAtMs': savedAtMs,
      };

  static FeedDraft fromJson(Map<String, dynamic> json) {
    return FeedDraft(
      id: (json['id'] as String?) ?? '',
      type: (json['type'] as String?) ?? 'image',
      caption: (json['caption'] as String?) ?? '',
      productIds:
          (json['productIds'] as List?)?.cast<String>() ?? const <String>[],
      taggedUsers: ((json['taggedUsers'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(NewPostUserTag.fromJson)
          .toList(),
      mediaPaths:
          (json['mediaPaths'] as List?)?.cast<String>() ?? const <String>[],
      thumbnailPath: json['thumbnailPath'] as String?,
      trimStartMs: json['trimStartMs'] as int?,
      trimmedDurationMs: json['trimmedDurationMs'] as int?,
      originalDurationMs: json['originalDurationMs'] as int?,
      userPickedCover: (json['userPickedCover'] as bool?) ?? false,
      savedAtMs: (json['savedAtMs'] as int?) ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }
}

/// Repository daftar draft feed post — key [_draftsKey] (JSON array), maks
/// [maxDrafts] (terlama tergeser saat draft baru masuk). Migrasi otomatis
/// dari slot lama [_legacyDraftKey] (format Fase 2B) dijalankan sekali di
/// [load] pertama kali dipanggil setelah upgrade.
class FeedDraftStore {
  static const maxDrafts = 5;

  Future<List<FeedDraft>> load() async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateLegacyIfNeeded(prefs);

    final raw = prefs.getString(_draftsKey);
    if (raw == null || raw.trim().isEmpty) return const [];

    List<FeedDraft> drafts;
    try {
      final decoded = jsonDecode(raw) as List;
      drafts = decoded
          .whereType<Map>()
          .map((m) => FeedDraft.fromJson(m.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return const [];
    }

    // Validasi file — media hilang (user hapus dari galeri, temp dir OS
    // di-clean, dst) → tandai broken tapi TETAP dikembalikan supaya UI
    // bisa tawarkan hapus draft tsb.
    final validated = <FeedDraft>[];
    for (final draft in drafts) {
      final broken = await _isBroken(draft);
      validated.add(draft.copyWith(broken: broken));
    }
    // Terbaru dulu — draft yang baru disimpan tampil paling depan di rail.
    validated.sort((a, b) => b.savedAtMs.compareTo(a.savedAtMs));
    return validated;
  }

  Future<bool> _isBroken(FeedDraft draft) async {
    for (final path in draft.mediaPaths) {
      if (!await File(path).exists()) return true;
    }
    final thumb = draft.thumbnailPath;
    if (thumb != null && thumb.isNotEmpty && !await File(thumb).exists()) {
      return true;
    }
    // Draft video migrasi dari slot lama (Fase 2B, sebelum durasi disimpan)
    // tidak punya originalDurationMs/trimmedDurationMs sama sekali — tanpa
    // durasi, validasi publish 1..60s tidak akan pernah lolos. Tandai
    // broken (tawarkan hapus) daripada biarkan jadi kartu dead-end yang
    // ketuknya gagal tanpa penjelasan.
    if (draft.type == 'video' &&
        draft.originalDurationMs == null &&
        draft.trimmedDurationMs == null) {
      return true;
    }
    return false;
  }

  Future<void> save(FeedDraft draft) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await _readRaw(prefs);
    final next = [
      ...current.where((d) => d.id != draft.id),
      draft,
    ]..sort((a, b) => a.savedAtMs.compareTo(b.savedAtMs));
    final trimmed = next.length > maxDrafts
        ? next.sublist(next.length - maxDrafts)
        : next;
    await _writeRaw(prefs, trimmed);
  }

  Future<void> remove(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await _readRaw(prefs);
    final next = current.where((d) => d.id != id).toList();
    await _writeRaw(prefs, next);
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_draftsKey);
  }

  Future<List<FeedDraft>> _readRaw(SharedPreferences prefs) async {
    final raw = prefs.getString(_draftsKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded
          .whereType<Map>()
          .map((m) => FeedDraft.fromJson(m.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _writeRaw(
    SharedPreferences prefs,
    List<FeedDraft> drafts,
  ) async {
    if (drafts.isEmpty) {
      await prefs.remove(_draftsKey);
      return;
    }
    await prefs.setString(
      _draftsKey,
      jsonEncode(drafts.map((d) => d.toJson()).toList()),
    );
  }

  /// Migrasi sekali-jalan dari slot lama Fase 2B
  /// (`'local|post-new|<json>|<ts>'`) → masukkan ke daftar baru → hapus
  /// key lama. No-op kalau key lama sudah tidak ada / sudah pernah
  /// dimigrasikan.
  Future<void> _migrateLegacyIfNeeded(SharedPreferences prefs) async {
    final raw = prefs.getString(_legacyDraftKey);
    if (raw == null || !raw.startsWith('local|post-new|')) return;
    try {
      final parts = raw.split('|');
      if (parts.length < 4) {
        await prefs.remove(_legacyDraftKey);
        return;
      }
      final jsonStr = parts.sublist(2, parts.length - 1).join('|');
      final payload = jsonDecode(jsonStr) as Map<String, dynamic>;
      final savedAtMs = (payload['savedAt'] as int?) ??
          int.tryParse(parts.last) ??
          DateTime.now().millisecondsSinceEpoch;
      final legacyDraft = FeedDraft(
        id: 'draft-$savedAtMs',
        type: (payload['type'] as String?) ?? 'image',
        caption: (payload['caption'] as String?) ?? '',
        productIds:
            (payload['productIds'] as List?)?.cast<String>() ??
                const <String>[],
        taggedUsers: ((payload['taggedUsers'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(NewPostUserTag.fromJson)
            .toList(),
        mediaPaths:
            (payload['media'] as List?)?.cast<String>() ?? const <String>[],
        thumbnailPath: payload['thumbnailPath'] as String?,
        trimStartMs: payload['trimStartMs'] as int?,
        userPickedCover: (payload['userPickedCover'] as bool?) ?? false,
        savedAtMs: savedAtMs,
      );

      final current = await _readRaw(prefs);
      final next = [
        ...current.where((d) => d.id != legacyDraft.id),
        legacyDraft,
      ]..sort((a, b) => a.savedAtMs.compareTo(b.savedAtMs));
      final trimmed = next.length > maxDrafts
          ? next.sublist(next.length - maxDrafts)
          : next;
      await _writeRaw(prefs, trimmed);
    } catch (_) {
      // Corrupt legacy payload — buang saja, jangan blok load daftar baru.
    } finally {
      await prefs.remove(_legacyDraftKey);
    }
  }
}

final feedDraftStore = FeedDraftStore();

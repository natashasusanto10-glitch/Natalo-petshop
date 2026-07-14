import 'package:flutter/foundation.dart';

/// Override status follow per userId hasil aksi user DI SESI INI —
/// menimpa `FeedAuthor.isFollowing` bawaan payload feed (yang cuma
/// snapshot saat fetch).
///
/// Kenapa global (bukan state per-chip): satu author bisa muncul di
/// banyak post sekaligus di feed. Kalau state cuma lokal di chip, follow
/// di post A tidak ter-reflect di post B dari author sama → chip tidak
/// konsisten. Semua chip subscribe notifier ini via ValueListenableBuilder.
///
/// Reset saat feed re-fetch TIDAK diperlukan — payload baru membawa
/// isFollowing terbaru dari server, dan override lama tetap benar (server
/// state sudah menyusul aksi user). Kalau user toggle lagi, override
/// menimpa lagi. Sederhana dan self-healing.
final ValueNotifier<Map<String, bool>> followOverrides =
    ValueNotifier<Map<String, bool>>(const {});

/// Set override follow untuk [userId]. Immutable copy supaya
/// ValueNotifier terpicu (perbandingan identitas map).
void setFollowOverride(String userId, bool following) {
  if (userId.isEmpty) return;
  followOverrides.value = {...followOverrides.value, userId: following};
}

/// Resolve snapshot server dengan aksi follow terbaru pada sesi ini.
bool resolveFollowState(String userId, bool serverValue) {
  if (userId.isEmpty) return serverValue;
  return followOverrides.value[userId] ?? serverValue;
}

/// Follow state bersifat viewer-specific, jadi wajib dibuang saat logout.
void clearFollowOverrides() {
  if (followOverrides.value.isEmpty) return;
  followOverrides.value = const {};
}

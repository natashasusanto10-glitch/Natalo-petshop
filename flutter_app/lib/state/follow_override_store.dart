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

final Map<String, int> _followRevisions = <String, int>{};
final Set<String> _pendingFollowMutations = <String>{};

/// Set override follow untuk [userId]. Immutable copy supaya
/// ValueNotifier terpicu (perbandingan identitas map).
void setFollowOverride(String userId, bool following) {
  if (userId.isEmpty) return;
  if (followOverrides.value[userId] == following) return;
  _followRevisions[userId] = (_followRevisions[userId] ?? 0) + 1;
  followOverrides.value = {...followOverrides.value, userId: following};
}

int followStateRevision(String userId) => _followRevisions[userId] ?? 0;

bool isFollowMutationPending(String userId) =>
    _pendingFollowMutations.contains(userId);

/// Marks an optimistic desired state as pending. The global pending marker
/// prevents a late profile/list response from replacing it mid-request.
void beginFollowMutation(String userId, bool following) {
  if (userId.isEmpty) return;
  _pendingFollowMutations.add(userId);
  // Bump even when the optimistic value was already written by the widget.
  // A read that started before this operation must remain stale after the
  // request confirms the same boolean value.
  _followRevisions[userId] = (_followRevisions[userId] ?? 0) + 1;
  if (followOverrides.value[userId] != following) {
    followOverrides.value = {...followOverrides.value, userId: following};
  }
}

void confirmFollowMutation(String userId, bool following) {
  if (userId.isEmpty) return;
  if (_pendingFollowMutations.remove(userId)) {
    // Invalidate reads that began while this mutation was pending, including
    // confirmations whose canonical boolean matches the optimistic override.
    _followRevisions[userId] = (_followRevisions[userId] ?? 0) + 1;
  }
  setFollowOverride(userId, following);
}

void abandonFollowMutation(String userId) {
  if (userId.isEmpty) return;
  if (_pendingFollowMutations.remove(userId)) {
    // A failed request also closes the pending interval. Any server read that
    // started inside it belongs to the old transition and must stay stale.
    _followRevisions[userId] = (_followRevisions[userId] ?? 0) + 1;
  }
}

/// Applies a server snapshot only if no newer local action happened after the
/// request began. This is the follow equivalent of FeedStore's stale-write
/// protection and lets cross-device changes eventually self-heal.
bool reconcileFollowStateFromServer(
  String userId,
  bool following, {
  required int observedRevision,
}) {
  if (userId.isEmpty ||
      _pendingFollowMutations.contains(userId) ||
      followStateRevision(userId) != observedRevision) {
    return false;
  }
  setFollowOverride(userId, following);
  return true;
}

/// Resolve snapshot server dengan aksi follow terbaru pada sesi ini.
bool resolveFollowState(String userId, bool serverValue) {
  if (userId.isEmpty) return serverValue;
  return followOverrides.value[userId] ?? serverValue;
}

/// Follow state bersifat viewer-specific, jadi wajib dibuang saat logout.
void clearFollowOverrides() {
  _followRevisions.clear();
  _pendingFollowMutations.clear();
  if (followOverrides.value.isNotEmpty) followOverrides.value = const {};
}

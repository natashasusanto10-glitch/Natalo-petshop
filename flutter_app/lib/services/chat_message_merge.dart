/// Rekonsiliasi/dedupe pesan chat customer (Plan 4, Task 5) — fungsi murni
/// terpisah dari `ChatRoomScreen` supaya bisa di-unit-test TANPA widget tree
/// (logika paling berisiko di Task 5: salah dedupe = pesan dobel ATAU
/// bubble optimistic macet di status `sending` selamanya).
library;

import '../models/chat_message.dart';

/// Gabungkan pesan SERVER ([incoming], hasil `ChatService.fetchMessages`)
/// ke [existing] — list yang mungkin berisi campuran pesan optimistic
/// (baru dikirim client sesi ini, `ChatMessage.isOptimistic == true`) dan
/// pesan server (`isOptimistic == false`). Provenance dibedakan lewat flag
/// [ChatMessage.isOptimistic], BUKAN `status` — proxy MENGIRIM
/// `status: "sent"` untuk pesan customer (`lib/chat/rooms.ts:204` →
/// `lib/chat/core.ts:69`), jadi `status` non-null tidak berarti "lokal".
///
/// Setelah sebuah pesan server dengan `clientMsgId` yang sama masuk, ia
/// MENGGANTI bubble optimistic di slot itu (aturan 1) — hasil di slot itu
/// jadi pesan server (`isOptimistic == false`), sehingga
/// `ChatRoomScreen._afterCursor` bisa memajukan cursor melewatinya di poll
/// berikutnya (tidak lagi terjebak re-drain tail tiap tick).
///
/// Aturan (diterapkan PER pesan `s` di [incoming], urut):
///  1. Ada pesan di [existing]/hasil-sejauh-ini dengan `clientMsgId` SAMA
///     dengan `s.clientMsgId` -> GANTI pesan itu dengan `s` (server adalah
///     source of truth; ini "mempromosikan" bubble optimistic jadi
///     confirmed — timestamp & status ikut ganti ke versi server).
///  2. Kalau tidak, tapi sudah ada pesan dengan `id` server SAMA dengan
///     `s.id` -> skip (sudah punya; menjaga idempoten kalau drain
///     forward/poll/pull-to-refresh mengembalikan baris yang sama lagi).
///  3. Selain itu -> append `s` sebagai pesan baru.
///
/// Hasil selalu diurutkan ASC by `createdAt` (dengan tiebreaker
/// DETERMINISTIK, lihat [_compareForOrder]) sebelum dikembalikan. Pure,
/// tanpa I/O, tanpa mutasi [existing]/[incoming] (return list baru).
List<ChatMessage> mergeChatMessages(
  List<ChatMessage> existing,
  List<ChatMessage> incoming,
) {
  final result = List<ChatMessage>.from(existing);
  for (final s in incoming) {
    final clientMsgId = s.clientMsgId;
    final clientIdx = clientMsgId == null
        ? -1
        : result.indexWhere((m) => m.clientMsgId == clientMsgId);
    if (clientIdx != -1) {
      result[clientIdx] = s;
      continue;
    }
    final idIdx = result.indexWhere((m) => m.id == s.id);
    if (idIdx != -1) continue;
    result.add(s);
  }
  result.sort(_compareForOrder);
  return result;
}

/// Urutan deterministik: `createdAt` ASC, lalu tiebreaker STABIL saat dua
/// pesan berbagi millisecond yang sama. Tanpa tiebreaker, `List.sort`
/// (TIDAK stabil di Dart) bisa menukar urutan dua pesan se-millisecond
/// antar poll → jitter visual (bubble lompat-lompat). Tiebreaker: `id`
/// server kalau non-kosong, else `clientMsgId` (fallback string kosong
/// supaya perbandingan tak pernah throw pada null — `ChatMessage.id`
/// sendiri sudah non-null tapi bisa string kosong utk bubble optimistic
/// yang id-nya = clientMsgId, sementara `clientMsgId` nullable).
int _compareForOrder(ChatMessage a, ChatMessage b) {
  final byTime = a.createdAt.compareTo(b.createdAt);
  if (byTime != 0) return byTime;
  final aKey = a.id.isNotEmpty ? a.id : (a.clientMsgId ?? '');
  final bKey = b.id.isNotEmpty ? b.id : (b.clientMsgId ?? '');
  return aKey.compareTo(bKey);
}

/// `createdAt` TERBESAR di antara [messages] yang BUKAN optimistic
/// (`isOptimistic == false`) — helper murni bersama dipakai DUA tempat di
/// `ChatRoomScreen`: cursor polling (`_afterCursor`, tak berubah) DAN guard
/// clock-skew bubble optimistic baru ([nextOptimisticCreatedAt], F3).
/// Bubble optimistic SENGAJA diabaikan — `createdAt` mereka `DateTime.now()`
/// LOKAL, tidak sinkron dgn jam server, jadi tidak aman dipakai sbg
/// referensi "waktu server terakhir yang diketahui". Null kalau belum ada
/// satupun pesan server di [messages].
int? maxServerCreatedAt(List<ChatMessage> messages) {
  int? result;
  for (final m in messages) {
    if (m.isOptimistic) continue;
    if (result == null || m.createdAt > result) result = m.createdAt;
  }
  return result;
}

/// `createdAt` deterministik untuk BUBBLE OPTIMISTIC BARU (F3, guard clock
/// skew) — jam device lokal ([now], default
/// `DateTime.now().millisecondsSinceEpoch`), TAPI di-clamp supaya tak
/// pernah <= `createdAt` pesan SERVER terbaru yang sudah diketahui klien
/// (dari [maxServerCreatedAt]). Tanpa clamp ini, device yang jamnya SKEW di
/// BELAKANG jam server bisa membuat bubble optimistic baru sort SEBELUM
/// pesan server yang sudah ada di list (mis. balasan staff yang baru saja
/// masuk lewat poll) sampai rekonsiliasi menggantinya dgn timestamp server
/// — tampak seperti dua bubble terbaru "bertukar posisi" sesaat lalu
/// "melompat" balik. `+1` (bukan `>=`) memastikan urutan STRICT setelah
/// pesan server terakhir, bukan cuma sama persis (yang bisa jatuh ke
/// tiebreaker id/clientMsgId di [_compareForOrder] dan masih berisiko
/// salah urutan untuk kasus ini).
int nextOptimisticCreatedAt(List<ChatMessage> messages, {int? now}) {
  final n = now ?? DateTime.now().millisecondsSinceEpoch;
  final floor = maxServerCreatedAt(messages);
  if (floor == null) return n;
  final minAllowed = floor + 1;
  return n > minAllowed ? n : minAllowed;
}

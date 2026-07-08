import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/chat_message.dart';
import 'package:natalo_petshop_flutter/services/chat_message_merge.dart';

ChatMessage _optimistic({
  required String clientMsgId,
  String? text,
  int createdAt = 0,
  ChatSendStatus status = ChatSendStatus.sending,
  ChatMsgType type = ChatMsgType.text,
}) {
  return ChatMessage(
    id: clientMsgId,
    sender: ChatSender.customer,
    type: type,
    text: text,
    createdAt: createdAt,
    clientMsgId: clientMsgId,
    status: status,
    // Bubble lokal — provenance-nya `isOptimistic: true` (BUKAN dari
    // `status`, yang cuma penanda tier centang).
    isOptimistic: true,
  );
}

ChatMessage _server({
  required String id,
  String? clientMsgId,
  String? text,
  int createdAt = 0,
  ChatSender sender = ChatSender.customer,
  ChatMsgType type = ChatMsgType.text,
}) {
  return ChatMessage(
    id: id,
    sender: sender,
    type: type,
    text: text,
    createdAt: createdAt,
    clientMsgId: clientMsgId,
    // Pesan customer dari proxy MEMBAWA `status: "sent"`
    // (`lib/chat/rooms.ts:204` → `lib/chat/core.ts:69`) — jadi model pesan
    // server realistis dgn status non-null. Provenance ditandai
    // `isOptimistic: false` (default), BUKAN oleh status.
    status: sender == ChatSender.customer ? ChatSendStatus.sent : null,
  );
}

void main() {
  group('mergeChatMessages', () {
    test('replace pesan optimistic dgn versi server via clientMsgId sama', () {
      final existing = [
        _optimistic(clientMsgId: 'c1', text: 'halo', createdAt: 1000),
      ];
      final incoming = [
        _server(id: 'srv-1', clientMsgId: 'c1', text: 'halo', createdAt: 500),
      ];

      final result = mergeChatMessages(existing, incoming);

      expect(result.length, 1);
      expect(result.single.id, 'srv-1');
      // Setelah rekonsiliasi, slot jadi pesan SERVER — `isOptimistic` false
      // (inilah yang bikin `_afterCursor` bisa maju melewatinya). `status`
      // TIDAK diandalkan lagi utk provenance (proxy kirim status:sent).
      expect(result.single.isOptimistic, isFalse);
      expect(result.single.createdAt, 500);
    });

    test('skip duplikat by id server (bukan clientMsgId)', () {
      final existing = [
        _server(id: 'srv-1', text: 'dari staff', createdAt: 100),
      ];
      final incoming = [
        _server(id: 'srv-1', text: 'dari staff', createdAt: 100),
      ];

      final result = mergeChatMessages(existing, incoming);

      expect(result.length, 1);
    });

    test('append pesan baru yang belum pernah ada (id & clientMsgId beda)', () {
      final existing = [
        _server(id: 'srv-1', text: 'a', createdAt: 100),
      ];
      final incoming = [
        _server(id: 'srv-2', text: 'b', createdAt: 200),
      ];

      final result = mergeChatMessages(existing, incoming);

      expect(result.map((m) => m.id).toList(), ['srv-1', 'srv-2']);
    });

    test('hasil selalu terurut ASC by createdAt walau incoming tak urut', () {
      final existing = [
        _server(id: 'srv-2', text: 'kedua', createdAt: 200),
      ];
      final incoming = [
        _server(id: 'srv-3', text: 'ketiga', createdAt: 300),
        _server(id: 'srv-1', text: 'pertama', createdAt: 100),
      ];

      final result = mergeChatMessages(existing, incoming);

      expect(result.map((m) => m.createdAt).toList(), [100, 200, 300]);
      expect(result.map((m) => m.id).toList(), ['srv-1', 'srv-2', 'srv-3']);
    });

    test(
        'pesan staff (tanpa clientMsgId) tidak pernah match optimistic '
        'customer manapun — selalu lewat jalur id', () {
      final existing = [
        _optimistic(clientMsgId: 'c1', text: 'tanya produk', createdAt: 100),
      ];
      final incoming = [
        _server(
          id: 'srv-staff-1',
          text: 'balasan staff',
          createdAt: 150,
          sender: ChatSender.staff,
        ),
      ];

      final result = mergeChatMessages(existing, incoming);

      expect(result.length, 2);
      // Bubble optimistic customer TETAP ada (belum direkonsiliasi -
      // clientMsgId beda), pesan staff baru ditambahkan terpisah.
      expect(result.any((m) => m.clientMsgId == 'c1'), true);
      expect(result.any((m) => m.id == 'srv-staff-1'), true);
    });

    test('foto optimistic direkonsiliasi sama seperti teks (type image)', () {
      final existing = [
        _optimistic(
          clientMsgId: 'c-img',
          createdAt: 900,
          type: ChatMsgType.image,
        ),
      ];
      final incoming = [
        _server(
          id: 'srv-img-1',
          clientMsgId: 'c-img',
          createdAt: 300,
          type: ChatMsgType.image,
        ),
      ];

      final result = mergeChatMessages(existing, incoming);

      expect(result.length, 1);
      expect(result.single.id, 'srv-img-1');
      expect(result.single.type, ChatMsgType.image);
      // Foto server hasil rekonsiliasi juga `isOptimistic: false`.
      expect(result.single.isOptimistic, isFalse);
    });

    test('existing/incoming kosong -> tidak throw, hasil sesuai', () {
      expect(mergeChatMessages(const [], const []), isEmpty);

      final onlyExisting = [_server(id: 's1', createdAt: 1)];
      expect(mergeChatMessages(onlyExisting, const []).length, 1);

      final onlyIncoming = [_server(id: 's1', createdAt: 1)];
      expect(mergeChatMessages(const [], onlyIncoming).length, 1);
    });

    test(
        'retry: incoming server row kedua dgn clientMsgId sama -> replace '
        'lagi, bukan dobel (resend idempoten proxy)', () {
      final existing = [
        _server(id: 'srv-1', clientMsgId: 'c1', text: 'halo', createdAt: 100),
      ];
      // Simulasi retry yang di-dedupe proxy -> baris server yang sama
      // datang lagi lewat poll berikutnya dgn clientMsgId sama.
      final incoming = [
        _server(id: 'srv-1', clientMsgId: 'c1', text: 'halo', createdAt: 100),
      ];

      final result = mergeChatMessages(existing, incoming);

      expect(result.length, 1);
    });

    test('tidak memutasi list existing/incoming yang dioper (pure)', () {
      final existing = [_server(id: 's1', createdAt: 1)];
      final incoming = [_server(id: 's2', createdAt: 2)];
      final existingCopy = List<ChatMessage>.from(existing);
      final incomingCopy = List<ChatMessage>.from(incoming);

      mergeChatMessages(existing, incoming);

      expect(existing.map((m) => m.id), existingCopy.map((m) => m.id));
      expect(incoming.map((m) => m.id), incomingCopy.map((m) => m.id));
    });

    test(
        'dua pesan createdAt SAMA -> urutan deterministik (tiebreaker id) '
        'apapun urutan input, tak ada jitter antar poll', () {
      // createdAt identik (satu millisecond) — tanpa tiebreaker, List.sort
      // yang tidak stabil bisa menukar urutan keduanya antar pemanggilan.
      final a = _server(id: 'srv-a', text: 'A', createdAt: 500);
      final b = _server(id: 'srv-b', text: 'B', createdAt: 500);

      // Jalankan dgn incoming di KEDUA urutan — hasil harus identik.
      final r1 = mergeChatMessages(const [], [a, b]);
      final r2 = mergeChatMessages(const [], [b, a]);

      expect(r1.map((m) => m.id).toList(), ['srv-a', 'srv-b']);
      expect(r2.map((m) => m.id).toList(), ['srv-a', 'srv-b']);
      // Idempoten & stabil: merge hasil sebelumnya dgn dirinya lagi tak
      // mengubah urutan (skenario poll berulang yang mengembalikan baris
      // yang sama).
      final r3 = mergeChatMessages(r1, [b, a]);
      expect(r3.map((m) => m.id).toList(), ['srv-a', 'srv-b']);
    });
  });

  group('maxServerCreatedAt', () {
    test('null kalau tak ada pesan server sama sekali', () {
      expect(maxServerCreatedAt(const []), isNull);
      final onlyOptimistic = [
        _optimistic(clientMsgId: 'c1', createdAt: 500),
      ];
      expect(maxServerCreatedAt(onlyOptimistic), isNull);
    });

    test('abaikan bubble optimistic, ambil createdAt server terbesar', () {
      final messages = [
        _server(id: 's1', createdAt: 100),
        _optimistic(clientMsgId: 'c1', createdAt: 9999),
        _server(id: 's2', createdAt: 300),
      ];
      expect(maxServerCreatedAt(messages), 300);
    });
  });

  group('nextOptimisticCreatedAt (F3 clock-skew guard)', () {
    test('tak ada pesan server -> pakai now apa adanya', () {
      expect(
        nextOptimisticCreatedAt(const [], now: 1000),
        1000,
      );
    });

    test('now SUDAH lebih besar dari createdAt server terbesar -> pakai now',
        () {
      final messages = [_server(id: 's1', createdAt: 100)];
      expect(nextOptimisticCreatedAt(messages, now: 5000), 5000);
    });

    test(
        'jam device SKEW di belakang server -> clamp ke maxServerCreatedAt+1 '
        '(bukan now mentah)', () {
      final messages = [_server(id: 's1', createdAt: 10000)];
      // now (device, skew di belakang) < createdAt server terbaru.
      expect(nextOptimisticCreatedAt(messages, now: 100), 10001);
    });

    test('now PERSIS sama dgn createdAt server terbesar -> tetap clamp naik',
        () {
      final messages = [_server(id: 's1', createdAt: 5000)];
      expect(nextOptimisticCreatedAt(messages, now: 5000), 5001);
    });
  });
}

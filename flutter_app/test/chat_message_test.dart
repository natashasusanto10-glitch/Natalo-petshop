import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/chat_message.dart';

void main() {
  test('parse pesan teks staff', () {
    final m = ChatMessage.fromJson({
      'id': 'm1',
      'senderRole': 'staff',
      'type': 'text',
      'text': 'halo',
      'createdAt': 1700000000000,
    });
    expect(m.sender, ChatSender.staff);
    expect(m.type, ChatMsgType.text);
    expect(m.text, 'halo');
  });

  // Provenance: pesan dari server (fromJson) TIDAK PERNAH optimistic —
  // `isOptimistic` selalu false, apapun `status` yang dibawa proxy. Ini
  // yang dipakai `_afterCursor` untuk memilih cursor polling (BUKAN
  // `status == null`, karena proxy MENGIRIM status:"sent" utk pesan
  // customer — lihat lib/chat/rooms.ts:204 → core.ts:69).
  test('fromJson selalu isOptimistic=false (bahkan dgn status:sent proxy)', () {
    final m = ChatMessage.fromJson({
      'id': 'm-srv',
      'senderRole': 'customer',
      'type': 'text',
      'text': 'pesanku',
      'status': 'sent',
      'clientMsgId': 'c-abc',
      'createdAt': 1700000000001,
    });
    expect(m.isOptimistic, isFalse);
    // `status` TETAP di-parse (buat tier centang UI) — cuma tidak dipakai
    // untuk menyimpulkan provenance.
    expect(m.status, ChatSendStatus.sent);
  });

  test('parse kartu produk', () {
    final m = ChatMessage.fromJson({
      'id': 'm2',
      'senderRole': 'staff',
      'type': 'product',
      'product': {
        'productId': 'p1',
        'name': 'RC Persian',
        'price': 285000,
        'stock': 8
      },
      'createdAt': 2,
    });
    expect(m.type, ChatMsgType.product);
    expect(m.product?.name, 'RC Persian');
    expect(m.product?.stock, 8);
  });

  test('tipe tak dikenal -> system (aman)', () {
    final m =
        ChatMessage.fromJson({'id': 'm3', 'type': 'weird', 'createdAt': 3});
    expect(m.type, ChatMsgType.system);
  });

  test('image message baca url', () {
    final m = ChatMessage.fromJson({
      'id': 'm4',
      'senderRole': 'customer',
      'type': 'image',
      'image': {'url': 'https://x/y.jpg'},
      'createdAt': 4,
    });
    expect(m.imageUrl, 'https://x/y.jpg');
    expect(m.sender, ChatSender.customer);
  });

  // Regression: wire pakai snake_case (product_context/order_context — cek
  // lib/chat/core.ts), enum Dart camelCase. Mapping ini logika paling
  // berisiko di task ini.
  test('tipe context snake_case -> enum camelCase', () {
    final pc = ChatMessage.fromJson({
      'id': 'm5',
      'senderRole': 'staff',
      'type': 'product_context',
      'createdAt': 5,
    });
    expect(pc.type, ChatMsgType.productContext);

    final oc = ChatMessage.fromJson({
      'id': 'm6',
      'senderRole': 'staff',
      'type': 'order_context',
      'createdAt': 6,
    });
    expect(oc.type, ChatMsgType.orderContext);
  });

  // Defensif (FIX 1): image.url ada tapi bukan String (payload rusak) ->
  // null, BUKAN throw.
  test('image url bukan string -> null (tanpa throw)', () {
    final m = ChatMessage.fromJson({
      'id': 'm7',
      'senderRole': 'staff',
      'type': 'image',
      'image': {'url': 123},
      'createdAt': 7,
    });
    expect(m.imageUrl, isNull);
  });
}

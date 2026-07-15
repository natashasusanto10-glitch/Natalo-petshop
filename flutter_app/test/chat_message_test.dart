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

  test('parse order_context v1 dan teruskan schemaVersion root', () {
    final m = ChatMessage.fromJson({
      'id': 'm-order-v1',
      'senderRole': 'system',
      'type': 'order_context',
      'schemaVersion': 3,
      'order': {
        'orderNumber': 'ORD-20260715-ABC',
        'status': 'PENDING',
        'paymentStatus': 'UNPAID',
        'paymentProofStatus': 'PENDING_REVIEW',
        'total': 2983946,
        'itemCount': 4,
        'hasPaymentProof': true,
        'proofVersion': 2,
        'createdAt': '2026-07-15T02:00:00.000Z',
      },
      'createdAt': 8,
    });

    expect(m.order?.orderNumber, 'ORD-20260715-ABC');
    expect(m.order?.schemaVersion, 3);
    expect(m.order?.itemCount, 4);
    expect(m.order?.paymentStatus, 'UNPAID');
    expect(m.order?.paymentProofStatus, 'PENDING_REVIEW');
    expect(m.order?.hasPaymentProof, isTrue);
    expect(m.order?.proofVersion, 2);
    expect(m.order?.createdAt, DateTime.utc(2026, 7, 15, 2));
    expect(
      chatOrderStatusLabel(
        m.order?.status,
        paymentProofStatus: m.order?.paymentProofStatus,
      ),
      'Menunggu verifikasi',
    );
  });

  test('parse order legacy snake_case dari context wrapper', () {
    final m = ChatMessage.fromJson({
      'id': 'm-order-legacy',
      'type': 'text',
      'context': {
        'type': 'order',
        'order_number': 'ORD-LEGACY',
        'payment_proof_status': 'VERIFIED',
        'item_count': '2',
        'grandTotal': '125000',
      },
      'createdAt': 9,
    });

    expect(m.order?.orderNumber, 'ORD-LEGACY');
    expect(m.order?.itemCount, 2);
    expect(m.order?.total, 125000);
    expect(m.order?.schemaVersion, 1);
  });

  test('schemaVersion diwariskan dari context wrapper bertingkat', () {
    final m = ChatMessage.fromJson({
      'id': 'm-order-wrapper',
      'type': 'order_context',
      'context': {
        'type': 'order',
        'schemaVersion': 4,
        'order': {'orderNumber': 'ORD-WRAPPED'},
      },
      'createdAt': 10,
    });

    expect(m.order?.orderNumber, 'ORD-WRAPPED');
    expect(m.order?.schemaVersion, 4);
  });
}

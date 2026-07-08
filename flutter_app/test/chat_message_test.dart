import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/chat_message.dart';

void main() {
  test('parse pesan teks staff', () {
    final m = ChatMessage.fromJson({
      'id': 'm1', 'senderRole': 'staff', 'type': 'text',
      'text': 'halo', 'createdAt': 1700000000000,
    });
    expect(m.sender, ChatSender.staff);
    expect(m.type, ChatMsgType.text);
    expect(m.text, 'halo');
  });

  test('parse kartu produk', () {
    final m = ChatMessage.fromJson({
      'id': 'm2', 'senderRole': 'staff', 'type': 'product',
      'product': {'productId': 'p1', 'name': 'RC Persian', 'price': 285000, 'stock': 8},
      'createdAt': 2,
    });
    expect(m.type, ChatMsgType.product);
    expect(m.product?.name, 'RC Persian');
    expect(m.product?.stock, 8);
  });

  test('tipe tak dikenal -> system (aman)', () {
    final m = ChatMessage.fromJson({'id': 'm3', 'type': 'weird', 'createdAt': 3});
    expect(m.type, ChatMsgType.system);
  });

  test('image message baca url', () {
    final m = ChatMessage.fromJson({
      'id': 'm4', 'senderRole': 'customer', 'type': 'image',
      'image': {'url': 'https://x/y.jpg'}, 'createdAt': 4,
    });
    expect(m.imageUrl, 'https://x/y.jpg');
    expect(m.sender, ChatSender.customer);
  });
}

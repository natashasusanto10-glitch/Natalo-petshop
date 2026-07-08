import 'package:flutter/material.dart';

/// Layar chat customer <-> staff (satu room per customer, 1:1 dgn NLCATTER).
///
/// STUB (Task 3) — hanya cukup untuk compile + routing (`/chat`). UI chat
/// penuh (bubble list, composer, product-context card, dst) dibangun di
/// Task 4 — hanya body `_ChatRoomScreenState.build` yang akan diganti,
/// constructor publik ini TETAP (kontrak sudah difix di brief Task 3).
class ChatRoomScreen extends StatefulWidget {
  const ChatRoomScreen({super.key, this.chatId, this.productContext});

  /// null = resolve room milik user yang sedang login di server (backend
  /// cari/buatkan room berdasarkan auth token, bukan dari client).
  final String? chatId;

  /// Konteks produk saat entry dari tombol chat di halaman detail produk,
  /// mis. `{'type': 'product', 'productId': ..., 'slug': ...}`. Dikirim
  /// sebagai `context` pesan pertama (Task 5).
  final Map<String, dynamic>? productContext;

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  // TODO(Task 4): full chat UI (bubble list, composer, product-context
  // card, polling/refresh, dst) — stub ini hanya supaya branch compile
  // dan rute `/chat` bisa di-test end-to-end lebih awal (Task 3).
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Natalo Petshop')),
      body: const Center(child: Text('Chat')),
    );
  }
}

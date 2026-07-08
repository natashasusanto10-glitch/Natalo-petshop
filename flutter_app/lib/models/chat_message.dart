/// Model pesan chat customer <-> staff (Plan 4 — UI chat customer Natalo).
///
/// Data datang dari REST proxy Next.js (Plan 2, `lib/chat/core.ts` di repo
/// Natalo) — app ini TIDAK punya Firestore, JANGAN import `cloud_firestore`.
/// Field waktu (`createdAt`) adalah int epoch millis (`Date.now()`), bukan
/// Firestore Timestamp — parsing di sini toleran terhadap `num` dan
/// mengabaikan tipe lain (fallback 0) alih-alih throw.
///
/// Proxy customer-projection (`projectMessageForCustomer` di core.ts)
/// SELALU menormalisasi `senderRole` mentah (termasuk 'system' dari staff
/// internal note dsb.) menjadi hanya 'customer'|'staff' sebelum sampai ke
/// client — parser `sender` di sini tetap defensif: nilai selain 'staff'
/// dianggap 'customer'.
library;

/// Peran pengirim pesan.
enum ChatSender { customer, staff }

/// Tipe pesan. Wire value dari proxy pakai snake_case untuk 2 tipe context
/// (`product_context`, `order_context`) — enum Dart pakai camelCase sesuai
/// konvensi Dart. Tipe tak dikenal (atau field `type` hilang) di-map ke
/// `system` — aman dirender sebagai catatan sistem daripada crash atau
/// salah asumsi sebagai teks biasa.
enum ChatMsgType { text, image, product, productContext, orderContext, system }

/// Status kirim pesan (dipakai UI untuk tier centang). `queued`/`sending`/
/// `failed` hanya relevan untuk pesan optimistic yang baru dikirim user di
/// sesi ini. `sent` di sisi lain JUGA datang dari proxy: pesan customer di
/// Firestore di-stamp `status: "sent"` (`lib/chat/rooms.ts:204`) dan
/// diteruskan ke client (`lib/chat/core.ts:69`) — jadi `status` BUKAN
/// penanda provenance (pakai [ChatMessage.isOptimistic] untuk itu).
enum ChatSendStatus { queued, sending, sent, failed }

ChatSender _parseSender(Object? raw) {
  return raw == 'staff' ? ChatSender.staff : ChatSender.customer;
}

ChatMsgType _parseType(Object? raw) {
  switch (raw) {
    case 'text':
      return ChatMsgType.text;
    case 'image':
      return ChatMsgType.image;
    case 'product':
      return ChatMsgType.product;
    case 'product_context':
      return ChatMsgType.productContext;
    case 'order_context':
      return ChatMsgType.orderContext;
    case 'system':
      return ChatMsgType.system;
    default:
      // Tipe tak dikenal (termasuk null/missing) -> system, bukan crash.
      return ChatMsgType.system;
  }
}

ChatSendStatus? _parseSendStatus(Object? raw) {
  switch (raw) {
    case 'queued':
      return ChatSendStatus.queued;
    case 'sending':
      return ChatSendStatus.sending;
    case 'sent':
      return ChatSendStatus.sent;
    case 'failed':
      return ChatSendStatus.failed;
    default:
      return null;
  }
}

/// Kartu produk yang dibagikan staff (pesan `type: product`) atau
/// disisipkan dari halaman Detail Produk (`type: product_context`).
/// Field mengikuti allowlist proxy (`CustomerMessage['product']` di
/// `lib/chat/core.ts`) — SENGAJA tak ada field cost/margin/supplier.
/// `discountPrice` opsional untuk kartu produk yang lebih informatif
/// (Task 4) — tolerant null kalau proxy belum mengirimnya.
class ChatProductRef {
  final String productId;
  final String? slug;
  final String name;
  final String? imageUrl;
  final int? price;
  final int? discountPrice;
  final int stock;

  const ChatProductRef({
    required this.productId,
    this.slug,
    required this.name,
    this.imageUrl,
    this.price,
    this.discountPrice,
    this.stock = 0,
  });

  factory ChatProductRef.fromJson(Map<String, dynamic> json) {
    return ChatProductRef(
      productId: _string(json['productId']),
      slug: _stringOrNull(json['slug']),
      name: _string(json['name']),
      imageUrl: _stringOrNull(json['imageUrl']),
      price: _asIntOrNull(json['price']),
      discountPrice: _asIntOrNull(json['discountPrice']),
      stock: _asInt(json['stock']),
    );
  }
}

/// Ringkasan pesanan yang disisipkan staff (pesan `type: order_context`).
/// Field mengikuti allowlist proxy (`CustomerMessage['order']`).
class ChatOrderRef {
  final String orderNumber;
  final String? status;
  final int? total;

  const ChatOrderRef({required this.orderNumber, this.status, this.total});

  factory ChatOrderRef.fromJson(Map<String, dynamic> json) {
    return ChatOrderRef(
      orderNumber: _string(json['orderNumber']),
      status: _stringOrNull(json['status']),
      total: _asIntOrNull(json['total']),
    );
  }
}

class ChatMessage {
  final String id;
  final ChatSender sender;
  final ChatMsgType type;
  final String? text;
  final ChatProductRef? product;

  /// Sub-objek gambar mentah `{url: string}` dari proxy. Dipakai lewat
  /// getter [imageUrl] — tidak butuh model khusus karena cuma 1 field.
  final Map<String, dynamic>? image;
  final ChatOrderRef? order;

  /// Epoch millis dari proxy. Fallback 0 kalau hilang/tak valid (BUKAN
  /// null) supaya sort by createdAt di caller tak perlu null-check.
  final int createdAt;

  /// Id optimistic yang dibuat client saat kirim (dedupe di proxy) —
  /// hanya ada pada pesan yang baru saja dikirim dari sesi ini.
  final String? clientMsgId;

  /// Status kirim (lihat [ChatSendStatus]) — dipakai UI untuk tier centang
  /// (jam `sending` → centang `sent` → error `failed`).
  ///
  /// **JANGAN dipakai untuk menyimpulkan provenance (server vs lokal).** Proxy
  /// SESUNGGUHNYA MENGIRIM `status: "sent"` untuk setiap pesan customer
  /// (`writeCustomerMessage` men-stamp `status: "sent"` di `lib/chat/rooms.ts:204`,
  /// dan proyeksi customer meneruskannya ke client di `lib/chat/core.ts:69`),
  /// jadi pesan customer hasil `fetchMessages` PUN parse ke
  /// `ChatSendStatus.sent` (non-null). Untuk membedakan bubble optimistic
  /// lokal dari pesan server, pakai [isOptimistic], BUKAN `status == null`.
  final ChatSendStatus? status;

  /// True HANYA untuk bubble optimistic yang dibuat lokal di sesi ini (belum
  /// dikonfirmasi/direkonsiliasi dgn baris server). Pesan yang datang dari
  /// server ([ChatMessage.fromJson]) SELALU `false` — server tidak pernah
  /// mengirim konsep "optimistic". Dipakai `ChatRoomScreen._afterCursor`
  /// untuk memilih cursor polling HANYA dari pesan server (timestamp lokal
  /// bubble optimistic tak sinkron dgn jam server) — menggantikan asumsi
  /// LAMA yang salah bahwa `status == null` berarti "dari server".
  final bool isOptimistic;

  /// True kalau pesan ini auto-generated (greeting/away message dsb.)
  final bool auto;

  const ChatMessage({
    required this.id,
    this.sender = ChatSender.customer,
    this.type = ChatMsgType.system,
    this.text,
    this.product,
    this.image,
    this.order,
    this.createdAt = 0,
    this.clientMsgId,
    this.status,
    this.isOptimistic = false,
    this.auto = false,
  });

  /// URL gambar dari sub-objek `image.url`. Null kalau bukan pesan gambar
  /// atau `image`/`image.url` hilang. Baca toleran: `url` yang ada tapi
  /// bukan String (mis. number/objek dari payload rusak) -> null, JANGAN
  /// throw (konsisten dgn filosofi parse toleran file ini).
  String? get imageUrl {
    final u = image?['url'];
    return u is String ? u : null;
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final productRaw = json['product'];
    final imageRaw = json['image'];
    final orderRaw = json['order'];
    return ChatMessage(
      id: _string(json['id']),
      sender: _parseSender(json['senderRole']),
      type: _parseType(json['type']),
      text: _stringOrNull(json['text']),
      product: productRaw is Map
          ? ChatProductRef.fromJson(Map<String, dynamic>.from(productRaw))
          : null,
      image: imageRaw is Map ? Map<String, dynamic>.from(imageRaw) : null,
      order: orderRaw is Map
          ? ChatOrderRef.fromJson(Map<String, dynamic>.from(orderRaw))
          : null,
      createdAt: _asInt(json['createdAt']),
      clientMsgId: _stringOrNull(json['clientMsgId']),
      status: _parseSendStatus(json['status']),
      auto: json['auto'] == true,
    );
  }
}

/// Holder state layar percakapan — dipakai `ChatStore` (Task 2) & layar
/// (Task 5+). `status` = status room (mis. `open`/`resolved`, apa adanya
/// dari proxy — belum ada tipe tertutup karena UI belum butuh cabang
/// per-status di task ini). `online` = status jam operasional toko dari
/// `GET /api/chat/config`.
class ChatRoomState {
  final String status;
  final List<ChatMessage> messages;
  final bool online;

  const ChatRoomState({
    this.status = 'open',
    this.messages = const [],
    this.online = false,
  });
}

// ---- Helpers parsing toleran (pola sama dengan lib/models/product.dart) ----

String _string(Object? value, {String fallback = ''}) {
  if (value == null) return fallback;
  final text = value.toString();
  return text.isEmpty ? fallback : text;
}

String? _stringOrNull(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

int _asInt(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

int? _asIntOrNull(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

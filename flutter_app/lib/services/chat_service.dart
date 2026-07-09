/// Wrapper endpoint chat customer (Plan 4) untuk REST proxy Plan 2 (Natalo
/// `app/api/chat/*` — repo ini TIDAK punya Firestore, semua network lewat
/// proxy Next.js). Isi: `newClientMsgId()` (id optimistic dedupe-safe),
/// `mapMessages()` (parse + sort murni), dan `ChatService` (wrapper
/// endpoint) yang di-DI lewat [ApiClientLike].
///
/// **Kenapa `ApiClientLike` bukan langsung `ApiClient`:** `apiClient`
/// (`api_client.dart`) constructor-nya PRIVATE (`ApiClient._()`, singleton
/// global) — tak bisa di-subclass/mock langsung untuk test. Interface tipis
/// ini expose 3 method yang dipakai chat (`getJson`/`postJson`/
/// `postMultipartFile`) dengan signature identik `ApiClient` asli, supaya
/// test bisa inject fake tanpa jaringan sama sekali.
library;

import 'dart:math';

import '../models/chat_message.dart';
import 'api_client.dart';

abstract class ApiClientLike {
  Future<dynamic> getJson(
    String path, {
    Map<String, dynamic>? query,
    Duration timeout = const Duration(seconds: 8),
  });

  Future<dynamic> postJson(
    String path, {
    Object? body,
    Duration timeout = const Duration(seconds: 25),
  });

  Future<dynamic> postMultipartFile(
    String path, {
    Map<String, dynamic>? query,
    required String fieldName,
    required String filePath,
    String? filename,
    String? contentType,
    Map<String, String>? fields,
    Duration timeout = const Duration(seconds: 30),
  });
}

/// Adapter default — delegasi apa adanya ke singleton `apiClient` asli
/// (auth header/timeout/decode/ApiException semua sudah ditangani di sana).
class _RealApiClient implements ApiClientLike {
  @override
  Future<dynamic> getJson(
    String path, {
    Map<String, dynamic>? query,
    Duration timeout = const Duration(seconds: 8),
  }) {
    return apiClient.getJson(path, query: query, timeout: timeout);
  }

  @override
  Future<dynamic> postJson(
    String path, {
    Object? body,
    Duration timeout = const Duration(seconds: 25),
  }) {
    return apiClient.postJson(path, body: body, timeout: timeout);
  }

  @override
  Future<dynamic> postMultipartFile(
    String path, {
    Map<String, dynamic>? query,
    required String fieldName,
    required String filePath,
    String? filename,
    String? contentType,
    Map<String, String>? fields,
    Duration timeout = const Duration(seconds: 30),
  }) {
    return apiClient.postMultipartFile(
      path,
      query: query,
      fieldName: fieldName,
      filePath: filePath,
      filename: filename,
      contentType: contentType,
      fields: fields,
      timeout: timeout,
    );
  }
}

const String _clientMsgIdAlphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

final Random _clientMsgIdRandom = Random.secure();

/// Bikin id optimistic per-pesan yang dikirim client — dipakai proxy untuk
/// dedupe retry (lihat `isValidClientMsgId` di `lib/chat/core.ts`, Natalo
/// repo: panjang 8-64, hanya `[A-Za-z0-9_-]`). Format: prefix `c`, timestamp
/// microsecond (radix-36, hanya `0-9a-z`) + underscore + 16 char random
/// alfanumerik — kombinasi timestamp+random bikin id unik antar panggilan
/// bahkan kalau terjadi di microsecond yang sama (mis. loop test cepat).
String newClientMsgId() {
  final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final suffix = List.generate(
    16,
    (_) => _clientMsgIdAlphabet[_clientMsgIdRandom.nextInt(
      _clientMsgIdAlphabet.length,
    )],
  ).join();
  final id = 'c${ts}_$suffix';
  // Guard defensif — harusnya tak pernah kepanjangan, tapi jaga kontrak
  // panjang maksimal 64 apa pun yang terjadi.
  return id.length > 64 ? id.substring(0, 64) : id;
}

/// Map list mentah respons proxy (`messages: [...]`) -> `List<ChatMessage>`
/// terurut ASC by `createdAt`, buang entri tanpa `id` non-kosong (data rusak
/// dari server harusnya tak pernah terjadi, tapi defensif). Fungsi murni,
/// tanpa I/O — dipakai `ChatService.fetchMessages`.
List<ChatMessage> mapMessages(List<dynamic> raw) {
  final out = <ChatMessage>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final map = Map<String, dynamic>.from(item);
    final id = map['id'];
    if (id == null || id.toString().trim().isEmpty) continue;
    out.add(ChatMessage.fromJson(map));
  }
  out.sort((a, b) => a.createdAt.compareTo(b.createdAt));
  return out;
}

/// Hasil `sendText`/`sendImage`.
///
/// **Bukan `ChatMessage` penuh** — proxy Plan 2 `/api/chat/send` &
/// `/api/chat/send-image` SENGAJA cuma balas `{ok, messageId, deduped}`
/// (+`url` untuk gambar), BUKAN objek pesan lengkap (lihat banner status
/// Plan 2 & kode `app/api/chat/send/route.ts` baris terakhir:
/// `NextResponse.json({ ok: true, messageId, deduped })`). Composer (Task
/// 5+) membangun bubble optimistic dari input lokal sendiri
/// (clientMsgId+text+now, status `sending`), lalu update status jadi
/// `sent`/pakai `messageId` ini begitu response datang — representasi
/// server penuh (senderRole/createdAt asli dst.) baru muncul di poll
/// berikutnya via `fetchMessages`.
class ChatSendResult {
  final bool ok;
  final String messageId;
  final bool deduped;

  /// URL gambar ter-upload — hanya terisi dari `sendImage` (`send` teks
  /// tidak punya field ini).
  final String? imageUrl;

  const ChatSendResult({
    this.ok = false,
    this.messageId = '',
    this.deduped = false,
    this.imageUrl,
  });
}

/// Hasil `fetchMessages` — `nextCursor` dipakai load-more (Plan 2 Task 7).
/// Backend nyata (Firestore `createdAt`) balas cursor sbg NUMBER, bukan
/// String — holder ini toleran (terima num ATAU string dari proxy) & selalu
/// expose sbg `String?` supaya caller tak perlu tahu tipe mentahnya.
class ChatMessagesPage {
  final List<ChatMessage> messages;
  final String? nextCursor;

  const ChatMessagesPage({this.messages = const [], this.nextCursor});
}

/// Config kill-switch + jam operasional (`GET /api/chat/config`, fix B3).
/// Default **fail-open**: `chatEnabled=true` (jangan matikan chat gara-gara
/// error network/parsing — itu tanggung jawab `ChatStore` yang catch di
/// layer atas, tapi default holder ini sendiri juga fail-open untuk
/// respons yang datang tapi field-nya hilang/rusak), `online=false`
/// (tampilkan status netral kalau tak yakin, BUKAN klaim online palsu).
class ChatConfig {
  final bool chatEnabled;
  final bool online;

  const ChatConfig({this.chatEnabled = true, this.online = false});
}

/// Wrapper endpoint chat proxy Plan 2. Semua method di sini MELEMPAR
/// `ApiException` apa adanya (termasuk `isUnauthorized` utk 401 re-login) —
/// caller (composer/screen, Task 5+) yang menangani. Beda dengan
/// `ChatStore.fetchUnread/fetchConfig` yang SENGAJA menyerap error supaya
/// polling background tak pernah crash app.
class ChatService {
  ChatService({ApiClientLike? client}) : _client = client ?? _RealApiClient();

  final ApiClientLike _client;

  /// Kirim pesan teks. `context` opsional — `{type: 'product'|'order',
  /// productId|orderNumber: ...}` (proxy re-fetch data tampilan dari Prisma,
  /// bukan percaya field lain dari client — lihat `app/api/chat/send/route.ts`).
  ///
  /// `clientMsgId` opsional — kalau caller sudah membangun bubble optimistic
  /// lokal (composer di `ChatRoomScreen`), ia MEMILIKI id-nya sendiri dan
  /// mengopernya ke sini supaya bubble optimistic & baris server yang datang
  /// di poll berikutnya (proyeksi proxy MEMBAWA `clientMsgId`) berbagi id
  /// yang sama → bisa dedupe/rekonsiliasi, dan retry mengirim ulang id YANG
  /// SAMA (proxy dedupe idempoten, lihat `writeCustomerMessage` di
  /// `lib/chat/rooms.ts`). Kalau null (call one-shot tanpa optimistic
  /// bubble), generate id baru sendiri.
  ///
  /// Tak ada parameter `chatId` di sini SENGAJA: proxy SELALU derive room
  /// dari sesi (`chatIdForUser(session.sub)`), tak pernah dari input client
  /// (anti-IDOR) — menambah parameter `chatId` yang tak pernah dipakai
  /// hanya akan menyesatkan pemanggil.
  Future<ChatSendResult> sendText(String text,
      {Map<String, dynamic>? context,
      String? replyToId,
      String? clientMsgId}) async {
    final data = await _client.postJson(
      '/api/chat/send',
      body: {
        'text': text,
        'clientMsgId': clientMsgId ?? newClientMsgId(),
        if (context != null) 'context': context,
        // Balasan: kirim HANYA id pesan yang dibalas — proxy mengambil-ulang
        // teks kutipan dari pesan asli (anti-palsu), klien tak boleh menyetir
        // isi kutipan. Pola sama dgn `context`.
        if (replyToId != null) 'replyTo': {'id': replyToId},
      },
    );
    return _parseSendResult(data);
  }

  /// Kirim foto. `clientMsgId` dikirim sebagai FIELD multipart/form-data
  /// (bukan query string): server (`app/api/chat/send-image/route.ts:75`)
  /// membacanya HANYA via `formData.get('clientMsgId')` — tidak ada fallback
  /// `searchParams`. Kirim lewat query akan bikin `formData.get` = null →
  /// `isValidClientMsgId(null)` gagal → 400 di setiap kirim foto. Karena itu
  /// dikirim via param `fields` (field form non-file, lihat
  /// `ApiClient.postMultipartFile`).
  ///
  /// `clientMsgId` opsional — sama seperti [sendText]: caller yang punya
  /// thumbnail optimistic mengoper id-nya sendiri supaya bisa direkonsiliasi
  /// dgn baris server + retry mengirim ulang id yang sama (dedupe proxy).
  Future<ChatSendResult> sendImage(String filePath,
      {String? clientMsgId}) async {
    final data = await _client.postMultipartFile(
      '/api/chat/send-image',
      fieldName: 'file',
      filePath: filePath,
      fields: {'clientMsgId': clientMsgId ?? newClientMsgId()},
      // 90 dtk (bukan default 30) — upload foto (s/d 5MB) + UploadThing di
      // server bisa lambat di jaringan mobile lemah; 30 dtk sering timeout
      // padahal upload sebenarnya masih jalan.
      timeout: const Duration(seconds: 90),
    );
    return _parseSendResult(data);
  }

  ChatSendResult _parseSendResult(dynamic data) {
    final map =
        data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    final url = map['url'];
    return ChatSendResult(
      ok: map['ok'] == true,
      messageId: (map['messageId'] ?? '').toString(),
      deduped: map['deduped'] == true,
      imageUrl: url is String ? url : null,
    );
  }

  /// Ambil histori pesan room `chatId` (selalu milik sesi sendiri — proxy
  /// validasi anti-IDOR di server, lihat `app/api/chat/[chatId]/route.ts`).
  /// `after` opsional = cursor halaman berikutnya (dari `nextCursor` respons
  /// sebelumnya, ATAU raw `createdAt` pesan terakhir yang sudah dimiliki).
  Future<ChatMessagesPage> fetchMessages(String chatId, {Object? after}) async {
    final data = await _client.getJson(
      '/api/chat/${Uri.encodeComponent(chatId)}',
      query: {if (after != null) 'after': '$after'},
    );
    final map =
        data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    final rawMessages = map['messages'];
    final messages = mapMessages(rawMessages is List ? rawMessages : const []);
    final cursorRaw = map['nextCursor'];
    return ChatMessagesPage(
      messages: messages,
      nextCursor: cursorRaw?.toString(),
    );
  }

  /// Badge unread pesan staff->customer (`AppChatButton`, Task 3).
  Future<int> fetchUnread() async {
    final data = await _client.getJson('/api/chat/unread');
    final map =
        data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    final raw = map['unreadForCustomer'];
    return raw is num ? raw.toInt() : 0;
  }

  /// Config kill-switch + jam operasional.
  Future<ChatConfig> fetchConfig() async {
    final data = await _client.getJson('/api/chat/config');
    final map =
        data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    final chatEnabled = map['chatEnabled'];
    final online = map['online'];
    return ChatConfig(
      chatEnabled: chatEnabled is bool ? chatEnabled : true,
      online: online is bool ? online : false,
    );
  }
}

final ChatService chatService = ChatService();

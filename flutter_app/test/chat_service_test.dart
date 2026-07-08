import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/services/api_client.dart';
import 'package:natalo_petshop_flutter/services/chat_service.dart';

/// Fake `ApiClientLike` — tanpa jaringan sama sekali. `postJsonHandler`/
/// `postMultipartHandler` opsional supaya tiap test bisa assert body/query/
/// fields yang dikirim sekaligus balas payload custom.
class _FakeApiClient implements ApiClientLike {
  _FakeApiClient({
    this.getResponses = const {},
    this.postJsonHandler,
    this.postMultipartHandler,
  });

  final Map<String, dynamic> getResponses;
  final dynamic Function(String path, Object? body)? postJsonHandler;
  // Terima query DAN fields — bug yang di-fix: clientMsgId harus datang
  // sebagai multipart FIELD (dibaca server via formData.get), bukan query.
  final dynamic Function(
    String path,
    Map<String, dynamic>? query,
    Map<String, String>? fields,
  )? postMultipartHandler;

  final List<Map<String, dynamic>> getCalls = [];
  Object? throwOnGet;

  @override
  Future<dynamic> getJson(
    String path, {
    Map<String, dynamic>? query,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    getCalls.add({'path': path, 'query': query});
    if (throwOnGet != null) throw throwOnGet!;
    return getResponses[path];
  }

  @override
  Future<dynamic> postJson(
    String path, {
    Object? body,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    return postJsonHandler?.call(path, body);
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
  }) async {
    return postMultipartHandler?.call(path, query, fields);
  }
}

void main() {
  group('newClientMsgId', () {
    test('valid format (8-64 char [A-Za-z0-9_-]) & unik antar panggilan', () {
      final id1 = newClientMsgId();
      final id2 = newClientMsgId();
      final re = RegExp(r'^[A-Za-z0-9_-]{8,64}$');
      expect(re.hasMatch(id1), true, reason: 'id1=$id1');
      expect(re.hasMatch(id2), true, reason: 'id2=$id2');
      expect(id1, isNot(equals(id2)));
    });
  });

  group('mapMessages', () {
    test('urut createdAt asc & buang entri tanpa id / id kosong', () {
      final result = mapMessages([
        {'id': 'm2', 'createdAt': 200, 'type': 'text'},
        {'createdAt': 50, 'type': 'text'}, // tanpa id -> drop
        {'id': 'm1', 'createdAt': 100, 'type': 'text'},
        {'id': '', 'createdAt': 10, 'type': 'text'}, // id kosong -> drop
      ]);
      expect(result.map((m) => m.id).toList(), ['m1', 'm2']);
    });

    test('list kosong -> list kosong (tanpa throw)', () {
      expect(mapMessages(const []), isEmpty);
    });
  });

  group('ChatService.sendText', () {
    test('kirim body {text, clientMsgId} & parse {ok, messageId, deduped}',
        () async {
      Map<String, dynamic>? capturedBody;
      final fake = _FakeApiClient(postJsonHandler: (path, body) {
        expect(path, '/api/chat/send');
        capturedBody = body as Map<String, dynamic>;
        return {'ok': true, 'messageId': 'm1', 'deduped': false};
      });
      final service = ChatService(client: fake);

      final result = await service.sendText('halo');

      expect(capturedBody!['text'], 'halo');
      expect(capturedBody!['clientMsgId'], isNotEmpty);
      expect(capturedBody!.containsKey('context'), false);
      expect(result.ok, true);
      expect(result.messageId, 'm1');
      expect(result.deduped, false);
    });

    test('sertakan context kalau diberikan', () async {
      Map<String, dynamic>? capturedBody;
      final fake = _FakeApiClient(postJsonHandler: (path, body) {
        capturedBody = body as Map<String, dynamic>;
        return {'ok': true, 'messageId': 'm2', 'deduped': false};
      });
      final service = ChatService(client: fake);

      await service.sendText(
        'lihat produk ini',
        context: {'type': 'product', 'productId': 'p1'},
      );

      expect(capturedBody!['context'], {'type': 'product', 'productId': 'p1'});
    });

    test('deduped=true tetap ok=true (retry idempoten)', () async {
      final fake = _FakeApiClient(postJsonHandler: (path, body) {
        return {'ok': true, 'messageId': 'm1', 'deduped': true};
      });
      final service = ChatService(client: fake);

      final result = await service.sendText('halo lagi');

      expect(result.deduped, true);
    });
  });

  group('ChatService.sendImage', () {
    test(
        'clientMsgId dikirim sebagai FIELD multipart (bukan query) & valid '
        'per isValidClientMsgId', () async {
      String? capturedPath;
      Map<String, dynamic>? capturedQuery;
      Map<String, String>? capturedFields;
      final fake = _FakeApiClient(postMultipartHandler: (path, query, fields) {
        capturedPath = path;
        capturedQuery = query;
        capturedFields = fields;
        return {
          'ok': true,
          'messageId': 'm3',
          'deduped': false,
          'url': 'https://x/y.jpg',
        };
      });
      final service = ChatService(client: fake);

      final result = await service.sendImage('/tmp/foo.jpg');

      expect(capturedPath, '/api/chat/send-image');
      // REGRESSION GUARD (confirmed bug): server hanya baca
      // formData.get('clientMsgId') — jadi HARUS lewat field, TIDAK boleh
      // lewat query (query -> formData null -> 400 di setiap kirim foto).
      final clientMsgId = capturedFields?['clientMsgId'];
      expect(clientMsgId, isNotNull);
      expect(RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(clientMsgId!), true,
          reason: 'clientMsgId=$clientMsgId');
      expect(
          capturedQuery == null || !capturedQuery!.containsKey('clientMsgId'),
          true,
          reason: 'clientMsgId TIDAK boleh dikirim via query: $capturedQuery');
      expect(result.ok, true);
      expect(result.imageUrl, 'https://x/y.jpg');
    });
  });

  group('ChatService.fetchMessages', () {
    test('parse {messages, nextCursor} & teruskan query after', () async {
      final fake = _FakeApiClient(getResponses: {
        '/api/chat/cust_1': {
          'messages': [
            {
              'id': 'm1',
              'createdAt': 1,
              'senderRole': 'customer',
              'type': 'text',
              'text': 'hai',
            },
          ],
          // Backend real (Firestore createdAt) balas NUMBER, bukan String —
          // holder harus toleran & tetap expose sbg String.
          'nextCursor': 12345,
        },
      });
      final service = ChatService(client: fake);

      final page = await service.fetchMessages('cust_1', after: 100);

      expect(page.messages.length, 1);
      expect(page.messages.first.id, 'm1');
      expect(page.nextCursor, '12345');
      expect(fake.getCalls.single['path'], '/api/chat/cust_1');
      expect(fake.getCalls.single['query'], {'after': '100'});
    });

    test('tanpa after -> query kosong; nextCursor null tetap null', () async {
      final fake = _FakeApiClient(getResponses: {
        '/api/chat/cust_1': {'messages': [], 'nextCursor': null},
      });
      final service = ChatService(client: fake);

      final page = await service.fetchMessages('cust_1');

      expect(page.messages, isEmpty);
      expect(page.nextCursor, isNull);
      expect(fake.getCalls.single['query'], {});
    });

    test('response tanpa field messages -> list kosong (tanpa throw)',
        () async {
      final fake = _FakeApiClient(getResponses: {
        '/api/chat/cust_1': <String, dynamic>{},
      });
      final service = ChatService(client: fake);

      final page = await service.fetchMessages('cust_1');

      expect(page.messages, isEmpty);
    });
  });

  group('ChatService.fetchUnread', () {
    test('parse unreadForCustomer angka', () async {
      final fake = _FakeApiClient(getResponses: {
        '/api/chat/unread': {'unreadForCustomer': 3},
      });
      final service = ChatService(client: fake);

      expect(await service.fetchUnread(), 3);
    });

    test('toleran: field hilang/non-angka -> 0', () async {
      final fake = _FakeApiClient(getResponses: {
        '/api/chat/unread': {'unreadForCustomer': 'bukan angka'},
      });
      final service = ChatService(client: fake);

      expect(await service.fetchUnread(), 0);
    });
  });

  group('ChatService.fetchConfig', () {
    test('parse chatEnabled=false & online=true', () async {
      final fake = _FakeApiClient(getResponses: {
        '/api/chat/config': {
          'chatEnabled': false,
          'online': true,
          'hours': <String, dynamic>{},
        },
      });
      final service = ChatService(client: fake);

      final config = await service.fetchConfig();

      expect(config.chatEnabled, false);
      expect(config.online, true);
    });

    test('toleran: field hilang -> fail-open (chatEnabled true, online false)',
        () async {
      final fake = _FakeApiClient(getResponses: {
        '/api/chat/config': <String, dynamic>{},
      });
      final service = ChatService(client: fake);

      final config = await service.fetchConfig();

      expect(config.chatEnabled, true);
      expect(config.online, false);
    });
  });

  group('ChatService — error propagation', () {
    test('ApiException dari client PROPAGASI apa adanya (tak diserap)',
        () async {
      final fake = _FakeApiClient()
        ..throwOnGet = const ApiException('Unauthorized', statusCode: 401);
      final service = ChatService(client: fake);

      expect(service.fetchUnread(), throwsA(isA<ApiException>()));
    });

    test('isUnauthorized true untuk 401 yg dilempar', () async {
      final fake = _FakeApiClient()
        ..throwOnGet = const ApiException('Unauthorized', statusCode: 401);
      final service = ChatService(client: fake);

      try {
        await service.fetchConfig();
        fail('harus melempar ApiException');
      } on ApiException catch (e) {
        expect(e.isUnauthorized, true);
      }
    });
  });
}

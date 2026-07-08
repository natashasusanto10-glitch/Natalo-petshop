import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/services/api_client.dart';
import 'package:natalo_petshop_flutter/services/chat_service.dart';
import 'package:natalo_petshop_flutter/state/chat_store.dart';

/// Fake `ApiClientLike` minimal — hanya `getJson` yang dipakai
/// `fetchUnread`/`fetchConfig`. `postJson`/`postMultipartFile` sengaja
/// `UnimplementedError` — kalau ChatStore tak sengaja memanggilnya, test
/// akan gagal loud, bukan diam-diam salah.
class _FakeApiClient implements ApiClientLike {
  _FakeApiClient({this.getResponses = const {}});

  final Map<String, dynamic> getResponses;
  Object? throwOnGet;

  @override
  Future<dynamic> getJson(
    String path, {
    Map<String, dynamic>? query,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (throwOnGet != null) throw throwOnGet!;
    return getResponses[path];
  }

  @override
  Future<dynamic> postJson(
    String path, {
    Object? body,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    throw UnimplementedError('postJson tak dipakai ChatStore');
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
    throw UnimplementedError('postMultipartFile tak dipakai ChatStore');
  }
}

void main() {
  group('ChatStore.setUnread', () {
    test('notifyListeners HANYA saat nilai berubah', () {
      final store = ChatStore();
      var notifyCount = 0;
      store.addListener(() => notifyCount++);

      store.setUnread(3);
      expect(store.unreadCount, 3);
      expect(notifyCount, 1);

      store.setUnread(3); // nilai sama -> no notify
      expect(notifyCount, 1);

      store.setUnread(5);
      expect(store.unreadCount, 5);
      expect(notifyCount, 2);
    });

    test('default unreadCount = 0', () {
      expect(ChatStore().unreadCount, 0);
    });
  });

  group('ChatStore.applyConfig', () {
    test('notifyListeners HANYA saat salah satu field berubah', () {
      final store = ChatStore();
      var notifyCount = 0;
      store.addListener(() => notifyCount++);

      // Sama dgn default (chatEnabled=true, online=false) -> no notify.
      store.applyConfig(chatEnabled: true, online: false);
      expect(notifyCount, 0);

      store.applyConfig(chatEnabled: false, online: false);
      expect(store.chatEnabled, false);
      expect(store.online, false);
      expect(notifyCount, 1);

      store.applyConfig(chatEnabled: false, online: false); // sama -> no notify
      expect(notifyCount, 1);

      store.applyConfig(chatEnabled: false, online: true); // online berubah
      expect(store.online, true);
      expect(notifyCount, 2);
    });

    test('default chatEnabled=true (fail-open), online=false', () {
      final store = ChatStore();
      expect(store.chatEnabled, true);
      expect(store.online, false);
    });
  });

  group('ChatStore.fetchUnread', () {
    test('fake client sukses -> isi state', () async {
      final fake = _FakeApiClient(getResponses: {
        '/api/chat/unread': {'unreadForCustomer': 7},
      });
      final store = ChatStore(service: ChatService(client: fake));

      await store.fetchUnread();

      expect(store.unreadCount, 7);
    });

    test('error jaringan -> state TAK berubah (aman, tak crash)', () async {
      final fake = _FakeApiClient()
        ..throwOnGet = const ApiException('network down');
      final store = ChatStore(service: ChatService(client: fake));
      store.setUnread(4); // state awal, bukan dari network

      await store.fetchUnread(); // tak boleh throw ke caller

      expect(store.unreadCount, 4); // tak berubah
    });
  });

  group('ChatStore.fetchConfig', () {
    test('fake client sukses -> isi chatEnabled & online (fix B3)', () async {
      final fake = _FakeApiClient(getResponses: {
        '/api/chat/config': {
          'chatEnabled': false,
          'online': true,
          'hours': <String, dynamic>{},
        },
      });
      final store = ChatStore(service: ChatService(client: fake));

      await store.fetchConfig();

      expect(store.chatEnabled, false);
      expect(store.online, true);
    });

    test('error jaringan -> chatEnabled tetap true (fail-open)', () async {
      final fake = _FakeApiClient()
        ..throwOnGet = const ApiException('network down');
      final store = ChatStore(service: ChatService(client: fake));
      // Set ke state non-default dulu supaya test benar2 verifikasi
      // "tak berubah", bukan cuma kebetulan sama dgn default.
      store.applyConfig(chatEnabled: false, online: true);

      await store.fetchConfig(); // tak boleh throw ke caller

      expect(store.chatEnabled, false); // tak berubah dari sebelum fetch
      expect(store.online, true); // tak berubah dari sebelum fetch
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:natalo_petshop_flutter/services/chat_message_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SharedPreferences> freshPrefs() async {
    SharedPreferences.setMockInitialValues({});
    return SharedPreferences.getInstance();
  }

  test('loadLatest kosong saat belum ada cache', () async {
    final cache = ChatMessageCache(prefs: freshPrefs);
    expect(await cache.loadLatest('cust_1'), isEmpty);
  });

  test('save lalu load round-trip via fromJson (asc + dedupe id kosong)',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final cache = ChatMessageCache(prefs: () async => prefs);

    await cache.saveLatest('cust_1', [
      {'id': 'm2', 'createdAt': 200, 'senderRole': 'customer', 'type': 'text', 'text': 'b'},
      {'id': 'm1', 'createdAt': 100, 'senderRole': 'customer', 'type': 'text', 'text': 'a'},
      {'createdAt': 50, 'type': 'text'}, // tanpa id → di-drop mapMessages
    ]);

    final loaded = await cache.loadLatest('cust_1');
    // Terurut asc & entri rusak dibuang (kontrak mapMessages).
    expect(loaded.map((m) => m.id).toList(), ['m1', 'm2']);
  });

  test('saveLatest memangkas ke 60 entri terakhir', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final cache = ChatMessageCache(prefs: () async => prefs);

    final many = List.generate(
      100,
      (i) => {
        'id': 'm$i',
        'createdAt': i,
        'senderRole': 'customer',
        'type': 'text',
        'text': 't$i',
      },
    );
    await cache.saveLatest('cust_1', many);

    final loaded = await cache.loadLatest('cust_1');
    expect(loaded.length, 60);
    // Yang tersimpan adalah 60 TERAKHIR (m40..m99).
    expect(loaded.first.id, 'm40');
    expect(loaded.last.id, 'm99');
  });

  test('clear menghapus cache room', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final cache = ChatMessageCache(prefs: () async => prefs);

    await cache.saveLatest('cust_1', [
      {'id': 'm1', 'createdAt': 1, 'senderRole': 'customer', 'type': 'text', 'text': 'x'},
    ]);
    expect(await cache.loadLatest('cust_1'), isNotEmpty);

    await cache.clear('cust_1');
    expect(await cache.loadLatest('cust_1'), isEmpty);
  });

  test('load toleran data rusak (bukan JSON list) → kosong', () async {
    SharedPreferences.setMockInitialValues({'chat_cache_v1_cust_1': 'bukan-json'});
    final prefs = await SharedPreferences.getInstance();
    final cache = ChatMessageCache(prefs: () async => prefs);

    expect(await cache.loadLatest('cust_1'), isEmpty);
  });
}

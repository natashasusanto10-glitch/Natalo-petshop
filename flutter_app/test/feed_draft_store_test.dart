import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/state/feed_draft_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('feed_draft_store_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<File> makeFile(String name) async {
    final file = File('${tempDir.path}${Platform.pathSeparator}$name');
    await file.writeAsString('fake-media-bytes');
    return file;
  }

  group('FeedDraftStore', () {
    test('save + load round-trip semua field', () async {
      final photo = await makeFile('photo1.jpg');
      final thumb = await makeFile('thumb1.jpg');
      final store = FeedDraftStore();
      final draft = FeedDraft(
        id: 'draft-1',
        type: 'video',
        caption: 'Halo dunia',
        productIds: const ['p1', 'p2'],
        mediaPaths: [photo.path],
        thumbnailPath: thumb.path,
        trimStartMs: 1500,
        trimmedDurationMs: 8000,
        originalDurationMs: 12000,
        userPickedCover: true,
        savedAtMs: 1720000000000,
      );

      await store.save(draft);
      final loaded = await store.load();

      expect(loaded, hasLength(1));
      final restored = loaded.single;
      expect(restored.id, 'draft-1');
      expect(restored.type, 'video');
      expect(restored.caption, 'Halo dunia');
      expect(restored.productIds, ['p1', 'p2']);
      expect(restored.mediaPaths, [photo.path]);
      expect(restored.thumbnailPath, thumb.path);
      expect(restored.trimStartMs, 1500);
      expect(restored.trimmedDurationMs, 8000);
      expect(restored.originalDurationMs, 12000);
      expect(restored.userPickedCover, true);
      expect(restored.savedAtMs, 1720000000000);
      expect(restored.broken, false);
    });

    test('upsert by id — save draft dengan id sama menimpa, bukan duplikat',
        () async {
      final photo = await makeFile('photo1.jpg');
      final store = FeedDraftStore();
      final draft1 = FeedDraft(
        id: 'draft-1',
        type: 'image',
        caption: 'versi 1',
        productIds: const [],
        mediaPaths: [photo.path],
        savedAtMs: 1000,
      );
      final draft2 = FeedDraft(
        id: 'draft-1',
        type: 'image',
        caption: 'versi 2',
        productIds: const [],
        mediaPaths: [photo.path],
        savedAtMs: 2000,
      );

      await store.save(draft1);
      await store.save(draft2);
      final loaded = await store.load();

      expect(loaded, hasLength(1));
      expect(loaded.single.caption, 'versi 2');
    });

    test('maks 5 draft — draft ke-6 menggeser yang terlama', () async {
      final photo = await makeFile('photo1.jpg');
      final store = FeedDraftStore();
      for (var i = 1; i <= 6; i++) {
        await store.save(FeedDraft(
          id: 'draft-$i',
          type: 'image',
          caption: 'draft $i',
          productIds: const [],
          mediaPaths: [photo.path],
          savedAtMs: i * 1000,
        ));
      }
      final loaded = await store.load();

      expect(loaded, hasLength(5));
      expect(loaded.map((d) => d.id), isNot(contains('draft-1')));
      expect(loaded.map((d) => d.id), contains('draft-6'));
    });

    test('migrasi otomatis dari slot lama saat load pertama', () async {
      final photo = await makeFile('photo1.jpg');
      final prefs = await SharedPreferences.getInstance();
      final payload = {
        'type': 'image',
        'caption': 'draft lama',
        'productIds': ['p9'],
        'media': [photo.path],
        'thumbnailPath': null,
        'trimStartMs': null,
        'userPickedCover': false,
        'savedAt': 1650000000000,
      };
      await prefs.setString(
        'natalo-feed-upload-pending',
        'local|post-new|${jsonEncode(payload)}|1650000000000',
      );

      final store = FeedDraftStore();
      final loaded = await store.load();

      expect(loaded, hasLength(1));
      expect(loaded.single.caption, 'draft lama');
      expect(loaded.single.type, 'image');
      expect(loaded.single.productIds, ['p9']);
      expect(prefs.getString('natalo-feed-upload-pending'), isNull);
    });

    test('media hilang → draft ditandai broken tapi tetap dikembalikan',
        () async {
      final store = FeedDraftStore();
      final draft = FeedDraft(
        id: 'draft-missing',
        type: 'image',
        caption: 'file hilang',
        productIds: const [],
        mediaPaths: ['${tempDir.path}${Platform.pathSeparator}ghost.jpg'],
        savedAtMs: 1000,
      );
      await store.save(draft);
      final loaded = await store.load();

      expect(loaded, hasLength(1));
      expect(loaded.single.broken, true);
    });

    test('remove menghapus draft by id', () async {
      final photo = await makeFile('photo1.jpg');
      final store = FeedDraftStore();
      await store.save(FeedDraft(
        id: 'draft-a',
        type: 'image',
        caption: 'a',
        productIds: const [],
        mediaPaths: [photo.path],
        savedAtMs: 1000,
      ));
      await store.save(FeedDraft(
        id: 'draft-b',
        type: 'image',
        caption: 'b',
        productIds: const [],
        mediaPaths: [photo.path],
        savedAtMs: 2000,
      ));

      await store.remove('draft-a');
      final loaded = await store.load();

      expect(loaded, hasLength(1));
      expect(loaded.single.id, 'draft-b');
    });

    test('clearAll menghapus semua draft', () async {
      final photo = await makeFile('photo1.jpg');
      final store = FeedDraftStore();
      await store.save(FeedDraft(
        id: 'draft-a',
        type: 'image',
        caption: 'a',
        productIds: const [],
        mediaPaths: [photo.path],
        savedAtMs: 1000,
      ));

      await store.clearAll();
      final loaded = await store.load();

      expect(loaded, isEmpty);
    });
  });
}

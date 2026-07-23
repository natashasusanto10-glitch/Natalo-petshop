import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_create_post_draft.dart';
import 'package:natalo_petshop_flutter/models/new_post_user_tag.dart';
import 'package:natalo_petshop_flutter/services/video_compress_gate.dart';
import 'package:natalo_petshop_flutter/state/feed_upload_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_compress/video_compress.dart';

const _pendingKey = 'natalo-feed-upload-inflight';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('kompresi gagal + trimStart → task FAILED (tanpa fallback original)',
      () async {
    final tmp = await File(
      '${Directory.systemTemp.path}/store-test-${DateTime.now().microsecondsSinceEpoch}.mp4',
    ).create();
    addTearDown(() => tmp.delete());
    final store = FeedUploadStore.instance;
    store.clear();
    VideoQuality? requestedQuality;
    store.gate = VideoCompressGate(
      compressRunner: (path,
          {quality = VideoQuality.Res1280x720Quality,
          includeAudio = true,
          startTime,
          duration}) async {
        requestedQuality = quality;
        throw StateError('compress boom');
      },
      cancelRunner: () async {},
      isPluginBusy: () => false,
      resetPluginFlag: () {},
    );
    // Rekam riwayat status (dedupe berurutan) via listener — sinyal pembeda
    // antara "rethrow murni" vs "regresi ke fallback lalu gagal di network":
    // fallback SELALU melewati status `uploading` (di-set saat mulai upload
    // thumbnail, progress 0.1) sebelum akhirnya gagal. Jalur rethrow gagal
    // SAAT kompresi, sebelum tahap upload — jadi `uploading` TIDAK PERNAH
    // tercapai. Assert final==failed saja tidak membedakan kedua jalur ini.
    final history = <FeedUploadStatus>[];
    void listener() {
      final status = store.activeTask?.status;
      if (status != null && (history.isEmpty || history.last != status)) {
        history.add(status);
      }
    }

    store.addListener(listener);
    addTearDown(() => store.removeListener(listener));

    await store.startVideoUpload(
      draft: FeedCreatePostDraft(
        localVideoPath: tmp.path,
        originalDuration: const Duration(seconds: 70),
        trimStart: const Duration(seconds: 5),
        trimmedDuration: const Duration(seconds: 60),
      ),
    );
    // startVideoUpload fire-and-forget — tunggu task settle.
    for (var i = 0;
        i < 50 && store.activeTask?.status != FeedUploadStatus.failed;
        i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(store.activeTask?.status, FeedUploadStatus.failed);
    expect(history, contains(FeedUploadStatus.failed));
    expect(
      history,
      isNot(contains(FeedUploadStatus.uploading)),
      reason: 'rethrow-on-trim-fail harus gagal SAAT kompresi, sebelum '
          'tahap upload — status uploading tak boleh pernah tercapai. '
          'Jika tercapai, berarti regresi ke fallback (upload video asli).',
    );
    expect(requestedQuality, VideoQuality.Res1920x1080Quality);
    store.removeListener(listener);
    store.clear();
  });

  group('prepareVideoPathForUpload', () {
    test('tanpa trim + sumber <=Full HD tetap di-re-encode (Opsi A kompres 4G)',
        () async {
      // Opsi A: sumber <=1080p TIDAK lagi di-skip — di-re-encode supaya bitrate
      // rekaman HP dipangkas. Hasil kompres lebih kecil (5 < 20 byte) → dipakai.
      final original = await File(
        '${Directory.systemTemp.path}/store-fullhd-${DateTime.now().microsecondsSinceEpoch}.mp4',
      ).writeAsBytes(List<int>.filled(20, 1));
      final compressed = await File(
        '${Directory.systemTemp.path}/store-fullhd-c-${DateTime.now().microsecondsSinceEpoch}.mp4',
      ).writeAsBytes(List<int>.filled(5, 2));
      addTearDown(() async {
        if (await original.exists()) await original.delete();
        if (await compressed.exists()) await compressed.delete();
      });
      final store = FeedUploadStore.instance;
      store.clear();
      var compressCalls = 0;
      store.gate = VideoCompressGate(
        compressRunner: (path,
            {quality = VideoQuality.Res1280x720Quality,
            includeAudio = true,
            startTime,
            duration}) async {
          compressCalls += 1;
          return MediaInfo(path: compressed.path, file: compressed);
        },
        cancelRunner: () async {},
        isPluginBusy: () => false,
        resetPluginFlag: () {},
      );

      final selected = await store.prepareVideoPathForUpload(
        FeedCreatePostDraft(
          localVideoPath: original.path,
          originalDuration: const Duration(seconds: 30),
        ),
        original.path,
      );

      expect(compressCalls, 1,
          reason: 'sumber <=1080p kini tetap di-re-encode (bukan di-skip)');
      expect(selected, compressed.path,
          reason: 'hasil kompres lebih kecil → dipakai');
      store.clear();
    });

    test(
        'tanpa trim + hasil kompres lebih besar memakai original dan hapus temp',
        () async {
      final original = await File(
        '${Directory.systemTemp.path}/store-original-${DateTime.now().microsecondsSinceEpoch}.mp4',
      ).writeAsBytes(List<int>.filled(10, 1));
      final compressed = await File(
        '${Directory.systemTemp.path}/store-compressed-${DateTime.now().microsecondsSinceEpoch}.mp4',
      ).writeAsBytes(List<int>.filled(20, 2));
      addTearDown(() async {
        if (await original.exists()) await original.delete();
        if (await compressed.exists()) await compressed.delete();
      });
      final store = FeedUploadStore.instance;
      store.clear();
      store.gate = VideoCompressGate(
        compressRunner: (path,
            {quality = VideoQuality.Res1280x720Quality,
            includeAudio = true,
            startTime,
            duration}) async {
          return MediaInfo(path: compressed.path, file: compressed);
        },
        cancelRunner: () async {},
        isPluginBusy: () => false,
        resetPluginFlag: () {},
      );

      final selected = await store.prepareVideoPathForUpload(
        FeedCreatePostDraft(
          localVideoPath: original.path,
          originalDuration: const Duration(seconds: 30),
        ),
        original.path,
      );

      expect(selected, original.path);
      expect(await compressed.exists(), isFalse);
      store.clear();
    });

    test('trim tetap memakai output kompres meski lebih besar', () async {
      final original = await File(
        '${Directory.systemTemp.path}/store-trim-original-${DateTime.now().microsecondsSinceEpoch}.mp4',
      ).writeAsBytes(List<int>.filled(10, 1));
      final compressed = await File(
        '${Directory.systemTemp.path}/store-trim-compressed-${DateTime.now().microsecondsSinceEpoch}.mp4',
      ).writeAsBytes(List<int>.filled(20, 2));
      addTearDown(() async {
        if (await original.exists()) await original.delete();
        if (await compressed.exists()) await compressed.delete();
      });
      final store = FeedUploadStore.instance;
      store.clear();
      store.gate = VideoCompressGate(
        compressRunner: (path,
            {quality = VideoQuality.Res1280x720Quality,
            includeAudio = true,
            startTime,
            duration}) async {
          return MediaInfo(path: compressed.path, file: compressed);
        },
        cancelRunner: () async {},
        isPluginBusy: () => false,
        resetPluginFlag: () {},
      );

      final selected = await store.prepareVideoPathForUpload(
        FeedCreatePostDraft(
          localVideoPath: original.path,
          originalDuration: const Duration(seconds: 70),
          trimStart: const Duration(seconds: 5),
          trimmedDuration: const Duration(seconds: 60),
        ),
        original.path,
      );

      expect(selected, compressed.path);
      expect(await compressed.exists(), isTrue);
      store.clear();
    });
  });

  test('cancelActive saat kompresi trimmed → status CANCELLED, bukan failed',
      () async {
    final tmp = await File(
      '${Directory.systemTemp.path}/store-cancel-${DateTime.now().microsecondsSinceEpoch}.mp4',
    ).create();
    addTearDown(() => tmp.delete());
    final store = FeedUploadStore.instance;
    store.clear();
    final started = Completer<void>();
    final blocker = Completer<MediaInfo?>();
    store.gate = VideoCompressGate(
      compressRunner: (path,
          {quality = VideoQuality.Res1280x720Quality,
          includeAudio = true,
          startTime,
          duration}) {
        started.complete();
        return blocker.future;
      },
      cancelRunner: () async =>
          blocker.completeError(StateError('cancelled by user')),
      isPluginBusy: () => false,
      resetPluginFlag: () {},
    );
    unawaited(store.startVideoUpload(
      draft: FeedCreatePostDraft(
        localVideoPath: tmp.path,
        originalDuration: const Duration(seconds: 70),
        trimStart: const Duration(seconds: 5),
        trimmedDuration: const Duration(seconds: 60),
      ),
    ));
    await started.future;
    await store.cancelActive();
    for (var i = 0; i < 50; i++) {
      final s = store.activeTask?.status;
      if (s == FeedUploadStatus.cancelled ||
          s == FeedUploadStatus.failed ||
          store.activeTask == null) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    // Status TIDAK boleh failed; boleh cancelled atau task sudah di-clear.
    expect(store.activeTask?.status, isNot(FeedUploadStatus.failed));
    store.clear();
  });

  group('resume upload setelah app ditutup (2C-4)', () {
    test(
        'checkForResumableUpload dengan payload valid + file media ada → '
        'task RESUMABLE', () async {
      final tmp = await File(
        '${Directory.systemTemp.path}/store-resume-${DateTime.now().microsecondsSinceEpoch}.mp4',
      ).create();
      addTearDown(() => tmp.delete());

      const taggedUsers = [
        NewPostUserTag(
          userId: 'u-video-resume',
          username: 'resume_user',
          name: 'Resume User',
        ),
      ];
      final payload = {
        'localId': 'upl-resume-1',
        'kind': 'video',
        'caption': 'Halo dari resume',
        'productIds': <String>['p1', 'p2'],
        'taggedUsers': taggedUsers.map((t) => t.toJson()).toList(),
        'mediaPaths': <String>[],
        'thumbnailPath': null,
        'localVideoPath': tmp.path,
        'trimStartMs': 5000,
        'trimmedDurationMs': 60000,
        'originalDurationMs': 70000,
        'userPickedCover': false,
        'mimeType': 'video/mp4',
        'originalFilename': 'clip.mp4',
        'provision': null,
        'savedAtMs': DateTime.now().millisecondsSinceEpoch,
      };
      SharedPreferences.setMockInitialValues({
        _pendingKey: jsonEncode(payload),
      });

      final store = FeedUploadStore.instance;
      store.clear();
      await store.checkForResumableUpload();

      expect(store.activeTask?.status, FeedUploadStatus.resumable);
      expect(store.activeTask?.kind, FeedUploadKind.video);
      expect(store.activeTask?.caption, 'Halo dari resume');
      expect(store.activeTask?.productIds, ['p1', 'p2']);
      expect(store.activeTask?.videoDraft?.localVideoPath, tmp.path);
      expect(store.activeTask?.taggedUsers, hasLength(1));
      expect(store.activeTask?.taggedUsers.single.userId, 'u-video-resume');
      expect(store.activeTask?.taggedUsers.single.mediaIndex, isNull);
      store.clear();
    });

    test(
        'checkForResumableUpload dengan file media hilang → tidak ada task '
        '+ persist terhapus', () async {
      final missingPath =
          '${Directory.systemTemp.path}/store-resume-missing-${DateTime.now().microsecondsSinceEpoch}.mp4';
      final payload = {
        'localId': 'upl-resume-2',
        'kind': 'video',
        'caption': '',
        'productIds': <String>[],
        'mediaPaths': <String>[],
        'thumbnailPath': null,
        'localVideoPath': missingPath,
        'trimStartMs': null,
        'trimmedDurationMs': null,
        'originalDurationMs': null,
        'userPickedCover': false,
        'mimeType': null,
        'originalFilename': null,
        'provision': null,
        'savedAtMs': DateTime.now().millisecondsSinceEpoch,
      };
      SharedPreferences.setMockInitialValues({
        _pendingKey: jsonEncode(payload),
      });

      final store = FeedUploadStore.instance;
      store.clear();
      await store.checkForResumableUpload();

      expect(store.activeTask, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_pendingKey), isNull);
      store.clear();
    });

    test('dismissResumable → task null + persist terhapus', () async {
      final tmp = await File(
        '${Directory.systemTemp.path}/store-resume-dismiss-${DateTime.now().microsecondsSinceEpoch}.mp4',
      ).create();
      addTearDown(() => tmp.delete());
      final payload = {
        'localId': 'upl-resume-3',
        'kind': 'video',
        'caption': '',
        'productIds': <String>[],
        'mediaPaths': <String>[],
        'thumbnailPath': null,
        'localVideoPath': tmp.path,
        'trimStartMs': null,
        'trimmedDurationMs': null,
        'originalDurationMs': null,
        'userPickedCover': false,
        'mimeType': null,
        'originalFilename': null,
        'provision': null,
        'savedAtMs': DateTime.now().millisecondsSinceEpoch,
      };
      SharedPreferences.setMockInitialValues({
        _pendingKey: jsonEncode(payload),
      });

      final store = FeedUploadStore.instance;
      store.clear();
      await store.checkForResumableUpload();
      expect(store.activeTask?.status, FeedUploadStatus.resumable);

      store.dismissResumable();
      // dismissResumable clears persist async (fire-and-forget) — beri
      // giliran microtask/timer supaya prefs.remove selesai.
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(store.activeTask, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_pendingKey), isNull);
      store.clear();
    });

    test('persist ditulis saat upload video mulai (gate menggantung)',
        () async {
      final tmp = await File(
        '${Directory.systemTemp.path}/store-resume-start-${DateTime.now().microsecondsSinceEpoch}.mp4',
      ).create();
      addTearDown(() => tmp.delete());
      final store = FeedUploadStore.instance;
      store.clear();
      final started = Completer<void>();
      final blocker = Completer<MediaInfo?>();
      store.gate = VideoCompressGate(
        compressRunner: (path,
            {quality = VideoQuality.Res1280x720Quality,
            includeAudio = true,
            startTime,
            duration}) {
          started.complete();
          return blocker.future;
        },
        cancelRunner: () async {},
        isPluginBusy: () => false,
        resetPluginFlag: () {},
      );

      unawaited(store.startVideoUpload(
        draft: FeedCreatePostDraft(
          localVideoPath: tmp.path,
          originalDuration: const Duration(seconds: 70),
          trimStart: const Duration(seconds: 5),
          trimmedDuration: const Duration(seconds: 60),
        ),
      ));
      await started.future;
      // Beri giliran microtask supaya _persistPending (await SharedPreferences
      // + prefs.setString) sempat jalan sebelum compress future digantung.
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_pendingKey), isNotNull);

      blocker.completeError(StateError('cleanup'));
      for (var i = 0;
          i < 50 && store.activeTask?.status != FeedUploadStatus.failed;
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      store.clear();
    });
  });
}

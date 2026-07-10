import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_create_post_draft.dart';
import 'package:natalo_petshop_flutter/services/video_compress_gate.dart';
import 'package:natalo_petshop_flutter/state/feed_upload_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_compress/video_compress.dart';

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
    store.gate = VideoCompressGate(
      compressRunner: (path, {quality = VideoQuality.Res1280x720Quality,
          includeAudio = true, startTime, duration}) async {
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
    for (var i = 0; i < 50 && store.activeTask?.status != FeedUploadStatus.failed; i++) {
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
    store.removeListener(listener);
    store.clear();
  });
}

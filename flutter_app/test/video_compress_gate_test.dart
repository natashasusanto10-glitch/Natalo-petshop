import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/services/video_compress_gate.dart';
import 'package:video_compress/video_compress.dart';

/// Helper — bikin CompressRunner dari body sederhana (param named lengkap
/// supaya match typedef, tapi test cuma peduli path).
CompressRunner runnerWith(Future<MediaInfo?> Function(String path) body) {
  return (
    String path, {
    VideoQuality quality = VideoQuality.Res1280x720Quality,
    bool includeAudio = true,
    int? startTime,
    int? duration,
  }) =>
      body(path);
}

void main() {
  group('VideoCompressGate', () {
    test('serialisasi: job kedua menunggu job pertama selesai', () async {
      final log = <String>[];
      final firstDone = Completer<void>();
      var call = 0;
      final gate = VideoCompressGate(
        compressRunner: runnerWith((path) async {
          call += 1;
          final id = call;
          log.add('start-$id');
          if (id == 1) await firstDone.future;
          log.add('end-$id');
          return null;
        }),
        cancelRunner: () async {},
        isPluginBusy: () => false,
        resetPluginFlag: () {},
      );

      final f1 = gate.compress('a.mp4');
      final f2 = gate.compress('b.mp4');
      await Future<void>.delayed(Duration.zero);
      expect(log, ['start-1'], reason: 'job 2 belum boleh mulai');
      firstDone.complete();
      await Future.wait([f1, f2]);
      expect(log, ['start-1', 'end-1', 'start-2', 'end-2']);
    });

    test('cancel ber-scope: cancel job antre tidak menyentuh plugin, '
        'job lain tetap jalan', () async {
      final aDone = Completer<void>();
      var cancelCalls = 0;
      final gate = VideoCompressGate(
        compressRunner: runnerWith((path) async {
          if (path == 'a.mp4') await aDone.future;
          return null;
        }),
        cancelRunner: () async => cancelCalls += 1,
        isPluginBusy: () => false,
        resetPluginFlag: () {},
      );
      final jobA = VideoCompressJob();
      final jobB = VideoCompressJob();
      final fA = gate.compress('a.mp4', job: jobA);
      final fB = gate.compress('b.mp4', job: jobB);
      await Future<void>.delayed(Duration.zero);

      await gate.cancel(jobB); // B masih antre — bukan job aktif
      expect(cancelCalls, 0, reason: 'plugin tidak boleh di-cancel');

      aDone.complete();
      expect(await fB, isNull, reason: 'B batal tanpa pernah jalan');
      await fA;

      await gate.cancel(jobA); // A sudah selesai → no-op
      expect(cancelCalls, 0);
    });

    test('cancel job aktif → cancelRunner dipanggil', () async {
      final started = Completer<void>();
      final blocker = Completer<MediaInfo?>();
      var cancelCalls = 0;
      final gate = VideoCompressGate(
        compressRunner: runnerWith((path) {
          started.complete();
          return blocker.future;
        }),
        cancelRunner: () async {
          cancelCalls += 1;
          blocker.complete(null); // simulasi plugin berhenti
        },
        isPluginBusy: () => false,
        resetPluginFlag: () {},
      );
      final job = VideoCompressJob();
      final f = gate.compress('a.mp4', job: job);
      await started.future;
      await gate.cancel(job);
      expect(cancelCalls, 1);
      expect(await f, isNull);
    });

    test('flag nyangkut setelah throw di-reset (finally) dan jalur pulih',
        () async {
      var busy = false;
      var resets = 0;
      final gate = VideoCompressGate(
        compressRunner: runnerWith((path) async {
          if (path == 'boom.mp4') {
            busy = true; // simulasi plugin ninggalin flag saat throw
            throw StateError('boom');
          }
          return null;
        }),
        cancelRunner: () async {},
        isPluginBusy: () => busy,
        resetPluginFlag: () {
          resets += 1;
          busy = false;
        },
      );
      await expectLater(gate.compress('boom.mp4'), throwsStateError);
      expect(resets, 1, reason: 'finally wajib reset flag nyangkut');
      expect(busy, isFalse);
      expect(await gate.compress('ok.mp4'), isNull,
          reason: 'kompresi berikutnya harus jalan normal');
    });

    test('flag stale saat idle di-reset SEBELUM job baru', () async {
      var busy = true; // plugin klaim sibuk padahal gate idle → stale
      var resets = 0;
      final gate = VideoCompressGate(
        compressRunner: runnerWith((path) async => null),
        cancelRunner: () async {},
        isPluginBusy: () => busy,
        resetPluginFlag: () {
          resets += 1;
          busy = false;
        },
      );
      expect(await gate.compress('a.mp4'), isNull);
      expect(resets, 1);
    });

    test('job yang di-cancel sebelum mulai tidak memanggil runner', () async {
      var runnerCalls = 0;
      final gate = VideoCompressGate(
        compressRunner: runnerWith((path) async {
          runnerCalls += 1;
          return null;
        }),
        cancelRunner: () async {},
        isPluginBusy: () => false,
        resetPluginFlag: () {},
      );
      final job = VideoCompressJob();
      await gate.cancel(job); // batal sebelum compress dipanggil
      expect(await gate.compress('a.mp4', job: job), isNull);
      expect(runnerCalls, 0);
    });
  });
}

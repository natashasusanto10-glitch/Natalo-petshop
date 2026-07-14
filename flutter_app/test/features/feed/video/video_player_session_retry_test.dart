import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/video/video_player_session.dart';
import 'package:natalo_petshop_flutter/services/video_quality_service.dart';
import 'package:video_player/video_player.dart';

/// T4 — orkestrasi retry/refresh [VideoPlayerSession] diuji via seam
/// `debugInitAttempt` (tanpa plugin video_player). Controller nyata null di
/// jalur test; kita hanya memverifikasi budget retry, klasifikasi permanen,
/// refresh signed URL (D4), dan reset budget lewat `retry()`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Delay backoff jadi no-op supaya test cepat & deterministik.
  Future<void> noDelay(Duration _) async {}

  test('buffer ahead merges adjacent ranges', () {
    final ahead = VideoPlayerSession.contiguousBufferAhead(
      position: const Duration(seconds: 1),
      buffered: [
        DurationRange(Duration.zero, const Duration(seconds: 2)),
        DurationRange(
          const Duration(seconds: 2),
          const Duration(seconds: 5),
        ),
      ],
    );

    expect(ahead, const Duration(seconds: 4));
  });

  test('buffer ahead stops at the first gap after playback position', () {
    final ahead = VideoPlayerSession.contiguousBufferAhead(
      position: const Duration(seconds: 1),
      buffered: [
        DurationRange(Duration.zero, const Duration(seconds: 2)),
        DurationRange(
          const Duration(seconds: 3),
          const Duration(seconds: 8),
        ),
      ],
    );

    expect(ahead, const Duration(seconds: 1));
  });

  test('metrics include network, quality, and startup context', () async {
    final metrics = <String, Map<String, Object>>{};
    final session = VideoPlayerSession(
      url: 'https://cdn/play_720p.mp4',
      userQualityPreference: 'data_saver',
      debugNetworkTier: NetworkTier.cellularSlow,
      debugMetricSink: (event, parameters) => metrics[event] = parameters,
      debugInitAttempt: (_) async {},
    );

    await pumpEventQueue();

    expect(metrics['video_init_started'],
        containsPair('network_tier', 'cellularSlow'));
    expect(metrics['video_init_started'],
        containsPair('quality_preference', 'data_saver'));
    expect(metrics['video_init_ready'], contains('duration_ms'));
    expect(metrics['video_init_ready'], containsPair('buffer_ahead_ms', 0));
    await session.dispose();
  });

  test('gagal sekali lalu sukses → retry TEPAT 1× lalu ready', () async {
    var attempts = 0;
    final session = VideoPlayerSession(
      url: 'https://cdn/play_720p.mp4',
      userQualityPreference: 'auto',
      debugDelay: noDelay,
      debugInitAttempt: (url) async {
        attempts++;
        if (attempts == 1) {
          throw Exception('network timeout');
        }
        // sukses percobaan ke-2.
      },
    );

    await pumpEventQueue();

    expect(attempts, 2, reason: 'satu percobaan awal + satu retry');
    expect(session.isInitialized, isTrue);
    expect(session.hasError, isFalse);
  });

  test('gagal terus → error final, budget retry TIDAK terlampaui (2 attempt)',
      () async {
    var attempts = 0;
    final session = VideoPlayerSession(
      url: 'https://cdn/play_720p.mp4',
      userQualityPreference: 'auto',
      debugDelay: noDelay,
      debugInitAttempt: (url) async {
        attempts++;
        throw Exception('network unreachable');
      },
    );

    await pumpEventQueue();

    expect(attempts, 2, reason: 'awal + tepat 1 retry, tidak lebih');
    expect(session.isInitialized, isFalse);
    expect(session.hasError, isTrue);
  });

  test('error permanen (format) → TIDAK di-retry (1 attempt saja)', () async {
    var attempts = 0;
    final session = VideoPlayerSession(
      url: 'https://cdn/play_720p.mp4',
      userQualityPreference: 'auto',
      debugDelay: noDelay,
      debugInitAttempt: (url) async {
        attempts++;
        throw Exception('unsupported format');
      },
    );

    await pumpEventQueue();

    expect(attempts, 1, reason: 'error permanen tak boleh memicu retry');
    expect(session.hasError, isTrue);
  });

  test('D4 — signed URL expired: refresh sekali, retry pakai URL segar',
      () async {
    var attempts = 0;
    var refreshCalls = 0;
    final seenUrls = <String>[];
    const signed = 'https://cdn/play_720p.mp4?token=abc&expires=123';
    const fresh = 'https://cdn/play_720p.mp4?token=NEW&expires=999';

    final session = VideoPlayerSession(
      url: signed,
      userQualityPreference: 'auto',
      debugDelay: noDelay,
      urlRefresher: () async {
        refreshCalls++;
        return fresh;
      },
      debugInitAttempt: (url) async {
        attempts++;
        seenUrls.add(url);
        if (attempts == 1) {
          throw Exception('403 forbidden'); // expired signature
        }
        // sukses dengan URL segar.
      },
    );

    await pumpEventQueue();

    expect(attempts, 2);
    expect(refreshCalls, 1, reason: 'refresh best-effort tepat sekali');
    expect(seenUrls.first, signed);
    expect(seenUrls.last, fresh,
        reason: 'retry memakai URL bertanda-tangan segar');
    expect(session.isInitialized, isTrue);
    expect(session.hasError, isFalse);
  });

  test('D4 — URL tak bertanda-tangan: refresher TIDAK dipanggil', () async {
    var refreshCalls = 0;
    var attempts = 0;
    final session = VideoPlayerSession(
      url: 'https://cdn/play_720p.mp4',
      userQualityPreference: 'auto',
      debugDelay: noDelay,
      urlRefresher: () async {
        refreshCalls++;
        return 'https://other';
      },
      debugInitAttempt: (url) async {
        attempts++;
        throw Exception('network');
      },
    );

    await pumpEventQueue();

    expect(refreshCalls, 0, reason: 'refresh hanya untuk URL signed');
    expect(attempts, 2);
    expect(session.hasError, isTrue);
  });

  test('retry() manual mereset budget → percobaan baru setelah error final',
      () async {
    var attempts = 0;
    var failUntilRetry = true;
    final session = VideoPlayerSession(
      url: 'https://cdn/play_720p.mp4',
      userQualityPreference: 'auto',
      debugDelay: noDelay,
      debugInitAttempt: (url) async {
        attempts++;
        if (failUntilRetry) throw Exception('network');
      },
    );

    await pumpEventQueue();
    expect(attempts, 2);
    expect(session.hasError, isTrue);

    // Manual "Coba lagi": izinkan sukses, budget di-reset.
    failUntilRetry = false;
    await session.retry();
    await pumpEventQueue();

    expect(attempts, 3, reason: 'retry manual = satu percobaan baru');
    expect(session.isInitialized, isTrue);
    expect(session.hasError, isFalse);
  });
}

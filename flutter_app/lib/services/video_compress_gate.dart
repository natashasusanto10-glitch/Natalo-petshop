import 'dart:async';

import 'package:video_compress/video_compress.dart';

/// Token satu job kompresi — supaya cancel HANYA membatalkan job miliknya
/// sendiri, bukan kompresi milik pemanggil lain (plugin-nya singleton
/// global).
class VideoCompressJob {
  bool _cancelled = false;
  bool get cancelled => _cancelled;
}

/// Runner injectable — production default memanggil plugin asli; unit test
/// menyuntik fake supaya tidak menyentuh platform channel.
typedef CompressRunner = Future<MediaInfo?> Function(
  String path, {
  VideoQuality quality,
  bool includeAudio,
  int? startTime,
  int? duration,
});

/// Satu-satunya pintu ke `VideoCompress.compressVideo`.
///
/// Kenapa perlu (bug nyata di production):
///  1. Plugin video_compress adalah singleton global. `compressVideo`
///     throw StateError kalau dipanggil saat masih ada proses jalan —
///     tanpa gate, layar trim & background upload store bisa tabrakan.
///  2. `compressVideo` internal TIDAK pakai try/finally — kalau proses
///     dibatalkan/throw di tengah, flag `isCompressing` nyangkut `true`
///     selamanya → SEMUA kompresi berikutnya langsung StateError
///     (gejala "swipe back → langsung error").
///  3. `cancelCompression()` global — dispose satu layar bisa membunuh
///     kompresi milik layar/store lain.
///
/// Solusi: antrikan job (serialisasi), cancel ber-scope via
/// [VideoCompressJob], dan reset paksa flag nyangkut.
class VideoCompressGate {
  VideoCompressGate({
    CompressRunner? compressRunner,
    Future<void> Function()? cancelRunner,
    bool Function()? isPluginBusy,
    void Function()? resetPluginFlag,
  })  : _compressRunner = compressRunner ?? _defaultCompress,
        _cancelRunner = cancelRunner ?? _defaultCancel,
        _isPluginBusy = isPluginBusy ?? _defaultIsBusy,
        _resetPluginFlag = resetPluginFlag ?? _defaultReset;

  static final VideoCompressGate instance = VideoCompressGate();

  final CompressRunner _compressRunner;
  final Future<void> Function() _cancelRunner;
  final bool Function() _isPluginBusy;
  final void Function() _resetPluginFlag;

  /// Antrian serialisasi — job berikutnya menunggu job sebelumnya.
  Future<void> _queue = Future<void>.value();

  /// Job yang sedang jalan di plugin. null = idle.
  VideoCompressJob? _active;

  static Future<MediaInfo?> _defaultCompress(
    String path, {
    VideoQuality quality = VideoQuality.Res1280x720Quality,
    bool includeAudio = true,
    int? startTime,
    int? duration,
  }) {
    return VideoCompress.compressVideo(
      path,
      quality: quality,
      deleteOrigin: false,
      includeAudio: includeAudio,
      startTime: startTime,
      duration: duration,
    );
  }

  static Future<void> _defaultCancel() => VideoCompress.cancelCompression();

  static bool _defaultIsBusy() => VideoCompress.isCompressing;

  static void _defaultReset() {
    // Flag internal plugin nyangkut karena compressVideo tidak pakai
    // try/finally. Protected member — pemakaian di sini disengaja.
    // ignore: invalid_use_of_protected_member
    VideoCompress.setProcessingStatus(false);
  }

  /// Kompres [path]. Antre otomatis kalau ada job lain jalan. Return null
  /// kalau [job] sudah dibatalkan (sebelum jalan) atau plugin return null
  /// (termasuk saat cancel di tengah proses).
  Future<MediaInfo?> compress(
    String path, {
    VideoQuality quality = VideoQuality.Res1280x720Quality,
    bool includeAudio = true,
    int? startTime,
    int? duration,
    VideoCompressJob? job,
  }) {
    final run = _queue.then((_) async {
      if (job != null && job.cancelled) return null;
      // Di titik ini tidak ada job aktif — kalau plugin masih klaim
      // sibuk, itu flag stale sisa cancel/throw sebelumnya. Reset.
      if (_active == null && _isPluginBusy()) _resetPluginFlag();
      _active = job ?? VideoCompressJob();
      try {
        return await _compressRunner(
          path,
          quality: quality,
          includeAudio: includeAudio,
          startTime: startTime,
          duration: duration,
        );
      } finally {
        _active = null;
        // Runner throw / cancel di tengah bisa ninggalin flag nyangkut.
        if (_isPluginBusy()) _resetPluginFlag();
      }
    });
    // Rantai antrian tidak boleh macet gara-gara job yang error.
    _queue = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  /// Batalkan [job]. Job aktif → stop plugin. Job antre → tandai batal
  /// (runner tidak akan dipanggil). Job selesai/asing → no-op. Job milik
  /// pemanggil lain TIDAK PERNAH ikut terbatalkan.
  Future<void> cancel(VideoCompressJob job) async {
    job._cancelled = true;
    if (identical(_active, job)) {
      await _cancelRunner();
    }
  }
}

final videoCompressGate = VideoCompressGate.instance;

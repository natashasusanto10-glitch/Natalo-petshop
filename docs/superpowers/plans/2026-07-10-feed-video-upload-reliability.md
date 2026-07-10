# Feed Video Upload Reliability (Fase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Membuat posting video feed andal — hilangkan dead-end error di Edit Video, tabrakan/state-nyangkut plugin kompresi (penyebab "swipe back → langsung error"), upload TUS tanpa retry, dan video pendek yang ter-upload tanpa kompres.

**Architecture:** Satu helper baru `VideoCompressGate` menjadi satu-satunya pintu ke plugin `video_compress` (serialisasi antrian + cancel ber-scope + reset flag nyangkut), diadopsi 3 call-site. Sisanya patch bedah kecil di layar trim (retry + PopScope), preview (`_next` tanpa copyWith palsu), dan `TusClient` (parameter retry).

**Tech Stack:** Flutter/Dart. Plugin: `video_compress 3.1.4`, `tus_client_dart 2.5.0`. Package name: `natalo_petshop_flutter`.

**Spec:** `docs/superpowers/specs/2026-07-10-feed-video-upload-reliability-design.md`

## Global Constraints

- Hanya keandalan pipeline — **DILARANG mengubah tampilan/layout/teks copy** kecuali dialog konfirmasi baru di Task 2 (Fix 5).
- Working dir Flutter: `flutter_app/` (semua perintah `flutter` dijalankan dari sini).
- Setiap task diakhiri `flutter analyze` bersih (0 issues) + test hijau + commit.
- Fakta plugin yang jadi dasar desain (sudah diverifikasi dari source pub cache):
  - `video_compress 3.1.4`: `compressVideo` **throw `StateError` kalau `isCompressing == true`**, dan `setProcessingStatus(false)` dipanggil **tanpa try/finally** → cancel/throw di tengah membuat flag nyangkut `true` selamanya. `VideoCompress` = getter singleton `IVideoCompress`; `setProcessingStatus` adalah `@protected` (perlu `// ignore: invalid_use_of_protected_member`).
  - `tus_client_dart 2.5.0`: `TusClient` punya param `retries` (default **0**), `retryScale` (`RetryScale.constant|lineal|exponential`), `retryInterval` (detik). `RetryScale` di-export dari root package.

---

### Task 1: `VideoCompressGate` + unit test

**Files:**
- Create: `flutter_app/lib/services/video_compress_gate.dart`
- Test: `flutter_app/test/video_compress_gate_test.dart`

**Interfaces:**
- Consumes: `package:video_compress/video_compress.dart` (`VideoCompress`, `MediaInfo`, `VideoQuality`).
- Produces (dipakai Task 2 & 3):
  - `class VideoCompressJob { bool get cancelled; }`
  - `class VideoCompressGate` dengan:
    - `Future<MediaInfo?> compress(String path, {VideoQuality quality = VideoQuality.Res1280x720Quality, bool includeAudio = true, int? startTime, int? duration, VideoCompressJob? job})`
    - `Future<void> cancel(VideoCompressJob job)`
  - global `final videoCompressGate = VideoCompressGate.instance;`

- [ ] **Step 1: Tulis failing test**

Buat `flutter_app/test/video_compress_gate_test.dart`:

```dart
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
```

- [ ] **Step 2: Jalankan test — pastikan gagal**

Run (dari `flutter_app/`): `flutter test test/video_compress_gate_test.dart`
Expected: FAIL — error compile "Target of URI doesn't exist ... video_compress_gate.dart".

- [ ] **Step 3: Implementasi gate**

Buat `flutter_app/lib/services/video_compress_gate.dart`:

```dart
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
```

- [ ] **Step 4: Jalankan test — pastikan lulus**

Run: `flutter test test/video_compress_gate_test.dart`
Expected: PASS — 6 tests passed.

- [ ] **Step 5: Analyze + commit**

```bash
cd flutter_app && flutter analyze
# Expected: No issues found!
git add flutter_app/lib/services/video_compress_gate.dart flutter_app/test/video_compress_gate_test.dart
git commit -m "feat(feed): VideoCompressGate — serialisasi + cancel ber-scope + reset flag nyangkut"
```

---

### Task 2: Layar Edit Video — adopsi gate + retry beneran (Fix 1) + swipe-back aman (Fix 5)

**Files:**
- Modify: `flutter_app/lib/screens/feed_video_upload_flow.dart` — kelas `_FeedVideoTrimScreenState` (± baris 382-701: `dispose`, `_exportTrim`, `build`)

**Interfaces:**
- Consumes (Task 1): `videoCompressGate.compress(...)`, `videoCompressGate.cancel(job)`, `VideoCompressJob`.
- Produces: tidak ada API baru — perubahan perilaku layar.

- [ ] **Step 1: Import gate + field job**

Di header file, tambah import (urut alfabet dengan import relatif lain):

```dart
import '../services/video_compress_gate.dart';
```

Di `_FeedVideoTrimScreenState`, tambah field setelah `Timer? _playbackGuard;`:

```dart
// Job kompresi milik layar ini — dipakai untuk cancel ber-scope di
// dispose (JANGAN cancelCompression global: bisa bunuh kompresi milik
// background upload store).
VideoCompressJob? _exportJob;
```

- [ ] **Step 2: dispose — cancel ber-scope, bukan global**

Ganti method `dispose()` yang lama:

```dart
@override
void dispose() {
  _playbackGuard?.cancel();
  _controller?.dispose();
  VideoCompress.cancelCompression();
  super.dispose();
}
```

menjadi:

```dart
@override
void dispose() {
  _playbackGuard?.cancel();
  _controller?.dispose();
  final job = _exportJob;
  if (job != null) {
    // Scoped cancel — hanya job milik layar ini. Kalau job sudah
    // selesai, ini no-op.
    unawaited(videoCompressGate.cancel(job));
  }
  super.dispose();
}
```

(`unawaited` sudah tersedia — file ini import `dart:async`.)

- [ ] **Step 3: `_exportTrim` — hapus dead-end + lewat gate**

Ganti bagian awal `_exportTrim()`:

```dart
Future<void> _exportTrim() async {
  if (_exporting || _error != null) return;
```

menjadi:

```dart
Future<void> _exportTrim() async {
  // `_error != null` sengaja TIDAK memblokir — saat error, tap Next =
  // retry. setState di bawah meng-clear error lama.
  if (_exporting) return;
```

Lalu ganti blok kompresi di dalam `try` (pemanggilan `VideoCompress.compressVideo`):

```dart
      final info = await VideoCompress.compressVideo(
        source,
        quality: VideoQuality.Res1280x720Quality,
        deleteOrigin: false,
        includeAudio: true,
        startTime: _range.start.floor(),
        duration: selectedSeconds,
      );
      final file = info?.file;
      if (file == null || !await file.exists()) {
```

menjadi (komentar 720p di atasnya dipertahankan):

```dart
      final job = VideoCompressJob();
      _exportJob = job;
      final info = await videoCompressGate.compress(
        source,
        quality: VideoQuality.Res1280x720Quality,
        includeAudio: true,
        startTime: _range.start.floor(),
        duration: selectedSeconds,
        job: job,
      );
      // Dibatalkan via back/dispose → layar sudah/akan ditutup, jangan
      // lempar error palsu.
      if (job.cancelled || !mounted) return;
      final file = info?.file;
      if (file == null || !await file.exists()) {
```

- [ ] **Step 4: Tombol Next — aktif saat error (retry)**

Di `build()` `_FeedVideoTrimScreenState`, ganti:

```dart
      trailing: _RoundNextButton(
        busy: _exporting,
        onTap: _loading || _exporting || _error != null ? null : _exportTrim,
      ),
```

menjadi:

```dart
      trailing: _RoundNextButton(
        busy: _exporting,
        // Saat _error terisi tombol TETAP aktif — tap = retry (dulu
        // disabled → dead-end: pesan "Coba lagi" tanpa cara retry).
        onTap: _loading || _exporting ? null : _exportTrim,
      ),
```

- [ ] **Step 5: PopScope + dialog konfirmasi saat exporting**

Tambah method di `_FeedVideoTrimScreenState` (setelah `_exportTrim`):

```dart
  /// Konfirmasi keluar saat kompresi jalan. Pola sama dengan
  /// `_confirmExit` di FeedUploadProgressScreen.
  Future<bool> _confirmCancelExport() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Batalkan proses video?'),
        content: const Text(
          'Video sedang diproses. Jika keluar sekarang, kamu perlu memproses ulang dari awal.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Lanjutkan'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
    return leave == true;
  }
```

Bungkus return `build()` dengan `PopScope` dan arahkan tombol back header lewat `maybePop` (supaya swipe-back dan tombol back share satu jalur):

```dart
    return PopScope(
      // Saat tidak exporting, back bebas seperti biasa. Saat exporting,
      // intercept → konfirmasi (cancel bersih terjadi di dispose via
      // gate scoped-cancel).
      canPop: !_exporting,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmCancelExport() && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: _DarkUploadScaffold(
        title: 'Edit Video',
        leading: Icons.arrow_back_rounded,
        onLeading: () => Navigator.maybePop(context),
        ...
      ),
    );
```

(Sisa isi `_DarkUploadScaffold` tidak berubah — hanya `onLeading` yang tadinya `() => Navigator.pop(context)` jadi `maybePop`, dan penambahan wrapper + indentasi.)

- [ ] **Step 6: Analyze + test + commit**

```bash
cd flutter_app && flutter analyze
# Expected: No issues found!
flutter test
# Expected: semua test pass (termasuk gate test Task 1)
git add flutter_app/lib/screens/feed_video_upload_flow.dart
git commit -m "fix(feed): Edit Video — retry beneran saat error + swipe-back aman via PopScope + kompresi lewat gate"
```

---

### Task 3: Adopsi gate di background store + layar progress legacy

**Files:**
- Modify: `flutter_app/lib/state/feed_upload_store.dart` — `_runVideoUpload` step 0 (± baris 259)
- Modify: `flutter_app/lib/screens/feed_video_upload_flow.dart` — `_FeedUploadProgressScreenState._startUpload` (± baris 1003)

**Interfaces:**
- Consumes (Task 1): `videoCompressGate.compress(path, quality:, includeAudio:)`.
- Produces: tidak ada API baru.

- [ ] **Step 1: Store — kompres lewat gate**

Di `feed_upload_store.dart` tambah import:

```dart
import '../services/video_compress_gate.dart';
```

Ganti pemanggilan di `_runVideoUpload` step 0:

```dart
          final info = await VideoCompress.compressVideo(
            originalPath,
            quality: VideoQuality.Res1280x720Quality,
            deleteOrigin: false,
            includeAudio: true,
          );
```

menjadi:

```dart
          // Lewat gate: kalau layar trim sedang kompres, job ini antre
          // (bukan StateError), dan dispose layar lain tidak bisa
          // membunuh job ini.
          final info = await videoCompressGate.compress(
            originalPath,
            quality: VideoQuality.Res1280x720Quality,
            includeAudio: true,
          );
```

Import `package:video_compress/video_compress.dart` DIPERTAHANKAN (masih dipakai `VideoQuality` + `VideoThumbnail`… catatan: `VideoThumbnail` dari package lain — cek: kalau setelah edit `flutter analyze` menandai import video_compress unused, berarti `VideoQuality` satu-satunya pemakai dan import tetap perlu untuk itu; biarkan).

- [ ] **Step 2: Layar progress legacy — kompres lewat gate**

Di `feed_video_upload_flow.dart`, `_FeedUploadProgressScreenState._startUpload`, ganti:

```dart
          final info = await VideoCompress.compressVideo(
            originalPath,
            quality: VideoQuality.Res1280x720Quality,
            deleteOrigin: false,
            includeAudio: true,
          );
```

menjadi:

```dart
          final info = await videoCompressGate.compress(
            originalPath,
            quality: VideoQuality.Res1280x720Quality,
            includeAudio: true,
          );
```

- [ ] **Step 3: Analyze + test + commit**

```bash
cd flutter_app && flutter analyze
# Expected: No issues found! (kalau ada warning unused import
# video_compress di salah satu file, hapus import itu lalu ulangi)
flutter test
# Expected: semua pass
git add flutter_app/lib/state/feed_upload_store.dart flutter_app/lib/screens/feed_video_upload_flow.dart
git commit -m "fix(feed): semua kompresi video lewat VideoCompressGate (store + layar progress legacy)"
```

---

### Task 4: TUS auto-retry (Fix 3)

**Files:**
- Modify: `flutter_app/lib/services/bunny_upload_service.dart` — `uploadViaTus` (± baris 152-156)

**Interfaces:**
- Consumes: `RetryScale` (sudah ter-export dari `package:tus_client_dart/tus_client_dart.dart` yang sudah di-import file ini).
- Produces: tidak ada API baru — perilaku `uploadViaTus` jadi auto-retry.

- [ ] **Step 1: Tambah parameter retry pada TusClient**

Ganti:

```dart
    final client = TusClient(
      XFile(videoFile.path),
      store: TusFileStore(uploadsDir),
      maxChunkSize: chunkSize,
    );
```

menjadi:

```dart
    // Auto-retry per-chunk: gangguan jaringan sesaat tidak lagi
    // menggagalkan seluruh upload. Backoff exponential: jeda 2s → 4s →
    // 8s. Kombinasi dengan TusFileStore di atas = resume dari byte
    // terakhir, bukan dari 0%. Gagal permanen hanya setelah 3 percobaan
    // berturut-turut gagal.
    final client = TusClient(
      XFile(videoFile.path),
      store: TusFileStore(uploadsDir),
      maxChunkSize: chunkSize,
      retries: 3,
      retryScale: RetryScale.exponential,
      retryInterval: 2,
    );
```

- [ ] **Step 2: Analyze + test + commit**

```bash
cd flutter_app && flutter analyze
# Expected: No issues found!
flutter test
# Expected: semua pass
git add flutter_app/lib/services/bunny_upload_service.dart
git commit -m "fix(feed): TUS upload auto-retry 3x exponential backoff — resume dari byte terakhir"
```

---

### Task 5: Video pendek kembali dikompres (Fix 4)

**Files:**
- Modify: `flutter_app/lib/screens/feed_video_upload_flow.dart` — `_FeedVideoPreviewScreenState._next()` (± baris 262-289)

**Interfaces:**
- Consumes: `FeedCreatePostDraft` getter (sudah diverifikasi): `finalVideoPath => trimmedVideoPath ?? localVideoPath`, `finalDuration => trimmedDuration ?? originalDuration`.
- Produces: draft yang masuk `FeedNewPostScreen` dari jalur preview kini punya `trimmedVideoPath == null` → `FeedUploadStore._runVideoUpload` step 0 menjalankan kompresi 720p.

- [ ] **Step 1: Hapus copyWith palsu**

Ganti bagian akhir `_next()`:

```dart
    await _controller?.pause();
    if (!mounted) return;
    final draft = widget.draft.copyWith(
      trimmedVideoPath: widget.draft.localVideoPath,
      trimmedDuration: widget.draft.originalDuration,
    );
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FeedNewPostScreen(
          draft: NewPostMediaDraft.video(draft),
        ),
      ),
    );
```

menjadi:

```dart
    await _controller?.pause();
    if (!mounted) return;
    // JANGAN isi trimmedVideoPath dengan path mentah: FeedUploadStore
    // memakai `trimmedVideoPath != null` sebagai penanda "sudah
    // terkompres 720p" untuk skip kompresi. Mengisinya di sini membuat
    // video pendek (≤60s) ter-upload MENTAH — file besar, upload lambat,
    // gampang gagal. finalVideoPath/finalDuration otomatis fallback ke
    // localVideoPath/originalDuration.
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FeedNewPostScreen(
          draft: NewPostMediaDraft.video(widget.draft),
        ),
      ),
    );
```

- [ ] **Step 2: Analyze + test + commit**

```bash
cd flutter_app && flutter analyze
# Expected: No issues found!
flutter test
# Expected: semua pass
git add flutter_app/lib/screens/feed_video_upload_flow.dart
git commit -m "fix(feed): video pendek ikut kompresi 720p — stop memalsukan trimmedVideoPath di preview Next"
```

---

### Task 6: Regression penuh + checklist device-verify

**Files:**
- Tidak ada perubahan kode — verifikasi.

- [ ] **Step 1: Full suite**

```bash
cd flutter_app && flutter analyze && flutter test
# Expected: No issues found! + semua test pass
```

- [ ] **Step 2: Laporkan checklist device-verify ke user**

Plugin kompresi & TUS adalah native — kepastian akhir butuh HP fisik. Sampaikan checklist ini apa adanya (JANGAN klaim fix terverifikasi sebelum ini dijalankan user):

1. Video WhatsApp **>60 detik** → masuk Edit Video → Next → sukses proses & upload.
2. Saat proses jalan di Edit Video → **swipe back** → muncul dialog "Batalkan proses video?" → pilih Keluar → balik lagi, ulangi trim → **tidak** langsung error.
3. Video WhatsApp **≤60 detik** → Next dari Preview → upload → cek log debug `[feed-upload-store] compressed:` muncul (bukti kompresi jalan).
4. Di tengah upload (relay card di Beranda) → matikan WiFi 5 detik → nyalakan → upload lanjut sampai selesai (bukti TUS retry + resume).
5. Setelah 1 kali gagal kompres (kalau kejadian) → tap Next lagi di Edit Video → proses jalan ulang (bukti retry beneran).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../models/feed_create_post_draft.dart';
import '../services/api_client.dart';
import '../services/app_analytics.dart';
import '../services/video_compress_gate.dart';
import '../services/bunny_upload_service.dart';
import '../services/feed_photo_service.dart';
import '../services/feed_service.dart';
import '../utils/haptics.dart';

/// Status upload feed post — drive UI relay card di Beranda.
enum FeedUploadStatus {
  idle,
  preparing,
  uploading,
  processing,
  success,
  waitingReview,
  failed,
  cancelled,

  /// Ada task inflight tersimpan dari sesi sebelumnya (app di-kill saat
  /// preparing/uploading) — FeedUploadBar tawarkan "Lanjutkan" (Fase 2C-4).
  resumable,
}

/// Tipe upload — photo carousel atau video. Logic upload jauh berbeda
/// (photo lewat /api/feed/upload-photo + bulk insert FeedMedia, video
/// lewat Bunny TUS). Discriminator pakai enum, bukan inheritance.
enum FeedUploadKind { photo, video }

/// In-flight upload task — di-track di FeedUploadStore. Immutable;
/// gunakan copyWith untuk update progress/status.
class FeedUploadTask {
  /// Unique ID local — supaya UI bisa pakai sebagai widget key
  /// (ValueKey) saat AnimatedSwitcher transition antar state.
  final String localId;
  final FeedUploadKind kind;

  // ── Photo-only fields ──
  /// File list untuk PHOTO_CAROUSEL kind. Empty untuk video.
  final List<File> photoFiles;

  // ── Video-only fields ──
  /// Draft video lengkap (path, duration, thumbnail, dll).
  final FeedCreatePostDraft? videoDraft;

  // ── Shared ──
  final String caption;
  final List<String> productIds;

  // ── Mutable status ──
  final FeedUploadStatus status;
  final double progress; // 0.0 - 1.0
  final String? errorMessage;
  final DateTime createdAt;

  /// Real photo counts dari onProgress callback (bukan derivasi banded
  /// progress) — supaya counter "Foto n/total" akurat & bisa n/n di akhir.
  final int? photosDone;
  final int? photosTotal;

  const FeedUploadTask({
    required this.localId,
    required this.kind,
    this.photoFiles = const [],
    this.videoDraft,
    this.caption = '',
    this.productIds = const [],
    required this.status,
    this.progress = 0,
    this.errorMessage,
    required this.createdAt,
    this.photosDone,
    this.photosTotal,
  });

  FeedUploadTask copyWith({
    FeedUploadStatus? status,
    double? progress,
    String? errorMessage,
    int? photosDone,
    int? photosTotal,
  }) {
    return FeedUploadTask(
      localId: localId,
      kind: kind,
      photoFiles: photoFiles,
      videoDraft: videoDraft,
      caption: caption,
      productIds: productIds,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      errorMessage: errorMessage,
      createdAt: createdAt,
      photosDone: photosDone ?? this.photosDone,
      photosTotal: photosTotal ?? this.photosTotal,
    );
  }
}

/// Singleton store — match pattern `memberStore` / `cartStore`. Hold
/// 1 active upload task (single-flight). Subscribe via AnimatedBuilder
/// atau ValueListenableBuilder di widget.
class FeedUploadStore extends ChangeNotifier {
  FeedUploadStore._();
  static final FeedUploadStore instance = FeedUploadStore._();

  FeedUploadTask? _task;
  FeedUploadTask? get activeTask => _task;
  bool get hasActiveUpload => _task != null;

  /// Injectable untuk unit test — default gate global.
  @visibleForTesting
  VideoCompressGate gate = videoCompressGate;

  /// Injectable clock untuk unit test — dipakai timestamp `savedAtMs` saat
  /// persist task inflight (bukan lagi untuk cek window `authExpire`; video
  /// resume sekarang selalu re-provision, lihat komentar `_runVideoUpload`).
  @visibleForTesting
  int Function() nowMs = () => DateTime.now().millisecondsSinceEpoch;

  /// Key SharedPreferences untuk persist task inflight (Fase 2C-4) — bila
  /// app di-kill saat preparing/uploading, task ini di-restore cold start
  /// dan ditawarkan sebagai "Lanjutkan".
  static const _pendingKey = 'natalo-feed-upload-inflight';

  /// Provision Bunny (postId + TUS creds) yang ikut ter-restore dari
  /// persist — HANYA untuk diagnostik/persist, TIDAK dipakai untuk skip
  /// provisionUpload. Resume video SELALU re-provision VideoId baru (lihat
  /// komentar `_runVideoUpload` Step 3) karena file selalu di-recompress
  /// ulang, jadi melanjutkan byte parsial di VideoId lama berisiko splice
  /// byte → video korup.
  BunnyUploadProvision? _pendingProvision;

  /// Guard supaya `checkForResumableUpload` hanya efektif sekali per
  /// proses (dipanggil dari HomeScreen post-frame, bisa re-run tiap kali
  /// HomeScreen instance baru dibuat — tab switch dll).
  bool _resumeChecked = false;

  /// Auto-dismiss timer untuk success / waiting-review state. Disimpan
  /// supaya bisa di-cancel kalau task baru di-start sebelum dismiss.
  Timer? _autoDismissTimer;

  /// Lock supaya double-submit tidak start 2 upload concurrent (race).
  bool _uploading = false;
  bool get isUploading => _uploading;

  /// Flag batal — dicek setelah tiap await besar di _run*Upload. Best
  /// effort: TUS chunk yang sudah terkirim tidak di-abort (lihat
  /// cancelActive doc).
  bool _cancelRequested = false;

  /// Job kompresi aktif milik upload video yang sedang jalan — dipakai
  /// cancelActive() untuk stop kompresi in-flight via gate (scoped,
  /// tidak membunuh kompresi milik layar lain).
  VideoCompressJob? _activeCompressJob;

  /// Setter test-only — assign task langsung + notify, tanpa lewat
  /// pipeline upload asli. Dipakai widget test FeedUploadBar untuk drive
  /// tiap status tanpa File/network nyata.
  @visibleForTesting
  void debugSetTask(FeedUploadTask? task) {
    _task = task;
    notifyListeners();
  }

  /// Batal upload aktif — BEST EFFORT, bukan garansi hard-abort.
  ///
  /// Semantik per titik:
  /// - Kompresi in-flight: dibatalkan via `gate.cancel(job)` (scoped ke
  ///   job upload ini saja).
  /// - Sebelum provision Bunny / sebelum finalize: flag dicek, upload
  ///   berhenti bersih, TIDAK create/finalize post.
  /// - TUS upload in-flight (chunk sedang jalan ke Bunny): TIDAK di-abort
  ///   di tengah kirim chunk — library TUS tidak expose abort socket yang
  ///   aman. Flag dicek SETELAH chunk selesai (baris progress callback
  ///   tidak langsung stop, tapi step berikutnya sebelum provision/finalize
  ///   akan berhenti). Placeholder Bunny yang telanjur ter-provision jadi
  ///   orphan server-side — sama seperti kasus kegagalan existing (tidak
  ///   ada cleanup otomatis di sisi client untuk kasus ini).
  Future<void> cancelActive() async {
    if (!_uploading || _task == null) return;
    _cancelRequested = true;
    final job = _activeCompressJob;
    if (job != null) {
      await gate.cancel(job);
    }
  }

  /// Cek flag batal — kalau di-set, transisi task ke `cancelled` + jadwalkan
  /// clear task setelah 400ms, return true (caller harus `return` segera,
  /// `_uploading=false` sudah ditangani `finally` existing di pemanggil).
  bool _checkCancel() {
    if (!_cancelRequested) return false;
    _update(status: FeedUploadStatus.cancelled);
    Timer(const Duration(milliseconds: 400), () {
      if (_task?.status == FeedUploadStatus.cancelled) {
        _task = null;
        notifyListeners();
      }
    });
    return true;
  }

  /// Start upload PHOTO_CAROUSEL — fire-and-forget. UI relay card auto
  /// update via notifyListeners. Returns immediately (Future<void>
  /// reflect "task accepted", bukan "upload selesai").
  Future<void> startPhotoUpload({
    required List<File> files,
    required String caption,
    List<String> productIds = const [],
    String? localId,
  }) async {
    if (_uploading) return;
    if (files.isEmpty || files.length > 8) {
      _task = FeedUploadTask(
        localId: localId ?? _genId(),
        kind: FeedUploadKind.photo,
        caption: caption,
        productIds: productIds,
        photoFiles: files,
        status: FeedUploadStatus.failed,
        errorMessage: 'Pilih 1-8 foto untuk posting.',
        createdAt: DateTime.now(),
      );
      notifyListeners();
      return;
    }

    _cancelAutoDismiss();
    _cancelRequested = false;
    _task = FeedUploadTask(
      localId: localId ?? _genId(),
      kind: FeedUploadKind.photo,
      caption: caption,
      productIds: productIds,
      photoFiles: files,
      status: FeedUploadStatus.preparing,
      createdAt: DateTime.now(),
    );
    _uploading = true;
    notifyListeners();

    // Kick off async — don't await; let caller return immediately.
    unawaited(_runPhotoUpload());
  }

  Future<void> _runPhotoUpload() async {
    final task = _task;
    if (task == null) return;
    // Persist inflight payload — kalau app di-kill saat upload foto
    // berjalan, cold-start berikutnya bisa tawarkan "Lanjutkan" (murah:
    // foto tinggal restart dari awal, tidak perlu resume byte).
    await _persistPending(task);
    try {
      _update(status: FeedUploadStatus.uploading, progress: 0.05);
      // Upload semua foto dengan progress callback per-foto.
      final total = task.photoFiles.length;
      final uploaded = await feedPhotoService.uploadAllPhotos(
        task.photoFiles,
        onProgress: (done, t) {
          // Map per-foto done ke 0.05-0.85 (reserve 0.85-0.95 untuk
          // create post step, 0.95-1.0 untuk processing).
          final ratio = total == 0 ? 0.0 : done / total;
          _update(
            status: FeedUploadStatus.uploading,
            progress: (0.05 + (0.80 * ratio)).clamp(0.05, 0.85),
            photosDone: done,
            photosTotal: t,
          );
        },
      );

      // ── Checkpoint batal — setelah upload foto, SEBELUM create post ──
      if (_checkCancel()) return;

      _update(status: FeedUploadStatus.processing, progress: 0.92);
      // Pattern match video upload (line 322-326): title = short version
      // (truncated 80 char untuk admin list view), description = full
      // caption text yang dipakai untuk render di comment drawer +
      // detail screen. Sebelumnya cuma title yang di-pass → description
      // null → caption tidak muncul di comment sheet untuk photo post.
      final caption = task.caption.trim();
      final result = await feedPhotoService.createPhotoPost(
        images: uploaded,
        title: caption.isEmpty
            ? 'Postingan baru'
            : caption.substring(0, math.min(80, caption.length)),
        description: caption.isEmpty ? null : caption,
        productIds: task.productIds,
      );

      AppHaptics.success();
      // Customer post selalu PENDING_REVIEW. Status server konfirmasi
      // via result.status — kalau "ACTIVE" (admin override), tampilkan
      // success. Default → waiting review.
      final waitingReview = result.status != 'ACTIVE';
      _update(
        status: waitingReview
            ? FeedUploadStatus.waitingReview
            : FeedUploadStatus.success,
        progress: 1,
      );
      unawaited(AppAnalytics.logEvent('feed_post_upload_success', {
        'type': task.photoFiles.length > 1 ? 'carousel' : 'photo',
      }));
      _scheduleAutoDismiss();
    } catch (error) {
      AppHaptics.warning();
      _update(
        status: FeedUploadStatus.failed,
        errorMessage: _friendlyError(error),
      );
      final reasonStr = error.toString();
      unawaited(AppAnalytics.logEvent('feed_post_upload_failed', {
        'type': task.photoFiles.length > 1 ? 'carousel' : 'photo',
        'reason': reasonStr.substring(0, math.min(90, reasonStr.length)),
      }));
    } finally {
      _uploading = false;
      await _clearPendingIfTerminal();
    }
  }

  /// Start upload VIDEO. Same fire-and-forget pattern dengan photo.
  /// Internal: compress (kalau perlu) → thumbnail upload → Bunny provision
  /// → TUS upload. Logic mirror `FeedUploadProgressScreen._startUpload()`.
  Future<void> startVideoUpload({
    required FeedCreatePostDraft draft,
  }) async {
    if (_uploading) return;
    _cancelAutoDismiss();
    _cancelRequested = false;
    _task = FeedUploadTask(
      localId: _genId(),
      kind: FeedUploadKind.video,
      caption: draft.caption,
      productIds: draft.taggedProductIds,
      videoDraft: draft,
      status: FeedUploadStatus.preparing,
      createdAt: DateTime.now(),
    );
    _uploading = true;
    notifyListeners();

    unawaited(_runVideoUpload());
  }

  Future<void> _runVideoUpload({BunnyUploadProvision? resumeProvision}) async {
    final task = _task;
    final draft = task?.videoDraft;
    if (task == null || draft == null) return;

    // Persist inflight payload — ditulis SAAT MULAI supaya app-kill di
    // tengah compress/upload masih bisa di-resume cold start berikutnya
    // (Fase 2C-4). Di-update lagi setelah provision Bunny sukses (postId +
    // TUS creds baru masuk).
    await _persistPending(task, provision: resumeProvision);

    try {
      final originalPath = draft.finalVideoPath;
      if (originalPath == null) {
        throw const FeedPhotoUploadException(
          'Video tidak tersedia. Kembali ke detail postingan.',
        );
      }

      // ── Step 0 — Normalize video max 1080p (Approach B: ber-range) ──
      // CRITICAL: missed di first version background upload (v1.0.86) →
      // user upload original video (50-300MB iPhone 4K) → Bunny encode
      // lambat → URL .mp4 404 sampai encode selesai. Trip compress dulu:
      // - Skip kalau sudah ada trimmedVideoPath (= sudah hasil
      //   VideoCompress di trim screen).
      // - Skip kalau compress gagal (fallback ke original) — TAPI HANYA
      //   kalau tidak ada range trim (lihat catch di bawah).
      // Match logic FeedUploadProgressScreen._startUpload() yang lama.
      _update(status: FeedUploadStatus.preparing, progress: 0.05);
      final videoPath = await prepareVideoPathForUpload(draft, originalPath);

      // ── Checkpoint batal — setelah compress ──
      if (_checkCancel()) return;

      // ── Step 1 — Generate thumbnail kalau belum ada ──
      // Sebelumnya skip generate, hanya pakai existing thumbnailPath.
      // Tapi kalau draft.thumbnailPath null (mis. user submit dari path
      // yang lewat tanpa cover picker), upload tidak punya thumbnail.
      // Cover: kalau video di-trim (trimStart != null), thumbnail dari
      // picker = frame 0 video ASLI (sebelum dipotong) → WAJIB regenerate
      // dari `videoPath` (hasil kompres yang sudah terpotong, timeline
      // mulai 0). timeMs selalu 500 karena videoPath sudah dimulai dari
      // titik yang benar.
      // Kecuali user sudah pilih sampul sendiri (layar Ubah Sampul,
      // `userPickedCover`) — cover itu sudah diekstrak dari rentang trim
      // yang benar, JANGAN ditimpa regenerate frame 0.
      String? thumbPath = draft.thumbnailPath;
      final coverFromUntrimmed =
          draft.trimStart != null && !draft.userPickedCover;
      if (coverFromUntrimmed ||
          thumbPath == null ||
          !File(thumbPath).existsSync()) {
        try {
          thumbPath = await VideoThumbnail.thumbnailFile(
            video: videoPath,
            imageFormat: ImageFormat.JPEG,
            maxWidth: 720,
            timeMs: 500,
            quality: 82,
          );
        } catch (_) {
          // Thumbnail generation fail → Bunny auto-generate dari frame.
        }
      }

      // ── Step 2 — Upload thumbnail ke feed-thumbnail bucket ──
      String? thumbnailUrl;
      if (thumbPath != null && File(thumbPath).existsSync()) {
        _update(status: FeedUploadStatus.uploading, progress: 0.1);
        try {
          final res = await feedService.uploadFeedThumbnail(
            filePath: thumbPath,
            filename: 'thumbnail.jpg',
            contentType: 'image/jpeg',
          );
          thumbnailUrl = res.url.isEmpty ? null : res.url;
        } catch (_) {
          // Thumbnail fail tidak block — server-side Bunny akan
          // auto-generate thumbnail dari frame video.
        }
      }

      // ── Checkpoint batal — setelah thumbnail, SEBELUM provision ──
      if (_checkCancel()) return;

      // ── Step 3 — Bunny provision (create FeedPost placeholder + dapat
      // TUS credentials). ──
      _update(status: FeedUploadStatus.uploading, progress: 0.2);
      final bunnyService = BunnyUploadService(
        apiClient: apiClient,
        feedService: feedService,
      );
      final caption = task.caption.trim();
      // Resume video SELALU re-provision (VideoId baru) — file di-recompress
      // ulang tiap resume (trimmedVideoPath sengaja tidak dipersist), jadi
      // tidak aman melanjutkan byte parsial di VideoId lama (risiko splice
      // byte lama+baru → video korup di Bunny; TUS fingerprint cuma path
      // file, tidak deteksi konten berubah). Konsekuensi: row FeedPost +
      // Bunny guid sesi lama jadi orphan (keterbatasan terdokumentasi, tidak
      // ada cleanup server di fase ini). Resume di sini = transfer diulang
      // otomatis dari 0% dengan state edit/draft tetap tersimpan, BUKAN
      // lanjut-dari-byte-terakhir.
      final provision = await bunnyService.provisionUpload(
        title: caption.isEmpty
            ? 'Postingan baru'
            : caption.substring(0, math.min(80, caption.length)),
        description: caption.isEmpty ? null : caption,
        videoDurationSec: draft.finalDuration?.inSeconds,
        productIds: task.productIds,
        thumbnailUrl: thumbnailUrl,
      );
      // Update persist dengan provision final (postId/tus creds) supaya
      // kalau app di-kill SETELAH provision tapi SEBELUM TUS selesai,
      // resume berikutnya tidak perlu re-provision lagi.
      await _persistPending(task, provision: provision);

      // Step 4 — TUS upload ke Bunny. Pakai videoPath yang sudah ter-compress
      // di Step 0 (kalau berhasil) atau original (kalau compress gagal /
      // skipped karena trimmedVideoPath sudah ada). videoPath di-validate
      // exists di Step 0 — defensive re-check di sini juga.
      if (!File(videoPath).existsSync()) {
        throw const FeedPhotoUploadException('File video tidak ditemukan.');
      }
      final tusCreds = provision.tus;
      if (tusCreds == null) {
        // Fallback ke single PUT (legacy).
        await bunnyService.uploadViaPut(
          videoFile: File(videoPath),
          uploadUrl: provision.uploadUrl ?? '',
          headers: provision.uploadHeaders,
          onProgress: (percent, _, __) {
            _update(
              status: FeedUploadStatus.uploading,
              progress: (0.2 + (0.7 * percent / 100)).clamp(0.2, 0.9),
            );
          },
        );
      } else {
        await bunnyService.uploadViaTus(
          videoFile: File(videoPath),
          credentials: tusCreds,
          filetype: 'video/mp4',
          title: caption.isEmpty ? 'feed-video' : caption,
          onProgress: (percent, _, __) {
            _update(
              status: FeedUploadStatus.uploading,
              progress: (0.2 + (0.7 * percent / 100)).clamp(0.2, 0.9),
            );
          },
        );
      }

      // ── Checkpoint batal — TUS chunks sudah terkirim (tidak di-abort
      // di tengah, lihat cancelActive doc), SEBELUM finalize ──
      if (_checkCancel()) return;

      // Step 4 — Server akan transcode via Bunny webhook async. Tampilkan
      // processing state. Customer post selalu PENDING_REVIEW.
      _update(status: FeedUploadStatus.processing, progress: 0.95);
      await bunnyService.finalize(provision.postId);

      AppHaptics.success();
      _update(status: FeedUploadStatus.waitingReview, progress: 1);
      unawaited(
        AppAnalytics.logEvent('feed_post_upload_success', {'type': 'video'}),
      );
      _scheduleAutoDismiss();
    } catch (error) {
      AppHaptics.warning();
      _update(
        status: FeedUploadStatus.failed,
        errorMessage: _friendlyError(error),
      );
      final reasonStr = error.toString();
      unawaited(AppAnalytics.logEvent('feed_post_upload_failed', {
        'type': 'video',
        'reason': reasonStr.substring(0, math.min(90, reasonStr.length)),
      }));
    } finally {
      _uploading = false;
      await _clearPendingIfTerminal();
    }
  }

  @visibleForTesting
  Future<String> prepareVideoPathForUpload(
    FeedCreatePostDraft draft,
    String originalPath,
  ) async {
    if (draft.trimmedVideoPath != null) return originalPath;

    final range = compressRangeOf(draft);
    final hasTrim = range.startTimeSec != null || range.durationSec != null;

    // Opsi A (kompres 4G): SELALU re-encode via preset Res1920x1080Quality —
    // termasuk sumber yang sudah <=1080p — supaya bitrate rekaman HP yang
    // tinggi (17-25 Mbps) dipangkas ke bitrate preset tanpa menurunkan
    // resolusi. Payload jauh lebih kecil = upload 4G jauh lebih andal.
    // Sebelumnya sumber <=1080p di-skip → di-upload mentah (50-150MB) → sering
    // timeout di seluler. Guard `_compressedIsLarger` di bawah tetap pakai
    // original kalau re-encode ternyata TIDAK mengecilkan (sumber sudah hemat).
    final job = VideoCompressJob();
    _activeCompressJob = job;
    try {
      final info = await gate.compress(
        originalPath,
        quality: VideoQuality.Res1920x1080Quality,
        includeAudio: true,
        startTime: range.startTimeSec,
        duration: range.durationSec,
        job: job,
      );
      final compressed = info?.file;
      if (compressed != null && await compressed.exists()) {
        if (!hasTrim && await _compressedIsLarger(compressed, originalPath)) {
          await _deleteTempCompressed(compressed, originalPath);
          return originalPath;
        }
        if (kDebugMode) {
          final origSize = await File(originalPath).length();
          final newSize = await compressed.length();
          debugPrint(
            '[feed-upload-store] compressed: ${origSize ~/ 1024}KB → '
            '${newSize ~/ 1024}KB '
            '(${(100 - newSize / origSize * 100).round()}% reduction)',
          );
        }
        return compressed.path;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[feed-upload-store] compress failed: $e');
      }
      if (hasTrim && !_cancelRequested) rethrow;
    } finally {
      _activeCompressJob = null;
    }
    return originalPath;
  }


  Future<bool> _compressedIsLarger(File compressed, String originalPath) async {
    try {
      final originalSize = await File(originalPath).length();
      final compressedSize = await compressed.length();
      return compressedSize > originalSize;
    } catch (_) {
      return false;
    }
  }

  Future<void> _deleteTempCompressed(
      File compressed, String originalPath) async {
    try {
      if (compressed.path != originalPath && await compressed.exists()) {
        await compressed.delete();
      }
    } catch (_) {}
  }

  /// Retry upload — restart from beginning dengan data yang sama.
  /// Dipanggil saat user tap "Coba Lagi" di failed relay card.
  Future<void> retry() async {
    final task = _task;
    if (task == null || _uploading) return;
    if (task.kind == FeedUploadKind.photo) {
      final files = task.photoFiles;
      final caption = task.caption;
      final productIds = task.productIds;
      _task = null;
      notifyListeners();
      await startPhotoUpload(
        files: files,
        caption: caption,
        productIds: productIds,
      );
    } else {
      final draft = task.videoDraft;
      if (draft == null) return;
      _task = null;
      notifyListeners();
      await startVideoUpload(draft: draft);
    }
  }

  /// Dismiss failed task — user explicit close. Sukses task auto-dismiss
  /// via timer (3 detik).
  void dismissFailed() {
    if (_task?.status == FeedUploadStatus.failed) {
      _task = null;
      _cancelAutoDismiss();
      notifyListeners();
    }
  }

  /// Force dismiss any task (cleanup saat logout).
  void clear() {
    _task = null;
    _uploading = false;
    _pendingProvision = null;
    _resumeChecked = false;
    _cancelAutoDismiss();
    notifyListeners();
  }

  // ──────────── Resume upload setelah app ditutup (Fase 2C-4) ────────────

  /// Dipanggil sekali saat cold start (HomeScreen post-frame, lihat
  /// `home_screen.dart` initState). Bila ada task inflight tersimpan
  /// (app di-kill saat preparing/uploading) DAN file media lokalnya masih
  /// ada → set `_task` ke status `resumable` supaya `FeedUploadBar`
  /// menawarkan "Lanjutkan". Kalau file sudah hilang (mis. cache OS
  /// dibersihkan), persist dihapus tanpa membuat task.
  ///
  /// Idempotent per proses — guard `_resumeChecked` supaya panggilan
  /// berulang (HomeScreen instance baru via tab switch) tidak berulang
  /// baca disk. Reset via `clear()` (logout).
  Future<void> checkForResumableUpload() async {
    if (_resumeChecked) return;
    _resumeChecked = true;
    // Jangan timpa task yang sedang aktif di foreground (upload jalan
    // atau relay card lain sedang ditampilkan).
    if (_uploading || _task != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_pendingKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        await _clearPending();
        return;
      }
      final json = Map<String, dynamic>.from(decoded);
      final kind =
          json['kind'] == 'video' ? FeedUploadKind.video : FeedUploadKind.photo;
      final caption = json['caption']?.toString() ?? '';
      final productIds = ((json['productIds'] as List?) ?? const [])
          .whereType<String>()
          .toList();
      final provisionRaw = json['provision'];
      final provision = provisionRaw is Map
          ? BunnyUploadProvision.fromJson(Map<String, dynamic>.from(provisionRaw))
          : null;

      List<File> photoFiles = const [];
      FeedCreatePostDraft? draft;
      bool filesOk;
      if (kind == FeedUploadKind.photo) {
        final paths = ((json['mediaPaths'] as List?) ?? const [])
            .whereType<String>()
            .toList();
        photoFiles = paths.map((p) => File(p)).toList(growable: false);
        filesOk =
            photoFiles.isNotEmpty && photoFiles.every((f) => f.existsSync());
      } else {
        final videoPath = json['localVideoPath']?.toString();
        filesOk = videoPath != null &&
            videoPath.isNotEmpty &&
            File(videoPath).existsSync();
        if (filesOk) {
          int? msOf(String key) => json[key] is int
              ? json[key] as int
              : int.tryParse(json[key]?.toString() ?? '');
          draft = FeedCreatePostDraft(
            localVideoPath: videoPath,
            thumbnailPath: json['thumbnailPath']?.toString(),
            trimStart: msOf('trimStartMs') != null
                ? Duration(milliseconds: msOf('trimStartMs')!)
                : null,
            trimmedDuration: msOf('trimmedDurationMs') != null
                ? Duration(milliseconds: msOf('trimmedDurationMs')!)
                : null,
            originalDuration: msOf('originalDurationMs') != null
                ? Duration(milliseconds: msOf('originalDurationMs')!)
                : null,
            userPickedCover: json['userPickedCover'] == true,
            mimeType: json['mimeType']?.toString(),
            originalFilename: json['originalFilename']?.toString(),
            caption: caption,
            taggedProductIds: productIds,
          );
        }
      }

      if (!filesOk) {
        await _clearPending();
        return;
      }

      _pendingProvision = provision;
      _task = FeedUploadTask(
        localId: json['localId']?.toString() ?? _genId(),
        kind: kind,
        photoFiles: photoFiles,
        videoDraft: draft,
        caption: caption,
        productIds: productIds,
        status: FeedUploadStatus.resumable,
        createdAt: DateTime.now(),
      );
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[feed-upload-store] checkForResumableUpload failed: $e');
      }
    }
  }

  /// User tap "Lanjutkan" di bar `resumable`. Foto: restart dari awal
  /// (murah, tidak ada progress byte untuk di-resume). Video: jalankan
  /// ulang `_runVideoUpload` — provision tersimpan tetap di-pass HANYA
  /// untuk keperluan persist/diagnostik, TIDAK di-reuse untuk provisioning
  /// (SELALU re-provision VideoId baru, lihat komentar di `_runVideoUpload`
  /// Step 3 — file di-recompress ulang tiap resume sehingga melanjutkan
  /// upload ke VideoId lama berisiko splice byte → video korup).
  Future<void> resumePersisted() async {
    final task = _task;
    if (task == null || task.status != FeedUploadStatus.resumable) return;
    if (_uploading) return;

    if (task.kind == FeedUploadKind.photo) {
      final files = task.photoFiles;
      final caption = task.caption;
      final productIds = task.productIds;
      final localId = task.localId;
      _pendingProvision = null;
      _task = null;
      notifyListeners();
      await startPhotoUpload(
        files: files,
        caption: caption,
        productIds: productIds,
        localId: localId,
      );
      return;
    }

    final draft = task.videoDraft;
    if (draft == null) {
      // Tidak ada draft valid untuk resume (seharusnya tidak terjadi —
      // checkForResumableUpload sudah validasi) — bersihkan saja.
      dismissResumable();
      return;
    }
    final provision = _pendingProvision;
    _pendingProvision = null;
    _cancelAutoDismiss();
    _cancelRequested = false;
    _task = FeedUploadTask(
      localId: task.localId,
      kind: FeedUploadKind.video,
      caption: task.caption,
      productIds: task.productIds,
      videoDraft: draft,
      status: FeedUploadStatus.preparing,
      createdAt: DateTime.now(),
    );
    _uploading = true;
    notifyListeners();
    unawaited(_runVideoUpload(resumeProvision: provision));
  }

  /// User tap × di bar `resumable` — buang task + hapus persist.
  void dismissResumable() {
    if (_task?.status != FeedUploadStatus.resumable) return;
    _task = null;
    _pendingProvision = null;
    notifyListeners();
    unawaited(_clearPending());
  }

  /// Serialize task inflight ke JSON persist. Dipanggil saat pipeline
  /// mulai (photo/video) DAN diupdate setelah provision Bunny sukses.
  Future<void> _persistPending(
    FeedUploadTask task, {
    BunnyUploadProvision? provision,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final draft = task.videoDraft;
      final json = <String, dynamic>{
        'localId': task.localId,
        'kind': task.kind == FeedUploadKind.video ? 'video' : 'photo',
        'caption': task.caption,
        'productIds': task.productIds,
        'mediaPaths': task.photoFiles.map((f) => f.path).toList(),
        'thumbnailPath': draft?.thumbnailPath,
        'localVideoPath': draft?.localVideoPath,
        'trimStartMs': draft?.trimStart?.inMilliseconds,
        'trimmedDurationMs': draft?.trimmedDuration?.inMilliseconds,
        'originalDurationMs': draft?.originalDuration?.inMilliseconds,
        'userPickedCover': draft?.userPickedCover ?? false,
        'mimeType': draft?.mimeType,
        'originalFilename': draft?.originalFilename,
        'provision': provision?.toJson(),
        'savedAtMs': nowMs(),
      };
      await prefs.setString(_pendingKey, jsonEncode(json));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[feed-upload-store] persistPending failed: $e');
      }
    }
  }

  Future<void> _clearPending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pendingKey);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[feed-upload-store] clearPending failed: $e');
      }
    }
  }

  /// Dipanggil di `finally` tiap pipeline — hapus persist bila task baru
  /// saja transisi ke status terminal (success/waitingReview/cancelled/
  /// failed). Retry tetap dilayani in-memory (`retry()`); persist semata
  /// untuk kasus app-kill saat preparing/uploading.
  Future<void> _clearPendingIfTerminal() async {
    final status = _task?.status;
    if (status == FeedUploadStatus.success ||
        status == FeedUploadStatus.waitingReview ||
        status == FeedUploadStatus.cancelled ||
        status == FeedUploadStatus.failed) {
      await _clearPending();
    }
  }

  void _update({
    FeedUploadStatus? status,
    double? progress,
    String? errorMessage,
    int? photosDone,
    int? photosTotal,
  }) {
    final task = _task;
    if (task == null) return;
    _task = task.copyWith(
      status: status,
      progress: progress,
      errorMessage: errorMessage,
      photosDone: photosDone,
      photosTotal: photosTotal,
    );
    notifyListeners();
  }

  void _scheduleAutoDismiss() {
    _cancelAutoDismiss();
    // Spec request: tahan success state 700-1200ms (compromise pakai
    // 1500ms — cukup user notice "Postingan terkirim" tanpa terlalu
    // lama nahan UI). Sebelumnya 3 detik = terlalu lama.
    _autoDismissTimer = Timer(const Duration(milliseconds: 1500), () {
      final s = _task?.status;
      if (s == FeedUploadStatus.success || s == FeedUploadStatus.waitingReview) {
        _task = null;
        notifyListeners();
      }
    });
  }

  void _cancelAutoDismiss() {
    _autoDismissTimer?.cancel();
    _autoDismissTimer = null;
  }

  String _genId() =>
      'upl-${DateTime.now().millisecondsSinceEpoch}-${math.Random().nextInt(99999)}';

  String _friendlyError(Object error) {
    final raw = error.toString();
    if (raw.contains('SocketException') || raw.contains('Failed host lookup')) {
      return 'Koneksi tidak stabil. Periksa internet kamu dan coba lagi.';
    }
    if (raw.contains('TimeoutException') || raw.contains('Timeout')) {
      return 'Upload timeout. Coba lagi dengan koneksi lebih cepat.';
    }
    if (error is FeedPhotoUploadException) return error.message;
    return 'Upload gagal. Coba lagi.';
  }
}

final feedUploadStore = FeedUploadStore.instance;

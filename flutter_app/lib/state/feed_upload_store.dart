import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../models/feed_create_post_draft.dart';
import '../services/api_client.dart';
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
  });

  FeedUploadTask copyWith({
    FeedUploadStatus? status,
    double? progress,
    String? errorMessage,
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

  /// Auto-dismiss timer untuk success / waiting-review state. Disimpan
  /// supaya bisa di-cancel kalau task baru di-start sebelum dismiss.
  Timer? _autoDismissTimer;

  /// Lock supaya double-submit tidak start 2 upload concurrent (race).
  bool _uploading = false;
  bool get isUploading => _uploading;

  /// Start upload PHOTO_CAROUSEL — fire-and-forget. UI relay card auto
  /// update via notifyListeners. Returns immediately (Future<void>
  /// reflect "task accepted", bukan "upload selesai").
  Future<void> startPhotoUpload({
    required List<File> files,
    required String caption,
    List<String> productIds = const [],
  }) async {
    if (_uploading) return;
    if (files.isEmpty || files.length > 8) {
      _task = FeedUploadTask(
        localId: _genId(),
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
    _task = FeedUploadTask(
      localId: _genId(),
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
          );
        },
      );

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
      _scheduleAutoDismiss();
    } catch (error) {
      AppHaptics.warning();
      _update(
        status: FeedUploadStatus.failed,
        errorMessage: _friendlyError(error),
      );
    } finally {
      _uploading = false;
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

  Future<void> _runVideoUpload() async {
    final task = _task;
    final draft = task?.videoDraft;
    if (task == null || draft == null) return;

    try {
      final originalPath = draft.finalVideoPath;
      if (originalPath == null) {
        throw const FeedPhotoUploadException(
          'Video tidak tersedia. Kembali ke detail postingan.',
        );
      }

      // ── Step 0 — Compress video ke 720p ──
      // CRITICAL: missed di first version background upload (v1.0.86) →
      // user upload original video (50-300MB iPhone 4K) → Bunny encode
      // lambat → URL .mp4 404 sampai encode selesai. Trip compress dulu:
      // - Skip kalau sudah ada trimmedVideoPath (= sudah hasil
      //   VideoCompress di trim screen).
      // - Skip kalau compress gagal (fallback ke original).
      // Match logic FeedUploadProgressScreen._startUpload() yang lama.
      _update(status: FeedUploadStatus.preparing, progress: 0.05);
      String videoPath = originalPath;
      if (draft.trimmedVideoPath == null) {
        try {
          final info = await VideoCompress.compressVideo(
            originalPath,
            quality: VideoQuality.Res1280x720Quality,
            deleteOrigin: false,
            includeAudio: true,
          );
          final compressed = info?.file;
          if (compressed != null && await compressed.exists()) {
            videoPath = compressed.path;
            if (kDebugMode) {
              final origSize = await File(originalPath).length();
              final newSize = await compressed.length();
              debugPrint(
                '[feed-upload-store] compressed: ${origSize ~/ 1024}KB → '
                '${newSize ~/ 1024}KB '
                '(${(100 - newSize / origSize * 100).round()}% reduction)',
              );
            }
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[feed-upload-store] compress failed, fallback: $e');
          }
          // Tetap pakai original — Bunny bisa accept + re-encode.
        }
      }

      // ── Step 1 — Generate thumbnail kalau belum ada ──
      // Sebelumnya skip generate, hanya pakai existing thumbnailPath.
      // Tapi kalau draft.thumbnailPath null (mis. user submit dari path
      // yang lewat tanpa cover picker), upload tidak punya thumbnail.
      // Generate sekarang dari frame 500ms.
      String? thumbPath = draft.thumbnailPath;
      if (thumbPath == null || !File(thumbPath).existsSync()) {
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

      // ── Step 3 — Bunny provision (create FeedPost placeholder + dapat
      // TUS credentials). ──
      _update(status: FeedUploadStatus.uploading, progress: 0.2);
      final bunnyService = BunnyUploadService(
        apiClient: apiClient,
        feedService: feedService,
      );
      final caption = task.caption.trim();
      final provision = await bunnyService.provisionUpload(
        title: caption.isEmpty
            ? 'Postingan baru'
            : caption.substring(0, math.min(80, caption.length)),
        description: caption.isEmpty ? null : caption,
        videoDurationSec: draft.finalDuration?.inSeconds,
        productIds: task.productIds,
        thumbnailUrl: thumbnailUrl,
      );

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

      // Step 4 — Server akan transcode via Bunny webhook async. Tampilkan
      // processing state. Customer post selalu PENDING_REVIEW.
      _update(status: FeedUploadStatus.processing, progress: 0.95);
      await bunnyService.finalize(provision.postId);

      AppHaptics.success();
      _update(status: FeedUploadStatus.waitingReview, progress: 1);
      _scheduleAutoDismiss();
    } catch (error) {
      AppHaptics.warning();
      _update(
        status: FeedUploadStatus.failed,
        errorMessage: _friendlyError(error),
      );
    } finally {
      _uploading = false;
    }
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
    _cancelAutoDismiss();
    notifyListeners();
  }

  void _update({
    FeedUploadStatus? status,
    double? progress,
    String? errorMessage,
  }) {
    final task = _task;
    if (task == null) return;
    _task = task.copyWith(
      status: status,
      progress: progress,
      errorMessage: errorMessage,
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

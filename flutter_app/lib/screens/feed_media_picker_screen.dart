// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../models/feed_create_post_draft.dart';
import '../services/app_analytics.dart';
import '../utils/card_modal_route.dart';
import '../utils/fade_route.dart';
import '../utils/haptics.dart';
import '../widgets/photo_crop/photo_crop_export.dart';
import '../widgets/photo_crop/photo_crop_preview.dart';
import '../widgets/photo_crop/photo_crop_transform.dart';
import 'feed_new_post_screen.dart';
import 'feed_post/feed_video_edit_screen.dart';

const int maxPhotoCarouselItems = 8;
const int minVideoDurationSeconds = 1;
const int maxVideoDurationSeconds = 60;

const _bgBlack = Color(0xFF000000);
const _natoloBlue = Color(0xFF1E5BFF);
const _textWhite = Color(0xFFFFFFFF);
const _textMuted = Color(0xFF9CA3AF);
const _selectedBorder = _natoloBlue;
const _tileBg = Color(0xFF1F2937);

/// Pesan format video tak didukung — dipakai saat VideoPlayerController
/// gagal initialize (decode error) baik di preview (`_ensureVideoController`)
/// maupun saat pick (`_selectVideo`), supaya user dapat pesan konsisten
/// alih-alih spinner selamanya / "File belum bisa diproses" generik.
const _unsupportedVideoFormatMessage =
    'Format video ini belum didukung. Coba video lain atau rekam ulang dengan kamera.';

// Saturation boost matrices DIHAPUS (v1.0.82) — bikin lag scroll grid
// + lag swipe/pinch preview karena ColorFilter shader apply per-frame
// ke setiap thumbnail (100+ tile) + ke VideoPlayer/preview. Trade-off:
// foto sedikit kurang saturated dibanding sebelumnya, tapi UX jauh
// lebih smooth. Bunny CDN sudah handle color profile P3 → sRGB di
// server-side (saat encoding), tidak perlu compensate di client.

enum FeedPostContentType {
  image,
  video,
}

/// Item dipilih oleh user (foto atau video).
class SelectedMediaItem {
  final String id; // AssetEntity.id atau path-based fallback
  final String localPath; // file path lokal hasil .file getter
  final FeedPostContentType contentType;
  final String? thumbnailPath;
  final int? durationSeconds;
  final int orderIndex;

  const SelectedMediaItem({
    required this.id,
    required this.localPath,
    required this.contentType,
    this.thumbnailPath,
    this.durationSeconds,
    required this.orderIndex,
  });

  SelectedMediaItem copyWithOrder(int newIndex) => SelectedMediaItem(
        id: id,
        localPath: localPath,
        contentType: contentType,
        thumbnailPath: thumbnailPath,
        durationSeconds: durationSeconds,
        orderIndex: newIndex,
      );
}

/// Inline gallery picker — Instagram-style.
///
/// Spec:
///  - Background hitam.
///  - Header: [X] Buat Postingan [Next]
///  - Preview full-width × ratio 4:5 fixed (frame tetap; toggle cover/contain).
///  - Gallery section: "Terbaru ˅" + "Album" button + helper text +
///    grid mixed foto/video thumbnails.
///  - Selection mode auto-detect: first pick = photo → photo mode (max 8),
///    first pick = video → video mode (max 1).
///  - Video preview autoplay muted + looping (real VideoPlayer, bukan
///    thumbnail).
///  - Toast invalid action.
///  - Album bottom sheet picker.
class FeedMediaPickerScreen extends StatefulWidget {
  const FeedMediaPickerScreen({super.key});

  /// Entry point flow posting — pengganti FeedUploadSheet.show() (dihapus).
  static Future<bool?> open(BuildContext context) {
    return Navigator.of(context).push<bool>(
      cardModalRoute((_) => const FeedMediaPickerScreen()),
    );
  }

  /// Rasio frame preview — KONSTAN 4:5 (fixed-frame ala IG). Seam test +
  /// dokumentasi invariant: WAJIB sama untuk kedua nilai [fitOriginal].
  /// Regresi lama: rasio berubah ke natural foto saat fitOriginal=true →
  /// seluruh layout (grid galeri) melompat.
  @visibleForTesting
  static double resolvePreviewAspect({required bool fitOriginal}) =>
      _FeedMediaPickerScreenState._defaultPreviewAspect;

  @override
  State<FeedMediaPickerScreen> createState() => _FeedMediaPickerScreenState();
}

class _FeedMediaPickerScreenState extends State<FeedMediaPickerScreen> {
  // ─── State ────────────────────────────────────────────────────────
  List<AssetPathEntity> _albums = const [];
  AssetPathEntity? _selectedAlbum;
  final List<AssetEntity> _assets = [];
  int _assetPage = 0;
  static const _pageSize = 80;
  bool _hasMoreAssets = true;
  bool _loadingAssets = false;

  FeedPostContentType? _mode; // null = belum ada pilihan (default).
  List<SelectedMediaItem> _selectedPhotos = const [];
  SelectedMediaItem? _selectedVideo;
  bool _busyProcessing = false;
  bool _isDisposing = false;
  String? _toastMessage;
  Timer? _toastTimer;

  PermissionState? _permissionState;
  VideoPlayerController? _videoController;
  bool _videoControllerReady = false;
  String? _videoControllerPath;

  /// Pesan error preview video (mis. format tak didukung / decode gagal
  /// oleh VideoPlayerController). null = tidak ada error. Di-reset saat
  /// ganti preview asset (`_setPreviewAsset`). Dipakai `_buildPreviewContent`
  /// untuk render pesan inline (bukan spinner selamanya) + toast sekali
  /// saat error pertama terjadi.
  String? _previewVideoError;

  // Instagram-style preview frame — FIXED, tidak pernah berubah ukuran:
  // - Frame selalu full-width × rasio 4:5 (ala IG picker).
  // - Default (fitOriginal=false): foto COVER (mengisi penuh + crop) →
  //   kesan pertama natural, bukan "terpress".
  // - Tap icon (fitOriginal=true): foto CONTAIN (utuh + letterbox) DI DALAM
  //   frame 4:5 yang SAMA. Bingkai diam, foto yang mengecil.
  // Toggle TIDAK me-resize frame lagi (dulu begitu → grid galeri melompat).
  static const double _defaultPreviewAspect = 4 / 5; // 0.8 portrait
  bool _previewFitOriginal = false;
  // Preview image size (lazy load lewat ui.instantiateImageCodec, ~50ms
  // vs ~500-1500ms via image package). Dipakai untuk pra-muat ke
  // PhotoCropPreview supaya tidak load ulang (anti-flash pinch).
  Size? _previewImageSize;
  String? _previewImageSizeAssetId; // track asset yg size-nya sudah loaded.
  final Map<String, PhotoCropTransform> _photoCropTransforms = {};
  // Lookup asset by id — dipakai strip re-crop (Task 5B) untuk resolve
  // AssetEntity dari id foto terpilih tanpa scan ulang _assets.
  final Map<String, AssetEntity> _assetById = {};
  bool _thumbStripHintShown = false;

  /// Rasio frame preview — KONSTAN 4:5 (ala IG picker, fixed-frame).
  /// Toggle fitOriginal tidak lagi mengubah ukuran frame; hanya cara foto
  /// mengisinya (cover ↔ contain) di dalam frame yang sama.
  double get _previewAspect => FeedMediaPickerScreen.resolvePreviewAspect(
        fitOriginal: _previewFitOriginal,
      );

  /// Load preview image dimensions cepat pakai `ui.instantiateImageCodec`
  /// (native, ~10x faster dari image package decode). Update state +
  /// trigger rebuild supaya _previewAspect computed.
  Future<void> _loadPreviewImageSize(String assetId, String path) async {
    if (_previewImageSizeAssetId == assetId && _previewImageSize != null) {
      return; // Sudah loaded untuk asset ini.
    }
    try {
      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final size = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      frame.image.dispose();
      if (!mounted || _previewAssetIdNow != assetId) return;
      setState(() {
        _previewImageSize = size;
        _previewImageSizeAssetId = assetId;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _previewImageSize = null;
        _previewImageSizeAssetId = null;
      });
    }
  }

  /// Helper: assetId yang sedang di-preview saat ini (untuk guard race).
  String? get _previewAssetIdNow => _previewAsset?.id;

  // ─── Lifecycle ────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    unawaited(
      AppAnalytics.logEvent(
          'feed_post_pick_opened', {'source': 'media_picker'}),
    );
    _initPermissionAndLoad();
  }

  @override
  void dispose() {
    _isDisposing = true;
    _toastTimer?.cancel();
    _disposeVideoController();
    super.dispose();
  }

  // ─── Permission + album fetch ─────────────────────────────────────
  Future<void> _initPermissionAndLoad() async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!mounted) return;
    setState(() => _permissionState = permission);
    if (!permission.isAuth && !permission.hasAccess) return;

    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.common, // foto + video
      onlyAll: false,
      filterOption: FilterOptionGroup(
        orders: [
          const OrderOption(type: OrderOptionType.createDate, asc: false)
        ],
      ),
    );
    // BUGFIX(audit): guard mounted terbalik — sebelumnya `if (!mounted ||
    // albums.isEmpty) setState(...)` tetap memanggil setState saat !mounted
    // (picker ditutup saat getAssetPathList masih await) → crash. Cek
    // mounted dulu & return, baru handle albums kosong.
    if (!mounted) return;
    if (albums.isEmpty) {
      setState(() => _albums = albums);
      return;
    }
    // Pilih "All / Recent" sebagai default (biasanya album pertama).
    final initialAlbum = albums.first;
    setState(() {
      _albums = albums;
      _selectedAlbum = initialAlbum;
    });
    await _loadMoreAssets(initial: true);
  }

  Future<void> _loadMoreAssets({bool initial = false}) async {
    if (_loadingAssets) return;
    final album = _selectedAlbum;
    if (album == null) return;
    if (!initial && !_hasMoreAssets) return;

    setState(() => _loadingAssets = true);
    try {
      final page = await album.getAssetListPaged(
        page: _assetPage,
        size: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        if (initial) _assets.clear();
        _assets.addAll(page);
        _hasMoreAssets = page.length >= _pageSize;
        _assetPage += 1;
        _loadingAssets = false;
      });
      // Initial — auto-set preview ke media terbaru kalau ada.
      if (initial && _assets.isNotEmpty) {
        await _setPreviewAsset(_assets.first);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingAssets = false);
    }
  }

  Future<void> _switchAlbum(AssetPathEntity album) async {
    if (album.id == _selectedAlbum?.id) return;
    setState(() {
      _selectedAlbum = album;
      _assetPage = 0;
      _hasMoreAssets = true;
      _assets.clear();
    });
    await _loadMoreAssets(initial: true);
  }

  // ─── Preview (asset terbaru saat first open, atau hover-style) ────
  AssetEntity? _previewAsset;
  String? _previewPath;
  String? _previewThumb;
  int? _previewDurationSec;
  FeedPostContentType? _previewType;

  Future<void> _setPreviewAsset(AssetEntity asset) async {
    // Defensif: pastikan lookup id→asset selalu up-to-date walau dipanggil
    // dari path lain (bukan hanya _selectPhoto), mis. auto-preview initial.
    _assetById[asset.id] = asset;
    final isVideo = asset.type == AssetType.video;
    // Pakai originFile (bukan asset.file) — preserve ICC color profile
    // bytes dari original photo (iPhone biasa simpan dengan P3 wide
    // gamut). asset.file mungkin re-compress + strip profile, bikin
    // warna ke-clamp lebih pucat saat di-render Flutter. originFile
    // raw bytes intact → ColorFilter saturation boost di bawah dapat
    // source yang lebih kaya.
    final file = await asset.originFile;
    if (!mounted || file == null) return;
    final path = file.path;
    setState(() {
      _previewAsset = asset;
      _previewPath = path;
      _previewType =
          isVideo ? FeedPostContentType.video : FeedPostContentType.image;
      _previewDurationSec = isVideo ? asset.duration : null;
      // Reset cached image size — akan reload di bawah untuk asset baru.
      // Penting supaya _previewAspect tidak pakai size foto sebelumnya.
      if (_previewImageSizeAssetId != asset.id) {
        _previewImageSize = null;
        _previewImageSizeAssetId = null;
      }
      // Reset error preview video — asset baru, error lama tidak relevan.
      _previewVideoError = null;
    });
    if (isVideo) {
      // Generate thumbnail fallback (saat video belum ready).
      final thumb = await _generateVideoThumbnail(path);
      if (!mounted) return;
      setState(() => _previewThumb = thumb);
      await _ensureVideoController(path);
    } else {
      setState(() => _previewThumb = null);
      await _disposeVideoController();
      // Fast-load dimensions via ui.instantiateImageCodec (~50ms).
      // Dipakai untuk: (1) natural aspect saat fitOriginal=true,
      // (2) pass ke _PhotoCropPreview supaya pinch responsive instan.
      unawaited(_loadPreviewImageSize(asset.id, path));
    }
  }

  // ─── Video player controller ─────────────────────────────────────
  Future<void> _ensureVideoController(String path) async {
    if (_videoControllerPath == path && _videoController != null) {
      // Same video — restart play kalau ke-pause.
      if (_videoController?.value.isPlaying == false) {
        await _videoController?.play();
      }
      return;
    }
    await _disposeVideoController();
    final controller = VideoPlayerController.file(File(path));
    _videoController = controller;
    _videoControllerPath = path;
    try {
      await controller.initialize();
      if (!mounted || _videoController != controller) return;
      // Muted by design (ala IG) — ini preview lokal saat memilih klip di
      // picker, bukan pemutaran feed; tidak perlu ikut appSettingsStore
      // .feedMuted, selalu bisu supaya tidak mengagetkan saat scroll galeri.
      await controller.setVolume(0);
      await controller.setLooping(true);
      await controller.play();
      setState(() {
        _videoControllerReady = true;
        _previewVideoError = null;
      });
    } catch (_) {
      await controller.dispose();
      if (!mounted || _videoController != controller) return;
      setState(() {
        _videoControllerReady = false;
        _previewVideoError = _unsupportedVideoFormatMessage;
      });
      _showToast(_unsupportedVideoFormatMessage);
    }
  }

  Future<void> _disposeVideoController() async {
    final controller = _videoController;
    _videoController = null;
    _videoControllerPath = null;
    // BUGFIX(audit): method ini dipanggil juga dari dispose() (di mana
    // mounted == false). setState() saat unmount → assertion 'setState()
    // called after dispose()'. Guard mounted: kalau lagi dispose, cukup
    // set field tanpa setState (UI sudah mau dibuang).
    if (mounted && !_isDisposing) {
      setState(() => _videoControllerReady = false);
    } else {
      _videoControllerReady = false;
    }
    await controller?.pause();
    await controller?.dispose();
  }

  Future<String?> _generateVideoThumbnail(String videoPath) async {
    try {
      final result = await VideoThumbnail.thumbnailFile(
        video: videoPath,
        imageFormat: ImageFormat.JPEG,
        quality: 75,
        maxWidth: 600,
      );
      return result;
    } catch (_) {
      return null;
    }
  }

  // ─── Photo prepare: cover/fit hasil preview Instagram-style ───────
  // Source foto bisa apa saja (9:16 HP screenshot, 4:3 DSLR, 1:1 square,
  // 16:9 landscape). Picker preview punya frame tetap 4:5.
  //
  // Saat _next():
  //   - Default cover/fill: center-crop ke 4:5 agar hasil match preview.
  //   - Fit/original: preserve rasio asli, hanya bake EXIF + resize aman.
  //
  // Limit max long-side 2160px supaya hasil tidak gigantic (iPhone foto
  // 12MP = ~4032×3024 → resize proportional). Vercel upload limit 4.5MB
  // tetap punya headroom di quality 88.
  static const int _maxLongSide = 2160;
  static const int _jpegQuality = 88;

  Future<List<File>> _preparePhotoFiles(
    List<SelectedMediaItem> items,
  ) async {
    // PERF: process semua foto PARALLEL via Future.wait + compute().
    // Sebelumnya sequential di main isolate — decode + bakeOrientation +
    // copyCrop + copyResize + encodeJpg semua di UI thread, blocking
    // ~500-1500ms PER foto. 8 foto = ~20 detik UI freeze → tombol Next
    // terasa "lagging". Sekarang tiap foto dispatch ke background
    // isolate (`compute()`) dan jalan paralel; main thread tetap responsif
    // selama spinner ditampilkan.
    final tmpDir = await getTemporaryDirectory();
    final tmpDirPath = tmpDir.path;
    final aspect = _previewAspect;
    final preserveOriginal = _previewFitOriginal;

    final futures = items.asMap().entries.map((entry) async {
      final index = entry.key;
      final item = entry.value;
      final transform = _photoCropTransforms[item.id] ?? PhotoCropTransform();
      // HEIC-safe: sama seperti jalur profil (profile_photo_picker_screen).
      final normalizedPath = await normalizePhotoSourceToJpeg(
        item.localPath,
        tmpDirPath,
        pathSeparator: Platform.pathSeparator,
      );
      final args = PhotoProcessArgs(
        sourcePath: normalizedPath,
        tmpDirPath: tmpDirPath,
        targetAspect: aspect,
        scale: transform.scale,
        offsetFractionX: transform.offsetFraction.dx,
        offsetFractionY: transform.offsetFraction.dy,
        preserveOriginal: preserveOriginal,
        maxLongSide: _maxLongSide,
        jpegQuality: _jpegQuality,
        timestampSuffix: index,
        pathSeparator: Platform.pathSeparator,
      );
      return compute(processPhotoInIsolate, args);
    }).toList();

    final paths = await Future.wait(futures);
    return paths.map(File.new).toList();
  }

  // ─── Selection logic ─────────────────────────────────────────────
  Future<void> _onTapAsset(AssetEntity asset) async {
    if (_busyProcessing) return;
    AppHaptics.tap();

    final isVideo = asset.type == AssetType.video;

    // Lock mode dari first pick. Kalau sudah ada mode, validate fit.
    if (_mode != null) {
      if (_mode == FeedPostContentType.image && isVideo) {
        _showToast('Video tidak bisa digabung dengan foto');
        return;
      }
      if (_mode == FeedPostContentType.video && !isVideo) {
        _showToast('Video hanya bisa dipilih satu');
        return;
      }
    }

    if (isVideo) {
      await _selectVideo(asset);
    } else {
      await _selectPhoto(asset);
    }
  }

  Future<void> _selectPhoto(AssetEntity asset) async {
    // Toggle: kalau sudah selected, deselect.
    final existingIndex =
        _selectedPhotos.indexWhere((item) => item.id == asset.id);
    if (existingIndex >= 0) {
      _removeSelectedPhotoAt(existingIndex);
      return;
    }
    if (_selectedPhotos.length >= maxPhotoCarouselItems) {
      _showToast('Maksimal 8 foto');
      return;
    }
    setState(() => _busyProcessing = true);
    try {
      final file = await asset.file;
      if (file == null) throw 'no_file';
      final item = SelectedMediaItem(
        id: asset.id,
        localPath: file.path,
        contentType: FeedPostContentType.image,
        orderIndex: _selectedPhotos.length,
      );
      if (!mounted) return;
      _assetById[asset.id] = asset;
      setState(() {
        _selectedPhotos = [..._selectedPhotos, item];
        _mode = FeedPostContentType.image;
        _busyProcessing = false;
      });
      // Update preview ke foto yang baru di-pick (atau foto terakhir
      // dalam selection list).
      await _setPreviewAsset(asset);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busyProcessing = false);
      _showToast('File belum bisa diproses. Coba pilih media lain.');
    }
  }

  Future<void> _selectVideo(AssetEntity asset) async {
    // Toggle: tap video sama = deselect.
    if (_selectedVideo?.id == asset.id) {
      setState(() {
        _selectedVideo = null;
        _mode = null;
      });
      return;
    }
    setState(() => _busyProcessing = true);
    try {
      final file = await asset.file;
      if (file == null) {
        throw 'Video ini belum bisa dibuka. Coba pilih video lain.';
      }
      final duration = asset.duration;
      if (duration < minVideoDurationSeconds) {
        throw 'Video terlalu pendek. Pilih video minimal 1 detik.';
      }
      final thumbnail = await _generateVideoThumbnail(file.path);
      if (!mounted) return;
      setState(() {
        _selectedVideo = SelectedMediaItem(
          id: asset.id,
          localPath: file.path,
          contentType: FeedPostContentType.video,
          thumbnailPath: thumbnail,
          durationSeconds: duration,
          orderIndex: 0,
        );
        _mode = FeedPostContentType.video;
        _busyProcessing = false;
      });
      await _setPreviewAsset(asset);
    } catch (error) {
      if (!mounted) return;
      setState(() => _busyProcessing = false);
      // error is String → pesan validasi kita sendiri (mis. durasi
      // minimum) — tampilkan apa adanya. Selain itu (decode/plugin
      // error lain, bukan String) → kemungkinan besar format video
      // tak didukung; pakai pesan format yang konsisten dengan
      // _ensureVideoController, bukan pesan generik "File belum bisa
      // diproses" yang kurang actionable.
      _showToast(
        error is String ? error : _unsupportedVideoFormatMessage,
      );
    }
  }

  void _removeSelectedPhotoAt(int index) {
    AppHaptics.selection();
    final next = List<SelectedMediaItem>.from(_selectedPhotos)..removeAt(index);
    setState(() {
      _selectedPhotos = List.generate(
        next.length,
        (i) => next[i].copyWithOrder(i),
      );
      if (_selectedPhotos.isEmpty) _mode = null;
    });
  }

  // ─── Toast ───────────────────────────────────────────────────────
  void _showToast(String message) {
    if (!mounted) return;
    setState(() => _toastMessage = message);
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(seconds: 2200 ~/ 1000), () {
      if (!mounted) return;
      setState(() => _toastMessage = null);
    });
    AppHaptics.warning();
  }

  // ─── Next ────────────────────────────────────────────────────────
  bool get _canProceed {
    if (_busyProcessing) return false;
    if (_mode == FeedPostContentType.image) return _selectedPhotos.isNotEmpty;
    if (_mode == FeedPostContentType.video) return _selectedVideo != null;
    return false;
  }

  Future<void> _next() async {
    if (!_canProceed) return;
    AppHaptics.tap();
    if (_mode == FeedPostContentType.image) {
      unawaited(
        AppAnalytics.logEvent('feed_post_media_selected', {
          'type': _selectedPhotos.length > 1 ? 'carousel' : 'photo',
          'count': _selectedPhotos.length,
        }),
      );
    } else if (_mode == FeedPostContentType.video) {
      unawaited(
        AppAnalytics.logEvent('feed_post_media_selected', {
          'type': 'video',
          'count': 1,
        }),
      );
    }
    if (_mode == FeedPostContentType.image) {
      // Prepare semua selected photos sesuai mode preview:
      // cover/fill → center-crop 4:5, fit/original → preserve rasio asli.
      setState(() => _busyProcessing = true);
      List<File> preparedFiles;
      try {
        preparedFiles = await _preparePhotoFiles(_selectedPhotos);
      } catch (_) {
        if (!mounted) return;
        setState(() => _busyProcessing = false);
        _showToast('Gagal proses foto. Coba lagi.');
        return;
      }
      if (!mounted) return;
      setState(() => _busyProcessing = false);
      // Pause video preview while we navigate.
      await _videoController?.pause();
      final result = await Navigator.push<bool>(
        context,
        fadeThroughRoute(
          FeedNewPostScreen(
            draft: NewPostMediaDraft.photos(preparedFiles),
          ),
        ),
      );
      if (result == true && mounted) Navigator.pop(context, true);
      return;
    }
    final video = _selectedVideo;
    if (video == null) return;
    final duration = Duration(seconds: video.durationSeconds ?? 0);
    final fileSize = await File(video.localPath).length();
    await _videoController?.pause();
    if (!mounted) return;
    final draft = FeedCreatePostDraft(
      originalVideoPath: video.localPath,
      localVideoPath: video.localPath,
      thumbnailPath: video.thumbnailPath,
      originalDuration: duration,
      fileSizeBytes: fileSize,
      originalFilename: video.localPath.split(RegExp(r'[\\/]')).last,
      mimeType: _videoMimeType(video.localPath),
    );
    // Semua video (<=60s dan >60s) masuk Edit Video fullscreen tunggal
    // (Fase 2B) — gabungan preview+trim, Next di sana push FeedNewPostScreen
    // sendiri (tidak pernah pop dengan value), jadi wiring konsisten.
    final result = await Navigator.push<bool>(
      context,
      fadeThroughRoute(FeedVideoEditScreen(draft: draft)),
    );
    if (result == true && mounted) Navigator.pop(context, true);
  }

  String _videoMimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.mkv')) return 'video/x-matroska';
    return 'video/mp4';
  }

  // ─── Album sheet ─────────────────────────────────────────────────
  Future<void> _openAlbumSheet() async {
    AppHaptics.tap();
    final picked = await showModalBottomSheet<AssetPathEntity>(
      context: context,
      backgroundColor: const Color(0xFF111827),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AlbumBottomSheet(
        albums: _albums,
        selected: _selectedAlbum,
      ),
    );
    if (picked != null && mounted) {
      await _switchAlbum(picked);
    }
  }

  // ─── Build ───────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final permission = _permissionState;
    return Scaffold(
      backgroundColor: _bgBlack,
      body: SafeArea(
        child: Column(
          children: [
            _MediaPickerHeader(
              canProceed: _canProceed,
              onClose: () => Navigator.pop(context, false),
              onNext: _next,
            ),
            if (permission == null)
              const Expanded(
                child: Center(
                  child: CircularProgressIndicator(
                    color: _natoloBlue,
                    strokeWidth: 2.4,
                  ),
                ),
              )
            else if (!permission.isAuth && !permission.hasAccess)
              const Expanded(child: _PermissionDeniedView())
            else
              Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    return CustomScrollView(
      slivers: [
        // Subtitle + constraint info dihapus per spec user — UI lebih
        // clean match Instagram (header langsung media tanpa helper text).
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
        // ── Preview area full-width × fixed 4:5 ──
        // Diagonal button overlay toggle cover/fill <-> contain/fit di dalam
        // frame yang sama, seperti Instagram picker.
        SliverToBoxAdapter(child: _buildPreview()),
        if (_mode == FeedPostContentType.image && _selectedPhotos.length >= 2)
          SliverToBoxAdapter(child: _buildThumbStripSection()),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _openAlbumSheet,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _selectedAlbum?.name ?? 'Terbaru',
                          style: const TextStyle(
                            color: _textWhite,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: _textWhite,
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _openAlbumSheet,
                  icon: const Icon(Icons.collections_outlined, size: 15),
                  label: const Text('Album'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _textWhite,
                    side: const BorderSide(color: Color(0xFF4B5563)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Constraint helper text dihapus per spec user — IG-style
        // (constraint info ditampilkan via toast saat user attempt aksi
        // invalid, bukan static text).
        const SliverToBoxAdapter(child: SizedBox(height: 10)),
        // ── Toast (kalau ada) ──
        if (_toastMessage != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: _PickerToast(message: _toastMessage!),
            ),
          ),
        // ── Grid 4-column ──
        SliverPadding(
          padding: EdgeInsets.only(
            bottom: _selectedPhotos.isNotEmpty ? 90 : 20,
          ),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
              childAspectRatio: 1,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                if (index >= _assets.length) {
                  if (_hasMoreAssets) _loadMoreAssets();
                  return const ColoredBox(color: _tileBg);
                }
                final asset = _assets[index];
                return _AssetGridTile(
                  asset: asset,
                  mode: _mode,
                  selectedPhotos: _selectedPhotos,
                  selectedVideo: _selectedVideo,
                  onTap: () => _onTapAsset(asset),
                );
              },
              childCount: _assets.length + (_hasMoreAssets ? 8 : 0),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreview() {
    // Frame FIXED: full-width (mengikuti lebar sliver) × rasio 4:5 konstan.
    // Tidak pernah berubah ukuran apa pun status toggle → grid galeri di
    // bawah tak bergeser (ala IG).
    return AspectRatio(
      aspectRatio: _previewAspect,
      child: ClipRRect(
        borderRadius: BorderRadius.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildPreviewContent(),
            // Floating fit/fill toggle bottom-left — visible saat mode
            // foto. Tap = cover <-> contain (di dalam frame yang sama).
            if (_mode != FeedPostContentType.video &&
                _previewType == FeedPostContentType.image)
              Positioned(
                left: 12,
                bottom: 12,
                child: _AspectToggleButton(
                  fitOriginal: _previewFitOriginal,
                  onTap: _togglePreviewFit,
                ),
              ),
            if (_mode == FeedPostContentType.image &&
                _selectedPhotos.length > 1 &&
                _previewAsset != null)
              Positioned(
                right: 10,
                top: 10,
                child: _PhotoCounterPill(
                  current: _selectedPhotoOrderForCounter,
                  total: _selectedPhotos.length,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Urutan foto tersorot (1-based) di antara foto terpilih — untuk pill
  /// counter "Foto X dari Y". Fallback 1 kalau tidak ketemu (mis. preview
  /// sedang menampilkan foto belum terseleksi).
  int get _selectedPhotoOrderForCounter {
    final asset = _previewAsset;
    if (asset == null) return 1;
    final idx = _selectedPhotos.indexWhere((p) => p.id == asset.id);
    return idx >= 0 ? idx + 1 : 1;
  }

  /// Tap thumbnail strip → bawa foto itu ke preview besar tanpa deselect
  /// (setara re-crop carousel IG). [id] = SelectedMediaItem.id / AssetEntity.id.
  Future<void> _recropSelectedPhoto(String id) async {
    final asset = _assetById[id];
    if (asset == null || _busyProcessing) return;
    AppHaptics.selection();
    await _setPreviewAsset(
        asset); // bawa ke preview besar; transform-nya ke-bind
  }

  /// Strip re-crop carousel (Task 5B) — tampil di bawah preview besar saat
  /// mode foto & minimal 2 foto terpilih. Hint 1× muncul saat strip
  /// pertama kali dirender di session ini.
  Widget _buildThumbStripSection() {
    final showHint = !_thumbStripHintShown;
    if (showHint) {
      // Set setelah build frame ini supaya hint hanya tampil sekali —
      // hindari setState di dalam build().
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _thumbStripHintShown = true);
      });
    }
    return Column(
      children: [
        const SizedBox(height: 12),
        if (showHint)
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text(
              'Ketuk foto untuk atur potongannya',
              style: TextStyle(
                color: _textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        _SelectedThumbStrip(
          items: _selectedPhotos
              .map((e) => (id: e.id, path: e.localPath))
              .toList(),
          activeId: _previewAsset?.id,
          onTap: _recropSelectedPhoto,
        ),
      ],
    );
  }

  /// Toggle cara foto mengisi frame 4:5 fixed: default cover/fill, tap ikon
  /// diagonal → contain/fit (foto utuh + letterbox) di frame yang SAMA.
  /// Frame tidak berubah ukuran; hanya BoxFit foto yang berganti.
  void _togglePreviewFit() {
    AppHaptics.tap();
    setState(() => _previewFitOriginal = !_previewFitOriginal);
  }

  PhotoCropTransform _getPhotoCropTransform(String assetId) {
    return _photoCropTransforms.putIfAbsent(assetId, PhotoCropTransform.new);
  }

  Widget _buildPreviewContent() {
    final asset = _previewAsset;
    if (asset == null) {
      return const ColoredBox(
        color: _tileBg,
        child: Center(
          child: Icon(
            Icons.photo_library_outlined,
            color: _textMuted,
            size: 56,
          ),
        ),
      );
    }
    if (_previewType == FeedPostContentType.video) {
      final controller = _videoController;
      final ready = _videoControllerReady &&
          controller != null &&
          controller.value.isInitialized;
      return Stack(
        fit: StackFit.expand,
        children: [
          // Wrap VideoPlayer + thumb fallback dengan ColorFiltered untuk
          // saturation boost — sama treatment dengan photo preview.
          // VideoPlayer pakai render path berbeda dari Image.file tapi
          // ColorFiltered saturation di-hapus dari preview — bikin
          // VideoPlayer + Image.file re-render dengan matrix shader
          // tiap frame video / tiap swipe interaksi. Drop = swipe
          // preview jauh lebih smooth.
          if (ready)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: controller.value.size.width > 0
                    ? controller.value.size.width
                    : 100,
                height: controller.value.size.height > 0
                    ? controller.value.size.height
                    : 100,
                child: VideoPlayer(controller),
              ),
            )
          else if (_previewThumb != null)
            Image.file(File(_previewThumb!), fit: BoxFit.cover)
          else
            const ColoredBox(color: _tileBg),
          // Spinner hanya selama masih ada harapan video bisa siap.
          // Kalau sudah gagal init (_previewVideoError != null),
          // spinner selamanya menyesatkan — tampilkan pesan inline
          // sebagai gantinya (lihat cabang di bawah).
          if (!ready && _previewVideoError == null)
            const Center(
              child: SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: _textWhite,
                ),
              ),
            ),
          if (!ready && _previewVideoError != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.videocam_off_rounded,
                      color: _textMuted,
                      size: 40,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _previewVideoError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _textMuted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_previewDurationSec != null && _previewDurationSec! > 0)
            Positioned(
              right: 10,
              bottom: 10,
              child: _DurationBadge(seconds: _previewDurationSec!),
            ),
        ],
      );
    }
    // Photo preview — Instagram-style fit/fill toggle di frame 4:5 FIXED.
    // - Default (fitOriginal=false): foto cover/fill (crop) mengisi frame.
    // - Tap icon (fitOriginal=true): foto contain/fit (utuh + letterbox)
    //   di dalam frame 4:5 yang SAMA — frame tidak berubah ukuran.
    // - Mode default: user bisa pinch/drag, hasil upload follow crop.
    if (_previewPath != null) {
      // Pass pre-loaded imageSize supaya _PhotoCropPreview tidak load
      // ulang (sudah loaded di _loadPreviewImageSize parent — fast 50ms
      // pakai ui.instantiateImageCodec). Pinch responsive instan tanpa
      // dead-window 500ms-1s yang lama.
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: PhotoCropPreview(
          key: ValueKey(
            '${asset.id}-${_previewFitOriginal ? 'fit' : 'fill'}',
          ),
          file: File(_previewPath!),
          fitOriginal: _previewFitOriginal,
          cropTransform: _getPhotoCropTransform(asset.id),
          preloadedImageSize:
              _previewImageSizeAssetId == asset.id ? _previewImageSize : null,
        ),
      );
    }
    return const ColoredBox(color: _tileBg);
  }
}

// ─── Header ──────────────────────────────────────────────────────────

class _MediaPickerHeader extends StatelessWidget {
  final bool canProceed;
  final VoidCallback onClose;
  final VoidCallback onNext;

  const _MediaPickerHeader({
    required this.canProceed,
    required this.onClose,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          const SizedBox(width: 14),
          _HeaderCloseButton(onTap: onClose),
          const Expanded(
            child: Text(
              'Post Baru',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _textWhite,
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          _HeaderNextButton(enabled: canProceed, onTap: onNext),
          const SizedBox(width: 14),
        ],
      ),
    );
  }
}

/// Header close — lingkaran 36 frosted (match mockup v2).
class _HeaderCloseButton extends StatelessWidget {
  final VoidCallback onTap;

  const _HeaderCloseButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.14),
              width: 1,
            ),
          ),
          child: const Icon(Icons.close_rounded, color: _textWhite, size: 19),
        ),
      ),
    );
  }
}

/// Header next — lingkaran 36 biru solid, disabled = frosted + ikon muted.
class _HeaderNextButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;

  const _HeaderNextButton({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: enabled ? _natoloBlue : Colors.white.withValues(alpha: 0.08),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.chevron_right_rounded,
            color: enabled ? _textWhite : _textMuted,
            size: 22,
          ),
        ),
      ),
    );
  }
}

// ─── Asset grid tile ─────────────────────────────────────────────────

class _AssetGridTile extends StatefulWidget {
  final AssetEntity asset;
  final FeedPostContentType? mode;
  final List<SelectedMediaItem> selectedPhotos;
  final SelectedMediaItem? selectedVideo;
  final VoidCallback onTap;

  const _AssetGridTile({
    required this.asset,
    required this.mode,
    required this.selectedPhotos,
    required this.selectedVideo,
    required this.onTap,
  });

  @override
  State<_AssetGridTile> createState() => _AssetGridTileState();
}

class _AssetGridTileState extends State<_AssetGridTile> {
  Uint8List? _thumb;

  @override
  void initState() {
    super.initState();
    _loadThumb();
  }

  @override
  void didUpdateWidget(_AssetGridTile old) {
    super.didUpdateWidget(old);
    if (old.asset.id != widget.asset.id) {
      _thumb = null;
      _loadThumb();
    }
  }

  Future<void> _loadThumb() async {
    final data = await widget.asset.thumbnailDataWithSize(
      const ThumbnailSize(220, 220),
    );
    if (!mounted) return;
    setState(() => _thumb = data);
  }

  bool get _isVideo => widget.asset.type == AssetType.video;
  bool get _isSelected {
    if (_isVideo) return widget.selectedVideo?.id == widget.asset.id;
    return widget.selectedPhotos.any((p) => p.id == widget.asset.id);
  }

  int? get _selectionOrder {
    if (_isVideo) return _isSelected ? 1 : null;
    final idx =
        widget.selectedPhotos.indexWhere((p) => p.id == widget.asset.id);
    return idx >= 0 ? idx + 1 : null;
  }

  bool get _isDimmed {
    final mode = widget.mode;
    if (mode == null) return false;
    if (mode == FeedPostContentType.image && _isVideo) return true;
    if (mode == FeedPostContentType.video &&
        !_isVideo &&
        widget.selectedVideo != null) {
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: _tileBg,
            child: _thumb == null
                ? const SizedBox.shrink()
                // ColorFiltered grid saturation di-hapus — terlalu mahal
                // di scroll (100+ thumbnail × ColorFilter render pass per
                // frame = stutter). User report grid scroll lag jadi
                // smooth setelah hapus ini.
                //
                // cacheWidth limit decode resolution ke 240px (sebelum
                // ditampilkan di 90×90 tile) — hemat memory + decode
                // time vs decode full thumbnail size.
                : Image.memory(
                    _thumb!,
                    fit: BoxFit.cover,
                    cacheWidth: 240,
                    gaplessPlayback: true,
                  ),
          ),
          if (_isDimmed) Container(color: Colors.black.withValues(alpha: 0.45)),
          if (_isSelected)
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: _selectedBorder, width: 3),
              ),
            ),
          if (_isVideo)
            const Positioned(
              top: 6,
              right: 6,
              child: Icon(
                Icons.videocam_rounded,
                color: _textWhite,
                size: 16,
              ),
            ),
          if (_isVideo && widget.asset.duration > 0)
            Positioned(
              right: 6,
              bottom: 6,
              child: _DurationBadge(seconds: widget.asset.duration),
            ),
          if (_selectionOrder != null && !_isVideo)
            Positioned(
              top: 6,
              right: 6,
              child: _SelectionBadge(order: _selectionOrder!),
            ),
          if (_selectionOrder != null && _isVideo)
            const Positioned(
              top: 6,
              right: 6,
              child: _SelectionBadge(order: 1),
            ),
          if (!_isSelected && !_isDimmed)
            Positioned(
              top: 6,
              right: 6,
              child: _UnselectedCircle(showVideoMargin: _isVideo),
            ),
        ],
      ),
    );
  }
}

class _SelectionBadge extends StatelessWidget {
  final int order;

  const _SelectionBadge({required this.order});

  @override
  Widget build(BuildContext context) {
    // Pop-in scale saat badge pertama muncul (foto baru dipilih) — element
    // ini fresh setiap kali swap dari _UnselectedCircle, jadi animasi
    // otomatis replay tiap seleksi baru tanpa perlu AnimationController.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.6, end: 1.0),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutBack,
      builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
      child: Container(
        width: 22,
        height: 22,
        decoration: const BoxDecoration(
          color: _natoloBlue,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            '$order',
            style: const TextStyle(
              color: _textWhite,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class _UnselectedCircle extends StatelessWidget {
  final bool showVideoMargin;

  const _UnselectedCircle({this.showVideoMargin = false});

  @override
  Widget build(BuildContext context) {
    // Untuk video, hide bullet circle karena overlap dengan video icon.
    if (showVideoMargin) return const SizedBox.shrink();
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _textWhite, width: 2),
      ),
    );
  }
}

class _DurationBadge extends StatelessWidget {
  final int seconds;

  const _DurationBadge({required this.seconds});

  @override
  Widget build(BuildContext context) {
    final mm = (seconds ~/ 60).toString().padLeft(1, '0');
    final ss = (seconds % 60).toString().padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.play_arrow_rounded, color: _textWhite, size: 9),
          const SizedBox(width: 2),
          Text(
            '$mm:$ss',
            style: const TextStyle(
              color: _textWhite,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pill counter "Foto X dari Y" — top-right preview besar, tampil saat
/// multi-foto (>1 selected).
class _PhotoCounterPill extends StatelessWidget {
  final int current;
  final int total;

  const _PhotoCounterPill({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Foto $current dari $total',
        style: const TextStyle(
          color: _textWhite,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

// ─── Permission denied ─────────────────────────────────────────────

class _PermissionDeniedView extends StatelessWidget {
  const _PermissionDeniedView();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.photo_library_outlined,
            color: _textMuted,
            size: 64,
          ),
          const SizedBox(height: 16),
          const Text(
            'Akses galeri ditolak',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _textWhite,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Buka Pengaturan untuk izinkan akses foto & video supaya bisa membuat postingan.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () => PhotoManager.openSetting(),
            style: ElevatedButton.styleFrom(
              backgroundColor: _natoloBlue,
              foregroundColor: _textWhite,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Buka Pengaturan',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Album bottom sheet ───────────────────────────────────────────

class _AlbumBottomSheet extends StatelessWidget {
  final List<AssetPathEntity> albums;
  final AssetPathEntity? selected;

  const _AlbumBottomSheet({
    required this.albums,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF374151),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Pilih Album',
                style: TextStyle(
                  color: _textWhite,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.5,
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: albums.length,
              separatorBuilder: (_, __) => const Divider(
                color: Color(0xFF1F2937),
                height: 1,
              ),
              itemBuilder: (context, index) {
                final album = albums[index];
                final isSelected = album.id == selected?.id;
                return ListTile(
                  onTap: () => Navigator.pop(context, album),
                  title: Text(
                    album.name,
                    style: TextStyle(
                      color: isSelected ? _natoloBlue : _textWhite,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  trailing: isSelected
                      ? const Icon(
                          Icons.check_rounded,
                          color: _natoloBlue,
                        )
                      : null,
                );
              },
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

// ─── Toast ────────────────────────────────────────────────────────

class _PickerToast extends StatelessWidget {
  final String message;

  const _PickerToast({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF7F1D1D).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: _textWhite,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Strip thumbnail foto terpilih (carousel) — tap untuk membawa foto ke
/// preview besar & atur crop-nya lagi. Presentasional murni.
class _SelectedThumbStrip extends StatelessWidget {
  final List<({String id, String path})> items; // urut = urutan slide
  final String? activeId; // foto yang sedang di preview
  final ValueChanged<String> onTap; // tap thumbnail → recrop id
  const _SelectedThumbStrip({
    required this.items,
    required this.activeId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = items[index];
          final active = item.id == activeId;
          return GestureDetector(
            key: ValueKey('thumb-${item.id}'),
            onTap: () => onTap(item.id),
            child: Container(
              width: 44,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: active ? _natoloBlue : Colors.transparent,
                  width: 2.5,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7.5),
                child: Image.file(
                  File(item.path),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const ColoredBox(color: _tileBg),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Seam untuk widget test — expose `_SelectedThumbStrip` tanpa perlu
/// `photo_manager` (presentasional murni, testable terpisah).
@visibleForTesting
Widget debugSelectedThumbStrip({
  required List<({String id, String path})> items,
  required String? activeId,
  required ValueChanged<String> onTap,
}) =>
    _SelectedThumbStrip(items: items, activeId: activeId, onTap: onTap);

/// Floating fit/fill toggle button — IG-style icon di bottom-left preview.
/// Tap = toggle cover/fill <-> contain/fit di frame 4:5 yang sama.
class _AspectToggleButton extends StatelessWidget {
  final bool fitOriginal;
  final VoidCallback onTap;

  const _AspectToggleButton({
    required this.fitOriginal,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.25),
              width: 0.8,
            ),
          ),
          child: Icon(
            fitOriginal
                ? Icons.fullscreen_exit_rounded
                : Icons.open_in_full_rounded,
            color: Colors.white,
            size: 19,
          ),
        ),
      ),
    );
  }
}

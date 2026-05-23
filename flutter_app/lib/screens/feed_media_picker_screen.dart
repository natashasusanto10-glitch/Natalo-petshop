// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../models/feed_create_post_draft.dart';
import '../utils/haptics.dart';
import 'feed_new_post_screen.dart';
import 'feed_video_upload_flow.dart';

const int maxPhotoCarouselItems = 8;
const int minVideoDurationSeconds = 1;
const int maxVideoDurationSeconds = 60;

const _bgBlack = Color(0xFF000000);
const _natoloBlue = Color(0xFF2563EB);
const _textWhite = Color(0xFFFFFFFF);
const _textMuted = Color(0xFF9CA3AF);
const _selectedBorder = _natoloBlue;
const _tileBg = Color(0xFF1F2937);

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

class _PhotoCropTransform {
  double scale = 1;
  Offset offsetFraction = Offset.zero;
}

/// Inline gallery picker — Instagram-style.
///
/// Spec:
///  - Background hitam.
///  - Header: [X] Buat Postingan [Next]
///  - Preview centered 75% lebar layar × ratio 3:4.
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
  String? _toastMessage;
  Timer? _toastTimer;

  PermissionState? _permissionState;
  VideoPlayerController? _videoController;
  bool _videoControllerReady = false;
  String? _videoControllerPath;

  // Instagram-style preview frame:
  // - Frame preview selalu 4:5.
  // - Default = cover/fill (media memenuhi frame).
  // - Tap icon diagonal = contain/fit (media terlihat utuh di frame sama).
  static const double _previewAspect = 4 / 5; // 0.8 portrait IG-standard.
  bool _previewFitOriginal = false;
  final Map<String, _PhotoCropTransform> _photoCropTransforms = {};

  // ─── Lifecycle ────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _initPermissionAndLoad();
  }

  @override
  void dispose() {
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
    if (!mounted || albums.isEmpty) {
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
      await controller.setVolume(0);
      await controller.setLooping(true);
      await controller.play();
      setState(() => _videoControllerReady = true);
    } catch (_) {
      await controller.dispose();
      if (!mounted || _videoController != controller) return;
      setState(() {
        _videoControllerReady = false;
      });
    }
  }

  Future<void> _disposeVideoController() async {
    final controller = _videoController;
    _videoController = null;
    _videoControllerPath = null;
    setState(() => _videoControllerReady = false);
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
    final results = <File>[];
    for (final item in items) {
      final source = File(item.localPath);
      final prepared = _previewFitOriginal
          ? await _preservePhoto(source)
          : await _cropPhotoWithTransform(
              source,
              _previewAspect,
              _photoCropTransforms[item.id] ?? _PhotoCropTransform(),
            );
      results.add(prepared);
    }
    return results;
  }

  /// Preserve original ratio + resize + encode JPEG. Return temp file.
  Future<File> _preservePhoto(File source) async {
    return _processPhoto(source);
  }

  /// Crop source supaya memenuhi target aspect 4:5, mengikuti pan/zoom
  /// yang user atur di preview. Kalau user belum geser/zoom, hasilnya sama
  /// seperti center-cover Instagram.
  Future<File> _cropPhotoWithTransform(
    File source,
    double targetAspect,
    _PhotoCropTransform transform,
  ) async {
    final bytes = await source.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return source;
    }
    final oriented = img.bakeOrientation(decoded);
    final srcW = oriented.width;
    final srcH = oriented.height;
    final frameW = targetAspect;
    const frameH = 1.0;
    final coverScale = math.max(frameW / srcW, frameH / srcH);
    final baseW = srcW * coverScale;
    final baseH = srcH * coverScale;
    final visualScale = transform.scale.clamp(1.0, 4.0).toDouble();
    final scaledW = baseW * visualScale;
    final scaledH = baseH * visualScale;
    final offsetX = transform.offsetFraction.dx * frameW;
    final offsetY = transform.offsetFraction.dy * frameH;

    final imageLeft = (frameW - scaledW) / 2 + offsetX;
    final imageTop = (frameH - scaledH) / 2 + offsetY;
    final cropX = (-imageLeft / scaledW) * srcW;
    final cropY = (-imageTop / scaledH) * srcH;
    final cropW = (frameW / scaledW) * srcW;
    final cropH = (frameH / scaledH) * srcH;

    final cropWInt = cropW.round().clamp(1, srcW).toInt();
    final cropHInt = cropH.round().clamp(1, srcH).toInt();
    final cropXInt =
        cropX.round().clamp(0, math.max(0, srcW - cropWInt)).toInt();
    final cropYInt =
        cropY.round().clamp(0, math.max(0, srcH - cropHInt)).toInt();

    img.Image cropped = img.copyCrop(
      oriented,
      x: cropXInt,
      y: cropYInt,
      width: cropWInt,
      height: cropHInt,
    );

    return _writeProcessedPhoto(cropped);
  }

  Future<File> _processPhoto(File source) async {
    final bytes = await source.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return source;
    return _writeProcessedPhoto(img.bakeOrientation(decoded));
  }

  Future<File> _writeProcessedPhoto(img.Image image) async {
    var output = image;
    // Resize ke max long-side 2160 kalau perlu. Cek mana dimensi
    // terbesar (height untuk portrait/square, width untuk landscape).
    final longSide =
        output.width > output.height ? output.width : output.height;
    if (longSide > _maxLongSide) {
      if (output.height >= output.width) {
        output = img.copyResize(
          output,
          height: _maxLongSide,
          interpolation: img.Interpolation.linear,
        );
      } else {
        output = img.copyResize(
          output,
          width: _maxLongSide,
          interpolation: img.Interpolation.linear,
        );
      }
    }

    final jpegBytes = img.encodeJpg(output, quality: _jpegQuality);
    final tmpDir = await getTemporaryDirectory();
    final ts = DateTime.now().microsecondsSinceEpoch;
    final out = File(
      '${tmpDir.path}${Platform.pathSeparator}natalo_crop_$ts.jpg',
    );
    await out.writeAsBytes(jpegBytes, flush: true);
    return out;
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
      if (file == null) throw 'no_file';
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
      _showToast(
        error is String
            ? error
            : 'File belum bisa diproses. Coba pilih media lain.',
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
        MaterialPageRoute(
          builder: (_) => FeedNewPostScreen(
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
    // Video > 60 dtk → masuk Trim Video. <= 60 dtk → masuk Preview/Detail.
    final needsTrim = duration.inSeconds > maxVideoDurationSeconds;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => needsTrim
            ? FeedVideoTrimScreen(draft: draft, returnResultOnNext: true)
            : FeedVideoPreviewScreen(draft: draft),
      ),
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
        // ── Preview area 75% × fixed 4:5 ──
        // Diagonal button overlay toggle cover/fill <-> contain/fit,
        // seperti Instagram picker.
        SliverToBoxAdapter(child: _buildPreview()),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final previewWidth = screenWidth * 0.75;
        return Center(
          child: SizedBox(
            width: previewWidth,
            child: AspectRatio(
              // Frame tetap 4:5; yang berubah hanya fit image di dalamnya.
              aspectRatio: _previewAspect,
              child: ClipRRect(
                borderRadius: BorderRadius.zero,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildPreviewContent(),
                    // Floating fit/fill toggle bottom-left — visible saat mode
                    // foto. Tap = cover <-> contain.
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
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Toggle preview image fitting: default cover/fill, tap icon diagonal
  /// untuk contain/fit supaya foto terlihat utuh di frame 4:5 yang sama.
  void _togglePreviewFit() {
    AppHaptics.tap();
    setState(() => _previewFitOriginal = !_previewFitOriginal);
  }

  _PhotoCropTransform _getPhotoCropTransform(String assetId) {
    return _photoCropTransforms.putIfAbsent(assetId, _PhotoCropTransform.new);
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
          if (!ready)
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
          if (_previewDurationSec != null && _previewDurationSec! > 0)
            Positioned(
              right: 10,
              bottom: 10,
              child: _DurationBadge(seconds: _previewDurationSec!),
            ),
        ],
      );
    }
    // Photo preview — Instagram-style fit/fill toggle.
    // - Default cover/fill: foto memenuhi frame 4:5.
    // - Tap icon diagonal: contain/fit, foto terlihat utuh.
    // - Dalam mode fill, user bisa pinch/drag dan hasil upload mengikuti crop.
    if (_previewPath != null) {
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: _PhotoCropPreview(
          key: ValueKey(
            '${asset.id}-${_previewFitOriginal ? 'fit' : 'fill'}',
          ),
          file: File(_previewPath!),
          fitOriginal: _previewFitOriginal,
          cropTransform: _getPhotoCropTransform(asset.id),
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
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, color: _textWhite, size: 26),
          ),
          const Expanded(
            child: Text(
              'Buat Postingan',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _textWhite,
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          TextButton(
            onPressed: canProceed ? onNext : null,
            child: Text(
              'Next',
              style: TextStyle(
                color: canProceed ? _natoloBlue : _textMuted,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
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
    return Container(
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
      child: Text(
        '$mm:$ss',
        style: const TextStyle(
          color: _textWhite,
          fontSize: 10,
          fontWeight: FontWeight.w900,
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

class _PhotoCropPreview extends StatefulWidget {
  final File file;
  final bool fitOriginal;
  final _PhotoCropTransform cropTransform;

  const _PhotoCropPreview({
    super.key,
    required this.file,
    required this.fitOriginal,
    required this.cropTransform,
  });

  @override
  State<_PhotoCropPreview> createState() => _PhotoCropPreviewState();
}

class _PhotoCropPreviewState extends State<_PhotoCropPreview> {
  Size? _imageSize;
  double _startScale = 1;
  Offset _startOffsetFraction = Offset.zero;

  @override
  void initState() {
    super.initState();
    _loadImageSize();
  }

  @override
  void didUpdateWidget(covariant _PhotoCropPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path) {
      _imageSize = null;
      _loadImageSize();
    }
  }

  Future<void> _loadImageSize() async {
    try {
      final bytes = await widget.file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null || !mounted) return;
      final oriented = img.bakeOrientation(decoded);
      setState(() {
        _imageSize = Size(
          oriented.width.toDouble(),
          oriented.height.toDouble(),
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _imageSize = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _bgBlack,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final frameSize = Size(
            constraints.maxWidth,
            constraints.maxHeight,
          );

          if (widget.fitOriginal) {
            return Image.file(
              widget.file,
              fit: BoxFit.contain,
              alignment: Alignment.center,
            );
          }

          final imageSize = _imageSize;
          if (imageSize == null ||
              frameSize.width <= 0 ||
              frameSize.height <= 0) {
            return Image.file(
              widget.file,
              fit: BoxFit.cover,
              alignment: Alignment.center,
            );
          }

          final coverScale = math.max(
            frameSize.width / imageSize.width,
            frameSize.height / imageSize.height,
          );
          final baseSize = Size(
            imageSize.width * coverScale,
            imageSize.height * coverScale,
          );
          final scale = widget.cropTransform.scale.clamp(1.0, 4.0).toDouble();
          final offsetPx = Offset(
            widget.cropTransform.offsetFraction.dx * frameSize.width,
            widget.cropTransform.offsetFraction.dy * frameSize.height,
          );
          final renderOffset = _clampOffsetPx(
            offsetPx,
            frameSize,
            baseSize,
            scale,
          );

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: (_) {
              _startScale = widget.cropTransform.scale;
              _startOffsetFraction = widget.cropTransform.offsetFraction;
            },
            onScaleUpdate: (details) {
              final nextScale =
                  (_startScale * details.scale).clamp(1.0, 4.0).toDouble();
              final startOffsetPx = Offset(
                _startOffsetFraction.dx * frameSize.width,
                _startOffsetFraction.dy * frameSize.height,
              );
              final nextOffsetPx = _clampOffsetPx(
                startOffsetPx + details.focalPointDelta,
                frameSize,
                baseSize,
                nextScale,
              );

              setState(() {
                widget.cropTransform.scale = nextScale;
                widget.cropTransform.offsetFraction = Offset(
                  nextOffsetPx.dx / frameSize.width,
                  nextOffsetPx.dy / frameSize.height,
                );
              });
            },
            onDoubleTap: () {
              setState(() {
                widget.cropTransform.scale = 1;
                widget.cropTransform.offsetFraction = Offset.zero;
              });
            },
            child: ClipRect(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Transform.translate(
                    offset: renderOffset,
                    child: Transform.scale(
                      scale: scale,
                      child: SizedBox(
                        width: baseSize.width,
                        height: baseSize.height,
                        child: Image.file(
                          widget.file,
                          fit: BoxFit.fill,
                          alignment: Alignment.center,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Offset _clampOffsetPx(
    Offset offset,
    Size frameSize,
    Size baseSize,
    double scale,
  ) {
    final maxDx = math.max(0.0, (baseSize.width * scale - frameSize.width) / 2);
    final maxDy =
        math.max(0.0, (baseSize.height * scale - frameSize.height) / 2);
    return Offset(
      offset.dx.clamp(-maxDx, maxDx).toDouble(),
      offset.dy.clamp(-maxDy, maxDy).toDouble(),
    );
  }
}

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

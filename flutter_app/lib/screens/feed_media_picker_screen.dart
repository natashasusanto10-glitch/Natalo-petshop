// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
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
        orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)],
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
    final file = await asset.file;
    if (!mounted || file == null) return;
    final path = file.path;
    setState(() {
      _previewAsset = asset;
      _previewPath = path;
      _previewType = isVideo ? FeedPostContentType.video : FeedPostContentType.image;
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
    final next = List<SelectedMediaItem>.from(_selectedPhotos)
      ..removeAt(index);
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
      final files = _selectedPhotos.map((item) => File(item.localPath)).toList();
      // Pause video preview while we navigate.
      await _videoController?.pause();
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => FeedNewPostScreen(
            draft: NewPostMediaDraft.photos(files),
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
        // ── Helper hint top ──
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Text(
              'Pilih foto atau video dari galeri kamu untuk membuat postingan.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _textMuted,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        // ── Preview area 75% × 3:4 ──
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
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
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
                  icon: const Icon(Icons.collections_outlined, size: 16),
                  label: const Text('Album'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _textWhite,
                    side: const BorderSide(color: Color(0xFF4B5563)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 2, 20, 12),
            child: Text(
              'Maksimal 8 foto • Video hanya bisa dipilih 1',
              style: TextStyle(
                color: _textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
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
              aspectRatio: 3 / 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _buildPreviewContent(),
              ),
            ),
          ),
        );
      },
    );
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
    // Photo preview.
    if (_previewPath != null) {
      return Image.file(File(_previewPath!), fit: BoxFit.cover);
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
                fontSize: 16,
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
    final idx = widget.selectedPhotos.indexWhere((p) => p.id == widget.asset.id);
    return idx >= 0 ? idx + 1 : null;
  }

  bool get _isDimmed {
    final mode = widget.mode;
    if (mode == null) return false;
    if (mode == FeedPostContentType.image && _isVideo) return true;
    if (mode == FeedPostContentType.video && !_isVideo && widget.selectedVideo != null) {
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
                : Image.memory(_thumb!, fit: BoxFit.cover),
          ),
          if (_isDimmed)
            Container(color: Colors.black.withValues(alpha: 0.45)),
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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

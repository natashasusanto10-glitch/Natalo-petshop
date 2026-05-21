import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../models/feed_create_post_draft.dart';
import '../utils/haptics.dart';
import 'feed_new_post_screen.dart';
import 'feed_video_upload_flow.dart';

const int maxPhotoCarouselItems = 8;
const int minVideoDurationSeconds = 1;
const int maxVideoDurationSeconds = 45;

enum FeedPostContentType {
  image,
  video,
}

class SelectedMediaItem {
  final String id;
  final String localPath;
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
}

class FeedMediaPickerScreen extends StatefulWidget {
  const FeedMediaPickerScreen({super.key});

  @override
  State<FeedMediaPickerScreen> createState() => _FeedMediaPickerScreenState();
}

class _FeedMediaPickerScreenState extends State<FeedMediaPickerScreen> {
  final _picker = ImagePicker();
  final _pageController = PageController();

  List<SelectedMediaItem> _selectedPhotos = const [];
  SelectedMediaItem? _selectedVideo;
  FeedPostContentType _mode = FeedPostContentType.image;
  bool _busy = false;
  String? _toastMessage;

  bool get _hasSelection => _mode == FeedPostContentType.image
      ? _selectedPhotos.isNotEmpty
      : _selectedVideo != null;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    if (_busy) return;
    AppHaptics.tap();
    setState(() {
      _busy = true;
      _toastMessage = null;
    });

    try {
      final picked = await _picker.pickMultiImage(
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1920,
        limit: maxPhotoCarouselItems,
      );
      if (picked.isEmpty) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final limited = picked.take(maxPhotoCarouselItems).toList();
      if (picked.length > maxPhotoCarouselItems) {
        _showInlineToast('Maksimal 8 foto untuk satu postingan.');
        AppHaptics.warning();
      }
      if (!mounted) return;
      setState(() {
        _selectedPhotos = List.generate(limited.length, (index) {
          return SelectedMediaItem(
            id: '${DateTime.now().microsecondsSinceEpoch}-$index',
            localPath: limited[index].path,
            contentType: FeedPostContentType.image,
            orderIndex: index,
          );
        });
        _busy = false;
      });
      if (_selectedPhotos.length > 1) {
        _pageController.jumpToPage(0);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showInlineToast('File belum bisa diproses. Coba pilih media lain.');
      AppHaptics.warning();
    }
  }

  Future<void> _pickVideo() async {
    if (_busy) return;
    AppHaptics.tap();
    setState(() {
      _busy = true;
      _toastMessage = null;
      _mode = FeedPostContentType.video;
    });

    try {
      final picked = await _picker.pickVideo(source: ImageSource.gallery);
      if (picked == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final localPath = await _copyVideoToCache(picked.path);
      final duration = await _readVideoDuration(localPath);
      if (duration.inSeconds < minVideoDurationSeconds) {
        throw const _MediaPickerException(
          'Video terlalu pendek. Pilih video minimal 1 detik.',
        );
      }
      final thumbnailPath = await _generateVideoThumbnail(localPath);
      if (!mounted) return;
      setState(() {
        _selectedVideo = SelectedMediaItem(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          localPath: localPath,
          contentType: FeedPostContentType.video,
          thumbnailPath: thumbnailPath,
          durationSeconds: duration.inSeconds,
          orderIndex: 0,
        );
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showInlineToast(
        error is _MediaPickerException
            ? error.message
            : 'File belum bisa diproses. Coba pilih media lain.',
      );
      AppHaptics.warning();
    }
  }

  Future<void> _next() async {
    if (!_hasSelection || _busy) return;
    AppHaptics.tap();
    if (_mode == FeedPostContentType.image) {
      final files =
          _selectedPhotos.map((item) => File(item.localPath)).toList();
      final result = await Navigator.push(
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
    final navigator = Navigator.of(context);
    final duration = Duration(seconds: video.durationSeconds ?? 0);
    final fileSizeBytes = await File(video.localPath).length();
    if (!mounted) return;
    final draft = FeedCreatePostDraft(
      originalVideoPath: video.localPath,
      localVideoPath: video.localPath,
      thumbnailPath: video.thumbnailPath,
      originalDuration: duration,
      fileSizeBytes: fileSizeBytes,
      originalFilename: video.localPath.split(RegExp(r'[\\/]')).last,
      mimeType: _videoMimeType(video.localPath, null),
    );
    final result = await navigator.push(
      MaterialPageRoute(
        builder: (_) => FeedVideoPreviewScreen(draft: draft),
      ),
    );
    if (result == true && mounted) Navigator.pop(context, true);
  }

  void _removePhoto(int index) {
    AppHaptics.selection();
    setState(() {
      final next = List<SelectedMediaItem>.from(_selectedPhotos)
        ..removeAt(index);
      _selectedPhotos = List.generate(next.length, (i) {
        final item = next[i];
        return SelectedMediaItem(
          id: item.id,
          localPath: item.localPath,
          contentType: item.contentType,
          thumbnailPath: item.thumbnailPath,
          durationSeconds: item.durationSeconds,
          orderIndex: i,
        );
      });
    });
  }

  void _switchMode(FeedPostContentType mode) {
    if (_mode == mode) return;
    AppHaptics.selection();
    setState(() {
      _mode = mode;
      _toastMessage = null;
    });
  }

  void _showInlineToast(String message) {
    if (!mounted) return;
    setState(() => _toastMessage = message);
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (!mounted || _toastMessage != message) return;
      setState(() => _toastMessage = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final photos = _selectedPhotos;
    final video = _selectedVideo;
    final isPhotoMode = _mode == FeedPostContentType.image;

    return Scaffold(
      backgroundColor: const Color(0xFF04070D),
      body: SafeArea(
        child: Column(
          children: [
            _MediaPickerHeader(
              nextEnabled: _hasSelection && !_busy,
              busy: _busy,
              onClose: () => Navigator.pop(context, false),
              onNext: _next,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  _MediaPreview(
                    mode: _mode,
                    photos: photos,
                    video: video,
                    pageController: _pageController,
                    onRemovePhoto: _removePhoto,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Terbaru',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _busy
                            ? null
                            : isPhotoMode
                                ? _pickPhotos
                                : _pickVideo,
                        icon: const Icon(
                          Icons.add_photo_alternate_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_toastMessage != null) ...[
                    _PickerToast(message: _toastMessage!),
                    const SizedBox(height: 12),
                  ],
                  _SelectedMediaGrid(
                    mode: _mode,
                    photos: photos,
                    video: video,
                    busy: _busy,
                    onPickPhotos: _pickPhotos,
                    onPickVideo: _pickVideo,
                    onRemovePhoto: _removePhoto,
                  ),
                ],
              ),
            ),
            _ModeTabs(
              mode: _mode,
              onChanged: _switchMode,
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaPickerHeader extends StatelessWidget {
  final bool nextEnabled;
  final bool busy;
  final VoidCallback onClose;
  final VoidCallback onNext;

  const _MediaPickerHeader({
    required this.nextEnabled,
    required this.busy,
    required this.onClose,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: busy ? null : onClose,
              icon: const Icon(
                Icons.close_rounded,
                color: Colors.white,
                size: 32,
              ),
            ),
          ),
          const Text(
            'Buat Postingan',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: nextEnabled ? onNext : null,
              child: Text(
                busy ? '...' : 'Next',
                style: TextStyle(
                  color: nextEnabled
                      ? const Color(0xFF4B8BFF)
                      : Colors.white.withValues(alpha: 0.32),
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaPreview extends StatelessWidget {
  final FeedPostContentType mode;
  final List<SelectedMediaItem> photos;
  final SelectedMediaItem? video;
  final PageController pageController;
  final ValueChanged<int> onRemovePhoto;

  const _MediaPreview({
    required this.mode,
    required this.photos,
    required this.video,
    required this.pageController,
    required this.onRemovePhoto,
  });

  @override
  Widget build(BuildContext context) {
    final isPhoto = mode == FeedPostContentType.image;
    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF101725), Color(0xFF05070D)],
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (isPhoto && photos.isNotEmpty)
                PageView.builder(
                  controller: pageController,
                  itemCount: photos.length,
                  itemBuilder: (context, index) {
                    return Image.file(
                      File(photos[index].localPath),
                      fit: BoxFit.cover,
                    );
                  },
                )
              else if (!isPhoto && video?.thumbnailPath != null)
                Image.file(
                  File(video!.thumbnailPath!),
                  fit: BoxFit.cover,
                )
              else
                Center(
                  child: Icon(
                    isPhoto
                        ? Icons.photo_library_outlined
                        : Icons.videocam_outlined,
                    color: Colors.white.withValues(alpha: 0.38),
                    size: 72,
                  ),
                ),
              if (!isPhoto && video != null)
                Center(
                  child: Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.42),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 42,
                    ),
                  ),
                ),
              if (!isPhoto && video?.durationSeconds != null)
                Positioned(
                  right: 14,
                  bottom: 14,
                  child: _DurationBadge(
                    seconds: video!.durationSeconds!,
                  ),
                ),
              if (isPhoto && photos.length > 1)
                Positioned(
                  top: 12,
                  right: 12,
                  child: _CountBadge(text: '${photos.length}/8'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedMediaGrid extends StatelessWidget {
  final FeedPostContentType mode;
  final List<SelectedMediaItem> photos;
  final SelectedMediaItem? video;
  final bool busy;
  final VoidCallback onPickPhotos;
  final VoidCallback onPickVideo;
  final ValueChanged<int> onRemovePhoto;

  const _SelectedMediaGrid({
    required this.mode,
    required this.photos,
    required this.video,
    required this.busy,
    required this.onPickPhotos,
    required this.onPickVideo,
    required this.onRemovePhoto,
  });

  @override
  Widget build(BuildContext context) {
    final isPhoto = mode == FeedPostContentType.image;
    final items = isPhoto ? photos : [if (video != null) video!];
    final itemCount = items.length + 1;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 3,
        mainAxisSpacing: 3,
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _PickTile(
            label: isPhoto ? 'Galeri' : 'Video',
            icon: isPhoto
                ? Icons.photo_library_rounded
                : Icons.video_library_rounded,
            busy: busy,
            onTap: isPhoto ? onPickPhotos : onPickVideo,
          );
        }
        final item = items[index - 1];
        return _MediaGridTile(
          item: item,
          order: isPhoto ? index : null,
          onRemove: isPhoto ? () => onRemovePhoto(index - 1) : null,
        );
      },
    );
  }
}

class _PickTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool busy;
  final VoidCallback onTap;

  const _PickTile({
    required this.label,
    required this.icon,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF111827),
      child: InkWell(
        onTap: busy ? null : onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            busy
                ? const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Color(0xFF4B8BFF),
                    ),
                  )
                : Icon(icon, color: const Color(0xFF4B8BFF), size: 34),
            const SizedBox(height: 8),
            Text(
              busy ? 'Memuat...' : label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaGridTile extends StatelessWidget {
  final SelectedMediaItem item;
  final int? order;
  final VoidCallback? onRemove;

  const _MediaGridTile({
    required this.item,
    this.order,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final isVideo = item.contentType == FeedPostContentType.video;
    final path = item.thumbnailPath ?? item.localPath;
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.file(
          File(path),
          fit: BoxFit.cover,
        ),
        if (order != null)
          Positioned(
            top: 6,
            right: 6,
            child: _OrderBadge(order: order!),
          ),
        if (isVideo)
          const Positioned(
            top: 6,
            right: 6,
            child: Icon(
              Icons.videocam_rounded,
              color: Colors.white,
              size: 21,
              shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
            ),
          ),
        if (onRemove != null)
          Positioned(
            left: 6,
            top: 6,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.62),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ModeTabs extends StatelessWidget {
  final FeedPostContentType mode;
  final ValueChanged<FeedPostContentType> onChanged;

  const _ModeTabs({
    required this.mode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFF10151F),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            _ModeTabButton(
              label: 'FOTO',
              active: mode == FeedPostContentType.image,
              onTap: () => onChanged(FeedPostContentType.image),
            ),
            _ModeTabButton(
              label: 'VIDEO',
              active: mode == FeedPostContentType.video,
              onTap: () => onChanged(FeedPostContentType.video),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeTabButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ModeTabButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? const Color(0xFF1E5BFF) : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(
            label,
            style: TextStyle(
              color:
                  active ? Colors.white : Colors.white.withValues(alpha: 0.6),
              fontSize: 15,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _OrderBadge extends StatelessWidget {
  final int order;

  const _OrderBadge({required this.order});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Color(0xFF2F6BFF),
        shape: BoxShape.circle,
      ),
      child: Text(
        '$order',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final String text;

  const _CountBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF2F6BFF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _DurationBadge extends StatelessWidget {
  final int seconds;

  const _DurationBadge({required this.seconds});

  @override
  Widget build(BuildContext context) {
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$minutes:${rest.toString().padLeft(2, '0')}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _PickerToast extends StatelessWidget {
  final String message;

  const _PickerToast({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<String> _copyVideoToCache(String sourcePath) async {
  final cacheDir = await getTemporaryDirectory();
  final extension = _extensionFor(sourcePath, fallback: 'mp4');
  final output =
      '${cacheDir.path}${Platform.pathSeparator}natalo-feed-${DateTime.now().microsecondsSinceEpoch}.$extension';
  return File(sourcePath).copy(output).then((file) => file.path);
}

Future<Duration> _readVideoDuration(String path) async {
  final controller = VideoPlayerController.file(File(path));
  try {
    await controller.initialize();
    return controller.value.duration;
  } finally {
    await controller.dispose();
  }
}

Future<String?> _generateVideoThumbnail(String path) async {
  final tempDir = await getTemporaryDirectory();
  return VideoThumbnail.thumbnailFile(
    video: path,
    thumbnailPath: tempDir.path,
    imageFormat: ImageFormat.JPEG,
    maxWidth: 720,
    timeMs: 500,
    quality: 82,
  );
}

String _videoMimeType(String path, String? mime) {
  if (mime == 'video/mp4' ||
      mime == 'video/webm' ||
      mime == 'video/quicktime') {
    return mime!;
  }
  final lower = path.toLowerCase();
  if (lower.endsWith('.mov')) return 'video/quicktime';
  if (lower.endsWith('.webm')) return 'video/webm';
  return 'video/mp4';
}

String _extensionFor(String path, {required String fallback}) {
  final name = path.split(RegExp(r'[\\/]')).last;
  final dot = name.lastIndexOf('.');
  if (dot == -1 || dot == name.length - 1) return fallback;
  return name.substring(dot + 1).toLowerCase();
}

class _MediaPickerException implements Exception {
  final String message;

  const _MediaPickerException(this.message);
}

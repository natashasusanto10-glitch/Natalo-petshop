import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../models/feed_create_post_draft.dart';
import '../models/product.dart';
import '../services/api_client.dart';
import '../services/bunny_upload_service.dart';
import '../services/feed_service.dart';
import '../services/product_service.dart';
import '../services/video_compress_gate.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import '../widgets/app_product_image.dart';
import 'feed_new_post_screen.dart';

const _feedUploadBlue = Color(0xFF1E5BFF);
const _feedUploadBg = Color(0xFF05070D);
const _feedUploadCard = Color(0xFF11141B);
const _feedUploadBorder = Color(0xFF252A35);
const _feedUploadText = Color(0xFFFFFFFF);
const _feedUploadMuted = Color(0xFFAEB7C7);

/// Max video size yang user boleh pick dari galeri/kamera.
/// 200MB cukup untuk 1080p 60s @ 25Mbps bitrate (typical iPhone source).
/// Compression akan turunkan jadi ~5-15MB sebelum upload ke Bunny.
const _maxFeedVideoBytes = 200 * 1024 * 1024;
const _minFeedVideoSeconds = 1;
const _maxFeedVideoSeconds = 60;

class FeedVideoStartScreen extends StatefulWidget {
  const FeedVideoStartScreen({super.key});

  @override
  State<FeedVideoStartScreen> createState() => _FeedVideoStartScreenState();
}

class _FeedVideoStartScreenState extends State<FeedVideoStartScreen> {
  final _picker = ImagePicker();
  bool _busy = false;
  String? _error;
  String _stage = '';

  Future<void> _pick(ImageSource source) async {
    if (_busy) return;
    AppHaptics.tap();
    setState(() {
      _busy = true;
      _error = null;
      _stage = source == ImageSource.camera
          ? 'Membuka kamera...'
          : 'Membuka galeri...';
    });

    try {
      final picked = await _picker.pickVideo(source: source);
      if (picked == null) {
        if (mounted) {
          setState(() {
            _busy = false;
            _stage = '';
          });
        }
        return;
      }

      if (!mounted) return;
      setState(() => _stage = 'Menyiapkan video...');

      final localPath = await _copyVideoToCache(picked.path);
      final localFile = File(localPath);
      final sizeBytes = await localFile.length();
      if (sizeBytes > _maxFeedVideoBytes) {
        throw _FeedVideoFlowException(
          'Video terlalu besar. Pilih video maksimal ${_formatBytes(_maxFeedVideoBytes)}.',
        );
      }

      final duration = await _readVideoDuration(localPath);
      if (duration.inMilliseconds < _minFeedVideoSeconds * 1000) {
        throw const _FeedVideoFlowException(
          'Video terlalu pendek. Pilih video minimal 1 detik.',
        );
      }

      final thumbPath = await _generateVideoThumbnail(localPath);
      final draft = FeedCreatePostDraft(
        originalVideoPath: picked.path,
        localVideoPath: localPath,
        thumbnailPath: thumbPath,
        originalDuration: duration,
        fileSizeBytes: sizeBytes,
        originalFilename: picked.name,
        mimeType: _videoMimeType(picked.path, picked.mimeType),
      );

      if (!mounted) return;
      setState(() {
        _busy = false;
        _stage = '';
      });

      if (duration.inSeconds > _maxFeedVideoSeconds) {
        AppHaptics.selection();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Video lebih dari 60 detik. Pilih bagian terbaik untuk digunakan.',
            ),
          ),
        );
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FeedVideoTrimScreen(draft: draft),
          ),
        );
        return;
      }

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FeedVideoPreviewScreen(draft: draft),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _stage = '';
        _error = error is _FeedVideoFlowException
            ? error.message
            : 'Video tidak bisa dibuka. Pilih video lain.';
      });
      AppHaptics.warning();
    }
  }

  @override
  Widget build(BuildContext context) {
    return _DarkUploadScaffold(
      title: 'Pilih Video',
      leading: Icons.close_rounded,
      onLeading: () => Navigator.pop(context, false),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: _StartPlaceholder(stage: _stage),
            ),
          ),
          if (_error != null) ...[
            _DarkErrorBox(message: _error!),
            const SizedBox(height: 14),
          ],
          _PrimaryUploadButton(
            label: _busy ? 'Menyiapkan...' : 'Pilih Video',
            icon: Icons.video_library_rounded,
            enabled: !_busy,
            onPressed: () => _pick(ImageSource.gallery),
          ),
          const SizedBox(height: 12),
          _SecondaryUploadButton(
            label: 'Rekam dari Kamera',
            icon: Icons.photo_camera_rounded,
            enabled: !_busy,
            onPressed: () => _pick(ImageSource.camera),
          ),
        ],
      ),
    );
  }
}

class FeedVideoPreviewScreen extends StatefulWidget {
  final FeedCreatePostDraft draft;

  const FeedVideoPreviewScreen({super.key, required this.draft});

  @override
  State<FeedVideoPreviewScreen> createState() => _FeedVideoPreviewScreenState();
}

class _FeedVideoPreviewScreenState extends State<FeedVideoPreviewScreen> {
  VideoPlayerController? _controller;
  bool _loading = true;
  bool _playing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initVideo() async {
    final path = widget.draft.localVideoPath;
    if (path == null) {
      setState(() {
        _loading = false;
        _error = 'Video tidak bisa dibuka. Pilih video lain.';
      });
      return;
    }
    final controller = VideoPlayerController.file(File(path));
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      controller.addListener(_syncPlaying);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _loading = false;
      });
    } catch (_) {
      await controller.dispose();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Video belum bisa dipreview. Pilih video lain.';
      });
    }
  }

  void _syncPlaying() {
    final playing = _controller?.value.isPlaying ?? false;
    if (mounted && playing != _playing) {
      setState(() => _playing = playing);
    }
  }

  Future<void> _togglePlay() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    AppHaptics.tap();
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
  }

  Future<void> _next() async {
    final duration = widget.draft.originalDuration ?? Duration.zero;
    if (duration.inSeconds > _maxFeedVideoSeconds) {
      AppHaptics.warning();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Video lebih dari 60 detik. Edit video untuk memilih bagian terbaik.',
          ),
        ),
      );
      return;
    }
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
  }

  @override
  Widget build(BuildContext context) {
    final duration = widget.draft.originalDuration ?? Duration.zero;
    final mustEditVideo = duration.inSeconds > _maxFeedVideoSeconds;
    return _DarkUploadScaffold(
      title: 'Preview Video',
      leading: Icons.close_rounded,
      onLeading: () => Navigator.pop(context),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _VideoPreviewStage(
                  controller: _controller,
                  thumbnailPath: widget.draft.thumbnailPath,
                  loading: _loading,
                  playing: _playing,
                  onTap: _togglePlay,
                ),
                const SizedBox(height: 16),
                _InfoPanel(
                  title: 'Durasi video yang dipilih',
                  value: _formatDuration(widget.draft.originalDuration),
                ),
                if (mustEditVideo) ...[
                  const SizedBox(height: 14),
                  const _DarkErrorBox(
                    message:
                        'Video lebih dari 60 detik. Edit video untuk memilih bagian terbaik.',
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  _DarkErrorBox(message: _error!),
                ],
              ],
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _SecondaryUploadButton(
                  label: 'Edit Video',
                  icon: Icons.content_cut_rounded,
                  enabled: !_loading && _error == null,
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    await _controller?.pause();
                    if (!mounted) return;
                    await navigator.push(
                      MaterialPageRoute(
                        builder: (_) =>
                            FeedVideoTrimScreen(draft: widget.draft),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PrimaryUploadButton(
                  label: 'Next',
                  icon: Icons.arrow_forward_rounded,
                  enabled: !_loading && _error == null && !mustEditVideo,
                  onPressed: _next,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class FeedVideoTrimScreen extends StatefulWidget {
  final FeedCreatePostDraft draft;
  final bool returnResultOnNext;

  const FeedVideoTrimScreen({
    super.key,
    required this.draft,
    this.returnResultOnNext = false,
  });

  @override
  State<FeedVideoTrimScreen> createState() => _FeedVideoTrimScreenState();
}

class _FeedVideoTrimScreenState extends State<FeedVideoTrimScreen> {
  VideoPlayerController? _controller;
  RangeValues _range = RangeValues(0, _maxFeedVideoSeconds.toDouble());
  bool _loading = true;
  bool _exporting = false;
  bool _playing = false;
  String? _error;
  Timer? _playbackGuard;
  // Job kompresi milik layar ini — dipakai untuk cancel ber-scope di
  // dispose (JANGAN cancelCompression global: bisa bunuh kompresi milik
  // background upload store).
  VideoCompressJob? _exportJob;
  // Extracted frames untuk timeline thumbnails — IG-style.
  // Diisi setelah video controller init, parallel sambil show fallback.
  List<Uint8List?> _frameThumbs = const [];
  static const _frameCount = 10;

  Duration get _duration => widget.draft.originalDuration ?? Duration.zero;

  @override
  void initState() {
    super.initState();
    _range = RangeValues(
      0,
      math.min(
        _maxFeedVideoSeconds.toDouble(),
        math.max(1, _duration.inMilliseconds / 1000),
      ),
    );
    _initVideo();
  }

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

  Future<void> _initVideo() async {
    final path = widget.draft.localVideoPath;
    if (path == null) {
      setState(() {
        _loading = false;
        _error = 'Video tidak bisa dibuka. Pilih video lain.';
      });
      return;
    }
    final controller = VideoPlayerController.file(File(path));
    try {
      await controller.initialize();
      // IG-style: looping AUTO sambil trim. Loop manual lewat playback
      // guard ke range.start saat reach range.end.
      await controller.setLooping(false);
      await controller.setVolume(0);
      controller.addListener(_syncPlaying);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _loading = false;
      });
      // Auto-start playback in trim window (IG-style: video selalu jalan).
      await controller
          .seekTo(Duration(milliseconds: (_range.start * 1000).round()));
      await controller.play();
      _startPlaybackGuard();
      // Extract frame thumbnails parallel (non-blocking).
      unawaited(_extractFrameThumbnails(path));
    } catch (_) {
      await controller.dispose();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Video belum bisa dipreview. Pilih video lain.';
      });
    }
  }

  /// Extract N frames distributed evenly across video duration. Dipakai
  /// untuk render timeline scrubber yang menggambarkan isi video (IG-style).
  Future<void> _extractFrameThumbnails(String videoPath) async {
    final durationMs = _duration.inMilliseconds;
    if (durationMs <= 0) return;
    final frames = List<Uint8List?>.filled(_frameCount, null);
    for (var i = 0; i < _frameCount; i++) {
      // Distribute timestamps: i / (N-1) supaya frame pertama = 0,
      // frame terakhir = durationMs.
      final tMs = ((durationMs * i) / (_frameCount - 1)).round();
      try {
        final bytes = await VideoThumbnail.thumbnailData(
          video: videoPath,
          imageFormat: ImageFormat.JPEG,
          quality: 50,
          maxWidth: 120,
          timeMs: tMs,
        );
        if (!mounted) return;
        frames[i] = bytes;
        setState(() => _frameThumbs = List<Uint8List?>.from(frames));
      } catch (_) {
        // Skip frame yang gagal extract.
      }
    }
  }

  void _syncPlaying() {
    final playing = _controller?.value.isPlaying ?? false;
    if (mounted && _playing != playing) {
      setState(() => _playing = playing);
    }
  }

  void _updateRange(RangeValues values, {required bool dragging}) {
    final old = _range;
    final total = math.max(1.0, _duration.inMilliseconds / 1000);
    var start = values.start.clamp(0.0, total - 1);
    var end = values.end.clamp(start + 1, total);
    final movedStart =
        (values.start - old.start).abs() > (values.end - old.end).abs();

    if (end - start > _maxFeedVideoSeconds) {
      if (movedStart) {
        end = math.min(total, start + _maxFeedVideoSeconds);
      } else {
        start = math.max(0, end - _maxFeedVideoSeconds);
      }
    }
    if (end - start < _minFeedVideoSeconds) {
      if (movedStart) {
        start = math.max(0, end - _minFeedVideoSeconds);
      } else {
        end = math.min(total, start + _minFeedVideoSeconds);
      }
    }

    setState(() => _range = RangeValues(start.toDouble(), end.toDouble()));

    // Live seek to handle position untuk preview — IG-style. Saat user
    // drag start handle, seek ke start. Saat drag end handle, seek ke
    // end. Saat user release, restart loop dari new range.start.
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final seekTo = movedStart ? start : end;
    controller.seekTo(Duration(milliseconds: (seekTo * 1000).round()));
    if (dragging) {
      // Sambil drag, pause supaya frame stabil di posisi handle.
      controller.pause();
    } else {
      // Release: lanjut auto-loop dari new range.start.
      controller.seekTo(Duration(milliseconds: (start * 1000).round()));
      controller.play();
      _startPlaybackGuard();
    }
  }

  void _startPlaybackGuard() {
    _playbackGuard?.cancel();
    _playbackGuard = Timer.periodic(const Duration(milliseconds: 120), (_) {
      final ctrl = _controller;
      if (ctrl == null || !ctrl.value.isInitialized || !ctrl.value.isPlaying) {
        return;
      }
      final posSec = ctrl.value.position.inMilliseconds / 1000;
      if (posSec >= _range.end) {
        ctrl.seekTo(Duration(milliseconds: (_range.start * 1000).round()));
      }
    });
  }

  Future<void> _exportTrim() async {
    // `_error != null` sengaja TIDAK memblokir — saat error, tap Next =
    // retry. setState di bawah meng-clear error lama.
    if (_exporting) return;
    final source = widget.draft.localVideoPath;
    if (source == null) return;
    final selectedSeconds = (_range.end - _range.start).round();
    if (selectedSeconds < _minFeedVideoSeconds ||
        selectedSeconds > _maxFeedVideoSeconds) {
      setState(() {
        _error = 'Pilih durasi antara 1 sampai 60 detik.';
      });
      return;
    }

    AppHaptics.tap();
    await _controller?.pause();
    setState(() {
      _exporting = true;
      _error = null;
    });

    try {
      // 720p compression — match IG upload spec + cocok untuk mobile feed
      // viewport (<6" screen). Bunny Stream tetap re-encode multi-variant
      // (240p/360p/480p/720p) untuk adaptive streaming. Dropped dari 1080p
      // karena 60s video di 1080p = ~50-60MB (sering gagal di koneksi
      // mobile / saat user matikan layar mid-upload), sedangkan 720p =
      // ~18-22MB (3× lebih cepat upload, success rate jauh lebih tinggi).
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
        throw const _FeedVideoFlowException(
          'Video belum berhasil diproses. Coba lagi.',
        );
      }
      final outputPath = file.path;
      final thumbPath = await _generateVideoThumbnail(outputPath, timeMs: 500);
      final nextDraft = widget.draft.copyWith(
        trimmedVideoPath: outputPath,
        thumbnailPath: thumbPath ?? widget.draft.thumbnailPath,
        trimmedDuration: Duration(seconds: selectedSeconds),
        fileSizeBytes: await file.length(),
      );
      if (!mounted) return;
      setState(() => _exporting = false);
      if (widget.returnResultOnNext) {
        Navigator.pop(context, nextDraft);
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FeedNewPostScreen(
            draft: NewPostMediaDraft.video(nextDraft),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _exporting = false;
        _error = error is _FeedVideoFlowException
            ? error.message
            : 'Video belum berhasil diproses. Coba lagi.';
      });
      AppHaptics.warning();
    }
  }

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

  @override
  Widget build(BuildContext context) {
    final totalSeconds = math.max(1.0, _duration.inMilliseconds / 1000);
    final selectedDuration = Duration(
      milliseconds: ((_range.end - _range.start) * 1000).round(),
    );
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
        trailing: _RoundNextButton(
          busy: _exporting,
          // Saat _error terisi tombol TETAP aktif — tap = retry (dulu
          // disabled → dead-end: pesan "Coba lagi" tanpa cara retry).
          onTap: _loading || _exporting ? null : _exportTrim,
        ),
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _VideoPreviewStage(
                    controller: _controller,
                    thumbnailPath: widget.draft.thumbnailPath,
                    loading: _loading,
                    // IG-style: video auto-loop terus, tidak ada tap-to-toggle
                    // play/pause. `playing` cuma untuk visual indicator
                    // (kalau perlu).
                    playing: _playing,
                    onTap: null,
                    timeText:
                        '${_formatDuration(Duration(milliseconds: (_range.start * 1000).round()))} / ${_formatDuration(_duration)}',
                  ),
                  const SizedBox(height: 14),
                  _InfoPanel(
                    title: 'Durasi yang dipilih',
                    value:
                        '${_formatDuration(selectedDuration)}  •  Maksimal 60 detik',
                  ),
                  const SizedBox(height: 16),
                  _TrimTimeline(
                    frameThumbs: _frameThumbs,
                    fallbackThumbnailPath: widget.draft.thumbnailPath,
                    range: _range,
                    totalSeconds: totalSeconds,
                    onChanged: _exporting
                        ? null
                        : (values, {required bool dragging}) =>
                            _updateRange(values, dragging: dragging),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Geser pegangan untuk memangkas video',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _feedUploadMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_exporting) ...[
                    const SizedBox(height: 18),
                    const _ProcessingPanel(),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    _DarkErrorBox(message: _error!),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FeedPostDetailScreen extends StatefulWidget {
  final FeedCreatePostDraft draft;

  const FeedPostDetailScreen({super.key, required this.draft});

  @override
  State<FeedPostDetailScreen> createState() => _FeedPostDetailScreenState();
}

class _FeedPostDetailScreenState extends State<FeedPostDetailScreen> {
  late FeedCreatePostDraft _draft;
  final _productSearchController = TextEditingController();
  List<Product> _products = const [];
  final Set<String> _selectedProductIds = {};
  bool _loadingProducts = false;
  bool _showingPurchased = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _draft = widget.draft;
    _selectedProductIds.addAll(_draft.taggedProductIds);
    _loadProducts();
  }

  @override
  void dispose() {
    _productSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts([String query = '']) async {
    setState(() {
      _loadingProducts = true;
      _showingPurchased = false;
    });
    // BUGFIX(audit): tanpa try/catch, throw saat fetch (API/DB down) bikin
    // _loadingProducts stuck true → "Memuat produk..." selamanya. Catch
    // reset flag + kosongkan list (graceful), bukan stuck.
    try {
      final result = await productService.fetchProducts(
        query: query,
        limit: 12,
        inStock: true,
        hasPrice: true,
        withImage: true,
      );
      if (!mounted) return;
      setState(() {
        _products = result.products.take(12).toList();
        _loadingProducts = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _products = const [];
          _loadingProducts = false;
        });
      }
    }
  }

  Future<void> _loadPurchasedProducts() async {
    setState(() {
      _loadingProducts = true;
      _showingPurchased = true;
      _productSearchController.clear();
    });
    try {
      final pinnable = await feedService.fetchPinnableProducts();
      if (!mounted) return;
      final products = pinnable.whereType<Map>().map((p) {
      final priceRaw = p['price'] ?? p['discountPrice'] ?? 0;
      return Product(
        id: (p['productId'] ?? p['id'] ?? '').toString(),
        slug: (p['slug'] ?? '').toString(),
        title: (p['name'] ?? p['title'] ?? '').toString(),
        category: 'Pernah Dibeli',
        brand: '',
        imageUrl: (p['imageUrl'] ?? '').toString(),
        price: priceRaw is num
            ? priceRaw.toDouble()
            : double.tryParse(priceRaw.toString()) ?? 0,
        rating: p['avgRating'] is num ? (p['avgRating'] as num).toDouble() : 0,
        reviewCount:
            p['reviewCount'] is num ? (p['reviewCount'] as num).toInt() : 0,
        stock: p['stock'] is num ? (p['stock'] as num).toInt() : 0,
        description: '',
      );
      }).toList();
      setState(() {
        _products = products;
        _loadingProducts = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _products = const [];
          _loadingProducts = false;
        });
      }
    }
  }

  void _toggleProduct(Product product) {
    AppHaptics.selection();
    setState(() {
      if (_selectedProductIds.contains(product.id)) {
        _selectedProductIds.remove(product.id);
      } else if (_selectedProductIds.length < 3) {
        _selectedProductIds.add(product.id);
      } else {
        _error = 'Maksimal 3 produk yang bisa ditag.';
      }
    });
  }

  Future<void> _editVideo() async {
    final updated = await Navigator.push<FeedCreatePostDraft>(
      context,
      MaterialPageRoute(
        builder: (_) => FeedVideoTrimScreen(
          draft: _draft,
          returnResultOnNext: true,
        ),
      ),
    );
    if (updated == null || !mounted) return;
    setState(() => _draft = updated);
  }

  Future<void> _upload() async {
    final videoPath = _draft.finalVideoPath;
    if (videoPath == null || !File(videoPath).existsSync()) {
      setState(() => _error = 'Video tidak tersedia. Pilih video lagi.');
      return;
    }
    AppHaptics.tap();
    await Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => FeedUploadProgressScreen(
          draft: _draft.copyWith(
            caption: '',
            taggedProductIds: _selectedProductIds.toList(),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _DarkUploadScaffold(
      title: 'Tag Produk',
      leading: Icons.arrow_back_rounded,
      onLeading: () => Navigator.pop(context),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _DetailPreviewCard(
                  draft: _draft,
                  onEdit: _editVideo,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text('Semua Produk'),
                      selected: !_showingPurchased,
                      onSelected: (_) => _loadProducts(),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Pernah Dibeli'),
                      selected: _showingPurchased,
                      onSelected: (_) => _loadPurchasedProducts(),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _ProductTagPicker(
                  controller: _productSearchController,
                  products: _products,
                  selectedProductIds: _selectedProductIds,
                  loading: _loadingProducts,
                  enabled: !_showingPurchased,
                  onSearch: _loadProducts,
                  onSelected: _toggleProduct,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  _DarkErrorBox(message: _error!),
                ],
              ],
            ),
          ),
          _PrimaryUploadButton(
            label: 'Upload ke Feed',
            icon: Icons.cloud_upload_rounded,
            onPressed: _upload,
          ),
        ],
      ),
    );
  }
}

class FeedUploadProgressScreen extends StatefulWidget {
  final FeedCreatePostDraft draft;

  const FeedUploadProgressScreen({super.key, required this.draft});

  @override
  State<FeedUploadProgressScreen> createState() =>
      _FeedUploadProgressScreenState();
}

class _FeedUploadProgressScreenState extends State<FeedUploadProgressScreen> {
  bool _uploading = true;
  bool _started = false;
  // Single unified message — user tidak perlu tau detail internal phase
  // (compress / thumb upload / provision / TUS / finalize). Backend
  // service detail tersembunyi, cuma progress bar yang update.
  String _stage = 'Mengirim postingan...';
  int _progress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startUpload());
  }

  Future<bool> _confirmExit() async {
    if (!_uploading) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Batalkan upload?'),
        content: const Text(
          'Upload sedang berjalan. Jika keluar sekarang, kamu perlu mencoba lagi.',
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

  Future<void> _startUpload() async {
    if (_started) return;
    _started = true;
    setState(() {
      _uploading = true;
      _error = null;
      _stage = 'Mengirim postingan...';
      _progress = 0;
    });

    try {
      final originalPath = widget.draft.finalVideoPath;
      if (originalPath == null) {
        throw const _FeedVideoFlowException(
          'Video tidak tersedia. Kembali ke detail postingan.',
        );
      }

      // Two-stage compression:
      // 1. Client (HP user) — di sini, sebelum upload. Pakai
      //    video_compress Res1280x720Quality (target 720p — match IG
      //    upload spec, cocok untuk mobile feed viewport <6" screen).
      //    Tujuan: kurangi bandwidth + speed up TUS upload + tingkatkan
      //    success rate di koneksi mobile. 60s @ 1080p = ~50-60MB sering
      //    gagal, 60s @ 720p = ~18-22MB jauh lebih reliable.
      // 2. Server (Bunny Stream) — auto re-encode jadi multiple
      //    resolutions (240p/360p/480p/720p) untuk adaptive streaming.
      //    Source 720p artinya Bunny tidak generate 1080p variant — ok
      //    karena feed display capped 720p anyway.
      //
      // Kalau video sudah lewat trim screen (>60s),
      // `trimmedVideoPath` sudah hasil VideoCompress 720p — skip re-compress.
      // Kalau short video langsung dari pick (no trim), compress dulu.
      String videoPath = originalPath;
      if (widget.draft.trimmedVideoPath == null) {
        // Silent compress — user tidak perlu tau internal backend service.
        // _stage tetap "Mengirim postingan..." dari setState awal.
        try {
          final info = await videoCompressGate.compress(
            originalPath,
            quality: VideoQuality.Res1280x720Quality,
            includeAudio: true,
          );
          final compressed = info?.file;
          if (compressed != null && await compressed.exists()) {
            videoPath = compressed.path;
            if (kDebugMode) {
              final origSize = await File(originalPath).length();
              final newSize = await compressed.length();
              debugPrint(
                '[feed-upload] compressed: ${origSize ~/ 1024}KB → '
                '${newSize ~/ 1024}KB (${(100 - newSize / origSize * 100).round()}% reduction)',
              );
            }
          }
        } catch (e) {
          // Kalau compress fail, fall back ke original. Bunny tetap
          // bisa accept + re-encode, user tetap bisa upload.
          if (kDebugMode) debugPrint('[feed-upload] compress failed: $e');
        }
      }

      // Step labels untuk error visibility — saat ada error, user lihat
      // "[Thumbnail] timeout" instead of generic "Upload belum berhasil".
      // Mudah debug + actionable hint untuk user retry / lapor admin.
      final thumbPath = widget.draft.thumbnailPath ??
          await _generateVideoThumbnail(videoPath, timeMs: 500);
      if (thumbPath == null || thumbPath.isEmpty) {
        throw const _FeedVideoFlowException(
          'Thumbnail video belum bisa dibuat. Coba lagi.',
        );
      }

      // Silent thumbnail upload — _stage tidak berubah, user tetap lihat
      // "Mengirim postingan..." dari awal sampai akhir.
      final FeedUploadResult thumbResult;
      try {
        thumbResult = await feedService.uploadFeedThumbnail(
          filePath: thumbPath,
          filename: 'thumbnail.jpg',
          contentType: 'image/jpeg',
        );
      } catch (error) {
        if (kDebugMode) {
          debugPrint('[feed-upload] thumbnail upload error: $error');
        }
        throw _FeedVideoFlowException(
          '[Thumbnail] ${_friendlyErrorMessage(error)}',
        );
      }
      if (thumbResult.url.isEmpty) {
        throw const _FeedVideoFlowException(
          '[Thumbnail] Server tidak mengembalikan URL — coba lagi atau '
          'hubungi admin.',
        );
      }

      final videoFile = File(videoPath);
      final caption = widget.draft.caption.trim();
      final bunnyService = BunnyUploadService(
        apiClient: apiClient,
        feedService: feedService,
      );

      // Silent provision Bunny credentials.
      final BunnyUploadProvision provision;
      try {
        provision = await bunnyService.provisionUpload(
          title: caption.isEmpty
              ? 'Postingan baru'
              : caption.substring(0, math.min(80, caption.length)),
          description: caption.isEmpty ? null : caption,
          videoDurationSec:
              (widget.draft.finalDuration?.inSeconds ?? _maxFeedVideoSeconds)
                  .clamp(_minFeedVideoSeconds, _maxFeedVideoSeconds)
                  .toInt(),
          productIds: widget.draft.taggedProductIds,
          thumbnailUrl: thumbResult.url,
        );
      } catch (error) {
        if (kDebugMode) debugPrint('[feed-upload] provision error: $error');
        throw _FeedVideoFlowException(
          '[Provision] ${_friendlyErrorMessage(error)}',
        );
      }

      // Silent TUS upload — _stage tetap "Mengirim postingan..." sementara
      // _progress percentage update real-time (cuma progress bar visible).
      try {
        if (provision.tus != null) {
          await bunnyService.uploadViaTus(
            videoFile: videoFile,
            credentials: provision.tus!,
            filetype:
                widget.draft.mimeType ?? _videoMimeType(videoFile.path, null),
            title: widget.draft.originalFilename ?? 'feed-video.mp4',
            onProgress: (percent, _, __) {
              if (mounted) setState(() => _progress = percent);
            },
          );
        } else if (provision.uploadUrl != null &&
            provision.uploadUrl!.isNotEmpty) {
          await bunnyService.uploadViaPut(
            videoFile: videoFile,
            uploadUrl: provision.uploadUrl!,
            headers: provision.uploadHeaders,
            onProgress: (percent, _, __) {
              if (mounted) setState(() => _progress = percent);
            },
          );
        } else {
          throw const _FeedVideoFlowException(
            '[Upload] Server tidak mengembalikan endpoint upload yang valid.',
          );
        }
      } catch (error) {
        if (kDebugMode) debugPrint('[feed-upload] video upload error: $error');
        if (error is _FeedVideoFlowException) rethrow;
        throw _FeedVideoFlowException(
          '[Upload] ${_friendlyErrorMessage(error)}',
        );
      }

      if (!mounted) return;
      // Silent finalize — _stage tetap sama, cuma progress 100%.
      setState(() {
        _progress = 100;
      });
      await bunnyService.finalize(provision.postId);
      if (!mounted) return;
      AppHaptics.success();
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const FeedPostSubmittedScreen()),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _started = false;
        _stage = '';
        _progress = 0;
        _error = _messageFor(
          error,
          'Upload belum berhasil. Periksa koneksi internet lalu coba lagi.',
        );
      });
      AppHaptics.error();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_uploading,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmExit() && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: _DarkUploadScaffold(
        title: '',
        leading: Icons.arrow_back_rounded,
        onLeading: () async {
          final navigator = Navigator.of(context);
          if (await _confirmExit() && mounted) navigator.pop();
        },
        child: Center(
          child: _error == null
              ? _UploadProgressContent(stage: _stage, progress: _progress)
              : _UploadErrorContent(
                  message: _error!,
                  onRetry: _startUpload,
                  onBack: () => Navigator.pop(context),
                ),
        ),
      ),
    );
  }
}

class FeedPostSubmittedScreen extends StatelessWidget {
  const FeedPostSubmittedScreen({super.key});

  void _backToFeed(BuildContext context) {
    Navigator.of(context).popUntil((route) {
      return route.settings.name == '/feed' || route.isFirst;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _DarkUploadScaffold(
      title: '',
      leading: Icons.arrow_back_rounded,
      onLeading: () => _backToFeed(context),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _SubmittedIllustration(),
            const SizedBox(height: 28),
            const Text(
              'Postingan berhasil dikirim!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _feedUploadText,
                fontSize: 23,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Feed kamu sedang menunggu review admin.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _feedUploadMuted,
                fontSize: 14.5,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 24),
            const _ReviewEstimateCard(),
            const SizedBox(height: 28),
            _PrimaryUploadButton(
              label: 'Lihat Postingan Saya',
              icon: Icons.video_collection_rounded,
              onPressed: () {
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/member/postingan',
                  (route) => route.isFirst,
                );
              },
            ),
            const SizedBox(height: 12),
            _SecondaryUploadButton(
              label: 'Kembali ke Feed',
              icon: Icons.play_circle_outline_rounded,
              onPressed: () => _backToFeed(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _DarkUploadScaffold extends StatelessWidget {
  final String title;
  final IconData leading;
  final VoidCallback onLeading;
  final Widget child;
  final Widget? trailing;

  const _DarkUploadScaffold({
    required this.title,
    required this.leading,
    required this.onLeading,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _feedUploadBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
          child: Column(
            children: [
              SizedBox(
                height: 48,
                child: Row(
                  children: [
                    _IconCircleButton(icon: leading, onTap: onLeading),
                    Expanded(
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _feedUploadText,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    trailing ?? const SizedBox(width: 44, height: 44),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class _StartPlaceholder extends StatelessWidget {
  final String stage;

  const _StartPlaceholder({required this.stage});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: math.min(MediaQuery.sizeOf(context).width * 0.58, 210),
          child: AspectRatio(
            aspectRatio: 9 / 16,
            child: Container(
              decoration: BoxDecoration(
                color: _feedUploadCard,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: _feedUploadBorder,
                  width: 1.2,
                ),
              ),
              child: CustomPaint(
                painter: _DashedBorderPainter(
                  color: Colors.white.withValues(alpha: 0.18),
                  radius: 24,
                ),
                child: Center(
                  child: Icon(
                    Icons.videocam_rounded,
                    color: Colors.white.withValues(alpha: 0.72),
                    size: 54,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          stage.isEmpty ? 'Belum ada video' : stage,
          style: TextStyle(
            color: stage.isEmpty ? _feedUploadMuted : _feedUploadBlue,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _VideoPreviewStage extends StatelessWidget {
  final VideoPlayerController? controller;
  final String? thumbnailPath;
  final bool loading;
  final bool playing;
  final VoidCallback? onTap;
  final String? timeText;

  const _VideoPreviewStage({
    required this.controller,
    required this.thumbnailPath,
    required this.loading,
    required this.playing,
    this.onTap,
    this.timeText,
  });

  @override
  Widget build(BuildContext context) {
    final ctrl = controller;
    return AspectRatio(
      aspectRatio: 9 / 13.5,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: ColoredBox(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (thumbnailPath != null)
                ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Transform.scale(
                    scale: 1.12,
                    child: Image.file(File(thumbnailPath!), fit: BoxFit.cover),
                  ),
                ),
              if (ctrl != null && ctrl.value.isInitialized)
                Center(
                  child: FittedBox(
                    fit: _isHorizontalSize(ctrl.value.size)
                        ? BoxFit.contain
                        : BoxFit.cover,
                    child: SizedBox(
                      width: ctrl.value.size.width,
                      height: ctrl.value.size.height,
                      child: VideoPlayer(ctrl),
                    ),
                  ),
                )
              else if (thumbnailPath != null)
                Image.file(File(thumbnailPath!), fit: BoxFit.cover),
              Positioned.fill(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: loading ? null : onTap,
                    child: Center(
                      child: loading
                          ? const CircularProgressIndicator(
                              color: _feedUploadBlue,
                            )
                          : AnimatedScale(
                              scale: playing ? 0.88 : 1,
                              duration: const Duration(milliseconds: 180),
                              child: Container(
                                height: 76,
                                width: 76,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.46),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.16),
                                  ),
                                ),
                                child: Icon(
                                  playing
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 42,
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 14,
                right: 14,
                bottom: 12,
                child: Text(
                  timeText ??
                      '00:00 / ${_formatDuration(ctrl?.value.duration)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    shadows: [
                      Shadow(color: Colors.black87, blurRadius: 8),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  final String title;
  final String value;

  const _InfoPanel({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _feedUploadCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _feedUploadBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _feedUploadMuted,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: _feedUploadText,
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

/// Instagram-style trim timeline.
///
/// Layout: horizontal strip of N frame thumbnails extracted dari video,
/// dengan 2 draggable handles (start kiri + end kanan) yang membentuk
/// selection window. Area outside selection di-dim. Window di-bordered
/// warna brand supaya jelas mana yang akan di-trim.
///
/// Handle drag callback dibedakan antara `dragging: true` (sambil drag,
/// untuk live seek + pause) dan `dragging: false` (release, untuk
/// restart loop dari new start position).
typedef _TimelineDragCallback = void Function(
  RangeValues values, {
  required bool dragging,
});

class _TrimTimeline extends StatefulWidget {
  final List<Uint8List?> frameThumbs;
  final String? fallbackThumbnailPath;
  final RangeValues range;
  final double totalSeconds;
  final _TimelineDragCallback? onChanged;

  const _TrimTimeline({
    required this.frameThumbs,
    required this.fallbackThumbnailPath,
    required this.range,
    required this.totalSeconds,
    required this.onChanged,
  });

  @override
  State<_TrimTimeline> createState() => _TrimTimelineState();
}

class _TrimTimelineState extends State<_TrimTimeline> {
  static const _handleWidth = 16.0;
  static const _frameStripHeight = 56.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      decoration: BoxDecoration(
        color: _feedUploadCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _feedUploadBorder),
      ),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              return _TrimRangeBar(
                width: constraints.maxWidth,
                stripHeight: _frameStripHeight,
                handleWidth: _handleWidth,
                frameThumbs: widget.frameThumbs,
                fallbackThumbnailPath: widget.fallbackThumbnailPath,
                range: widget.range,
                totalSeconds: widget.totalSeconds,
                onChanged: widget.onChanged,
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatDuration(Duration.zero), style: _markerStyle),
              Text(
                _formatDuration(
                  Duration(milliseconds: (widget.totalSeconds * 1000).round()),
                ),
                style: _markerStyle,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static const _markerStyle = TextStyle(
    color: _feedUploadMuted,
    fontSize: 11,
    fontWeight: FontWeight.w700,
  );
}

/// Internal widget yang handle gesture detection + render frame strip
/// + dim overlay + draggable handles.
class _TrimRangeBar extends StatefulWidget {
  final double width;
  final double stripHeight;
  final double handleWidth;
  final List<Uint8List?> frameThumbs;
  final String? fallbackThumbnailPath;
  final RangeValues range;
  final double totalSeconds;
  final _TimelineDragCallback? onChanged;

  const _TrimRangeBar({
    required this.width,
    required this.stripHeight,
    required this.handleWidth,
    required this.frameThumbs,
    required this.fallbackThumbnailPath,
    required this.range,
    required this.totalSeconds,
    required this.onChanged,
  });

  @override
  State<_TrimRangeBar> createState() => _TrimRangeBarState();
}

class _TrimRangeBarState extends State<_TrimRangeBar> {
  // Track which handle is being dragged. null = idle.
  // 'start' = left handle, 'end' = right handle, 'window' = window pan.
  String? _activeHandle;

  double get _availableWidth => widget.width - widget.handleWidth * 2;

  double _secondsToX(double seconds) {
    final ratio = (seconds / widget.totalSeconds).clamp(0.0, 1.0);
    return widget.handleWidth + ratio * _availableWidth;
  }

  double _xToSeconds(double x) {
    final clamped = (x - widget.handleWidth).clamp(0.0, _availableWidth);
    if (_availableWidth <= 0) return 0;
    return (clamped / _availableWidth) * widget.totalSeconds;
  }

  void _onDragStart(String handle) {
    if (widget.onChanged == null) return;
    _activeHandle = handle;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final cb = widget.onChanged;
    if (cb == null || _activeHandle == null) return;
    final localX =
        (details.globalPosition.dx - _renderBoxOriginX()).clamp(0.0, widget.width);
    final sec = _xToSeconds(localX);
    if (_activeHandle == 'start') {
      cb(RangeValues(sec, widget.range.end), dragging: true);
    } else if (_activeHandle == 'end') {
      cb(RangeValues(widget.range.start, sec), dragging: true);
    } else if (_activeHandle == 'window') {
      final span = widget.range.end - widget.range.start;
      final dragMid = sec;
      var newStart = dragMid - span / 2;
      var newEnd = dragMid + span / 2;
      if (newStart < 0) {
        newStart = 0;
        newEnd = span;
      }
      if (newEnd > widget.totalSeconds) {
        newEnd = widget.totalSeconds;
        newStart = newEnd - span;
      }
      cb(RangeValues(newStart, newEnd), dragging: true);
    }
  }

  void _onDragEnd(_) {
    final cb = widget.onChanged;
    if (cb != null && _activeHandle != null) {
      // Trigger release event → parent restart loop.
      cb(widget.range, dragging: false);
    }
    _activeHandle = null;
  }

  double _renderBoxOriginX() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return 0;
    return box.localToGlobal(Offset.zero).dx;
  }

  @override
  Widget build(BuildContext context) {
    final startX = _secondsToX(widget.range.start);
    final endX = _secondsToX(widget.range.end);
    return SizedBox(
      width: widget.width,
      height: widget.stripHeight,
      child: Stack(
        children: [
          // ── Frame strip background ──
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Row(
              children: List.generate(
                _FeedVideoTrimScreenState._frameCount,
                (i) {
                  final bytes = i < widget.frameThumbs.length
                      ? widget.frameThumbs[i]
                      : null;
                  return Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B2230),
                        border: Border(
                          right: BorderSide(
                            color: Colors.black.withValues(alpha: 0.30),
                            width: 0.5,
                          ),
                        ),
                      ),
                      child: bytes != null
                          ? Image.memory(bytes, fit: BoxFit.cover)
                          : widget.fallbackThumbnailPath != null
                              ? Image.file(
                                  File(widget.fallbackThumbnailPath!),
                                  fit: BoxFit.cover,
                                  opacity:
                                      const AlwaysStoppedAnimation(0.35),
                                )
                              : const SizedBox.shrink(),
                    ),
                  );
                },
              ),
            ),
          ),
          // ── Dim outside selection window ──
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: startX,
            child: IgnorePointer(
              child: Container(
                color: Colors.black.withValues(alpha: 0.55),
              ),
            ),
          ),
          Positioned(
            left: endX,
            top: 0,
            bottom: 0,
            right: 0,
            child: IgnorePointer(
              child: Container(
                color: Colors.black.withValues(alpha: 0.55),
              ),
            ),
          ),
          // ── Selection window border ──
          Positioned(
            left: startX,
            right: widget.width - endX,
            top: 0,
            bottom: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (_) => _onDragStart('window'),
              onHorizontalDragUpdate: _onDragUpdate,
              onHorizontalDragEnd: _onDragEnd,
              child: Container(
                decoration: const BoxDecoration(
                  border: Border.symmetric(
                    horizontal: BorderSide(color: Colors.white, width: 3),
                  ),
                ),
              ),
            ),
          ),
          // ── Start handle (left) ──
          Positioned(
            left: startX - widget.handleWidth,
            top: 0,
            bottom: 0,
            width: widget.handleWidth,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (_) => _onDragStart('start'),
              onHorizontalDragUpdate: _onDragUpdate,
              onHorizontalDragEnd: _onDragEnd,
              child: const _TrimHandle(side: 'left'),
            ),
          ),
          // ── End handle (right) ──
          Positioned(
            left: endX,
            top: 0,
            bottom: 0,
            width: widget.handleWidth,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (_) => _onDragStart('end'),
              onHorizontalDragUpdate: _onDragUpdate,
              onHorizontalDragEnd: _onDragEnd,
              child: const _TrimHandle(side: 'right'),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrimHandle extends StatelessWidget {
  final String side;

  const _TrimHandle({required this.side});

  @override
  Widget build(BuildContext context) {
    final isLeft = side == 'left';
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.horizontal(
          left: isLeft ? const Radius.circular(6) : Radius.zero,
          right: isLeft ? Radius.zero : const Radius.circular(6),
        ),
      ),
      alignment: Alignment.center,
      child: Container(
        width: 3,
        height: 18,
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _DetailPreviewCard extends StatelessWidget {
  final FeedCreatePostDraft draft;
  final VoidCallback onEdit;

  const _DetailPreviewCard({required this.draft, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _feedUploadCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _feedUploadBorder),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 82,
              height: 82,
              child: draft.thumbnailPath == null
                  ? const ColoredBox(
                      color: Color(0xFF1B2230),
                      child: Icon(
                        Icons.play_circle_fill_rounded,
                        color: Colors.white54,
                      ),
                    )
                  : Image.file(File(draft.thumbnailPath!), fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Preview Video',
                  style: TextStyle(
                    color: _feedUploadText,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Durasi ${_formatDuration(draft.finalDuration)}',
                  style: const TextStyle(
                    color: _feedUploadMuted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: onEdit,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: _feedUploadBorder),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Edit Video'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductTagPicker extends StatelessWidget {
  final TextEditingController controller;
  final List<Product> products;
  final Set<String> selectedProductIds;
  final bool loading;
  final bool enabled;
  final ValueChanged<String> onSearch;
  final ValueChanged<Product> onSelected;

  const _ProductTagPicker({
    required this.controller,
    required this.products,
    required this.selectedProductIds,
    required this.loading,
    required this.enabled,
    required this.onSearch,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _feedUploadCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _feedUploadBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tag produk opsional',
            style: TextStyle(
              color: _feedUploadText,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            enabled: enabled,
            style: const TextStyle(color: _feedUploadText),
            decoration: _darkInputDecoration(
              'Cari produk',
              'Cari produk',
              suffixIcon: IconButton(
                onPressed: enabled ? () => onSearch(controller.text) : null,
                icon: loading
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search_rounded),
              ),
            ),
            onSubmitted: onSearch,
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 132,
            child: products.isEmpty
                ? Center(
                    child: Text(
                      loading ? 'Memuat produk...' : 'Produk belum ditemukan',
                      style: const TextStyle(
                        color: _feedUploadMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: products.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final product = products[index];
                      final active = selectedProductIds.contains(product.id);
                      return InkWell(
                        onTap: () => onSelected(product),
                        borderRadius: BorderRadius.circular(16),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 118,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: active
                                ? _feedUploadBlue.withValues(alpha: 0.18)
                                : const Color(0xFF151A24),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color:
                                  active ? _feedUploadBlue : _feedUploadBorder,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: AppProductImage(
                                      imageUrl: product.imageUrl,
                                      height: 56,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  if (active)
                                    const Positioned(
                                      right: 4,
                                      top: 4,
                                      child: Icon(
                                        Icons.check_circle_rounded,
                                        color: _feedUploadBlue,
                                        size: 20,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 7),
                              Text(
                                product.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _feedUploadText,
                                  fontSize: 11,
                                  height: 1.18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                formatRupiah(product.price),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _feedUploadBlue,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _UploadProgressContent extends StatelessWidget {
  final String stage;
  final int progress;

  const _UploadProgressContent({
    required this.stage,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 112,
          width: 112,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CircularProgressIndicator(
                value: progress > 0 ? progress / 100 : null,
                color: _feedUploadBlue,
                backgroundColor: Colors.white.withValues(alpha: 0.12),
                strokeWidth: 5,
              ),
              const Icon(Icons.cloud_upload_rounded,
                  color: Colors.white, size: 42),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Text(
          stage.isEmpty ? 'Mengirim postingan...' : stage,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _feedUploadText,
            fontSize: 19,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Mohon tunggu sebentar, jangan tutup aplikasi.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _feedUploadMuted,
            fontSize: 14,
            height: 1.45,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 26),
        Text(
          '$progress%',
          style: const TextStyle(
            color: _feedUploadText,
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: progress > 0 ? progress / 100 : null,
            minHeight: 5,
            color: _feedUploadBlue,
            backgroundColor: Colors.white.withValues(alpha: 0.10),
          ),
        ),
      ],
    );
  }
}

class _UploadErrorContent extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  const _UploadErrorContent({
    required this.message,
    required this.onRetry,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.cloud_off_rounded, color: Color(0xFFFF7A7A), size: 70),
        const SizedBox(height: 20),
        const Text(
          'Upload belum berhasil',
          style: TextStyle(
            color: _feedUploadText,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _feedUploadMuted,
            fontSize: 14,
            height: 1.45,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 24),
        _PrimaryUploadButton(
          label: 'Coba Lagi',
          icon: Icons.refresh_rounded,
          onPressed: onRetry,
        ),
        const SizedBox(height: 12),
        _SecondaryUploadButton(
          label: 'Kembali ke Detail Postingan',
          icon: Icons.arrow_back_rounded,
          onPressed: onBack,
        ),
      ],
    );
  }
}

class _SubmittedIllustration extends StatelessWidget {
  const _SubmittedIllustration();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 132,
      width: 132,
      decoration: BoxDecoration(
        color: _feedUploadBlue.withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: 82,
            width: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFDCE8FF),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: _feedUploadBlue.withValues(alpha: 0.30),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: const Icon(
              Icons.playlist_add_check_rounded,
              color: _feedUploadBlue,
              size: 46,
            ),
          ),
          const Positioned(
            right: 18,
            bottom: 24,
            child: Icon(Icons.pets_rounded, color: Color(0xFFF7B955), size: 34),
          ),
          const Positioned(
            left: 23,
            top: 24,
            child: Icon(Icons.auto_awesome_rounded,
                color: _feedUploadBlue, size: 18),
          ),
        ],
      ),
    );
  }
}

class _ReviewEstimateCard extends StatelessWidget {
  const _ReviewEstimateCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _feedUploadCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _feedUploadBorder),
      ),
      child: const Row(
        children: [
          Icon(Icons.schedule_rounded, color: _feedUploadBlue),
          SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Estimasi review',
                style: TextStyle(
                  color: _feedUploadMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 3),
              Text(
                '1 x 24 jam',
                style: TextStyle(
                  color: _feedUploadText,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProcessingPanel extends StatelessWidget {
  const _ProcessingPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _feedUploadBlue.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _feedUploadBlue.withValues(alpha: 0.35)),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Sedang memproses video...',
              style: TextStyle(
                color: _feedUploadText,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryUploadButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool enabled;

  const _PrimaryUploadButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon, size: 19),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: _feedUploadBlue,
          disabledBackgroundColor: const Color(0xFF293244),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _SecondaryUploadButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool enabled;

  const _SecondaryUploadButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon, size: 19),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: _feedUploadText,
          disabledForegroundColor: _feedUploadMuted.withValues(alpha: 0.35),
          side: BorderSide(
            color: enabled
                ? _feedUploadBorder
                : _feedUploadBorder.withValues(alpha: 0.45),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _RoundNextButton extends StatelessWidget {
  final bool busy;
  final VoidCallback? onTap;

  const _RoundNextButton({required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 24,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: onTap == null ? const Color(0xFF293244) : _feedUploadBlue,
          shape: BoxShape.circle,
        ),
        child: busy
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.arrow_forward_rounded, color: Colors.white),
      ),
    );
  }
}

class _IconCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _IconCircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 24,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    );
  }
}

class _DarkErrorBox extends StatelessWidget {
  final String message;

  const _DarkErrorBox({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFF3A1821),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFF7A7A)),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFFFFCDD2),
          height: 1.35,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

InputDecoration _darkInputDecoration(
  String label,
  String hint, {
  Widget? suffixIcon,
}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    suffixIcon: suffixIcon,
    labelStyle: const TextStyle(color: _feedUploadMuted),
    hintStyle: TextStyle(color: _feedUploadMuted.withValues(alpha: 0.75)),
    counterStyle: const TextStyle(color: _feedUploadMuted),
    filled: true,
    fillColor: const Color(0xFF0B0E16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: _feedUploadBorder),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: _feedUploadBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: _feedUploadBlue, width: 1.4),
    ),
  );
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;

  const _DashedBorderPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    const dash = 7.0;
    const gap = 6.0;
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.radius != radius;
  }
}

class _FeedVideoFlowException implements Exception {
  final String message;
  const _FeedVideoFlowException(this.message);
}

Future<String> _copyVideoToCache(String sourcePath) async {
  final source = File(sourcePath);
  if (!await source.exists()) {
    throw const _FeedVideoFlowException(
      'Video tidak bisa dibuka. Pilih video lain.',
    );
  }
  final cacheDir = await getTemporaryDirectory();
  final dir = Directory('${cacheDir.path}${Platform.pathSeparator}feed_upload');
  if (!await dir.exists()) await dir.create(recursive: true);
  final ext = _extensionFor(sourcePath);
  final target = File(
      '${dir.path}${Platform.pathSeparator}feed_${DateTime.now().millisecondsSinceEpoch}$ext');
  return (await source.copy(target.path)).path;
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

Future<String?> _generateVideoThumbnail(String path, {int timeMs = 0}) async {
  final cacheDir = await getTemporaryDirectory();
  return VideoThumbnail.thumbnailFile(
    video: path,
    thumbnailPath: cacheDir.path,
    imageFormat: ImageFormat.JPEG,
    maxWidth: 720,
    timeMs: timeMs,
    quality: 82,
  );
}

String _extensionFor(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0 || dot == path.length - 1) return '.mp4';
  final ext = path.substring(dot).toLowerCase();
  if (ext.length > 8) return '.mp4';
  return ext;
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

String _formatDuration(Duration? duration) {
  final d = duration ?? Duration.zero;
  final total = d.inSeconds;
  final minutes = (total ~/ 60).toString().padLeft(2, '0');
  final seconds = (total % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
  return '$bytes B';
}

bool _isHorizontalSize(Size size) {
  if (size.width <= 0 || size.height <= 0) return false;
  return size.width > size.height;
}

String _messageFor(Object error, String fallback) {
  if (error is ApiException) return error.message;
  if (error is _FeedVideoFlowException) return error.message;
  return fallback;
}

/// Translate raw exception jadi pesan singkat actionable.
///
/// Dipakai saat upload step tertentu (thumbnail/provision/TUS) gagal —
/// disambung dengan label step `[Thumbnail]` / `[Provision]` / `[Upload]`
/// supaya user tahu mana yang failing kalau lapor admin.
String _friendlyErrorMessage(Object error) {
  if (error is ApiException) {
    if (error.statusCode == 401) {
      return 'Sesi login expired. Login ulang lalu coba lagi.';
    }
    if (error.statusCode == 403) {
      return 'Kamu belum punya izin upload video. Hubungi admin.';
    }
    if (error.statusCode == 413) {
      return 'File terlalu besar. Pilih video lebih pendek.';
    }
    if (error.statusCode == 429) {
      return 'Batas upload tercapai (3/hari untuk member). Coba lagi besok.';
    }
    if (error.statusCode == 503) {
      return 'Layanan video sementara tidak tersedia. Coba lagi nanti.';
    }
    if (error.statusCode != null && error.statusCode! >= 500) {
      return 'Server bermasalah. Coba lagi 1-2 menit.';
    }
    return error.message;
  }
  final raw = error.toString().toLowerCase();
  if (raw.contains('socketexception') ||
      raw.contains('failed host lookup') ||
      raw.contains('connection refused')) {
    return 'Tidak bisa connect ke server. Cek koneksi internet.';
  }
  if (raw.contains('timeout')) {
    return 'Upload belum berhasil diproses. Coba lagi sebentar.';
  }
  if (raw.contains('handshake')) {
    return 'Masalah SSL/handshake. Coba lagi atau ganti jaringan.';
  }
  return error.toString().split('\n').first;
}

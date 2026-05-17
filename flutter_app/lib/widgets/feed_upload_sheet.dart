import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../models/product.dart';
import '../services/api_client.dart';
import '../services/bunny_upload_service.dart';
import '../services/feed_service.dart';
import '../services/product_service.dart';
import '../utils/haptics.dart';
import 'app_product_image.dart';

const _uploadSheetBg = Color(0xFFF7FBFF);
const _uploadInk = Color(0xFF0F172A);
const _uploadBlue = Color(0xFF1E5FBF);
// Naik dari 20 MB → 200 MB. Alasan: iPhone 1080p × 45s ~80-120 MB,
// iPhone 4K HEVC × 45s ~200-300 MB. Sebelumnya banyak user gagal upload
// karena native video iPhone melebihi 20 MB. 200 MB feasible karena
// migrate ke Bunny direct (bypass Vercel 4.5 MB serverless limit) +
// TUS resumable (koneksi putus = lanjut, bukan restart).
const _maxVideoBytes = 200 * 1024 * 1024;
const _minVideoSeconds = 1;
const _maxVideoSeconds = 45;

// Sprint 3 #8 — pending upload state untuk recovery saat app crash /
// kill mid-upload. TUS fingerprint sendiri di-track tus-js-client, tapi
// metadata user-facing (filename, post id, timestamp) disimpan di
// SharedPreferences supaya bisa show banner "Lanjutkan upload?"
const _pendingUploadKey = 'natalo-feed-upload-pending';

class FeedUploadSheet extends StatefulWidget {
  const FeedUploadSheet({super.key});

  static Future<bool?> show(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const FeedUploadSheet(),
    );
  }

  @override
  State<FeedUploadSheet> createState() => _FeedUploadSheetState();
}

class _FeedUploadSheetState extends State<FeedUploadSheet>
    with WidgetsBindingObserver {
  final _captionController = TextEditingController();
  final _productSearchController = TextEditingController();
  final _picker = ImagePicker();

  XFile? _video;
  String? _thumbnailPath;
  int _coverTimeMs = 0;
  VideoPlayerController? _previewController;
  Product? _selectedProduct;
  List<Product> _products = const [];
  bool _loadingProducts = false;
  // Sprint 4 — toggle source produk: false = search all products,
  // true = pinnable (yang user pernah beli, untuk anti-spam promo).
  bool _showingPurchased = false;
  bool _uploading = false;
  String _stage = '';
  int _uploadProgressPct = 0;
  String? _error;
  // Sprint 3 #8 — backup _stage saat lifecycle pause, restore saat resume.
  String? _stageBeforePause;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadProducts();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _captionController.dispose();
    _productSearchController.dispose();
    _previewController?.dispose();
    // Free VideoCompress resources kalau encode masih in-progress saat
    // user dismiss sheet — hindari leak FFmpeg session di native.
    VideoCompress.cancelCompression();
    super.dispose();
  }

  /// Sprint 3 #8 — App lifecycle awareness untuk upload UX.
  ///
  /// Saat app dipindah ke background mid-upload (user buka WhatsApp, dll),
  /// native http transport (TUS) auto-pause beberapa detik lalu di-suspend
  /// oleh OS. tus_client_dart retry internal saat foreground — kita cuma
  /// switch progress messaging supaya user paham.
  ///
  /// Saat foreground lagi, restore stage message. TUS resume otomatis
  /// karena library punya internal state + retry exponential.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_uploading) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _stageBeforePause = _stage;
      if (mounted) {
        setState(() {
          _stage = 'Upload pause sementara — app di background. '
              'Buka kembali untuk lanjut.';
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      if (mounted && _stageBeforePause != null) {
        setState(() {
          _stage = 'Melanjutkan upload...';
        });
        // Kasih 1 detik baca, lalu kembali ke stage asli supaya progress
        // bar update messaging tetap nyambung dengan progress %.
        Future.delayed(const Duration(seconds: 1), () {
          if (!mounted || !_uploading) return;
          setState(() {
            _stage = _stageBeforePause ?? 'Mengunggah video...';
            _stageBeforePause = null;
          });
        });
      }
    }
  }

  Future<void> _loadProducts([String query = '']) async {
    setState(() {
      _loadingProducts = true;
      _showingPurchased = false;
    });
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
  }

  /// Load products yang USER PERNAH BELI (DELIVERED + PAID). Match endpoint
  /// PWA /api/feed/pinnable-products. Match perilaku Capacitor PWA: user
  /// hanya bisa tag produk yang punya verified ownership (anti-spam promo).
  Future<void> _loadPurchasedProducts() async {
    setState(() {
      _loadingProducts = true;
      _showingPurchased = true;
      _productSearchController.clear();
    });
    final pinnable = await feedService.fetchPinnableProducts();
    if (!mounted) return;
    // Map JSON ke Product model — pinnable response punya field beda
    // dari /api/products (productId vs id, name vs title).
    final products = pinnable.map((p) {
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
  }

  Future<void> _pickVideo() async {
    if (_uploading) return;
    AppHaptics.tap();
    setState(() {
      _error = null;
      _stage = 'Membuka galeri...';
    });
    final picked = await _picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(seconds: _maxVideoSeconds),
    );
    if (picked == null) {
      if (mounted) setState(() => _stage = '');
      return;
    }

    await _previewController?.dispose();
    _previewController = null;
    _thumbnailPath = null;
    _coverTimeMs = 0;

    final file = File(picked.path);
    final sizeBytes = await file.length();
    if (sizeBytes > _maxVideoBytes) {
      if (!mounted) return;
      setState(() {
        _video = null;
        _stage = '';
        _error =
            'Ukuran video maksimal ${_formatBytes(_maxVideoBytes)}. Video ini ${_formatBytes(sizeBytes)}.';
      });
      return;
    }

    final controller = VideoPlayerController.file(file);
    try {
      setState(() => _stage = 'Mengecek video...');
      await controller.initialize();
      final duration = controller.value.duration;
      final seconds = duration.inMilliseconds / 1000;
      if (seconds < _minVideoSeconds || seconds > _maxVideoSeconds) {
        await controller.dispose();
        if (!mounted) return;
        setState(() {
          _video = null;
          _stage = '';
          _error =
              'Durasi video Feed harus $_minVideoSeconds-$_maxVideoSeconds detik.';
        });
        return;
      }

      controller
        ..setLooping(true)
        ..setVolume(0);
      await controller.play();

      setState(() => _stage = 'Membuat cover...');
      final defaultCoverMs = _defaultCoverTimeMs(duration);
      final thumbPath = await _generateThumbnail(
        picked.path,
        timeMs: defaultCoverMs,
      );
      if (thumbPath == null || thumbPath.isEmpty) {
        await controller.dispose();
        if (!mounted) return;
        setState(() {
          _video = null;
          _stage = '';
          _error = 'Cover video belum bisa dibuat. Coba video lain.';
        });
        return;
      }

      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _video = picked;
        _thumbnailPath = thumbPath;
        _coverTimeMs = defaultCoverMs;
        _previewController = controller;
        _stage = '';
        _error = null;
      });
    } catch (error) {
      await controller.dispose();
      if (!mounted) return;
      setState(() {
        _video = null;
        _stage = '';
        _error = 'Video belum bisa dibaca. Coba pilih file MP4/MOV lain.';
      });
    }
  }

  Future<String?> _generateThumbnail(
    String videoPath, {
    required int timeMs,
  }) async {
    final tempDir = await getTemporaryDirectory();
    return VideoThumbnail.thumbnailFile(
      video: videoPath,
      thumbnailPath: tempDir.path,
      imageFormat: ImageFormat.JPEG,
      maxWidth: 720,
      timeMs: timeMs,
      quality: 82,
    );
  }

  int _defaultCoverTimeMs(Duration duration) {
    final totalMs = duration.inMilliseconds;
    if (totalMs <= 1200) return 0;
    return (totalMs * 0.35).round().clamp(0, totalMs - 500).toInt();
  }

  Future<void> _openCoverPicker() async {
    final video = _video;
    final controller = _previewController;
    if (video == null || controller == null || _uploading) return;
    AppHaptics.tap();
    final duration = controller.value.duration;
    final totalMs = duration.inMilliseconds;
    final options = <_CoverOption>[
      const _CoverOption('Awal', 0),
      _CoverOption('Tengah', (totalMs * 0.5).round()),
      _CoverOption('Akhir', math.max(0, totalMs - 700).toInt()),
    ];
    final selected = await showModalBottomSheet<_CoverOption>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _CoverPickerSheet(
        options: options,
        currentTimeMs: _coverTimeMs,
        thumbnailPath: _thumbnailPath,
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _stage = 'Membuat cover...';
      _error = null;
    });
    try {
      final thumbPath = await _generateThumbnail(
        video.path,
        timeMs: selected.timeMs,
      );
      if (!mounted) return;
      if (thumbPath == null || thumbPath.isEmpty) {
        setState(() {
          _stage = '';
          _error = 'Cover video belum bisa dibuat. Coba titik lain.';
        });
        return;
      }
      setState(() {
        _thumbnailPath = thumbPath;
        _coverTimeMs = selected.timeMs;
        _stage = '';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stage = '';
        _error = 'Cover video belum bisa dibuat. Coba lagi.';
      });
    }
  }

  /// Sprint 1 — Bunny direct upload (replace legacy /api/feed/upload-video).
  ///
  /// Flow baru:
  ///   1. Upload thumbnail dulu lewat /api/feed/upload-thumbnail (file
  ///      kecil <1 MB, OK lewat serverless).
  ///   2. POST /api/feed/bunny/upload-url → server bikin Bunny placeholder
  ///      + FeedPost row (status=uploading), return signed URL + TUS creds.
  ///   3. Upload video direct ke Bunny CDN via TUS (resumable). Tidak
  ///      lewat Vercel serverless lagi — bypass 4.5 MB body + 60s timeout.
  ///   4. Bunny webhook handle encoding completion async — server update
  ///      encodingStatus=ready saat selesai. Client return langsung,
  ///      tidak block UI.
  ///
  /// TUS benefit: koneksi putus di tengah → resume otomatis dari byte
  /// terakhir, bukan restart dari 0%. Critical untuk file 200 MB di
  /// koneksi mobile Indonesia.
  Future<void> _submit() async {
    final video = _video;
    final thumbPath = _thumbnailPath;
    final controller = _previewController;
    final caption = _captionController.text.trim();
    if (video == null || thumbPath == null || controller == null) {
      setState(() => _error = 'Pilih video dulu sebelum upload.');
      return;
    }
    if (caption.length < 3) {
      setState(() => _error = 'Caption minimal 3 karakter.');
      return;
    }

    setState(() {
      _uploading = true;
      _error = null;
      _stage = 'Mengunggah cover...';
      _uploadProgressPct = 0;
    });

    try {
      // STEP 1 — Upload thumbnail dulu (kecil, lewat serverless OK).
      // Thumbnail URL akan di-pass ke provisionUpload sebagai client-
      // generated preview (server fallback ke Bunny auto-thumbnail nanti).
      final thumbResult = await feedService.uploadFeedThumbnail(
        filePath: thumbPath,
        filename: 'thumbnail.jpg',
        contentType: 'image/jpeg',
      );
      if (thumbResult.url.isEmpty) {
        throw const ApiException('Upload thumbnail belum mengembalikan URL.');
      }

      // STEP 1.5 — Client-side compression (video_compress).
      //
      // Kompres video di device dulu sebelum upload ke Bunny — save 60-
      // 80% bytes untuk source 4K/1080p, save 3-5 menit waktu upload di
      // mobile data. Bunny tetap akan re-encode multi-variant di server,
      // jadi tidak ada quality loss yang signifikan dari double encode.
      //
      // Threshold: kompres kalau file >30 MB. File kecil (clip pendek
      // dari kamera 720p) tidak perlu — save CPU device + waktu encode.
      //
      // Output: 720p H.264 ~3 Mbps (match Bunny target profile). Encode
      // time di iPhone modern ~30-60 detik untuk 45s clip, Android mid
      // mungkin 60-90 detik.
      //
      // Error handling: kalau compress gagal (codec tidak supported,
      // OOM, dll), fallback ke upload raw original — tidak block flow.
      final rawVideoFile = File(video.path);
      final rawVideoSize = await rawVideoFile.length();
      File videoFile = rawVideoFile;
      int videoSize = rawVideoSize;
      final shouldCompress = rawVideoSize > 30 * 1024 * 1024;

      if (shouldCompress) {
        if (!mounted) return;
        setState(() {
          _stage =
              'Mengompres video ${(rawVideoSize / 1024 / 1024).toStringAsFixed(0)} MB '
              '— biar upload lebih cepat...';
          _uploadProgressPct = 0;
        });

        try {
          final info = await VideoCompress.compressVideo(
            video.path,
            quality: VideoQuality.MediumQuality, // ~720p H.264
            deleteOrigin: false,
            includeAudio: true,
            // frameRate: 30, // default sudah ~30
          );
          if (info != null && info.file != null) {
            final compressedFile = info.file!;
            final compressedSize = await compressedFile.length();
            // Kalau hasil kompres LEBIH BESAR dari original (kasus rare:
            // source sudah kompres tinggi seperti 4K HEVC), pakai original.
            if (compressedSize > 0 && compressedSize < rawVideoSize) {
              videoFile = compressedFile;
              videoSize = compressedSize;
            }
          }
        } catch (_) {
          // Compress gagal — fallback ke upload raw. Tidak throw supaya
          // user tetap bisa post.
        }
      }

      if (!mounted) return;
      setState(() => _stage = 'Menyiapkan upload...');

      // STEP 2 — Provision Bunny placeholder + FeedPost row.
      final durationSec = (controller.value.duration.inMilliseconds / 1000)
          .round()
          .clamp(
            _minVideoSeconds,
            _maxVideoSeconds,
          )
          .toInt();

      final bunnyService = BunnyUploadService(
        apiClient: apiClient,
        feedService: feedService,
      );
      final provision = await bunnyService.provisionUpload(
        title: caption.length > 80 ? caption.substring(0, 80) : caption,
        description: caption,
        videoDurationSec: durationSec,
        productIds:
            _selectedProduct == null ? const [] : [_selectedProduct!.id],
        thumbnailUrl: thumbResult.url,
      );

      // STEP 3 — Save pending state untuk crash recovery (Sprint 3 #8).
      final sizeMB = videoSize / (1024 * 1024);
      await _savePendingUpload(
        postId: provision.postId,
        videoGuid: provision.videoGuid,
        filename: _filename(video, fallback: 'feed-video.mp4'),
        sizeMB: sizeMB,
      );

      // STEP 4 — Upload via TUS (kalau available) atau fallback PUT.
      final hintLargeFile = videoSize > 50 * 1024 * 1024;
      if (!mounted) return;
      setState(() {
        _stage = hintLargeFile
            ? 'Mengunggah video ${sizeMB.toStringAsFixed(0)} MB '
                '— koneksi putus pun lanjut otomatis...'
            : 'Mengunggah video...';
      });

      if (provision.tus != null) {
        try {
          await bunnyService.uploadViaTus(
            videoFile: videoFile,
            credentials: provision.tus!,
            filetype: _videoMimeType(video),
            title: _filename(video, fallback: 'feed-video.mp4'),
            onProgress: (percent, _, __) {
              if (!mounted) return;
              setState(() => _uploadProgressPct = percent);
            },
          );
        } catch (e) {
          // TUS gagal total — message manusiawi (TUS sudah auto-retry
          // internal sebelum throw).
          throw const ApiException(
            'Upload terputus berkali-kali. Coba lagi dengan koneksi yang '
            'lebih stabil — atau gunakan WiFi.',
          );
        }
      } else if (provision.uploadUrl != null &&
          provision.uploadUrl!.isNotEmpty) {
        // Fallback ke simple PUT kalau server tidak return TUS creds.
        await bunnyService.uploadViaPut(
          videoFile: videoFile,
          uploadUrl: provision.uploadUrl!,
          headers: provision.uploadHeaders,
          onProgress: (percent, _, __) {
            if (!mounted) return;
            setState(() => _uploadProgressPct = percent);
          },
        );
      } else {
        throw const ApiException(
          'Server tidak mengembalikan endpoint upload yang valid.',
        );
      }

      // STEP 5 — Cleanup pending state (upload sukses).
      await _clearPendingUpload();

      if (!mounted) return;
      setState(() {
        _stage = 'Memfinalisasi...';
        _uploadProgressPct = 100;
      });
      await bunnyService.finalize(provision.postId);

      if (!mounted) return;
      AppHaptics.success();
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _stage = '';
        _uploadProgressPct = 0;
        _error = _messageFor(error, 'Upload video gagal. Coba lagi.');
      });
      if (error is ApiException && error.statusCode == 401) {
        Navigator.pop(context, false);
        Navigator.pushNamed(context, '/member/login');
      }
    }
  }

  /// Sprint 3 #8 — Save pending upload metadata ke SharedPreferences.
  /// TTL 24 jam (match Bunny TUS session expiry).
  Future<void> _savePendingUpload({
    required String postId,
    required String videoGuid,
    required String filename,
    required double sizeMB,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _pendingUploadKey,
        '$postId|$videoGuid|$filename|${sizeMB.toStringAsFixed(1)}|'
        '${DateTime.now().millisecondsSinceEpoch}',
      );
    } catch (_) {
      // Storage error — silent fail, recovery banner just won't show.
    }
  }

  Future<void> _clearPendingUpload() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pendingUploadKey);
    } catch (_) {
      // ignore
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return FractionallySizedBox(
      heightFactor: 0.94,
      child: Container(
        decoration: const BoxDecoration(
          color: _uploadSheetBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Padding(
          padding: EdgeInsets.only(bottom: keyboard),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                height: 4,
                width: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFF94A3B8).withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              _Header(onClose: () => Navigator.pop(context, false)),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
                  children: [
                    _VideoPickerCard(
                      controller: _previewController,
                      thumbnailPath: _thumbnailPath,
                      stage: _stage,
                      uploading: _uploading,
                      onPick: _pickVideo,
                      onPickCover: _openCoverPicker,
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _captionController,
                      enabled: !_uploading,
                      maxLines: 4,
                      maxLength: 1000,
                      decoration: _inputDecoration(
                        'Caption video',
                        'Ceritakan momen lucu, review produk, atau tips rawat pet...',
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Source toggle: All products vs. Pernah dibeli (verified
                    // ownership). Capacitor pattern — anti-spam tagging.
                    Row(
                      children: [
                        ChoiceChip(
                          label: const Text('Semua Produk'),
                          selected: !_showingPurchased,
                          onSelected: _uploading
                              ? null
                              : (_) => _loadProducts(),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          avatar: const Icon(
                            Icons.verified_rounded,
                            size: 16,
                            color: Color(0xFF0B7FEA),
                          ),
                          label: const Text('Pernah Dibeli'),
                          selected: _showingPurchased,
                          onSelected: _uploading
                              ? null
                              : (_) => _loadPurchasedProducts(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _ProductPicker(
                      controller: _productSearchController,
                      products: _products,
                      selected: _selectedProduct,
                      loading: _loadingProducts,
                      enabled: !_uploading && !_showingPurchased,
                      onSearch: _loadProducts,
                      onSelected: (product) {
                        AppHaptics.tap();
                        setState(() {
                          _selectedProduct = _selectedProduct?.id == product.id
                              ? null
                              : product;
                        });
                      },
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      _ErrorBox(message: _error!),
                    ],
                  ],
                ),
              ),
              _Footer(
                uploading: _uploading,
                stage: _stage,
                uploadProgressPct: _uploadProgressPct,
                hasVideo: _video != null,
                onSubmit: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onClose;

  const _Header({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 10, 8),
      child: Row(
        children: [
          Container(
            height: 42,
            width: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F7FF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.add_rounded, color: Color(0xFF4D8ED6)),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '+ Upload Video',
                  style: TextStyle(
                    color: Color(0xFF1E5FBF),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Video 1-45 detik, maksimal 20 MB.',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, color: _uploadInk),
            tooltip: 'Tutup',
          ),
        ],
      ),
    );
  }
}

class _VideoPickerCard extends StatelessWidget {
  final VideoPlayerController? controller;
  final String? thumbnailPath;
  final String stage;
  final bool uploading;
  final VoidCallback onPick;
  final VoidCallback onPickCover;

  const _VideoPickerCard({
    required this.controller,
    required this.thumbnailPath,
    required this.stage,
    required this.uploading,
    required this.onPick,
    required this.onPickCover,
  });

  @override
  Widget build(BuildContext context) {
    final ctrl = controller;
    final hasVideo = ctrl != null && ctrl.value.isInitialized;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white),
        boxShadow: [
          BoxShadow(
            color: _uploadBlue.withValues(alpha: 0.08),
            blurRadius: 26,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: _SafeFeedUploadPreview(
              controller: ctrl,
              thumbnailPath: thumbnailPath,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasVideo ? 'Video siap diupload' : 'Pilih video dari galeri',
                  style: const TextStyle(
                    color: _uploadInk,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  hasVideo
                      ? 'Preview aman untuk Feed 9:16. Cover bisa dipilih sebelum upload.'
                      : 'Pilih momen petshop, kucing, anjing, review produk, atau tips singkat.',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12.5,
                    height: 1.45,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: uploading ? null : onPick,
                    icon: const Icon(Icons.video_library_rounded),
                    label: Text(hasVideo ? 'Ganti video' : 'Pilih video'),
                  ),
                ),
                if (hasVideo) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: uploading ? null : onPickCover,
                      icon: const Icon(Icons.photo_filter_rounded),
                      label: const Text('Pilih cover'),
                    ),
                  ),
                ],
                if (stage.isNotEmpty && !uploading) ...[
                  const SizedBox(height: 10),
                  Text(
                    stage,
                    style: const TextStyle(
                      color: _uploadBlue,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SafeFeedUploadPreview extends StatelessWidget {
  final VideoPlayerController? controller;
  final String? thumbnailPath;

  const _SafeFeedUploadPreview({
    required this.controller,
    required this.thumbnailPath,
  });

  @override
  Widget build(BuildContext context) {
    final ctrl = controller;
    final hasVideo = ctrl != null && ctrl.value.isInitialized;
    final thumb = thumbnailPath;
    return SizedBox(
      height: 202,
      width: 114,
      child: ColoredBox(
        color: const Color(0xFF0B1220),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (thumb != null)
              ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Transform.scale(
                  scale: 1.12,
                  child: Image.file(File(thumb), fit: BoxFit.cover),
                ),
              )
            else
              const Center(
                child: Icon(
                  Icons.smart_display_rounded,
                  color: Colors.white54,
                  size: 44,
                ),
              ),
            if (hasVideo)
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
            else if (thumb != null)
              Image.file(File(thumb), fit: BoxFit.cover),
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.54),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.14),
                  ),
                ),
                child: const Text(
                  'Preview 9:16',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoverOption {
  final String label;
  final int timeMs;

  const _CoverOption(this.label, this.timeMs);
}

class _CoverPickerSheet extends StatelessWidget {
  final List<_CoverOption> options;
  final int currentTimeMs;
  final String? thumbnailPath;

  const _CoverPickerSheet({
    required this.options,
    required this.currentTimeMs,
    required this.thumbnailPath,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(14),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                height: 4,
                width: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Pilih cover',
              style: TextStyle(
                color: _uploadInk,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Cover dipakai saat video belum diputar.',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                if (thumbnailPath != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.file(
                      File(thumbnailPath!),
                      height: 116,
                      width: 66,
                      fit: BoxFit.cover,
                    ),
                  ),
                if (thumbnailPath != null) const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    children: options.map((option) {
                      final active =
                          (option.timeMs - currentTimeMs).abs() < 650;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          onTap: () => Navigator.pop(context, option),
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 13,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: active
                                  ? const Color(0xFFEAF5FF)
                                  : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: active
                                    ? _uploadBlue
                                    : const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  active
                                      ? Icons.check_circle_rounded
                                      : Icons.radio_button_unchecked_rounded,
                                  color: active
                                      ? _uploadBlue
                                      : const Color(0xFF94A3B8),
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    option.label,
                                    style: const TextStyle(
                                      color: _uploadInk,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductPicker extends StatelessWidget {
  final TextEditingController controller;
  final List<Product> products;
  final Product? selected;
  final bool loading;
  final bool enabled;
  final ValueChanged<String> onSearch;
  final ValueChanged<Product> onSelected;

  const _ProductPicker({
    required this.controller,
    required this.products,
    required this.selected,
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
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tag produk opsional',
            style: TextStyle(
              color: _uploadInk,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            enabled: enabled,
            decoration: _inputDecoration(
              'Cari produk',
              'Contoh: Royal Canin, pasir, snack...',
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
            height: 104,
            child: products.isEmpty
                ? Center(
                    child: Text(
                      loading ? 'Memuat produk...' : 'Produk belum ditemukan',
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: products.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final product = products[index];
                      final active = selected?.id == product.id;
                      return InkWell(
                        onTap: enabled ? () => onSelected(product) : null,
                        borderRadius: BorderRadius.circular(16),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 156,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: active
                                ? const Color(0xFFEAF5FF)
                                : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: active
                                  ? _uploadBlue
                                  : const Color(0xFFE2E8F0),
                              width: active ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: AppProductImage(
                                  imageUrl: product.imageUrl,
                                  height: 58,
                                  width: 58,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  product.title,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _uploadInk,
                                    fontSize: 11.5,
                                    height: 1.22,
                                    fontWeight: FontWeight.w900,
                                  ),
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

class _Footer extends StatelessWidget {
  final bool uploading;
  final String stage;
  final int uploadProgressPct;
  final bool hasVideo;
  final VoidCallback onSubmit;

  const _Footer({
    required this.uploading,
    required this.stage,
    required this.uploadProgressPct,
    required this.hasVideo,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.94),
          border: const Border(top: BorderSide(color: Color(0xFFE2E8F0))),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (uploading && stage.isNotEmpty) ...[
              Row(
                children: [
                  const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      uploadProgressPct > 0 && uploadProgressPct < 100
                          ? '$stage $uploadProgressPct%'
                          : stage,
                      style: const TextStyle(
                        color: _uploadBlue,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: uploading || !hasVideo ? null : onSubmit,
                icon: const Icon(Icons.cloud_upload_rounded),
                label: const Text('Upload ke Feed'),
                style: FilledButton.styleFrom(
                  backgroundColor: _uploadBlue,
                  disabledBackgroundColor: const Color(0xFFCBD5E1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;

  const _ErrorBox({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFDA4AF)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: Color(0xFFE11D48)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF9F1239),
                fontWeight: FontWeight.w800,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

InputDecoration _inputDecoration(
  String label,
  String hint, {
  Widget? suffixIcon,
}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: const Color(0xFFF8FAFC),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: _uploadBlue, width: 1.4),
    ),
  );
}

String _filename(XFile file, {required String fallback}) {
  final name = file.name.trim();
  if (name.isNotEmpty) return name;
  final segments = file.path.split(RegExp(r'[\\/]'));
  return segments.isEmpty ? fallback : segments.last;
}

String _videoMimeType(XFile file) {
  final mime = file.mimeType;
  if (mime == 'video/mp4' ||
      mime == 'video/webm' ||
      mime == 'video/quicktime') {
    return mime!;
  }
  final lower = file.path.toLowerCase();
  if (lower.endsWith('.mov')) return 'video/quicktime';
  if (lower.endsWith('.webm')) return 'video/webm';
  return 'video/mp4';
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
  return fallback;
}

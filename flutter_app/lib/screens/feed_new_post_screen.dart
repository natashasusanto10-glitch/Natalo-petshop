import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../config/feature_flags.dart';
import '../models/feed_create_post_draft.dart';
import '../models/product.dart';
import '../services/app_analytics.dart';
import '../services/feed_service.dart';
import '../state/feed_draft_store.dart';
import '../state/feed_upload_store.dart';
import '../utils/formatters.dart';
import '../utils/fade_route.dart';
import '../utils/haptics.dart';
import '../widgets/app_product_image.dart';
import '../widgets/app_toast.dart';
import 'feed_caption_edit_screen.dart';
import 'feed_post/feed_cover_picker_screen.dart';
import 'feed_post/feed_post_preview_screen.dart'
    show FeedPostPreviewScreen, FeedPreviewResult;

const _newPostBlue = Color(0xFF1E5BFF);
const _newPostInk = Color(0xFF101828);
const _newPostMuted = Color(0xFF667085);
const _newPostBorder = Color(0xFFE0E7F0);
const _newPostSoft = Color(0xFFF5F8FF);

/// Loop playback dalam rentang trim draft (Approach B: file belum
/// terpotong secara fisik sampai upload). Return timer guard — cancel
/// di dispose. Tanpa trimStart → biarkan looping bawaan controller.
Timer? startTrimLoopGuard(
  VideoPlayerController controller,
  FeedCreatePostDraft? draft,
) {
  final start = draft?.trimStart;
  final span = draft?.finalDuration;
  if (start == null || span == null) return null;
  final end = start + span;
  controller.seekTo(start);
  return Timer.periodic(const Duration(milliseconds: 200), (_) {
    if (!controller.value.isInitialized || !controller.value.isPlaying) return;
    if (controller.value.position >= end) controller.seekTo(start);
  });
}

enum NewPostMediaType {
  image,
  video,
}

class NewPostMediaDraft {
  final NewPostMediaType type;
  final List<File> photoFiles;
  final FeedCreatePostDraft? videoDraft;

  const NewPostMediaDraft._({
    required this.type,
    this.photoFiles = const [],
    this.videoDraft,
  });

  const NewPostMediaDraft.photos(List<File> files)
      : this._(type: NewPostMediaType.image, photoFiles: files);

  const NewPostMediaDraft.video(FeedCreatePostDraft draft)
      : this._(type: NewPostMediaType.video, videoDraft: draft);
}

class FeedNewPostScreen extends StatefulWidget {
  final NewPostMediaDraft draft;

  /// Optional caption pre-fill — dipakai saat resume draft dari SharedPreferences
  /// (tap "Lanjutkan draft" banner di My Posts). Null = composer kosong.
  final String? prefilledCaption;

  /// Optional product IDs pre-fill — sama dengan prefilledCaption, dipakai
  /// pas resume draft. Empty = no products tagged.
  final List<String> prefilledProductIds;

  /// Id draft (dari `FeedDraftStore`) yang sedang di-resume — bila layar
  /// ini dibuka dari restore draft (bukan compose baru), simpan ulang
  /// harus UPSERT ke id yang sama (bukan bikin draft duplikat), dan
  /// publish sukses menghapus draft ini.
  final String? resumeDraftId;

  const FeedNewPostScreen({
    super.key,
    required this.draft,
    this.prefilledCaption,
    this.prefilledProductIds = const [],
    this.resumeDraftId,
  });

  @override
  State<FeedNewPostScreen> createState() => _FeedNewPostScreenState();
}

class _FeedNewPostScreenState extends State<FeedNewPostScreen> {
  final _captionController = TextEditingController();
  final _productSearchController = TextEditingController();
  final _photoPageController = PageController();
  final Set<String> _selectedProductIds = {};

  FeedCreatePostDraft? _videoDraft;
  List<Product> _products = const [];
  List<Product> _visibleProducts = const [];
  bool _loadingProducts = true;
  bool _savingDraft = false;
  String? _error;
  int _photoIndex = 0;

  /// Foto carousel — mutable copy dari `widget.draft.photoFiles` (yang
  /// immutable) supaya user bisa urutkan (drag) & hapus slide di layar
  /// Bagikan (Task 5 / 2C-3). Foto sudah pre-cropped final JPEG dari
  /// picker — reorder/hapus cuma manipulasi urutan/isi List<File>, TANPA
  /// re-crop. Setiap referensi ke `widget.draft.photoFiles` di state class
  /// ini HARUS baca dari `_photoFiles`, bukan `widget.draft.photoFiles`
  /// langsung, supaya reorder/hapus ke-reflect di semua tempat (upload,
  /// counter, dots, save draft, dst).
  late final List<File> _photoFiles = List.of(widget.draft.photoFiles);

  /// Id draft aktif — null = belum pernah disimpan sebagai draft. Di-set
  /// dari `widget.resumeDraftId` (kalau restore) atau dibuat baru saat
  /// `_saveDraftAndExit` pertama kali dipanggil, supaya save berikutnya
  /// UPSERT (bukan duplikat).
  String? _draftId;

  bool get _isVideo => widget.draft.type == NewPostMediaType.video;

  bool get _hasProgress {
    return _captionController.text.trim().isNotEmpty ||
        _selectedProductIds.isNotEmpty ||
        _photoFiles.isNotEmpty ||
        widget.draft.videoDraft != null;
  }

  @override
  void initState() {
    super.initState();
    unawaited(
      AppAnalytics.logEvent('feed_post_share_opened', {
        'type': _isVideo
            ? 'video'
            : (_photoFiles.length > 1 ? 'carousel' : 'photo'),
      }),
    );
    _videoDraft = widget.draft.videoDraft;
    _draftId = widget.resumeDraftId;
    // Restore caption + tagged products dari draft (kalau ada).
    if (widget.prefilledCaption != null &&
        widget.prefilledCaption!.isNotEmpty) {
      _captionController.text = widget.prefilledCaption!;
    }
    if (widget.prefilledProductIds.isNotEmpty) {
      _selectedProductIds.addAll(widget.prefilledProductIds);
    }
    _captionController.addListener(() {
      if (mounted) setState(() {});
    });
    if (kShopTagEnabled) {
      _loadPurchasedProducts();
    }
  }

  @override
  void dispose() {
    _captionController.dispose();
    _productSearchController.dispose();
    _photoPageController.dispose();
    super.dispose();
  }

  /// Buka Caption editor sebagai fade-modal — terpisah dari Post Baru.
  /// Match Final Lock Spec: tap "Tulis caption..." trigger → fade overlay
  /// dengan white sheet di atas + dim Post Baru di bawah. Return value
  /// (caption baru) selalu di-commit ke controller — back/OK keduanya save.
  Future<void> _editCaption() async {
    AppHaptics.tap();
    final result = await showCaptionEditModal(
      context,
      initialCaption: _captionController.text,
    );
    if (!mounted) return;
    if (result != null) {
      _captionController.text = result;
      // setState dihandle via _captionController listener (sudah ada di
      // initState — auto rebuild trigger preview text).
    }
  }

  Future<void> _loadPurchasedProducts() async {
    setState(() {
      _loadingProducts = true;
      _error = null;
    });
    try {
      final pinnable = await feedService.fetchPinnableProducts(limit: 30);
      if (!mounted) return;
      final products = pinnable
          .whereType<Map>()
          .map((p) {
            // Kontrak API `app/api/feed/pinnable-products/route.ts`:
            // `price` = harga EFEKTIF (discountPrice ?? price asli),
            // `originalPrice` = harga DASAR asli. API TIDAK mengirim key
            // `discountPrice`/`memberPrice` — jangan baca key itu di sini.
            double? toDouble(dynamic v) {
              if (v is num) return v.toDouble();
              if (v is String) return double.tryParse(v);
              return null;
            }

            final effective = toDouble(p['price']);
            final base = toDouble(p['originalPrice']) ?? effective;
            final hasRealDiscount =
                effective != null && base != null && effective < base;
            return Product(
              id: (p['productId'] ?? p['id'] ?? '').toString(),
              slug: (p['slug'] ?? '').toString(),
              title: (p['name'] ?? p['title'] ?? '').toString(),
              category:
                  (p['variant'] ?? p['category'] ?? 'Pernah Dibeli').toString(),
              brand: '',
              imageUrl: (p['imageUrl'] ?? '').toString(),
              price: base ?? 0,
              discountPrice: hasRealDiscount ? effective : null,
              rating: p['avgRating'] is num
                  ? (p['avgRating'] as num).toDouble()
                  : 0,
              reviewCount: p['reviewCount'] is num
                  ? (p['reviewCount'] as num).toInt()
                  : 0,
              stock: p['stock'] is num ? (p['stock'] as num).toInt() : 0,
              description: '',
            );
          })
          .where((product) => product.id.isNotEmpty)
          .toList();
      setState(() {
        _products = products;
        _visibleProducts = products;
        _loadingProducts = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingProducts = false;
        _error = 'Produk yang pernah dibeli belum bisa dimuat.';
      });
    }
  }

  void _searchPurchasedProducts(String query) {
    final keyword = query.trim().toLowerCase();
    setState(() {
      _visibleProducts = keyword.isEmpty
          ? _products
          : _products
              .where((product) => product.title.toLowerCase().contains(keyword))
              .toList();
    });
  }

  void _toggleProduct(Product product) {
    AppHaptics.selection();
    setState(() {
      if (_selectedProductIds.contains(product.id)) {
        _selectedProductIds.remove(product.id);
      } else {
        _selectedProductIds.add(product.id);
      }
    });
  }

  /// Urutkan ulang slide carousel (drag di strip bawah thumbnail) — cuma
  /// manipulasi urutan `_photoFiles` (foto sudah pre-cropped final JPEG
  /// dari picker, TANPA re-crop). Setelah pindah, coba tetap fokus ke
  /// slide logis yang sama di thumbnail PageView (fallback clamp).
  void _reorderPhoto(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex == newIndex) return;
    AppHaptics.selection();
    setState(() {
      final moved = _photoFiles.removeAt(oldIndex);
      _photoFiles.insert(newIndex, moved);
      if (_photoIndex == oldIndex) {
        _photoIndex = newIndex;
      } else if (_photoIndex > oldIndex && _photoIndex <= newIndex) {
        _photoIndex -= 1;
      } else if (_photoIndex < oldIndex && _photoIndex >= newIndex) {
        _photoIndex += 1;
      }
      _photoIndex = _photoIndex.clamp(0, _photoFiles.length - 1);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_photoPageController.hasClients) return;
      _photoPageController.jumpToPage(_photoIndex);
    });
  }

  /// Hapus satu slide carousel — min 1 foto tersisa (tombol hapus
  /// disembunyikan/di-guard saat tinggal 1). Tidak ada undo — langsung
  /// hapus (spec brief: "snackbar undo TIDAK perlu").
  void _deletePhoto(int index) {
    if (_photoFiles.length <= 1) return;
    AppHaptics.selection();
    setState(() {
      _photoFiles.removeAt(index);
      if (index < _photoIndex) _photoIndex -= 1;
      _photoIndex = _photoIndex.clamp(0, _photoFiles.length - 1);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_photoPageController.hasClients) return;
      _photoPageController.jumpToPage(_photoIndex);
    });
  }

  /// Buka fullscreen Preview Mode — show bagaimana post akan tampil di
  /// feed sebelum publish. User bisa balik untuk revise atau langsung
  /// Share dari preview.
  Future<void> _openPreview() async {
    AppHaptics.tap();
    final caption = _captionController.text.trim();
    final selected =
        _products.where((p) => _selectedProductIds.contains(p.id)).toList();
    if (!mounted) return;
    final result = await Navigator.push<FeedPreviewResult>(
      context,
      fadeThroughRoute(
        FeedPostPreviewScreen(
          draft: _isVideo ? widget.draft : NewPostMediaDraft.photos(_photoFiles),
          videoDraft: _videoDraft,
          caption: caption,
          products: selected,
        ),
        fullscreenDialog: true,
      ),
    );
    if (!mounted) return;
    if (result == FeedPreviewResult.share) {
      await _upload();
    } else if (result == FeedPreviewResult.saveDraft) {
      await _saveDraftAndExit();
    }
  }

  /// Buka `FeedCoverPickerScreen` (filmstrip scrubber, rentang trim aktif)
  /// untuk pilih sampul baru. Return non-null → set thumbnailPath baru +
  /// tandai `userPickedCover: true` (dipakai 2C-1 untuk skip auto-cover).
  Future<void> _editCover() async {
    final draft = _videoDraft;
    final path = draft?.localVideoPath;
    final span = draft?.finalDuration;
    if (path == null || span == null) return;
    AppHaptics.tap();
    final selectedPath = await Navigator.push<String>(
      context,
      fadeThroughRoute(
        FeedCoverPickerScreen(
          videoPath: path,
          rangeStart: draft?.trimStart ?? Duration.zero,
          rangeSpan: span,
          currentCoverPath: draft?.thumbnailPath,
        ),
      ),
    );
    if (selectedPath == null || !mounted) return;
    setState(() {
      _videoDraft = draft?.copyWith(
        thumbnailPath: selectedPath,
        userPickedCover: true,
      );
    });
  }

  /// Submit post — IG-style background upload.
  ///
  /// User tap "Upload" → langsung kembali ke Beranda + mini relay card
  /// muncul di bawah search bar. Upload jalan via `feedUploadStore` di
  /// background sambil user lanjut browsing. NO MORE full-screen progress.
  ///
  /// Hapus pattern lama: Navigator.pushReplacement → FeedUploadProgressScreen
  /// / FeedPhotoUploadProgressScreen yang blocking user sampai upload kelar.
  Future<void> _upload() async {
    if (_error != null) return;
    if (feedUploadStore.isUploading) {
      // Double-submit guard — kalau ada upload sebelumnya yang masih
      // jalan, kasih tau user lewat snackbar (jangan stack 2 upload).
      AppToast.showBanner(
        context,
        'Ada postingan yang masih dikirim. Tunggu sebentar.',
        kind: ToastKind.info,
      );
      return;
    }
    AppHaptics.tap();
    final caption = _captionController.text.trim();
    final productIds = _selectedProductIds.toList();

    if (_isVideo) {
      final draft = _videoDraft;
      final videoPath = draft?.finalVideoPath;
      final duration = draft?.finalDuration;
      if (draft == null ||
          videoPath == null ||
          !File(videoPath).existsSync() ||
          duration == null ||
          duration.inSeconds < 1 ||
          duration.inSeconds > 60) {
        setState(() =>
            _error = 'Media belum bisa diproses. Coba pilih ulang media.');
        return;
      }
      // Kick off background upload via store. Caller tidak await — task
      // jalan di background. Caption + productIds di-baked ke draft.
      final readyDraft = draft.copyWith(
        caption: caption,
        taggedProductIds: productIds,
      );
      feedUploadStore.startVideoUpload(draft: readyDraft);
      unawaited(AppAnalytics.logEvent('feed_post_submitted', {
        'type': 'video',
        'product_count': productIds.length,
      }));
      final draftId = _draftId;
      if (draftId != null) unawaited(feedDraftStore.remove(draftId));
      _goHome();
      return;
    }

    final files = _photoFiles;
    if (files.isEmpty || files.length > 8) {
      setState(
          () => _error = 'Media belum bisa diproses. Coba pilih ulang media.');
      return;
    }

    // Kick off background photo upload via store.
    feedUploadStore.startPhotoUpload(
      files: files,
      caption: caption,
      productIds: productIds,
    );
    unawaited(AppAnalytics.logEvent('feed_post_submitted', {
      'type': files.length > 1 ? 'carousel' : 'photo',
      'product_count': productIds.length,
    }));
    final draftId = _draftId;
    if (draftId != null) unawaited(feedDraftStore.remove(draftId));
    _goHome();
  }

  /// Navigate back to Beranda (home tab) — clear all create-post stack.
  /// pushNamedAndRemoveUntil ke '/' = Home screen (initial route).
  void _goHome() {
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }

  Future<void> _saveDraftAndExit() async {
    if (_savingDraft) return;
    AppHaptics.tap();
    setState(() => _savingDraft = true);
    final now = DateTime.now().millisecondsSinceEpoch;
    // Keep id sama kalau ini resume/edit ulang draft — upsert bukan
    // duplikat. Draft baru → id fresh, langsung di-keep di state supaya
    // save berikutnya (atau remove saat publish sukses) pakai id yang sama.
    final draftId = _draftId ?? 'draft-$now';
    _draftId = draftId;
    final draft = FeedDraft(
      id: draftId,
      type: _isVideo ? 'video' : 'image',
      caption: _captionController.text.trim(),
      productIds: _selectedProductIds.toList(),
      mediaPaths: _isVideo
          ? [_videoDraft?.finalVideoPath].whereType<String>().toList()
          : _photoFiles.map((file) => file.path).toList(),
      thumbnailPath: _videoDraft?.thumbnailPath,
      trimStartMs: _videoDraft?.trimStart?.inMilliseconds,
      trimmedDurationMs: _videoDraft?.trimmedDuration?.inMilliseconds,
      originalDurationMs: _videoDraft?.originalDuration?.inMilliseconds,
      userPickedCover: _videoDraft?.userPickedCover ?? false,
      savedAtMs: now,
    );
    await feedDraftStore.save(draft);
    if (!mounted) return;
    setState(() => _savingDraft = false);
    Navigator.pop(context, false);
  }

  Future<bool> _confirmLeave() async {
    if (!_hasProgress) return true;
    final action = await showModalBottomSheet<_LeaveAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _LeaveDraftSheet(
        onContinue: () => Navigator.pop(context, _LeaveAction.continueEdit),
        onSave: () => Navigator.pop(context, _LeaveAction.saveDraft),
        onDiscard: () => Navigator.pop(context, _LeaveAction.discard),
      ),
    );
    if (action == _LeaveAction.saveDraft) {
      await _saveDraftAndExit();
      return false;
    }
    if (action == _LeaveAction.discard) {
      AppHaptics.warning();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) {
          Navigator.pop(context, false);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            onPressed: () async {
              if (await _confirmLeave() && context.mounted) {
                Navigator.pop(context, false);
              }
            },
            icon: const Icon(Icons.arrow_back_rounded, color: _newPostInk),
          ),
          title: const Text(
            'Post Baru',
            style: TextStyle(
              color: _newPostInk,
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
          centerTitle: true,
          // Tombol "Preview" text di-hapus per Instagram pattern.
          // Sekarang preview mode di-trigger via TAP image/video preview
          // langsung. Lebih natural — user tap apa yang dia mau lihat
          // fullscreen.
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                  children: [
                    // Tap media preview → buka fullscreen Preview Mode.
                    // Match Instagram pattern: no "Preview" text button,
                    // user tap image/video langsung. Tap routing:
                    //  - Tap video      → open preview (via onToggleVideo
                    //    callback yang sekarang rewire ke _openPreview,
                    //    bukan toggle play/pause — video tetap auto-loop
                    //    di editor)
                    //  - Tap photo area → open preview (via outer
                    //    GestureDetector — PageView swipe horizontal tetap
                    //    work karena swipe ≠ tap gesture)
                    //  - Tap "Edit cover" button → tetap edit cover (button
                    //    capture tap lebih spesifik)
                    // Thumbnail kecil — IG-style "Post Baru" share screen.
                    // widthFactor 0.42 (~42% lebar layar), aspect 3:4. Video
                    // pakai cover statis (thumbnailPath) — TIDAK ada video
                    // player inline di layar ini (keputusan #4, lihat brief
                    // Fase 2B Task 3). Preview dgn video asli hanya di
                    // FeedPostPreviewScreen (fullscreen).
                    Center(
                      child: FractionallySizedBox(
                        widthFactor: 0.42,
                        child: _NewPostThumbnail(
                          isVideo: _isVideo,
                          photoFiles: _photoFiles,
                          videoDraft: _videoDraft,
                          photoIndex: _photoIndex,
                          photoPageController: _photoPageController,
                          onPhotoChanged: (index) =>
                              setState(() => _photoIndex = index),
                          onOpenPreview: _openPreview,
                          onEditCover: _editCover,
                        ),
                      ),
                    ),
                    if (!_isVideo && _photoFiles.length > 1) ...[
                      const SizedBox(height: 14),
                      _PhotoReorderStrip(
                        photoFiles: _photoFiles,
                        onReorder: _reorderPhoto,
                        onDelete: _deletePhoto,
                      ),
                    ],
                    const SizedBox(height: 22),
                    // Simple caption trigger — tap → buka fade-modal Caption
                    // editor (separate page). Tidak ada border/box, tidak
                    // ada counter, tidak ada emoji button. Match Final Lock
                    // Spec.
                    _CaptionTrigger(
                      captionText: _captionController.text,
                      onTap: _editCaption,
                    ),
                    if (kShopTagEnabled) ...[
                      const SizedBox(height: 26),
                      const _SectionTitle('Tag Produk Pernah Dibeli'),
                      const SizedBox(height: 12),
                      _PurchasedProductSearch(
                        controller: _productSearchController,
                        onChanged: _searchPurchasedProducts,
                      ),
                      const SizedBox(height: 14),
                      _PurchasedProducts(
                        products: _visibleProducts,
                        loading: _loadingProducts,
                        selectedIds: _selectedProductIds,
                        onTap: _toggleProduct,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        _ErrorBox(message: _error!),
                      ],
                    ],
                  ],
                ),
              ),
              _BottomActions(
                uploadEnabled: _error == null,
                onSaveDraft: _saveDraftAndExit,
                onShare: _upload,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // _toggleVideo() di-remove karena video tap sekarang re-route ke
  // _openPreview (lihat onToggleVideo: _openPreview di build()). Video
  // tetap auto-loop muted di editor preview area; toggle play/pause
  // manual hanya tersedia di fullscreen Preview Mode.
}

/// Thumbnail kecil (~42% lebar layar, aspect 3:4, radius 18) untuk layar
/// "Post Baru" share — bukan editor lagi. Video: cover statis (tanpa video
/// player inline — keputusan #4 Fase 2B) + pill "Pratinjau" + "Ubah sampul".
/// Foto/carousel: PageView swipeable + pill "Pratinjau" + counter X/Y +
/// dot indicator (tanpa "Ubah sampul").
class _NewPostThumbnail extends StatelessWidget {
  final bool isVideo;
  final List<File> photoFiles;
  final FeedCreatePostDraft? videoDraft;
  final int photoIndex;
  final PageController photoPageController;
  final ValueChanged<int> onPhotoChanged;
  final VoidCallback onOpenPreview;
  final VoidCallback onEditCover;

  const _NewPostThumbnail({
    required this.isVideo,
    required this.photoFiles,
    required this.videoDraft,
    required this.photoIndex,
    required this.photoPageController,
    required this.onPhotoChanged,
    required this.onOpenPreview,
    required this.onEditCover,
  });

  @override
  Widget build(BuildContext context) {
    final files = photoFiles;
    final thumb = videoDraft?.thumbnailPath;
    return AspectRatio(
      aspectRatio: 3 / 4,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onOpenPreview,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (isVideo)
                (thumb != null
                    ? Image.file(
                        File(thumb),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const _ThumbnailFallback(),
                      )
                    : const _ThumbnailFallback())
              else
                PageView.builder(
                  controller: photoPageController,
                  itemCount: files.length,
                  onPageChanged: onPhotoChanged,
                  itemBuilder: (context, index) {
                    return Image.file(files[index], fit: BoxFit.cover);
                  },
                ),
              Positioned(
                left: 8,
                top: 8,
                child: _ThumbnailPill(
                  icon: Icons.visibility_outlined,
                  label: 'Pratinjau',
                  onTap: onOpenPreview,
                ),
              ),
              if (!isVideo && files.length > 1)
                Positioned(
                  right: 8,
                  top: 8,
                  child: _ThumbnailPill(
                    icon: null,
                    label: '${photoIndex + 1}/${files.length}',
                    onTap: null,
                  ),
                ),
              if (!isVideo && files.length > 1)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 8,
                  child: _DotIndicator(
                    length: files.length,
                    index: photoIndex,
                  ),
                ),
              if (isVideo)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 8,
                  child: Center(
                    child: _ThumbnailPill(
                      icon: Icons.photo_outlined,
                      label: 'Ubah sampul',
                      onTap: onEditCover,
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

/// Fallback saat video belum punya thumbnail (mis. sedang diproses).
class _ThumbnailFallback extends StatelessWidget {
  const _ThumbnailFallback();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF161A24),
      child: Center(
        child: Icon(Icons.videocam_outlined, color: Colors.white38, size: 34),
      ),
    );
  }
}

/// Pill overlay reusable untuk thumbnail — "Pratinjau", "Ubah sampul",
/// counter X/Y. bg rgba(0,0,0,0.52) radius 999, teks 10.5 w700, ikon kecil
/// opsional. `onTap` null = non-interactive (mis. counter pill).
class _ThumbnailPill extends StatelessWidget {
  final IconData? icon;
  final String label;
  final VoidCallback? onTap;

  const _ThumbnailPill({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.white, size: 12),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: content,
      ),
    );
  }
}

class _DotIndicator extends StatelessWidget {
  final int length;
  final int index;

  const _DotIndicator({
    required this.length,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(length, (i) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: i == index ? 8 : 7,
          height: i == index ? 8 : 7,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: i == index
                ? _newPostBlue
                : Colors.white.withValues(alpha: 0.58),
            shape: BoxShape.circle,
          ),
        );
      }),
    );
  }
}

/// Strip slide horizontal di bawah thumbnail carousel — reorder via
/// long-press drag (`ReorderableDragStartListener`) + hapus per-slide
/// (min 1 foto tersisa). Item 56×72 radius 10, badge nomor kecil (soft
/// tint, bukan warna nge-jreng), tombol × 18px pojok kanan-atas.
class _PhotoReorderStrip extends StatelessWidget {
  final List<File> photoFiles;
  final void Function(int oldIndex, int newIndex) onReorder;
  final ValueChanged<int> onDelete;

  const _PhotoReorderStrip({
    required this.photoFiles,
    required this.onReorder,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final canDelete = photoFiles.length > 1;
    return SizedBox(
      height: 76,
      child: ReorderableListView(
        scrollDirection: Axis.horizontal,
        buildDefaultDragHandles: false,
        onReorder: onReorder,
        children: [
          for (var i = 0; i < photoFiles.length; i++)
            Padding(
              key: ValueKey('slide-$i'),
              padding: EdgeInsets.only(
                right: i == photoFiles.length - 1 ? 0 : 10,
              ),
              child: ReorderableDragStartListener(
                index: i,
                child: _PhotoReorderTile(
                  index: i,
                  file: photoFiles[i],
                  canDelete: canDelete,
                  onDelete: () => onDelete(i),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PhotoReorderTile extends StatelessWidget {
  final int index;
  final File file;
  final bool canDelete;
  final VoidCallback onDelete;

  const _PhotoReorderTile({
    required this.index,
    required this.file,
    required this.canDelete,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 72,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(
              file,
              width: 56,
              height: 72,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 56,
                height: 72,
                color: const Color(0xFF161A24),
                child: const Icon(
                  Icons.image_outlined,
                  color: Colors.white38,
                  size: 20,
                ),
              ),
            ),
          ),
          Positioned(
            left: 4,
            bottom: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          if (canDelete)
            Positioned(
              right: -6,
              top: -6,
              child: GestureDetector(
                key: ValueKey('slide-delete-$index'),
                behavior: HitTestBehavior.opaque,
                onTap: onDelete,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: _newPostBorder),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    size: 13,
                    color: _newPostMuted,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: _newPostInk,
        fontSize: 18,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

/// Simple caption trigger — no box, no border, no counter, no emoji.
/// Tap → buka fade-modal Caption editor (separate page).
///
/// Visual:
///  - Saat caption kosong → "Tulis caption..." muted text
///  - Saat caption ada    → tampilkan caption text (max 2 lines, ellipsis,
///    Option 1 dari diskusi — match IG: langsung lihat content)
///
/// Tap area full-width supaya gampang tap (no missed taps di sisi).
class _CaptionTrigger extends StatelessWidget {
  final String captionText;
  final VoidCallback onTap;

  const _CaptionTrigger({
    required this.captionText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasCaption = captionText.trim().isNotEmpty;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: SizedBox(
          width: double.infinity,
          child: Text(
            hasCaption ? captionText : 'Tulis caption...',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: hasCaption ? _newPostInk : const Color(0xFF98A2B3),
              fontSize: 15,
              height: 1.4,
              fontWeight:
                  hasCaption ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _PurchasedProductSearch extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _PurchasedProductSearch({
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'Cari produk',
        hintStyle: const TextStyle(
          color: Color(0xFF98A2B3),
          fontWeight: FontWeight.w700,
        ),
        prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF98A2B3)),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: _newPostBorder, width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: _newPostBorder, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: _newPostBlue, width: 1.4),
        ),
      ),
    );
  }
}

class _PurchasedProducts extends StatelessWidget {
  final List<Product> products;
  final bool loading;
  final Set<String> selectedIds;
  final ValueChanged<Product> onTap;

  const _PurchasedProducts({
    required this.products,
    required this.loading,
    required this.selectedIds,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const SizedBox(
        height: 136,
        child: Center(
          child: CircularProgressIndicator(color: _newPostBlue),
        ),
      );
    }
    if (products.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _newPostSoft,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _newPostBorder),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Belum ada produk yang bisa ditag',
              style: TextStyle(
                color: _newPostInk,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(height: 5),
            Text(
              'Produk yang pernah kamu beli akan muncul di sini.',
              style: TextStyle(
                color: _newPostMuted,
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }
    return SizedBox(
      height: 150,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: products.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final product = products[index];
          final selected = selectedIds.contains(product.id);
          return _PurchasedProductCard(
            product: product,
            selected: selected,
            onTap: () => onTap(product),
          );
        },
      ),
    );
  }
}

class _PurchasedProductCard extends StatelessWidget {
  final Product product;
  final bool selected;
  final VoidCallback onTap;

  const _PurchasedProductCard({
    required this.product,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 116,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? _newPostBlue : _newPostBorder,
            width: selected ? 1.8 : 1.1,
          ),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: AppProductImage(
                    imageUrl: product.imageUrl,
                    width: 54,
                    height: 54,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  product.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? _newPostBlue : _newPostInk,
                    fontSize: 12.5,
                    height: 1.2,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (product.finalPrice > 0) ...[
                  const Spacer(),
                  Text(
                    formatRupiah(product.finalPrice),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _newPostMuted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
            Positioned(
              top: -8,
              right: -8,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: selected ? _newPostBlue : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? _newPostBlue : const Color(0xFFD0D5DD),
                    width: 1.5,
                  ),
                ),
                child: selected
                    ? const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 20,
                      )
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dual bottom bar — "Simpan Draft" (outline soft biru) + "Bagikan"
/// (filled biru), berdampingan 52px, radius 16, gap 10. Ganti tombol
/// tunggal lama — param `busy` dihapus total (upload sekarang background
/// via feedUploadStore, tidak butuh loading state di sini).
class _BottomActions extends StatelessWidget {
  final bool uploadEnabled;
  final VoidCallback onSaveDraft;
  final VoidCallback onShare;

  const _BottomActions({
    required this.uploadEnabled,
    required this.onSaveDraft,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE5EAF2))),
        ),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 52,
                child: OutlinedButton(
                  onPressed: onSaveDraft,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: _newPostSoft,
                    side: const BorderSide(color: _newPostBorder),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Simpan Draft',
                    style: TextStyle(
                      color: _newPostBlue,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: uploadEnabled ? onShare : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: _newPostBlue,
                    disabledBackgroundColor: const Color(0xFFCBD5E1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Bagikan',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
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
        borderRadius: BorderRadius.circular(16),
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
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _LeaveAction {
  continueEdit,
  saveDraft,
  discard,
}

class _LeaveDraftSheet extends StatelessWidget {
  final VoidCallback onContinue;
  final VoidCallback onSave;
  final VoidCallback onDiscard;

  const _LeaveDraftSheet({
    required this.onContinue,
    required this.onSave,
    required this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 26,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFD0D5DD),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Simpan sebagai draft?',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _newPostInk,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Postingan kamu belum diupload. Simpan sebagai draft supaya bisa dilanjutkan nanti.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _newPostMuted,
                fontSize: 14.5,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 22),
            _SheetButton(label: 'Lanjut Edit', onTap: onContinue),
            const SizedBox(height: 10),
            _SheetButton(
              label: 'Simpan Draft',
              onTap: onSave,
              filled: true,
            ),
            const SizedBox(height: 10),
            _SheetButton(
              label: 'Buang',
              onTap: onDiscard,
              destructive: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool filled;
  final bool destructive;

  const _SheetButton({
    required this.label,
    required this.onTap,
    this.filled = false,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive ? const Color(0xFFEF4444) : _newPostBlue;
    if (filled) {
      return SizedBox(
        width: double.infinity,
        height: 50,
        child: FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: color,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: Text(label),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side:
              BorderSide(color: destructive ? const Color(0xFFFCA5A5) : color),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(label),
      ),
    );
  }
}


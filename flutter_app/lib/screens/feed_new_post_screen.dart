import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../models/feed_create_post_draft.dart';
import '../models/product.dart';
import '../services/feed_service.dart';
import '../state/member_store.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import '../widgets/app_product_image.dart';
import '../widgets/profile_avatar.dart';
import 'feed_photo_upload_flow.dart';
import 'feed_video_upload_flow.dart';

const _newPostDraftKey = 'natalo-feed-upload-pending';
const _newPostBlue = Color(0xFF1E5BFF);
const _newPostInk = Color(0xFF101828);
const _newPostMuted = Color(0xFF667085);
const _newPostBorder = Color(0xFFE0E7F0);
const _newPostSoft = Color(0xFFF5F8FF);

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

  const FeedNewPostScreen({
    super.key,
    required this.draft,
  });

  @override
  State<FeedNewPostScreen> createState() => _FeedNewPostScreenState();
}

class _FeedNewPostScreenState extends State<FeedNewPostScreen> {
  final _captionController = TextEditingController();
  final _productSearchController = TextEditingController();
  final _photoPageController = PageController();
  final Set<String> _selectedProductIds = {};

  VideoPlayerController? _videoController;
  FeedCreatePostDraft? _videoDraft;
  List<Product> _products = const [];
  List<Product> _visibleProducts = const [];
  bool _loadingProducts = true;
  bool _savingDraft = false;
  String? _error;
  int _photoIndex = 0;

  bool get _isVideo => widget.draft.type == NewPostMediaType.video;

  bool get _hasProgress {
    return _captionController.text.trim().isNotEmpty ||
        _selectedProductIds.isNotEmpty ||
        widget.draft.photoFiles.isNotEmpty ||
        widget.draft.videoDraft != null;
  }

  @override
  void initState() {
    super.initState();
    _videoDraft = widget.draft.videoDraft;
    _captionController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadPurchasedProducts();
    _initVideo();
  }

  @override
  void dispose() {
    _captionController.dispose();
    _productSearchController.dispose();
    _photoPageController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _initVideo() async {
    final path = _videoDraft?.finalVideoPath;
    if (!_isVideo || path == null) return;
    final controller = VideoPlayerController.file(File(path));
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _videoController = controller);
    } catch (_) {
      await controller.dispose();
      if (!mounted) return;
      setState(
          () => _error = 'Media belum bisa diproses. Coba pilih ulang media.');
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
            final priceRaw = p['price'] ?? p['discountPrice'] ?? 0;
            return Product(
              id: (p['productId'] ?? p['id'] ?? '').toString(),
              slug: (p['slug'] ?? '').toString(),
              title: (p['name'] ?? p['title'] ?? '').toString(),
              category:
                  (p['variant'] ?? p['category'] ?? 'Pernah Dibeli').toString(),
              brand: '',
              imageUrl: (p['imageUrl'] ?? '').toString(),
              price: priceRaw is num
                  ? priceRaw.toDouble()
                  : double.tryParse(priceRaw.toString()) ?? 0,
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

  /// Buka fullscreen Preview Mode — show bagaimana post akan tampil di
  /// feed sebelum publish. User bisa balik untuk revise atau langsung
  /// Share dari preview.
  Future<void> _openPreview() async {
    AppHaptics.tap();
    // Pause video di-edit screen supaya audio tidak overlap dengan video
    // di preview screen.
    await _videoController?.pause();
    final caption = _captionController.text.trim();
    if (!mounted) return;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => FeedPostPreviewScreen(
          draft: widget.draft,
          videoDraft: _videoDraft,
          caption: caption,
        ),
      ),
    );
    // Setelah balik dari preview, kalau user tekan Share di preview,
    // result == true → langsung upload.
    if (result == true && mounted) {
      await _upload();
    } else {
      // Resume video editor preview.
      await _videoController?.play();
    }
  }

  Future<void> _editCover() async {
    final draft = _videoDraft;
    final path = draft?.finalVideoPath;
    final duration = draft?.finalDuration;
    if (path == null || duration == null) return;
    AppHaptics.tap();
    final selectedMs = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _CoverPickerSheet(
        duration: duration,
        currentThumbnailPath: draft?.thumbnailPath,
      ),
    );
    if (selectedMs == null) return;
    final thumb = await VideoThumbnail.thumbnailFile(
      video: path,
      imageFormat: ImageFormat.JPEG,
      maxWidth: 720,
      timeMs: selectedMs,
      quality: 82,
    );
    if (!mounted || thumb == null) return;
    setState(() {
      _videoDraft = draft?.copyWith(thumbnailPath: thumb);
    });
  }

  Future<void> _upload() async {
    if (_error != null) return;
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
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => FeedUploadProgressScreen(
            draft: draft.copyWith(
              caption: caption,
              taggedProductIds: productIds,
            ),
          ),
        ),
      );
      return;
    }

    final files = widget.draft.photoFiles;
    if (files.isEmpty || files.length > 8) {
      setState(
          () => _error = 'Media belum bisa diproses. Coba pilih ulang media.');
      return;
    }
    await Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => FeedPhotoUploadProgressScreen(
          files: files,
          title: caption.isEmpty ? 'Postingan baru' : caption,
          productIds: productIds,
        ),
      ),
    );
  }

  Future<void> _saveDraftAndExit() async {
    if (_savingDraft) return;
    AppHaptics.tap();
    setState(() => _savingDraft = true);
    final prefs = await SharedPreferences.getInstance();
    final payload = {
      'type': _isVideo ? 'video' : 'image',
      'caption': _captionController.text.trim(),
      'productIds': _selectedProductIds.toList(),
      'media': _isVideo
          ? [_videoDraft?.finalVideoPath].whereType<String>().toList()
          : widget.draft.photoFiles.map((file) => file.path).toList(),
      'thumbnailPath': _videoDraft?.thumbnailPath,
      'savedAt': DateTime.now().millisecondsSinceEpoch,
    };
    await prefs.setString(
      _newPostDraftKey,
      'local|post-new|${jsonEncode(payload)}|${DateTime.now().millisecondsSinceEpoch}',
    );
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
    final captionLength = _captionController.text.characters.length;
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
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _openPreview,
                      child: _MediaPreview(
                        draft: widget.draft,
                        videoDraft: _videoDraft,
                        videoController: _videoController,
                        photoIndex: _photoIndex,
                        photoPageController: _photoPageController,
                        onPhotoChanged: (index) =>
                            setState(() => _photoIndex = index),
                        // Rewire: video tap → open preview (bukan toggle
                        // play/pause). Video tetap auto-loop muted di
                        // editor preview area.
                        onToggleVideo: _openPreview,
                        onEditCover: _editCover,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const _SectionTitle('Caption'),
                    const SizedBox(height: 10),
                    _CaptionField(
                      controller: _captionController,
                      counter: '$captionLength/1000',
                    ),
                    const SizedBox(height: 26),
                    const _SectionTitle(
                      'Tag produk yang pernah dibeli',
                      trailing: Icon(
                        Icons.info_outline_rounded,
                        size: 18,
                        color: Color(0xFF98A2B3),
                      ),
                    ),
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
                ),
              ),
              _BottomActions(
                savingDraft: _savingDraft,
                uploadEnabled: _error == null,
                onSaveDraft: _saveDraftAndExit,
                onUpload: _upload,
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

class _MediaPreview extends StatelessWidget {
  final NewPostMediaDraft draft;
  final FeedCreatePostDraft? videoDraft;
  final VideoPlayerController? videoController;
  final int photoIndex;
  final PageController photoPageController;
  final ValueChanged<int> onPhotoChanged;
  final VoidCallback onToggleVideo;
  final VoidCallback onEditCover;

  const _MediaPreview({
    required this.draft,
    required this.videoDraft,
    required this.videoController,
    required this.photoIndex,
    required this.photoPageController,
    required this.onPhotoChanged,
    required this.onToggleVideo,
    required this.onEditCover,
  });

  @override
  Widget build(BuildContext context) {
    final isVideo = draft.type == NewPostMediaType.video;
    final files = draft.photoFiles;
    // Aspect ratio 4:5 — match Instagram Feed portrait (`width 80, height
    // 100`). Sebelumnya 16:10 landscape — video portrait user terlihat
    // kecil center dengan kanan-kiri kosong. 4:5 accommodate portrait
    // content natural sambil tetap show foto landscape (sedikit
    // letterbox top-bottom acceptable).
    return AspectRatio(
      aspectRatio: 4 / 5,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (isVideo)
              _VideoPreview(
                draft: videoDraft,
                controller: videoController,
                onTap: onToggleVideo,
              )
            else
              PageView.builder(
                controller: photoPageController,
                itemCount: files.length,
                onPageChanged: onPhotoChanged,
                itemBuilder: (context, index) {
                  return Image.file(files[index], fit: BoxFit.cover);
                },
              ),
            if (!isVideo && files.length > 1)
              Positioned(
                top: 16,
                right: 16,
                child: _MediaCounter(text: '${photoIndex + 1}/${files.length}'),
              ),
            if (!isVideo && files.length > 1)
              Positioned(
                left: 0,
                right: 0,
                bottom: 10,
                child: _DotIndicator(
                  length: files.length,
                  index: photoIndex,
                ),
              ),
            if (isVideo)
              Positioned(
                left: 16,
                bottom: 16,
                child: _EditCoverButton(onTap: onEditCover),
              ),
          ],
        ),
      ),
    );
  }
}

class _VideoPreview extends StatelessWidget {
  final FeedCreatePostDraft? draft;
  final VideoPlayerController? controller;
  final VoidCallback onTap;

  const _VideoPreview({
    required this.draft,
    required this.controller,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ctrl = controller;
    final thumb = draft?.thumbnailPath;
    final playing = ctrl?.value.isPlaying ?? false;
    final videoReady = ctrl != null && ctrl.value.isInitialized;
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Thumb cuma render saat video belum ready (loading state) —
          // memberikan preview frame sebentar sebelum VideoPlayer initialize.
          // Setelah video loaded, thumb HILANG supaya kanan-kiri video
          // (yang punya aspect ratio asli) tampil sebagai black screen,
          // bukan thumb yang ke-stretch BoxFit.cover (terlihat seperti blur).
          if (!videoReady && thumb != null)
            Image.file(File(thumb), fit: BoxFit.cover)
          else if (!videoReady)
            const Center(
              child: Icon(
                Icons.play_circle_outline_rounded,
                color: Colors.white54,
                size: 64,
              ),
            ),
          if (videoReady)
            Center(
              child: AspectRatio(
                aspectRatio: ctrl.value.aspectRatio,
                child: VideoPlayer(ctrl),
              ),
            ),
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                child: Center(
                  child: AnimatedOpacity(
                    opacity: playing ? 0 : 1,
                    duration: const Duration(milliseconds: 160),
                    child: Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.42),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 38,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditCoverButton extends StatelessWidget {
  final VoidCallback onTap;

  const _EditCoverButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.46),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.edit_rounded, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text(
                'Edit cover',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MediaCounter extends StatelessWidget {
  final String text;

  const _MediaCounter({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: _newPostInk,
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
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

class _SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;

  const _SectionTitle(this.text, {this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: _newPostInk,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _CaptionField extends StatelessWidget {
  final TextEditingController controller;
  final String counter;

  const _CaptionField({
    required this.controller,
    required this.counter,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLength: 1000,
      minLines: 2,
      maxLines: 4,
      style: const TextStyle(
        color: _newPostInk,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        hintText: 'Ceritakan momen lucu atau seru si kecil...',
        hintStyle: const TextStyle(
          color: Color(0xFF98A2B3),
          fontWeight: FontWeight.w600,
        ),
        counterText: counter,
        counterStyle: const TextStyle(
          color: Color(0xFF98A2B3),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.fromLTRB(16, 15, 16, 12),
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
                if (product.price > 0) ...[
                  const Spacer(),
                  Text(
                    formatRupiah(product.price),
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

class _BottomActions extends StatelessWidget {
  final bool savingDraft;
  final bool uploadEnabled;
  final VoidCallback onSaveDraft;
  final VoidCallback onUpload;

  const _BottomActions({
    required this.savingDraft,
    required this.uploadEnabled,
    required this.onSaveDraft,
    required this.onUpload,
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
                height: 56,
                child: OutlinedButton(
                  onPressed: savingDraft ? null : onSaveDraft,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _newPostBlue,
                    side: const BorderSide(color: _newPostBlue, width: 1.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  child: Text(savingDraft ? 'Menyimpan...' : 'Simpan Draft'),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: SizedBox(
                height: 56,
                child: FilledButton(
                  onPressed: uploadEnabled ? onUpload : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: _newPostBlue,
                    disabledBackgroundColor: const Color(0xFFCBD5E1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  child: const Text('Upload ke Feed'),
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

class _CoverPickerSheet extends StatelessWidget {
  final Duration duration;
  final String? currentThumbnailPath;

  const _CoverPickerSheet({
    required this.duration,
    required this.currentThumbnailPath,
  });

  @override
  Widget build(BuildContext context) {
    final totalMs = duration.inMilliseconds;
    final options = <({String label, int timeMs})>[
      (label: 'Awal', timeMs: 0),
      (label: 'Tengah', timeMs: (totalMs * 0.5).round()),
      (label: 'Akhir', timeMs: (totalMs - 700).clamp(0, totalMs)),
    ];
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(26),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 46,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFD0D5DD),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Edit cover',
              style: TextStyle(
                color: _newPostInk,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                if (currentThumbnailPath != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.file(
                      File(currentThumbnailPath!),
                      width: 84,
                      height: 84,
                      fit: BoxFit.cover,
                    ),
                  ),
                if (currentThumbnailPath != null) const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    children: options.map((option) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          onTap: () => Navigator.pop(context, option.timeMs),
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 13,
                            ),
                            decoration: BoxDecoration(
                              color: _newPostSoft,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: _newPostBorder),
                            ),
                            child: Text(
                              option.label,
                              style: const TextStyle(
                                color: _newPostInk,
                                fontWeight: FontWeight.w900,
                              ),
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

// ─── Preview Mode — fullscreen preview before publish ──────────────

/// Fullscreen preview screen — show how post akan tampil di feed
/// publik. Inspired by Instagram "New reel" → tap "Edit" → preview mode.
///
/// Layout:
///  - Background hitam (immersive)
///  - Media fullscreen di tengah dengan aspect ratio asli
///  - Floating action rail di kanan (heart, comment, share) — UI mockup,
///    tidak interactive (preview only)
///  - Creator avatar + name + caption overlay di bawah
///  - Bottom action bar: "Simpan Draft" + "Upload ke Feed" (real action)
///  - Back button kiri atas
class FeedPostPreviewScreen extends StatefulWidget {
  final NewPostMediaDraft draft;
  final FeedCreatePostDraft? videoDraft;
  final String caption;

  const FeedPostPreviewScreen({
    super.key,
    required this.draft,
    required this.videoDraft,
    required this.caption,
  });

  @override
  State<FeedPostPreviewScreen> createState() => _FeedPostPreviewScreenState();
}

class _FeedPostPreviewScreenState extends State<FeedPostPreviewScreen> {
  VideoPlayerController? _videoController;
  bool _videoReady = false;
  int _photoIndex = 0;
  late final PageController _photoPageController;

  bool get _isVideo => widget.draft.type == NewPostMediaType.video;

  @override
  void initState() {
    super.initState();
    _photoPageController = PageController();
    if (_isVideo) _initVideo();
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _photoPageController.dispose();
    super.dispose();
  }

  Future<void> _initVideo() async {
    final path = widget.videoDraft?.finalVideoPath;
    if (path == null) return;
    final controller = VideoPlayerController.file(File(path));
    _videoController = controller;
    try {
      await controller.initialize();
      if (!mounted || _videoController != controller) return;
      await controller.setLooping(true);
      await controller.setVolume(0);
      await controller.play();
      setState(() => _videoReady = true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _videoReady = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Media fullscreen ──
          Positioned.fill(child: _buildMediaContent()),
          // ── Top chrome: back button + Preview label ──
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  _PreviewRoundButton(
                    icon: Icons.arrow_back_rounded,
                    onTap: () => Navigator.pop(context, false),
                  ),
                  const Expanded(
                    child: Center(
                      child: Text(
                        'Preview',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 44),
                ],
              ),
            ),
          ),
          // ── Right rail: heart / comment / share (mockup, not interactive) ──
          const Positioned(
            right: 14,
            bottom: 200,
            child: _PreviewActionRail(),
          ),
          // ── Bottom-left creator overlay ──
          Positioned(
            left: 16,
            right: 80,
            bottom: 120,
            child: _PreviewCreatorOverlay(caption: widget.caption),
          ),
          // ── Bottom action bar: Simpan Draft + Upload ke Feed ──
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor:
                              Colors.white.withValues(alpha: 0.10),
                          side: const BorderSide(color: Colors.white24),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Simpan Draft',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _newPostBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Upload ke Feed',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaContent() {
    if (_isVideo) {
      final ctrl = _videoController;
      if (_videoReady && ctrl != null && ctrl.value.isInitialized) {
        return Center(
          child: AspectRatio(
            aspectRatio: ctrl.value.aspectRatio,
            child: VideoPlayer(ctrl),
          ),
        );
      }
      final thumb = widget.videoDraft?.thumbnailPath;
      if (thumb != null) {
        return Image.file(File(thumb), fit: BoxFit.contain);
      }
      return const Center(
        child: SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(
            color: Colors.white,
            strokeWidth: 2.4,
          ),
        ),
      );
    }
    // Photo / carousel.
    final files = widget.draft.photoFiles;
    if (files.isEmpty) {
      return const Center(
        child: Icon(Icons.image_outlined, color: Colors.white24, size: 64),
      );
    }
    if (files.length == 1) {
      return Image.file(files.first, fit: BoxFit.contain);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _photoPageController,
          itemCount: files.length,
          onPageChanged: (i) => setState(() => _photoIndex = i),
          itemBuilder: (context, index) {
            return Image.file(files[index], fit: BoxFit.contain);
          },
        ),
        Positioned(
          top: 70,
          right: 14,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${_photoIndex + 1}/${files.length}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PreviewRoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _PreviewRoundButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

/// Right rail mockup — heart, comment, share. NOT interactive — ini cuma
/// show user bagaimana action buttons akan terlihat di feed publik nanti.
class _PreviewActionRail extends StatelessWidget {
  const _PreviewActionRail();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PreviewActionIcon(icon: Icons.favorite_border_rounded, label: '0'),
        SizedBox(height: 22),
        _PreviewActionIcon(
          icon: Icons.mode_comment_outlined,
          label: '0',
        ),
        SizedBox(height: 22),
        _PreviewActionIcon(icon: Icons.send_outlined, label: '0'),
      ],
    );
  }
}

class _PreviewActionIcon extends StatelessWidget {
  final IconData icon;
  final String label;

  const _PreviewActionIcon({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white, size: 32),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _PreviewCreatorOverlay extends StatelessWidget {
  final String caption;

  const _PreviewCreatorOverlay({required this.caption});

  @override
  Widget build(BuildContext context) {
    final profile = memberStore.profile;
    final name = profile?.name ?? 'Kamu';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            ProfileAvatar(
              initial: profile?.initial ?? 'U',
              imageUrl: profile?.profilePhotoUrl,
              size: 34,
              fontSize: 14,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        if (caption.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            caption,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }
}

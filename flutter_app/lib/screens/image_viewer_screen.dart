import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/product.dart';
import '../state/cart_store.dart';
import '../theme/natalo_colors.dart';
import '../utils/formatters.dart';
import '../widgets/app_product_image.dart';

/// Brand blue lokal untuk `VideoProgressIndicator.playedColor` di
/// [_PreviewVideoSlide]. `NataloColors.nataloBlue` = `NataloColors.primary`
/// (0xFF1E5FBF) — jangan referensi private `_brandBlue` dari file lain.
const _brandBlue = NataloColors.nataloBlue;

/// Fullscreen image viewer dengan pinch-to-zoom.
///
/// Default mode tetap generic. Saat dibuka dari Detail Produk, caller bisa
/// mengaktifkan [productMediaViewer] untuk menampilkan counter, thumbnail
/// strip, dan sticky mini product bar.
class ImageViewerScreen extends StatefulWidget {
  /// Pakai salah satu — multi-page `images` ATAU single `url`.
  final List<String>? images;
  final String? url;
  final int initialIndex;
  final bool productMediaViewer;
  final Product? product;
  final ProductVariant? selectedVariant;
  final bool needsVariantSelection;
  final VoidCallback? onSelectVariant;
  final void Function(ProductVariant? variant, int quantity)? onAddToCart;

  /// Video produk opsional. Saat non-kosong → video jadi SLIDE #0 (autoplay
  /// bersuara), foto jadi slide 1+. `initialIndex` adalah index SLIDE
  /// (video=0, foto=1+), bukan index foto.
  final String? videoUrl;
  final String? videoThumbnailUrl;
  final int? videoDurationSec;

  /// Poster fallback (biasanya `product.imageUrl`) diteruskan ke
  /// [_PreviewVideoSlide] saat thumbnail video null/gagal.
  final String? posterImageUrl;

  const ImageViewerScreen({
    super.key,
    this.images,
    this.url,
    this.initialIndex = 0,
    this.productMediaViewer = false,
    this.product,
    this.selectedVariant,
    this.needsVariantSelection = false,
    this.onSelectVariant,
    this.onAddToCart,
    this.videoUrl,
    this.videoThumbnailUrl,
    this.videoDurationSec,
    this.posterImageUrl,
  }) : assert(images != null || url != null,
            'ImageViewerScreen butuh images atau url');

  List<String> get list => images ?? [url!];

  /// True kalau ada video → viewer menampilkan video sebagai slide 0.
  bool get hasVideo => (videoUrl ?? '').isNotEmpty;

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  late final PageController _controller;
  late int _index;
  // Dua sumber lock untuk PageView swipe:
  //  - _zoomed: scale > 1 → user lagi pan zoomed image, swipe page harus
  //    OFF biar pan tidak ke-hijack jadi pindah foto.
  //  - _multiTouch: >=2 jari di layar → user lagi pinch. Detected via
  //    Listener (manual pointer count) supaya KETAUAN langsung di pointer
  //    landing, BEFORE gesture arena resolve. Tanpa ini, arena race antara
  //    PageView.HorizontalDrag vs InteractiveViewer.Scale sering dimenangkan
  //    PageView (drag claim duluan) → pinch GAGAL trigger.
  //
  // PageView physics = NeverScrollable kalau ANY dari dua flag aktif.
  bool _zoomed = false;
  bool _multiTouch = false;
  int _activePointers = 0;

  @override
  void initState() {
    super.initState();
    // Total slide = foto + (video kalau ada). `initialIndex` = index SLIDE.
    final total = widget.hasVideo ? widget.list.length + 1 : widget.list.length;
    final maxIndex = total - 1;
    _index = widget.initialIndex.clamp(0, maxIndex < 0 ? 0 : maxIndex);
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setZoomed(bool value) {
    if (_zoomed == value) return;
    setState(() => _zoomed = value);
  }

  void _onPointerDown(PointerDownEvent _) {
    _activePointers++;
    final next = _activePointers >= 2;
    if (next != _multiTouch) setState(() => _multiTouch = next);
  }

  void _onPointerUp(PointerEvent _) {
    _activePointers = math.max(0, _activePointers - 1);
    final next = _activePointers >= 2;
    if (next != _multiTouch) setState(() => _multiTouch = next);
  }

  bool get _lockSwipe => _zoomed || _multiTouch;

  @override
  Widget build(BuildContext context) {
    final images = widget.list;
    final hasVideo = widget.hasVideo;
    // Total slide: video (kalau ada) di depan, lalu foto.
    final totalSlides = hasVideo ? images.length + 1 : images.length;
    final product = widget.product;
    final showProductChrome = widget.productMediaViewer && product != null;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      // ROOT CAUSE blank-hitam/squished-pojok: Stack default StackFit.loose
      // → kalau Scaffold body kasih constraint longgar (min 0), Stack
      // mengkerut ke ukuran child non-positioned terkecil (tombol back ~48px)
      // → SEMUA isi (PageView, chrome) ter-squish ke kotak kecil pojok
      // kiri-atas, sisanya hitam. SizedBox.expand + StackFit.expand memaksa
      // Stack isi penuh layar apapun constraint-nya.
      body: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Guard: kalau images kosong (data tidak terkirim), jangan render
            // PageView 0-item (layar hitam total + chrome nyangkut di pojok).
            // Tampilkan placeholder eksplisit. Video-only (`hasVideo`) tetap
            // punya 1 slide → jangan placeholder.
            if (images.isEmpty && !hasVideo)
              const Center(
                child: Icon(
                  Icons.image_not_supported_outlined,
                  color: Colors.white38,
                  size: 48,
                ),
              )
            else
              Positioned.fill(
                // Listener wrap PageView — count pointers manually di pre-arena
                // layer (Listener runs BEFORE gesture recognizers). Begitu jari
                // ke-2 nempel → _multiTouch=true → physics lock instan,
                // InteractiveViewer panEnabled=true → pinch claim arena tanpa
                // kompetisi dari PageView.HorizontalDrag.
                child: Listener(
                  onPointerDown: _onPointerDown,
                  onPointerUp: _onPointerUp,
                  onPointerCancel: _onPointerUp,
                  behavior: HitTestBehavior.translucent,
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: totalSlides,
                    onPageChanged: (value) => setState(() => _index = value),
                    physics: _lockSwipe
                        ? const NeverScrollableScrollPhysics()
                        : const PageScrollPhysics(),
                    itemBuilder: (context, i) {
                      // Slide #0 = video (kalau ada). Video BUKAN _ZoomableImage
                      // — tak masuk mesin zoom/multitouch. `active` re-evaluasi
                      // tiap build (onPageChanged → setState _index) → autoplay
                      // hanya saat jadi slide aktif, pause saat pindah.
                      if (hasVideo && i == 0) {
                        return _PreviewVideoSlide(
                          // Key stabil per-URL: pertahankan state controller
                          // saat rebuild (onPageChanged) — resume instan.
                          key: ValueKey('preview-video-${widget.videoUrl}'),
                          videoUrl: widget.videoUrl!,
                          thumbnailUrl: widget.videoThumbnailUrl,
                          posterImageUrl: widget.posterImageUrl,
                          active: _index == 0,
                        );
                      }
                      final imgI = i - (hasVideo ? 1 : 0);
                      return _ZoomableImage(
                        imageUrl: images[imgI],
                        multiTouch: _multiTouch,
                        onZoomChanged: _setZoomed,
                      );
                    },
                  ),
                ),
              ),
            // CRITICAL: Positioned wrap supaya SafeArea TIDAK ke-stretch ke
            // fullscreen oleh StackFit.expand. Tanpa Positioned, SafeArea +
            // IconButton dapat tight constraint full-stack → icon ke-center
            // di tengah layar, dan IconButton hit-test cover SELURUH viewport
            // → semua pinch/swipe/tap ke-consume jadi click back, gesture
            // ke InteractiveViewer/PageView GAK PERNAH SAMPAI.
            Positioned(
              top: 0,
              left: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8, top: 8),
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Kembali',
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                ),
              ),
            ),
            if (showProductChrome) ...[
              Positioned(
                left: 16,
                right: 16,
                bottom: MediaQuery.paddingOf(context).bottom + 96,
                child: _ProductMediaThumbnails(
                  images: images,
                  activeIndex: _index,
                  // `hasVideo` = SATU sumber kebenaran (sama dgn viewer/PageView,
                  // berbasis `videoUrl`). Strip menampilkan item video iff viewer
                  // punya slide video → cegah desync off-by-one. `videoThumbnailUrl`
                  // (thumbnail video → poster produk) HANYA gambar yg ditampilkan.
                  hasVideo: hasVideo,
                  videoThumbnailUrl:
                      widget.videoThumbnailUrl ?? widget.posterImageUrl,
                  videoDurationSec: widget.videoDurationSec,
                  onTap: (index) {
                    _controller.animateToPage(
                      index,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                    );
                  },
                ),
              ),
              Positioned(
                left: 16,
                bottom: MediaQuery.paddingOf(context).bottom + 162,
                child: _ProductMediaCounter(
                  current: _index + 1,
                  total: totalSlides,
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _ProductMediaBar(
                  product: product,
                  selectedVariant: widget.selectedVariant,
                  needsVariantSelection: widget.needsVariantSelection,
                  onSelectVariant: widget.onSelectVariant,
                  onAddToCart: widget.onAddToCart,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Foto fullscreen dengan peek-zoom IG-style.
///
/// Solusi gesture conflict InteractiveViewer↔PageView (known Flutter
/// issue):
///  - **scale=1 (default)**: `panEnabled=false` → InteractiveViewer tidak
///    consume drag 1-jari → swipe horizontal diteruskan ke PageView
///    (navigasi antar foto). Pinch (2-jari scale gesture) tetap detect.
///  - **scale>1 (zoomed)**: `panEnabled=true` → user bisa pan zoomed
///    image bebas. PageView physics di-lock di parent supaya pan tidak
///    hijack jadi swipe.
///  - **Lepas jari**: animasi snap-back ke identity (Matrix4.identity)
///    → scale balik 1 → swipe PageView aktif lagi.
///
/// Callback [onZoomChanged] fire saat zoom state berubah (true=zoomed,
/// false=normal) → parent toggle PageView physics.
class _ZoomableImage extends StatefulWidget {
  final String imageUrl;
  final bool multiTouch;
  final ValueChanged<bool> onZoomChanged;

  const _ZoomableImage({
    required this.imageUrl,
    required this.multiTouch,
    required this.onZoomChanged,
  });

  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage>
    with SingleTickerProviderStateMixin {
  final TransformationController _controller = TransformationController();
  late final AnimationController _anim;
  Animation<Matrix4>? _resetAnim;
  // _isZoomed: scale > threshold (TransformationController-driven).
  // panEnabled effective = widget.multiTouch || _isZoomed.
  // Single-finger di scale=1 → panEnabled false → InteractiveViewer tidak
  // consume horizontal drag → PageView dapat swipe foto.
  bool _isZoomed = false;

  // Posisi tap terakhir (viewport coords) dari onDoubleTapDown — dipakai
  // supaya double-tap zoom TERPUSAT di titik yang di-tap, bukan selalu
  // tengah layar.
  Offset? _doubleTapPosition;

  static const double _zoomedThreshold = 1.02;
  // Level zoom saat double-tap dari kondisi normal. Di antara minScale(1)
  // dan maxScale(4). Pinch tetap bisa lanjut sampai 4x.
  static const double _doubleTapScale = 2.5;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() {
        final m = _resetAnim?.value;
        if (m != null) _controller.value = m;
      });
    _controller.addListener(_onTransform);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTransform);
    _anim.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onTransform() {
    // getMaxScaleOnAxis = effective scale factor dari transformation matrix.
    final scale = _controller.value.getMaxScaleOnAxis();
    final zoomed = scale > _zoomedThreshold;
    if (zoomed != _isZoomed) {
      setState(() => _isZoomed = zoomed);
      widget.onZoomChanged(zoomed);
    }
  }

  void _onInteractionEnd(ScaleEndDetails _) {
    // Snap balik ke identity (ukuran normal) saat jari dilepas, KECUALI
    // sudah di identity. Compare via storage list bukan == karena Matrix4
    // equality tidak reliable.
    final current = _controller.value;
    final isIdentity = current.storage
        .asMap()
        .entries
        .every((e) => e.value == Matrix4.identity().storage[e.key]);
    if (isIdentity) return;
    _animateTo(Matrix4.identity());
  }

  /// Animasi transform dari matrix sekarang ke [target] pakai _anim +
  /// Matrix4Tween. Dipakai bersama untuk snap-back (target=identity) dan
  /// double-tap zoom-in (target=zoomed matrix).
  void _animateTo(Matrix4 target) {
    _resetAnim = Matrix4Tween(
      begin: _controller.value,
      end: target,
    ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));
    _anim.forward(from: 0);
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    _doubleTapPosition = details.localPosition;
  }

  void _handleDoubleTap() {
    final scale = _controller.value.getMaxScaleOnAxis();
    // Sudah zoom → double-tap balikkan ke normal. Masih normal → zoom in
    // ke _doubleTapScale, terpusat di titik tap.
    if (scale > _zoomedThreshold) {
      _animateTo(Matrix4.identity());
      return;
    }
    final position = _doubleTapPosition;
    if (position == null) return;
    // Translate supaya titik tap tetap di posisi layar yang sama setelah
    // di-scale: pt_screen = scale * pt + t → agar tetap, t = -pt*(scale-1).
    final dx = -position.dx * (_doubleTapScale - 1);
    final dy = -position.dy * (_doubleTapScale - 1);
    final target = Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(_doubleTapScale, _doubleTapScale, _doubleTapScale, 1);
    _animateTo(target);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final h = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : MediaQuery.sizeOf(context).height;
        // panEnabled aktif kalau (a) user lagi multi-touch (pinch) — biar
        // ScaleGestureRecognizer langsung claim arena tanpa kompetisi, atau
        // (b) image sudah zoomed — biar 1-finger pan dalam image bebas.
        // Di kondisi default (1 finger + scale=1) panEnabled=false → drag
        // diteruskan ke PageView untuk swipe ke foto lain.
        final panEnabled = widget.multiTouch || _isZoomed;
        // GestureDetector di LUAR InteractiveViewer: onDoubleTapDown
        // localPosition = viewport coords (sama ruang dengan transform
        // InteractiveViewer), jadi zoom bisa terpusat di titik tap.
        // DoubleTap tidak bentrok dengan pinch/pan (tap ≠ drag) maupun
        // PageView swipe (tidak ada aksi single-tap di foto).
        return GestureDetector(
          onDoubleTapDown: _handleDoubleTapDown,
          onDoubleTap: _handleDoubleTap,
          child: InteractiveViewer(
            transformationController: _controller,
            panEnabled: panEnabled,
            scaleEnabled: true,
            minScale: 1,
            maxScale: 4,
            onInteractionEnd: _onInteractionEnd,
            child: Center(
              child: AppProductImage(
                imageUrl: widget.imageUrl,
                width: w,
                height: h,
                fit: BoxFit.contain,
                borderRadius: BorderRadius.zero,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ProductMediaCounter extends StatelessWidget {
  final int current;
  final int total;

  const _ProductMediaCounter({
    required this.current,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF111827).withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$current/$total',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}

class _ProductMediaThumbnails extends StatelessWidget {
  final List<String> images;
  final int activeIndex;
  final ValueChanged<int> onTap;

  /// SATU sumber kebenaran "ada video" — SAMA dgn viewer (`ImageViewerScreen
  /// .hasVideo`, berbasis `videoUrl`). Strip menampilkan item video iff ini
  /// true; TIDAK boleh disimpulkan dari `videoThumbnailUrl != null` (bisa
  /// desync off-by-one kalau thumbnail/poster null tapi videoUrl ada).
  final bool hasVideo;

  /// Gambar untuk thumbnail video (caller resolve: thumbnail video → poster
  /// produk). HANYA gambar; tampil/tidaknya item video ditentukan [hasVideo].
  final String? videoThumbnailUrl;
  final int? videoDurationSec;

  const _ProductMediaThumbnails({
    required this.images,
    required this.activeIndex,
    required this.onTap,
    this.hasVideo = false,
    this.videoThumbnailUrl,
    this.videoDurationSec,
  });

  @override
  Widget build(BuildContext context) {
    // Total item = foto + (video di depan kalau ada). Index item == index SLIDE
    // (video=0, foto ke-k = k+1), jadi onTap(index) langsung ke slide benar.
    final total = hasVideo ? images.length + 1 : images.length;
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: total,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final active = index == activeIndex;
          if (hasVideo && index == 0) {
            return _thumbFrame(
              active: active,
              slideIndex: 0,
              child: _videoThumbContent(active),
            );
          }
          final imgI = index - (hasVideo ? 1 : 0);
          return _thumbFrame(
            active: active,
            slideIndex: index,
            child: AppProductImage(
              imageUrl: images[imgI],
              fit: BoxFit.cover,
              borderRadius: BorderRadius.zero,
            ),
          );
        },
      ),
    );
  }

  /// Bingkai thumbnail 56x56 + border aktif (gaya existing). `child` di-clip
  /// dengan radius yang sama supaya konten (foto / video) tak bocor sudut.
  Widget _thumbFrame({
    required bool active,
    required int slideIndex,
    required Widget child,
  }) {
    return GestureDetector(
      onTap: () => onTap(slideIndex),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 56,
        height: 56,
        padding: EdgeInsets.all(active ? 2 : 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? Colors.white : Colors.white24,
            width: active ? 2 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(active ? 7 : 9),
          child: child,
        ),
      ),
    );
  }

  /// Isi thumbnail video: poster + ▶ overlay + badge durasi (mm:ss unpadded).
  Widget _videoThumbContent(bool active) {
    return Stack(
      fit: StackFit.expand,
      children: [
        AppProductImage(
          imageUrl: videoThumbnailUrl ?? '',
          fit: BoxFit.cover,
          borderRadius: BorderRadius.zero,
        ),
        // Dim tipis biar ▶ + badge kebaca di atas thumbnail terang.
        const ColoredBox(color: Color(0x33000000)),
        Center(
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.play_arrow_rounded,
              color: Colors.white,
              size: 15,
            ),
          ),
        ),
        if (videoDurationSec != null)
          Positioned(
            right: 2,
            bottom: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.68),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _formatVideoDuration(videoDurationSec!),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Format durasi `mm:ss` dengan menit tak di-pad (mis. `0:32`, `1:05`).
/// Mirror `ProductDetailVideoSlide._formatDuration` (file terpisah, private).
String _formatVideoDuration(int totalSeconds) {
  final s = totalSeconds < 0 ? 0 : totalSeconds;
  final m = s ~/ 60;
  final sec = s % 60;
  return '$m:${sec.toString().padLeft(2, '0')}';
}

class _ProductMediaBar extends StatelessWidget {
  final Product product;
  final ProductVariant? selectedVariant;
  final bool needsVariantSelection;
  final VoidCallback? onSelectVariant;
  final void Function(ProductVariant? variant, int quantity)? onAddToCart;

  const _ProductMediaBar({
    required this.product,
    required this.selectedVariant,
    required this.needsVariantSelection,
    this.onSelectVariant,
    this.onAddToCart,
  });

  @override
  Widget build(BuildContext context) {
    final displayPrice = selectedVariant == null
        ? product.finalPrice.round()
        : effectiveCartVariantPrice(product, selectedVariant!);
    final originalPrice = selectedVariant?.price ?? product.price.round();
    final hasDiscount = originalPrice > displayPrice;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding + 12),
      decoration: BoxDecoration(
        color: const Color(0xFF111111).withValues(alpha: 0.96),
        border: const Border(
          top: BorderSide(color: Color(0xFF27272A)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        formatRupiah(displayPrice),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFFF4778),
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
                    ),
                    if (hasDiscount) ...[
                      const SizedBox(width: 8),
                      Text(
                        formatRupiah(originalPrice),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF9CA3AF),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.lineThrough,
                          decorationColor: Color(0xFF9CA3AF),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: () => _handleCta(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFF6B7280)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            child: Text(
              needsVariantSelection ? 'Pilih Varian' : '+ Keranjang',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleCta(BuildContext context) {
    Navigator.of(context).pop();
    if (needsVariantSelection) {
      onSelectVariant?.call();
      return;
    }
    onAddToCart?.call(selectedVariant, 1);
  }
}

/// Slide video di dalam viewer fullscreen (di-wire ke PageView oleh Task 2).
///
/// Beda dengan [ProductDetailVideoSlide] (manual-play, bisu-sampai-tap): slide
/// ini **autoplay BERSUARA saat [active]** — membuka viewer fullscreen =
/// keputusan user, jadi boleh langsung bunyi (default options, bukan mute /
/// mixWithOthers). Saat [active] jadi false → hanya `pause()`; controller
/// **tetap hidup** supaya resume instan saat user bolak-balik antar slide
/// (tidak re-download). Dispose HANYA saat widget dibuang.
///
/// State machine:
/// - poster (belum init) → thumbnail/poster contain di hitam
/// - initializing (`_initializing`) → poster + spinner
/// - ready (`_ready`) → VideoPlayer contain di hitam + progress + mute
/// - failed (`_failed`) → poster + ▶ retry (tap = `_ensure`), BUKAN kotak hitam
///
/// onTap toggle play/pause pakai `HitTestBehavior.opaque` + `onTap` SAJA →
/// tidak meng-claim horizontal drag, jadi PageView parent tetap bisa swipe.
class _PreviewVideoSlide extends StatefulWidget {
  final String videoUrl;
  final String? thumbnailUrl;

  /// Poster fallback saat `thumbnailUrl` null/kosong/gagal — biasanya
  /// `product.imageUrl`. Cegah slide hitam saat thumbnail bermasalah.
  final String? posterImageUrl;

  /// True saat slide ini yang aktif di PageView → autoplay. False → pause
  /// (controller dipertahankan untuk resume instan).
  final bool active;

  const _PreviewVideoSlide({
    super.key,
    required this.videoUrl,
    required this.thumbnailUrl,
    this.posterImageUrl,
    required this.active,
  });

  @override
  State<_PreviewVideoSlide> createState() => _PreviewVideoSlideState();
}

class _PreviewVideoSlideState extends State<_PreviewVideoSlide>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;

  /// True selama `initialize()` in-flight (ada `await` belum selesai). Dipakai:
  /// (a) render spinner, (b) cegah re-entry `_ensure`, (c) single-owner dispose
  /// — saat in-flight `dispose()` TIDAK dispose controller; race guard di
  /// `_ensure` (`!mounted`/`!identical`) yang dispose (cegah double-dispose =
  /// assertion "already disposed").
  bool _initializing = false;

  /// True setelah init sukses → render VideoPlayer.
  bool _ready = false;

  /// True kalau init gagal → poster + ▶ retry (JANGAN kotak hitam).
  bool _failed = false;

  /// Suara: default bersuara (false). Toggle via tombol mute.
  bool _muted = false;

  /// Ikon toggle play/pause yang muncul sekejap lalu fade saat user tap.
  bool _showToggleIcon = false;
  Timer? _toggleIconTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.active) _ensure();
  }

  @override
  void didUpdateWidget(covariant _PreviewVideoSlide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active == widget.active) return;
    final controller = _controller;
    if (!widget.active) {
      // active true→false: pause tapi PERTAHANKAN controller (resume instan).
      if (controller != null && controller.value.isInitialized) {
        unawaited(controller.pause());
      }
    } else {
      // active false→true: controller siap → langsung play; belum ada / masih
      // in-flight / gagal → `_ensure` (bikin atau resume saat init selesai).
      if (controller != null && controller.value.isInitialized) {
        unawaited(controller.play());
      } else {
        _ensure();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _toggleIconTimer?.cancel();
    final controller = _controller;
    _controller = null;
    // Kalau init MASIH in-flight: JANGAN dispose di sini — race guard di
    // `_ensure` yang dispose (`_controller` sudah null → `!identical` true).
    // Dispose ganda controller = assertion "already disposed".
    if (controller != null && !_initializing) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // App ke background / layar terkunci → pause supaya suara tidak lanjut di
    // belakang (ExoPlayer Android terutama; preview ini autoplay BERSUARA).
    // TIDAK auto-resume saat `resumed` — konservatif seperti slide detail
    // (`ProductDetailVideoSlide`); user tap untuk lanjut.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      final controller = _controller;
      if (controller != null &&
          controller.value.isInitialized &&
          controller.value.isPlaying) {
        unawaited(controller.pause());
      }
    }
  }

  /// Pastikan ada controller yang main. Controller sudah ada → play. Belum →
  /// buat, initialize (bersuara, default options), race-guard setelah await,
  /// lalu play kalau `widget.active`. Init gagal → poster + ▶ retry.
  Future<void> _ensure() async {
    final existing = _controller;
    if (existing != null) {
      if (existing.value.isInitialized) unawaited(existing.play());
      return; // masih in-flight → play menyusul saat init selesai.
    }
    if (_initializing) return; // cegah re-entry.
    final url = widget.videoUrl.trim();
    if (url.isEmpty) {
      setState(() => _failed = true);
      return;
    }
    // Default options (BUKAN mixWithOthers, BUKAN setVolume(0) di awal):
    // slide fullscreen sengaja bersuara.
    final c = VideoPlayerController.networkUrl(Uri.parse(url));
    _controller = c;
    setState(() {
      _initializing = true;
      _failed = false;
    });
    try {
      await c.initialize();
      // Race guard SETELAH await: widget lepas / controller sudah di-swap →
      // buang controller lokal, jangan sentuh state lagi.
      if (!mounted || !identical(_controller, c)) {
        _initializing = false;
        unawaited(c.dispose());
        return;
      }
      await c.setLooping(false);
      await c.setVolume(_muted ? 0 : 1);
      if (!mounted || !identical(_controller, c)) {
        _initializing = false;
        unawaited(c.dispose());
        return;
      }
      if (widget.active) unawaited(c.play());
      setState(() {
        _ready = true;
        _initializing = false;
      });
    } catch (_) {
      // Init gagal (URL rusak / hiccup) → poster + ▶ retry, BUKAN kotak hitam.
      if (identical(_controller, c)) _controller = null;
      unawaited(c.dispose());
      if (mounted) {
        setState(() {
          _initializing = false;
          _ready = false;
          _failed = true;
        });
      } else {
        _initializing = false;
      }
    }
  }

  void _togglePlay() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final willPlay = !controller.value.isPlaying;
    unawaited(willPlay ? controller.play() : controller.pause());
    _toggleIconTimer?.cancel();
    setState(() => _showToggleIcon = true);
    // Ikon nongol sekejap lalu fade (saat main). Saat pause overlay ▶ tetap
    // terlihat karena build memaksa ikon saat `!isPlaying`.
    _toggleIconTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _showToggleIcon = false);
    });
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    final controller = _controller;
    if (controller != null) unawaited(controller.setVolume(_muted ? 0 : 1));
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final showVideo =
        _ready && controller != null && controller.value.isInitialized;
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (showVideo) _buildPlaying(controller) else _buildPoster(),
          if (showVideo) ...[
            // Tombol mute (pojok kanan-atas, di bawah zona SafeArea top).
            Positioned(
              top: MediaQuery.paddingOf(context).top + 12,
              right: 12,
              child: GestureDetector(
                onTap: _toggleMute,
                child: Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Icon(
                    _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ),
            // Progress bar tipis, ditaruh di atas zona chrome viewer (Task 2
            // render `_ProductMediaBar` + thumbnails + `_ProductMediaCounter`
            // di atas slide). Counter ada di `bottom + 162` (top-nya ~+187),
            // jadi +192 supaya scrub bar full-width TIDAK ketiban chip counter.
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.paddingOf(context).bottom + 192,
              child: VideoProgressIndicator(
                controller,
                allowScrubbing: true,
                colors: const VideoProgressColors(playedColor: _brandBlue),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Saat main: contain di latar hitam (letterbox — konsisten foto viewer yang
  // juga `BoxFit.contain`). onTap SAJA + opaque supaya PageView tetap bisa swipe.
  Widget _buildPlaying(VideoPlayerController controller) {
    final size = controller.value.size;
    final isPlaying = controller.value.isPlaying;
    // Ikon nampak saat: baru toggle (fade) ATAU sedang pause (affordance resume).
    final showIcon = _showToggleIcon || !isPlaying;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _togglePlay,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.black),
          Center(
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: VideoPlayer(controller),
              ),
            ),
          ),
          Center(
            child: AnimatedOpacity(
              opacity: showIcon ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: _PreviewGlyph(
                icon:
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Belum ready / gagal: poster contain di hitam + spinner (initializing) atau
  // ▶ retry (failed). Tap ▶ = `_ensure` (coba lagi).
  Widget _buildPoster() {
    return Stack(
      fit: StackFit.expand,
      children: [
        _posterImage(),
        if (_initializing)
          const Center(child: CircularProgressIndicator(color: Colors.white))
        else if (_failed)
          Center(
            child: GestureDetector(
              onTap: _ensure,
              child: const _PreviewGlyph(icon: Icons.play_arrow_rounded),
            ),
          ),
      ],
    );
  }

  Widget _posterImage() {
    // Prioritas: thumbnailUrl → posterImageUrl (foto produk) → hitam netral.
    // Contain (bukan cover) supaya konsisten letterbox video.
    final thumb = widget.thumbnailUrl?.trim() ?? '';
    final poster = widget.posterImageUrl?.trim() ?? '';
    if (thumb.isEmpty) return _posterFrom(poster);
    return CachedNetworkImage(
      imageUrl: thumb,
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.contain,
      placeholder: (_, __) => _posterFrom(poster),
      errorWidget: (_, __, ___) => _posterFrom(poster),
    );
  }

  Widget _posterFrom(String url) {
    if (url.isEmpty) return const ColoredBox(color: Colors.black);
    return CachedNetworkImage(
      imageUrl: url,
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.contain,
      placeholder: (_, __) => const ColoredBox(color: Colors.black),
      errorWidget: (_, __, ___) => const ColoredBox(color: Colors.black),
    );
  }
}

/// Lingkaran 64 hitam-transparan + ikon putih 36 — tombol ▶/⏸ [_PreviewVideoSlide].
class _PreviewGlyph extends StatelessWidget {
  final IconData icon;
  const _PreviewGlyph({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: Colors.white, size: 36),
    );
  }
}

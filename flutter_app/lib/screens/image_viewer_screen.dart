import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/product.dart';
import '../state/cart_store.dart';
import '../utils/formatters.dart';
import '../widgets/app_product_image.dart';

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
  }) : assert(images != null || url != null,
            'ImageViewerScreen butuh images atau url');

  List<String> get list => images ?? [url!];

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
    final maxIndex = widget.list.length - 1;
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
          // Tampilkan placeholder eksplisit.
          if (images.isEmpty)
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
                  itemCount: images.length,
                  onPageChanged: (value) => setState(() => _index = value),
                  physics: _lockSwipe
                      ? const NeverScrollableScrollPhysics()
                      : const PageScrollPhysics(),
                  itemBuilder: (context, i) => _ZoomableImage(
                    imageUrl: images[i],
                    multiTouch: _multiTouch,
                    onZoomChanged: _setZoomed,
                  ),
                ),
              ),
            ),
          SafeArea(
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
          if (showProductChrome) ...[
            Positioned(
              left: 16,
              right: 16,
              bottom: MediaQuery.paddingOf(context).bottom + 96,
              child: _ProductMediaThumbnails(
                images: images,
                activeIndex: _index,
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
                total: images.length,
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

  static const double _zoomedThreshold = 1.02;

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
    _resetAnim = Matrix4Tween(
      begin: current,
      end: Matrix4.identity(),
    ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));
    _anim.forward(from: 0);
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
        return InteractiveViewer(
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

  const _ProductMediaThumbnails({
    required this.images,
    required this.activeIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final active = index == activeIndex;
          return GestureDetector(
            onTap: () => onTap(index),
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
              child: AppProductImage(
                imageUrl: images[index],
                fit: BoxFit.cover,
                borderRadius: BorderRadius.circular(active ? 7 : 9),
              ),
            ),
          );
        },
      ),
    );
  }
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

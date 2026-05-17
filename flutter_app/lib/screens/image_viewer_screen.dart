import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/haptics.dart';

/// Fullscreen image viewer dengan **pinch-to-zoom** + **swipe horizontal**
/// + **swipe vertical untuk dismiss**. Native gesture-based, halus 60fps —
/// Capacitor WebView tidak punya equivalent native untuk semua gesture ini
/// (swiper bisa, tapi pinch zoom + swipe-to-dismiss perlu library JS lagi).
class ImageViewerScreen extends StatefulWidget {
  final List<String> images;
  final int initialIndex;
  final String? heroTag;

  const ImageViewerScreen({
    super.key,
    required this.images,
    this.initialIndex = 0,
    this.heroTag,
  });

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  late final PageController _controller;
  late int _activeIndex;
  // Track vertical drag untuk swipe-to-dismiss.
  double _dragOffset = 0;
  bool _isInteractingWithImage = false;

  @override
  void initState() {
    super.initState();
    _activeIndex = widget.initialIndex.clamp(0, widget.images.length - 1);
    _controller = PageController(initialPage: _activeIndex);
    // Sembunyikan status bar untuk full immersion experience.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _controller.dispose();
    super.dispose();
  }

  double get _backgroundOpacity {
    // Fade background out saat drag — visual cue dismiss coming.
    final progress = (_dragOffset.abs() / 240).clamp(0.0, 1.0);
    return 1 - progress * 0.7;
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (_isInteractingWithImage) return;
    setState(() => _dragOffset += details.delta.dy);
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (_dragOffset.abs() > 120 ||
        details.primaryVelocity != null &&
            details.primaryVelocity!.abs() > 600) {
      AppHaptics.tap();
      Navigator.pop(context);
    } else {
      setState(() => _dragOffset = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: _backgroundOpacity),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
          onPressed: () {
            AppHaptics.tap();
            Navigator.pop(context);
          },
        ),
        title: Text(
          '${_activeIndex + 1} / ${widget.images.length}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        centerTitle: true,
      ),
      body: GestureDetector(
        onVerticalDragUpdate: _onVerticalDragUpdate,
        onVerticalDragEnd: _onVerticalDragEnd,
        child: Transform.translate(
          offset: Offset(0, _dragOffset),
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.images.length,
            onPageChanged: (index) {
              AppHaptics.tap();
              setState(() => _activeIndex = index);
            },
            itemBuilder: (context, index) {
              return _ZoomableImage(
                imageUrl: widget.images[index],
                heroTag: index == 0 ? widget.heroTag : null,
                onInteractionStateChanged: (active) {
                  if (_isInteractingWithImage != active) {
                    setState(() => _isInteractingWithImage = active);
                  }
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Single image dengan InteractiveViewer untuk pinch-zoom + pan.
/// Double-tap → toggle 1x ↔ 2x zoom dengan smooth animation.
class _ZoomableImage extends StatefulWidget {
  final String imageUrl;
  final String? heroTag;
  final ValueChanged<bool> onInteractionStateChanged;

  const _ZoomableImage({
    required this.imageUrl,
    required this.heroTag,
    required this.onInteractionStateChanged,
  });

  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage>
    with SingleTickerProviderStateMixin {
  late final TransformationController _transformController;
  late final AnimationController _animationController;
  Animation<Matrix4>? _animation;
  TapDownDetails? _doubleTapDetails;

  @override
  void initState() {
    super.initState();
    _transformController = TransformationController();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..addListener(() {
        if (_animation != null) {
          _transformController.value = _animation!.value;
        }
      });
  }

  @override
  void dispose() {
    _transformController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _onDoubleTapDown(TapDownDetails details) {
    _doubleTapDetails = details;
  }

  void _onDoubleTap() {
    AppHaptics.tap();
    final position = _doubleTapDetails?.localPosition;
    if (position == null) return;
    final isZoomed = _transformController.value != Matrix4.identity();
    Matrix4 target;
    if (isZoomed) {
      target = Matrix4.identity();
    } else {
      // Zoom 2.5x ke titik double-tap.
      target = Matrix4.identity()
        ..translateByDouble(-position.dx * 1.5, -position.dy * 1.5, 0, 1)
        ..scaleByDouble(2.5, 2.5, 1, 1);
    }
    _animation = Matrix4Tween(
      begin: _transformController.value,
      end: target,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutCubic,
      ),
    );
    _animationController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final image = CachedNetworkImage(
      imageUrl: widget.imageUrl,
      fit: BoxFit.contain,
      placeholder: (_, __) => const Center(
        child: SizedBox(
          height: 32,
          width: 32,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white,
          ),
        ),
      ),
      errorWidget: (_, __, ___) => const Center(
        child: Icon(
          Icons.broken_image_outlined,
          color: Colors.white54,
          size: 64,
        ),
      ),
    );

    final wrapped = widget.heroTag != null
        ? Hero(tag: widget.heroTag!, child: image)
        : image;

    return GestureDetector(
      onDoubleTapDown: _onDoubleTapDown,
      onDoubleTap: _onDoubleTap,
      child: InteractiveViewer(
        transformationController: _transformController,
        minScale: 1,
        maxScale: 5,
        onInteractionStart: (_) {
          widget.onInteractionStateChanged(true);
        },
        onInteractionEnd: (_) {
          widget.onInteractionStateChanged(false);
        },
        child: Center(child: wrapped),
      ),
    );
  }
}

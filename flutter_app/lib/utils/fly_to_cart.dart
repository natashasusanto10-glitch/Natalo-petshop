import 'package:flutter/material.dart';

import '../widgets/app_cart_button.dart';
import 'haptics.dart';

/// Animate sebuah mini product image dari posisi source (mis. tombol
/// "Add to Cart") → ke posisi cart icon di AppBar. Pattern Tokopedia /
/// Shopee saat user add product ke keranjang: thumbnail produk fly +
/// shrink + fade ke cart icon dengan curved trajectory (parabolic).
///
/// Usage:
/// ```dart
/// flyImageToCart(
///   context: context,
///   imageUrl: product.imageUrl,
///   sourceKey: _addButtonKey,
/// );
/// ```
///
/// Behavior:
/// - Kalau source atau target render box tidak ditemukan (mis. cart
///   icon belum mount, screen tidak punya AppCartButton), no-op silently.
/// - Animation duration 600ms total: 200ms ease-out fly + 200ms scale-down
///   + 200ms fade-out di akhir.
/// - Image fly via curved path (parabolic arc) — bukan straight line.
///   Lebih natural daripada lerp linear.
/// - Haptic light di pertengahan animation (saat image "land" di cart).
///
/// Performance: pakai Overlay (single entry per call). Auto-cleanup
/// saat animation complete via OverlayEntry.remove(). Tidak block UI.
Future<void> flyImageToCart({
  required BuildContext context,
  required String imageUrl,
  required GlobalKey sourceKey,
}) async {
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return;

  final sourceBox =
      sourceKey.currentContext?.findRenderObject() as RenderBox?;
  final cartBox = AppCartButton.iconKey.currentContext
      ?.findRenderObject() as RenderBox?;
  if (sourceBox == null || cartBox == null) return;

  final sourceOffset = sourceBox.localToGlobal(Offset.zero);
  final sourceSize = sourceBox.size;
  final cartOffset = cartBox.localToGlobal(Offset.zero);
  final cartSize = cartBox.size;

  // Start: tengah dari source button. End: tengah dari cart icon.
  final fromCenter = sourceOffset +
      Offset(sourceSize.width / 2, sourceSize.height / 2);
  final toCenter = cartOffset +
      Offset(cartSize.width / 2, cartSize.height / 2);

  // Insert overlay entry — listen ke flag completed dari stateful child
  // supaya self-remove.
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _FlyToCartOverlay(
      imageUrl: imageUrl,
      from: fromCenter,
      to: toCenter,
      onComplete: () => entry.remove(),
    ),
  );
  overlay.insert(entry);
}

class _FlyToCartOverlay extends StatefulWidget {
  final String imageUrl;
  final Offset from;
  final Offset to;
  final VoidCallback onComplete;

  const _FlyToCartOverlay({
    required this.imageUrl,
    required this.from,
    required this.to,
    required this.onComplete,
  });

  @override
  State<_FlyToCartOverlay> createState() => _FlyToCartOverlayState();
}

class _FlyToCartOverlayState extends State<_FlyToCartOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _t;

  // Image initial size: 64px (cukup besar untuk dilihat user) → shrink
  // ke 18px (cart icon mini) di akhir animation.
  static const double _startSize = 64;
  static const double _endSize = 18;

  // Arc height: how high above the straight line the image lifts during
  // its flight. Negative supaya arc ke atas. Ratio terhadap horizontal
  // distance — supaya arc proporsional.
  static const double _arcRatio = 0.35;

  bool _hapticFired = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _t = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutCubic);
    _ctrl.forward();
    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onComplete();
      }
    });
    _t.addListener(_maybeFireHaptic);
  }

  void _maybeFireHaptic() {
    // Light haptic saat image "land" di cart — ~85% progress (sebelum
    // fade-out fully) supaya user terasa "ada item masuk".
    if (!_hapticFired && _t.value >= 0.85) {
      _hapticFired = true;
      AppHaptics.selection();
    }
  }

  @override
  void dispose() {
    _t.removeListener(_maybeFireHaptic);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (_, __) {
        final t = _t.value;
        // Parabolic arc — interpolate antara from & to dengan offset Y
        // negatif di tengah supaya curve ke atas.
        final lerpX = widget.from.dx + (widget.to.dx - widget.from.dx) * t;
        final lerpY = widget.from.dy + (widget.to.dy - widget.from.dy) * t;
        final horizontalDist = (widget.to.dx - widget.from.dx).abs();
        final arcHeight = horizontalDist * _arcRatio;
        // sin(pi * t) = 0 di t=0/1, 1 di t=0.5 → bell curve, peak di
        // tengah animation.
        final arcOffset = -arcHeight * _sinPi(t);
        final size = _startSize + (_endSize - _startSize) * t;
        // Fade out di 80% terakhir — visible most of animation, hilang
        // saat sampai cart icon (overlap dgn cart icon pulse).
        final opacity = t < 0.8 ? 1.0 : (1 - (t - 0.8) / 0.2);
        return Positioned(
          left: lerpX - size / 2,
          top: lerpY + arcOffset - size / 2,
          width: size,
          height: size,
          child: IgnorePointer(
            child: Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.network(
                  widget.imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: const Color(0xFFE5E7EB),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// sin(pi * t) approximation — tidak import 'dart:math' untuk satu
  /// pakai. Math.sin available di dart:math, lebih simple.
  double _sinPi(double t) {
    // Taylor expansion is overkill — pakai dart:math.sin via inline:
    // tapi tidak bisa tanpa import. Trick: pakai parabola approximation
    // 4*t*(1-t) yang mirip sin(pi*t) (peak 1 di tengah, 0 di edges).
    return 4 * t * (1 - t);
  }
}

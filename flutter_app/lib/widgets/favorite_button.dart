import 'package:flutter/material.dart';

import '../models/product.dart';
import '../theme/natalo_colors.dart';
import '../utils/haptics.dart';

/// Heart toggle untuk wishlist / favorites. Stub minimal: client-side
/// toggle state, tidak sync ke server. TODO: integrate dengan
/// favoritesStore + /api/member/favorites.
///
/// Premium polish (Tier 2):
/// - Scale-bounce 1.0 → 1.35 → 1.0 saat tap (320ms easeOutBack)
/// - Color crossfade outline → solid danger saat toggle on
/// - Subtle haptic tap (sudah ada via AppHaptics.tap)
class FavoriteButton extends StatefulWidget {
  /// Bisa dipanggil dengan `productId` saja atau dengan `product` (extract id).
  final String? productId;
  final Product? product;
  final bool initialFavorite;
  final double size;
  /// Kalau true, tombol punya shadow + bg circle (untuk overlay di image).
  final bool elevated;

  const FavoriteButton({
    super.key,
    this.productId,
    this.product,
    this.initialFavorite = false,
    this.size = 24,
    this.elevated = false,
  }) : assert(productId != null || product != null,
            'FavoriteButton butuh productId atau product');

  String get effectiveProductId => productId ?? product!.id;

  @override
  State<FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<FavoriteButton>
    with SingleTickerProviderStateMixin {
  late bool _favorite = widget.initialFavorite;
  late final AnimationController _bounceCtrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _bounceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    // Bounce curve: 1.0 → 1.35 → 1.0 dengan easeOutBack overshoot di puncak.
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.35)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.35, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 55,
      ),
    ]).animate(_bounceCtrl);
  }

  @override
  void dispose() {
    _bounceCtrl.dispose();
    super.dispose();
  }

  void _toggle() {
    AppHaptics.tap();
    setState(() => _favorite = !_favorite);
    _bounceCtrl.forward(from: 0);
    // TODO: sync ke favoritesStore + POST /api/member/favorites/{productId}.
  }

  @override
  Widget build(BuildContext context) {
    // Color crossfade via AnimatedSwitcher pada icon — outline ↔ solid.
    // Icon swap pakai key beda supaya AnimatedSwitcher detect change.
    final iconColor =
        _favorite ? NataloColors.danger : NataloColors.textSecondary;
    final icon = AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.7, end: 1.0).animate(anim),
          child: child,
        ),
      ),
      child: Icon(
        _favorite ? Icons.favorite_rounded : Icons.favorite_outline_rounded,
        key: ValueKey(_favorite),
        color: iconColor,
        size: widget.size * 0.55,
      ),
    );

    final animatedIcon = ScaleTransition(
      scale: _scale,
      child: icon,
    );

    final button = InkResponse(
      onTap: _toggle,
      radius: widget.size,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Center(child: animatedIcon),
      ),
    );
    if (!widget.elevated) return button;
    return Material(
      color: Colors.white,
      elevation: 2,
      shape: const CircleBorder(),
      child: button,
    );
  }
}

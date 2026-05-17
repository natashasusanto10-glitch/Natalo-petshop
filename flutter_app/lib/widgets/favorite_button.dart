import 'package:flutter/material.dart';

import '../models/product.dart';
import '../theme/natalo_colors.dart';
import '../utils/haptics.dart';

/// Heart toggle untuk wishlist / favorites. Stub minimal: client-side
/// toggle state, tidak sync ke server. TODO: integrate dengan
/// favoritesStore + /api/member/favorites.
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

class _FavoriteButtonState extends State<FavoriteButton> {
  late bool _favorite = widget.initialFavorite;

  void _toggle() {
    AppHaptics.tap();
    setState(() => _favorite = !_favorite);
    // TODO: sync ke favoritesStore + POST /api/member/favorites/{productId}.
  }

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      _favorite ? Icons.favorite_rounded : Icons.favorite_outline_rounded,
      color: _favorite ? NataloColors.danger : NataloColors.textSecondary,
      size: widget.size * 0.55,
    );
    final button = InkResponse(
      onTap: _toggle,
      radius: widget.size,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Center(child: icon),
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

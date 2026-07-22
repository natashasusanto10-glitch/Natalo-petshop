import 'package:flutter/material.dart';

import '../models/product.dart';
import '../services/api_client.dart';
import '../state/favorite_store.dart';
import '../theme/natalo_colors.dart';
import '../utils/haptics.dart';
import 'app_toast.dart';

/// Heart toggle untuk wishlist / favorites.
///
/// Wire ke `favoriteStore`:
/// - Listen state via AnimatedBuilder supaya icon auto-update kalau
///   state berubah dari tempat lain (mis. WishlistScreen hapus item).
/// - Tap → `favoriteStore.toggle(product)` yang sync ke server via
///   `/api/member/favorites` (POST/DELETE). Failure auto-revert state.
/// - Kalau user tidak login, snackbar hint + action button "Masuk".
///
/// Premium polish (Tier 2):
/// - Scale-bounce 1.0 → 1.35 → 1.0 saat tap (320ms easeOutBack)
/// - Color crossfade outline → solid danger saat toggle on
/// - Subtle haptic tap (AppHaptics.tap)
class FavoriteButton extends StatefulWidget {
  /// Bisa dipanggil dengan `productId` saja atau dengan `product` (extract id).
  final String? productId;
  final Product? product;

  /// Fallback state — dipakai kalau favoriteStore belum loaded. Setelah
  /// store loaded, state dari store yang dipakai.
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
  }) : assert(
          productId != null || product != null,
          'FavoriteButton butuh productId atau product',
        );

  String get effectiveProductId => productId ?? product!.id;

  @override
  State<FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<FavoriteButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounceCtrl;
  late final Animation<double> _scale;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _bounceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 1.35,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.35,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 55,
      ),
    ]).animate(_bounceCtrl);

    // Fire-and-forget hydrate dari /api/member/favorites — kalau user
    // baru buka app, ensure store ke-load sebelum interact.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      favoriteStore.ensureLoaded();
    });
  }

  @override
  void dispose() {
    _bounceCtrl.dispose();
    super.dispose();
  }

  bool _isFavorite() {
    if (favoriteStore.loaded) {
      return favoriteStore.isFavorite(widget.effectiveProductId);
    }
    return widget.initialFavorite;
  }

  Future<void> _toggle() async {
    if (_saving) return;
    final product = widget.product;
    if (product == null) {
      // Productless usage — tidak bisa toggle, hanya display state.
      return;
    }
    AppHaptics.tap();
    _bounceCtrl.forward(from: 0);
    setState(() => _saving = true);
    try {
      await favoriteStore.toggle(product);
    } on FavoriteAuthRequiredException {
      if (!mounted) return;
      AppToast.showBanner(
        context,
        'Login member untuk menyimpan ke wishlist.',
        kind: ToastKind.info,
        actionLabel: 'Masuk',
        onAction: () => Navigator.pushNamed(context, '/member/login'),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      AppToast.showBanner(
        context,
        'Gagal simpan wishlist: ${error.message}',
        kind: ToastKind.error,
      );
    } catch (error) {
      if (!mounted) return;
      AppToast.showBanner(
        context,
        'Gagal simpan wishlist: $error',
        kind: ToastKind.error,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: favoriteStore,
      builder: (context, _) {
        final favorite = _isFavorite();
        final iconColor =
            favorite ? NataloColors.danger : NataloColors.textSecondary;
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
            favorite ? Icons.favorite_rounded : Icons.favorite_outline_rounded,
            key: ValueKey(favorite),
            color: iconColor,
            size: widget.size * 0.55,
          ),
        );

        final animatedIcon = ScaleTransition(scale: _scale, child: icon);

        final button = Material(
          color: widget.elevated ? Colors.white : Colors.transparent,
          elevation: widget.elevated ? 2 : 0,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _toggle,
            excludeFromSemantics: true,
            customBorder: const CircleBorder(),
            splashFactory: NoSplash.splashFactory,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            overlayColor:
                const WidgetStatePropertyAll<Color>(Colors.transparent),
            child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: Center(child: animatedIcon),
            ),
          ),
        );
        return Semantics(
          button: true,
          label: favorite ? 'Hapus dari wishlist' : 'Tambahkan ke wishlist',
          child: button,
        );
      },
    );
  }
}

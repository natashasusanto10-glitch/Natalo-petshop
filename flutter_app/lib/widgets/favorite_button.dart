import 'package:flutter/material.dart';

import '../models/product.dart';
import '../state/favorite_store.dart';
import '../state/member_store.dart';
import '../utils/haptics.dart';
import '../utils/motion_prefs.dart';
import '../utils/read_only_mode.dart';
import 'app_toast.dart';
import 'app_ui.dart';

/// Wishlist heart button dengan pump animation saat tap.
/// - Tap → optimistic UI (state berubah instant via favoriteStore)
/// - Heart icon pump (scale 1.0 → 1.4 → 1.0 elastic) saat dari unliked
///   menjadi liked → kasih positive feedback
/// - Custom toast slide-from-top instead of bottom SnackBar
/// - Respect MotionPrefs.shouldReduce
class FavoriteButton extends StatefulWidget {
  final Product product;
  final double size;
  final bool elevated;

  const FavoriteButton({
    super.key,
    required this.product,
    this.size = 44,
    this.elevated = true,
  });

  @override
  State<FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<FavoriteButton>
    with SingleTickerProviderStateMixin {
  bool _busy = false;
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    favoriteStore.ensureLoaded();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1.0, end: 1.4)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1.4, end: 1.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 60,
      ),
    ]).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_busy) return;
    if (!memberStore.isLoggedIn) {
      AppToast.show(
        context,
        'Login member untuk menyimpan wishlist.',
        kind: ToastKind.info,
      );
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) Navigator.pushNamed(context, '/member/login');
      });
      return;
    }

    AppHaptics.tap();
    setState(() => _busy = true);
    final wasLikedBefore = favoriteStore.isFavorite(widget.product.id);
    try {
      final added = await favoriteStore.toggle(widget.product);
      if (!mounted) return;
      // Trigger pump animation kalau ini transition unliked → liked.
      if (added && !wasLikedBefore && !MotionPrefs.shouldReduce(context)) {
        _controller
          ..reset()
          ..forward();
      }
      AppToast.show(
        context,
        added ? 'Masuk wishlist 💖' : 'Dihapus dari wishlist',
        kind: added ? ToastKind.success : ToastKind.info,
        icon: added
            ? Icons.favorite_rounded
            : Icons.favorite_border_rounded,
      );
    } on ReadOnlyModeException catch (e) {
      if (!mounted) return;
      showReadOnlySnackbar(context, e);
    } catch (error) {
      if (!mounted) return;
      AppToast.show(
        context,
        'Gagal: $error',
        kind: ToastKind.error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: favoriteStore,
      builder: (context, _) {
        final active = favoriteStore.isFavorite(widget.product.id);
        return Tooltip(
          message: active ? 'Hapus dari wishlist' : 'Tambah wishlist',
          child: AppPressable(
            onTap: _busy ? null : _toggle,
            borderRadius: BorderRadius.circular(999),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              height: widget.size,
              width: widget.size,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.94)),
                boxShadow: widget.elevated
                    ? [
                        BoxShadow(
                          color:
                              const Color(0xFF60A5FA).withValues(alpha: 0.08),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ]
                    : null,
              ),
              child: _busy
                  ? Padding(
                      padding: EdgeInsets.all(widget.size * 0.28),
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    )
                  : AnimatedBuilder(
                      animation: _scale,
                      builder: (context, _) {
                        return Transform.scale(
                          scale: _scale.value,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            transitionBuilder: (child, anim) =>
                                ScaleTransition(scale: anim, child: child),
                            child: Icon(
                              active
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              key: ValueKey(active),
                              color: active
                                  ? const Color(0xFFDB2777)
                                  : const Color(0xFF1E5FBF),
                              size: widget.size * 0.54,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        );
      },
    );
  }
}

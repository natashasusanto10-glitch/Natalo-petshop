import 'package:flutter/material.dart';

import '../state/cart_store.dart';
import '../theme/natalo_colors.dart';
import '../utils/action_throttle.dart';

/// Cart icon dengan badge jumlah item. Diletakkan di AppBar action.
/// Auto-rebuild saat cartStore change.
///
/// Premium polish (Tier 3): badge pulse-scale 1.0 → 1.4 → 1.0 saat count
/// naik (item ditambah ke cart). Animation di-trigger by detecting count
/// transition (prev < current) via StatefulWidget local state. Tidak
/// pulse saat count turun (item removed) atau saat first build.
class AppCartButton extends StatefulWidget {
  final VoidCallback? onPressed;

  const AppCartButton({super.key, this.onPressed});

  /// Cart icon ada di BANYAK screen (Beranda, Produk, Wishlist, dst).
  /// IndexedStack keep semua tab alive → multiple AppCartButton coexist.
  /// Static GlobalKey TIDAK boleh dipakai untuk multi-instance — Flutter
  /// rule: 1 GlobalKey = 1 widget. Sebelumnya pakai single static key
  /// → bug "cart icon hilang dari Beranda" karena Flutter diam-diam
  /// drop instance kedua.
  ///
  /// Fix: per-instance key di state + static `activeIconKey` yang track
  /// instance terakhir attached. `flyImageToCart()` baca `activeIconKey`
  /// untuk dapat posisi target. Default ke instance latest visible
  /// (yang user lihat saat tap "Add to Cart") — tetap akurat untuk
  /// 99% kasus karena animation fly DI screen yang sama.
  static GlobalKey? _activeIconKey;

  /// Cart icon yang sedang attached terakhir — null kalau belum ada
  /// AppCartButton yang ke-build (mis. di splash / login screen).
  static GlobalKey? get activeIconKey => _activeIconKey;

  @override
  State<AppCartButton> createState() => _AppCartButtonState();
}

class _AppCartButtonState extends State<AppCartButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseScale;
  // Per-instance GlobalKey supaya tidak konflik dengan AppCartButton lain
  // yang concurrent alive di tab lain (IndexedStack).
  final GlobalKey _iconKey = GlobalKey(debugLabel: 'AppCartButton-icon');
  final ActionThrottle _tapThrottle = ActionThrottle(
    interval: const Duration(milliseconds: 450),
  );
  int _prevCount = 0;

  @override
  void initState() {
    super.initState();
    _prevCount = cartStore.count;
    // Register sebagai active cart icon — flyImageToCart() akan target
    // posisi key ini. Multiple register OK, latest wins (biasanya tab
    // aktif terakhir di-build).
    AppCartButton._activeIconKey = _iconKey;
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
    );
    _pulseScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.4)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.4, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 60,
      ),
    ]).animate(_pulseCtrl);

    cartStore.addListener(_onCartChanged);
  }

  @override
  void dispose() {
    // Clear activeIconKey hanya kalau masih nunjuk ke instance ini —
    // kalau instance lain sudah overwrite (mis. user pindah tab),
    // biarkan saja supaya `activeIconKey` tetap pointing ke yang aktif.
    if (AppCartButton._activeIconKey == _iconKey) {
      AppCartButton._activeIconKey = null;
    }
    cartStore.removeListener(_onCartChanged);
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Setiap kali widget jadi visible (tab switch dengan IndexedStack
    // tidak rebuild state, tapi rebuild widget tree), claim active key
    // supaya fly-to-cart animation target icon yang user lihat sekarang.
    AppCartButton._activeIconKey = _iconKey;
  }

  void _onCartChanged() {
    final newCount = cartStore.count;
    // Pulse hanya saat count NAIK — bukan saat remove / clear / first sync.
    if (newCount > _prevCount && mounted) {
      _pulseCtrl.forward(from: 0);
    }
    _prevCount = newCount;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: cartStore,
      builder: (context, _) {
        final count = cartStore.count;
        return Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              tooltip: 'Keranjang',
              // Warna onSurface eksplisit (default M3 IconButton = abu
              // onSurfaceVariant) + chrome rapat samakan dgn AppHeaderIconButton
              // → ikon header hitam & jaraknya konsisten.
              color: Theme.of(context).colorScheme.onSurface,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              constraints: const BoxConstraints(minWidth: 34, minHeight: 44),
              // shrinkWrap: tanpa ini MaterialTapTargetSize.padded tetap
              // melebarkan layout ke 48px → gap antar ikon header jauh.
              style: IconButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => _tapThrottle.run(
                widget.onPressed ?? () => Navigator.pushNamed(context, '/cart'),
              ),
              // Wrap icon dgn KeyedSubtree(key: _iconKey) — per-instance
              // key supaya tidak konflik dengan AppCartButton di tab lain.
              // flyImageToCart() lookup via AppCartButton.activeIconKey
              // yang track instance terakhir aktif.
              icon: KeyedSubtree(
                key: _iconKey,
                child: const Icon(Icons.shopping_cart_outlined),
              ),
            ),
            if (count > 0)
              Positioned(
                right: 6,
                top: 6,
                child: ScaleTransition(
                  scale: _pulseScale,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: NataloColors.danger,
                      borderRadius: BorderRadius.circular(8),
                      // Soft red glow saat pulse — subtle, hanya kerasa saat
                      // animation aktif (transparent saat resting karena
                      // shadow blur kecil + opacity rendah).
                      boxShadow: [
                        BoxShadow(
                          color: NataloColors.danger.withValues(alpha: 0.45),
                          blurRadius: 6,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    constraints: const BoxConstraints(minWidth: 16),
                    child: Text(
                      count > 99 ? '99+' : '$count',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

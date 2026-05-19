import 'package:flutter/material.dart';

import '../state/cart_store.dart';
import '../theme/natalo_colors.dart';

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

  @override
  State<AppCartButton> createState() => _AppCartButtonState();
}

class _AppCartButtonState extends State<AppCartButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseScale;
  int _prevCount = 0;

  @override
  void initState() {
    super.initState();
    _prevCount = cartStore.count;
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
    cartStore.removeListener(_onCartChanged);
    _pulseCtrl.dispose();
    super.dispose();
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
              onPressed: widget.onPressed ??
                  () => Navigator.pushNamed(context, '/cart'),
              icon: const Icon(Icons.shopping_cart_outlined),
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

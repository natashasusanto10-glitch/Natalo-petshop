import 'package:flutter/material.dart';

import '../state/cart_store.dart';
import '../theme/natalo_colors.dart';

/// Cart icon dengan badge jumlah item. Diletakkan di AppBar action.
/// Auto-rebuild saat cartStore change.
class AppCartButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const AppCartButton({super.key, this.onPressed});

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
              onPressed:
                  onPressed ?? () => Navigator.pushNamed(context, '/cart'),
              icon: const Icon(Icons.shopping_cart_outlined),
            ),
            if (count > 0)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: NataloColors.danger,
                    borderRadius: BorderRadius.circular(8),
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
          ],
        );
      },
    );
  }
}

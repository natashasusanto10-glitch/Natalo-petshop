import 'package:flutter/material.dart';

import '../models/cart_item.dart';
import '../state/cart_store.dart';
import '../theme/natalo_colors.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import '../widgets/app_product_image.dart';
import '../widgets/app_ui.dart';
import '../widgets/bottom_nav.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  void _openCheckout(BuildContext context) {
    Navigator.pushNamed(context, '/checkout');
  }

  Future<void> _removeWithUndo(BuildContext context, CartItem item) async {
    AppHaptics.tap();
    await cartStore.remove(item.key);
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Produk telah dihapus'),
        duration: const Duration(milliseconds: 1400),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Batalkan',
          onPressed: () => cartStore.addItem(item),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F9FF),
      appBar: AppBar(
        title: const Text('Keranjang'),
        actions: [
          AnimatedBuilder(
            animation: cartStore,
            builder: (context, _) {
              if (cartStore.isEmpty) return const SizedBox.shrink();
              return IconButton(
                tooltip: 'Kosongkan keranjang',
                onPressed: () async {
                  AppHaptics.tap();
                  final count = cartStore.count;
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text('Yakin mau hapus $count produk?'),
                      content: const Text(
                        'Semua produk di keranjang akan dihapus.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Batal'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Hapus'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) {
                    await cartStore.clear();
                  }
                },
                icon: const Icon(Icons.delete_outline_rounded),
              );
            },
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: cartStore,
        builder: (context, _) {
          if (cartStore.isEmpty) {
            return const AppEmptyState(
              icon: Icons.shopping_cart_outlined,
              title: 'Keranjang kosong',
              subtitle: 'Yuk, jelajahi produk dan tambahkan ke keranjang.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 180),
            itemCount: cartStore.items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final item = cartStore.items[index];
              return _CartItemCard(
                item: item,
                onRemove: () => _removeWithUndo(context, item),
              );
            },
          );
        },
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: cartStore,
            builder: (context, _) {
              if (cartStore.isEmpty) return const SizedBox.shrink();
              return SafeArea(
                top: false,
                bottom: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      top: BorderSide(
                          color: Colors.black.withValues(alpha: 0.06)),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.07),
                        blurRadius: 20,
                        offset: const Offset(0, -8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Total',
                              style: TextStyle(
                                color: NataloColors.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              formatRupiah(cartStore.subtotal),
                              style: const TextStyle(
                                color: NataloColors.textPrimary,
                                fontWeight: FontWeight.w900,
                                fontSize: 20,
                              ),
                            ),
                          ],
                        ),
                      ),
                      FilledButton(
                        onPressed: () => _openCheckout(context),
                        child: const Text('Checkout'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const BottomNavBar(currentIndex: 3),
        ],
      ),
    );
  }
}

class _CartItemCard extends StatelessWidget {
  final CartItem item;
  final VoidCallback onRemove;

  const _CartItemCard({
    required this.item,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final maxStock =
        item.effectiveStock <= 0 ? item.quantity : item.effectiveStock;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.pushNamed(
          context,
          '/product-detail',
          arguments: item.product,
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: AppProductImage(
                  imageUrl: item.imageUrl,
                  width: 76,
                  height: 76,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: NataloColors.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    if (item.variantLabel != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        item.variantLabel!,
                        style: const TextStyle(
                          color: NataloColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      formatRupiah(item.unitPrice),
                      style: const TextStyle(
                        color: NataloColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        IconButton.filledTonal(
                          onPressed: onRemove,
                          icon: const Icon(Icons.delete_outline_rounded),
                          iconSize: 18,
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: item.quantity <= 1
                              ? onRemove
                              : () {
                                  AppHaptics.tap();
                                  cartStore.updateQuantity(
                                    item.key,
                                    item.quantity - 1,
                                  );
                                },
                          icon: const Icon(Icons.remove_rounded),
                        ),
                        SizedBox(
                          width: 34,
                          child: Text(
                            '${item.quantity}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: item.quantity >= maxStock
                              ? null
                              : () {
                                  AppHaptics.tap();
                                  cartStore.updateQuantity(
                                    item.key,
                                    item.quantity + 1,
                                  );
                                },
                          icon: const Icon(Icons.add_rounded),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

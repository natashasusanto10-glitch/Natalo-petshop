import 'package:flutter/material.dart';

import '../models/cart_item.dart';
import '../state/cart_store.dart';
import '../theme/natalo_colors.dart';
import '../utils/formatters.dart';
import '../widgets/app_ui.dart';

/// Checkout screen — list ringkasan item, hitung total, lalu hand off ke
/// payment flow. Stub minimal: terima `items` opsional (untuk Buy Now flow
/// yang bypass cart), atau pakai semua isi cart kalau tidak ada.
class CheckoutScreen extends StatelessWidget {
  /// Item override — kalau diberikan, checkout pakai list ini bukan cartStore.
  final List<CartItem>? items;

  const CheckoutScreen({super.key, this.items});

  @override
  Widget build(BuildContext context) {
    final lineItems = items ?? cartStore.items;
    final total = lineItems.fold<int>(0, (s, it) => s + it.lineTotal);
    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: lineItems.isEmpty
          ? const AppEmptyState(
              icon: Icons.shopping_bag_outlined,
              title: 'Tidak ada item',
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Item',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        for (final item in lineItems)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${item.product.title}'
                                    '${item.variantLabel == null ? "" : " — ${item.variantLabel}"}'
                                    ' × ${item.quantity}',
                                  ),
                                ),
                                Text(formatRupiah(item.lineTotal)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const AppInfoBanner(
                  message: 'Flow lengkap (alamat + kurir + pembayaran) '
                      'belum diport ke Flutter.',
                ),
              ],
            ),
      bottomNavigationBar: lineItems.isEmpty
          ? null
          : AppGlassBottomBar(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Total'),
                        Text(
                          formatRupiah(total),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                            color: NataloColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content:
                              Text('Pembayaran belum tersedia di Flutter app.'),
                        ),
                      );
                    },
                    child: const Text('Lanjut Bayar'),
                  ),
                ],
              ),
            ),
    );
  }
}

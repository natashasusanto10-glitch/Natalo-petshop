import 'package:flutter/material.dart';

import '../state/cart_store.dart';
import '../state/member_store.dart';
import '../theme/natalo_colors.dart';
import '../utils/formatters.dart';
import '../widgets/app_cart_button.dart';

/// Home screen — landing utama. Stub menampilkan greeting + cart count +
/// quick nav grid ke halaman utama. Real implementation: hero banner,
/// featured products, brand strip, dst (port dari app/page.tsx).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Natalo Petshop'),
        actions: const [AppCartButton()],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            AnimatedBuilder(
              animation: memberStore,
              builder: (context, _) {
                final profile = memberStore.profile;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const CircleAvatar(
                          radius: 24,
                          backgroundColor: NataloColors.primary,
                          child: Icon(
                            Icons.pets_rounded,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                profile == null
                                    ? 'Halo, tamu'
                                    : 'Halo, ${profile.name}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                profile == null
                                    ? 'Login untuk akses pesanan + voucher'
                                    : profile.email ?? profile.phone ?? '',
                                style: const TextStyle(
                                  color: NataloColors.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (profile == null)
                          FilledButton(
                            onPressed: () => Navigator.pushNamed(
                              context,
                              '/member/login',
                            ),
                            child: const Text('Login'),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            _QuickGrid(),
            const SizedBox(height: 16),
            AnimatedBuilder(
              animation: cartStore,
              builder: (context, _) {
                if (cartStore.isEmpty) return const SizedBox.shrink();
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.shopping_cart_rounded),
                    title: Text('${cartStore.count} item di keranjang'),
                    subtitle: Text(
                      'Total: ${formatRupiah(cartStore.subtotal)}',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.pushNamed(context, '/cart'),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickGrid extends StatelessWidget {
  static const _items = [
    _QuickItem(Icons.storefront_rounded, 'Produk', '/products'),
    _QuickItem(Icons.local_offer_rounded, 'Brand', '/brands'),
    _QuickItem(Icons.video_library_rounded, 'Feed', '/feed'),
    _QuickItem(Icons.favorite_rounded, 'Wishlist', '/wishlist'),
    _QuickItem(Icons.receipt_long_rounded, 'Pesanan', '/member/orders'),
    _QuickItem(Icons.person_rounded, 'Akun', '/member'),
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.05,
      ),
      itemBuilder: (context, i) {
        final item = _items[i];
        return Card(
          child: InkWell(
            onTap: () => Navigator.pushNamed(context, item.route),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    item.icon,
                    size: 28,
                    color: NataloColors.primary,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.label,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _QuickItem {
  final IconData icon;
  final String label;
  final String route;
  const _QuickItem(this.icon, this.label, this.route);
}

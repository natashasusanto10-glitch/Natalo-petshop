import 'package:flutter/material.dart';

import '../models/product.dart';
import '../services/product_service.dart';
import '../theme/natalo_colors.dart';
import '../utils/formatters.dart';
import '../widgets/app_cart_button.dart';
import '../widgets/app_product_image.dart';
import '../widgets/app_ui.dart';

/// Products catalog screen. Accept opsional filter awal dari navigation.
class ProductsScreen extends StatefulWidget {
  final String? selectedBrand;
  final String? initialQuery;
  final String? initialCategory;

  const ProductsScreen({
    super.key,
    this.selectedBrand,
    this.initialQuery,
    this.initialCategory,
  });

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  late Future<List<Product>> _future;

  @override
  void initState() {
    super.initState();
    _future = productService.fetchAll(
      brand: widget.selectedBrand,
      category: widget.initialCategory,
      query: widget.initialQuery,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Produk'),
        actions: const [AppCartButton()],
      ),
      body: FutureBuilder<List<Product>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const AppSkeletonList();
          final products = snapshot.data!;
          if (products.isEmpty) {
            return const AppEmptyState(
              icon: Icons.search_off_rounded,
              title: 'Belum ada produk',
              subtitle: 'Coba ubah filter atau cek koneksi internet.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: products.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final p = products[i];
              return Card(
                child: ListTile(
                  leading: AppProductImage(
                    imageUrl: p.imageUrl,
                    width: 56,
                    height: 56,
                  ),
                  title: Text(p.name),
                  subtitle: Text(
                    formatRupiah(p.finalPrice),
                    style: const TextStyle(
                      color: NataloColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onTap: () => Navigator.pushNamed(
                    context,
                    '/product-detail',
                    arguments: p,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

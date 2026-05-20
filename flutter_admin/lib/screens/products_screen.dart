import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../theme/admin_theme.dart';
import 'add_product_screen.dart';
import 'product_edit_screen.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  bool _loading = true;
  String? _error;
  List<_ProductRow> _products = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await adminApi.getJson(
        '/api/admin/products',
        query: {
          'limit': 100,
          if (_searchQuery.isNotEmpty) 'q': _searchQuery,
        },
      );
      final list = _extractList(data);
      _products = list.map(_ProductRow.fromJson).toList();
    } on AdminApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Tidak bisa load produk. Cek koneksi.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _extractList(dynamic data) {
    if (data is Map<String, dynamic>) {
      for (final key in ['products', 'items', 'data', 'results']) {
        final v = data[key];
        if (v is List) {
          return v.whereType<Map<String, dynamic>>().toList();
        }
      }
    }
    if (data is List) {
      return data.whereType<Map<String, dynamic>>().toList();
    }
    return const [];
  }

  Future<void> _openEdit(_ProductRow product) async {
    await Navigator.of(context).push<dynamic>(
      MaterialPageRoute(
        builder: (_) => ProductEditScreen(
          productId: product.id,
          initialName: product.name,
          initialPrice: product.price,
          initialStock: product.stock,
          initialActive: product.isActive,
          imageUrl: product.imageUrl,
        ),
      ),
    );
    // Re-fetch list supaya UI update — caller pop bisa pass result, tapi
    // simpler refetch full list (data konsisten dengan backend).
    _load();
  }

  Future<void> _updateStock(_ProductRow product, int delta) async {
    final newStock = (product.stock + delta).clamp(0, 99999);
    if (newStock == product.stock) return;
    try {
      await adminApi.patchJson(
        '/api/admin/products/${Uri.encodeComponent(product.id)}',
        body: {'stock': newStock},
      );
      if (!mounted) return;
      setState(() {
        final idx = _products.indexWhere((p) => p.id == product.id);
        if (idx >= 0) {
          _products[idx] = product.copyWith(stock: newStock);
        }
      });
    } on AdminApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal update stok: ${e.message}')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal update stok. Coba lagi.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Produk'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Tambah produk',
            onPressed: () async {
              final created = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => const AddProductScreen(),
                ),
              );
              if (created == true) _load();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Cari produk...',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onSubmitted: (value) {
                setState(() => _searchQuery = value.trim());
                _load();
              },
            ),
          ),
          Expanded(
            child: _buildBody(),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AdminColors.primary),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded,
                  size: 48, color: AdminColors.textMuted),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: AdminColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _load,
                child: const Text('Coba lagi'),
              ),
            ],
          ),
        ),
      );
    }
    if (_products.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 48, color: AdminColors.textMuted),
            SizedBox(height: 12),
            Text('Belum ada produk',
                style: TextStyle(
                  fontSize: 14,
                  color: AdminColors.textSecondary,
                )),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: AdminColors.primary,
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _products.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final p = _products[i];
          return _ProductCard(
            product: p,
            onStockMinus: () => _updateStock(p, -1),
            onStockPlus: () => _updateStock(p, 1),
            onTap: () => _openEdit(p),
          );
        },
      ),
    );
  }
}

class _ProductRow {
  final String id;
  final String name;
  final String? imageUrl;
  final int price;
  final int stock;
  final bool isActive;

  const _ProductRow({
    required this.id,
    required this.name,
    this.imageUrl,
    required this.price,
    required this.stock,
    required this.isActive,
  });

  _ProductRow copyWith({int? stock, bool? isActive, int? price}) {
    return _ProductRow(
      id: id,
      name: name,
      imageUrl: imageUrl,
      price: price ?? this.price,
      stock: stock ?? this.stock,
      isActive: isActive ?? this.isActive,
    );
  }

  factory _ProductRow.fromJson(Map<String, dynamic> json) {
    return _ProductRow(
      id: (json['id'] ?? json['slug'] ?? '').toString(),
      name: (json['name'] ?? '-').toString(),
      imageUrl: (json['imageUrl'] ?? json['image'] ?? json['thumbnailUrl'])
          ?.toString(),
      price: (json['price'] ?? json['priceCents'] ?? 0) is num
          ? (json['price'] ?? json['priceCents'] ?? 0).toInt()
          : 0,
      stock: (json['stock'] ?? json['totalStock'] ?? 0) is num
          ? (json['stock'] ?? json['totalStock'] ?? 0).toInt()
          : 0,
      isActive: json['isActive'] != false,
    );
  }
}

class _ProductCard extends StatelessWidget {
  final _ProductRow product;
  final VoidCallback onStockMinus;
  final VoidCallback onStockPlus;
  final VoidCallback onTap;

  const _ProductCard({
    required this.product,
    required this.onStockMinus,
    required this.onStockPlus,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final lowStock = product.stock <= 5;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AdminColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image.
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 64,
              height: 64,
              child: product.imageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: product.imageUrl!,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: AdminColors.background,
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: AdminColors.background,
                        child: const Icon(
                          Icons.image_not_supported_outlined,
                          color: AdminColors.textMuted,
                          size: 24,
                        ),
                      ),
                    )
                  : Container(
                      color: AdminColors.background,
                      child: const Icon(
                        Icons.image_outlined,
                        color: AdminColors.textMuted,
                        size: 24,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),

          // Info.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AdminColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  formatRupiah(product.price),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AdminColors.primary,
                  ),
                ),
                const SizedBox(height: 8),
                // Stock control row.
                Row(
                  children: [
                    _StockButton(
                      icon: Icons.remove_rounded,
                      onPressed: product.stock > 0 ? onStockMinus : null,
                    ),
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        product.stock.toString(),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: lowStock
                              ? AdminColors.danger
                              : AdminColors.textPrimary,
                        ),
                      ),
                    ),
                    _StockButton(
                      icon: Icons.add_rounded,
                      onPressed: onStockPlus,
                    ),
                    const SizedBox(width: 6),
                    if (lowStock)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AdminColors.danger.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: const Text(
                          'Stok kritis',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: AdminColors.danger,
                          ),
                        ),
                      ),
                    const Spacer(),
                    if (!product.isActive)
                      const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Icon(
                          Icons.visibility_off_outlined,
                          size: 16,
                          color: AdminColors.textMuted,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }
}

class _StockButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  const _StockButton({required this.icon, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          border: Border.all(
            color: disabled ? AdminColors.divider : AdminColors.primary,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(
          icon,
          size: 16,
          color: disabled ? AdminColors.textMuted : AdminColors.primary,
        ),
      ),
    );
  }
}

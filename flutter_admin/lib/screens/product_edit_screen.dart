import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_client.dart';
import '../theme/admin_theme.dart';

/// Edit form untuk satu produk — nama, harga, stok, status aktif.
///
/// Pakai endpoint PATCH /api/admin/products/{id} yang sudah ada di backend.
/// Field yang di-edit di-send sebagai diff (kalau tidak berubah, tidak masuk
/// body) supaya validation server-side bisa partial-update.
class ProductEditScreen extends StatefulWidget {
  final String productId;
  final String initialName;
  final int initialPrice;
  final int initialStock;
  final bool initialActive;
  final String? imageUrl;

  const ProductEditScreen({
    super.key,
    required this.productId,
    required this.initialName,
    required this.initialPrice,
    required this.initialStock,
    required this.initialActive,
    this.imageUrl,
  });

  @override
  State<ProductEditScreen> createState() => _ProductEditScreenState();
}

class _ProductEditScreenState extends State<ProductEditScreen> {
  late TextEditingController _nameController;
  late TextEditingController _priceController;
  late TextEditingController _stockController;
  late bool _isActive;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _priceController =
        TextEditingController(text: widget.initialPrice.toString());
    _stockController =
        TextEditingController(text: widget.initialStock.toString());
    _isActive = widget.initialActive;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _nameController.text.trim();
    final price = int.tryParse(_priceController.text.trim()) ?? -1;
    final stock = int.tryParse(_stockController.text.trim()) ?? -1;

    if (name.isEmpty) {
      _showError('Nama tidak boleh kosong');
      return;
    }
    if (price < 0) {
      _showError('Harga harus angka >= 0');
      return;
    }
    if (stock < 0) {
      _showError('Stok harus angka >= 0');
      return;
    }

    final body = <String, dynamic>{};
    if (name != widget.initialName) body['name'] = name;
    if (price != widget.initialPrice) body['price'] = price;
    if (stock != widget.initialStock) body['stock'] = stock;
    if (_isActive != widget.initialActive) body['isActive'] = _isActive;

    if (body.isEmpty) {
      Navigator.of(context).pop(null);
      return;
    }

    setState(() => _saving = true);
    try {
      await adminApi.patchJson(
        '/api/admin/products/${Uri.encodeComponent(widget.productId)}',
        body: body,
      );
      if (!mounted) return;
      Navigator.of(context).pop(_ProductUpdateResult(
        name: name,
        price: price,
        stock: stock,
        isActive: _isActive,
      ));
    } on AdminApiException catch (e) {
      _showError('Gagal simpan: ${e.message}');
    } catch (_) {
      _showError('Gagal simpan. Coba lagi.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Produk'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(
              'Simpan',
              style: TextStyle(
                color: _saving ? AdminColors.textMuted : AdminColors.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        children: [
          if (widget.imageUrl != null)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: widget.imageUrl!,
                    width: 160,
                    height: 160,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      width: 160,
                      height: 160,
                      color: AdminColors.background,
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _FieldLabel('Nama Produk'),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    hintText: 'Nama produk',
                  ),
                ),
                const SizedBox(height: 14),
                const _FieldLabel('Harga (Rp)'),
                TextField(
                  controller: _priceController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: const InputDecoration(
                    hintText: '0',
                    prefixText: 'Rp ',
                  ),
                ),
                const SizedBox(height: 14),
                const _FieldLabel('Stok'),
                TextField(
                  controller: _stockController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: const InputDecoration(
                    hintText: '0',
                  ),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Produk aktif',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AdminColors.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    _isActive
                        ? 'Tampil di app customer'
                        : 'Disembunyikan dari app customer',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AdminColors.textSecondary,
                    ),
                  ),
                  value: _isActive,
                  activeThumbColor: AdminColors.primary,
                  onChanged: (v) => setState(() => _isActive = v),
                ),
              ],
            ),
          ),
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: CircularProgressIndicator(color: AdminColors.primary),
              ),
            ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;
  const _FieldLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AdminColors.textSecondary,
        ),
      ),
    );
  }
}

class _ProductUpdateResult {
  final String name;
  final int price;
  final int stock;
  final bool isActive;
  const _ProductUpdateResult({
    required this.name,
    required this.price,
    required this.stock,
    required this.isActive,
  });
}

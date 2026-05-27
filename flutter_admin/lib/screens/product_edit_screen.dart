import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_client.dart';
import '../services/upload_service.dart';
import '../theme/admin_theme.dart';
import 'variant_management_screen.dart';

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
  late String? _currentImageUrl;
  bool _saving = false;
  bool _uploadingImage = false;
  File? _pickedImage;
  bool _imageChanged = false;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _priceController =
        TextEditingController(text: widget.initialPrice.toString());
    _stockController =
        TextEditingController(text: widget.initialStock.toString());
    _isActive = widget.initialActive;
    _currentImageUrl = widget.imageUrl;
  }

  Future<void> _pickAndUploadImage() async {
    if (_uploadingImage || _saving) return;
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (picked == null) return;
      final file = File(picked.path);
      setState(() {
        _pickedImage = file;
        _uploadingImage = true;
      });
      final url = await AdminUploadService.instance.uploadProductImage(file);
      if (!mounted) return;
      setState(() {
        _currentImageUrl = url;
        _imageChanged = true;
        _uploadingImage = false;
      });
    } on AdminUploadException catch (e) {
      if (!mounted) return;
      setState(() => _uploadingImage = false);
      _showError(e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _uploadingImage = false);
      _showError('Gagal upload foto. Coba lagi.');
    }
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

    if (_uploadingImage) {
      _showError('Tunggu upload foto selesai dulu');
      return;
    }

    final body = <String, dynamic>{};
    if (name != widget.initialName) body['name'] = name;
    if (price != widget.initialPrice) body['price'] = price;
    if (stock != widget.initialStock) body['stock'] = stock;
    if (_isActive != widget.initialActive) body['isActive'] = _isActive;
    if (_imageChanged && _currentImageUrl != null) {
      body['imageUrl'] = _currentImageUrl;
    }

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
      Navigator.of(context).pop(true);
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
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _FieldLabel('Foto Produk'),
                _EditImagePicker(
                  pickedImage: _pickedImage,
                  imageUrl: _currentImageUrl,
                  uploading: _uploadingImage,
                  onPick: _pickAndUploadImage,
                ),
              ],
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
          const SizedBox(height: 12),
          Container(
            color: Colors.white,
            child: ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AdminColors.primaryLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.layers_outlined,
                  color: AdminColors.primary,
                ),
              ),
              title: const Text(
                'Kelola Varian',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: const Text(
                'Ukuran, warna, atau opsi lain — harga & stok per kombinasi',
                style: TextStyle(
                  fontSize: 11.5,
                  color: AdminColors.textMuted,
                ),
              ),
              trailing: const Icon(
                Icons.chevron_right_rounded,
                color: AdminColors.textMuted,
              ),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => VariantManagementScreen(
                      productId: widget.productId,
                      productName: _nameController.text.trim().isEmpty
                          ? widget.initialName
                          : _nameController.text.trim(),
                    ),
                  ),
                );
              },
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

class _EditImagePicker extends StatelessWidget {
  final File? pickedImage;
  final String? imageUrl;
  final bool uploading;
  final VoidCallback onPick;

  const _EditImagePicker({
    required this.pickedImage,
    required this.imageUrl,
    required this.uploading,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = pickedImage != null || imageUrl != null;
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: pickedImage != null
              ? Image.file(
                  pickedImage!,
                  width: double.infinity,
                  height: 200,
                  fit: BoxFit.cover,
                )
              : imageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: imageUrl!,
                      width: double.infinity,
                      height: 200,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => Container(
                        height: 200,
                        color: AdminColors.background,
                      ),
                    )
                  : Container(
                      width: double.infinity,
                      height: 200,
                      color: AdminColors.background,
                      child: const Icon(
                        Icons.image_outlined,
                        size: 48,
                        color: AdminColors.textMuted,
                      ),
                    ),
        ),
        if (uploading)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 10),
                    Text(
                      'Mengupload foto...',
                      style: TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Positioned(
          bottom: 8,
          right: 8,
          child: Material(
            color: AdminColors.primary,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: uploading ? null : onPick,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      hasImage
                          ? Icons.refresh_rounded
                          : Icons.add_a_photo_outlined,
                      color: Colors.white,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      hasImage ? 'Ganti foto' : 'Pilih foto',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

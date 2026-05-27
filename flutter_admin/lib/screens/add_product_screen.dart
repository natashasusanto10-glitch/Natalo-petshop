import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_client.dart';
import '../services/upload_service.dart';
import '../theme/admin_theme.dart';

/// Form untuk tambah produk baru. POST /api/admin/products.
///
/// Field minimal: nama, harga, stok. Field opsional: deskripsi, weight,
/// imageUrl (di-upload dari galeri HP via /api/admin/upload).
class AddProductScreen extends StatefulWidget {
  const AddProductScreen({super.key});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _stockController = TextEditingController(text: '0');
  final _weightController = TextEditingController(text: '500');
  final _descController = TextEditingController();
  final _picker = ImagePicker();
  bool _isActive = true;
  bool _saving = false;
  bool _uploadingImage = false;
  File? _pickedImage;
  String? _uploadedImageUrl;

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    _weightController.dispose();
    _descController.dispose();
    super.dispose();
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
        _uploadedImageUrl = null;
        _uploadingImage = true;
      });
      final url = await AdminUploadService.instance.uploadProductImage(file);
      if (!mounted) return;
      setState(() {
        _uploadedImageUrl = url;
        _uploadingImage = false;
      });
    } on AdminUploadException catch (e) {
      if (!mounted) return;
      setState(() => _uploadingImage = false);
      _err(e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _uploadingImage = false);
      _err('Gagal upload foto. Coba lagi.');
    }
  }

  void _removeImage() {
    setState(() {
      _pickedImage = null;
      _uploadedImageUrl = null;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _nameController.text.trim();
    final price = int.tryParse(_priceController.text.trim()) ?? -1;
    final stock = int.tryParse(_stockController.text.trim()) ?? 0;
    final weight = int.tryParse(_weightController.text.trim()) ?? 500;

    if (name.isEmpty) return _err('Nama produk wajib diisi');
    if (price < 0) return _err('Harga harus angka >= 0');
    if (_uploadingImage) return _err('Tunggu upload foto selesai dulu');

    setState(() => _saving = true);
    try {
      await adminApi.postJson(
        '/api/admin/products',
        body: {
          'name': name,
          'price': price,
          'stock': stock,
          'weightGram': weight,
          if (_descController.text.trim().isNotEmpty)
            'description': _descController.text.trim(),
          if (_uploadedImageUrl != null) 'imageUrl': _uploadedImageUrl,
          'isActive': _isActive,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Produk berhasil dibuat ✓'),
          backgroundColor: AdminColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop(true);
    } on AdminApiException catch (e) {
      _err('Gagal: ${e.message}');
    } catch (_) {
      _err('Gagal simpan. Coba lagi.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _err(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tambah Produk'),
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
                const _Label('Nama Produk *'),
                TextField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    hintText: 'Misal: Royal Canin Kitten 2KG',
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _Label('Harga (Rp) *'),
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
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _Label('Stok'),
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
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const _Label('Berat (gram)'),
                TextField(
                  controller: _weightController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: const InputDecoration(
                    hintText: '500',
                    suffixText: 'g',
                  ),
                ),
                const SizedBox(height: 14),
                const _Label('Foto Produk (opsional)'),
                _ProductImagePicker(
                  pickedImage: _pickedImage,
                  uploadedUrl: _uploadedImageUrl,
                  uploading: _uploadingImage,
                  onPick: _pickAndUploadImage,
                  onRemove: _removeImage,
                ),
                const SizedBox(height: 14),
                const _Label('Deskripsi'),
                TextField(
                  controller: _descController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'Tulis deskripsi produk...',
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Aktifkan langsung',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    _isActive
                        ? 'Tampil di app customer setelah simpan'
                        : 'Disimpan sebagai draft',
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

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AdminColors.textSecondary,
        ),
      ),
    );
  }
}

/// Picker + preview foto produk. Tap untuk pick dari galeri, tap-X untuk
/// hapus. Selama upload, tampilkan overlay loader. Selesai upload → badge
/// "Terupload ✓" supaya admin tahu URL ready dipakai saat simpan.
class _ProductImagePicker extends StatelessWidget {
  final File? pickedImage;
  final String? uploadedUrl;
  final bool uploading;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  const _ProductImagePicker({
    required this.pickedImage,
    required this.uploadedUrl,
    required this.uploading,
    required this.onPick,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    if (pickedImage == null && uploadedUrl == null) {
      return InkWell(
        onTap: onPick,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 140,
          decoration: BoxDecoration(
            color: AdminColors.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AdminColors.divider,
              style: BorderStyle.solid,
            ),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_a_photo_outlined,
                  size: 32, color: AdminColors.textMuted),
              SizedBox(height: 8),
              Text(
                'Pilih foto dari galeri',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AdminColors.textSecondary,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'JPG, PNG, WEBP — maks 2 MB',
                style: TextStyle(
                  fontSize: 11,
                  color: AdminColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
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
                  : CachedNetworkImage(
                      imageUrl: uploadedUrl!,
                      width: double.infinity,
                      height: 200,
                      fit: BoxFit.cover,
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
              top: 8,
              right: 8,
              child: Material(
                color: Colors.black.withValues(alpha: 0.55),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: uploading ? null : onRemove,
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.close_rounded,
                        color: Colors.white, size: 18),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (uploadedUrl != null && !uploading)
              const Row(
                children: [
                  Icon(Icons.check_circle_rounded,
                      size: 14, color: AdminColors.success),
                  SizedBox(width: 4),
                  Text(
                    'Foto terupload',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AdminColors.success,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            const Spacer(),
            TextButton.icon(
              onPressed: uploading ? null : onPick,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Ganti foto'),
            ),
          ],
        ),
      ],
    );
  }
}

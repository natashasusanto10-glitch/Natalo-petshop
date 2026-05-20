import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_client.dart';
import '../theme/admin_theme.dart';

/// Form untuk tambah produk baru. POST /api/admin/products.
///
/// Field minimal: nama, harga, stok. Field opsional: deskripsi, weight,
/// imageUrl (manual URL paste — full image picker upload pakai Bunny
/// upload flow akan masuk Phase 4).
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
  final _imageUrlController = TextEditingController();
  bool _isActive = true;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    _weightController.dispose();
    _descController.dispose();
    _imageUrlController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _nameController.text.trim();
    final price = int.tryParse(_priceController.text.trim()) ?? -1;
    final stock = int.tryParse(_stockController.text.trim()) ?? 0;
    final weight = int.tryParse(_weightController.text.trim()) ?? 500;
    final imageUrl = _imageUrlController.text.trim();

    if (name.isEmpty) return _err('Nama produk wajib diisi');
    if (price < 0) return _err('Harga harus angka >= 0');

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
          if (imageUrl.isNotEmpty) 'imageUrl': imageUrl,
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
                const _Label('URL Gambar (opsional)'),
                TextField(
                  controller: _imageUrlController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    hintText: 'https://...',
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Upload langsung dari HP — coming soon. '
                  'Sementara paste URL CDN/Bunny.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AdminColors.textMuted,
                  ),
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

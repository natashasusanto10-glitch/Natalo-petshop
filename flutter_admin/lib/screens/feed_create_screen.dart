import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_client.dart';
import '../services/upload_service.dart';
import '../theme/admin_theme.dart';

/// Form admin untuk create FEED post — MVP PHOTO_CAROUSEL only.
///
/// Flow:
///   1. Admin pilih 1-8 foto dari galeri
///   2. Tiap foto auto-upload ke /api/feed/upload-photo
///   3. Admin isi judul (≥3 char) + caption opsional
///   4. Submit → POST /api/feed/posts dengan
///      `{kind: PHOTO_CAROUSEL, tab: REKOMENDASI, title, description?,
///        images: [{url, key, width?, height?}]}`
///
/// Auto status = ACTIVE (admin role), publishedAt = now → langsung tampil
/// di feed customer. Untuk video & promo post, admin masih pakai web
/// dashboard (Bunny TUS upload tidak di-port ke Flutter di MVP ini).
class FeedCreateScreen extends StatefulWidget {
  const FeedCreateScreen({super.key});

  @override
  State<FeedCreateScreen> createState() => _FeedCreateScreenState();
}

class _FeedCreateScreenState extends State<FeedCreateScreen> {
  static const int _maxPhotos = 8;
  static const int _maxTitle = 200;
  static const int _maxDescription = 2000;

  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _picker = ImagePicker();

  final List<_FeedPhotoEntry> _photos = [];
  bool _submitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    if (_submitting) return;
    final remaining = _maxPhotos - _photos.length;
    if (remaining <= 0) {
      _showError('Maksimal $_maxPhotos foto per postingan.');
      return;
    }
    try {
      final picked = await _picker.pickMultiImage(
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1920,
        limit: remaining,
      );
      if (picked.isEmpty) return;
      final files = picked.take(remaining).map((x) => File(x.path)).toList();
      final entries = <_FeedPhotoEntry>[];
      for (final file in files) {
        entries.add(_FeedPhotoEntry(file: file));
      }
      setState(() => _photos.addAll(entries));
      // Fire upload paralel — UI per-entry update saat selesai.
      await Future.wait(entries.map(_uploadOne));
    } catch (e) {
      _showError('Gagal pilih foto: $e');
    }
  }

  Future<void> _uploadOne(_FeedPhotoEntry entry) async {
    try {
      final result =
          await AdminUploadService.instance.uploadFeedPhoto(entry.file);
      if (!mounted) return;
      setState(() {
        entry.uploadedUrl = result.url;
        entry.uploadedKey = result.key;
        entry.error = null;
      });
    } on AdminUploadException catch (e) {
      if (!mounted) return;
      setState(() => entry.error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => entry.error = 'Upload gagal.');
    }
  }

  void _removePhoto(_FeedPhotoEntry entry) {
    if (_submitting) return;
    setState(() => _photos.remove(entry));
  }

  Future<void> _retryUpload(_FeedPhotoEntry entry) async {
    setState(() => entry.error = null);
    await _uploadOne(entry);
  }

  bool get _allUploaded =>
      _photos.isNotEmpty && _photos.every((p) => p.uploadedUrl != null);

  bool get _anyUploading =>
      _photos.any((p) => p.uploadedUrl == null && p.error == null);

  Future<void> _submit() async {
    if (_submitting) return;
    final title = _titleController.text.trim();
    final desc = _descController.text.trim();

    if (title.length < 3) {
      return _showError('Judul minimal 3 karakter.');
    }
    if (_photos.isEmpty) {
      return _showError('Pilih minimal 1 foto.');
    }
    if (_anyUploading) {
      return _showError('Tunggu upload foto selesai dulu.');
    }
    if (!_allUploaded) {
      return _showError('Ada foto yang gagal upload — coba lagi atau hapus.');
    }

    setState(() => _submitting = true);
    try {
      await adminApi.postJson(
        '/api/feed/posts',
        body: {
          'kind': 'PHOTO_CAROUSEL',
          'tab': 'REKOMENDASI',
          'title': title,
          if (desc.isNotEmpty) 'description': desc,
          'images': _photos
              .map((p) => {
                    'url': p.uploadedUrl,
                    if (p.uploadedKey != null) 'key': p.uploadedKey,
                  })
              .toList(),
        },
        timeout: const Duration(seconds: 20),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Post feed berhasil dipublikasikan ✓'),
          backgroundColor: AdminColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop(true);
    } on AdminApiException catch (e) {
      _showError('Gagal: ${e.message}');
    } catch (_) {
      _showError('Gagal kirim. Coba lagi.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titleLen = _titleController.text.length;
    final descLen = _descController.text.length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Buat Post Feed'),
        actions: [
          TextButton(
            onPressed: _submitting ? null : _submit,
            child: Text(
              _submitting ? 'Mengirim...' : 'Publikasikan',
              style: TextStyle(
                color: _submitting ? AdminColors.textMuted : AdminColors.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        children: [
          Container(
            color: AdminColors.primaryLight,
            padding: const EdgeInsets.all(14),
            child: const Row(
              children: [
                Icon(Icons.feed_outlined,
                    color: AdminColors.primary, size: 22),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Post foto akan tampil di tab Rekomendasi. '
                    'Untuk post video/promo, pakai dashboard web.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AdminColors.textPrimary,
                      height: 1.4,
                    ),
                  ),
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Foto (1-8)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AdminColors.textSecondary,
                      ),
                    ),
                    Text(
                      '${_photos.length} / $_maxPhotos',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AdminColors.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _PhotoGrid(
                  photos: _photos,
                  canAddMore: _photos.length < _maxPhotos && !_submitting,
                  onAdd: _pickPhotos,
                  onRemove: _removePhoto,
                  onRetry: _retryUpload,
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Judul *',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AdminColors.textSecondary,
                      ),
                    ),
                    Text(
                      '$titleLen / $_maxTitle',
                      style: TextStyle(
                        fontSize: 11,
                        color: titleLen > _maxTitle
                            ? AdminColors.danger
                            : AdminColors.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _titleController,
                  maxLength: _maxTitle,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Misal: Promo akhir pekan!',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Caption (opsional)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AdminColors.textSecondary,
                      ),
                    ),
                    Text(
                      '$descLen / $_maxDescription',
                      style: TextStyle(
                        fontSize: 11,
                        color: descLen > _maxDescription
                            ? AdminColors.danger
                            : AdminColors.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _descController,
                  maxLength: _maxDescription,
                  maxLines: 5,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Tulis deskripsi promo, produk, atau cerita...',
                    counterText: '',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _FeedPhotoEntry {
  final File file;
  String? uploadedUrl;
  String? uploadedKey;
  String? error;

  _FeedPhotoEntry({required this.file});
}

class _PhotoGrid extends StatelessWidget {
  final List<_FeedPhotoEntry> photos;
  final bool canAddMore;
  final VoidCallback onAdd;
  final ValueChanged<_FeedPhotoEntry> onRemove;
  final ValueChanged<_FeedPhotoEntry> onRetry;

  const _PhotoGrid({
    required this.photos,
    required this.canAddMore,
    required this.onAdd,
    required this.onRemove,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      for (final p in photos) _PhotoTile(entry: p, onRemove: onRemove, onRetry: onRetry),
      if (canAddMore) _AddTile(onTap: onAdd),
    ];
    if (tiles.isEmpty) {
      return _AddTile(onTap: onAdd, large: true);
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: tiles,
    );
  }
}

class _PhotoTile extends StatelessWidget {
  final _FeedPhotoEntry entry;
  final ValueChanged<_FeedPhotoEntry> onRemove;
  final ValueChanged<_FeedPhotoEntry> onRetry;

  const _PhotoTile({
    required this.entry,
    required this.onRemove,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final uploading = entry.uploadedUrl == null && entry.error == null;
    return SizedBox(
      width: 96,
      height: 96,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              entry.file,
              width: 96,
              height: 96,
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
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          if (entry.error != null)
            Positioned.fill(
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onRetry(entry),
                child: Container(
                  decoration: BoxDecoration(
                    color: AdminColors.danger.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.refresh_rounded,
                            color: Colors.white, size: 20),
                        SizedBox(height: 2),
                        Text(
                          'Retry',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            top: 2,
            right: 2,
            child: Material(
              color: Colors.black.withValues(alpha: 0.6),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => onRemove(entry),
                child: const Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(Icons.close_rounded,
                      color: Colors.white, size: 14),
                ),
              ),
            ),
          ),
          if (entry.uploadedUrl != null && entry.error == null)
            const Positioned(
              bottom: 4,
              left: 4,
              child: Icon(Icons.check_circle_rounded,
                  color: AdminColors.success, size: 18),
            ),
        ],
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  final VoidCallback onTap;
  final bool large;

  const _AddTile({required this.onTap, this.large = false});

  @override
  Widget build(BuildContext context) {
    final size = large ? 140.0 : 96.0;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: large ? double.infinity : size,
        height: size,
        decoration: BoxDecoration(
          color: AdminColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AdminColors.divider),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_a_photo_outlined,
                size: 24, color: AdminColors.textMuted),
            SizedBox(height: 4),
            Text(
              'Tambah foto',
              style: TextStyle(
                fontSize: 11,
                color: AdminColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

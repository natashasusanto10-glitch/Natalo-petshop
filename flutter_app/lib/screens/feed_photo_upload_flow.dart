import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/product.dart';
import '../services/feed_photo_service.dart';
import '../services/product_service.dart';
import '../utils/haptics.dart';
import 'feed_new_post_screen.dart';
import 'feed_video_upload_flow.dart' show FeedPostSubmittedScreen;

const int _kPhotoMin = 1;
const int _kPhotoMax = 8;

/// Brand colors — match dark upload scaffold dari video flow.
const Color _kBg = Color(0xFF0F1419);
const Color _kSurface = Color(0xFF1A1F2E);
const Color _kBorder = Color(0xFF2A3041);
const Color _kAccent = Color(0xFF0B7FEA);
const Color _kTextPrimary = Colors.white;
const Color _kTextSecondary = Color(0xFF94A3B8);

// ════════════════════════════════════════════════════════════════
// 1. PICKER SCREEN — User select 1-8 foto via system image_picker.
// ════════════════════════════════════════════════════════════════

class FeedPhotoPickerScreen extends StatefulWidget {
  const FeedPhotoPickerScreen({super.key});

  @override
  State<FeedPhotoPickerScreen> createState() => _FeedPhotoPickerScreenState();
}

class _FeedPhotoPickerScreenState extends State<FeedPhotoPickerScreen> {
  final _picker = ImagePicker();
  bool _busy = false;
  String? _error;
  List<File> _selected = const [];

  Future<void> _pickFromGallery() async {
    if (_busy) return;
    AppHaptics.tap();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // image_picker pickMultiImage — system handles multi-select UI.
      // Default limit unlimited, kita enforce 1-8 di client side.
      //
      // maxWidth/maxHeight 1920: auto-downsize foto besar sebelum di-load
      // ke device memory. iPhone 15 camera 4032×3024 = ~5MB JPEG, di-resize
      // ke 1920×1440 jadi ~500KB (10x smaller). Critical untuk upload speed
      // di 4G Indonesia (5-15 Mbps): 8 foto × 5MB = 40MB raw upload (60s),
      // setelah resize 8 × 500KB = 4MB (6s). 10x lebih cepat tanpa quality
      // loss yang noticeable di display feed (max viewport phone ~1170px).
      final picked = await _picker.pickMultiImage(
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1920,
        limit: _kPhotoMax,
      );
      if (picked.isEmpty) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      if (picked.length > _kPhotoMax) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = 'Maksimal $_kPhotoMax foto dalam 1 postingan.';
        });
        AppHaptics.warning();
        return;
      }
      final newFiles = picked.map((x) => File(x.path)).toList();
      if (!mounted) return;
      // BUGFIX(audit): tombol berlabel "Ganti / Tambah Foto" tapi sebelumnya
      // MENIMPA seluruh seleksi (`_selected = files`) → foto yang sudah
      // dipilih hilang, padahal label janji "Tambah". Sekarang MERGE ke
      // seleksi existing, dedup by path, cap _kPhotoMax. Hapus foto tertentu
      // tetap bisa via tombol X per-thumbnail (onRemove/_removeAt).
      final seenPaths = <String>{};
      final merged = <File>[];
      for (final f in [..._selected, ...newFiles]) {
        if (seenPaths.add(f.path)) merged.add(f);
      }
      final overflow = merged.length > _kPhotoMax;
      setState(() {
        _selected = overflow ? merged.take(_kPhotoMax).toList() : merged;
        _busy = false;
        _error = overflow
            ? 'Maksimal $_kPhotoMax foto dalam 1 postingan.'
            : null;
      });
      if (overflow) AppHaptics.warning();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Gagal buka galeri. Coba lagi.';
      });
      AppHaptics.warning();
    }
  }

  void _continue() {
    if (_selected.length < _kPhotoMin) {
      setState(() => _error = 'Pilih minimal 1 foto untuk melanjutkan.');
      AppHaptics.warning();
      return;
    }
    if (_selected.length > _kPhotoMax) {
      setState(() => _error = 'Maksimal $_kPhotoMax foto dalam 1 postingan.');
      AppHaptics.warning();
      return;
    }
    AppHaptics.tap();
    final draft = FeedPhotoDraft(localFiles: _selected);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FeedPhotoPreviewScreen(draft: draft),
      ),
    );
  }

  void _removeAt(int index) {
    AppHaptics.selection();
    final next = List<File>.from(_selected)..removeAt(index);
    setState(() {
      _selected = next;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasSelection = _selected.isNotEmpty;
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: _kTextPrimary),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Pilih Foto',
          style: TextStyle(
            color: _kTextPrimary,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        actions: [
          if (hasSelection)
            TextButton(
              onPressed: _busy ? null : _continue,
              child: const Text(
                'Lanjut',
                style: TextStyle(
                  color: _kAccent,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Counter row.
              Row(
                children: [
                  Expanded(
                    child: Text(
                      hasSelection
                          ? '${_selected.length}/$_kPhotoMax foto dipilih'
                          : 'Pilih 1-$_kPhotoMax foto untuk dijadikan postingan',
                      style: const TextStyle(
                        color: _kTextSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (hasSelection)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () {
                              setState(() => _selected = const []);
                              AppHaptics.selection();
                            },
                      child: const Text(
                        'Hapus semua',
                        style: TextStyle(
                          color: Color(0xFFEF4444),
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),

              // Selected photos preview grid (atau placeholder kalau kosong).
              Expanded(
                child: hasSelection
                    ? _SelectedPhotosGrid(
                        files: _selected,
                        onRemove: _removeAt,
                      )
                    : _PickerPlaceholder(),
              ),

              // Error message.
              if (_error != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        color: Color(0xFFEF4444),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: Color(0xFFEF4444),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 14),

              // Primary CTA — buka system photo picker.
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: _busy ? null : _pickFromGallery,
                  icon: Icon(
                    hasSelection
                        ? Icons.refresh_rounded
                        : Icons.photo_library_rounded,
                  ),
                  label: Text(
                    _busy
                        ? 'Membuka galeri...'
                        : hasSelection
                            ? 'Ganti / Tambah Foto'
                            : 'Pilih Foto dari Galeri',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kAccent,
                    foregroundColor: _kTextPrimary,
                    disabledBackgroundColor: const Color(0xFF334155),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),

              if (hasSelection) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _continue,
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: const Text('Lanjut ke Preview'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _kTextPrimary,
                      side: const BorderSide(color: _kBorder, width: 1.4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PickerPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: _kSurface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _kBorder, width: 1),
            ),
            child: const Icon(
              Icons.photo_library_outlined,
              color: _kAccent,
              size: 48,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Belum ada foto dipilih',
            style: TextStyle(
              color: _kTextPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Tap tombol di bawah untuk pilih foto\n'
            'dari galeri (1-8 foto)',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _kTextSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectedPhotosGrid extends StatelessWidget {
  final List<File> files;
  final void Function(int) onRemove;

  const _SelectedPhotosGrid({required this.files, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.8,
      ),
      itemCount: files.length,
      itemBuilder: (context, index) {
        final isFirst = index == 0;
        return Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.file(
                files[index],
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
            // Order badge — foto pertama = cover/thumbnail.
            Positioned(
              top: 6,
              left: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color:
                      isFirst ? _kAccent : Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  isFirst ? 'COVER' : '${index + 1}',
                  style: const TextStyle(
                    color: _kTextPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ),
            // Remove button.
            Positioned(
              top: 6,
              right: 6,
              child: GestureDetector(
                onTap: () => onRemove(index),
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════
// 2. PREVIEW SCREEN — Carousel preview semua foto dengan swipe.
// ════════════════════════════════════════════════════════════════

class FeedPhotoPreviewScreen extends StatefulWidget {
  final FeedPhotoDraft draft;

  const FeedPhotoPreviewScreen({super.key, required this.draft});

  @override
  State<FeedPhotoPreviewScreen> createState() => _FeedPhotoPreviewScreenState();
}

class _FeedPhotoPreviewScreenState extends State<FeedPhotoPreviewScreen> {
  final _pageController = PageController();
  int _currentIndex = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() => _currentIndex = index);
  }

  void _continue() {
    AppHaptics.tap();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FeedNewPostScreen(
          draft: NewPostMediaDraft.photos(widget.draft.localFiles),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final files = widget.draft.localFiles;
    final isMultiple = files.length > 1;
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: _kTextPrimary),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Preview',
          style: TextStyle(
            color: _kTextPrimary,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  PageView.builder(
                    controller: _pageController,
                    onPageChanged: _onPageChanged,
                    itemCount: files.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Image.file(
                            files[index],
                            fit: BoxFit.contain,
                            width: double.infinity,
                          ),
                        ),
                      );
                    },
                  ),
                  // Counter pill di pojok kanan atas — Instagram pattern.
                  if (isMultiple)
                    Positioned(
                      top: 16,
                      right: 28,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          '${_currentIndex + 1}/${files.length}',
                          style: const TextStyle(
                            color: _kTextPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Dots indicator (Instagram-style).
            if (isMultiple) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(files.length, (i) {
                  final active = i == _currentIndex;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: active ? 22 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: active
                          ? _kAccent
                          : _kTextSecondary.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  );
                }),
              ),
            ],
            const SizedBox(height: 22),
            // Action buttons row.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 54,
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Ganti Foto'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _kTextPrimary,
                          side: const BorderSide(
                            color: _kBorder,
                            width: 1.4,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 54,
                      child: ElevatedButton.icon(
                        onPressed: _continue,
                        icon: const Icon(Icons.arrow_forward_rounded),
                        label: const Text('Lanjut'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kAccent,
                          foregroundColor: _kTextPrimary,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// 3. DETAIL SCREEN — Optional product tag + submit.
// ════════════════════════════════════════════════════════════════

class FeedPhotoDetailScreen extends StatefulWidget {
  final FeedPhotoDraft draft;

  const FeedPhotoDetailScreen({super.key, required this.draft});

  @override
  State<FeedPhotoDetailScreen> createState() => _FeedPhotoDetailScreenState();
}

class _FeedPhotoDetailScreenState extends State<FeedPhotoDetailScreen> {
  List<Product> _products = const [];
  final Set<String> _selectedProductIds = {};
  bool _loadingProducts = false;
  String? _error;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _selectedProductIds.addAll(widget.draft.taggedProductIds);
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    setState(() => _loadingProducts = true);
    // BUGFIX(audit): tanpa try/catch, throw saat fetch (API/DB down) bikin
    // _loadingProducts stuck true → spinner produk muter selamanya. Catch
    // reset flag + kosongkan list (graceful degrade).
    try {
      final result = await productService.fetchProducts(
        query: '',
        limit: 12,
        inStock: true,
        hasPrice: true,
        withImage: true,
      );
      if (!mounted) return;
      setState(() {
        _products = result.products.take(12).toList();
        _loadingProducts = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _products = const [];
          _loadingProducts = false;
        });
      }
    }
  }

  void _toggleProduct(Product product) {
    AppHaptics.selection();
    setState(() {
      if (_selectedProductIds.contains(product.id)) {
        _selectedProductIds.remove(product.id);
      } else if (_selectedProductIds.length < 3) {
        _selectedProductIds.add(product.id);
      } else {
        _error = 'Maksimal 3 produk yang bisa ditag.';
      }
    });
  }

  Future<void> _submit() async {
    AppHaptics.tap();
    setState(() {
      _submitting = true;
      _error = null;
    });
    final files = widget.draft.localFiles;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FeedPhotoUploadProgressScreen(
          files: files,
          title: 'Postingan baru',
          productIds: _selectedProductIds.toList(),
        ),
      ),
    );
    if (mounted) {
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final files = widget.draft.localFiles;
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: _kTextPrimary),
        title: const Text(
          'Tag Produk',
          style: TextStyle(
            color: _kTextPrimary,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // Media preview thumbnail (foto pertama + carousel hint).
                  AspectRatio(
                    aspectRatio: 4 / 3,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.file(
                              files.first,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        if (files.length > 1)
                          Positioned(
                            top: 10,
                            right: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.65),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.collections_rounded,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${files.length} foto',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Product tag picker.
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'PRODUK TERKAIT (OPSIONAL)',
                          style: TextStyle(
                            color: _kTextSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                      Text(
                        '${_selectedProductIds.length}/3',
                        style: const TextStyle(
                          color: _kTextSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_loadingProducts)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: _kAccent,
                          ),
                        ),
                      ),
                    )
                  else if (_products.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _kSurface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _kBorder),
                      ),
                      child: const Text(
                        'Belum ada produk untuk di-tag.',
                        style: TextStyle(
                          color: _kTextSecondary,
                          fontSize: 13,
                        ),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _products.map((product) {
                        final selected =
                            _selectedProductIds.contains(product.id);
                        return GestureDetector(
                          onTap: () => _toggleProduct(product),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: selected
                                  ? _kAccent.withValues(alpha: 0.20)
                                  : _kSurface,
                              borderRadius: BorderRadius.circular(99),
                              border: Border.all(
                                color: selected ? _kAccent : _kBorder,
                                width: 1.2,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (selected) ...[
                                  const Icon(
                                    Icons.check_rounded,
                                    size: 14,
                                    color: _kAccent,
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 160,
                                  ),
                                  child: Text(
                                    product.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color:
                                          selected ? _kAccent : _kTextPrimary,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 18),

                  // Info admin review.
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _kAccent.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _kAccent.withValues(alpha: 0.30),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          color: _kAccent,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Postingan kamu akan ditinjau admin Natalo '
                            'sebelum tayang di Feed. Biasanya butuh '
                            '1-24 jam.',
                            style: TextStyle(
                              color: _kAccent.withValues(alpha: 0.95),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: Color(0xFFEF4444),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Sticky submit button.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: _submitting ? null : _submit,
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded),
                  label: Text(_submitting ? 'Mengirim...' : 'Upload ke Feed'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kAccent,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFF334155),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// 4. UPLOAD PROGRESS — batch upload + create post + success / fail.
// ════════════════════════════════════════════════════════════════

class FeedPhotoUploadProgressScreen extends StatefulWidget {
  final List<File> files;
  final String title;
  final List<String> productIds;

  const FeedPhotoUploadProgressScreen({
    super.key,
    required this.files,
    required this.title,
    required this.productIds,
  });

  @override
  State<FeedPhotoUploadProgressScreen> createState() =>
      _FeedPhotoUploadProgressScreenState();
}

class _FeedPhotoUploadProgressScreenState
    extends State<FeedPhotoUploadProgressScreen> {
  int _uploadedCount = 0;
  String _stage = 'Mengunggah foto...';
  String? _error;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    try {
      // Step 1: Batch upload photos serial dengan progress.
      final uploaded = await feedPhotoService.uploadAllPhotos(
        widget.files,
        onProgress: (done, total) {
          if (!mounted) return;
          setState(() {
            _uploadedCount = done;
            _stage = 'Mengunggah foto $done dari $total...';
          });
        },
      );

      if (!mounted) return;
      setState(() => _stage = 'Mengirim postingan...');

      // Step 2: Create FeedPost dengan media array.
      // Discard result — kita tidak butuh postId di success flow,
      // FeedPostSubmittedScreen show generic confirmation tanpa link
      // ke post (post masih PENDING_REVIEW, belum publik).
      await feedPhotoService.createPhotoPost(
        images: uploaded,
        title: widget.title,
        productIds: widget.productIds,
      );

      if (!mounted) return;
      setState(() {
        _done = true;
        _stage = 'Berhasil!';
      });

      AppHaptics.success();

      // Navigate ke success screen (reuse video flow success).
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const FeedPostSubmittedScreen(),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = 'Upload gagal';
        _error = e is FeedPhotoUploadException
            ? e.message
            : 'Koneksi tidak stabil. Periksa internet kamu dan coba lagi.';
      });
      AppHaptics.warning();
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.files.length;
    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: _done
                      ? const Color(0xFF22C55E).withValues(alpha: 0.15)
                      : _error != null
                          ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                          : _kAccent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _done
                      ? Icons.check_rounded
                      : _error != null
                          ? Icons.error_outline_rounded
                          : Icons.cloud_upload_rounded,
                  color: _done
                      ? const Color(0xFF22C55E)
                      : _error != null
                          ? const Color(0xFFEF4444)
                          : _kAccent,
                  size: 48,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                _stage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _kTextPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (_error == null && !_done) ...[
                const SizedBox(height: 18),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: total > 0 ? _uploadedCount / total : 0,
                    backgroundColor: _kSurface,
                    minHeight: 6,
                    valueColor: const AlwaysStoppedAnimation<Color>(_kAccent),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFEF4444),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text('Kembali ke Detail'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

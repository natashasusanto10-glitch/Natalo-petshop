import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../models/feed_post.dart';
import '../services/api_client.dart';
import '../services/feed_service.dart';
import '../state/feed_store.dart';
import '../theme/natalo_colors.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import '../widgets/app_toast.dart';

/// Edit Postingan — edit caption + manage tagged products.
/// Video/thumbnail tidak bisa di-edit (replace upload ulang).
class MemberPostEditScreen extends StatefulWidget {
  final FeedPost post;

  const MemberPostEditScreen({super.key, required this.post});

  @override
  State<MemberPostEditScreen> createState() => _MemberPostEditScreenState();
}

class _MemberPostEditScreenState extends State<MemberPostEditScreen> {
  late final TextEditingController _captionController;
  late final Set<String> _selectedProductIds;
  List<_EditableTaggedProduct> _taggableProducts = const [];
  bool _saving = false;
  bool _loadingProducts = false;
  String? _productError;

  static const _maxCaptionLength = 280;
  static const _maxTaggedProducts = 3;

  @override
  void initState() {
    super.initState();
    _captionController = TextEditingController(text: widget.post.caption ?? '');
    _selectedProductIds = widget.post.productIds.toSet();
    _loadTaggableProducts();
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    AppHaptics.tap();
    final caption = _captionController.text.trim();
    setState(() => _saving = true);
    try {
      await feedService.updateMyPost(
        widget.post.id,
        title: _titleFromCaption(caption),
        description: caption.isEmpty ? null : caption,
        productIds: _selectedProductIds.toList(),
      );
      if (!mounted) return;
      final wasActive = widget.post.statusInfo == FeedPostStatus.active;
      // Sync ke FeedStore — semua screen lain (Reels, grid Postingan Saya,
      // Detail) yang baca caption/status post ini ikut update. Status
      // backend reset ke PENDING_REVIEW kalau wasActive (re-review).
      final existing = feedStore.get(widget.post.id);
      if (existing != null) {
        feedStore.applyPostUpdate(existing.copyWith(
          caption: caption.isEmpty ? null : caption,
          description: caption.isEmpty ? '' : caption,
          status: wasActive ? 'PENDING_REVIEW' : existing.status,
        ));
      }
      AppToast.show(
        context,
        wasActive
            ? 'Perubahan tersimpan. Postingan masuk review ulang.'
            : 'Perubahan tersimpan.',
      );
      Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (!mounted) return;
      AppHaptics.warning();
      AppToast.show(
        context,
        error.message,
        kind: ToastKind.error,
      );
    } catch (_) {
      if (!mounted) return;
      AppHaptics.warning();
      AppToast.show(
        context,
        'Perubahan belum bisa disimpan. Coba lagi.',
        kind: ToastKind.error,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _titleFromCaption(String caption) {
    if (caption.isEmpty) return 'Postingan baru';
    final firstLine = caption.split('\n').first.trim();
    final title = firstLine.isEmpty ? caption : firstLine;
    if (title.length <= 200) return title;
    return title.substring(0, 200).trimRight();
  }

  Future<List<_EditableTaggedProduct>> _loadTaggableProducts({
    bool rethrowOnError = false,
  }) async {
    if (_loadingProducts) return _taggableProducts;
    setState(() {
      _loadingProducts = true;
      _productError = null;
    });
    try {
      final raw = await feedService.fetchPinnableProducts(limit: 120);
      final products = raw
          .whereType<Map>()
          .map((item) => _EditableTaggedProduct.fromJson(item))
          .where((product) => product.id.isNotEmpty)
          .toList();
      if (!mounted) return const [];
      setState(() {
        _taggableProducts = products;
        _loadingProducts = false;
      });
      return products;
    } catch (_) {
      if (!mounted) return const [];
      setState(() {
        _productError = 'Produk belum bisa dimuat.';
        _loadingProducts = false;
      });
      if (rethrowOnError) rethrow;
      return const [];
    }
  }

  Future<void> _openProductPicker() async {
    AppHaptics.tap();
    if (_taggableProducts.isEmpty && !_loadingProducts) {
      await _loadTaggableProducts();
    }
    if (!mounted) return;
    final result = await showModalBottomSheet<_TaggedProductPickerResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TaggedProductPickerSheet(
        products: _taggableProducts,
        selectedIds: _selectedProductIds,
        loading: _loadingProducts,
        errorText: _productError,
        onRetry: () => _loadTaggableProducts(rethrowOnError: true),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _selectedProductIds
        ..clear()
        ..addAll(result.selectedIds);
      _taggableProducts = result.products;
    });
  }

  List<_EditableTaggedProduct> get _selectedProducts {
    if (_selectedProductIds.isEmpty) return const [];
    final byId = {
      for (final product in _taggableProducts) product.id: product,
    };
    return _selectedProductIds
        .map((id) => byId[id])
        .whereType<_EditableTaggedProduct>()
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFF),
      appBar: AppBar(
        title: const Text('Edit Postingan'),
        backgroundColor: const Color(0xFFF7FAFF),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Video preview thumbnail
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF1F2937),
              borderRadius: BorderRadius.circular(14),
            ),
            child: AspectRatio(
              aspectRatio: widget.post.aspectRatio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (widget.post.thumbnailUrl != null &&
                      widget.post.thumbnailUrl!.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: CachedNetworkImage(
                        imageUrl: widget.post.thumbnailUrl!,
                        fit: BoxFit.cover,
                        fadeInDuration: const Duration(milliseconds: 220),
                        fadeOutDuration: const Duration(milliseconds: 120),
                        fadeInCurve: Curves.easeOut,
                        placeholder: (_, __) => Shimmer.fromColors(
                          baseColor: NataloColors.surface,
                          highlightColor: NataloColors.border,
                          child: Container(color: NataloColors.surface),
                        ),
                        errorWidget: (_, __, ___) => Container(),
                      ),
                    ),
                  Center(
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              widget.post.isVideo
                  ? 'Video tidak bisa diganti. Untuk video baru, hapus postingan lalu upload ulang.'
                  : 'Media tidak bisa diganti. Untuk foto baru, hapus postingan lalu upload ulang.',
              style: const TextStyle(
                color: NataloColors.textTertiary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Caption editor
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Text(
              'Caption',
              style: TextStyle(
                color: NataloColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          TextField(
            controller: _captionController,
            maxLines: 5,
            minLines: 3,
            maxLength: _maxCaptionLength,
            enabled: !_saving,
            decoration: const InputDecoration(
              hintText: 'Tulis caption postingan…',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          // Tagged products section
          _TaggedProductsCard(
            selectedProducts: _selectedProducts,
            selectedCount: _selectedProductIds.length,
            loading: _loadingProducts,
            onManage: _saving ? null : _openProductPicker,
          ),
          const SizedBox(height: 10),
          if (widget.post.statusInfo == FeedPostStatus.active)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: const Text(
                'Catatan: perubahan pada postingan yang sudah tayang akan masuk review admin lagi sebelum tampil publik.',
                style: TextStyle(
                  color: Color(0xFF92400E),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : const Text('Simpan Perubahan'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text(
              'Batal',
              style: TextStyle(
                color: NataloColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaggedProductsCard extends StatelessWidget {
  final List<_EditableTaggedProduct> selectedProducts;
  final int selectedCount;
  final bool loading;
  final VoidCallback? onManage;

  const _TaggedProductsCard({
    required this.selectedProducts,
    required this.selectedCount,
    required this.loading,
    required this.onManage,
  });

  @override
  Widget build(BuildContext context) {
    final hasResolvedProducts = selectedProducts.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDDE8F8)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFFCE7F3),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.local_offer_outlined,
                  color: Color(0xFFBE185D),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Produk Ditag',
                      style: TextStyle(
                        color: NataloColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      loading
                          ? 'Memuat produk...'
                          : selectedCount == 0
                              ? 'Belum ada produk'
                              : '$selectedCount produk ditag',
                      style: const TextStyle(
                        color: NataloColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onManage,
                child: const Text(
                  'Atur',
                  style: TextStyle(
                    color: NataloColors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (hasResolvedProducts) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final product in selectedProducts)
                    _SelectedProductChip(product: product),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SelectedProductChip extends StatelessWidget {
  final _EditableTaggedProduct product;

  const _SelectedProductChip({required this.product});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.fromLTRB(6, 5, 9, 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ProductThumb(url: product.imageUrl, size: 24),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              product.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: NataloColors.textPrimary,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaggedProductPickerResult {
  final Set<String> selectedIds;
  final List<_EditableTaggedProduct> products;

  const _TaggedProductPickerResult(this.selectedIds, this.products);
}

class _TaggedProductPickerSheet extends StatefulWidget {
  final List<_EditableTaggedProduct> products;
  final Set<String> selectedIds;
  final bool loading;
  final String? errorText;
  final Future<List<_EditableTaggedProduct>> Function() onRetry;

  const _TaggedProductPickerSheet({
    required this.products,
    required this.selectedIds,
    required this.loading,
    required this.errorText,
    required this.onRetry,
  });

  @override
  State<_TaggedProductPickerSheet> createState() =>
      _TaggedProductPickerSheetState();
}

class _TaggedProductPickerSheetState extends State<_TaggedProductPickerSheet> {
  late final Set<String> _selected = {...widget.selectedIds};
  late List<_EditableTaggedProduct> _products = widget.products;
  late String? _errorText = widget.errorText;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  bool _retrying = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<_EditableTaggedProduct> get _filteredProducts {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _products;
    return _products
        .where((product) => product.name.toLowerCase().contains(q))
        .toList();
  }

  void _toggle(_EditableTaggedProduct product) {
    AppHaptics.tap();
    setState(() {
      if (_selected.contains(product.id)) {
        _selected.remove(product.id);
      } else if (_selected.length <
          _MemberPostEditScreenState._maxTaggedProducts) {
        _selected.add(product.id);
      } else {
        AppHaptics.warning();
        AppToast.show(
          context,
          'Maksimal ${_MemberPostEditScreenState._maxTaggedProducts} produk.',
          kind: ToastKind.info,
        );
      }
    });
  }

  Future<void> _retry() async {
    setState(() {
      _retrying = true;
      _errorText = null;
    });
    try {
      final products = await widget.onRetry();
      if (!mounted) return;
      setState(() {
        _products = products;
        _errorText = null;
        _retrying = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorText = 'Produk belum bisa dimuat.';
        _retrying = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final products = _filteredProducts;
    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomInset),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1D5DB),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Produk Ditag',
                          style: TextStyle(
                            color: NataloColors.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(_selected.clear),
                        child: const Text('Hapus Semua'),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Cari produk yang pernah dibeli',
                      prefixIcon: const Icon(Icons.search_rounded),
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFFE2E8F0),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFFE2E8F0),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${_selected.length}/${_MemberPostEditScreenState._maxTaggedProducts} produk dipilih',
                      style: const TextStyle(
                        color: NataloColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _buildProductList(products, scrollController),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
                    child: FilledButton(
                      onPressed: () => Navigator.pop(
                        context,
                        _TaggedProductPickerResult(_selected, _products),
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                        backgroundColor: NataloColors.primary,
                      ),
                      child: const Text('Simpan Produk Ditag'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProductList(
    List<_EditableTaggedProduct> products,
    ScrollController scrollController,
  ) {
    if (widget.loading || _retrying) {
      return const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2.4,
          color: NataloColors.primary,
        ),
      );
    }
    if ((_errorText ?? '').isNotEmpty && _products.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _errorText!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: NataloColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _retry,
                child: const Text('Coba Lagi'),
              ),
            ],
          ),
        ),
      );
    }
    if (products.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Text(
            'Belum ada produk yang bisa ditag. Produk muncul setelah order dibayar dan diterima.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: NataloColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
        ),
      );
    }
    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      itemCount: products.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final product = products[index];
        final selected = _selected.contains(product.id);
        return ListTile(
          contentPadding: EdgeInsets.zero,
          onTap: () => _toggle(product),
          leading: _ProductThumb(url: product.imageUrl, size: 46),
          title: Text(
            product.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: NataloColors.textPrimary,
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          subtitle: Text(
            [
              if (product.price > 0) formatRupiah(product.price.toDouble()),
              if ((product.orderNumber ?? '').isNotEmpty) product.orderNumber!,
            ].join(' • '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: NataloColors.textSecondary,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          trailing: Icon(
            selected
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            color: selected ? NataloColors.primary : const Color(0xFFCBD5E1),
          ),
        );
      },
    );
  }
}

class _ProductThumb extends StatelessWidget {
  final String? url;
  final double size;

  const _ProductThumb({required this.url, required this.size});

  @override
  Widget build(BuildContext context) {
    final imageUrl = url ?? '';
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: Container(
        width: size,
        height: size,
        color: const Color(0xFFE2E8F0),
        child: imageUrl.isEmpty
            ? const Icon(
                Icons.inventory_2_outlined,
                color: NataloColors.textTertiary,
              )
            : CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const Icon(
                  Icons.inventory_2_outlined,
                  color: NataloColors.textTertiary,
                ),
              ),
      ),
    );
  }
}

class _EditableTaggedProduct {
  final String id;
  final String slug;
  final String name;
  final String? imageUrl;
  final double price;
  final String? orderNumber;

  const _EditableTaggedProduct({
    required this.id,
    required this.slug,
    required this.name,
    this.imageUrl,
    this.price = 0,
    this.orderNumber,
  });

  factory _EditableTaggedProduct.fromJson(Map<dynamic, dynamic> json) {
    final priceRaw = json['price'] ?? json['discountPrice'] ?? 0;
    return _EditableTaggedProduct(
      id: (json['productId'] ?? json['id'] ?? '').toString(),
      slug: (json['slug'] ?? '').toString(),
      name: (json['name'] ?? json['title'] ?? 'Produk Natalo').toString(),
      imageUrl: (json['imageUrl'] ?? '').toString(),
      price: priceRaw is num
          ? priceRaw.toDouble()
          : double.tryParse(priceRaw.toString()) ?? 0,
      orderNumber: json['orderNumber']?.toString(),
    );
  }
}

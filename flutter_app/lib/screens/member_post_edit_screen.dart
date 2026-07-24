import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../models/feed_post.dart';
import '../models/new_post_user_tag.dart';
import '../services/api_client.dart';
import '../services/feed_service.dart';
import '../state/feed_store.dart';
import '../theme/natalo_colors.dart';
import '../theme/natalo_text.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import '../widgets/app_toast.dart';
import 'feed_post/feed_tag_people_screen.dart';
import 'feed_post/feed_tag_people_video_screen.dart';

/// Apakah edit ini akan mengembalikan post ke antrian review admin?
///
/// Cocok dengan aturan server (post-moderation.ts `editReTriggersModeration`):
/// sekarang TIDAK ada konten yang di-review ulang saat edit — foto maupun
/// video tetap tayang. Selalu false. Parameter dipertahankan supaya call site
/// tak berubah kalau kebijakan berubah lagi.
bool feedPostEditNeedsReview({
  required bool wasActive,
  required bool isVideo,
}) =>
    false;

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
  late List<NewPostUserTag> _taggedUsers = widget.post.taggedUsers
      .map((t) => NewPostUserTag(
            userId: t.userId,
            username: t.username ?? '',
            name: t.name,
            profilePhotoUrl: t.profilePhotoUrl,
            mediaIndex: t.mediaIndex,
            x: t.x,
            y: t.y,
          ))
      .toList();
  bool _taggedUsersEdited = false;

  static const _maxCaptionLength = 2000;
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
        taggedUsers: _taggedUsersEdited ? _taggedUsers : null,
      );
      if (!mounted) return;
      final wasActive = widget.post.statusInfo == FeedPostStatus.active;
      final needsReview = feedPostEditNeedsReview(
        wasActive: wasActive,
        isVideo: widget.post.isVideo,
      );
      // Sync ke FeedStore — semua screen lain (Reels, grid Postingan Saya,
      // Detail) yang baca caption/status post ini ikut update. Server hanya
      // re-review VIDEO yang tayang; foto/carousel tetap ACTIVE — optimistic
      // status di sini memprediksi keputusan server itu.
      //
      // Fallback ke widget.post kalau post ini belum ada di store (mis.
      // screen dibuka dari rute yang tidak sempat seed FeedStore terlebih
      // dulu). Tanpa fallback ini, caller re-sync (feedStore.get →
      // setState) jadi no-op diam-diam dan caption/status baru baru
      // kelihatan setelah refetch — store TETAP harus ditulis di kedua
      // kasus, bukan cuma saat sudah ada entry.
      final base = feedStore.get(widget.post.id) ?? widget.post;
      feedStore.applyPostUpdate(base.copyWith(
        caption: caption.isEmpty ? null : caption,
        description: caption.isEmpty ? '' : caption,
        status: needsReview ? 'PENDING_REVIEW' : base.status,
        taggedUsers: _taggedUsersEdited
            ? _taggedUsers
                .map((t) => FeedTaggedUser(
                      userId: t.userId,
                      username: t.username,
                      name: t.name,
                      profilePhotoUrl: t.profilePhotoUrl,
                      mediaId: null,
                      mediaIndex: t.mediaIndex,
                      x: t.x,
                      y: t.y,
                    ))
                .toList()
            : null,
      ));
      AppToast.show(
        context,
        needsReview
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
    // Caption kosong → title kosong ("") juga; tanpa placeholder (paritas IG).
    if (caption.isEmpty) return '';
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

  Future<void> _openTagPeople() async {
    AppHaptics.tap();
    final List<NewPostUserTag>? result;
    if (widget.post.isVideo) {
      result = await Navigator.of(context).push<List<NewPostUserTag>>(
        MaterialPageRoute(
          builder: (_) => FeedTagPeopleVideoScreen(initialTags: _taggedUsers),
        ),
      );
    } else {
      final images = widget.post.mediaItems
          .map<ImageProvider>((m) => CachedNetworkImageProvider(m.mediaUrl))
          .toList();
      if (images.isEmpty) return; // defensive: foto tanpa media, jangan crash
      result = await Navigator.of(context).push<List<NewPostUserTag>>(
        MaterialPageRoute(
          builder: (_) => FeedTagPeopleScreen(
            photoImages: images,
            initialTags: _taggedUsers,
          ),
        ),
      );
    }
    if (result == null || !mounted) return;
    setState(() {
      _taggedUsers = result!;
      _taggedUsersEdited = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Header IG "Edit info": X (batal) kiri, judul tengah, centang
            // bulat (simpan) kanan.
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: cs.onSurface),
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    tooltip: 'Batal',
                  ),
                  Text(
                    'Edit info',
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 16,
                      fontWeight: NataloWeight.strong,
                    ),
                  ),
                  _SaveCheckButton(
                    saving: _saving,
                    onTap: _saving ? null : _save,
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  // Cover thumbnail + caption borderless dalam satu Row (ala IG).
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _CoverThumb(post: widget.post),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _captionController,
                          minLines: 3,
                          maxLines: 8,
                          maxLength: _maxCaptionLength,
                          enabled: !_saving,
                          style: TextStyle(color: cs.onSurface, fontSize: 14),
                          decoration: const InputDecoration(
                            hintText: 'Tulis caption...',
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            filled: false,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                            counterText: '',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.post.isVideo
                        ? 'Video tidak bisa diganti. Untuk video baru, hapus postingan lalu upload ulang.'
                        : 'Media tidak bisa diganti. Untuk foto baru, hapus postingan lalu upload ulang.',
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 11,
                      fontWeight: NataloWeight.body,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Divider(height: 1, color: cs.outlineVariant),
                  // Baris "Produk ditandai" (list polos + chevron).
                  InkWell(
                    onTap: _saving ? null : _openProductPicker,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Produk ditandai',
                            style: TextStyle(
                              color: cs.onSurface,
                              fontSize: 15,
                              fontWeight: NataloWeight.body,
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _loadingProducts
                                    ? 'Memuat...'
                                    : _selectedProductIds.isEmpty
                                        ? 'Tambah'
                                        : '${_selectedProductIds.length} dipilih',
                                style: TextStyle(
                                  color: cs.onSurfaceVariant,
                                  fontSize: 13,
                                  fontWeight: NataloWeight.body,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: cs.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  Divider(height: 1, color: cs.outlineVariant),
                  // Baris "Orang ditandai" (Spec D).
                  InkWell(
                    onTap: _saving ? null : _openTagPeople,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Orang ditandai',
                              style: TextStyle(
                                color: cs.onSurface,
                                fontSize: 15,
                                fontWeight: NataloWeight.body,
                              )),
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(
                              _taggedUsers.isEmpty
                                  ? 'Tambah'
                                  : '${_taggedUsers.length} dipilih',
                              style: TextStyle(
                                color: cs.onSurfaceVariant,
                                fontSize: 13,
                                fontWeight: NataloWeight.body,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.chevron_right_rounded,
                                color: cs.onSurfaceVariant),
                          ]),
                        ],
                      ),
                    ),
                  ),
                  Divider(height: 1, color: cs.outlineVariant),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoverThumb extends StatelessWidget {
  final FeedPost post;
  const _CoverThumb({required this.post});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final url = post.thumbnailUrl;
    return Container(
      width: 56,
      height: 56,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (url != null && url.isNotEmpty)
            CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              placeholder: (_, __) => Shimmer.fromColors(
                baseColor: cs.surfaceContainerHighest,
                highlightColor: cs.outlineVariant,
                child: Container(color: cs.surfaceContainerHighest),
              ),
              errorWidget: (_, __, ___) => const SizedBox.shrink(),
            ),
          if (post.isVideo)
            const Center(
              child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
            ),
        ],
      ),
    );
  }
}

class _SaveCheckButton extends StatelessWidget {
  final bool saving;
  final VoidCallback? onTap;
  const _SaveCheckButton({required this.saving, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        margin: const EdgeInsets.only(right: 8),
        decoration: const BoxDecoration(
          color: NataloColors.primary,
          shape: BoxShape.circle,
        ),
        child: saving
            ? const Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.check_rounded, color: Colors.white, size: 18),
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
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final products = _filteredProducts;
    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
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
                    color: cs.onSurfaceVariant,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Produk Ditag',
                          style: TextStyle(
                            color: cs.onSurface,
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
                      fillColor: cs.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: cs.outlineVariant,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: cs.outlineVariant,
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
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
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
    final cs = Theme.of(context).colorScheme;
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
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _retry,
                child: const Text('Coba lagi'),
              ),
            ],
          ),
        ),
      );
    }
    if (products.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            'Belum ada produk yang bisa ditag. Produk muncul setelah order dibayar dan diterima.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: cs.onSurfaceVariant,
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
            style: TextStyle(
              color: cs.onSurface,
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
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          trailing: Icon(
            selected
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            color: selected ? NataloColors.primary : cs.onSurfaceVariant,
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
    final cs = Theme.of(context).colorScheme;
    final imageUrl = url ?? '';
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: Container(
        width: size,
        height: size,
        color: cs.surfaceContainerHighest,
        child: imageUrl.isEmpty
            ? Icon(
                Icons.inventory_2_outlined,
                color: cs.onSurfaceVariant,
              )
            : CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Icon(
                  Icons.inventory_2_outlined,
                  color: cs.onSurfaceVariant,
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

import 'package:flutter/material.dart';
import '../theme/natalo_colors.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../models/review.dart';
import '../services/api_client.dart';
import '../services/review_service.dart';
import '../state/member_store.dart';
import '../utils/formatters.dart';
import '../utils/read_only_mode.dart';
import '../widgets/app_product_image.dart';
import '../widgets/app_ui.dart';
import '../widgets/glass_surface.dart';
import '../widgets/natalo_paw_refresh_indicator.dart';

const _brandBlue = NataloColors.primary;
const _starGold = Color(0xFFF6B73C);
const _successGreen = Color(0xFF16A34A);

enum _ReviewTab { pending, reviewed }

class MemberReviewsScreen extends StatefulWidget {
  const MemberReviewsScreen({super.key});

  @override
  State<MemberReviewsScreen> createState() => _MemberReviewsScreenState();
}

class _MemberReviewsScreenState extends State<MemberReviewsScreen> {
  late Future<List<ReviewableItem>> _itemsFuture;
  _ReviewTab _activeTab = _ReviewTab.pending;
  final List<_ReviewedProductReview> _localReviews = [];

  @override
  void initState() {
    super.initState();
    _itemsFuture = _loadItems();
    // Deep link integration: kalau dipush dengan arguments `{orderItemId}`
    // (mis. dari order detail "Review" button), auto-open submit sheet
    // untuk item tsb setelah list loaded. UX: user tidak perlu cari item
    // ulang di list — langsung masuk form review.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final args = ModalRoute.of(context)?.settings.arguments;
      final targetItemId = args is Map ? args['orderItemId']?.toString() : null;
      if (targetItemId == null || targetItemId.isEmpty) return;
      try {
        final items = await _itemsFuture;
        if (!mounted) return;
        final target = items.firstWhere(
          (i) => i.orderItemId == targetItemId && !i.hasReviewed,
          orElse: () =>
              items.isNotEmpty ? items.first : throw StateError('no items'),
        );
        if (target.orderItemId == targetItemId && !target.hasReviewed) {
          _openReviewForm(target);
        }
      } catch (_) {
        // Item not reviewable atau list empty — biarin user lihat list.
      }
    });
  }

  Future<List<ReviewableItem>> _loadItems() {
    if (!memberStore.isLoggedIn) return Future.value(const []);
    return reviewService.fetchReviewableItems();
  }

  Future<void> _refresh() async {
    setState(() => _itemsFuture = _loadItems());
    await _itemsFuture;
  }

  Future<void> _openReviewForm(ReviewableItem item) async {
    final submitted = await showModalBottomSheet<_SubmittedReview>(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ReviewSubmitSheet(item: item),
    );
    if (submitted == null || !mounted) return;
    setState(() {
      _activeTab = _ReviewTab.reviewed;
      _localReviews
          .removeWhere((review) => review.item.orderItemId == item.orderItemId);
      _localReviews.insert(
        0,
        _ReviewedProductReview(
          item: item,
          rating: submitted.rating,
          content: submitted.content,
          createdAt: DateTime.now(),
        ),
      );
      _itemsFuture = _loadItems();
    });
    // Snackbar conditional based on pointsAwarded:
    //   - >0 (review LENGKAP) → celebration "Selamat! +5 poin loyal"
    //   - 0 (review minimal) → nudge "Tambah foto+deskripsi untuk +5 poin"
    final earnedBonus = submitted.pointsAwarded > 0;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          earnedBonus
              ? '🎁 Review terkirim. +${submitted.pointsAwarded} poin loyal masuk akunmu!'
              : 'Review terkirim. Tambah foto + deskripsi (min 10 huruf) untuk dapat 5 poin loyal.',
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: earnedBonus ? const Color(0xFF059669) : null,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  List<ReviewableItem> _pendingItems(List<ReviewableItem> items) {
    final localIds =
        _localReviews.map((review) => review.item.orderItemId).toSet();
    return items
        .where(
            (item) => !item.hasReviewed && !localIds.contains(item.orderItemId))
        .toList();
  }

  List<_ReviewedProductReview> _reviewedItems(List<ReviewableItem> items) {
    final remote = items.where((item) => item.hasReviewed).map((item) {
      return _ReviewedProductReview(
        item: item,
        rating: item.reviewRating ?? 5,
        content: item.reviewText,
        createdAt: item.reviewedAt ?? item.orderDate ?? DateTime.now(),
      );
    });
    final remoteIds = remote.map((review) => review.item.orderItemId).toSet();
    return [
      ..._localReviews
          .where((review) => !remoteIds.contains(review.item.orderItemId)),
      ...remote,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Ulasan Produk'),
        backgroundColor: cs.surface,
        surfaceTintColor: cs.surface,
      ),
      body: !memberStore.isLoggedIn
          ? AppEmptyState(
              lottiePath: AppLottiePaths.empty,
              title: 'Login untuk memberi review',
              body: 'Review hanya tersedia untuk member yang sudah belanja.',
              buttonLabel: 'Login',
              onPressed: () => Navigator.pushNamed(context, '/member/login'),
            )
          : NataloPawRefreshIndicator(
              onRefresh: _refresh,
              child: FutureBuilder<List<ReviewableItem>>(
                future: _itemsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const AppSkeletonList();
                  }

                  if (snapshot.hasError) {
                    return ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        AppEmptyState(
                          title: 'Ulasan belum bisa dimuat',
                          body: snapshot.error is ApiException
                              ? (snapshot.error as ApiException).message
                              : 'Coba tarik layar untuk memuat ulang.',
                          buttonLabel: 'Muat Ulang',
                          onPressed: _refresh,
                        ),
                      ],
                    );
                  }

                  final items = snapshot.data ?? const <ReviewableItem>[];
                  final pending = _pendingItems(items);
                  final reviewed = _reviewedItems(items);
                  final showingPending = _activeTab == _ReviewTab.pending;

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
                    children: [
                      const _ReviewPageIntro(),
                      const SizedBox(height: 16),
                      _ReviewSummaryRow(
                        pendingCount: pending.length,
                        reviewedCount: reviewed.length,
                      ),
                      const SizedBox(height: 16),
                      _ReviewSegmentedTabs(
                        active: _activeTab,
                        pendingCount: pending.length,
                        reviewedCount: reviewed.length,
                        onChanged: (tab) => setState(() => _activeTab = tab),
                      ),
                      const SizedBox(height: 16),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeOutCubic,
                        child: showingPending
                            ? _PendingReviewList(
                                key: const ValueKey('pending'),
                                items: pending,
                                onReview: _openReviewForm,
                              )
                            : _ReviewedList(
                                key: const ValueKey('reviewed'),
                                reviews: reviewed,
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
    );
  }
}

class _ReviewPageIntro extends StatelessWidget {
  const _ReviewPageIntro();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ulasan Produk',
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            height: 1.18,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Beri rating dan cerita pengalamanmu untuk produk yang sudah sampai.',
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 14,
            fontWeight: FontWeight.w500,
            height: 1.42,
          ),
        ),
      ],
    );
  }
}

class _ReviewSummaryRow extends StatelessWidget {
  final int pendingCount;
  final int reviewedCount;

  const _ReviewSummaryRow({
    required this.pendingCount,
    required this.reviewedCount,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ReviewSummaryCard(
            icon: Icons.schedule_rounded,
            count: pendingCount,
            label: 'Menunggu Review',
            color: _brandBlue,
            tint: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF0B7FEA).withValues(alpha: 0.20)
                : const Color(0xFFEAF5FF),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ReviewSummaryCard(
            icon: Icons.check_circle_rounded,
            count: reviewedCount,
            label: 'Sudah Review',
            color: _successGreen,
            tint: const Color(0xFFECFDF3),
          ),
        ),
      ],
    );
  }
}

class _ReviewSummaryCard extends StatelessWidget {
  final IconData icon;
  final int count;
  final String label;
  final Color color;
  final Color tint;

  const _ReviewSummaryCard({
    required this.icon,
    required this.count,
    required this.label,
    required this.color,
    required this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GlassSurface(
      radius: 22,
      padding: const EdgeInsets.all(14),
      tint: cs.surface,
      child: Row(
        children: [
          Container(
            height: 42,
            width: 42,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$count',
                  style: TextStyle(
                    color: color,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewSegmentedTabs extends StatelessWidget {
  final _ReviewTab active;
  final int pendingCount;
  final int reviewedCount;
  final ValueChanged<_ReviewTab> onChanged;

  const _ReviewSegmentedTabs({
    required this.active,
    required this.pendingCount,
    required this.reviewedCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          _ReviewTabButton(
            label: 'Menunggu Review ($pendingCount)',
            active: active == _ReviewTab.pending,
            onTap: () => onChanged(_ReviewTab.pending),
          ),
          _ReviewTabButton(
            label: 'Sudah Direview ($reviewedCount)',
            active: active == _ReviewTab.reviewed,
            onTap: () => onChanged(_ReviewTab.reviewed),
          ),
        ],
      ),
    );
  }
}

class _ReviewTabButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ReviewTabButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
          decoration: BoxDecoration(
            color: active ? _brandBlue : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: active
                  ? Colors.white
                  : Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _PendingReviewList extends StatelessWidget {
  final List<ReviewableItem> items;
  final ValueChanged<ReviewableItem> onReview;

  const _PendingReviewList({
    super.key,
    required this.items,
    required this.onReview,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const _ReviewEmptyState(
        icon: Icons.verified_rounded,
        title: 'Semua produk sudah kamu review',
        body: 'Terima kasih sudah berbagi pengalaman belanja di Natalo.',
      );
    }

    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          AppAnimatedEntrance(
            index: i,
            child: _ReviewableItemCard(
              item: items[i],
              onReview: () => onReview(items[i]),
            ),
          ),
          if (i != items.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _ReviewedList extends StatelessWidget {
  final List<_ReviewedProductReview> reviews;

  const _ReviewedList({super.key, required this.reviews});

  @override
  Widget build(BuildContext context) {
    if (reviews.isEmpty) {
      return const _ReviewEmptyState(
        icon: Icons.rate_review_outlined,
        title: 'Belum ada review',
        body: 'Review yang sudah kamu kirim akan tampil di sini.',
      );
    }

    return Column(
      children: [
        for (var i = 0; i < reviews.length; i++) ...[
          AppAnimatedEntrance(
            index: i,
            child: _ReviewedItemCard(review: reviews[i]),
          ),
          if (i != reviews.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _ReviewableItemCard extends StatelessWidget {
  final ReviewableItem item;
  final VoidCallback onReview;

  const _ReviewableItemCard({required this.item, required this.onReview});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GlassSurface(
      radius: 22,
      padding: const EdgeInsets.all(14),
      tint: cs.surface,
      child: Column(
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: AppProductImage(
                  imageUrl: item.productImage ?? '',
                  height: 74,
                  width: 74,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.productName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    if (item.variantLabel != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.variantLabel!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 5),
                    Text(
                      '${_priceText(item)} x ${item.quantity}',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${item.orderNumber ?? 'Pesanan selesai'} • ${_formatDate(item.orderDate)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onReview,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              child: const Text('Beri Review'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewedItemCard extends StatelessWidget {
  final _ReviewedProductReview review;

  const _ReviewedItemCard({required this.review});

  @override
  Widget build(BuildContext context) {
    final item = review.item;
    final content = review.content?.trim();
    final cs = Theme.of(context).colorScheme;
    return GlassSurface(
      radius: 22,
      padding: const EdgeInsets.all(14),
      tint: cs.surface,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: AppProductImage(
              imageUrl: item.productImage ?? '',
              height: 72,
              width: 72,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    _MiniStars(rating: review.rating),
                    const SizedBox(width: 8),
                    Text(
                      _formatDate(review.createdAt),
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                if (content != null && content.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Text(
                    content,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _ReviewEmptyState({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GlassSurface(
      radius: 24,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 34),
      tint: cs.surface,
      child: Column(
        children: [
          Container(
            height: 64,
            width: 64,
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF0B7FEA).withValues(alpha: 0.20)
                  : const Color(0xFFEAF5FF),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Icon(icon, color: _brandBlue, size: 32),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewSubmitSheet extends StatefulWidget {
  final ReviewableItem item;

  const _ReviewSubmitSheet({required this.item});

  @override
  State<_ReviewSubmitSheet> createState() => _ReviewSubmitSheetState();
}

class _ReviewSubmitSheetState extends State<_ReviewSubmitSheet> {
  static const _maxMedia = 5;
  static const _maxVideos = 1;

  final _contentController = TextEditingController();
  final _picker = ImagePicker();
  final List<ProductReviewMedia> _mediaItems = [];
  final Set<String> _selectedSuggestions = {};
  int _rating = 0;
  bool _submitting = false;
  bool _uploadingMedia = false;

  @override
  void initState() {
    super.initState();
    // Listen text changes supaya _ReviewBonusHint reactive — saat user
    // ngetik, check "Deskripsi >= 10 huruf" auto-update.
    _contentController.addListener(_onContentChanged);
  }

  void _onContentChanged() {
    // setState minimal — cuma trigger rebuild untuk hint banner.
    // TextField sendiri tetap controlled, gak ada flicker.
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _contentController.removeListener(_onContentChanged);
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _chooseMediaSource() async {
    if (_mediaItems.length >= _maxMedia || _uploadingMedia) return;
    final source = await showModalBottomSheet<_ReviewMediaSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: GlassSurface(
            radius: 26,
            padding: const EdgeInsets.all(12),
            tint: Theme.of(context).colorScheme.surface,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PhotoSourceTile(
                  icon: Icons.photo_camera_outlined,
                  label: 'Ambil Foto',
                  onTap: () => Navigator.pop(
                    context,
                    const _ReviewMediaSource.image(ImageSource.camera),
                  ),
                ),
                _PhotoSourceTile(
                  icon: Icons.photo_library_outlined,
                  label: 'Pilih Foto',
                  onTap: () => Navigator.pop(
                    context,
                    const _ReviewMediaSource.image(ImageSource.gallery),
                  ),
                ),
                if (_mediaItems.where((item) => item.isVideo).length <
                    _maxVideos) ...[
                  _PhotoSourceTile(
                    icon: Icons.videocam_outlined,
                    label: 'Rekam Video',
                    onTap: () => Navigator.pop(
                      context,
                      const _ReviewMediaSource.video(ImageSource.camera),
                    ),
                  ),
                  _PhotoSourceTile(
                    icon: Icons.video_library_outlined,
                    label: 'Pilih Video',
                    onTap: () => Navigator.pop(
                      context,
                      const _ReviewMediaSource.video(ImageSource.gallery),
                    ),
                  ),
                ],
                if (_mediaItems.where((item) => item.isVideo).length >=
                    _maxVideos)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    child: Text(
                      'Maksimal 1 video per review.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                _PhotoSourceTile(
                  icon: Icons.close_rounded,
                  label: 'Batal',
                  onTap: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (source == null) return;
    if (source.isVideo) {
      await _pickAndUploadVideo(source.source);
    } else {
      await _pickAndUploadPhoto(source.source);
    }
  }

  Future<void> _pickAndUploadPhoto(ImageSource source) async {
    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 82,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (picked == null) return;

    setState(() => _uploadingMedia = true);
    try {
      final result = await reviewService.uploadReviewMedia(picked);
      if (!mounted) return;
      if (result.url.isEmpty) throw const ApiException('Upload foto gagal.');
      setState(
          () => _mediaItems.add(ProductReviewMedia.image(url: result.url)));
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on ReadOnlyModeException catch (error) {
      if (!mounted) return;
      showReadOnlySnackbar(context, error);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upload foto gagal: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _uploadingMedia = false);
    }
  }

  Future<void> _pickAndUploadVideo(ImageSource source) async {
    final picked = await _picker.pickVideo(
      source: source,
      maxDuration: const Duration(seconds: 30),
    );
    if (picked == null) return;

    setState(() => _uploadingMedia = true);
    try {
      var videoPath = picked.path;
      try {
        final compressed = await VideoCompress.compressVideo(
          picked.path,
          quality: VideoQuality.MediumQuality,
          includeAudio: true,
          deleteOrigin: false,
        );
        final compressedPath = compressed?.path;
        if (compressedPath != null && compressedPath.isNotEmpty) {
          videoPath = compressedPath;
        }
      } catch (_) {
        videoPath = picked.path;
      }
      final thumbnailPath = await VideoThumbnail.thumbnailFile(
        video: videoPath,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 720,
        quality: 76,
      );
      if (thumbnailPath == null || thumbnailPath.isEmpty) {
        throw const ApiException('Thumbnail video gagal dibuat.');
      }
      final thumbnail = await reviewService.uploadReviewMedia(
        XFile(thumbnailPath, mimeType: 'image/jpeg', name: 'review-thumb.jpg'),
      );
      final video = await reviewService.uploadReviewMedia(
        XFile(
          videoPath,
          mimeType: _reviewVideoMimeType(videoPath, picked.mimeType),
          name: picked.name,
        ),
      );
      if (!mounted) return;
      if (video.url.isEmpty) throw const ApiException('Upload video gagal.');
      setState(() {
        _mediaItems.add(ProductReviewMedia(
          type: 'video',
          url: video.url,
          thumbnailUrl: thumbnail.url,
        ));
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on ReadOnlyModeException catch (error) {
      if (!mounted) return;
      showReadOnlySnackbar(context, error);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upload video gagal: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _uploadingMedia = false);
    }
  }

  void _applySuggestion(String text) {
    HapticFeedback.selectionClick();
    final existing = _contentController.text.trim();
    final separator = existing.isEmpty ? '' : ', ';
    _contentController.text = '$existing$separator$text';
    _contentController.selection = TextSelection.collapsed(
      offset: _contentController.text.length,
    );
    setState(() => _selectedSuggestions.add(text));
  }

  Future<void> _submit() async {
    if (_rating == 0 || _submitting) return;
    setState(() => _submitting = true);
    try {
      final result = await reviewService.submitReview(
        productId: widget.item.productId,
        orderItemId: widget.item.orderItemId,
        rating: _rating,
        content: _contentController.text.trim().isEmpty
            ? null
            : _contentController.text.trim(),
        imageUrls: _mediaItems
            .where((item) => !item.isVideo)
            .map((item) => item.url)
            .toList(growable: false),
        media: List.unmodifiable(_mediaItems),
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.pop(
        context,
        _SubmittedReview(
          rating: _rating,
          content: _contentController.text.trim(),
          pointsAwarded: result.pointsAwarded,
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on ReadOnlyModeException catch (error) {
      if (!mounted) return;
      showReadOnlySnackbar(context, error);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal kirim review: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final cs = Theme.of(context).colorScheme;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.fromLTRB(12, 0, 12, bottom + 12),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.90,
        ),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 30,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                height: 5,
                width: 50,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ReviewSheetProductPreview(item: widget.item),
                      const SizedBox(height: 14),
                      // Reward hint banner — kasih incentive visual ke user.
                      // Reactive: check items (rating/desk/foto) berubah warna
                      // saat user isi → user lihat progress real-time menuju
                      // bonus poin.
                      _ReviewBonusHint(
                        hasRating: _rating > 0,
                        hasContent: _contentController.text.trim().length >= 10,
                        hasMedia: _mediaItems.isNotEmpty,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Bagaimana pengalamanmu dengan produk ini?',
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: PremiumStarRating(
                          value: _rating,
                          onChanged: (rating) {
                            setState(() => _rating = rating);
                            HapticFeedback.selectionClick();
                            if (rating >= 4) HapticFeedback.lightImpact();
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: Text(
                            _rating == 0
                                ? 'Sentuh bintang untuk memberi rating'
                                : _ratingLabel(_rating),
                            key: ValueKey(_rating),
                            style: TextStyle(
                              color: _rating == 0
                                  ? cs.onSurfaceVariant
                                  : _brandBlue,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: _contentController,
                        minLines: 4,
                        maxLines: 6,
                        maxLength: 500,
                        decoration: const InputDecoration(
                          hintText:
                              'Apa yang paling kamu suka dari produk ini?',
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _SuggestionChips(
                        selected: _selectedSuggestions,
                        onSelected: _applySuggestion,
                      ),
                      const SizedBox(height: 16),
                      _ReviewMediaPicker(
                        mediaItems: _mediaItems,
                        uploading: _uploadingMedia,
                        maxMedia: _maxMedia,
                        onAdd: _chooseMediaSource,
                        onRemove: (item) =>
                            setState(() => _mediaItems.remove(item)),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _rating == 0 || _submitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(_submitting ? 'Mengirim...' : 'Kirim Review'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PremiumStarRating extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const PremiumStarRating({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(5, (index) {
            final rating = index + 1;
            final active = rating <= value;
            return TweenAnimationBuilder<double>(
              key: ValueKey('$rating-$value'),
              tween: Tween(begin: active ? 1.18 : 1.0, end: 1.0),
              duration: Duration(milliseconds: 170 + (index * 18)),
              curve: Curves.easeOutBack,
              builder: (context, scale, child) {
                return Transform.scale(scale: scale, child: child);
              },
              child: IconButton(
                onPressed: () => onChanged(rating),
                padding: const EdgeInsets.symmetric(horizontal: 3),
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  transitionBuilder: (child, animation) {
                    return ScaleTransition(scale: animation, child: child);
                  },
                  child: Icon(
                    active ? Icons.star_rounded : Icons.star_border_rounded,
                    key: ValueKey(active),
                    color: active ? _starGold : const Color(0xFFD1D5DB),
                    size: 39,
                  ),
                ),
              ),
            );
          }),
        ),
        if (value == 5)
          const Positioned(
            right: -4,
            top: -5,
            child: Icon(Icons.auto_awesome_rounded, color: _starGold, size: 17),
          ),
      ],
    );
  }
}

class _ReviewSheetProductPreview extends StatelessWidget {
  final ReviewableItem item;

  const _ReviewSheetProductPreview({required this.item});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AppProductImage(
            imageUrl: item.productImage ?? '',
            height: 62,
            width: 62,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.productName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '${_priceText(item)} x ${item.quantity}',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SuggestionChips extends StatelessWidget {
  final Set<String> selected;
  final ValueChanged<String> onSelected;

  const _SuggestionChips({
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    const suggestions = [
      (Icons.thumb_up_alt_outlined, 'Produk bagus'),
      (Icons.local_shipping_outlined, 'Pengiriman cepat'),
      (Icons.inventory_2_outlined, 'Packing rapi'),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final suggestion in suggestions)
          ChoiceChip(
            selected: selected.contains(suggestion.$2),
            onSelected: (_) => onSelected(suggestion.$2),
            avatar: Icon(
              suggestion.$1,
              size: 16,
              color:
                  selected.contains(suggestion.$2) ? Colors.white : _brandBlue,
            ),
            label: Text(suggestion.$2),
            selectedColor: _brandBlue,
            backgroundColor: Theme.of(context).colorScheme.surface,
            labelStyle: TextStyle(
              color:
                  selected.contains(suggestion.$2) ? Colors.white : _brandBlue,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
            side: BorderSide(
              color: selected.contains(suggestion.$2)
                  ? _brandBlue
                  : const Color(0xFFBFDBFE),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
          ),
      ],
    );
  }
}

class _ReviewMediaSource {
  final ImageSource source;
  final bool isVideo;

  const _ReviewMediaSource.image(this.source) : isVideo = false;
  const _ReviewMediaSource.video(this.source) : isVideo = true;
}

class _ReviewMediaPicker extends StatelessWidget {
  final List<ProductReviewMedia> mediaItems;
  final bool uploading;
  final int maxMedia;
  final VoidCallback onAdd;
  final ValueChanged<ProductReviewMedia> onRemove;

  const _ReviewMediaPicker({
    required this.mediaItems,
    required this.uploading,
    required this.maxMedia,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Foto / Video Review',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              '${mediaItems.length}/$maxMedia',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        SizedBox(
          height: 84,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount:
                mediaItems.length + (mediaItems.length < maxMedia ? 1 : 0),
            separatorBuilder: (_, __) => const SizedBox(width: 9),
            itemBuilder: (context, index) {
              if (index == mediaItems.length) {
                return _AddMediaTile(uploading: uploading, onTap: onAdd);
              }

              final item = mediaItems[index];
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.network(
                      item.previewUrl,
                      height: 84,
                      width: 84,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        height: 84,
                        width: 84,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Theme.of(context).colorScheme.surfaceContainerHighest
                            : const Color(0xFFEFF4FA),
                        child: const Icon(Icons.image_not_supported_outlined),
                      ),
                    ),
                  ),
                  if (item.isVideo)
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.play_circle_fill_rounded,
                            color: Colors.white,
                            size: 34,
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    right: -6,
                    top: -6,
                    child: IconButton.filled(
                      onPressed: () => onRemove(item),
                      icon: const Icon(Icons.close_rounded, size: 16),
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        foregroundColor: Colors.white,
                        fixedSize: const Size(28, 28),
                        minimumSize: const Size(28, 28),
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AddMediaTile extends StatelessWidget {
  final bool uploading;
  final VoidCallback onTap;

  const _AddMediaTile({required this.uploading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: uploading ? null : onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 84,
        width: 112,
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? Theme.of(context).colorScheme.surfaceContainerHighest
              : const Color(0xFFF8FBFF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFBFDBFE)),
        ),
        child: uploading
            ? const Center(
                child: SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              )
            : const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_photo_alternate_outlined, color: _brandBlue),
                  SizedBox(height: 6),
                  Text(
                    '+ Media',
                    style: TextStyle(
                      color: _brandBlue,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _PhotoSourceTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PhotoSourceTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: _brandBlue),
      title: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      onTap: onTap,
    );
  }
}

class _MiniStars extends StatelessWidget {
  final int rating;

  const _MiniStars({required this.rating});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        return Icon(
          index < rating ? Icons.star_rounded : Icons.star_border_rounded,
          color: _starGold,
          size: 16,
        );
      }),
    );
  }
}

/// Reward hint banner di review form — kasih incentive visual ke user
/// untuk lengkapi review demi 5 poin loyal.
///
/// 3 check items dengan icon + warna conditional:
///   ⭐ Beri bintang
///   📝 Tulis deskripsi (min 10 huruf)
///   📸 Tambah min 1 foto/video
///
/// Saat satu check terpenuhi, icon berubah warna jadi hijau + checkmark.
/// Saat semua 3 terpenuhi, banner berubah jadi hijau celebration
/// "Siap dapat 5 poin loyal!". Memberi visual reinforcement progress.
class _ReviewBonusHint extends StatelessWidget {
  final bool hasRating;
  final bool hasContent;
  final bool hasMedia;

  const _ReviewBonusHint({
    required this.hasRating,
    required this.hasContent,
    required this.hasMedia,
  });

  bool get _isComplete => hasRating && hasContent && hasMedia;

  @override
  Widget build(BuildContext context) {
    final accent = _isComplete
        ? const Color(0xFF059669) // emerald saat lengkap
        : const Color(0xFFFBBF24); // amber saat masih ada yang kosong
    final bg = _isComplete ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB);
    final borderColor =
        _isComplete ? const Color(0xFFA7F3D0) : const Color(0xFFFCD34D);
    final headlineColor =
        _isComplete ? const Color(0xFF065F46) : const Color(0xFF92400E);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _isComplete
                      ? Icons.celebration_rounded
                      : Icons.card_giftcard_rounded,
                  color: accent,
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _isComplete
                      ? 'Siap dapat +5 poin loyal setelah submit!'
                      : 'Lengkapi review = +5 poin loyal',
                  style: TextStyle(
                    color: headlineColor,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _BonusCheckRow(
            label: 'Beri bintang',
            checked: hasRating,
          ),
          const SizedBox(height: 3),
          _BonusCheckRow(
            label: 'Tulis deskripsi (min 10 huruf)',
            checked: hasContent,
          ),
          const SizedBox(height: 3),
          _BonusCheckRow(
            label: 'Tambah min 1 foto/video',
            checked: hasMedia,
          ),
        ],
      ),
    );
  }
}

class _BonusCheckRow extends StatelessWidget {
  final String label;
  final bool checked;

  const _BonusCheckRow({required this.label, required this.checked});

  @override
  Widget build(BuildContext context) {
    final color = checked ? const Color(0xFF059669) : const Color(0xFF9CA3AF);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          checked
              ? Icons.check_circle_rounded
              : Icons.radio_button_unchecked_rounded,
          color: color,
          size: 14,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: checked ? const Color(0xFF065F46) : const Color(0xFF6B7280),
            fontSize: 11.5,
            fontWeight: checked ? FontWeight.w800 : FontWeight.w600,
            decoration:
                checked ? TextDecoration.lineThrough : TextDecoration.none,
            decorationColor: color.withValues(alpha: 0.4),
          ),
        ),
      ],
    );
  }
}

class _SubmittedReview {
  final int rating;
  final String? content;

  /// Bonus poin yang di-award oleh server kalau review LENGKAP
  /// (rating + deskripsi >= 10 char + min 1 foto/video). 0 kalau belum lengkap.
  /// Parent snackbar tampilkan feedback conditional.
  final int pointsAwarded;

  const _SubmittedReview({
    required this.rating,
    this.content,
    this.pointsAwarded = 0,
  });
}

class _ReviewedProductReview {
  final ReviewableItem item;
  final int rating;
  final String? content;
  final DateTime createdAt;

  const _ReviewedProductReview({
    required this.item,
    required this.rating,
    this.content,
    required this.createdAt,
  });
}

String _ratingLabel(int rating) {
  return switch (rating) {
    1 => 'Sangat kurang',
    2 => 'Kurang puas',
    3 => 'Cukup',
    4 => 'Puas',
    5 => 'Sangat puas',
    _ => '',
  };
}

String _reviewVideoMimeType(String path, String? mimeType) {
  if (mimeType == 'video/mp4' ||
      mimeType == 'video/webm' ||
      mimeType == 'video/quicktime') {
    return mimeType!;
  }
  final lower = path.toLowerCase();
  if (lower.endsWith('.mov')) return 'video/quicktime';
  if (lower.endsWith('.webm')) return 'video/webm';
  return 'video/mp4';
}

String _priceText(ReviewableItem item) {
  if (item.price <= 0) return 'Produk Natalo';
  return formatRupiah(item.price);
}

String _formatDate(DateTime? date) {
  if (date == null) return 'Tanggal pesanan';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

import 'package:flutter/material.dart';

import '../models/product.dart';
import '../models/review.dart';
import '../services/api_client.dart';
import '../services/review_service.dart';
import 'app_ui.dart';
import 'glass_surface.dart';

const _brandBlue = Color(0xFF0B7FEA);

class ProductReviewSection extends StatefulWidget {
  final Product product;

  const ProductReviewSection({super.key, required this.product});

  @override
  State<ProductReviewSection> createState() => _ProductReviewSectionState();
}

class _ProductReviewSectionState extends State<ProductReviewSection> {
  ReviewSummary? _summary;
  List<ProductReview> _reviews = const [];
  ReviewFilter _filter = const ReviewFilter();
  String? _nextCursor;
  bool _loading = true;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void didUpdateWidget(covariant ProductReviewSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.product.slug != widget.product.slug) {
      _filter = const ReviewFilter();
      _loadInitial();
    }
  }

  Future<void> _loadInitial() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        reviewService.fetchSummary(widget.product.slug),
        reviewService.fetchReviews(widget.product.slug, filter: _filter),
      ]);
      if (!mounted) return;
      final summary = results[0] as ReviewSummary;
      final page = results[1] as ProductReviewPage;
      setState(() {
        _summary = summary;
        _reviews = page.reviews;
        _nextCursor = page.nextCursor;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _summary = ReviewSummary(
          avgRating: widget.product.rating,
          reviewCount: widget.product.reviewCount,
          ratingBreakdown: const {},
        );
        _reviews = const [];
        _nextCursor = null;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _applyFilter(ReviewFilter filter) async {
    setState(() {
      _filter = filter.copyWith(clearCursor: true);
      _loading = true;
    });
    try {
      final page = await reviewService.fetchReviews(
        widget.product.slug,
        filter: _filter,
      );
      if (!mounted) return;
      setState(() {
        _reviews = page.reviews;
        _nextCursor = page.nextCursor;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    final cursor = _nextCursor;
    if (cursor == null || _loadingMore) return;

    setState(() => _loadingMore = true);
    try {
      final page = await reviewService.fetchReviews(
        widget.product.slug,
        filter: _filter.copyWith(cursor: cursor),
      );
      if (!mounted) return;
      setState(() {
        _reviews = [..._reviews, ...page.reviews];
        _nextCursor = page.nextCursor;
      });
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _toggleHelpful(ProductReview review) async {
    try {
      final count = await reviewService.toggleHelpful(review.id);
      if (!mounted) return;
      setState(() {
        _reviews = _reviews
            .map((item) => item.id == review.id
                ? item.copyWith(helpfulCount: count)
                : item)
            .toList();
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Login',
            onPressed: () => Navigator.pushNamed(context, '/member/login'),
          ),
        ),
      );
    }
  }

  /// Edit review user — dialog dengan field title + content + rating.
  /// PATCH ke /api/reviews/{id}. Server validate ownership.
  Future<void> _editReview(ProductReview review) async {
    final titleCtrl = TextEditingController(text: review.title ?? '');
    final contentCtrl = TextEditingController(text: review.content ?? '');
    int rating = review.rating;
    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Edit Review',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Rating', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Row(
                  children: List.generate(5, (i) {
                    final filled = i < rating;
                    return IconButton(
                      onPressed: () => setLocal(() => rating = i + 1),
                      icon: Icon(
                        filled ? Icons.star_rounded : Icons.star_border_rounded,
                        color: const Color(0xFFFBBF24),
                        size: 28,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    );
                  }),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Judul review',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: contentCtrl,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Ulasan kamu',
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
    if (updated != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await reviewService.updateReview(
        reviewId: review.id,
        title: titleCtrl.text.trim(),
        content: contentCtrl.text.trim(),
        rating: rating,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Review berhasil diupdate.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      // Refresh list dari server supaya display sync.
      _loadInitial();
    } on ApiException catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(error.statusCode == 403
              ? 'Tidak bisa edit review user lain.'
              : 'Gagal: ${error.message}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Gagal: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      titleCtrl.dispose();
      contentCtrl.dispose();
    }
  }

  /// Delete review user — confirmation dialog dulu, lalu DELETE /api/reviews/{id}.
  Future<void> _deleteReview(ProductReview review) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          'Hapus review?',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: const Text(
          'Review yang sudah dihapus tidak bisa dikembalikan.',
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
            ),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await reviewService.deleteReview(review.id);
      if (!mounted) return;
      setState(() {
        _reviews = _reviews.where((r) => r.id != review.id).toList();
      });
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Review dihapus.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(error.statusCode == 403
              ? 'Tidak bisa hapus review user lain.'
              : 'Gagal: ${error.message}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Gagal: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;

    return GlassSurface(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SoftIconTile(
                icon: Icons.star_rounded,
                color: Color(0xFFF59E0B),
                size: 48,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Rating & Review',
                      style: TextStyle(
                        color: Color(0xFF17202A),
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      summary == null
                          ? 'Memuat ulasan pembeli'
                          : '${summary.reviewCount} ulasan pembeli',
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (summary != null) _ReviewSummaryPanel(summary: summary),
          const SizedBox(height: 14),
          if ((summary?.reviewCount ?? 0) > 0) ...[
            _ReviewFilters(
              summary: summary!,
              filter: _filter,
              onChanged: _applyFilter,
            ),
            const SizedBox(height: 14),
          ],
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: _loading
                ? const _ReviewSkeleton()
                : _reviews.isEmpty
                    ? _EmptyReviewState(hasReviews: summary?.reviewCount != 0)
                    : Column(
                        children: [
                          ..._reviews.map(
                            (review) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _ReviewCard(
                                review: review,
                                onHelpful: () => _toggleHelpful(review),
                                onEdit: () => _editReview(review),
                                onDelete: () => _deleteReview(review),
                              ),
                            ),
                          ),
                          if (_nextCursor != null)
                            OutlinedButton.icon(
                              onPressed: _loadingMore ? null : _loadMore,
                              icon: _loadingMore
                                  ? const SizedBox(
                                      height: 16,
                                      width: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.expand_more_rounded),
                              label: Text(
                                _loadingMore
                                    ? 'Memuat...'
                                    : 'Muat Lebih Banyak',
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

class _ReviewSummaryPanel extends StatelessWidget {
  final ReviewSummary summary;

  const _ReviewSummaryPanel({required this.summary});

  @override
  Widget build(BuildContext context) {
    if (summary.reviewCount == 0) {
      return const AppInfoBanner(
        icon: Icons.rate_review_outlined,
        message:
            'Belum ada review. Jadilah pembeli pertama yang memberi ulasan.',
        color: Color(0xFFF59E0B),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.92)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 86,
            child: Column(
              children: [
                Text(
                  summary.avgRating.toStringAsFixed(1),
                  style: const TextStyle(
                    color: Color(0xFFF59E0B),
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 4),
                _Stars(rating: summary.avgRating, size: 16),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              children: [5, 4, 3, 2, 1].map((star) {
                final count = summary.ratingBreakdown[star] ?? 0;
                final percent = summary.reviewCount == 0
                    ? 0.0
                    : count / summary.reviewCount;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 28,
                        child: Text(
                          '$star',
                          style: const TextStyle(
                            color: Color(0xFF92400E),
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: percent,
                            minHeight: 7,
                            backgroundColor: const Color(0xFFEFF4FA),
                            color: const Color(0xFFF59E0B),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 26,
                        child: Text(
                          count.toString(),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewFilters extends StatelessWidget {
  final ReviewSummary summary;
  final ReviewFilter filter;
  final ValueChanged<ReviewFilter> onChanged;

  const _ReviewFilters({
    required this.summary,
    required this.filter,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _FilterChip(
                label: 'Semua',
                active: filter.rating == null && !filter.withImage,
                onTap: () => onChanged(filter.copyWith(
                  clearRating: true,
                  withImage: false,
                )),
              ),
              ...[5, 4, 3, 2, 1].map(
                (star) => _FilterChip(
                  label: '$star bintang',
                  active: filter.rating == star,
                  onTap: () => onChanged(
                    filter.rating == star
                        ? filter.copyWith(clearRating: true)
                        : filter.copyWith(rating: star),
                  ),
                ),
              ),
              _FilterChip(
                label: 'Dengan foto',
                active: filter.withImage,
                onTap: () =>
                    onChanged(filter.copyWith(withImage: !filter.withImage)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _SortButton(
                label: 'Terbaru',
                active: filter.sort == 'newest',
                onTap: () => onChanged(filter.copyWith(sort: 'newest')),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SortButton(
                label: 'Membantu',
                active: filter.sort == 'helpful',
                onTap: () => onChanged(filter.copyWith(sort: 'helpful')),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        selected: active,
        label: Text(label),
        onSelected: (_) => onTap(),
        selectedColor: _brandBlue,
        labelStyle: TextStyle(
          color: active ? Colors.white : const Color(0xFF475569),
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
        backgroundColor: Colors.white.withValues(alpha: 0.80),
        side: BorderSide(
          color: active ? _brandBlue : const Color(0xFFE5E7EB),
        ),
      ),
    );
  }
}

class _SortButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _SortButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor:
            active ? _brandBlue.withValues(alpha: 0.08) : Colors.white,
        side: BorderSide(
          color: active ? _brandBlue : const Color(0xFFE5E7EB),
        ),
      ),
      child: Text(label),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final ProductReview review;
  final VoidCallback onHelpful;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _ReviewCard({
    required this.review,
    required this.onHelpful,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.92)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: _brandBlue.withValues(alpha: 0.10),
                child: Text(
                  review.userName.isEmpty
                      ? 'N'
                      : review.userName.characters.first.toUpperCase(),
                  style: const TextStyle(
                    color: _brandBlue,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review.userName,
                      style: const TextStyle(
                        color: Color(0xFF17202A),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Row(
                      children: [
                        _Stars(rating: review.rating.toDouble(), size: 15),
                        const SizedBox(width: 6),
                        Text(
                          _formatDate(review.createdAt),
                          style: const TextStyle(
                            color: Color(0xFF9CA3AF),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // 3-dot menu cuma muncul kalau review.isMine (backend return
              // flag). Server validate ownership saat update/delete — 403
              // jika spoofed.
              if (review.isMine && (onEdit != null || onDelete != null))
                PopupMenuButton<String>(
                  icon: const Icon(
                    Icons.more_vert_rounded,
                    color: Color(0xFF9CA3AF),
                    size: 18,
                  ),
                  onSelected: (value) {
                    if (value == 'edit' && onEdit != null) onEdit!();
                    if (value == 'delete' && onDelete != null) onDelete!();
                  },
                  itemBuilder: (_) => [
                    if (onEdit != null)
                      const PopupMenuItem<String>(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, size: 18),
                            SizedBox(width: 8),
                            Text('Edit Review'),
                          ],
                        ),
                      ),
                    if (onDelete != null)
                      const PopupMenuItem<String>(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline_rounded,
                                size: 18, color: Color(0xFFEF4444)),
                            SizedBox(width: 8),
                            Text(
                              'Hapus Review',
                              style: TextStyle(color: Color(0xFFEF4444)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
            ],
          ),
          if (review.variantLabel != null) ...[
            const SizedBox(height: 8),
            AppStatusPill(
              label: 'Varian ${review.variantLabel}',
              color: _brandBlue,
              icon: Icons.tune_rounded,
            ),
          ],
          if (review.title != null) ...[
            const SizedBox(height: 10),
            Text(
              review.title!,
              style: const TextStyle(
                color: Color(0xFF17202A),
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
          if (review.content != null) ...[
            const SizedBox(height: 6),
            Text(
              review.content!,
              style: const TextStyle(
                color: Color(0xFF475569),
                fontWeight: FontWeight.w600,
                height: 1.45,
              ),
            ),
          ],
          if (review.images.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 74,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: review.images.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final url = review.images[index];
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.network(
                      url,
                      height: 74,
                      width: 74,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        height: 74,
                        width: 74,
                        color: const Color(0xFFEFF4FA),
                        child: const Icon(Icons.image_not_supported_outlined),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          if (review.reply != null) ...[
            const SizedBox(height: 10),
            AppInfoBanner(
              icon: Icons.storefront_outlined,
              message: 'Balasan Natalo: ${review.reply!.content}',
              color: _brandBlue,
            ),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onHelpful,
              icon: const Icon(Icons.thumb_up_alt_outlined, size: 18),
              label: Text('Membantu (${review.helpfulCount})'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stars extends StatelessWidget {
  final double rating;
  final double size;

  const _Stars({required this.rating, this.size = 16});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final filled = rating >= index + 0.75;
        final half = !filled && rating >= index + 0.25;
        return Icon(
          filled
              ? Icons.star_rounded
              : half
                  ? Icons.star_half_rounded
                  : Icons.star_border_rounded,
          color: const Color(0xFFF59E0B),
          size: size,
        );
      }),
    );
  }
}

class _ReviewSkeleton extends StatelessWidget {
  const _ReviewSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        AppSkeletonBox(height: 110, radius: 20),
        SizedBox(height: 10),
        AppSkeletonBox(height: 96, radius: 20),
      ],
    );
  }
}

class _EmptyReviewState extends StatelessWidget {
  final bool hasReviews;

  const _EmptyReviewState({required this.hasReviews});

  @override
  Widget build(BuildContext context) {
    return AppInfoBanner(
      icon: hasReviews
          ? Icons.filter_alt_off_outlined
          : Icons.rate_review_outlined,
      message: hasReviews
          ? 'Tidak ada review yang cocok dengan filter ini.'
          : 'Belum ada review untuk produk ini.',
      color: hasReviews ? const Color(0xFFF59E0B) : const Color(0xFFF59E0B),
    );
  }
}

String _formatDate(DateTime date) {
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

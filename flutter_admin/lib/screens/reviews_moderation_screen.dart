import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../services/api_client.dart';
import '../theme/admin_theme.dart';
import '../widgets/skeletons.dart';

/// Moderasi Ulasan — list semua review customer dengan tab filter status
/// (Tampil / Disembunyikan / Dihapus). Admin bisa:
///   - Hide / unhide / delete review yang melanggar (caci maki, spam, dll)
///   - Reply ulasan customer dari mobile
///   - Filter by rating 1..5 + search by keyword/produk
class ReviewsModerationScreen extends StatefulWidget {
  const ReviewsModerationScreen({super.key});

  @override
  State<ReviewsModerationScreen> createState() =>
      _ReviewsModerationScreenState();
}

class _ReviewsModerationScreenState extends State<ReviewsModerationScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  int? _ratingFilter;

  static const _tabs = <_StatusTab>[
    _StatusTab(key: 'visible', label: 'Tampil'),
    _StatusTab(key: 'hidden', label: 'Disembunyikan'),
    _StatusTab(key: 'deleted', label: 'Dihapus'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchSubmit(String v) {
    final trimmed = v.trim();
    if (trimmed == _searchQuery) return;
    setState(() => _searchQuery = trimmed);
  }

  void _clearSearch() {
    if (_searchQuery.isEmpty && _searchController.text.isEmpty) return;
    _searchController.clear();
    setState(() => _searchQuery = '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Moderasi Ulasan'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(110),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        textInputAction: TextInputAction.search,
                        onSubmitted: _onSearchSubmit,
                        decoration: InputDecoration(
                          hintText: 'Cari isi ulasan / produk',
                          prefixIcon:
                              const Icon(Icons.search_rounded, size: 20),
                          suffixIcon: _searchQuery.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.close_rounded,
                                      size: 18),
                                  onPressed: _clearSearch,
                                ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _RatingFilterButton(
                      value: _ratingFilter,
                      onChanged: (v) => setState(() => _ratingFilter = v),
                    ),
                  ],
                ),
              ),
              TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                indicatorColor: AdminColors.primary,
                labelColor: AdminColors.primary,
                unselectedLabelColor: AdminColors.textSecondary,
                labelStyle:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                unselectedLabelStyle:
                    const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                tabs: _tabs.map((t) => Tab(text: t.label)).toList(),
              ),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _tabs
            .map((t) => _ReviewList(
                  statusKey: t.key,
                  searchQuery: _searchQuery,
                  ratingFilter: _ratingFilter,
                ))
            .toList(),
      ),
    );
  }
}

class _StatusTab {
  final String key;
  final String label;
  const _StatusTab({required this.key, required this.label});
}

class _RatingFilterButton extends StatelessWidget {
  final int? value;
  final ValueChanged<int?> onChanged;
  const _RatingFilterButton({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int?>(
      initialValue: value,
      onSelected: onChanged,
      tooltip: 'Filter rating',
      icon: Icon(
        Icons.star_rounded,
        color: value == null ? AdminColors.textMuted : Colors.amber,
      ),
      itemBuilder: (_) => [
        const PopupMenuItem(value: null, child: Text('Semua rating')),
        for (var i = 5; i >= 1; i--)
          PopupMenuItem(
            value: i,
            child: Row(
              children: [
                ...List.generate(
                  i,
                  (_) => const Icon(Icons.star_rounded,
                      size: 14, color: Colors.amber),
                ),
                ...List.generate(
                  5 - i,
                  (_) => Icon(Icons.star_rounded,
                      size: 14, color: Colors.grey.shade300),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ReviewList extends StatefulWidget {
  final String statusKey;
  final String searchQuery;
  final int? ratingFilter;
  const _ReviewList({
    required this.statusKey,
    required this.searchQuery,
    this.ratingFilter,
  });

  @override
  State<_ReviewList> createState() => _ReviewListState();
}

class _ReviewListState extends State<_ReviewList>
    with AutomaticKeepAliveClientMixin {
  bool _loading = true;
  String? _error;
  List<_ReviewRow> _reviews = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _ReviewList old) {
    super.didUpdateWidget(old);
    if (old.searchQuery != widget.searchQuery ||
        old.ratingFilter != widget.ratingFilter) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await adminApi.getJson(
        '/api/admin/reviews',
        query: {
          'status': widget.statusKey,
          if (widget.searchQuery.isNotEmpty) 'q': widget.searchQuery,
          if (widget.ratingFilter != null) 'rating': widget.ratingFilter,
        },
      );
      if (data is Map<String, dynamic>) {
        final list = data['reviews'];
        if (list is List) {
          _reviews = list
              .whereType<Map<String, dynamic>>()
              .map(_ReviewRow.fromJson)
              .toList();
        }
      }
    } on AdminApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Tidak bisa load ulasan. Cek koneksi.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setStatus(_ReviewRow row, String newStatus,
      {String? hiddenReason}) async {
    HapticFeedback.lightImpact();
    try {
      await adminApi.patchJson(
        '/api/admin/reviews/${Uri.encodeComponent(row.id)}/status',
        body: {
          'status': newStatus,
          if (hiddenReason != null) 'hiddenReason': hiddenReason,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Status ulasan diupdate ke $newStatus')),
        );
      }
      await _load();
    } on AdminApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal: ${e.message}')),
        );
      }
    }
  }

  Future<void> _reply(_ReviewRow row) async {
    final controller = TextEditingController(text: row.reply?.content ?? '');
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Balas Ulasan',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'Customer akan dapat notifikasi balasan ini.',
                style: TextStyle(
                    fontSize: 12, color: AdminColors.textSecondary),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 5,
                minLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Terima kasih atas ulasannya...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () =>
                      Navigator.pop(ctx, controller.text.trim()),
                  child: Text(row.reply == null ? 'Kirim Balasan' : 'Update'),
                ),
              ),
            ],
          ),
        );
      },
    );
    controller.dispose();
    if (result == null || result.isEmpty) return;

    try {
      await adminApi.postJson(
        '/api/admin/reviews/${Uri.encodeComponent(row.id)}/reply',
        body: {'content': result},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Balasan terkirim')),
        );
      }
      await _load();
    } on AdminApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal balas: ${e.message}')),
        );
      }
    }
  }

  Future<void> _confirmHide(_ReviewRow row) async {
    final reasonController = TextEditingController();
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Sembunyikan ulasan?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Customer masih bisa lihat ulasannya, tapi tidak '
                  'muncul publik di product page.'),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(
                  labelText: 'Alasan (opsional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal'),
            ),
            TextButton(
              style:
                  TextButton.styleFrom(foregroundColor: AdminColors.warning),
              onPressed: () =>
                  Navigator.pop(ctx, reasonController.text.trim()),
              child: const Text('Sembunyikan'),
            ),
          ],
        );
      },
    );
    reasonController.dispose();
    if (result == null) return;
    await _setStatus(row, 'HIDDEN',
        hiddenReason: result.isEmpty ? null : result);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return SkeletonList(count: 6, builder: (_) => const OrderCardSkeleton());
    }
    if (_error != null) {
      return _ErrorBox(message: _error!, onRetry: _load);
    }
    if (_reviews.isEmpty) {
      return _EmptyBox(
        icon: widget.searchQuery.isNotEmpty
            ? Icons.search_off_rounded
            : Icons.reviews_outlined,
        label: widget.searchQuery.isNotEmpty
            ? 'Tidak ada hasil "${widget.searchQuery}"'
            : 'Belum ada ulasan',
      );
    }
    return RefreshIndicator(
      color: AdminColors.primary,
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _reviews.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final r = _reviews[i];
          return _ReviewCard(
            row: r,
            onReply: () => _reply(r),
            onHide: () => _confirmHide(r),
            onUnhide: () => _setStatus(r, 'VISIBLE'),
            onDelete: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Hapus ulasan?'),
                  content: const Text(
                      'Tindakan ini tidak bisa dibatalkan. Customer juga tidak akan lihat lagi.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Batal'),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                          foregroundColor: AdminColors.danger),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Hapus'),
                    ),
                  ],
                ),
              );
              if (ok == true) await _setStatus(r, 'DELETED');
            },
          );
        },
      ),
    );
  }
}

class _ReviewRow {
  final String id;
  final String? productName;
  final String? productImage;
  final String? userName;
  final int rating;
  final String? title;
  final String? content;
  final String status;
  final String? hiddenReason;
  final List<String> images;
  final _ReplyData? reply;
  final DateTime createdAt;

  _ReviewRow({
    required this.id,
    required this.productName,
    required this.productImage,
    required this.userName,
    required this.rating,
    required this.title,
    required this.content,
    required this.status,
    required this.hiddenReason,
    required this.images,
    required this.reply,
    required this.createdAt,
  });

  factory _ReviewRow.fromJson(Map<String, dynamic> j) {
    final product = j['product'];
    final user = j['user'];
    final replyJ = j['reply'];
    final imgs = j['images'];
    return _ReviewRow(
      id: (j['id'] ?? '').toString(),
      productName:
          product is Map ? product['name']?.toString() : null,
      productImage:
          product is Map ? product['imageUrl']?.toString() : null,
      userName: user is Map ? user['name']?.toString() : null,
      rating: (j['rating'] as num?)?.toInt() ?? 0,
      title: j['title']?.toString(),
      content: j['content']?.toString(),
      status: (j['status'] ?? 'VISIBLE').toString(),
      hiddenReason: j['hiddenReason']?.toString(),
      images: imgs is List
          ? imgs
              .whereType<Map>()
              .map((m) => m['imageUrl']?.toString())
              .whereType<String>()
              .toList()
          : [],
      reply: replyJ is Map<String, dynamic>
          ? _ReplyData(
              content: (replyJ['content'] ?? '').toString(),
              updatedAt: DateTime.tryParse(
                      replyJ['updatedAt']?.toString() ?? '') ??
                  DateTime.now(),
            )
          : null,
      createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class _ReplyData {
  final String content;
  final DateTime updatedAt;
  const _ReplyData({required this.content, required this.updatedAt});
}

class _ReviewCard extends StatelessWidget {
  final _ReviewRow row;
  final VoidCallback onReply;
  final VoidCallback onHide;
  final VoidCallback onUnhide;
  final VoidCallback onDelete;

  const _ReviewCard({
    required this.row,
    required this.onReply,
    required this.onHide,
    required this.onUnhide,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AdminColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header — produk + status chip.
          Row(
            children: [
              if (row.productImage != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: CachedNetworkImage(
                    imageUrl: row.productImage!,
                    width: 36,
                    height: 36,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => Container(
                      width: 36,
                      height: 36,
                      color: AdminColors.background,
                    ),
                    errorWidget: (_, _, _) => Container(
                      width: 36,
                      height: 36,
                      color: AdminColors.background,
                    ),
                  ),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  row.productName ?? '-',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AdminColors.textPrimary,
                  ),
                ),
              ),
              _StatusChip(status: row.status),
            ],
          ),
          const SizedBox(height: 8),
          // Rating + user.
          Row(
            children: [
              ...List.generate(
                5,
                (i) => Icon(
                  Icons.star_rounded,
                  size: 14,
                  color: i < row.rating
                      ? Colors.amber
                      : Colors.grey.shade300,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${row.userName ?? '-'} • ${DateFormat('dd MMM yyyy', 'id_ID').format(row.createdAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AdminColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
          if ((row.title ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              row.title!,
              style: const TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w700),
            ),
          ],
          if ((row.content ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              row.content!,
              style: const TextStyle(
                  fontSize: 13, color: AdminColors.textPrimary),
            ),
          ],
          if (row.images.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 60,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: row.images.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (_, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: CachedNetworkImage(
                    imageUrl: row.images[i],
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ],
          if (row.hiddenReason != null && row.hiddenReason!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: AdminColors.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  const Icon(Icons.visibility_off_outlined,
                      size: 14, color: AdminColors.warning),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Alasan disembunyikan: ${row.hiddenReason}',
                      style: const TextStyle(
                          fontSize: 11, color: AdminColors.warning),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (row.reply != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AdminColors.primaryLight,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.storefront_rounded,
                          size: 12, color: AdminColors.primary),
                      const SizedBox(width: 4),
                      const Text(
                        'Balasan toko',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AdminColors.primary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        DateFormat('dd MMM HH:mm', 'id_ID')
                            .format(row.reply!.updatedAt),
                        style: const TextStyle(
                            fontSize: 10, color: AdminColors.textMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    row.reply!.content,
                    style: const TextStyle(
                        fontSize: 12, color: AdminColors.textPrimary),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          // Action buttons.
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.reply_rounded, size: 16),
                  label: Text(
                    row.reply == null ? 'Balas' : 'Edit Balasan',
                    style: const TextStyle(fontSize: 12),
                  ),
                  onPressed: onReply,
                ),
              ),
              const SizedBox(width: 8),
              if (row.status == 'VISIBLE')
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.visibility_off_outlined, size: 16),
                    label: const Text(
                      'Sembunyikan',
                      style: TextStyle(fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AdminColors.warning,
                    ),
                    onPressed: onHide,
                  ),
                )
              else if (row.status == 'HIDDEN')
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.visibility_outlined, size: 16),
                    label: const Text(
                      'Tampilkan',
                      style: TextStyle(fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AdminColors.success,
                    ),
                    onPressed: onUnhide,
                  ),
                ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded,
                    color: AdminColors.danger),
                onPressed: onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (bg, fg, label) = switch (status.toUpperCase()) {
      'VISIBLE' => (
        const Color(0xFFE6F7F4),
        AdminColors.success,
        'Tampil'
      ),
      'HIDDEN' => (
        const Color(0xFFFFF8E1),
        AdminColors.warning,
        'Disembunyikan'
      ),
      'DELETED' => (
        const Color(0xFFFEE2E2),
        AdminColors.danger,
        'Dihapus'
      ),
      _ => (
        const Color(0xFFEEEEEE),
        AdminColors.textSecondary,
        status
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBox({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 48, color: AdminColors.textMuted),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 13, color: AdminColors.textSecondary),
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onRetry, child: const Text('Coba lagi')),
          ],
        ),
      ),
    );
  }
}

class _EmptyBox extends StatelessWidget {
  final IconData icon;
  final String label;
  const _EmptyBox({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AdminColors.textMuted),
            const SizedBox(height: 14),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AdminColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

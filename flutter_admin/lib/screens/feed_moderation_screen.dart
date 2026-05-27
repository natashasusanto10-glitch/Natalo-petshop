import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../services/api_client.dart';
import '../services/notification_counts.dart';
import '../theme/admin_theme.dart';
import '../widgets/skeletons.dart';

/// Moderasi feed post — review queue customer + post admin.
///
/// Filter:
///   - pending  → Customer post belum di-review (PENDING_REVIEW)
///   - all      → semua post non-deleted
///   - hidden   → post yang di-hide admin
///   - rejected → post ditolak admin
///
/// Action per status:
///   PENDING_REVIEW → Approve | Reject (wajib note)
///   ACTIVE         → Hide | Delete
///   HIDDEN         → Unhide | Delete
///   REJECTED       → Restore (re-queue ke PENDING)
class FeedModerationScreen extends StatefulWidget {
  const FeedModerationScreen({super.key});

  @override
  State<FeedModerationScreen> createState() => _FeedModerationScreenState();
}

class _FeedModerationScreenState extends State<FeedModerationScreen> {
  static const _filters = [
    ('pending', 'Pending'),
    ('user_video', 'Komunitas'),
    ('admin_video', 'Admin Post'),
    ('hidden', 'Hidden'),
    ('rejected', 'Rejected'),
    ('all', 'Semua'),
  ];

  String _filter = 'pending';
  final List<Map<String, dynamic>> _items = [];
  String? _cursor;
  bool _loading = false;
  bool _hasMore = true;
  String? _error;
  int _pendingCount = 0;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _load(reset: true);
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 200 &&
          !_loading &&
          _hasMore) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      if (reset) {
        _error = null;
        _cursor = null;
        _hasMore = true;
        _items.clear();
      }
    });
    try {
      final data = await adminApi.getJson(
        '/api/admin/feed/posts',
        query: {
          'filter': _filter,
          if (_cursor != null) 'cursor': _cursor,
        },
      );
      if (data is Map<String, dynamic>) {
        final list = (data['items'] as List?) ?? const [];
        final fetched =
            list.whereType<Map<String, dynamic>>().toList(growable: false);
        final counts = data['counts'];
        setState(() {
          _items.addAll(fetched);
          _cursor = data['nextCursor']?.toString();
          _hasMore = _cursor != null;
          if (counts is Map<String, dynamic> && counts['pending'] is num) {
            _pendingCount = (counts['pending'] as num).toInt();
          }
        });
      }
    } on AdminApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Tidak bisa load feed. Cek koneksi.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _moderate(
    Map<String, dynamic> post,
    String action, {
    String? note,
  }) async {
    final id = post['id']?.toString();
    if (id == null) return;
    try {
      await adminApi.patchJson(
        '/api/admin/feed/posts/${Uri.encodeComponent(id)}',
        body: {
          'action': action,
          if (note != null && note.isNotEmpty) 'note': note,
        },
        timeout: const Duration(seconds: 15),
      );
      if (!mounted) return;
      HapticFeedback.lightImpact();
      NotificationCounts.instance.refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_actionDoneLabel(action)),
          backgroundColor: AdminColors.success,
        ),
      );
      await _load(reset: true);
    } on AdminApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal: ${e.message}')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal moderate. Coba lagi.')),
      );
    }
  }

  Future<void> _delete(Map<String, dynamic> post) async {
    final id = post['id']?.toString();
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus post?'),
        content: const Text(
          'Post akan dihapus permanen (soft-delete). '
          'Bisa di-restore nanti via filter Trash di web.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AdminColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await adminApi.deleteJson(
        '/api/admin/feed/posts/${Uri.encodeComponent(id)}',
        timeout: const Duration(seconds: 15),
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Post dihapus.'),
          backgroundColor: AdminColors.success,
        ),
      );
      await _load(reset: true);
    } on AdminApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal: ${e.message}')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal hapus. Coba lagi.')),
      );
    }
  }

  String _actionDoneLabel(String action) {
    return switch (action) {
      'approve' => 'Post disetujui — sudah tampil di feed.',
      'reject' => 'Post ditolak.',
      'hide' => 'Post di-hide dari feed.',
      'unhide' => 'Post kembali tampil di feed.',
      'restore' => 'Post di-restore ke antrian review.',
      _ => 'Aksi berhasil.',
    };
  }

  Future<void> _openDetail(Map<String, dynamic> post) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FeedDetailSheet(
        post: post,
        onApprove: () async {
          Navigator.of(context).pop();
          await _moderate(post, 'approve');
        },
        onReject: () async {
          Navigator.of(context).pop();
          final note = await _askNote(
            title: 'Tolak Post',
            hint: 'Alasan tolak (wajib, max 500 char) — customer akan lihat ini',
            requireNote: true,
          );
          if (note != null) await _moderate(post, 'reject', note: note);
        },
        onHide: () async {
          Navigator.of(context).pop();
          final note = await _askNote(
            title: 'Hide Post',
            hint: 'Catatan internal (opsional)',
            requireNote: false,
          );
          if (note != null) await _moderate(post, 'hide', note: note);
        },
        onUnhide: () async {
          Navigator.of(context).pop();
          await _moderate(post, 'unhide');
        },
        onRestore: () async {
          Navigator.of(context).pop();
          await _moderate(post, 'restore');
        },
        onDelete: () async {
          Navigator.of(context).pop();
          await _delete(post);
        },
      ),
    );
  }

  Future<String?> _askNote({
    required String title,
    required String hint,
    required bool requireNote,
  }) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          maxLines: 3,
          maxLength: 500,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () {
              final text = controller.text.trim();
              if (requireNote && text.isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Note wajib diisi.')),
                );
                return;
              }
              Navigator.pop(ctx, text);
            },
            child: const Text('Lanjut'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Moderasi Feed'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : () => _load(reset: true),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final f in _filters)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(
                          f.$1 == 'pending' && _pendingCount > 0
                              ? '${f.$2} ($_pendingCount)'
                              : f.$2,
                        ),
                        selected: _filter == f.$1,
                        selectedColor: AdminColors.primaryLight,
                        labelStyle: TextStyle(
                          color: _filter == f.$1
                              ? AdminColors.primary
                              : AdminColors.textSecondary,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                        onSelected: (_) {
                          setState(() => _filter = f.$1);
                          _load(reset: true);
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded,
                  size: 48, color: AdminColors.textMuted),
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AdminColors.textSecondary)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => _load(reset: true),
                child: const Text('Coba lagi'),
              ),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty && _loading) {
      return SkeletonList(
        count: 5,
        builder: (_) => const FeedTileSkeleton(),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _filter == 'pending'
                  ? Icons.inbox_outlined
                  : Icons.feed_outlined,
              size: 48,
              color: AdminColors.textMuted,
            ),
            const SizedBox(height: 12),
            Text(
              _filter == 'pending'
                  ? 'Tidak ada post menunggu review 🎉'
                  : 'Belum ada post di filter ini',
              style: const TextStyle(color: AdminColors.textSecondary),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: AdminColors.primary,
      onRefresh: () => _load(reset: true),
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.all(12),
        itemCount: _items.length + (_hasMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          if (i >= _items.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AdminColors.primary,
                  ),
                ),
              ),
            );
          }
          return _FeedPostTile(
            post: _items[i],
            onTap: () => _openDetail(_items[i]),
          );
        },
      ),
    );
  }
}

const _kindLabels = <String, String>{
  'COMMUNITY': 'Komunitas',
  'VIDEO_ONLY': 'Video',
  'VIDEO_PRODUCT': 'Video + Produk',
  'PROMO': 'Promo',
  'PHOTO_CAROUSEL': 'Foto',
  'PRODUCT_ONLY': 'Produk',
};

const _statusInfo = <String, (Color, String)>{
  'PENDING_REVIEW': (AdminColors.warning, 'PENDING'),
  'ACTIVE': (AdminColors.success, 'ACTIVE'),
  'HIDDEN': (AdminColors.textMuted, 'HIDDEN'),
  'REJECTED': (AdminColors.danger, 'REJECTED'),
};

class _FeedPostTile extends StatelessWidget {
  final Map<String, dynamic> post;
  final VoidCallback onTap;

  const _FeedPostTile({required this.post, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final title = (post['title'] ?? '-').toString();
    final kind = (post['kind'] ?? '').toString();
    final status = (post['status'] ?? '').toString();
    final author = post['author'] is Map<String, dynamic>
        ? post['author'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final authorName = (author['name'] ?? '-').toString();
    final authorRole = (author['role'] ?? '').toString();
    final createdAt = post['createdAt']?.toString();
    final thumb = (post['firstMediaUrl'] ?? post['thumbnailUrl'])?.toString();
    final isVideo =
        post['videoUrl'] != null || kind.startsWith('VIDEO') || kind == 'PROMO';
    final mediaCount = (post['mediaCount'] is num)
        ? (post['mediaCount'] as num).toInt()
        : 0;

    final statusVisual =
        _statusInfo[status] ?? (AdminColors.textMuted, status);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: status == 'PENDING_REVIEW'
                ? AdminColors.warning
                : AdminColors.divider,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail.
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 72,
                height: 90,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (thumb != null && thumb.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: thumb,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => Container(
                          color: AdminColors.background,
                        ),
                        errorWidget: (_, _, _) => Container(
                          color: AdminColors.background,
                          child: const Icon(
                            Icons.broken_image_outlined,
                            color: AdminColors.textMuted,
                            size: 20,
                          ),
                        ),
                      )
                    else
                      Container(
                        color: AdminColors.background,
                        child: const Icon(
                          Icons.feed_outlined,
                          color: AdminColors.textMuted,
                          size: 24,
                        ),
                      ),
                    if (isVideo)
                      const Center(
                        child: Icon(
                          Icons.play_circle_outline_rounded,
                          color: Colors.white,
                          size: 32,
                          shadows: [
                            Shadow(color: Colors.black54, blurRadius: 6),
                          ],
                        ),
                      ),
                    if (mediaCount > 1)
                      Positioned(
                        bottom: 4,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            '×$mediaCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _Tag(
                        text: statusVisual.$2,
                        color: statusVisual.$1,
                      ),
                      const SizedBox(width: 4),
                      _Tag(
                        text: _kindLabels[kind] ?? kind,
                        color: AdminColors.textSecondary,
                        outlined: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AdminColors.textPrimary,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        authorRole == 'ADMIN'
                            ? Icons.verified_user_outlined
                            : Icons.person_outline,
                        size: 12,
                        color: AdminColors.textMuted,
                      ),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Text(
                          authorName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AdminColors.textMuted,
                          ),
                        ),
                      ),
                      Text(
                        _shortDate(createdAt),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AdminColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _shortDate(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    return DateFormat('dd MMM', 'id_ID').format(dt.toLocal());
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  final bool outlined;
  const _Tag({required this.text, required this.color, this.outlined = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: outlined ? Colors.transparent : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(3),
        border: outlined ? Border.all(color: color.withValues(alpha: 0.3)) : null,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _FeedDetailSheet extends StatelessWidget {
  final Map<String, dynamic> post;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onHide;
  final VoidCallback onUnhide;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  const _FeedDetailSheet({
    required this.post,
    required this.onApprove,
    required this.onReject,
    required this.onHide,
    required this.onUnhide,
    required this.onRestore,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final title = (post['title'] ?? '-').toString();
    final desc = post['description']?.toString();
    final status = (post['status'] ?? '').toString();
    final kind = (post['kind'] ?? '').toString();
    final author = post['author'] is Map<String, dynamic>
        ? post['author'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final product = post['product'] is Map<String, dynamic>
        ? post['product'] as Map<String, dynamic>
        : null;
    final moderatedBy = post['moderatedBy'] is Map<String, dynamic>
        ? post['moderatedBy'] as Map<String, dynamic>
        : null;
    final moderationNote = post['moderationNote']?.toString();
    final createdAt = post['createdAt']?.toString();
    final likeCount =
        (post['likeCount'] is num) ? (post['likeCount'] as num).toInt() : 0;
    final commentCount = (post['commentCount'] is num)
        ? (post['commentCount'] as num).toInt()
        : 0;
    final viewCount =
        (post['viewCount'] is num) ? (post['viewCount'] as num).toInt() : 0;
    final thumb = (post['firstMediaUrl'] ?? post['thumbnailUrl'])?.toString();
    final isVideo =
        post['videoUrl'] != null || kind.startsWith('VIDEO') || kind == 'PROMO';

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: AdminColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Thumbnail preview.
                  if (thumb != null && thumb.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: AspectRatio(
                        aspectRatio: 9 / 12,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CachedNetworkImage(
                              imageUrl: thumb,
                              fit: BoxFit.cover,
                              placeholder: (_, _) => Container(
                                color: AdminColors.background,
                              ),
                              errorWidget: (_, _, _) => Container(
                                color: AdminColors.background,
                                child: const Icon(
                                  Icons.broken_image_outlined,
                                  color: AdminColors.textMuted,
                                ),
                              ),
                            ),
                            if (isVideo)
                              Center(
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.55),
                                    borderRadius: BorderRadius.circular(40),
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
                  const SizedBox(height: 12),

                  // Status + kind tags.
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _Tag(
                        text: (_statusInfo[status]?.$2) ?? status,
                        color: _statusInfo[status]?.$1 ?? AdminColors.textMuted,
                      ),
                      _Tag(
                        text: _kindLabels[kind] ?? kind,
                        color: AdminColors.textSecondary,
                        outlined: true,
                      ),
                      if (post['tab'] != null)
                        _Tag(
                          text: post['tab'].toString(),
                          color: AdminColors.natalo,
                          outlined: true,
                        ),
                    ],
                  ),

                  const SizedBox(height: 12),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AdminColors.textPrimary,
                      height: 1.3,
                    ),
                  ),

                  if (desc != null && desc.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      desc,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AdminColors.textPrimary,
                        height: 1.5,
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),
                  _kvRow('Author',
                      '${author['name'] ?? '-'} (${author['role'] ?? '-'})'),
                  _kvRow('Dibuat', _fullDate(createdAt)),
                  if (product != null)
                    _kvRow(
                        'Produk tag', (product['name'] ?? '-').toString()),
                  const SizedBox(height: 12),

                  // Engagement stats.
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AdminColors.background,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        _statCell(Icons.favorite_outline, likeCount, 'Likes'),
                        _statCell(
                            Icons.chat_bubble_outline, commentCount, 'Komentar'),
                        _statCell(
                            Icons.visibility_outlined, viewCount, 'View'),
                      ],
                    ),
                  ),

                  if (moderatedBy != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AdminColors.background,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Moderasi terakhir oleh ${moderatedBy['name'] ?? '-'}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AdminColors.textSecondary,
                            ),
                          ),
                          if (moderationNote != null &&
                              moderationNote.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              moderationNote,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AdminColors.textPrimary,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Action bar di bawah.
          Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              border:
                  Border(top: BorderSide(color: AdminColors.divider)),
            ),
            padding: EdgeInsets.fromLTRB(
              12,
              10,
              12,
              10 + MediaQuery.of(context).padding.bottom,
            ),
            child: _buildActions(status),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(String status) {
    final actions = <Widget>[];
    switch (status) {
      case 'PENDING_REVIEW':
        actions.add(
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.close_rounded, size: 16),
              label: const Text('Tolak'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AdminColors.danger,
                side: const BorderSide(color: AdminColors.danger),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: onReject,
            ),
          ),
        );
        actions.add(const SizedBox(width: 10));
        actions.add(
          Expanded(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.check_rounded, size: 16),
              label: const Text('Setujui'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminColors.success,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: onApprove,
            ),
          ),
        );
        break;
      case 'ACTIVE':
        actions.add(
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.delete_outline_rounded, size: 16),
              label: const Text('Hapus'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AdminColors.danger,
                side: const BorderSide(color: AdminColors.danger),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: onDelete,
            ),
          ),
        );
        actions.add(const SizedBox(width: 10));
        actions.add(
          Expanded(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.visibility_off_outlined, size: 16),
              label: const Text('Hide'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminColors.warning,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: onHide,
            ),
          ),
        );
        break;
      case 'HIDDEN':
        actions.add(
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.delete_outline_rounded, size: 16),
              label: const Text('Hapus'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AdminColors.danger,
                side: const BorderSide(color: AdminColors.danger),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: onDelete,
            ),
          ),
        );
        actions.add(const SizedBox(width: 10));
        actions.add(
          Expanded(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.visibility_outlined, size: 16),
              label: const Text('Unhide'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminColors.success,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: onUnhide,
            ),
          ),
        );
        break;
      case 'REJECTED':
        actions.add(
          Expanded(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.restore_rounded, size: 16),
              label: const Text('Restore ke Pending'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminColors.info,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: onRestore,
            ),
          ),
        );
        break;
      default:
        actions.add(
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.delete_outline_rounded, size: 16),
              label: const Text('Hapus'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AdminColors.danger,
                side: const BorderSide(color: AdminColors.danger),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: onDelete,
            ),
          ),
        );
    }
    return Row(children: actions);
  }

  Widget _kvRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AdminColors.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12.5,
                color: AdminColors.textPrimary,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCell(IconData icon, int value, String label) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 16, color: AdminColors.textSecondary),
          const SizedBox(height: 2),
          Text(
            NumberFormat('#,###', 'id_ID').format(value),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AdminColors.textPrimary,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10.5,
              color: AdminColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  String _fullDate(String? iso) {
    if (iso == null) return '-';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    return DateFormat('dd MMM yyyy, HH:mm', 'id_ID').format(dt.toLocal());
  }
}

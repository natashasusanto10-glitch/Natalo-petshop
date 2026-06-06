import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../services/api_client.dart';
import '../theme/admin_theme.dart';
import '../widgets/skeletons.dart';

/// Feed Reports — review user-submitted reports tentang feed post atau
/// komentar yang dianggap melanggar. Admin bisa resolve (sudah ambil
/// tindakan terpisah via Moderasi Feed) atau dismiss (no violation).
///
/// Tab: Pending (default, FIFO) / Resolved / Dismissed / Semua
///
/// Catatan: Endpoint cuma update STATUS report — hide/delete post/comment
/// dilakukan via FeedModerationScreen.
class FeedReportsScreen extends StatefulWidget {
  const FeedReportsScreen({super.key});

  @override
  State<FeedReportsScreen> createState() => _FeedReportsScreenState();
}

class _FeedReportsScreenState extends State<FeedReportsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const _tabs = <_ReportTab>[
    _ReportTab(key: 'pending', label: 'Pending'),
    _ReportTab(key: 'resolved', label: 'Resolved'),
    _ReportTab(key: 'dismissed', label: 'Dismissed'),
    _ReportTab(key: 'all', label: 'Semua'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Feed Reports'),
        bottom: TabBar(
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
      ),
      body: TabBarView(
        controller: _tabController,
        children: _tabs.map((t) => _ReportList(filterKey: t.key)).toList(),
      ),
    );
  }
}

class _ReportTab {
  final String key;
  final String label;
  const _ReportTab({required this.key, required this.label});
}

class _ReportList extends StatefulWidget {
  final String filterKey;
  const _ReportList({required this.filterKey});

  @override
  State<_ReportList> createState() => _ReportListState();
}

class _ReportListState extends State<_ReportList>
    with AutomaticKeepAliveClientMixin {
  bool _loading = true;
  String? _error;
  List<_ReportRow> _reports = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await adminApi.getJson(
        '/api/admin/feed/reports',
        query: {'status': widget.filterKey},
      );
      if (data is Map<String, dynamic>) {
        final list = data['reports'];
        if (list is List) {
          _reports = list
              .whereType<Map<String, dynamic>>()
              .map(_ReportRow.fromJson)
              .toList();
        }
      }
    } on AdminApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Tidak bisa load reports. Cek koneksi.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _action(_ReportRow row, String action) async {
    HapticFeedback.lightImpact();
    try {
      await adminApi.patchJson(
        '/api/admin/feed/reports/${Uri.encodeComponent(row.id)}',
        body: {'action': action},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(action == 'resolve'
                ? 'Report di-resolve'
                : 'Report di-dismiss'),
          ),
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return SkeletonList(count: 6, builder: (_) => const OrderCardSkeleton());
    }
    if (_error != null) {
      return _ErrorBox(message: _error!, onRetry: _load);
    }
    if (_reports.isEmpty) {
      return const _EmptyBox(
        icon: Icons.flag_outlined,
        label: 'Tidak ada report di tab ini',
      );
    }
    return RefreshIndicator(
      color: AdminColors.primary,
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _reports.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final r = _reports[i];
          return _ReportCard(
            row: r,
            onResolve: () => _action(r, 'resolve'),
            onDismiss: () => _action(r, 'dismiss'),
          );
        },
      ),
    );
  }
}

class _ReportRow {
  final String id;
  final String reason;
  final String? detail;
  final String status;
  final DateTime createdAt;
  final String? reporterName;
  final String? postTitle;
  final String? postThumbnail;
  final String? postAuthorName;
  final String? postStatus;
  final String? commentContent;
  final String? commentAuthorName;
  final bool isComment;

  const _ReportRow({
    required this.id,
    required this.reason,
    required this.detail,
    required this.status,
    required this.createdAt,
    required this.reporterName,
    required this.postTitle,
    required this.postThumbnail,
    required this.postAuthorName,
    required this.postStatus,
    required this.commentContent,
    required this.commentAuthorName,
    required this.isComment,
  });

  factory _ReportRow.fromJson(Map<String, dynamic> j) {
    final reporter = j['reporter'];
    final post = j['post'];
    final comment = j['comment'];
    return _ReportRow(
      id: (j['id'] ?? '').toString(),
      reason: (j['reason'] ?? '-').toString(),
      detail: j['detail']?.toString(),
      status: (j['status'] ?? 'PENDING').toString(),
      createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      reporterName: reporter is Map ? reporter['name']?.toString() : null,
      postTitle: post is Map ? post['title']?.toString() : null,
      postThumbnail: post is Map ? post['thumbnailUrl']?.toString() : null,
      postAuthorName: post is Map && post['author'] is Map
          ? (post['author'] as Map)['name']?.toString()
          : null,
      postStatus: post is Map ? post['status']?.toString() : null,
      commentContent: comment is Map ? comment['content']?.toString() : null,
      commentAuthorName: comment is Map && comment['author'] is Map
          ? (comment['author'] as Map)['name']?.toString()
          : null,
      isComment: comment is Map,
    );
  }
}

class _ReportCard extends StatelessWidget {
  final _ReportRow row;
  final VoidCallback onResolve;
  final VoidCallback onDismiss;
  const _ReportCard({
    required this.row,
    required this.onResolve,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final isPending = row.status == 'PENDING';
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
          // Header: reason chip + date.
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AdminColors.danger.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.flag_rounded,
                        size: 12, color: AdminColors.danger),
                    const SizedBox(width: 4),
                    Text(
                      row.reason,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: AdminColors.danger,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  DateFormat('dd MMM yyyy HH:mm', 'id_ID')
                      .format(row.createdAt),
                  style: const TextStyle(
                      fontSize: 11, color: AdminColors.textMuted),
                ),
              ),
              _StatusChip(status: row.status),
            ],
          ),
          if (row.reporterName != null) ...[
            const SizedBox(height: 6),
            Text(
              'Dilaporkan oleh: ${row.reporterName}',
              style: const TextStyle(
                  fontSize: 11.5, color: AdminColors.textSecondary),
            ),
          ],
          if (row.detail != null && row.detail!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Detail: ${row.detail}',
              style: const TextStyle(
                  fontSize: 12, color: AdminColors.textPrimary),
            ),
          ],
          const SizedBox(height: 10),
          // Content preview — post atau comment.
          if (row.isComment)
            _CommentPreview(
              content: row.commentContent ?? '-',
              authorName: row.commentAuthorName ?? '-',
            )
          else if (row.postTitle != null || row.postThumbnail != null)
            _PostPreview(
              title: row.postTitle ?? '-',
              thumbnail: row.postThumbnail,
              authorName: row.postAuthorName ?? '-',
              postStatus: row.postStatus,
            )
          else
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AdminColors.background,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Konten sudah dihapus',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: AdminColors.textMuted,
                ),
              ),
            ),
          if (isPending) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: const Text('Dismiss', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AdminColors.textSecondary,
                    ),
                    onPressed: onDismiss,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: const Text('Resolve', style: TextStyle(fontSize: 12)),
                    onPressed: onResolve,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PostPreview extends StatelessWidget {
  final String title;
  final String? thumbnail;
  final String authorName;
  final String? postStatus;

  const _PostPreview({
    required this.title,
    required this.thumbnail,
    required this.authorName,
    this.postStatus,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AdminColors.background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          if (thumbnail != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: CachedNetworkImage(
                imageUrl: thumbnail!,
                width: 50,
                height: 50,
                fit: BoxFit.cover,
                placeholder: (_, _) => Container(
                  width: 50,
                  height: 50,
                  color: AdminColors.divider,
                ),
              ),
            )
          else
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: AdminColors.divider,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(Icons.feed_outlined,
                  color: AdminColors.textMuted),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AdminColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Post oleh: $authorName${postStatus != null ? ' • ${postStatus!.toLowerCase()}' : ''}',
                  style: const TextStyle(
                      fontSize: 11, color: AdminColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentPreview extends StatelessWidget {
  final String content;
  final String authorName;
  const _CommentPreview(
      {required this.content, required this.authorName});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AdminColors.background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.comment_outlined,
                  size: 14, color: AdminColors.textMuted),
              const SizedBox(width: 6),
              Text(
                'Komentar oleh: $authorName',
                style: const TextStyle(
                    fontSize: 11, color: AdminColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            content,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 12.5, color: AdminColors.textPrimary),
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
      'PENDING' => (
        const Color(0xFFFFF8E1),
        AdminColors.warning,
        'Pending'
      ),
      'RESOLVED' => (
        const Color(0xFFE6F7F4),
        AdminColors.success,
        'Resolved'
      ),
      'DISMISSED' => (
        const Color(0xFFEEEEEE),
        AdminColors.textSecondary,
        'Dismissed'
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

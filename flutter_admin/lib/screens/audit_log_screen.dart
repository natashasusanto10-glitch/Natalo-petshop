import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../services/api_client.dart';
import '../theme/admin_theme.dart';

/// Read-only feed audit log admin actions.
/// Pagination via cursor — load 30 per fetch, infinite scroll.
class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  final _scrollController = ScrollController();
  final List<Map<String, dynamic>> _items = [];
  String? _cursor;
  bool _loading = false;
  bool _hasMore = true;
  String? _error;

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
        '/api/admin/audit-log',
        query: {
          'limit': 30,
          if (_cursor != null) 'cursor': _cursor,
        },
      );
      if (data is Map<String, dynamic>) {
        final list = (data['items'] as List?) ?? const [];
        final fetched =
            list.whereType<Map<String, dynamic>>().toList(growable: false);
        setState(() {
          _items.addAll(fetched);
          _cursor = data['nextCursor']?.toString();
          _hasMore = _cursor != null;
        });
      }
    } on AdminApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Tidak bisa load audit log. Cek koneksi.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audit Log'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : () => _load(reset: true),
          ),
        ],
      ),
      body: _buildBody(),
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
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AdminColors.textSecondary),
              ),
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
      return const Center(
        child: CircularProgressIndicator(color: AdminColors.primary),
      );
    }
    if (_items.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.fact_check_outlined,
                size: 48, color: AdminColors.textMuted),
            SizedBox(height: 12),
            Text('Belum ada log',
                style: TextStyle(color: AdminColors.textSecondary)),
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
        separatorBuilder: (_, __) => const SizedBox(height: 8),
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
          return _AuditLogTile(item: _items[i]);
        },
      ),
    );
  }
}

/// Color + icon mapping per action category — quick visual scan supaya
/// admin tahu jenis aksi tanpa baca code lengkap.
class _ActionVisual {
  final IconData icon;
  final Color color;
  final String label;
  const _ActionVisual(this.icon, this.color, this.label);
}

const _actionVisuals = <String, _ActionVisual>{
  'ORDER_MARK_PAID': _ActionVisual(
      Icons.payments_outlined, AdminColors.success, 'Tandai Lunas'),
  'ORDER_MARK_PROCESSING': _ActionVisual(
      Icons.work_history_outlined, AdminColors.info, 'Diproses'),
  'ORDER_MARK_SHIPPED':
      _ActionVisual(Icons.local_shipping_outlined, AdminColors.info, 'Kirim'),
  'ORDER_MARK_DELIVERED':
      _ActionVisual(Icons.check_circle_outline, AdminColors.success, 'Selesai'),
  'ORDER_CANCELLED':
      _ActionVisual(Icons.cancel_outlined, AdminColors.danger, 'Cancel'),
  'ORDER_CANCEL_REQUEST_APPROVED': _ActionVisual(
      Icons.task_alt_outlined, AdminColors.success, 'Cancel Approved'),
  'ORDER_CANCEL_REQUEST_REJECTED': _ActionVisual(
      Icons.block_outlined, AdminColors.danger, 'Cancel Rejected'),
  'REFUND_ISSUED':
      _ActionVisual(Icons.replay_outlined, AdminColors.danger, 'Refund'),
  'REFUND_ITEM_OOS': _ActionVisual(
      Icons.report_off_outlined, AdminColors.warning, 'Item Kosong'),
  'VOUCHER_CREATED':
      _ActionVisual(Icons.local_offer_outlined, AdminColors.primary, 'Voucher+'),
  'VOUCHER_UPDATED':
      _ActionVisual(Icons.edit_outlined, AdminColors.primary, 'Voucher Edit'),
  'VOUCHER_DELETED': _ActionVisual(
      Icons.delete_outline_rounded, AdminColors.danger, 'Voucher Hapus'),
  'USER_ROLE_CHANGED':
      _ActionVisual(Icons.shield_outlined, AdminColors.warning, 'Role'),
  'USER_BIRTHDATE_OVERRIDDEN':
      _ActionVisual(Icons.cake_outlined, AdminColors.warning, 'Override DOB'),
  'FEED_POST_APPROVED':
      _ActionVisual(Icons.thumb_up_outlined, AdminColors.success, 'Feed +'),
  'FEED_POST_REJECTED':
      _ActionVisual(Icons.thumb_down_outlined, AdminColors.danger, 'Feed -'),
  'FEED_POST_HIDDEN': _ActionVisual(
      Icons.visibility_off_outlined, AdminColors.warning, 'Feed Hide'),
  'PUSH_BROADCAST':
      _ActionVisual(Icons.campaign_outlined, AdminColors.natalo, 'Broadcast'),
};

_ActionVisual _visualFor(String action) {
  return _actionVisuals[action] ??
      _ActionVisual(Icons.history_outlined, AdminColors.textSecondary, action);
}

class _AuditLogTile extends StatelessWidget {
  final Map<String, dynamic> item;
  const _AuditLogTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final action = (item['action'] ?? '').toString();
    final summary = (item['summary'] ?? '').toString();
    final actor = item['actor'] is Map<String, dynamic>
        ? (item['actor'] as Map<String, dynamic>)
        : const <String, dynamic>{};
    final actorName = (actor['name'] ?? actor['email'] ?? 'Admin').toString();
    final createdAt = item['createdAt']?.toString();
    final targetType = (item['targetType'] ?? '').toString();
    final visual = _visualFor(action);

    return InkWell(
      onTap: () => _showDetail(context),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AdminColors.divider),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: visual.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(visual.icon, color: visual.color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: visual.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          visual.label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: visual.color,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (targetType.isNotEmpty)
                        Text(
                          targetType,
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: AdminColors.textMuted,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AdminColors.textPrimary,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.person_outline,
                          size: 11, color: AdminColors.textMuted),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Text(
                          actorName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AdminColors.textMuted,
                          ),
                        ),
                      ),
                      Text(
                        _formatDate(createdAt),
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

  void _showDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AuditLogDetailSheet(item: item),
    );
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    return DateFormat('dd MMM HH:mm', 'id_ID').format(dt.toLocal());
  }
}

class _AuditLogDetailSheet extends StatelessWidget {
  final Map<String, dynamic> item;
  const _AuditLogDetailSheet({required this.item});

  @override
  Widget build(BuildContext context) {
    final action = (item['action'] ?? '').toString();
    final summary = (item['summary'] ?? '').toString();
    final targetType = (item['targetType'] ?? '').toString();
    final targetId = (item['targetId'] ?? '').toString();
    final metadata = item['metadata'];
    final actor = item['actor'] is Map<String, dynamic>
        ? (item['actor'] as Map<String, dynamic>)
        : const <String, dynamic>{};
    final actorName = (actor['name'] ?? actor['email'] ?? 'Admin').toString();
    final createdAt = item['createdAt']?.toString() ?? '';

    final metadataJson = metadata == null
        ? null
        : const JsonEncoder.withIndent('  ').convert(metadata);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: AdminColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              action,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AdminColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              summary,
              style: const TextStyle(
                fontSize: 13.5,
                color: AdminColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            _DetailRow(label: 'Aktor', value: actorName),
            _DetailRow(label: 'Target', value: '$targetType / $targetId'),
            _DetailRow(label: 'Waktu', value: _formatFullDate(createdAt)),
            if (metadataJson != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text(
                    'Metadata',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AdminColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    icon: const Icon(Icons.copy_outlined, size: 14),
                    label: const Text('Copy JSON',
                        style: TextStyle(fontSize: 12)),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: metadataJson));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Metadata di-copy.'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AdminColors.background,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  metadataJson,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontFamily: 'monospace',
                    color: AdminColors.textPrimary,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatFullDate(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    return DateFormat('dd MMM yyyy, HH:mm:ss', 'id_ID').format(dt.toLocal());
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
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
}

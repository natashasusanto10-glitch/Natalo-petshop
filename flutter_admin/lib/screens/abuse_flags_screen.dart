import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api_client.dart';
import '../theme/admin_theme.dart';

/// Review queue untuk voucher / akun abuse flags. Admin tap → bottom
/// sheet detail dengan tombol Review (clean), Dismiss (ignore), atau
/// Block (set user role=BLOCKED, invalidate token).
class AbuseFlagsScreen extends StatefulWidget {
  const AbuseFlagsScreen({super.key});

  @override
  State<AbuseFlagsScreen> createState() => _AbuseFlagsScreenState();
}

class _AbuseFlagsScreenState extends State<AbuseFlagsScreen> {
  String _statusFilter = 'OPEN';
  bool _loading = false;
  String? _error;
  String? _cursor;
  bool _hasMore = true;
  final List<Map<String, dynamic>> _items = [];
  Map<String, int> _counts = const {};
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
        '/api/admin/abuse-flags',
        query: {
          'status': _statusFilter,
          'limit': 30,
          if (_cursor != null) 'cursor': _cursor,
        },
      );
      if (data is Map<String, dynamic>) {
        final list = (data['items'] as List?) ?? const [];
        final fetched =
            list.whereType<Map<String, dynamic>>().toList(growable: false);
        final counts = data['counts'] is Map<String, dynamic>
            ? Map<String, int>.fromEntries(
                (data['counts'] as Map<String, dynamic>).entries.map(
                      (e) => MapEntry(
                        e.key,
                        e.value is num ? (e.value as num).toInt() : 0,
                      ),
                    ),
              )
            : const <String, int>{};
        setState(() {
          _items.addAll(fetched);
          _cursor = data['nextCursor']?.toString();
          _hasMore = _cursor != null;
          _counts = counts;
        });
      }
    } on AdminApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Tidak bisa load abuse flags. Cek koneksi.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _review(Map<String, dynamic> flag) async {
    final result = await showModalBottomSheet<_ReviewResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AbuseFlagDetailSheet(flag: flag),
    );
    if (result == null) return;

    final id = flag['id']?.toString();
    if (id == null) return;
    try {
      await adminApi.patchJson(
        '/api/admin/abuse-flags/${Uri.encodeComponent(id)}',
        body: {
          'action': result.action,
          if (result.adminNote != null && result.adminNote!.isNotEmpty)
            'adminNote': result.adminNote,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_actionDoneLabel(result.action)),
          backgroundColor: AdminColors.success,
          behavior: SnackBarBehavior.floating,
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
        const SnackBar(content: Text('Gagal review. Coba lagi.')),
      );
    }
  }

  String _actionDoneLabel(String action) {
    return switch (action) {
      'REVIEWED' => 'Flag ditandai sudah di-review.',
      'DISMISSED' => 'Flag di-dismiss.',
      'BLOCKED' => 'User di-block — sesi langsung ter-invalidate.',
      _ => 'Status flag ter-update.',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Abuse Flags')),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final f in const [
                    ('OPEN', 'Open'),
                    ('REVIEWED', 'Reviewed'),
                    ('DISMISSED', 'Dismissed'),
                    ('BLOCKED', 'Blocked'),
                    ('ALL', 'Semua'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(
                          _counts.containsKey(f.$1) && f.$1 != 'ALL'
                              ? '${f.$2} (${_counts[f.$1] ?? 0})'
                              : f.$2,
                        ),
                        selected: _statusFilter == f.$1,
                        selectedColor: AdminColors.primaryLight,
                        labelStyle: TextStyle(
                          color: _statusFilter == f.$1
                              ? AdminColors.primary
                              : AdminColors.textSecondary,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                        onSelected: (_) {
                          setState(() => _statusFilter = f.$1);
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
      return const Center(
        child: CircularProgressIndicator(color: AdminColors.primary),
      );
    }
    if (_items.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shield_outlined,
                size: 48, color: AdminColors.textMuted),
            SizedBox(height: 12),
            Text('Tidak ada flag di sini',
                style: TextStyle(color: AdminColors.textSecondary)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      color: AdminColors.primary,
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
          return _FlagTile(
            flag: _items[i],
            onTap: () => _review(_items[i]),
          );
        },
      ),
    );
  }
}

const _ruleLabels = <String, String>{
  'BURST_VOUCHER_CLAIM': 'Burst voucher claim',
  'GMAIL_ALIAS_DUPLICATE': 'Gmail alias multi-akun',
  'DUPLICATE_SHIPPING_ADDRESS': 'Alamat duplikat',
  'NEW_ACCOUNT_INSTANT_CLAIM': 'Akun baru claim instan',
};

class _FlagTile extends StatelessWidget {
  final Map<String, dynamic> flag;
  final VoidCallback onTap;

  const _FlagTile({required this.flag, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final rule = (flag['ruleCode'] ?? '').toString();
    final severity = (flag['severity'] ?? 'MEDIUM').toString();
    final status = (flag['status'] ?? 'OPEN').toString();
    final user = flag['user'] is Map<String, dynamic>
        ? flag['user'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final userName = (user['name'] ?? user['email'] ?? 'User').toString();
    final userEmail = user['email']?.toString();
    final createdAt = flag['createdAt']?.toString();

    final severityColor = switch (severity) {
      'HIGH' => AdminColors.danger,
      'MEDIUM' => AdminColors.warning,
      _ => AdminColors.textMuted,
    };
    final statusColor = switch (status) {
      'OPEN' => AdminColors.warning,
      'REVIEWED' => AdminColors.success,
      'BLOCKED' => AdminColors.danger,
      _ => AdminColors.textMuted,
    };

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: status == 'OPEN' && severity == 'HIGH'
                ? AdminColors.danger
                : AdminColors.divider,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: severityColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    severity,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: severityColor,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: statusColor,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  _shortDate(createdAt),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AdminColors.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _ruleLabels[rule] ?? rule,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AdminColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              userName,
              style: const TextStyle(
                fontSize: 12.5,
                color: AdminColors.textSecondary,
              ),
            ),
            if (userEmail != null && userEmail != userName)
              Text(
                userEmail,
                style: const TextStyle(
                  fontSize: 11,
                  color: AdminColors.textMuted,
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

class _ReviewResult {
  final String action;
  final String? adminNote;
  const _ReviewResult({required this.action, this.adminNote});
}

class _AbuseFlagDetailSheet extends StatefulWidget {
  final Map<String, dynamic> flag;
  const _AbuseFlagDetailSheet({required this.flag});

  @override
  State<_AbuseFlagDetailSheet> createState() => _AbuseFlagDetailSheetState();
}

class _AbuseFlagDetailSheetState extends State<_AbuseFlagDetailSheet> {
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    final f = widget.flag;
    final rule = (f['ruleCode'] ?? '').toString();
    final severity = (f['severity'] ?? 'MEDIUM').toString();
    final status = (f['status'] ?? 'OPEN').toString();
    final user = f['user'] is Map<String, dynamic>
        ? f['user'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final details = f['details'];
    final detailsJson = details == null
        ? null
        : const JsonEncoder.withIndent('  ').convert(details);
    final canAct = status == 'OPEN';

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                _ruleLabels[rule] ?? rule,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AdminColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Severity: $severity  •  Status: $status',
                style: const TextStyle(
                  fontSize: 12,
                  color: AdminColors.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AdminColors.background,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'User',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AdminColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      (user['name'] ?? '-').toString(),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AdminColors.textPrimary,
                      ),
                    ),
                    if (user['email'] != null)
                      Text(
                        user['email'].toString(),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AdminColors.textSecondary,
                        ),
                      ),
                    if (user['phoneNumber'] != null)
                      Text(
                        user['phoneNumber'].toString(),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AdminColors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              if (detailsJson != null) ...[
                const SizedBox(height: 12),
                const Text(
                  'Detail Pattern',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AdminColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AdminColors.background,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    detailsJson,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontFamily: 'monospace',
                      color: AdminColors.textPrimary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
              if (canAct) ...[
                const SizedBox(height: 14),
                TextField(
                  controller: _noteController,
                  maxLines: 2,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    labelText: 'Catatan admin (opsional)',
                    hintText: 'Dokumentasi reasoning untuk audit log',
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(
                          _ReviewResult(
                            action: 'DISMISSED',
                            adminNote: _noteController.text.trim(),
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AdminColors.textSecondary,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('Dismiss'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(
                          _ReviewResult(
                            action: 'REVIEWED',
                            adminNote: _noteController.text.trim(),
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AdminColors.success,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('OK'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Block user ini?'),
                        content: const Text(
                          'User akan di-block (role=BLOCKED) dan semua '
                          'sesi login langsung invalid. Tindakan ini '
                          'akan ter-log di audit dengan namamu.\n\nLanjutkan?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Batal'),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                                foregroundColor: AdminColors.danger),
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Block'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true && context.mounted) {
                      Navigator.of(context).pop(_ReviewResult(
                        action: 'BLOCKED',
                        adminNote: _noteController.text.trim(),
                      ));
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AdminColors.danger,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.block_rounded, size: 18),
                  label: const Text('Block User'),
                ),
              ] else
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'Flag ini sudah di-$status — tidak bisa diubah lagi.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AdminColors.textMuted,
                      fontStyle: FontStyle.italic,
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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../services/api_client.dart';
import '../theme/admin_theme.dart';

class VouchersScreen extends StatefulWidget {
  const VouchersScreen({super.key});

  @override
  State<VouchersScreen> createState() => _VouchersScreenState();
}

class _VouchersScreenState extends State<VouchersScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _vouchers = [];
  String _statusFilter = 'active';

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
        '/api/admin/vouchers',
        query: {'status': _statusFilter, 'limit': 100},
      );
      if (data is Map && data['vouchers'] is List) {
        _vouchers = (data['vouchers'] as List)
            .whereType<Map<String, dynamic>>()
            .toList();
      }
    } on AdminApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Tidak bisa load voucher. Cek koneksi.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const _CreateVoucherScreen()),
    );
    if (created == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Voucher'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Tambah voucher',
            onPressed: _openCreate,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                for (final filter in const ['active', 'expired', 'all'])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(filter == 'active'
                          ? 'Aktif'
                          : filter == 'expired'
                              ? 'Berakhir'
                              : 'Semua'),
                      selected: _statusFilter == filter,
                      selectedColor: AdminColors.primaryLight,
                      labelStyle: TextStyle(
                        color: _statusFilter == filter
                            ? AdminColors.primary
                            : AdminColors.textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                      onSelected: (_) {
                        setState(() => _statusFilter = filter);
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AdminColors.primary),
      );
    }
    if (_error != null) {
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
                  onPressed: _load, child: const Text('Coba lagi')),
            ],
          ),
        ),
      );
    }
    if (_vouchers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.local_offer_outlined,
                  size: 48, color: AdminColors.textMuted),
              const SizedBox(height: 12),
              const Text(
                'Belum ada voucher',
                style: TextStyle(color: AdminColors.textSecondary),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _openCreate,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Buat voucher pertama'),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: AdminColors.primary,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _vouchers.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _VoucherCard(voucher: _vouchers[i]),
      ),
    );
  }
}

class _VoucherCard extends StatelessWidget {
  final Map<String, dynamic> voucher;
  const _VoucherCard({required this.voucher});

  @override
  Widget build(BuildContext context) {
    final code = (voucher['code'] ?? '-').toString();
    final name = (voucher['name'] ?? '').toString();
    final discountPercent = voucher['discountPercent'];
    final discountAmount = voucher['discountAmount'];
    final minOrder = (voucher['minimumOrder'] ?? 0) is num
        ? (voucher['minimumOrder'] as num).toInt()
        : 0;
    final maxUsage = voucher['maxUsage'];
    final usedCount = (voucher['usedCount'] ?? 0) is num
        ? (voucher['usedCount'] as num).toInt()
        : 0;
    final isActive = voucher['isActive'] == true;
    final expiresAt = voucher['expiresAt']?.toString();

    final discountStr = discountPercent is num && discountPercent > 0
        ? '${discountPercent.toInt()}%'
        : discountAmount is num && discountAmount > 0
            ? formatRupiah(discountAmount.toInt())
            : '-';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isActive ? AdminColors.primary : AdminColors.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AdminColors.primaryLight,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      code,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AdminColors.primary,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: code));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Kode $code di-copy.'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      child: const Icon(
                        Icons.copy_outlined,
                        size: 13,
                        color: AdminColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (!isActive)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AdminColors.divider,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Text(
                    'Tidak aktif',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AdminColors.textMuted,
                    ),
                  ),
                ),
            ],
          ),
          if (name.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              name,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AdminColors.textPrimary,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.discount_outlined,
                  size: 14, color: AdminColors.success),
              const SizedBox(width: 4),
              Text(
                'Diskon $discountStr',
                style: const TextStyle(
                  fontSize: 12,
                  color: AdminColors.textSecondary,
                ),
              ),
              if (minOrder > 0) ...[
                const SizedBox(width: 12),
                const Icon(Icons.shopping_cart_outlined,
                    size: 14, color: AdminColors.textMuted),
                const SizedBox(width: 4),
                Text(
                  'Min ${formatRupiah(minOrder)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AdminColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              if (maxUsage is num && maxUsage > 0) ...[
                const Icon(Icons.tag_outlined,
                    size: 14, color: AdminColors.textMuted),
                const SizedBox(width: 4),
                Text(
                  '$usedCount / ${maxUsage.toInt()} kuota',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AdminColors.textSecondary,
                  ),
                ),
              ] else ...[
                const Icon(Icons.tag_outlined,
                    size: 14, color: AdminColors.textMuted),
                const SizedBox(width: 4),
                Text(
                  '$usedCount kali dipakai',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AdminColors.textSecondary,
                  ),
                ),
              ],
              const SizedBox(width: 12),
              if (expiresAt != null) ...[
                const Icon(Icons.event_outlined,
                    size: 14, color: AdminColors.textMuted),
                const SizedBox(width: 4),
                Text(
                  _formatDate(expiresAt),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AdminColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    return DateFormat('dd MMM yyyy', 'id_ID').format(dt.toLocal());
  }
}

class _CreateVoucherScreen extends StatefulWidget {
  const _CreateVoucherScreen();

  @override
  State<_CreateVoucherScreen> createState() => _CreateVoucherScreenState();
}

class _CreateVoucherScreenState extends State<_CreateVoucherScreen> {
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _percentController = TextEditingController();
  final _amountController = TextEditingController();
  final _minOrderController = TextEditingController(text: '0');
  final _maxUsageController = TextEditingController();
  DateTime? _expiresAt;
  String _discountMode = 'percent'; // 'percent' atau 'amount'
  bool _saving = false;

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _descController.dispose();
    _percentController.dispose();
    _amountController.dispose();
    _minOrderController.dispose();
    _maxUsageController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) return _err('Kode wajib diisi');

    final percent =
        int.tryParse(_percentController.text.trim()) ?? 0;
    final amount = int.tryParse(_amountController.text.trim()) ?? 0;

    if (_discountMode == 'percent' && percent <= 0) {
      return _err('Diskon % harus > 0');
    }
    if (_discountMode == 'amount' && amount <= 0) {
      return _err('Diskon Rp harus > 0');
    }

    setState(() => _saving = true);
    try {
      await adminApi.postJson(
        '/api/admin/vouchers',
        body: {
          'code': code,
          if (_nameController.text.trim().isNotEmpty)
            'name': _nameController.text.trim(),
          if (_descController.text.trim().isNotEmpty)
            'description': _descController.text.trim(),
          if (_discountMode == 'percent') 'discountPercent': percent,
          if (_discountMode == 'amount') 'discountAmount': amount,
          'minimumOrder':
              int.tryParse(_minOrderController.text.trim()) ?? 0,
          if (_maxUsageController.text.trim().isNotEmpty)
            'maxUsage': int.tryParse(_maxUsageController.text.trim()),
          if (_expiresAt != null)
            'expiresAt': _expiresAt!.toIso8601String(),
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Voucher dibuat ✓'),
          backgroundColor: AdminColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop(true);
    } on AdminApiException catch (e) {
      _err('Gagal: ${e.message}');
    } catch (_) {
      _err('Gagal simpan voucher. Coba lagi.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _err(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  Future<void> _pickExpiresAt() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiresAt ?? now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 2)),
    );
    if (picked != null) {
      setState(() => _expiresAt = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Buat Voucher'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(
              'Simpan',
              style: TextStyle(
                color: _saving ? AdminColors.textMuted : AdminColors.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _L('Kode Voucher *'),
                TextField(
                  controller: _codeController,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'[A-Z0-9_-]')),
                  ],
                  decoration: const InputDecoration(
                    hintText: 'PROMO2026',
                  ),
                ),
                const SizedBox(height: 14),
                const _L('Nama Voucher (opsional)'),
                TextField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    hintText: 'Diskon Akhir Pekan',
                  ),
                ),
                const SizedBox(height: 14),
                const _L('Deskripsi (opsional)'),
                TextField(
                  controller: _descController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: 'Diskon untuk semua produk pakan kucing',
                  ),
                ),
                const SizedBox(height: 14),
                const _L('Jenis Diskon *'),
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Persen (%)'),
                        value: 'percent',
                        groupValue: _discountMode,
                        activeColor: AdminColors.primary,
                        onChanged: (v) =>
                            setState(() => _discountMode = v ?? 'percent'),
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Nominal (Rp)'),
                        value: 'amount',
                        groupValue: _discountMode,
                        activeColor: AdminColors.primary,
                        onChanged: (v) =>
                            setState(() => _discountMode = v ?? 'amount'),
                      ),
                    ),
                  ],
                ),
                if (_discountMode == 'percent')
                  TextField(
                    controller: _percentController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: const InputDecoration(
                      hintText: '10',
                      suffixText: '%',
                    ),
                  )
                else
                  TextField(
                    controller: _amountController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: const InputDecoration(
                      hintText: '50000',
                      prefixText: 'Rp ',
                    ),
                  ),
                const SizedBox(height: 14),
                const _L('Minimum Order (Rp)'),
                TextField(
                  controller: _minOrderController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: const InputDecoration(
                    hintText: '0',
                    prefixText: 'Rp ',
                  ),
                ),
                const SizedBox(height: 14),
                const _L('Kuota Pemakaian (opsional)'),
                TextField(
                  controller: _maxUsageController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: const InputDecoration(
                    hintText: 'Kosongkan = tidak terbatas',
                  ),
                ),
                const SizedBox(height: 14),
                const _L('Tanggal Berakhir (opsional)'),
                InkWell(
                  onTap: _pickExpiresAt,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: AdminColors.background,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AdminColors.divider),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.event_outlined,
                            color: AdminColors.textMuted, size: 20),
                        const SizedBox(width: 10),
                        Text(
                          _expiresAt != null
                              ? DateFormat('dd MMM yyyy', 'id_ID')
                                  .format(_expiresAt!)
                              : 'Tap untuk pilih tanggal',
                          style: TextStyle(
                            fontSize: 14,
                            color: _expiresAt != null
                                ? AdminColors.textPrimary
                                : AdminColors.textMuted,
                          ),
                        ),
                        if (_expiresAt != null) ...[
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () =>
                                setState(() => _expiresAt = null),
                          ),
                        ],
                      ],
                    ),
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

class _L extends StatelessWidget {
  final String text;
  const _L(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AdminColors.textSecondary,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_client.dart';
import '../theme/admin_theme.dart';

/// Detail screen untuk satu order — view + actions.
///
/// Actions yang admin paling sering pakai (Shopee Seller pattern):
/// - **Tandai Diproses** (PAID → PROCESSING) untuk acknowledge sudah lihat
/// - **Input Resi & Kirim** (PROCESSING → SHIPPED) dengan input nomor resi
/// - **Tandai Selesai** (SHIPPED → DELIVERED) manual confirm sampai
/// - **Refund / Cancel** (any → CANCELLED/REFUNDED)
class OrderDetailScreen extends StatefulWidget {
  final String orderNumber;
  const OrderDetailScreen({super.key, required this.orderNumber});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _order;
  bool _actionInProgress = false;

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
        '/api/admin/orders/${Uri.encodeComponent(widget.orderNumber)}',
      );
      if (data is Map<String, dynamic>) {
        _order = data;
      } else {
        _error = 'Response format tidak terduga.';
      }
    } on AdminApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Tidak bisa load detail. Cek koneksi.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _updateOrder(Map<String, dynamic> body) async {
    if (_actionInProgress) return;
    setState(() => _actionInProgress = true);
    try {
      final updated = await adminApi.patchJson(
        '/api/admin/orders/${Uri.encodeComponent(widget.orderNumber)}',
        body: body,
      );
      if (updated is Map<String, dynamic> && _order != null) {
        setState(() {
          for (final key in updated.keys) {
            _order![key] = updated[key];
          }
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pesanan ter-update.'),
            backgroundColor: AdminColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on AdminApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal: ${e.message}')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal update. Coba lagi.')),
      );
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  Future<void> _onShipPressed() async {
    final result = await showModalBottomSheet<_ShipFormResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ShipForm(),
    );
    if (result == null) return;
    await _updateOrder({
      'status': 'SHIPPED',
      'trackingNumber': result.trackingNumber,
      'courierCode': result.courierCode,
      'courierService': result.courierService,
    });
  }

  Future<void> _confirmAndUpdateStatus(String newStatus, String label) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('$label?'),
        content: Text(
          'Status pesanan akan diubah jadi "$label". Lanjutkan?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ya'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _updateOrder({'status': newStatus});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('#${widget.orderNumber}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: _buildBottomActions(),
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
    if (_order == null) {
      return const Center(child: Text('Order tidak ditemukan'));
    }

    final o = _order!;
    final items = (o['items'] as List?) ?? const [];
    return RefreshIndicator(
      onRefresh: _load,
      color: AdminColors.primary,
      child: ListView(
        children: [
          // Status banner.
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _StatusChipLarge(status: (o['status'] ?? 'PENDING').toString()),
                const Spacer(),
                Text(
                  _formatDate(o['createdAt']?.toString()),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AdminColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Customer info.
          _SectionCard(
            title: 'Pelanggan',
            children: [
              _InfoRow(
                icon: Icons.person_outline,
                label: 'Nama',
                value: (o['customerName'] ?? '-').toString(),
              ),
              _InfoRow(
                icon: Icons.phone_outlined,
                label: 'HP',
                value: (o['customerPhone'] ?? '-').toString(),
                trailing: IconButton(
                  icon: const Icon(Icons.call_outlined,
                      color: AdminColors.success, size: 20),
                  onPressed: () async {
                    final phone = o['customerPhone']?.toString();
                    if (phone == null || phone.isEmpty) return;
                    final uri = Uri.parse('tel:$phone');
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri);
                    }
                  },
                ),
              ),
              if (o['customerEmail'] != null)
                _InfoRow(
                  icon: Icons.email_outlined,
                  label: 'Email',
                  value: o['customerEmail'].toString(),
                ),
            ],
          ),

          // Shipping address.
          _SectionCard(
            title: 'Alamat Pengiriman',
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  [
                    o['shippingAddress'],
                    o['shippingCity'],
                    o['shippingProvinceName'],
                    o['shippingPostalCode'],
                  ]
                      .where((v) => v != null && v.toString().isNotEmpty)
                      .join(', '),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AdminColors.textPrimary,
                    height: 1.4,
                  ),
                ),
              ),
              if (o['courierCode'] != null || o['courierService'] != null)
                _InfoRow(
                  icon: Icons.local_shipping_outlined,
                  label: 'Kurir',
                  value: '${o['courierCode'] ?? '-'} ${o['courierService'] ?? ''}'
                      .trim(),
                ),
              if (o['trackingNumber'] != null)
                _InfoRow(
                  icon: Icons.receipt_long_outlined,
                  label: 'Resi',
                  value: o['trackingNumber'].toString(),
                  trailing: IconButton(
                    icon: const Icon(Icons.copy_outlined, size: 18),
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: o['trackingNumber'].toString()),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Resi di-copy.'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),

          // Items.
          _SectionCard(
            title: 'Item Pesanan (${items.length})',
            children: [
              for (final item in items)
                if (item is Map<String, dynamic>)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (item['name'] ?? '-').toString(),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AdminColors.textPrimary,
                                ),
                              ),
                              if (item['variantLabel'] != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  item['variantLabel'].toString(),
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: AdminColors.textMuted,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 2),
                              Text(
                                'x${item['quantity'] ?? 1}  •  ${formatRupiah(item['price'] ?? 0)}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AdminColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          formatRupiah(
                            (item['price'] ?? 0) is num
                                ? ((item['price'] as num) *
                                        ((item['quantity'] as num?) ?? 1))
                                    .toInt()
                                : 0,
                          ),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AdminColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          ),

          // Total breakdown.
          _SectionCard(
            title: 'Total',
            children: [
              _TotalRow(label: 'Subtotal', value: o['subtotal']),
              _TotalRow(label: 'Ongkir', value: o['shippingCost']),
              if ((o['discount'] ?? 0) is num && (o['discount'] as num) > 0)
                _TotalRow(label: 'Diskon', value: -(o['discount'] as num).toInt()),
              const Divider(),
              _TotalRow(label: 'Total', value: o['total'], bold: true),
              _InfoRow(
                icon: Icons.payment_outlined,
                label: 'Pembayaran',
                value:
                    '${o['paymentProvider'] ?? '-'} • ${o['paymentStatus'] ?? '-'}',
              ),
            ],
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget? _buildBottomActions() {
    if (_order == null) return null;
    final status = (_order!['status'] ?? '').toString().toUpperCase();

    final actions = <Widget>[];

    switch (status) {
      case 'PENDING':
        actions.add(_actionButton(
          label: 'Tandai Lunas',
          onPressed: () => _confirmAndUpdateStatus('PAID', 'Tandai Lunas'),
          color: AdminColors.success,
        ));
        actions.add(_actionButton(
          label: 'Batalkan',
          outlined: true,
          color: AdminColors.danger,
          onPressed: () =>
              _confirmAndUpdateStatus('CANCELLED', 'Batalkan Pesanan'),
        ));
        break;
      case 'PAID':
        actions.add(_actionButton(
          label: 'Tandai Diproses',
          onPressed: () =>
              _confirmAndUpdateStatus('PROCESSING', 'Tandai Diproses'),
          color: AdminColors.info,
        ));
        actions.add(_actionButton(
          label: 'Langsung Kirim',
          onPressed: _onShipPressed,
          color: AdminColors.primary,
        ));
        break;
      case 'PROCESSING':
        actions.add(_actionButton(
          label: 'Input Resi & Kirim',
          onPressed: _onShipPressed,
          color: AdminColors.primary,
        ));
        break;
      case 'SHIPPED':
        actions.add(_actionButton(
          label: 'Tandai Selesai',
          onPressed: () =>
              _confirmAndUpdateStatus('DELIVERED', 'Tandai Selesai'),
          color: AdminColors.success,
        ));
        break;
      case 'DELIVERED':
      case 'CANCELLED':
      case 'REFUNDED':
        return null;
    }

    if (actions.isEmpty) return null;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AdminColors.divider)),
      ),
      padding: EdgeInsets.fromLTRB(
        12,
        10,
        12,
        10 + MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: actions[i]),
          ],
        ],
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required VoidCallback onPressed,
    required Color color,
    bool outlined = false,
  }) {
    if (outlined) {
      return OutlinedButton(
        onPressed: _actionInProgress ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        child: Text(label),
      );
    }
    return ElevatedButton(
      onPressed: _actionInProgress ? null : onPressed,
      style: ElevatedButton.styleFrom(backgroundColor: color),
      child: _actionInProgress
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.white,
              ),
            )
          : Text(label),
    );
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final local = dt.toLocal();
    return '${local.day}/${local.month}/${local.year} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AdminColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AdminColors.textMuted),
          const SizedBox(width: 8),
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AdminColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AdminColors.textPrimary,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  final String label;
  final dynamic value;
  final bool bold;

  const _TotalRow({
    required this.label,
    required this.value,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    final intValue = (value is num) ? (value as num).toInt() : 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: bold ? 14 : 12.5,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
                color: bold ? AdminColors.textPrimary : AdminColors.textSecondary,
              ),
            ),
          ),
          Text(
            formatRupiah(intValue),
            style: TextStyle(
              fontSize: bold ? 16 : 13,
              fontWeight: FontWeight.w800,
              color: bold ? AdminColors.primary : AdminColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChipLarge extends StatelessWidget {
  final String status;
  const _StatusChipLarge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (bg, fg, label) = switch (status.toUpperCase()) {
      'PENDING' => (
        const Color(0xFFFFF8E1),
        AdminColors.warning,
        'Order Baru'
      ),
      'PAID' => (
        const Color(0xFFE6F7F4),
        AdminColors.success,
        'Sudah Dibayar'
      ),
      'PROCESSING' => (
        const Color(0xFFE3F2FD),
        AdminColors.info,
        'Diproses'
      ),
      'READY_FOR_PICKUP' => (
        const Color(0xFFE6F7F4),
        AdminColors.success,
        'Siap Diambil'
      ),
      'SHIPPED' => (
        const Color(0xFFFFF3F0),
        AdminColors.primary,
        'Dikirim'
      ),
      'DELIVERED' => (
        const Color(0xFFE6F7F4),
        AdminColors.success,
        'Selesai'
      ),
      'CANCELLED' => (
        const Color(0xFFFEE2E2),
        AdminColors.danger,
        'Dibatalkan'
      ),
      'REFUNDED' => (
        const Color(0xFFEEEEEE),
        AdminColors.textSecondary,
        'Refund'
      ),
      _ => (
        const Color(0xFFEEEEEE),
        AdminColors.textSecondary,
        status
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }
}

class _ShipFormResult {
  final String trackingNumber;
  final String courierCode;
  final String courierService;

  const _ShipFormResult({
    required this.trackingNumber,
    required this.courierCode,
    required this.courierService,
  });
}

class _ShipForm extends StatefulWidget {
  const _ShipForm();

  @override
  State<_ShipForm> createState() => _ShipFormState();
}

class _ShipFormState extends State<_ShipForm> {
  final _resiController = TextEditingController();
  String _courier = 'JNE';
  String _service = 'REG';

  static const _couriers = ['JNE', 'JNT', 'SiCepat', 'Anteraja', 'POS', 'Lain'];
  static const _services = ['REG', 'YES', 'OKE', 'CTC', 'Cargo', 'Lain'];

  @override
  void dispose() {
    _resiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
            const Text(
              'Input Resi & Kirim',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AdminColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Status pesanan akan jadi "Dikirim".',
              style: TextStyle(
                fontSize: 12,
                color: AdminColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _resiController,
              decoration: const InputDecoration(
                hintText: 'Nomor resi',
                prefixIcon: Icon(Icons.receipt_long_outlined),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _courier,
                    decoration: const InputDecoration(
                      labelText: 'Kurir',
                    ),
                    items: _couriers
                        .map((c) =>
                            DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _courier = v ?? _courier),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _service,
                    decoration: const InputDecoration(
                      labelText: 'Layanan',
                    ),
                    items: _services
                        .map((s) =>
                            DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _service = v ?? _service),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                final resi = _resiController.text.trim();
                if (resi.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Nomor resi wajib diisi.')),
                  );
                  return;
                }
                Navigator.of(context).pop(
                  _ShipFormResult(
                    trackingNumber: resi,
                    courierCode: _courier,
                    courierService: _service,
                  ),
                );
              },
              child: const Text('Kirim Pesanan'),
            ),
          ],
        ),
      ),
    );
  }
}

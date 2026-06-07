import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_client.dart';
import '../services/export_service.dart';
import '../services/notification_counts.dart';
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

  /// Resi cuma relevan untuk order yang sudah dibayar dan butuh kirim
  /// (PAID/PROCESSING/READY_FOR_PICKUP/SHIPPED). Untuk PENDING admin
  /// belum tahu pasti pesanan jadi atau tidak — print resi pemborosan.
  /// Untuk DELIVERED/CANCELLED/REFUNDED sudah lewat — historical only.
  bool _canPrintResi(Map<String, dynamic> order) {
    final s = (order['status'] ?? '').toString().toUpperCase();
    return s == 'PAID' ||
        s == 'PROCESSING' ||
        s == 'READY_FOR_PICKUP' ||
        s == 'SHIPPED';
  }

  Future<void> _printResi() async {
    if (_order == null) return;
    HapticFeedback.lightImpact();
    try {
      await AdminExportService.instance.printResi(_order!);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal cetak: $e')),
        );
      }
    }
  }

  Future<void> _shareResi() async {
    if (_order == null) return;
    HapticFeedback.lightImpact();
    try {
      await AdminExportService.instance.shareResi(_order!);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal share: $e')),
        );
      }
    }
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

  Future<void> _onApproveCancellation() async {
    final orderId = widget.orderNumber;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Setujui pembatalan?'),
        content: const Text(
          'Order akan dibatalkan & sistem otomatis: refund saldo (kalau '
          'sudah bayar), restore stok, rollback voucher, kirim notif ke '
          'customer. Lanjutkan?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AdminColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Setujui'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _runAction(() async {
      await adminApi.postJson(
        '/api/admin/orders/${Uri.encodeComponent(orderId)}/cancellation/approve',
        timeout: const Duration(seconds: 20),
      );
      _showSuccess('Pembatalan disetujui — order CANCELLED, refund ter-issue.');
      await _load();
    });
  }

  Future<void> _onRejectCancellation() async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _RejectCancellationSheet(),
    );
    if (reason == null || reason.isEmpty) return;
    await _runAction(() async {
      await adminApi.postJson(
        '/api/admin/orders/${Uri.encodeComponent(widget.orderNumber)}/cancellation/reject',
        body: {'rejectReason': reason},
      );
      _showSuccess('Permintaan pembatalan ditolak — notif terkirim ke customer.');
      await _load();
    });
  }

  Future<void> _onRefundWallet({String? itemId, int? maxAmount}) async {
    final result = await showModalBottomSheet<_RefundFormResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RefundWalletSheet(
        itemId: itemId,
        suggestedAmount: maxAmount,
      ),
    );
    if (result == null) return;
    await _runAction(() async {
      await adminApi.postJson(
        '/api/admin/orders/${Uri.encodeComponent(widget.orderNumber)}/refund-wallet',
        body: {
          'amount': result.amount,
          'reason': result.reason,
          if (result.itemId != null) 'itemId': result.itemId,
          if (result.adminNote != null && result.adminNote!.isNotEmpty)
            'adminNote': result.adminNote,
        },
        timeout: const Duration(seconds: 20),
      );
      _showSuccess('Refund Rp${result.amount} ter-issue ke Saldo Refund customer.');
      await _load();
    });
  }

  Future<void> _onMarkItemOutOfStock(Map<String, dynamic> item) async {
    final itemId = item['id']?.toString();
    if (itemId == null) return;
    final qty = (item['quantity'] is num) ? (item['quantity'] as num).toInt() : 1;
    final name = (item['name'] ?? 'Item').toString();
    final result = await showModalBottomSheet<_MarkOOSResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MarkOOSSheet(itemName: name, maxQty: qty),
    );
    if (result == null) return;
    await _runAction(() async {
      await adminApi.postJson(
        '/api/admin/orders/${Uri.encodeComponent(widget.orderNumber)}/items/${Uri.encodeComponent(itemId)}/out-of-stock',
        body: {
          'missingQty': result.missingQty,
          if (result.adminNote != null && result.adminNote!.isNotEmpty)
            'adminNote': result.adminNote,
        },
        timeout: const Duration(seconds: 20),
      );
      _showSuccess('$name × ${result.missingQty} ditandai kosong — refund auto-issue.');
      await _load();
    });
  }

  Future<void> _runAction(Future<void> Function() fn) async {
    if (_actionInProgress) return;
    setState(() => _actionInProgress = true);
    try {
      await fn();
    } on AdminApiException catch (e) {
      _showError('Gagal: ${e.message}');
    } catch (_) {
      _showError('Gagal. Coba lagi.');
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    // Haptic confirm action sukses — tactile feedback Material guidelines.
    HapticFeedback.lightImpact();
    // Update badge counter — order status changed bisa pengaruhi
    // ordersPending / cancelRequests.
    NotificationCounts.instance.refresh();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AdminColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
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
          // Menu cetak / share resi — disabled kalau order belum loaded
          // atau status belum siap kirim (PENDING/CANCELLED tidak butuh
          // label resi).
          if (_order != null && _canPrintResi(_order!))
            PopupMenuButton<String>(
              icon: const Icon(Icons.print_rounded),
              tooltip: 'Cetak / Share Resi',
              onSelected: (v) async {
                if (v == 'print') await _printResi();
                if (v == 'share') await _shareResi();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'print',
                  child: ListTile(
                    leading: Icon(Icons.print_outlined),
                    title: Text('Cetak Resi'),
                    subtitle: Text('Via printer Bluetooth/WiFi'),
                    dense: true,
                  ),
                ),
                PopupMenuItem(
                  value: 'share',
                  child: ListTile(
                    leading: Icon(Icons.share_outlined),
                    title: Text('Share PDF Resi'),
                    subtitle: Text('Kirim ke WA/Drive/Email'),
                    dense: true,
                  ),
                ),
              ],
            ),
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
    final refundCases = (o['refundCases'] as List?) ?? const [];
    final cancellationStatus =
        (o['cancellationRequestStatus'] ?? '').toString();
    final refundEligible = o['refundEligible'] == true;
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

          // Order timeline — Shopee-style step indicator.
          // Sembunyikan untuk CANCELLED/REFUNDED karena status flow tidak
          // applicable (cancellation banner sudah handle visual-nya).
          if (!_isTerminalCancelled((o['status'] ?? '').toString()))
            _OrderTimeline(
              status: (o['status'] ?? 'PENDING').toString(),
              createdAt: o['createdAt']?.toString(),
              shippedAt: o['shippedAt']?.toString(),
              updatedAt: o['updatedAt']?.toString(),
            ),

          // Cancellation request banner — muncul kalau ada request PENDING /
          // APPROVED / REJECTED. PENDING punya tombol Setujui & Tolak.
          if (cancellationStatus.isNotEmpty)
            _CancellationBanner(
              status: cancellationStatus,
              reason: o['cancellationReason']?.toString(),
              rejectReason: o['cancellationRejectReason']?.toString(),
              requestedAt: o['cancellationRequestedAt']?.toString(),
              respondedAt: o['cancellationRespondedAt']?.toString(),
              actionInProgress: _actionInProgress,
              onApprove: _onApproveCancellation,
              onReject: _onRejectCancellation,
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
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
                        if (refundEligible)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              style: TextButton.styleFrom(
                                foregroundColor: AdminColors.danger,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 0),
                                minimumSize: const Size(0, 28),
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: _actionInProgress
                                  ? null
                                  : () => _onMarkItemOutOfStock(item),
                              icon: const Icon(Icons.report_off_outlined,
                                  size: 14),
                              label: const Text(
                                'Tandai kosong',
                                style: TextStyle(fontSize: 11.5),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
            ],
          ),

          // Refund history — display kalau ada refund case ter-issue.
          if (refundCases.isNotEmpty)
            _SectionCard(
              title: 'Refund (${refundCases.length})',
              children: [
                for (final rc in refundCases)
                  if (rc is Map<String, dynamic>)
                    _RefundCaseRow(refundCase: rc),
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
    final refundEligible = _order!['refundEligible'] == true;
    final cancellationStatus =
        (_order!['cancellationRequestStatus'] ?? '').toString();

    final actions = <Widget>[];

    // Kalau ada cancellation request PENDING, prioritaskan tombol
    // approve/reject di banner — sembunyikan action status biasa supaya
    // admin fokus respon dulu (sama pattern web).
    if (cancellationStatus == 'PENDING') {
      return null;
    }

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

    // Always-available secondary action: refund ke Saldo Refund (kalau
    // refundEligible). Admin bisa pakai ini untuk partial refund manual
    // (misal customer komplain harga salah, kasih kompensasi sebagian).
    if (refundEligible) {
      actions.add(_actionButton(
        label: 'Refund ke Saldo',
        outlined: true,
        color: AdminColors.danger,
        onPressed: () => _onRefundWallet(),
      ));
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

class _RefundFormResult {
  final int amount;
  final String reason;
  final String? itemId;
  final String? adminNote;

  const _RefundFormResult({
    required this.amount,
    required this.reason,
    this.itemId,
    this.adminNote,
  });
}

class _MarkOOSResult {
  final int missingQty;
  final String? adminNote;

  const _MarkOOSResult({required this.missingQty, this.adminNote});
}

/// Banner cancellation request — varian warna sesuai status.
class _CancellationBanner extends StatelessWidget {
  final String status;
  final String? reason;
  final String? rejectReason;
  final String? requestedAt;
  final String? respondedAt;
  final bool actionInProgress;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _CancellationBanner({
    required this.status,
    required this.reason,
    required this.rejectReason,
    required this.requestedAt,
    required this.respondedAt,
    required this.actionInProgress,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final (bg, fg, title, body) = switch (status) {
      'PENDING' => (
          const Color(0xFFFFF3F0),
          AdminColors.primary,
          'Permintaan pembatalan',
          'Customer minta cancel order. Cek alasannya lalu setujui atau tolak.',
        ),
      'APPROVED' => (
          const Color(0xFFE6F7F4),
          AdminColors.success,
          'Pembatalan disetujui',
          'Permintaan pembatalan sudah disetujui & order sudah CANCELLED.',
        ),
      'REJECTED' => (
          const Color(0xFFFEE2E2),
          AdminColors.danger,
          'Pembatalan ditolak',
          'Kamu sudah tolak permintaan ini — order kembali ke flow normal.',
        ),
      _ => (
          const Color(0xFFEEEEEE),
          AdminColors.textSecondary,
          'Status pembatalan: $status',
          '',
        ),
    };
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 8, 0, 0),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      color: bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                status == 'APPROVED'
                    ? Icons.check_circle_outline_rounded
                    : status == 'REJECTED'
                        ? Icons.cancel_outlined
                        : Icons.warning_amber_rounded,
                color: fg,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              body,
              style: const TextStyle(
                fontSize: 12.5,
                color: AdminColors.textPrimary,
                height: 1.4,
              ),
            ),
          ],
          if (reason != null && reason!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Alasan customer:',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AdminColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    reason!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AdminColors.textPrimary,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (status == 'REJECTED' &&
              rejectReason != null &&
              rejectReason!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Alasan penolakan kamu:',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AdminColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    rejectReason!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AdminColors.textPrimary,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (status == 'PENDING') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: actionInProgress ? null : onReject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AdminColors.danger,
                      side: const BorderSide(color: AdminColors.danger),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Tolak'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: actionInProgress ? null : onApprove,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AdminColors.success,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Setujui'),
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

/// Row untuk satu RefundCase di section history.
class _RefundCaseRow extends StatelessWidget {
  final Map<String, dynamic> refundCase;
  const _RefundCaseRow({required this.refundCase});

  static const _reasonLabels = {
    'OUT_OF_STOCK': 'Stok kosong',
    'PARTIAL_CANCEL': 'Cancel sebagian',
    'RETURN_APPROVED': 'Retur disetujui',
    'ORDER_CANCELLED': 'Order dibatalkan',
    'OTHER': 'Lain-lain',
  };

  @override
  Widget build(BuildContext context) {
    final amount = (refundCase['amount'] is num)
        ? (refundCase['amount'] as num).toInt()
        : 0;
    final status = (refundCase['status'] ?? 'PENDING').toString();
    final reason = (refundCase['reason'] ?? 'OTHER').toString();
    final note = refundCase['adminNote']?.toString();
    final itemRefund = refundCase['orderItemId'] != null;
    final created = refundCase['createdAt']?.toString();
    final credited = refundCase['creditedAt']?.toString();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AdminColors.background,
        borderRadius: BorderRadius.circular(6),
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
                  color: status == 'CREDITED'
                      ? const Color(0xFFE6F7F4)
                      : const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: status == 'CREDITED'
                        ? AdminColors.success
                        : AdminColors.warning,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _reasonLabels[reason] ?? reason,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AdminColors.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                formatRupiah(amount),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AdminColors.danger,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            itemRefund ? 'Per-item' : 'Whole order',
            style: const TextStyle(
              fontSize: 10.5,
              color: AdminColors.textMuted,
            ),
          ),
          if (note != null && note.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              note,
              style: const TextStyle(
                fontSize: 11.5,
                color: AdminColors.textPrimary,
                height: 1.3,
              ),
            ),
          ],
          if (credited != null || created != null) ...[
            const SizedBox(height: 4),
            Text(
              credited != null
                  ? 'Credited: ${_shortDate(credited)}'
                  : 'Dibuat: ${_shortDate(created!)}',
              style: const TextStyle(
                fontSize: 10.5,
                color: AdminColors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _shortDate(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final local = dt.toLocal();
    return '${local.day}/${local.month}/${local.year} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class _RejectCancellationSheet extends StatefulWidget {
  const _RejectCancellationSheet();
  @override
  State<_RejectCancellationSheet> createState() =>
      _RejectCancellationSheetState();
}

class _RejectCancellationSheetState extends State<_RejectCancellationSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
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
              'Tolak Permintaan Pembatalan',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AdminColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Jelaskan alasan penolakan — customer akan terima notif berisi pesan ini.',
              style: TextStyle(fontSize: 12, color: AdminColors.textSecondary),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              maxLines: 4,
              maxLength: 500,
              decoration: const InputDecoration(
                hintText: 'Misal: pesanan sudah masuk antrian packing dan tidak bisa dibatalkan.',
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminColors.danger,
              ),
              onPressed: () {
                final reason = _controller.text.trim();
                if (reason.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Alasan penolakan wajib diisi.')),
                  );
                  return;
                }
                Navigator.of(context).pop(reason);
              },
              child: const Text('Tolak Permintaan'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RefundWalletSheet extends StatefulWidget {
  final String? itemId;
  final int? suggestedAmount;
  const _RefundWalletSheet({this.itemId, this.suggestedAmount});

  @override
  State<_RefundWalletSheet> createState() => _RefundWalletSheetState();
}

class _RefundWalletSheetState extends State<_RefundWalletSheet> {
  late final TextEditingController _amountController;
  final _noteController = TextEditingController();
  String _reason = 'OTHER';

  static const _reasons = [
    ('OUT_OF_STOCK', 'Stok kosong'),
    ('PARTIAL_CANCEL', 'Cancel sebagian'),
    ('RETURN_APPROVED', 'Retur disetujui'),
    ('ORDER_CANCELLED', 'Order dibatalkan'),
    ('OTHER', 'Lain-lain'),
  ];

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.suggestedAmount != null && widget.suggestedAmount! > 0
          ? widget.suggestedAmount.toString()
          : '',
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
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
              'Refund ke Saldo Refund',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AdminColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Nominal akan masuk ke Saldo Refund customer & bisa dipakai untuk order berikutnya.',
              style: TextStyle(fontSize: 12, color: AdminColors.textSecondary),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                hintText: '0',
                prefixText: 'Rp ',
                labelText: 'Nominal Refund',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _reason,
              decoration: const InputDecoration(labelText: 'Alasan'),
              items: _reasons
                  .map((r) => DropdownMenuItem(
                        value: r.$1,
                        child: Text(r.$2),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _reason = v ?? 'OTHER'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              maxLines: 2,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Catatan untuk customer (opsional)',
                hintText: 'Akan tampil di history refund customer',
              ),
            ),
            const SizedBox(height: 6),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminColors.danger,
              ),
              onPressed: () {
                final amount =
                    int.tryParse(_amountController.text.trim()) ?? 0;
                if (amount <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Nominal refund harus > 0.')),
                  );
                  return;
                }
                Navigator.of(context).pop(_RefundFormResult(
                  amount: amount,
                  reason: _reason,
                  itemId: widget.itemId,
                  adminNote: _noteController.text.trim().isEmpty
                      ? null
                      : _noteController.text.trim(),
                ));
              },
              child: const Text('Issue Refund'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MarkOOSSheet extends StatefulWidget {
  final String itemName;
  final int maxQty;
  const _MarkOOSSheet({required this.itemName, required this.maxQty});

  @override
  State<_MarkOOSSheet> createState() => _MarkOOSSheetState();
}

class _MarkOOSSheetState extends State<_MarkOOSSheet> {
  late final TextEditingController _qtyController;
  final _noteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _qtyController = TextEditingController(text: widget.maxQty.toString());
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _noteController.dispose();
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
              'Tandai Item Kosong',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AdminColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.itemName,
              style: const TextStyle(
                fontSize: 12.5,
                color: AdminColors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Refund net-of-voucher otomatis ter-issue ke Saldo customer.',
              style: TextStyle(fontSize: 11.5, color: AdminColors.textMuted),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _qtyController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Qty kosong (max ${widget.maxQty})',
                hintText: '${widget.maxQty}',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              maxLines: 2,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Catatan tambahan (opsional)',
              ),
            ),
            const SizedBox(height: 6),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminColors.danger,
              ),
              onPressed: () {
                final qty = int.tryParse(_qtyController.text.trim()) ?? 0;
                if (qty <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Qty harus > 0.')),
                  );
                  return;
                }
                if (qty > widget.maxQty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(
                            'Qty melebihi qty order (max ${widget.maxQty}).')),
                  );
                  return;
                }
                Navigator.of(context).pop(_MarkOOSResult(
                  missingQty: qty,
                  adminNote: _noteController.text.trim().isEmpty
                      ? null
                      : _noteController.text.trim(),
                ));
              },
              child: const Text('Tandai Kosong + Refund'),
            ),
          ],
        ),
      ),
    );
  }
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

/// True jika status order = CANCELLED / REFUNDED → tidak relevan tampilkan
/// timeline normal (Dibuat→Selesai) karena flow sudah putus.
bool _isTerminalCancelled(String status) {
  final s = status.toUpperCase();
  return s == 'CANCELLED' || s == 'REFUNDED';
}

/// Order Timeline — visual step indicator gaya Shopee/Tokopedia.
///
/// 5 step:
///   0. Dibuat       (PENDING)
///   1. Dibayar      (PAID)
///   2. Dikemas      (PROCESSING / READY_FOR_PICKUP)
///   3. Dikirim      (SHIPPED)
///   4. Selesai      (DELIVERED)
///
/// Visual:
///   - Step "done" : circle terisi penuh + check icon + timestamp
///   - Step "active": circle terisi (color primary) + pulse-style border
///   - Step "upcoming": circle outline kosong + label muted
///   - Connector line antara step: solid kalau next step sudah done,
///     dashed kalau next step belum
///
/// Layout horizontal — paling cocok untuk mobile portrait (5 step
/// muat dengan icon kecil + label 1 baris di bawah).
class _OrderTimeline extends StatelessWidget {
  final String status;
  final String? createdAt;
  final String? shippedAt;
  final String? updatedAt;

  const _OrderTimeline({
    required this.status,
    this.createdAt,
    this.shippedAt,
    this.updatedAt,
  });

  /// Map status → index step yang sedang aktif (sedang berlangsung).
  /// Semua step dengan index < activeStep dianggap sudah selesai.
  int _activeStepIndex(String status) {
    switch (status.toUpperCase()) {
      case 'PENDING':
      case 'PENDING_PAYMENT':
        return 0;
      case 'PAID':
        return 1;
      case 'PROCESSING':
      case 'READY_FOR_PICKUP':
        return 2;
      case 'SHIPPED':
      case 'IN_TRANSIT':
        return 3;
      case 'DELIVERED':
      case 'COMPLETED':
        return 4;
      default:
        return 0;
    }
  }

  String? _timestampFor(int stepIndex, int activeIndex) {
    // Step 0 (Dibuat) → selalu createdAt.
    if (stepIndex == 0) return createdAt;
    // Step 3 (Dikirim) → shippedAt (explicit timestamp dari backend).
    if (stepIndex == 3 && activeIndex >= 3) return shippedAt;
    // Step 4 (Selesai) → updatedAt sebagai best-estimate.
    if (stepIndex == 4 && activeIndex >= 4) return updatedAt;
    // Step 1 (Dibayar) / 2 (Dikemas) tidak punya timestamp explicit di
    // schema sekarang — kalau step "active", tampilkan updatedAt (best
    // fallback). Kalau "done", tidak tampilkan timestamp (admin sudah
    // tahu order ini lewat status berikutnya).
    if (stepIndex == activeIndex) return updatedAt;
    return null;
  }

  String _formatShort(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    return DateFormat('dd MMM HH:mm', 'id_ID').format(dt.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final activeIndex = _activeStepIndex(status);
    const steps = <_TimelineStep>[
      _TimelineStep(label: 'Dibuat', icon: Icons.receipt_long_rounded),
      _TimelineStep(label: 'Dibayar', icon: Icons.payments_rounded),
      _TimelineStep(label: 'Dikemas', icon: Icons.inventory_2_rounded),
      _TimelineStep(label: 'Dikirim', icon: Icons.local_shipping_rounded),
      _TimelineStep(label: 'Selesai', icon: Icons.check_circle_rounded),
    ];

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 12),
      margin: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'Progress Pesanan',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AdminColors.textSecondary,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < steps.length; i++) ...[
                Expanded(
                  child: _TimelineNode(
                    step: steps[i],
                    isDone: i < activeIndex,
                    isActive: i == activeIndex,
                    timestamp: _formatShort(_timestampFor(i, activeIndex)),
                  ),
                ),
                if (i < steps.length - 1)
                  _TimelineConnector(
                    isDone: i < activeIndex,
                    isActiveTo: i == activeIndex,
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _TimelineStep {
  final String label;
  final IconData icon;
  const _TimelineStep({required this.label, required this.icon});
}

class _TimelineNode extends StatelessWidget {
  final _TimelineStep step;
  final bool isDone;
  final bool isActive;
  final String timestamp;

  const _TimelineNode({
    required this.step,
    required this.isDone,
    required this.isActive,
    required this.timestamp,
  });

  @override
  Widget build(BuildContext context) {
    // Color logic:
    //   done   → success green (selesai, no further action)
    //   active → primary coral (sedang berlangsung, fokus admin)
    //   upcoming → muted grey
    final Color circleColor = isDone
        ? AdminColors.success
        : isActive
            ? AdminColors.primary
            : AdminColors.divider;
    final Color iconColor = isDone || isActive
        ? Colors.white
        : AdminColors.textMuted;
    final Color labelColor = isDone
        ? AdminColors.textPrimary
        : isActive
            ? AdminColors.primary
            : AdminColors.textMuted;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            // Outer pulse-ring untuk step active — visual hint kalau ini
            // step yang sedang menunggu action.
            if (isActive)
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AdminColors.primary.withValues(alpha: 0.15),
                ),
              ),
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: circleColor,
                shape: BoxShape.circle,
                border: !isDone && !isActive
                    ? Border.all(color: AdminColors.divider, width: 1.5)
                    : null,
              ),
              child: Icon(
                isDone ? Icons.check_rounded : step.icon,
                size: 16,
                color: iconColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            step.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
              color: labelColor,
            ),
          ),
        ),
        const SizedBox(height: 2),
        SizedBox(
          height: 12,
          child: Text(
            timestamp,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 9,
              color: AdminColors.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}

class _TimelineConnector extends StatelessWidget {
  final bool isDone;
  final bool isActiveTo;
  const _TimelineConnector({required this.isDone, required this.isActiveTo});

  @override
  Widget build(BuildContext context) {
    // Line color: hijau kalau step ini sudah dilewati (i < activeIndex);
    // primary kalau ini line yang mengarah ke active step; grey kalau
    // belum tercapai.
    final color = isDone
        ? AdminColors.success
        : isActiveTo
            ? AdminColors.primary
            : AdminColors.divider;
    return Padding(
      padding: const EdgeInsets.only(top: 13),
      child: Container(
        width: 16,
        height: 2,
        color: color,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/member_profile.dart';
import '../models/shipping_rate.dart';
import '../services/order_service.dart';
import '../state/cart_store.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import '../widgets/app_product_image.dart';
import '../widgets/app_toast.dart';
import '../widgets/app_ui.dart';
import '../widgets/natalo_paw_refresh_indicator.dart';
import '../widgets/order_tracking_timeline.dart';

const _brandBlue = Color(0xFF0B7FEA);
const _bankAccounts = {
  'BCA_NATASHA': _BankAccount(
    bankName: 'BCA',
    accountNumber: '8280277046',
    accountName: 'NATASHA',
  ),
  'BCA_NL_PET': _BankAccount(
    bankName: 'BCA',
    accountNumber: '0987654321',
    accountName: 'NL Pet Shop',
  ),
};

class _BankAccount {
  final String bankName;
  final String accountNumber;
  final String accountName;

  const _BankAccount({
    required this.bankName,
    required this.accountNumber,
    required this.accountName,
  });
}

class MemberOrderDetailScreen extends StatefulWidget {
  final OrderSummary order;

  const MemberOrderDetailScreen({super.key, required this.order});

  @override
  State<MemberOrderDetailScreen> createState() =>
      _MemberOrderDetailScreenState();
}

class _MemberOrderDetailScreenState extends State<MemberOrderDetailScreen> {
  late OrderSummary _order;
  late Future<OrderSummary> _orderFuture;
  bool _reordering = false;
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
    _orderFuture = _loadOrder();
  }

  Future<OrderSummary> _loadOrder() async {
    try {
      final fresh = await orderService.fetchOrderDetail(
        _order.orderNumber,
        trackingToken: _order.trackingToken,
      );
      _order = fresh;
      return fresh;
    } catch (_) {
      return _order;
    }
  }

  Future<void> _refreshOrder() async {
    setState(() => _orderFuture = _loadOrder());
    await _orderFuture;
  }

  /// Share order via native share sheet — kirim summary order ke kontak/
  /// app lain (mis. WhatsApp customer service untuk komplain, atau ke
  /// keluarga buat pamer haha). PWA pakai navigator.share yang patchy
  /// di Android WebView. Native share_plus jauh lebih reliable.
  Future<void> _shareOrder() async {
    AppHaptics.tap();
    final order = _order;
    final url = 'https://natalopetshop.com/akun/pesanan/${order.orderNumber}';
    final summary = StringBuffer()
      ..writeln('🐾 Pesanan Natalo Petshop')
      ..writeln('No. ${order.orderNumber}')
      ..writeln('Status: ${_statusReadable(order.status)}')
      ..writeln('Total: ${formatRupiah(order.total)}')
      ..writeln()
      ..writeln('Track: $url');
    try {
      await Share.share(
        summary.toString(),
        subject: 'Pesanan Natalo #${order.orderNumber}',
      );
    } catch (_) {
      // Silent fail — share adalah opsional, jangan blokir flow.
    }
  }

  String _statusReadable(String status) {
    switch (status.toUpperCase()) {
      case 'UNPAID':
      case 'PENDING':
        return 'Menunggu pembayaran';
      case 'PAID':
        return 'Sudah dibayar';
      case 'PROCESSING':
        return 'Sedang diproses';
      case 'SHIPPED':
        return 'Dalam pengiriman';
      case 'DELIVERED':
        return 'Selesai';
      case 'CANCELLED':
        return 'Dibatalkan';
      default:
        return status;
    }
  }

  Future<void> _confirmCancel(BuildContext context, OrderSummary order) async {
    if (_cancelling) return;
    AppHaptics.tap();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFFFEE2E2),
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Icon(
            Icons.cancel_outlined,
            color: Color(0xFFEF4444),
            size: 28,
          ),
        ),
        title: const Text(
          'Batalkan pesanan?',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Pesanan ${order.orderNumber} akan dibatalkan dan tidak bisa '
              'dikembalikan. Stock produk akan otomatis tersedia lagi.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
            if (order.voucherCode != null && order.voucherCode!.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'Voucher yang dipakai akan bisa digunakan ulang.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Tidak Jadi'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),
            child: const Text('Ya, Batalkan'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _executeCancel(order);
  }

  Future<void> _executeCancel(OrderSummary order) async {
    setState(() => _cancelling = true);
    try {
      await orderService.cancelOrder(orderNumber: order.orderNumber);
      if (!mounted) return;
      AppHaptics.success();
      // Refresh order detail dari server supaya status update ke CANCELLED.
      await _refreshOrder();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pesanan berhasil dibatalkan.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      AppHaptics.warning();
      final message = error.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Pembatalan gagal: $message'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  Future<void> _buyAgain(BuildContext context, OrderSummary order) async {
    if (_reordering) return;

    setState(() => _reordering = true);
    try {
      final result = await orderService.reorder(
        orderNumber: order.orderNumber,
      );

      if (result.items.isEmpty) {
        final reason = result.skippedReasons.firstOrNull;
        throw Exception(reason ?? 'Tidak ada item yang bisa dibeli lagi.');
      }

      for (final item in result.items) {
        cartStore.addProduct(item.product, quantity: item.quantity);
      }
      await cartStore.syncToServer();

      if (!context.mounted) return;
      final message = result.hasPartialChanges
          ? 'Item tersedia masuk keranjang'
          : 'Produk masuk keranjang';
      AppToast.showCartAdded(
        context,
        message,
        onTap: () => Navigator.pushNamed(context, '/cart'),
      );
    } catch (error) {
      if (!context.mounted) return;
      final message = error.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Beli lagi gagal: $message'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _reordering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<OrderSummary>(
      future: _orderFuture,
      initialData: _order,
      builder: (context, snapshot) {
        final order = snapshot.data ?? _order;
        final loading = snapshot.connectionState == ConnectionState.waiting;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Detail Pesanan'),
            actions: [
              // Native share — kirim ringkasan pesanan via WhatsApp/Telegram/
              // dll. PWA tidak punya akses share sheet yang reliable.
              IconButton(
                onPressed: _shareOrder,
                tooltip: 'Bagikan pesanan',
                icon: const Icon(Icons.ios_share_rounded),
              ),
            ],
          ),
          body: NataloPawRefreshIndicator(
            onRefresh: _refreshOrder,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 118),
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: loading
                      ? const LinearProgressIndicator(minHeight: 3)
                      : const SizedBox(height: 3),
                ),
                const SizedBox(height: 9),
                _OrderHeader(order: order),
                const SizedBox(height: 12),
                // Visual timeline 4-stage — animated pulse di stage aktif,
                // connector lines hijau di stage selesai. Native feel yang
                // PWA hard to replicate karena animated icon.
                OrderTrackingTimeline(
                  status: order.status,
                  createdAt: order.createdAt,
                  type: order.isSelfPickup
                      ? OrderTimelineType.pickup
                      : OrderTimelineType.delivery,
                ),
                const SizedBox(height: 12),
                if (order.isSelfPickup) ...[
                  _PickupInfoCard(order: order),
                  const SizedBox(height: 12),
                ],
                if (_shouldShowPaymentAction(order)) ...[
                  _PaymentActionCard(order: order),
                  const SizedBox(height: 12),
                ],
                if (_shouldShowPaymentProof(order)) ...[
                  _PaymentProofCard(order: order, onUploaded: _refreshOrder),
                  const SizedBox(height: 12),
                ],
                if (_canCancelOrder(order)) ...[
                  _CancelOrderCard(
                    loading: _cancelling,
                    onCancel: () => _confirmCancel(context, order),
                  ),
                  const SizedBox(height: 12),
                ],
                _OrderItemsCard(order: order),
                const SizedBox(height: 12),
                _PaymentSummary(order: order),
              ],
            ),
          ),
          bottomNavigationBar: AppGlassBottomBar(
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: order.items.isEmpty
                        ? null
                        : _reordering
                            ? null
                            : () => _buyAgain(context, order),
                    icon: _reordering
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.replay_rounded),
                    label: Text(_reordering ? 'Memproses' : 'Beli Lagi'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pushNamed(context, '/products'),
                    icon: const Icon(Icons.shopping_bag_outlined),
                    label: const Text('Belanja'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PaymentActionCard extends StatelessWidget {
  final OrderSummary order;

  const _PaymentActionCard({required this.order});

  Future<void> _openPayment(BuildContext context) async {
    final paymentUrl = order.paymentUrl;
    if (paymentUrl == null || paymentUrl.isEmpty) return;

    final uri = Uri.tryParse(paymentUrl);
    if (uri == null) {
      _showSnack(context, 'Link pembayaran tidak valid.');
      return;
    }

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!context.mounted) return;
    if (!opened) _showSnack(context, 'Tidak bisa membuka pembayaran.');
  }

  Future<void> _copy(BuildContext context, String value, String message) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    _showSnack(context, message);
  }

  @override
  Widget build(BuildContext context) {
    if (order.paymentProvider.toUpperCase() == 'MIDTRANS') {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Pembayaran Online',
              subtitle: 'Selesaikan pembayaran lewat Midtrans.',
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: order.paymentUrl == null
                    ? null
                    : () => _openPayment(context),
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Bayar Sekarang'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  backgroundColor: _brandBlue,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final bank = _bankAccounts[order.manualBank ?? 'BCA_NATASHA'] ??
        _bankAccounts['BCA_NATASHA']!;
    final totalTransfer = order.total + (order.uniqueCode ?? 0);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
            icon: Icons.account_balance_outlined,
            title: 'Transfer Manual',
            subtitle: 'Transfer sesuai nominal agar verifikasi lebih cepat.',
          ),
          const SizedBox(height: 14),
          _CopyRow(
            label: 'Bank tujuan',
            value: bank.bankName,
            helper: 'a/n ${bank.accountName}',
            onCopy: () => _copy(
              context,
              bank.accountNumber,
              'Nomor rekening tersalin.',
            ),
          ),
          const SizedBox(height: 10),
          _CopyRow(
            label: 'Nomor rekening',
            value: bank.accountNumber,
            monospace: true,
            onCopy: () => _copy(
              context,
              bank.accountNumber,
              'Nomor rekening tersalin.',
            ),
          ),
          const SizedBox(height: 10),
          _CopyRow(
            label: 'Total transfer',
            value: formatRupiah(totalTransfer),
            strong: true,
            helper: order.uniqueCode == null
                ? null
                : 'Termasuk kode unik ${order.uniqueCode}.',
            onCopy: () => _copy(
              context,
              totalTransfer.round().toString(),
              'Nominal transfer tersalin.',
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentProofCard extends StatefulWidget {
  final OrderSummary order;
  final Future<void> Function() onUploaded;

  const _PaymentProofCard({required this.order, required this.onUploaded});

  @override
  State<_PaymentProofCard> createState() => _PaymentProofCardState();
}

class _PaymentProofCardState extends State<_PaymentProofCard> {
  final _picker = ImagePicker();
  bool _uploading = false;
  String? _proofUrl;

  bool get _hasProof =>
      (_proofUrl?.isNotEmpty ?? false) ||
      (widget.order.paymentProofUrl?.isNotEmpty ?? false);

  Future<void> _pickAndUpload() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1800,
    );
    if (picked == null) return;

    setState(() => _uploading = true);
    try {
      final url = await orderService.uploadPaymentProof(
        orderNumber: widget.order.orderNumber,
        file: picked,
        trackingToken: widget.order.trackingToken,
      );
      if (!mounted) return;
      setState(() => _proofUrl = url);
      await widget.onUploaded();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bukti transfer berhasil dikirim.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upload gagal: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor =
        _hasProof ? const Color(0xFF16A34A) : const Color(0xFFF59E0B);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SoftIconTile(
                icon: _hasProof
                    ? Icons.verified_outlined
                    : Icons.receipt_long_outlined,
                color: statusColor,
                size: 44,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _hasProof ? 'Bukti Transfer Terkirim' : 'Bukti Transfer',
                      style: const TextStyle(
                        color: Color(0xFF17202A),
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      _hasProof
                          ? 'Admin akan mengecek pembayaran manual.'
                          : 'Upload foto bukti pembayaran manual.',
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: _hasProof
                ? const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: AppInfoBanner(
                      icon: Icons.check_circle_outline_rounded,
                      message:
                          'Bukti tersimpan. Admin akan verifikasi pembayaran.',
                      color: Color(0xFF16A34A),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: _uploading
                ? const LinearProgressIndicator(minHeight: 6)
                : SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _pickAndUpload,
                      icon: Icon(
                        _hasProof
                            ? Icons.refresh_rounded
                            : Icons.upload_file_rounded,
                      ),
                      label: Text(_hasProof ? 'Ganti Bukti' : 'Upload Bukti'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        backgroundColor: _brandBlue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _PickupInfoCard extends StatelessWidget {
  final OrderSummary order;

  const _PickupInfoCard({required this.order});

  Future<void> _openMaps(BuildContext context) async {
    AppHaptics.tap();
    final lat = order.pickupLatitude;
    final lng = order.pickupLongitude;
    final fallbackQuery = Uri.encodeComponent(
      '${order.pickupLocationName ?? PickupStoreInfo.name} '
      '${order.pickupAddress ?? PickupStoreInfo.address}',
    );
    final url = lat != null && lng != null
        ? 'https://www.google.com/maps/search/?api=1&query=$lat,$lng'
        : (order.pickupMapsUrl?.trim().isNotEmpty == true
            ? order.pickupMapsUrl!.trim()
            : 'https://www.google.com/maps/search/?api=1&query=$fallbackQuery');
    final uri = Uri.tryParse(url);
    if (uri == null) {
      _showSnack(context, 'Link Google Maps tidak valid.');
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!context.mounted || opened) return;
    _showSnack(context, 'Tidak bisa membuka Google Maps.');
  }

  @override
  Widget build(BuildContext context) {
    final locationName = order.pickupLocationName?.trim().isNotEmpty == true
        ? order.pickupLocationName!.trim()
        : PickupStoreInfo.name;
    final address = order.pickupAddress?.trim().isNotEmpty == true
        ? order.pickupAddress!.trim()
        : PickupStoreInfo.address;
    final hours = order.pickupHours?.trim().isNotEmpty == true
        ? order.pickupHours!.trim()
        : PickupStoreInfo.hours;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
            icon: Icons.storefront_rounded,
            title: 'Metode Pengambilan',
            subtitle: 'Ambil pesanan langsung di toko.',
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ambil Sendiri di Toko',
                      style: TextStyle(
                        color: Color(0xFF17202A),
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Self Pick Up - Gratis Ongkir',
                      style: TextStyle(
                        color: _brandBlue,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F8EF),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Gratis ongkir',
                  style: TextStyle(
                    color: Color(0xFF087A3A),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _PickupInfoRow(
            icon: Icons.location_on_outlined,
            title: 'Lokasi Toko',
            content: '$locationName\n$address',
          ),
          const SizedBox(height: 16),
          _PickupInfoRow(
            icon: Icons.access_time_rounded,
            title: 'Jam Ambil',
            content: hours,
          ),
          const SizedBox(height: 18),
          _PickupCodeBox(
            pickupCode: order.pickupCode,
            orderStatus: order.status,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: () => _openMaps(context),
              icon: const Icon(Icons.location_on_outlined, size: 20),
              label: const Text('Buka di Google Maps'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _brandBlue,
                side: const BorderSide(color: _brandBlue, width: 1.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PickupCodeBox extends StatelessWidget {
  final String? pickupCode;
  final String? orderStatus;

  const _PickupCodeBox({required this.pickupCode, this.orderStatus});

  /// Status pill yang relevant untuk pickup:
  /// - PENDING/PAID/PROCESSING → "Sedang disiapkan" (kuning)
  /// - READY_FOR_PICKUP → "Siap diambil!" (hijau gradient + animated)
  /// - DELIVERED → "Sudah diambil" (abu, faded)
  ({String label, Color bg, Color fg, IconData icon})? _statusBadge() {
    final status = (orderStatus ?? '').toUpperCase();
    if (status == 'READY_FOR_PICKUP') {
      return (
        label: 'Siap diambil',
        bg: const Color(0xFF16A34A),
        fg: Colors.white,
        icon: Icons.check_circle_rounded,
      );
    }
    if (status == 'DELIVERED' || status == 'COMPLETED') {
      return (
        label: 'Sudah diambil',
        bg: const Color(0xFFE5E7EB),
        fg: const Color(0xFF6B7280),
        icon: Icons.task_alt_rounded,
      );
    }
    if (status == 'PROCESSING' ||
        status == 'PAID' ||
        status == 'PENDING') {
      return (
        label: 'Sedang disiapkan',
        bg: const Color(0xFFFFF7E0),
        fg: const Color(0xFFB45309),
        icon: Icons.inventory_2_rounded,
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final code = pickupCode?.trim();
    final hasCode = code != null && code.isNotEmpty;
    final badge = _statusBadge();

    return InkWell(
      onTap: hasCode
          ? () {
              AppHaptics.tap();
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Kode "$code" disalin ke clipboard.'),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          : null,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          color: const Color(0xFFEAF8EF),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFCBEFD8)),
        ),
        child: Column(
          children: [
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.qr_code_2_rounded,
                  size: 16,
                  color: Color(0xFF087A3A),
                ),
                SizedBox(width: 6),
                Text(
                  'Kode Pengambilan',
                  style: TextStyle(
                    color: Color(0xFF087A3A),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              hasCode ? code : 'Kode pengambilan belum tersedia',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: const Color(0xFF087A3A),
                fontSize: hasCode ? 28 : 15,
                fontWeight: FontWeight.w900,
                letterSpacing: hasCode ? 3 : 0,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasCode
                  ? 'Tap untuk salin — tunjukkan ke kasir saat ambil.'
                  : 'Kode keluar saat pesanan selesai disiapkan toko.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF087A3A),
                fontSize: 12.5,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (badge != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: badge.bg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(badge.icon, color: badge.fg, size: 14),
                    const SizedBox(width: 5),
                    Text(
                      badge.label,
                      style: TextStyle(
                        color: badge.fg,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PickupInfoRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String content;

  const _PickupInfoRow({
    required this.icon,
    required this.title,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF8EF),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, size: 21, color: const Color(0xFF059669)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF374151),
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                content,
                style: const TextStyle(
                  color: Color(0xFF17202A),
                  fontSize: 14,
                  height: 1.45,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SoftIconTile(icon: icon, color: _brandBlue, size: 42),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF17202A),
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CopyRow extends StatelessWidget {
  final String label;
  final String value;
  final String? helper;
  final bool strong;
  final bool monospace;
  final VoidCallback onCopy;

  const _CopyRow({
    required this.label,
    required this.value,
    required this.onCopy,
    this.helper,
    this.strong = false,
    this.monospace = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.92)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF60A5FA).withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: TextStyle(
                    color: strong ? _brandBlue : const Color(0xFF17202A),
                    fontSize: strong ? 20 : 16,
                    fontWeight: FontWeight.w900,
                    fontFamily: monospace ? 'monospace' : null,
                  ),
                ),
                if (helper != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    helper!,
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton.filledTonal(
            onPressed: onCopy,
            icon: const Icon(Icons.copy_rounded),
            tooltip: 'Salin',
          ),
        ],
      ),
    );
  }
}

class _OrderHeader extends StatelessWidget {
  final OrderSummary order;

  const _OrderHeader({required this.order});

  @override
  Widget build(BuildContext context) {
    final statusColor = _orderStatusColor(order.status);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1493F7),
            Color.alphaBlend(
              statusColor.withValues(alpha: 0.18),
              const Color(0xFF075EBB),
            ),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: statusColor.withValues(alpha: 0.20),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -22,
            top: -22,
            child: Container(
              height: 112,
              width: 112,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.10),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    height: 52,
                    width: 52,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.38),
                      ),
                    ),
                    child: Icon(
                      _orderStatusIcon(order.status),
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _statusReadable(order.status),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          order.isSelfPickup
                              ? _pickupStatusSubtitle(
                                  order.status,
                                  order.paymentStatus,
                                )
                              : _paymentLabel(order.paymentStatus),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.78),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AppStatusPill(
                    label: _statusLabel(order.status),
                    color: Colors.white,
                    icon: _orderStatusIcon(order.status),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                'No. Pesanan',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.68),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      order.orderNumber,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: order.orderNumber),
                      );
                      if (context.mounted) {
                        _showSnack(context, 'Nomor pesanan tersalin.');
                      }
                    },
                    icon: const Icon(Icons.copy_rounded),
                    color: Colors.white,
                    tooltip: 'Salin nomor pesanan',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.20),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _HeaderMetric(
                        label: 'Tanggal',
                        value: _formatDate(order.createdAt),
                      ),
                    ),
                    Container(
                      height: 34,
                      width: 1,
                      color: Colors.white.withValues(alpha: 0.16),
                    ),
                    Expanded(
                      child: _HeaderMetric(
                        label: 'Total',
                        value: formatRupiah(order.total),
                        alignEnd: true,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderMetric extends StatelessWidget {
  final String label;
  final String value;
  final bool alignEnd;

  const _HeaderMetric({
    required this.label,
    required this.value,
    this.alignEnd = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.66),
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: alignEnd ? TextAlign.right : TextAlign.left,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _OrderItemsCard extends StatelessWidget {
  final OrderSummary order;

  const _OrderItemsCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final items = order.items;
    final canReviewOrder = order.status.toUpperCase() == 'DELIVERED';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SoftIconTile(
                icon: Icons.inventory_2_outlined,
                color: _brandBlue,
                size: 42,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Produk Pesanan',
                      style: TextStyle(
                        color: Color(0xFF17202A),
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Item yang masuk dalam pesanan ini.',
                      style: TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              AppStatusPill(
                label: '${order.itemCount} item',
                color: _brandBlue,
                icon: Icons.shopping_bag_outlined,
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (items.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: const Text(
                'Item pesanan belum tersedia di response API.',
                style: TextStyle(
                  color: Color(0xFF6B7280),
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else
            ...List.generate(items.length, (index) {
              final item = items[index];
              final canReview =
                  canReviewOrder && !item.reviewed && item.id.isNotEmpty;
              return Padding(
                padding: EdgeInsets.only(
                  bottom: index == items.length - 1 ? 0 : 12,
                ),
                child: _OrderProductTile(
                  item: item,
                  canReviewOrder: canReviewOrder,
                  canReview: canReview,
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _OrderProductTile extends StatelessWidget {
  final OrderItemSummary item;
  final bool canReviewOrder;
  final bool canReview;

  const _OrderProductTile({
    required this.item,
    required this.canReviewOrder,
    required this.canReview,
  });

  @override
  Widget build(BuildContext context) {
    final subtotal = item.price * item.quantity;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE7EEF7)),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AppProductImage(
                  imageUrl: item.imageUrl,
                  height: 68,
                  width: 68,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF17202A),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _MiniChip(
                          label: item.variantLabel ?? item.categoryName ?? '',
                          icon: Icons.sell_outlined,
                        ),
                        _MiniChip(
                          label: 'Qty ${item.quantity}',
                          icon: Icons.close_rounded,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${formatRupiah(item.price)} / item',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF6B7280),
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Text(
                          formatRupiah(subtotal),
                          style: const TextStyle(
                            color: _brandBlue,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (canReviewOrder) ...[
            const SizedBox(height: 11),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: AppStatusPill(
                      label:
                          item.reviewed ? 'Sudah direview' : 'Menunggu review',
                      color: item.reviewed
                          ? const Color(0xFF16A34A)
                          : const Color(0xFFF59E0B),
                      icon: item.reviewed
                          ? Icons.check_circle_outline_rounded
                          : Icons.rate_review_outlined,
                    ),
                  ),
                  if (canReview)
                    TextButton.icon(
                      // Pass orderItemId — member_reviews_screen akan
                      // auto-open submit sheet untuk item ini langsung.
                      onPressed: () => Navigator.pushNamed(
                        context,
                        '/member/reviews',
                        arguments: {'orderItemId': item.id},
                      ),
                      icon: const Icon(Icons.edit_note_rounded),
                      label: const Text('Ulas'),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  final String label;
  final IconData icon;

  const _MiniChip({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: const Color(0xFF6B7280)),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentSummary extends StatelessWidget {
  final OrderSummary order;

  const _PaymentSummary({required this.order});

  @override
  Widget build(BuildContext context) {
    final subtotal = order.subtotal > 0 ? order.subtotal : order.total;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
            icon: Icons.receipt_long_outlined,
            title: 'Rincian Pembayaran',
            subtitle: 'Ringkasan biaya untuk pesanan ini.',
          ),
          const SizedBox(height: 14),
          _SummaryLine(label: 'Subtotal', value: formatRupiah(subtotal)),
          _SummaryLine(
            label: 'Ongkir',
            value: formatRupiah(order.shippingCost),
          ),
          _SummaryLine(
            label: 'Diskon',
            value: '-${formatRupiah(order.discount)}',
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _brandBlue.withValues(alpha: 0.10),
                  const Color(0xFFEAF6FF),
                ],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _brandBlue.withValues(alpha: 0.16)),
            ),
            child: _SummaryLine(
              label: 'Total bayar',
              value: formatRupiah(order.total),
              strong: true,
              bottomPadding: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  final String label;
  final String value;
  final bool strong;
  final double bottomPadding;

  const _SummaryLine({
    required this.label,
    required this.value,
    this.strong = false,
    this.bottomPadding = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color:
                    strong ? const Color(0xFF17202A) : const Color(0xFF6B7280),
                fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: strong ? _brandBlue : const Color(0xFF17202A),
              fontWeight: FontWeight.w900,
              fontSize: strong ? 18 : 14,
            ),
          ),
        ],
      ),
    );
  }
}

String _statusReadable(String status) {
  return switch (status.toUpperCase()) {
    'UNPAID' ||
    'PENDING' ||
    'WAITING_PAYMENT' ||
    'PENDING_PAYMENT' =>
      'Menunggu pembayaran',
    'PAID' => 'Sudah dibayar',
    'PROCESSING' => 'Sedang diproses',
    'READY_TO_PICKUP' || 'READY_FOR_PICKUP' || 'READY_PICKUP' => 'Siap Diambil',
    'PICKED_UP' => 'Sudah Diambil',
    'SHIPPED' => 'Dalam pengiriman',
    'DELIVERED' || 'COMPLETED' => 'Selesai',
    'CANCELLED' => 'Dibatalkan',
    _ => status,
  };
}

Color _orderStatusColor(String status) {
  return switch (status.toUpperCase()) {
    'UNPAID' ||
    'PENDING' ||
    'WAITING_PAYMENT' ||
    'PENDING_PAYMENT' =>
      const Color(0xFFF59E0B),
    'PAID' || 'PROCESSING' => _brandBlue,
    'READY_TO_PICKUP' ||
    'READY_FOR_PICKUP' ||
    'READY_PICKUP' =>
      const Color(0xFF1E5FBF),
    'SHIPPED' => const Color(0xFF7C3AED),
    'PICKED_UP' || 'DELIVERED' || 'COMPLETED' => const Color(0xFF16A34A),
    'CANCELLED' => const Color(0xFFEF4444),
    _ => _brandBlue,
  };
}

IconData _orderStatusIcon(String status) {
  return switch (status.toUpperCase()) {
    'UNPAID' ||
    'PENDING' ||
    'WAITING_PAYMENT' ||
    'PENDING_PAYMENT' =>
      Icons.schedule_rounded,
    'PAID' => Icons.payments_outlined,
    'PROCESSING' => Icons.inventory_2_outlined,
    'READY_TO_PICKUP' ||
    'READY_FOR_PICKUP' ||
    'READY_PICKUP' =>
      Icons.storefront_rounded,
    'PICKED_UP' => Icons.check_circle_outline_rounded,
    'SHIPPED' => Icons.local_shipping_outlined,
    'DELIVERED' || 'COMPLETED' => Icons.verified_outlined,
    'CANCELLED' => Icons.cancel_outlined,
    _ => Icons.receipt_long_outlined,
  };
}

String _statusLabel(String status) {
  return switch (status.toUpperCase()) {
    'UNPAID' => 'Belum Bayar',
    'PENDING' => 'Menunggu',
    'WAITING_PAYMENT' || 'PENDING_PAYMENT' => 'Belum Bayar',
    'PAID' => 'Lunas',
    'PROCESSING' => 'Diproses',
    'READY_TO_PICKUP' || 'READY_FOR_PICKUP' || 'READY_PICKUP' => 'Siap Diambil',
    'PICKED_UP' => 'Sudah Diambil',
    'SHIPPED' => 'Dikirim',
    'DELIVERED' || 'COMPLETED' => 'Selesai',
    'CANCELLED' => 'Dibatalkan',
    _ => status,
  };
}

String _pickupStatusSubtitle(String orderStatus, String paymentStatus) {
  final payment = paymentStatus.toUpperCase();
  if (payment == 'UNPAID' || payment == 'PENDING') return 'Menunggu bayar';

  return switch (orderStatus.toUpperCase()) {
    'READY_TO_PICKUP' ||
    'READY_FOR_PICKUP' ||
    'READY_PICKUP' =>
      'Pesanan siap diambil di toko',
    'PICKED_UP' ||
    'DELIVERED' ||
    'COMPLETED' =>
      'Pesanan sudah diterima customer',
    'PROCESSING' || 'PAID' => 'Tim sedang menyiapkan pesanan',
    _ => 'Ambil sendiri di toko',
  };
}

String _paymentLabel(String status) {
  return switch (status) {
    'UNPAID' => 'Belum dibayar',
    'PENDING' => 'Menunggu bayar',
    'PAID' => 'Lunas',
    _ => status,
  };
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

bool _shouldShowPaymentProof(OrderSummary order) {
  final manual = order.paymentProvider.toUpperCase() == 'MANUAL';
  final paid = order.paymentStatus.toUpperCase() == 'PAID';
  return manual && !paid;
}

bool _shouldShowPaymentAction(OrderSummary order) {
  final paid = order.paymentStatus.toUpperCase() == 'PAID';
  if (paid) return false;
  if (order.paymentProvider.toUpperCase() == 'MANUAL') return true;
  return order.paymentUrl?.isNotEmpty ?? false;
}

/// Order bisa dibatalkan customer kalau:
/// - Status masih PENDING (belum diproses admin)
/// - Belum dibayar (paymentStatus != PAID)
/// Setelah masuk PROCESSING/SHIPPED/dst, harus kontak admin manual.
bool _canCancelOrder(OrderSummary order) {
  final status = order.status.toUpperCase();
  final paymentStatus = order.paymentStatus.toUpperCase();
  return status == 'PENDING' && paymentStatus != 'PAID';
}

/// Card "Batalkan Pesanan" — muncul kalau order masih PENDING + belum dibayar.
/// Style: subtle red border, danger button. Sengaja tidak prominent supaya
/// user tidak accidentally click — primary action di order pending adalah
/// "Bayar Sekarang" via _PaymentActionCard di atas.
class _CancelOrderCard extends StatelessWidget {
  final bool loading;
  final VoidCallback onCancel;

  const _CancelOrderCard({required this.loading, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.cancel_outlined,
              color: Color(0xFFEF4444),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Mau batalkan pesanan?',
                  style: TextStyle(
                    color: Color(0xFF17202A),
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Bisa dibatalkan sebelum dibayar.',
                  style: TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 38,
            child: OutlinedButton(
              onPressed: loading ? null : onCancel,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFEF4444),
                side: const BorderSide(color: Color(0xFFFCA5A5), width: 1.2),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              child: loading
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFFEF4444),
                      ),
                    )
                  : const Text('Batalkan'),
            ),
          ),
        ],
      ),
    );
  }
}

void _showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
  );
}

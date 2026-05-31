import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/member_profile.dart';
import '../models/product.dart';
import '../models/shipping_rate.dart';
import '../services/order_service.dart';
import '../services/product_service.dart';
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
  bool _confirmingDelivered = false;

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

  Future<void> _confirmCancel(BuildContext context, OrderSummary order) async {
    if (_cancelling) return;
    AppHaptics.tap();
    // Preview message disesuaikan dengan paymentStatus supaya user tahu
    // apa yang akan terjadi:
    //   - Belum bayar → cancel instan, no refund (sesuai spec owner)
    //   - Sudah bayar (PAID) → kirim permintaan ke admin (Shopee pattern).
    //     Pembatalan TIDAK langsung jadi, butuh approval. Admin Approve →
    //     refund full ke Saldo. Admin Reject → order tetap aktif.
    final paymentStatus = order.paymentStatus.toUpperCase();
    final hasPaid = paymentStatus == 'PAID';
    final refundText = hasPaid
        ? 'Pesanan sudah dibayar, jadi pembatalan butuh konfirmasi '
            'admin dulu. Setelah disetujui, total '
            '${_formatRupiahShort(order.total)} akan dikembalikan '
            'ke Saldo Refund kamu.'
        : 'Pesanan belum dibayar, jadi pembatalan langsung diproses dan '
            'tidak ada nominal yang perlu di-refund.';
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
              refundText,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF17202A),
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Voucher atau promo yang dipakai akan dibebaskan dan stok '
              'produk dikembalikan. Aksi ini tidak bisa dibatalkan.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
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

  /// Format Rp ringkas (tanpa decimal, dengan thousand separator).
  /// Accept num supaya bisa dipakai untuk int (refund amount) maupun
  /// double (order.total). Dibulatkan ke integer dulu sebelum format.
  String _formatRupiahShort(num amount) {
    final s = amount.round().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return 'Rp${buf.toString()}';
  }

  Future<void> _executeCancel(OrderSummary order) async {
    setState(() => _cancelling = true);
    try {
      final result =
          await orderService.cancelOrder(orderNumber: order.orderNumber);
      if (!mounted) return;
      AppHaptics.success();
      // Refresh order detail dari server supaya status update ke CANCELLED.
      await _refreshOrder();
      if (!mounted) return;
      // Toast disesuaikan dengan mode:
      //   - requested (paymentStatus=PAID): permintaan dikirim ke admin,
      //     order BELUM cancel. Tampilkan pesan dari server (atau default).
      //   - instant + ada credited: cancel + ada nominal balik ke saldo.
      //   - instant + no credited: cancel + tidak ada duit yang balik.
      final String message;
      if (result.isRequested) {
        message = result.alreadyRequested
            ? 'Permintaan pembatalan sudah pernah diajukan. Tunggu konfirmasi admin.'
            : (result.serverMessage ??
                'Permintaan pembatalan dikirim. Menunggu konfirmasi admin.');
      } else {
        final credited = result.totalCredited;
        message = credited > 0
            ? 'Pesanan dibatalkan. Saldo Refund +${_formatRupiahShort(credited)}.'
            : 'Pesanan berhasil dibatalkan.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
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

  /// User konfirmasi paket sudah diterima (Shopee/Tokopedia pattern).
  /// Tombol tampil saat status SHIPPED. Setelah confirm:
  ///   - status berubah DELIVERED
  ///   - window refund / komplain TUTUP (admin tidak bisa refund lagi)
  ///   - email + push "Pesanan selesai" dikirim ke user
  /// Confirm dialog dipakai supaya user tidak accidentally tap → kehilangan
  /// window komplain.
  Future<void> _confirmDelivered(
    BuildContext context,
    OrderSummary order,
  ) async {
    if (_confirmingDelivered) return;
    AppHaptics.tap();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFFD1FAE5),
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Icon(
            Icons.check_circle_outline_rounded,
            color: Color(0xFF059669),
            size: 28,
          ),
        ),
        title: const Text(
          'Sudah terima pesanan?',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Konfirmasi pesanan sudah sampai dan kondisinya OK. Setelah ini, '
              'pesanan akan ditandai selesai dan window komplain/refund akan '
              'tutup.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF374151),
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1.5,
              ),
            ),
            SizedBox(height: 10),
            Text(
              'Kalau ada masalah dengan paket, jangan tap dulu — hubungi admin '
              'via WhatsApp.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Belum'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
            ),
            child: const Text('Ya, Sudah Terima'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _executeConfirmDelivered(order);
  }

  Future<void> _executeConfirmDelivered(OrderSummary order) async {
    setState(() => _confirmingDelivered = true);
    try {
      final result = await orderService.confirmDelivered(
        orderNumber: order.orderNumber,
      );
      if (!mounted) return;
      AppHaptics.success();
      await _refreshOrder();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.alreadyConfirmed
                ? 'Pesanan sudah ditandai selesai.'
                : result.message,
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      AppHaptics.warning();
      final message = error.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Konfirmasi gagal: $message'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _confirmingDelivered = false);
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
        // Semua item skipped — kasih friendly message.
        // Pakai first reason kalau cuma 1, summary count kalau multiple
        // (avoid super-long toast yang ke-truncate di small screen).
        final reasons = result.skippedReasons;
        final message = reasons.isEmpty
            ? 'Tidak ada item yang bisa dibeli lagi.'
            : reasons.length == 1
                ? reasons.first
                : '${reasons.length} produk tidak bisa dibeli lagi (stok habis / tidak tersedia).';
        throw Exception(message);
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
                // Core order detail first. Ini mencegah layar terlihat seperti
                // blank card besar ketika payment/proof section gagal memuat
                // atau belum diperlukan oleh status order tertentu.
                _OrderItemsCard(order: order),
                const SizedBox(height: 12),
                // Info pengiriman — tampil mulai dari status SHIPPED.
                // Display kondisional: nomor resi (kurir regular) atau
                // info driver (kurir instant Gojek/Grab/dst).
                if (_shouldShowShippingInfo(order)) ...[
                  _ShippingInfoCard(order: order),
                  const SizedBox(height: 12),
                ],
                _PaymentSummary(order: order),
                const SizedBox(height: 12),
                if (_shouldShowPaymentAction(order)) ...[
                  _PaymentActionCard(order: order),
                  const SizedBox(height: 12),
                ],
                if (_shouldShowPaymentProof(order)) ...[
                  _PaymentProofCard(order: order, onUploaded: _refreshOrder),
                  const SizedBox(height: 12),
                ],
                // Banner state pembatalan: PENDING (menunggu admin) atau
                // REJECTED (ditolak admin) — tampil di atas tombol cancel.
                // Untuk PENDING, tombol cancel disembunyikan oleh
                // _canCancelOrder (anti double-submit).
                if (order.hasPendingCancellationRequest) ...[
                  _CancellationPendingBanner(
                    reason: order.cancellationReason,
                    requestedAt: order.cancellationRequestedAt,
                  ),
                  const SizedBox(height: 12),
                ] else if (order.cancellationRejected) ...[
                  _CancellationRejectedBanner(
                    userReason: order.cancellationReason,
                    rejectReason: order.cancellationRejectReason,
                    respondedAt: order.cancellationRespondedAt,
                  ),
                  const SizedBox(height: 12),
                ],
                if (_canCancelOrder(order)) ...[
                  _CancelOrderCard(
                    loading: _cancelling,
                    onCancel: () => _confirmCancel(context, order),
                  ),
                  const SizedBox(height: 12),
                ],
                // Tombol "Pesanan Sudah Diterima" — tampil hanya kalau status
                // SHIPPED (paket sudah di kurir, user nunggu sampai). Setelah
                // tap → status DELIVERED, window refund tutup. Self-pickup
                // tidak pakai tombol ini (admin handle via markAsPickedUp).
                if (order.status.toUpperCase() == 'SHIPPED' &&
                    !order.isSelfPickup) ...[
                  _ConfirmDeliveredCard(
                    loading: _confirmingDelivered,
                    onConfirm: () => _confirmDelivered(context, order),
                    autoConfirmAt: order.autoConfirmAt,
                  ),
                  const SizedBox(height: 12),
                ],
                // Self-pickup layout: Pickup info → Pickup code →
                // Google Maps button → Ready notice. Produk + payment summary
                // sudah muncul di atas supaya detail utama selalu terlihat.
                if (order.isSelfPickup) ...[
                  _PickupInfoCard(order: order),
                  const SizedBox(height: 12),
                  _PickupCodeBox(
                    pickupCode: order.pickupCode,
                    orderStatus: order.status,
                  ),
                  const SizedBox(height: 12),
                  _PickupGoogleMapsButton(order: order),
                  const SizedBox(height: 12),
                ],
                if (order.isSelfPickup && _isReadyForPickup(order)) ...[
                  const _ReadyPickupNoticeCard(),
                ],
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
        mainAxisSize: MainAxisSize.min,
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
            // Emphasize transfer PERSIS — kode unik (sudah termasuk di
            // nominal) bikin tiap order beda supaya admin gampang cocokkan
            // dengan bukti. User cukup transfer angka pas ini, JANGAN
            // dibulatkan (kalau dibulatkan, kode unik hilang → admin susah
            // verifikasi).
            helper: order.uniqueCode == null
                ? 'Transfer dengan nominal pas, jangan dibulatkan ya.'
                : 'Transfer PAS sampai 3 digit terakhir (sudah termasuk kode unik ${order.uniqueCode}). Jangan dibulatkan.',
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
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _OrderDetailIconTile(
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

/// Pickup store info card — ONLY store info (location + hours). Pickup
/// code dan Google Maps button di-extract ke widget terpisah supaya tidak
/// nge-bloat satu card jadi sepertiga layar dengan blank space besar.
/// Pattern: satu konsep = satu card.
class _PickupInfoCard extends StatelessWidget {
  final OrderSummary order;

  const _PickupInfoCard({required this.order});

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
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5EAF2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Ambil Sendiri di Toko',
                  style: TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F8EF),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Gratis ongkir',
                  style: TextStyle(
                    color: Color(0xFF108A43),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Self Pick Up - Gratis Ongkir',
            style: TextStyle(
              color: Color(0xFF0B83E6),
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 20),
          _PickupInfoRow(
            icon: Icons.location_on_outlined,
            title: 'Lokasi Toko',
            content: '$locationName\n$address',
          ),
          const SizedBox(height: 20),
          _PickupInfoRow(
            icon: Icons.access_time_rounded,
            title: 'Jam Ambil',
            content: hours,
          ),
        ],
      ),
    );
  }
}

/// Standalone "Buka di Google Maps" button — extracted dari _PickupInfoCard
/// supaya bukan card di dalam card. Url dari order.pickupMapsUrl atau
/// fallback ke PickupStoreInfo.mapsUrl (share.google direct link).
class _PickupGoogleMapsButton extends StatelessWidget {
  final OrderSummary order;

  const _PickupGoogleMapsButton({required this.order});

  Future<void> _openMaps(BuildContext context) async {
    AppHaptics.tap();
    final lat = order.pickupLatitude;
    final lng = order.pickupLongitude;
    final fallbackQuery = Uri.encodeComponent(
      '${order.pickupLocationName ?? PickupStoreInfo.name} '
      '${order.pickupAddress ?? PickupStoreInfo.address}',
    );
    // Priority: explicit order.pickupMapsUrl → coordinates → default
    // PickupStoreInfo.mapsUrl (share.google) → search query fallback.
    final url = order.pickupMapsUrl?.trim().isNotEmpty == true
        ? order.pickupMapsUrl!.trim()
        : (lat != null && lng != null
            ? 'https://www.google.com/maps/search/?api=1&query=$lat,$lng'
            : PickupStoreInfo.mapsUrl.isNotEmpty
                ? PickupStoreInfo.mapsUrl
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
    return OutlinedButton.icon(
      onPressed: () => _openMaps(context),
      icon: const Icon(Icons.location_on_outlined),
      label: const Text('Buka di Google Maps'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        side: const BorderSide(color: Color(0xFF0B83E6), width: 1.5),
        foregroundColor: const Color(0xFF0B83E6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Notice "Pesanan Anda sudah siap diambil" — muncul setelah Payment
/// Summary untuk status READY_FOR_PICKUP. Soft blue tile + helper text.
class _ReadyPickupNoticeCard extends StatelessWidget {
  const _ReadyPickupNoticeCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5EAF2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F4FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.verified_user_outlined,
              color: Color(0xFF0B83E6),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pesanan Anda sudah siap diambil.',
                  style: TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Harap ambil pesanan sesuai jam operasional toko.',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
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
    if (status == 'PROCESSING' || status == 'PAID' || status == 'PENDING') {
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
        _OrderDetailIconTile(icon: icon, color: _brandBlue, size: 42),
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
                              : _paymentLabel(
                                  order.paymentStatus,
                                  hasProof: (order.paymentProofUrl ?? '')
                                      .isNotEmpty,
                                ),
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
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _OrderDetailIconTile(
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

class _OrderProductTile extends StatefulWidget {
  final OrderItemSummary item;
  final bool canReviewOrder;
  final bool canReview;

  const _OrderProductTile({
    required this.item,
    required this.canReviewOrder,
    required this.canReview,
  });

  @override
  State<_OrderProductTile> createState() => _OrderProductTileState();
}

class _OrderProductTileState extends State<_OrderProductTile> {
  bool _navigating = false;

  /// Tap item → fetch Product detail + push ke ProductDetailScreen.
  /// Defensive: kalau produk sudah ke-archive / deleted, kasih friendly
  /// snackbar instead of crash.
  Future<void> _openProductDetail() async {
    if (_navigating) return; // Double-tap guard
    setState(() => _navigating = true);
    try {
      final slug = widget.item.productSlug;
      Product? product;
      if (slug != null && slug.isNotEmpty) {
        product = await productService.fetchProductBySlug(slug);
      }
      product ??= (await productService.fetchProducts(
        ids: [widget.item.productId],
        limit: 1,
      ))
          .products
          .firstOrNull;

      if (!mounted) return;
      if (product == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Produk sudah tidak tersedia.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      await Navigator.pushNamed(
        context,
        '/product-detail',
        arguments: product,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gagal buka detail produk. Coba lagi.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _navigating = false);
    }
  }

  OrderItemSummary get item => widget.item;
  bool get canReviewOrder => widget.canReviewOrder;
  bool get canReview => widget.canReview;

  @override
  Widget build(BuildContext context) {
    final subtotal = item.price * item.quantity;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _navigating ? null : _openProductDetail,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE7EEF7)),
          ),
          child: Column(
        mainAxisSize: MainAxisSize.min,
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
        ),
      ),
    );
  }
}

class _OrderDetailIconTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;

  const _OrderDetailIconTile({
    required this.icon,
    required this.color,
    this.size = 42,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(
        icon,
        color: color,
        size: size * 0.52,
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
        mainAxisSize: MainAxisSize.min,
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
          // Granular discount breakdown — split per kategori untuk
          // transparency. Customer langsung tau "voucher saya yang -Rp
          // 20rb itu untuk produk atau ongkir?". Match Shopee/Tokopedia
          // pattern.
          //
          // Fallback chain: kalau productDiscount/shippingDiscount tidak
          // tersedia (legacy order pre-split), tampilkan aggregate
          // `discount` untuk backward compat.
          if (order.productDiscount > 0)
            _DiscountLineWithVoucher(
              label: 'Diskon Produk',
              amount: order.productDiscount,
              voucherCode:
                  order.productVoucherCode ?? order.voucherCode,
            )
          else if (order.shippingDiscount > 0)
            // No productDiscount tapi ada shippingDiscount — keep aggregate
            // gak tampil supaya cleaner.
            const SizedBox.shrink()
          else if (order.discount > 0)
            _SummaryLine(
              label: 'Diskon',
              value: '-${formatRupiah(order.discount)}',
            ),
          if (order.shippingDiscount > 0)
            _DiscountLineWithVoucher(
              label: 'Diskon Ongkir',
              amount: order.shippingDiscount,
              voucherCode: order.freeShippingVoucherCode ??
                  order.shippingVoucherCode,
            ),
          // Saldo Refund line — tampil hanya kalau order pakai saldo.
          // Tanpa line ini, math tidak nyambung: subtotal - diskon ≠ total
          // (selisih = saldo) → user bingung kenapa total Rp1.7jt padahal
          // subtotal Rp2.7jt - diskon Rp80k = Rp2.7jt. Spec audit trail.
          if (order.refundBalanceUsed > 0)
            _SummaryLine(
              label: 'Saldo Refund Digunakan',
              value: '-${formatRupiah(order.refundBalanceUsed)}',
            ),
          // Per-voucher detail list — tampil kalau VoucherUsage[] dari
          // backend ada. Pattern Shopee: di bawah summary, tampilkan
          // detail "✓ NATA-DISC: -Rp X" supaya customer confidence
          // voucher mereka beneran ke-apply.
          if (order.voucherUsages.isNotEmpty) ...[
            const SizedBox(height: 10),
            _VoucherUsageList(usages: order.voucherUsages),
          ],
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

/// Discount line dengan inline voucher code chip (kalau ada).
/// Pattern: "Diskon Produk (NATA-DISC) -Rp 30.000" — kode voucher
/// di-display sebagai monospace pill kecil supaya stand out dari teks
/// regular. Kalau voucher code null (mis. legacy order tanpa code
/// tracking), label-only.
class _DiscountLineWithVoucher extends StatelessWidget {
  final String label;
  final double amount;
  final String? voucherCode;

  const _DiscountLineWithVoucher({
    required this.label,
    required this.amount,
    this.voucherCode,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (voucherCode != null && voucherCode!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      voucherCode!,
                      style: const TextStyle(
                        color: Color(0xFF4338CA),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Text(
            '-${formatRupiah(amount)}',
            style: const TextStyle(
              color: Color(0xFFDC2626),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// List per-voucher detail di bawah summary. Tampilkan kalau backend
/// kasih VoucherUsage[] data — biasa cuma untuk order yang pakai
/// multiple voucher. Goal: transparency "voucher saya kepake gak?".
///
/// Layout: light blue box, checkmark icon + voucher label + amount.
/// Match pattern Shopee detail order.
class _VoucherUsageList extends StatelessWidget {
  final List<OrderVoucherUsage> usages;

  const _VoucherUsageList({required this.usages});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFC7D2FE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.local_offer_outlined,
                size: 14,
                color: Color(0xFF4338CA),
              ),
              SizedBox(width: 6),
              Text(
                'Voucher Digunakan',
                style: TextStyle(
                  color: Color(0xFF4338CA),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...usages.map(
            (u) => Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  const Text(
                    '✓ ',
                    style: TextStyle(
                      color: Color(0xFF059669),
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${u.displayLabel}: ',
                            style: const TextStyle(
                              color: Color(0xFF4338CA),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          TextSpan(
                            text: u.code,
                            style: const TextStyle(
                              color: Color(0xFF1E1B4B),
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Text(
                    '-${formatRupiah(u.discountAmount)}',
                    style: const TextStyle(
                      color: Color(0xFFDC2626),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
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

/// Label status bayar — "turunan": kalau order MANUAL belum lunas TAPI
/// user sudah upload bukti (hasProof), tampilkan "Menunggu verifikasi"
/// alih-alih "Menunggu bayar". Status di DB tetap PENDING (Opsi B — tidak
/// nambah enum status baru), label dihitung dari status + ada-tidaknya
/// bukti. User jadi tahu buktinya sudah masuk + sedang dicek admin.
String _paymentLabel(String status, {bool hasProof = false}) {
  final s = status.toUpperCase();
  if (hasProof && (s == 'PENDING' || s == 'UNPAID')) {
    return 'Menunggu verifikasi';
  }
  return switch (s) {
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
  if (_isFinalizedOrder(order)) return false;
  final manual = order.paymentProvider.toUpperCase() == 'MANUAL';
  final paid = order.paymentStatus.toUpperCase() == 'PAID';
  return manual && !paid;
}

bool _shouldShowPaymentAction(OrderSummary order) {
  if (_isFinalizedOrder(order)) return false;
  final paid = order.paymentStatus.toUpperCase() == 'PAID';
  if (paid) return false;
  if (order.paymentProvider.toUpperCase() == 'MANUAL') return true;
  return order.paymentUrl?.isNotEmpty ?? false;
}

bool _isFinalizedOrder(OrderSummary order) {
  final status = order.status.toUpperCase();
  return status == 'CANCELLED' ||
      status == 'CANCELED' ||
      status == 'REFUNDED' ||
      status == 'EXPIRED';
}

/// Order bisa dibatalkan customer kalau status "sebelum paket dikirim":
/// PENDING, PAID, atau PROCESSING. Begitu masuk READY_FOR_PICKUP /
/// SHIPPED / DELIVERED → tidak bisa cancel sendiri (paket sudah di kurir
/// atau sudah dianggap selesai).
///
/// Cancel flow (Shopee/Tokopedia pattern):
///   - paymentStatus != "PAID" → INSTANT cancel, tidak ada refund
///   - paymentStatus == "PAID" → REQUEST mode, butuh approval admin
///     (server cuma create pending request, status order belum berubah)
///
/// Tombol cancel disembunyikan kalau sudah ada request PENDING (anti
/// double-submit) — user diarahkan ke banner "Menunggu konfirmasi admin"
/// yang render di atas.
bool _canCancelOrder(OrderSummary order) {
  final status = order.status.toUpperCase();
  if (status != 'PENDING' && status != 'PAID' && status != 'PROCESSING') {
    return false;
  }
  // Sudah ada pending request → jangan tampilin tombol cancel lagi.
  if (order.hasPendingCancellationRequest) return false;
  return true;
}

/// Pesanan siap diambil — toko sudah konfirmasi item ready, tinggal
/// customer datang. Status READY_FOR_PICKUP / READY_TO_PICKUP / READY_PICKUP
/// (backend variasi naming).
bool _isReadyForPickup(OrderSummary order) {
  final status = order.status.toUpperCase();
  return status == 'READY_FOR_PICKUP' ||
      status == 'READY_TO_PICKUP' ||
      status == 'READY_PICKUP';
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
                  'Bisa dibatalkan sebelum paket dikirim.',
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

/// Decide kapan card "Info Pengiriman" tampil:
/// - Status SHIPPED / DELIVERED — paket sudah dikirim, info kurir relevant
/// - Bukan self-pickup — pickup gak ada kurir
/// - Ada salah satu data: trackingNumber ATAU shippingDriverInfo
bool _shouldShowShippingInfo(OrderSummary order) {
  final status = order.status.toUpperCase();
  if (status != 'SHIPPED' && status != 'DELIVERED') return false;
  if (order.isSelfPickup) return false;
  final hasResi =
      order.trackingNumber != null && order.trackingNumber!.trim().isNotEmpty;
  final hasDriver = order.shippingDriverInfo != null &&
      order.shippingDriverInfo!.trim().isNotEmpty;
  return hasResi || hasDriver;
}

/// Card "Info Pengiriman" — display kondisional resi vs info driver.
/// Untuk kurir regular (JNE/JNT/dst): tampilkan nomor resi.
/// Untuk kurir instant (Gojek/Grab/dst): tampilkan info driver yang
/// admin isi (nama/HP/plat/link GPS — format bebas, mono font supaya
/// rapih kalau ada line break).
class _ShippingInfoCard extends StatelessWidget {
  final OrderSummary order;

  const _ShippingInfoCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final hasResi = order.trackingNumber != null &&
        order.trackingNumber!.trim().isNotEmpty;
    final hasDriver = order.shippingDriverInfo != null &&
        order.shippingDriverInfo!.trim().isNotEmpty;
    final courierLabel =
        order.courierService ?? order.courierCode ?? 'Kurir';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF2FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  hasDriver
                      ? Icons.two_wheeler_rounded
                      : Icons.local_shipping_rounded,
                  color: const Color(0xFF1E5FBF),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Info Pengiriman',
                      style: TextStyle(
                        color: Color(0xFF17202A),
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      hasDriver
                          ? '$courierLabel · Same-day delivery'
                          : courierLabel,
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (hasResi)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Nomor Resi',
                      style: TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    order.trackingNumber!,
                    style: const TextStyle(
                      color: Color(0xFF17202A),
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            )
          else if (hasDriver) ...[
            const Text(
              'Info Driver',
              style: TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              // SelectableText supaya user bisa copy nomor HP / link GPS.
              child: SelectableText(
                order.shippingDriverInfo!,
                style: const TextStyle(
                  color: Color(0xFF17202A),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  height: 1.5,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Card "Pesanan Sudah Diterima" — tombol prominent hijau yang muncul
/// kalau status SHIPPED (paket sudah dikirim ke kurir). Tap → confirm
/// dialog → status DELIVERED + window refund tutup.
///
/// Style: lebih prominent dari Cancel Card (primary action di stage ini).
/// Customer ekspektasi: "kalau sudah terima, tap di sini" — analog dengan
/// "Pesanan Diterima" di Shopee/Tokopedia.
class _ConfirmDeliveredCard extends StatelessWidget {
  final bool loading;
  final VoidCallback onConfirm;
  /// Estimasi kapan order auto-DELIVERED via cron (default H+7 sejak
  /// shipped). Tampilkan small text "Otomatis selesai DD MMM YYYY"
  /// di bawah button supaya user tau timing-nya + decision aid.
  /// Null = belum SHIPPED atau backend belum expose field ini.
  final DateTime? autoConfirmAt;

  const _ConfirmDeliveredCard({
    required this.loading,
    required this.onConfirm,
    this.autoConfirmAt,
  });

  String _formatAutoConfirm(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Agt', 'Sep', 'Okt', 'Nov', 'Des',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFA7F3D0), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFD1FAE5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.check_circle_outline_rounded,
                  color: Color(0xFF059669),
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
                      'Pesanan sudah sampai?',
                      style: TextStyle(
                        color: Color(0xFF065F46),
                        fontSize: 14.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Konfirmasi untuk selesaikan pesanan.',
                      style: TextStyle(
                        color: Color(0xFF047857),
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
                child: FilledButton(
                  onPressed: loading ? null : onConfirm,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
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
                            color: Colors.white,
                          ),
                        )
                      : const Text('Sudah Diterima'),
                ),
              ),
            ],
          ),
          // Auto-confirm info — transparency soal cron auto-DELIVERED.
          // User gak surprise saat dapat email "Pesanan otomatis selesai".
          if (autoConfirmAt != null) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.schedule_rounded,
                  color: Color(0xFF047857),
                  size: 14,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Otomatis selesai ${_formatAutoConfirm(autoConfirmAt!)} kalau belum dikonfirmasi.',
                    style: const TextStyle(
                      color: Color(0xFF047857),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
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

/// Banner "Permintaan Pembatalan Menunggu Admin". Muncul saat user sudah
/// submit cancel request (paymentStatus=PAID) dan admin belum approve /
/// reject. Tombol cancel di order detail otomatis disembunyikan
/// (_canCancelOrder return false).
class _CancellationPendingBanner extends StatelessWidget {
  final String? reason;
  final DateTime? requestedAt;

  const _CancellationPendingBanner({
    required this.reason,
    required this.requestedAt,
  });

  String _formatTime(DateTime dt) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Agt', 'Sep', 'Okt', 'Nov', 'Des',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}, '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFCD34D), width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.hourglass_top_rounded,
              color: Color(0xFFB45309),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Menunggu konfirmasi admin',
                  style: TextStyle(
                    color: Color(0xFF92400E),
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Pembatalan kamu sedang ditinjau. Kalau disetujui, total '
                  'pesanan akan dikembalikan ke Saldo Refund.',
                  style: TextStyle(
                    color: Color(0xFF78350F),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                  ),
                ),
                if (reason != null && reason!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Alasan kamu: "${reason!}"',
                      style: const TextStyle(
                        color: Color(0xFF422006),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
                if (requestedAt != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Diajukan ${_formatTime(requestedAt!)}',
                    style: const TextStyle(
                      color: Color(0xFFB45309),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Banner "Permintaan Pembatalan Ditolak". Muncul kalau request user
/// di-reject admin. Tombol cancel akan muncul kembali (_canCancelOrder
/// allow PENDING/PAID/PROCESSING tanpa cek rejected) supaya user bisa
/// re-submit kalau perlu.
class _CancellationRejectedBanner extends StatelessWidget {
  final String? userReason;
  final String? rejectReason;
  final DateTime? respondedAt;

  const _CancellationRejectedBanner({
    required this.userReason,
    required this.rejectReason,
    required this.respondedAt,
  });

  String _formatTime(DateTime dt) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Agt', 'Sep', 'Okt', 'Nov', 'Des',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}, '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFCA5A5), width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.block_rounded,
              color: Color(0xFFB91C1C),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Permintaan pembatalan ditolak',
                  style: TextStyle(
                    color: Color(0xFF7F1D1D),
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (rejectReason != null && rejectReason!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Alasan admin: "${rejectReason!}"',
                      style: const TextStyle(
                        color: Color(0xFF7F1D1D),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
                if (userReason != null && userReason!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Alasan kamu sebelumnya: "${userReason!}"',
                    style: const TextStyle(
                      color: Color(0xFF991B1B),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                ],
                if (respondedAt != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Ditolak ${_formatTime(respondedAt!)}',
                    style: const TextStyle(
                      color: Color(0xFFB91C1C),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
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

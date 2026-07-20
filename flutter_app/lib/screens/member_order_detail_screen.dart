import 'dart:async';

import 'package:flutter/material.dart';
import '../theme/natalo_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
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
import '../utils/order_chat_context.dart';
import '../utils/payment_url_policy.dart';
import '../widgets/app_chat_button.dart';
import '../widgets/app_product_image.dart';
import '../widgets/app_toast.dart';
import '../widgets/app_ui.dart';
import '../widgets/natalo_paw_refresh_indicator.dart';
import '../widgets/order_tracking_timeline.dart';

const _brandBlue = NataloColors.primary;
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
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Voucher atau promo yang dipakai akan dibebaskan dan stok '
              'produk dikembalikan. Aksi ini tidak bisa dibatalkan.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
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
      // Kind-inference: dynamic message dari try-block pembatalan berhasil —
      // tidak semua cabang mengandung literal "berhasil", tapi context-nya
      // selalu hasil pembatalan sukses (order dibatalkan / permintaan
      // terkirim) → kind: success.
      AppToast.showBanner(context, message, kind: ToastKind.success);
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst('Exception: ', '');
      AppToast.showBanner(
        context,
        'Pembatalan gagal: $message',
        kind: ToastKind.error,
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
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Konfirmasi pesanan sudah sampai dan kondisinya OK. Setelah ini, '
              'pesanan akan ditandai selesai dan window komplain/refund akan '
              'tutup.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Kalau ada masalah dengan paket, jangan tap dulu — hubungi admin '
              'via WhatsApp.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
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
      // Kind-inference: dynamic message dari try-block konfirmasi diterima
      // berhasil — context-nya selalu sukses → kind: success.
      AppToast.showBanner(
        context,
        result.alreadyConfirmed
            ? 'Pesanan sudah ditandai selesai.'
            : result.message,
        kind: ToastKind.success,
      );
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst('Exception: ', '');
      AppToast.showBanner(
        context,
        'Konfirmasi gagal: $message',
        kind: ToastKind.error,
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
      AppToast.showBanner(
        context,
        'Beli lagi gagal: $message',
        kind: ToastKind.error,
      );
    } finally {
      if (mounted) setState(() => _reordering = false);
    }
  }

  List<OrderItemSummary> _pendingReviewItems(OrderSummary order) => order.items
      .where((item) => !item.reviewed && item.id.trim().isNotEmpty)
      .toList(growable: false);

  bool _isCompleted(OrderSummary order) {
    final status = order.status.toUpperCase();
    return status == 'DELIVERED' || status == 'COMPLETED';
  }

  Future<void> _openReviews(OrderSummary order) async {
    final pending = _pendingReviewItems(order);
    await Navigator.pushNamed(
      context,
      '/member/reviews',
      arguments: {
        if (pending.length == 1) 'orderItemId': pending.first.id,
        'orderNumber': order.orderNumber,
        'isSelfPickup': order.isSelfPickup,
      },
    );
    if (mounted) await _refreshOrder();
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
            // SizedBox 12: jarak tepi kanan (ikon shrinkWrap mepet tepi).
            actions: [
              AppChatButton(
                routeArguments: buildOrderChatContext(order),
                tooltip: 'Chat tentang pesanan ini',
              ),
              const SizedBox(width: 12),
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
                  timelineEvents: order.timelineEvents,
                  readyForPickupAt: order.readyForPickupAt,
                  pickedUpAt: order.pickedUpAt,
                  shippedAt: order.shippedAt,
                  deliveredAt: order.deliveredAt ?? order.completedAt,
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
          bottomNavigationBar: _OrderBottomActions(
            order: order,
            reordering: _reordering,
            pendingReviewCount: _pendingReviewItems(order).length,
            completed: _isCompleted(order),
            onReview: () => _openReviews(order),
            onBuyAgain: () => _buyAgain(context, order),
          ),
        );
      },
    );
  }
}

class _OrderBottomActions extends StatelessWidget {
  final OrderSummary order;
  final bool reordering;
  final int pendingReviewCount;
  final bool completed;
  final VoidCallback onReview;
  final VoidCallback onBuyAgain;

  const _OrderBottomActions({
    required this.order,
    required this.reordering,
    required this.pendingReviewCount,
    required this.completed,
    required this.onReview,
    required this.onBuyAgain,
  });

  @override
  Widget build(BuildContext context) {
    final canReorder = order.items.isNotEmpty && !reordering;
    return AppGlassBottomBar(
      child: Row(
        children: [
          if (completed && pendingReviewCount > 0) ...[
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('order-review-cta'),
                onPressed: onReview,
                icon: const Icon(Icons.rate_review_outlined),
                label: Text(
                  pendingReviewCount == 1
                      ? 'Beri Ulasan'
                      : 'Ulas $pendingReviewCount Produk',
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(borderRadius: AppRadius.large),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: ElevatedButton.icon(
              key: const ValueKey('order-reorder-cta'),
              onPressed: canReorder ? onBuyAgain : null,
              icon: reordering
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.replay_rounded),
              label: Text(reordering ? 'Memproses' : 'Beli Lagi'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(borderRadius: AppRadius.large),
              ),
            ),
          ),
        ],
      ),
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
    if (uri == null ||
        !PaymentUrlPolicy.isValidMidtransPaymentUrl(paymentUrl)) {
      // Kind-inference: "tidak valid" tidak literal match keyword "tidak
      // bisa", tapi context-nya link diblokir/gagal terbuka → error.
      _showSnack(
        context,
        'Link pembayaran tidak valid atau tidak tepercaya.',
        kind: ToastKind.error,
      );
      return;
    }

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!context.mounted) return;
    if (!opened) {
      _showSnack(context, 'Tidak bisa membuka pembayaran.',
          kind: ToastKind.error);
    }
  }

  Future<void> _copy(BuildContext context, String value, String message) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    // Semua caller _copy mengirim pesan "... tersalin." → success.
    _showSnack(context, message, kind: ToastKind.success);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (order.paymentProvider.toUpperCase() == 'MIDTRANS') {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: cs.outlineVariant),
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
    final hasProof = _hasActivePaymentProof(order);
    final deadline = order.paymentDeadline;
    final expired =
        !hasProof && deadline != null && DateTime.now().isAfter(deadline);
    // Instruksi transfer hanya relevan saat order masih aktif menunggu
    // bayar (belum upload bukti & belum lewat deadline). Setelah bukti
    // masuk → tampil "menunggu verifikasi"; setelah expired → tampil
    // "batas waktu habis". Menyembunyikan instruksi mencegah user transfer
    // ulang (double bayar) atau transfer ke order yang sudah hangus.
    final showInstructions = !hasProof && !expired;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant),
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
          // Status: countdown bayar / menunggu verifikasi / kadaluarsa.
          _ManualPaymentBanner(deadline: deadline, hasProof: hasProof),
          if (showInstructions) ...[
            const SizedBox(height: 14),
            // Badge bank — chip teks berwarna (tanpa aset logo).
            _BankBadge(name: bank.bankName),
            const SizedBox(height: 12),
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
            const SizedBox(height: 16),
            _BcaTransferSteps(
              accountNumber: bank.accountNumber,
              accountName: bank.accountName,
              totalTransfer: totalTransfer,
            ),
          ],
        ],
      ),
    );
  }
}

/// Banner status pembayaran manual — 3 state:
///  - belum bayar  → countdown "Bayar dalam HH:MM:SS" (amber, < 1 jam jadi
///    merah urgensi)
///  - sudah upload bukti → "Menunggu verifikasi" (biru, no timer)
///  - lewat deadline → "Batas waktu habis" (abu)
/// Ticker 1 detik hanya jalan saat countdown aktif. Warna pakai tint-alpha
/// dari warna semantik supaya kebaca di light & dark theme (bukan bg terang
/// hardcoded).
class _ManualPaymentBanner extends StatefulWidget {
  final DateTime? deadline;
  final bool hasProof;

  const _ManualPaymentBanner({required this.deadline, required this.hasProof});

  @override
  State<_ManualPaymentBanner> createState() => _ManualPaymentBannerState();
}

class _ManualPaymentBannerState extends State<_ManualPaymentBanner> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Ticker hanya perlu saat ada countdown aktif (belum bukti + ada
    // deadline). Tidak boot timer kalau cuma tampil banner statis.
    if (!widget.hasProof && widget.deadline != null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.hasProof) {
      return _banner(
        accent: const Color(0xFF2563EB),
        icon: Icons.hourglass_top_rounded,
        title: 'Bukti terkirim — menunggu verifikasi',
        subtitle: 'Admin akan cek pembayaranmu. Biasanya beberapa menit.',
      );
    }
    final deadline = widget.deadline;
    if (deadline == null) return const SizedBox.shrink();
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      return _banner(
        accent: const Color(0xFF6B7280),
        icon: Icons.timer_off_rounded,
        title: 'Batas waktu bayar habis',
        subtitle: 'Pesanan akan dibatalkan otomatis. Silakan pesan lagi.',
      );
    }
    final urgent = remaining.inMinutes < 60;
    return _banner(
      accent: urgent ? const Color(0xFFDC2626) : const Color(0xFFB45309),
      icon: Icons.timer_outlined,
      title: 'Bayar dalam ${_fmt(remaining)}',
      subtitle: urgent
          ? 'Segera selesaikan sebelum pesanan dibatalkan otomatis.'
          : 'Selesaikan transfer sebelum batas waktu agar pesanan tidak batal.',
      mono: true,
    );
  }

  Widget _banner({
    required Color accent,
    required IconData icon,
    required String title,
    required String subtitle,
    bool mono = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w900,
                    fontSize: mono ? 17 : 14.5,
                    fontFeatures:
                        mono ? const [FontFeature.tabularFigures()] : null,
                    letterSpacing: mono ? 0.5 : 0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    fontSize: 11.5,
                    height: 1.3,
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

/// Chip teks bank (tanpa aset logo) — keputusan desain: badge teks berwarna.
class _BankBadge extends StatelessWidget {
  final String name;
  const _BankBadge({required this.name});

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF1D4ED8);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.30)),
      ),
      child: Text(
        name,
        style: const TextStyle(
          color: accent,
          fontWeight: FontWeight.w900,
          fontSize: 13,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Langkah transfer m-BCA (ringkas, channel paling umum). Numbered list
/// dengan nominal + rekening inline supaya user tidak bolak-balik scroll.
class _BcaTransferSteps extends StatelessWidget {
  final String accountNumber;
  final String accountName;
  final double totalTransfer;

  const _BcaTransferSteps({
    required this.accountNumber,
    required this.accountName,
    required this.totalTransfer,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final steps = <String>[
      'Buka aplikasi BCA mobile, login dengan kode akses.',
      'Pilih m-Transfer → Transfer ke BCA.',
      'Masukkan nomor rekening $accountNumber (bisa salin di atas).',
      'Masukkan nominal PERSIS ${formatRupiah(totalTransfer)} — jangan dibulatkan.',
      'Pastikan nama penerima $accountName, lalu konfirmasi.',
      'Simpan bukti transfer, lalu upload di kartu "Bukti Transfer" di bawah.',
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.format_list_numbered_rounded,
                  size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(
                'Cara bayar via BCA mobile',
                style: TextStyle(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w900,
                  fontSize: 13.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _brandBlue.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      color: _brandBlue,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      steps[i],
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
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

/// Thumbnail bukti transfer ter-upload — tap untuk lihat full-screen
/// (pinch-zoom). Tampil read-only; ganti bukti lewat tombol "Ganti Bukti".
class _ProofThumbnail extends StatelessWidget {
  final String url;
  const _ProofThumbnail({required this.url});

  void _openFull(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.of(ctx).pop(),
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Center(
                child: Image.network(url, fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: 44,
              right: 16,
              child: IconButton(
                onPressed: () => Navigator.of(ctx).pop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => _openFull(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: Container(
                width: double.infinity,
                color: cs.surfaceContainerHighest,
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  height: 180,
                  width: double.infinity,
                  loadingBuilder: (ctx, child, progress) => progress == null
                      ? child
                      : const SizedBox(
                          height: 180,
                          child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                  errorBuilder: (ctx, _, __) => SizedBox(
                    height: 180,
                    child: Center(
                      child: Icon(Icons.broken_image_outlined,
                          color: cs.onSurfaceVariant),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.zoom_in_rounded, color: Colors.white, size: 14),
                    SizedBox(width: 4),
                    Text(
                      'Lihat',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
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

  bool get _hasStoredProof =>
      (_proofUrl?.isNotEmpty ?? false) ||
      (widget.order.paymentProofUrl?.isNotEmpty ?? false);

  String get _proofStatus {
    if (_proofUrl?.isNotEmpty ?? false) return 'PENDING_REVIEW';
    final status = widget.order.paymentProofStatus?.trim().toUpperCase();
    if (status != null && status.isNotEmpty) return status;
    return _hasStoredProof ? 'PENDING_REVIEW' : 'NOT_UPLOADED';
  }

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
      AppToast.showBanner(
        context,
        'Bukti transfer berhasil dikirim.',
        kind: ToastKind.success,
      );
    } catch (_) {
      if (!mounted) return;
      // Kind-inference: literal substring "berhasil" muncul di "belum
      // berhasil" (negasi), tapi ini catch-block kegagalan upload → error.
      AppToast.showBanner(
        context,
        'Bukti belum berhasil diunggah. Periksa koneksi lalu coba lagi.',
        kind: ToastKind.error,
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _openChat() {
    final contextData = buildOrderChatContext(widget.order);
    final orderData = contextData['order'] as Map<String, dynamic>;
    if (_proofUrl?.isNotEmpty ?? false) {
      orderData['hasPaymentProof'] = true;
      orderData['paymentProofStatus'] = 'PENDING_REVIEW';
    }
    Navigator.pushNamed(context, '/chat', arguments: contextData);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final proofRejected = _proofStatus == 'REJECTED';
    final proofVerified = _proofStatus == 'VERIFIED';
    final hasActiveProof = _hasStoredProof && !proofRejected;
    final statusColor = proofRejected
        ? const Color(0xFFDC2626)
        : hasActiveProof
            ? const Color(0xFF16A34A)
            : const Color(0xFFF59E0B);
    final title = proofRejected
        ? 'Bukti Perlu Diperbarui'
        : proofVerified
            ? 'Pembayaran Terverifikasi'
            : hasActiveProof
                ? 'Menunggu Verifikasi'
                : 'Bukti Transfer';
    final subtitle = proofRejected
        ? 'Upload ulang bukti transfer yang lebih jelas atau sesuai.'
        : proofVerified
            ? 'Bukti pembayaran sudah diperiksa admin.'
            : hasActiveProof
                ? 'Admin akan mengecek pembayaran manual.'
                : 'Upload foto bukti pembayaran manual.';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant),
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
                icon: proofRejected
                    ? Icons.error_outline_rounded
                    : hasActiveProof
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
                      title,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Preview thumbnail bukti yang sudah di-upload — tap untuk lihat
          // full-screen. Sebelumnya user cuma dapat flag boolean tanpa bisa
          // memastikan foto yang ke-upload benar/jelas.
          if (_hasStoredProof &&
              (_proofUrl ?? widget.order.paymentProofUrl) != null) ...[
            const SizedBox(height: 14),
            _ProofThumbnail(
              url: (_proofUrl ?? widget.order.paymentProofUrl)!,
            ),
          ],
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: _hasStoredProof
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: AppInfoBanner(
                      icon: proofRejected
                          ? Icons.error_outline_rounded
                          : Icons.check_circle_outline_rounded,
                      message: proofRejected
                          ? 'Bukti ditolak. Periksa kembali lalu upload bukti baru.'
                          : proofVerified
                              ? 'Bukti pembayaran sudah diverifikasi admin.'
                              : 'Bukti tersimpan dan sedang menunggu pemeriksaan admin.',
                      color: statusColor,
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
                        _hasStoredProof
                            ? Icons.refresh_rounded
                            : Icons.upload_file_rounded,
                      ),
                      label: Text(
                        proofRejected
                            ? 'Upload Ulang'
                            : _hasStoredProof
                                ? 'Ganti Bukti'
                                : 'Upload Bukti',
                      ),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        backgroundColor: _brandBlue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
          ),
          if (_hasStoredProof && !_uploading) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openChat,
                icon: const ChatDotsBubbleIcon(size: 19),
                label: const Text('Buka Chat'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  foregroundColor: _brandBlue,
                  side: const BorderSide(color: _brandBlue),
                ),
              ),
            ),
          ],
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

    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant),
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
              Expanded(
                child: Text(
                  'Ambil Sendiri di Toko',
                  style: TextStyle(
                    color: cs.onSurface,
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
      // Kind-inference: "tidak valid" → error (link diblokir/gagal parse).
      _showSnack(context, 'Link Google Maps tidak valid.',
          kind: ToastKind.error);
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!context.mounted || opened) return;
    _showSnack(context, 'Tidak bisa membuka Google Maps.',
        kind: ToastKind.error);
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
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF0B7FEA).withValues(alpha: 0.20)
                  : const Color(0xFFE8F4FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.verified_user_outlined,
              color: Color(0xFF0B83E6),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pesanan Anda sudah siap diambil.',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Harap ambil pesanan sesuai jam operasional toko.',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
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
              Clipboard.setData(ClipboardData(text: code));
              AppToast.showBanner(
                context,
                'Kode "$code" disalin ke clipboard.',
                kind: ToastKind.success,
                duration: const Duration(seconds: 2),
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
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                content,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
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
    final cs = Theme.of(context).colorScheme;
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
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
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
    final cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant),
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
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: TextStyle(
                    color: strong ? _brandBlue : cs.onSurface,
                    fontSize: strong ? 20 : 16,
                    fontWeight: FontWeight.w900,
                    fontFamily: monospace ? 'monospace' : null,
                  ),
                ),
                if (helper != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    helper!,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
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
                                  hasProof:
                                      (order.paymentProofUrl ?? '').isNotEmpty,
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
                        _showSnack(
                          context,
                          'Nomor pesanan tersalin.',
                          kind: ToastKind.success,
                        );
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
    final cs = Theme.of(context).colorScheme;
    final items = order.items;
    final canReviewOrder = order.status.toUpperCase() == 'DELIVERED';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant),
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Produk Pesanan',
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Item yang masuk dalam pesanan ini.',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
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
                color: Theme.of(context).brightness == Brightness.dark
                    ? cs.surfaceContainerHighest
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Text(
                'Item pesanan belum tersedia di response API.',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
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
        AppToast.showBanner(context, 'Produk sudah tidak tersedia.');
        return;
      }
      await Navigator.pushNamed(
        context,
        '/product-detail',
        arguments: product,
      );
    } catch (_) {
      if (!mounted) return;
      AppToast.showBanner(
        context,
        'Gagal buka detail produk. Coba lagi.',
        kind: ToastKind.error,
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
    final cs = Theme.of(context).colorScheme;
    final subtotal = item.price * item.quantity;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _navigating ? null : _openProductDetail,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? cs.surfaceContainerHighest
                : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Theme.of(context).brightness == Brightness.dark
                  ? cs.outlineVariant
                  : const Color(0xFFE7EEF7),
            ),
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
                          style: TextStyle(
                            color: cs.onSurface,
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
                              label:
                                  item.variantLabel ?? item.categoryName ?? '',
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
                                style: TextStyle(
                                  color: cs.onSurfaceVariant,
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
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: AppStatusPill(
                          label: item.reviewed
                              ? 'Sudah direview'
                              : 'Menunggu review',
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
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: cs.onSurfaceVariant),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cs.onSurfaceVariant,
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
    final cs = Theme.of(context).colorScheme;
    final subtotal = order.subtotal > 0 ? order.subtotal : order.total;
    // Ongkir asli sebelum dipotong voucher gratis ongkir. shippingCost yang
    // disimpan sudah NET (hasil akhir setelah potongan), jadi ongkir asli =
    // net + shippingDiscount — dipakai untuk tampilan dicoret.
    final originalShipping = order.shippingCost + order.shippingDiscount;
    // Total Diskon = potongan scope PRODUK (termasuk loyalty). Diskon ongkir
    // sengaja TIDAK dijumlahkan di sini karena sudah tercermin di baris Ongkir
    // (dicoret) — kalau ikut, potongannya kehitung dobel. Fallback: order
    // legacy tanpa split productDiscount → pakai aggregate `discount` dikurangi
    // porsi ongkir.
    final productDiscountTotal = order.productDiscount > 0
        ? order.productDiscount
        : (order.discount - order.shippingDiscount)
            .clamp(0, double.infinity)
            .toDouble();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant),
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
          // Ongkir — kalau ada potongan voucher gratis ongkir, tampilkan
          // ongkir asli dicoret + hasil akhir ("GRATIS" bila 0, atau sisa yang
          // tetap dibayar bila voucher punya batas maks).
          _OngkirLine(
            originalShipping: originalShipping,
            shippingCost: order.shippingCost,
            hasDiscount: order.shippingDiscount > 0,
          ),
          // Total Diskon — satu baris ringkas potongan produk (termasuk
          // loyalty). Rincian per-voucher (produk, loyalty, gratis ongkir)
          // ada di kotak "Voucher Digunakan" di bawah, jadi baris diskon
          // per-kategori tidak diulang di sini (menghindari info dobel).
          if (productDiscountTotal > 0)
            _SummaryLine(
              label: 'Total Diskon',
              value: '-${formatRupiah(productDiscountTotal)}',
              valueColor: const Color(0xFFDC2626),
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
  final Color? valueColor;

  const _SummaryLine({
    required this.label,
    required this.value,
    this.strong = false,
    this.bottomPadding = 8,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: strong ? cs.onSurface : cs.onSurfaceVariant,
                fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? (strong ? _brandBlue : cs.onSurface),
              fontWeight: FontWeight.w900,
              fontSize: strong ? 18 : 14,
            ),
          ),
        ],
      ),
    );
  }
}

/// Baris Ongkir dengan dukungan tampilan potongan voucher gratis ongkir.
/// - Tanpa diskon ongkir: tampil nominal ongkir biasa.
/// - Ada diskon + ongkir jadi 0: ongkir asli dicoret + label hijau "GRATIS".
/// - Ada diskon tapi masih sisa (voucher punya batas maks): ongkir asli
///   dicoret + nominal sisa yang tetap dibayar.
class _OngkirLine extends StatelessWidget {
  final double originalShipping;
  final double shippingCost;
  final bool hasDiscount;

  const _OngkirLine({
    required this.originalShipping,
    required this.shippingCost,
    required this.hasDiscount,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isFree = shippingCost <= 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Ongkir',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (!hasDiscount)
            Text(
              formatRupiah(shippingCost),
              style: TextStyle(
                color: cs.onSurface,
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            )
          else ...[
            Text(
              formatRupiah(originalShipping),
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                fontSize: 13,
                decoration: TextDecoration.lineThrough,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              isFree ? 'GRATIS' : formatRupiah(shippingCost),
              style: TextStyle(
                color: isFree ? const Color(0xFF059669) : cs.onSurface,
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            ),
          ],
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

bool _hasActivePaymentProof(OrderSummary order) {
  final hasUrl = (order.paymentProofUrl ?? '').trim().isNotEmpty;
  if (!hasUrl) return false;
  return order.paymentProofStatus?.trim().toUpperCase() != 'REJECTED';
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
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant),
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Mau batalkan pesanan?',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Bisa dibatalkan sebelum paket dikirim.',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
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
    final hasResi =
        order.trackingNumber != null && order.trackingNumber!.trim().isNotEmpty;
    final hasDriver = order.shippingDriverInfo != null &&
        order.shippingDriverInfo!.trim().isNotEmpty;
    final courierLabel = order.courierService ?? order.courierCode ?? 'Kurir';
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant),
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
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF0B7FEA).withValues(alpha: 0.20)
                      : const Color(0xFFEAF2FF),
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
                    Text(
                      'Info Pengiriman',
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      hasDriver
                          ? '$courierLabel · Same-day delivery'
                          : courierLabel,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
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
                color: Theme.of(context).brightness == Brightness.dark
                    ? cs.surfaceContainerHighest
                    : const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Nomor Resi',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    order.trackingNumber!,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            )
          else if (hasDriver) ...[
            Text(
              'Info Driver',
              style: TextStyle(
                color: cs.onSurfaceVariant,
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
                color: Theme.of(context).brightness == Brightness.dark
                    ? cs.surfaceContainerHighest
                    : const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outlineVariant),
              ),
              // SelectableText supaya user bisa copy nomor HP / link GPS.
              child: SelectableText(
                order.shippingDriverInfo!,
                style: TextStyle(
                  color: cs.onSurface,
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
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agt',
      'Sep',
      'Okt',
      'Nov',
      'Des',
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
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agt',
      'Sep',
      'Okt',
      'Nov',
      'Des',
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
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agt',
      'Sep',
      'Okt',
      'Nov',
      'Des',
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

void _showSnack(
  BuildContext context,
  String message, {
  ToastKind kind = ToastKind.info,
}) {
  AppToast.showBanner(context, message, kind: kind);
}

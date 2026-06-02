import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/natalo_store_config.dart';
import '../models/member_profile.dart';
import '../services/home_widget_service.dart';
import '../services/member_service.dart';
import '../services/order_service.dart';
import '../state/cart_store.dart';
import '../state/member_store.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import '../widgets/app_product_image.dart';
import '../widgets/app_toast.dart';
import '../widgets/app_ui.dart';
import '../widgets/natalo_paw_refresh_indicator.dart';

const _brandBlue = Color(0xFF0B7FEA);

enum _OrderFilter {
  all('Semua'),
  unpaid('Belum Bayar'),
  processing('Diproses'),
  shipped('Dikirim'),
  delivered('Selesai'),
  cancelled('Dibatalkan');

  final String label;

  const _OrderFilter(this.label);

  static _OrderFilter fromRouteArgument(Object? argument) {
    final value = argument?.toString().trim().toLowerCase();
    return switch (value) {
      'unpaid' || 'belum_bayar' || 'belum-bayar' => _OrderFilter.unpaid,
      'processing' || 'diproses' => _OrderFilter.processing,
      'shipped' || 'dikirim' => _OrderFilter.shipped,
      'delivered' || 'selesai' || 'completed' => _OrderFilter.delivered,
      'cancelled' || 'canceled' || 'dibatalkan' => _OrderFilter.cancelled,
      _ => _OrderFilter.all,
    };
  }
}

class MemberOrdersScreen extends StatefulWidget {
  final Object? initialFilterArgument;

  const MemberOrdersScreen({
    super.key,
    this.initialFilterArgument,
  });

  @override
  State<MemberOrdersScreen> createState() => _MemberOrdersScreenState();
}

class _MemberOrdersScreenState extends State<MemberOrdersScreen> {
  late Future<List<OrderSummary>> _ordersFuture;
  late _OrderFilter _selectedFilter;

  @override
  void initState() {
    super.initState();
    _selectedFilter =
        _OrderFilter.fromRouteArgument(widget.initialFilterArgument);
    _ordersFuture = _loadOrders();
  }

  Future<List<OrderSummary>> _loadOrders() async {
    if (!memberStore.isLoggedIn) return [];
    // Sengaja TIDAK try-catch — biar exception bubble ke FutureBuilder
    // (snapshot.hasError) → render AppErrorState dengan retry button.
    // Sebelum perbaikan: silent catch return [] bikin user lihat "Belum
    // ada pesanan" padahal sebenarnya network error (confusing UX).
    final orders = await memberService.fetchOrders();
    // Sync most-recent order ke Android home widget (silent no-op iOS).
    if (orders.isNotEmpty) {
      AppHomeWidgetService.updateLastOrder(orders.first);
    } else {
      AppHomeWidgetService.updateLastOrder(null);
    }
    return orders;
  }

  Future<void> _refresh() async {
    setState(() => _ordersFuture = _loadOrders());
    await _ordersFuture;
  }

  List<OrderSummary> _filterOrders(List<OrderSummary> orders) {
    return orders.where(_matchesSelectedFilter).toList();
  }

  bool _matchesSelectedFilter(OrderSummary order) {
    final status = order.status.toUpperCase();
    final payment = order.paymentStatus.toUpperCase();

    // BUG FIX: order CANCELLED tetap punya paymentStatus UNPAID/PENDING
    // (karena tidak pernah dibayar). Tanpa explicit exclude, filter
    // "Belum Bayar" ikut match order dibatalkan → duplicate di 2 tab.
    final isFinalized = status == 'CANCELLED' || status == 'REFUNDED';

    return switch (_selectedFilter) {
      _OrderFilter.all => true,
      _OrderFilter.unpaid => !isFinalized &&
          (status == 'PENDING' ||
              status == 'UNPAID' ||
              payment == 'UNPAID' ||
              payment == 'PENDING'),
      _OrderFilter.processing => status == 'PROCESSING' || status == 'PAID',
      _OrderFilter.shipped => status == 'SHIPPED',
      _OrderFilter.delivered => status == 'DELIVERED',
      _OrderFilter.cancelled => status == 'CANCELLED',
    };
  }

  @override
  Widget build(BuildContext context) {
    if (!memberStore.isLoggedIn) {
      return const _LoginRequiredScaffold(title: 'Pesanan Saya');
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Pesanan Saya'),
        actions: [
          IconButton(
            onPressed: () => Navigator.pushNamed(context, '/notifications'),
            icon: const Icon(Icons.notifications_none_rounded),
            tooltip: 'Notifikasi',
          ),
          IconButton(
            onPressed: () => Navigator.pushNamed(context, '/cart'),
            icon: const Icon(Icons.shopping_cart_outlined),
            tooltip: 'Keranjang',
          ),
        ],
      ),
      body: FutureBuilder<List<OrderSummary>>(
        future: _ordersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return Column(
              children: [
                _OrderFilterTabs(
                  selected: _selectedFilter,
                  onChanged: (filter) =>
                      setState(() => _selectedFilter = filter),
                ),
                const Expanded(child: AppSkeletonList(itemCount: 5)),
              ],
            );
          }

          // Error state — network down / server 5xx. Sebelum perbaikan
          // silent-catch, kasus ini render "Belum ada pesanan" (confusing).
          // Sekarang user dapat retry button yang jelas.
          if (snapshot.hasError) {
            return Column(
              children: [
                _OrderFilterTabs(
                  selected: _selectedFilter,
                  onChanged: (filter) =>
                      setState(() => _selectedFilter = filter),
                ),
                Expanded(
                  child: AppErrorState(
                    variant: AppErrorVariant.network,
                    title: 'Gagal memuat pesanan',
                    description:
                        'Periksa koneksi internet kamu lalu coba lagi.',
                    onRetry: _refresh,
                  ),
                ),
              ],
            );
          }

          final orders = snapshot.data ?? [];
          final filteredOrders = _filterOrders(orders);
          final content = orders.isEmpty
              ? _EmptyOrdersState(onRefresh: _refresh)
              : filteredOrders.isEmpty
                  ? _FilteredOrdersEmptyState(
                      filter: _selectedFilter,
                      onRefresh: _refresh,
                    )
                  : NataloPawRefreshIndicator(
                      onRefresh: _refresh,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                        itemCount: filteredOrders.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) => _OrderCard(
                          order: filteredOrders[index],
                          index: index,
                          onRefresh: _refresh,
                        ),
                      ),
                    );

          return Column(
            children: [
              _OrderFilterTabs(
                selected: _selectedFilter,
                onChanged: (filter) => setState(() => _selectedFilter = filter),
              ),
              Expanded(child: content),
            ],
          );
        },
      ),
    );
  }
}

class _OrderFilterTabs extends StatelessWidget {
  final _OrderFilter selected;
  final ValueChanged<_OrderFilter> onChanged;

  const _OrderFilterTabs({
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        bottom: false,
        child: SizedBox(
          height: 52,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _OrderFilter.values.length,
            separatorBuilder: (_, __) => const SizedBox(width: 18),
            itemBuilder: (context, index) {
              final filter = _OrderFilter.values[index];
              final active = selected == filter;

              return InkWell(
                onTap: () => onChanged(filter),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.only(top: 15),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        filter.label,
                        style: TextStyle(
                          color: active ? _brandBlue : cs.onSurfaceVariant,
                          fontSize: 14,
                          fontWeight:
                              active ? FontWeight.w900 : FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        height: 3,
                        width: active ? 52 : 0,
                        decoration: BoxDecoration(
                          color: _brandBlue,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LoginRequiredScaffold extends StatelessWidget {
  final String title;

  const _LoginRequiredScaffold({required this.title});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 76,
                width: 76,
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF0B7FEA).withValues(alpha: 0.20)
                      : const Color(0xFFEAF5FF),
                  borderRadius: BorderRadius.circular(26),
                ),
                child: const Icon(
                  Icons.lock_outline_rounded,
                  color: _brandBlue,
                  size: 36,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Login member diperlukan',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Masuk untuk melihat data terbaru dari akun Natalo kamu.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: () => Navigator.pushNamed(context, '/member/login'),
                child: const Text('Masuk Member'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderCard extends StatefulWidget {
  final OrderSummary order;
  final int index;

  /// Callback untuk re-fetch list dari parent setelah action yang ubah
  /// status (mis. konfirmasi terima → DELIVERED). Tanpa ini, card stuck
  /// nampilin status lama sampai user refresh manual.
  final Future<void> Function() onRefresh;

  const _OrderCard({
    required this.order,
    required this.index,
    required this.onRefresh,
  });

  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard> {
  bool _confirming = false;
  bool _cancelling = false;

  OrderSummary get order => widget.order;
  int get index => widget.index;

  Future<void> _openOrderDetail(BuildContext context) async {
    // Await — user mungkin upload bukti transfer / batalkan di detail.
    // Saat balik, refresh list supaya badge + tombol ikut update
    // (mis. "Belum Bayar/Bayar Sekarang" → "Menunggu Verifikasi" setelah
    // bukti diupload). Tanpa ini list stale, gejala yang dilaporkan user.
    await Navigator.pushNamed(
      context,
      '/member/order-detail',
      arguments: order,
    );
    if (mounted) await widget.onRefresh();
  }

  Future<void> _openPayment(BuildContext context) async {
    final paymentUrl = order.paymentUrl;
    if (paymentUrl == null || paymentUrl.isEmpty) {
      _openOrderDetail(context);
      return;
    }

    final uri = Uri.tryParse(paymentUrl);
    if (uri == null) {
      _showSnack(context, 'Link pembayaran tidak valid.');
      return;
    }

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!context.mounted) return;
    if (!opened) _showSnack(context, 'Tidak bisa membuka pembayaran.');
  }

  /// Beli Lagi handler — unified pakai backend reorder endpoint.
  ///
  /// Sebelumnya pattern ini client-side: fetch products + manual stock
  /// check + variant matching. Banyak edge case bug (mis. stok 0 untuk
  /// produk yang sebenarnya tersedia). Detail Pesanan screen pakai
  /// backend reorder dan WORKS, jadi kita unify ke pattern yang sama
  /// — single source of truth + auto-fix bug.
  ///
  /// Backend handle: stock check, variant matching, partial fulfillment,
  /// friendly error message (lihat lib/reorder.ts).
  Future<void> _buyAgain(BuildContext context) async {
    if (order.items.isEmpty) {
      _openOrderDetail(context);
      return;
    }

    try {
      final result = await orderService.reorder(
        orderNumber: order.orderNumber,
      );
      if (!context.mounted) return;

      if (result.items.isEmpty) {
        // Semua item skipped — pakai friendly message dari backend.
        final reasons = result.skippedReasons;
        final message = reasons.isEmpty
            ? 'Tidak ada item yang bisa dibeli lagi.'
            : reasons.length == 1
                ? reasons.first
                : '${reasons.length} produk tidak bisa dibeli lagi (stok habis / tidak tersedia).';
        _showSnack(context, message);
        return;
      }

      for (final item in result.items) {
        cartStore.addProduct(item.product, quantity: item.quantity);
      }
      await cartStore.syncToServer();
      if (!context.mounted) return;

      final message = result.hasPartialChanges
          ? 'Sebagian produk masuk keranjang. Ada yang stok habis.'
          : 'Produk masuk keranjang';
      AppToast.showCartAdded(
        context,
        message,
        onTap: () => Navigator.pushNamed(context, '/cart'),
      );
    } catch (error) {
      if (!context.mounted) return;
      final message = error.toString().replaceFirst('Exception: ', '');
      _showSnack(context, 'Beli lagi gagal: $message');
    }
  }

  Future<void> _copyOrderNumber(BuildContext context) async {
    AppHaptics.tap();
    await Clipboard.setData(ClipboardData(text: order.orderNumber));
    if (!context.mounted) return;
    AppToast.show(context, 'Nomor pesanan disalin.');
  }

  Future<void> _copyTrackingNumber(BuildContext context) async {
    final tracking = order.trackingNumber?.trim();
    if (tracking == null || tracking.isEmpty) return;
    AppHaptics.tap();
    await Clipboard.setData(ClipboardData(text: tracking));
    if (!context.mounted) return;
    AppToast.show(context, 'Nomor resi disalin.');
  }

  Future<void> _openOrderHelp(BuildContext context) async {
    AppHaptics.tap();
    final uri = NataloStoreConfig.whatsappUri(
      message:
          'Halo Natalo, saya butuh bantuan untuk pesanan ${order.orderNumber}.',
    );
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!context.mounted) return;
    if (!opened) {
      AppToast.show(
        context,
        'Tidak bisa buka WhatsApp. Pastikan WhatsApp terpasang.',
        kind: ToastKind.error,
      );
    }
  }

  Future<void> _openTracking(BuildContext context) async {
    AppHaptics.tap();
    final trackingUrl = order.biteshipTrackingUrl?.trim();
    if (trackingUrl != null && trackingUrl.isNotEmpty) {
      final uri = Uri.tryParse(trackingUrl);
      if (uri != null) {
        final opened = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (!context.mounted) return;
        if (opened) return;
      }
    }
    if (!context.mounted) return;
    _openOrderDetail(context);
  }

  /// User konfirmasi paket sudah diterima (langsung dari list card,
  /// tidak harus drill ke detail dulu). Confirm dialog → POST endpoint
  /// → refresh list. Dialog dipakai supaya user tidak accidentally
  /// kehilangan window refund/komplain.
  Future<void> _confirmDelivered(BuildContext context) async {
    if (_confirming) return;
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
              'Konfirmasi pesanan sudah sampai dan kondisinya OK. '
              'Window komplain/refund akan tutup setelah ini.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Kalau ada masalah, jangan tap dulu — hubungi admin via WA.',
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
    if (confirmed != true || !mounted) return;

    setState(() => _confirming = true);
    try {
      final result =
          await orderService.confirmDelivered(orderNumber: order.orderNumber);
      if (!context.mounted) return;
      AppHaptics.success();
      // Refresh list dari parent supaya status card update ke DELIVERED
      // dan card pindah dari tab "Dikirim" ke tab "Selesai".
      await widget.onRefresh();
      if (!context.mounted) return;
      _showSnack(
        context,
        result.alreadyConfirmed
            ? 'Pesanan sudah ditandai selesai.'
            : result.message,
      );
    } catch (error) {
      if (!context.mounted) return;
      AppHaptics.warning();
      final message = error.toString().replaceFirst('Exception: ', '');
      _showSnack(context, 'Konfirmasi gagal: $message');
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  bool get _isFinalized {
    final status = order.status.toUpperCase();
    return status == 'CANCELLED' ||
        status == 'CANCELED' ||
        status == 'REFUNDED' ||
        status == 'EXPIRED';
  }

  bool get _isCancelled {
    final status = order.status.toUpperCase();
    return status == 'CANCELLED' || status == 'CANCELED';
  }

  bool get _isReorderable {
    final status = order.status.toUpperCase();
    return _isCancelled || status == 'DELIVERED' || status == 'COMPLETED';
  }

  bool get _canCancelOrder {
    final status = order.status.toUpperCase();
    if (status != 'PENDING' && status != 'PAID' && status != 'PROCESSING') {
      return false;
    }
    return !order.hasPendingCancellationRequest;
  }

  bool get _isUnpaid {
    if (_isFinalized) return false;
    // Order full saldo refund (total 0 + paid status) — TIDAK butuh
    // pembayaran. Defensive guard: kalau total === 0 dan paymentStatus
    // PAID, skip "Belum Bayar" detection (sudah lunas via saldo).
    if (order.total == 0 && order.paymentStatus.toUpperCase() == 'PAID') {
      return false;
    }
    final status = order.status.toUpperCase();
    final payment = order.paymentStatus.toUpperCase();

    return payment == 'UNPAID' || payment == 'PENDING' || status == 'PENDING';
  }

  /// User sudah upload bukti transfer (paymentProofUrl terisi). Untuk order
  /// manual, ini sinyal "Menunggu Verifikasi" — admin tinggal verifikasi.
  bool get _hasProof => (order.paymentProofUrl ?? '').trim().isNotEmpty;

  /// Order belum lunas TAPI bukti sudah diupload → tampil chip "Menunggu
  /// Verifikasi" (bukan tombol "Bayar Sekarang"). Kartu tetap tappable ke
  /// detail untuk upload ulang kalau bukti salah (tidak ada alur admin
  /// "tolak bukti", jadi recovery lewat re-upload / hubungi admin).
  bool get _isAwaitingVerification => _isUnpaid && _hasProof;

  /// Order yang udah SHIPPED + bukan self-pickup → user butuh konfirmasi
  /// "Sudah Diterima". Self-pickup tidak transit SHIPPED (PROCESSING →
  /// READY_FOR_PICKUP → DELIVERED via admin scan), jadi skip.
  bool get _needsDeliveryConfirmation {
    final status = order.status.toUpperCase();
    return status == 'SHIPPED' && !order.isSelfPickup;
  }

  bool get _isReadyForPickup {
    final status = order.status.toUpperCase();
    return status == 'READY_FOR_PICKUP' ||
        status == 'READY_TO_PICKUP' ||
        status == 'READY_PICKUP';
  }

  String? get _actionLabel {
    // Bukti sudah diupload → tidak ada tombol bayar; render chip
    // "Menunggu Verifikasi" terpisah (lihat build). Kartu tetap tappable.
    if (_isAwaitingVerification) return null;
    if (_isUnpaid) return 'Bayar Sekarang';
    if (_needsDeliveryConfirmation) return 'Sudah Diterima';
    if (_isReorderable) return 'Beli Lagi';
    return null;
  }

  /// Warna CTA button — hijau emerald untuk konfirmasi diterima (primary
  /// action di stage SHIPPED, beda dari blue brand untuk action lain).
  Color get _actionColor {
    if (_needsDeliveryConfirmation) return const Color(0xFF059669);
    return _brandBlue;
  }

  void _handleOrderAction(BuildContext context) {
    if (_isUnpaid) {
      _openPayment(context);
      return;
    }
    if (_needsDeliveryConfirmation) {
      _confirmDelivered(context);
      return;
    }
    if (_isReorderable) {
      _buyAgain(context);
    }
  }

  Future<void> _confirmCancelOrder(BuildContext context) async {
    if (_cancelling || !_canCancelOrder) return;
    final paid = order.paymentStatus.toUpperCase() == 'PAID';
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
            color: Color(0xFFDC2626),
            size: 28,
          ),
        ),
        title: Text(
          paid ? 'Ajukan pembatalan?' : 'Batalkan pesanan?',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        content: Text(
          paid
              ? 'Pesanan sudah dibayar. Pembatalan akan dikirim ke admin untuk disetujui dulu.'
              : 'Pesanan akan dibatalkan dan tidak akan diproses lagi.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Tidak'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            child: Text(paid ? 'Ajukan' : 'Batalkan'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _cancelling = true);
    try {
      final result = await orderService.cancelOrder(
        orderNumber: order.orderNumber,
        reason: 'Dibatalkan dari aplikasi oleh pelanggan.',
      );
      if (!context.mounted) return;
      AppHaptics.success();
      await widget.onRefresh();
      if (!context.mounted) return;
      final credited = result.totalCredited;
      final message = result.serverMessage ??
          (result.isRequested
              ? 'Permintaan pembatalan dikirim. Menunggu konfirmasi admin.'
              : credited > 0
                  ? 'Pesanan dibatalkan. Saldo refund ${formatRupiah(credited.toDouble())} masuk.'
                  : 'Pesanan dibatalkan.');
      _showSnack(context, message);
    } catch (error) {
      if (!context.mounted) return;
      AppHaptics.warning();
      final message = error.toString().replaceFirst('Exception: ', '');
      _showSnack(context, 'Pembatalan gagal: $message');
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  void _showOrderOptions(BuildContext context) {
    AppHaptics.tap();
    final actions = <_OrderQuickAction>[];
    final status = order.status.toUpperCase();
    final tracking = order.trackingNumber?.trim();

    if (_isUnpaid) {
      actions.add(
        _OrderQuickAction(
          icon: Icons.payment_rounded,
          title: 'Bayar sekarang',
          color: _brandBlue,
          onTap: () => _openPayment(context),
        ),
      );
    }
    if (_needsDeliveryConfirmation) {
      actions.add(
        _OrderQuickAction(
          icon: Icons.check_circle_outline_rounded,
          title: 'Sudah diterima',
          color: const Color(0xFF059669),
          onTap: () => _confirmDelivered(context),
        ),
      );
    }
    if (status == 'SHIPPED' || _isReadyForPickup) {
      actions.add(
        _OrderQuickAction(
          icon: Icons.local_shipping_outlined,
          title: order.isSelfPickup
              ? 'Lihat info pengambilan'
              : 'Lacak pengiriman',
          onTap: () => _openTracking(context),
        ),
      );
    }
    if (tracking != null && tracking.isNotEmpty) {
      actions.add(
        _OrderQuickAction(
          icon: Icons.confirmation_number_outlined,
          title: 'Salin nomor resi',
          onTap: () => _copyTrackingNumber(context),
        ),
      );
    }
    if (status == 'DELIVERED' || status == 'COMPLETED') {
      actions.add(
        _OrderQuickAction(
          icon: Icons.rate_review_outlined,
          title: 'Beri ulasan',
          onTap: () => Navigator.pushNamed(context, '/member/reviews'),
        ),
      );
    }
    if (_isReorderable) {
      actions.add(
        _OrderQuickAction(
          icon: Icons.shopping_bag_outlined,
          title: 'Beli lagi',
          color: _brandBlue,
          onTap: () => _buyAgain(context),
        ),
      );
    }
    if (_canCancelOrder) {
      final paid = order.paymentStatus.toUpperCase() == 'PAID';
      actions.add(
        _OrderQuickAction(
          icon: Icons.cancel_outlined,
          title: paid ? 'Ajukan pembatalan' : 'Batalkan pesanan',
          color: const Color(0xFFDC2626),
          onTap: () => _confirmCancelOrder(context),
        ),
      );
    }
    if (!_isFinalized) {
      actions.add(
        _OrderQuickAction(
          icon: Icons.chat_bubble_outline_rounded,
          title: 'Hubungi admin',
          onTap: () => _openOrderHelp(context),
        ),
      );
    }
    actions
      ..add(
        _OrderQuickAction(
          icon: Icons.copy_rounded,
          title: 'Salin nomor pesanan',
          onTap: () => _copyOrderNumber(context),
        ),
      )
      ..add(
        _OrderQuickAction(
          icon: Icons.receipt_long_outlined,
          title: 'Lihat detail pesanan',
          onTap: () => _openOrderDetail(context),
        ),
      );

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => _OrderOptionsSheet(
        order: order,
        actions: actions,
        onActionTap: (action) {
          Navigator.pop(sheetContext);
          action.onTap();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final statusColor = _statusColor(order.status);
    final actionLabel = _actionLabel;

    return AppAnimatedEntrance(
      index: index,
      child: Semantics(
        button: true,
        label: 'Buka detail pesanan ${order.orderNumber}',
        child: Container(
          decoration: _cardDecoration(),
          child: Material(
            color: cs.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(color: cs.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _openOrderDetail(context),
              borderRadius: BorderRadius.circular(24),
              splashColor: _brandBlue.withValues(alpha: 0.06),
              highlightColor: _brandBlue.withValues(alpha: 0.035),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            order.orderNumber,
                            style: TextStyle(
                              color: cs.onSurface,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        AppStatusPill(
                          label: _statusLabel(order.status),
                          color: statusColor,
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          onPressed: () => _showOrderOptions(context),
                          icon: const Icon(Icons.more_vert_rounded),
                          color: cs.onSurfaceVariant,
                          tooltip: 'Opsi pesanan',
                          constraints: const BoxConstraints(
                            minHeight: 34,
                            minWidth: 34,
                          ),
                          style: IconButton.styleFrom(
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_formatDate(order.createdAt)} • ${_displayItemCount(order)} item',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _OrderProductPreview(order: order),
                    const SizedBox(height: 12),
                    Divider(height: 1, color: cs.outlineVariant),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Total Belanja',
                                style: TextStyle(
                                  color: cs.onSurfaceVariant,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                formatRupiah(order.total),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _brandBlue,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              // Badge "💰 Saldo Refund Rp{X}" kalau order
                              // pakai saldo refund. Useful untuk user
                              // track penggunaan saldo + jelas kenapa
                              // total bisa Rp0 (tanpa badge ini confusing).
                              if (order.refundBalanceUsed > 0) ...[
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEAF2FF),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: const Color(0xFFBFDBFE),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.account_balance_wallet_rounded,
                                        size: 12,
                                        color: _brandBlue,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Saldo Refund ${formatRupiah(order.refundBalanceUsed)}',
                                        style: const TextStyle(
                                          color: _brandBlue,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (actionLabel != null) ...[
                          const SizedBox(width: 12),
                          ElevatedButton(
                            // Disable saat lagi proses konfirmasi terima.
                            onPressed: _confirming
                                ? null
                                : () => _handleOrderAction(context),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(0, 40),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              backgroundColor: _actionColor,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _confirming
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    actionLabel,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                          ),
                        ] else if (_isAwaitingVerification) ...[
                          // Bukti transfer sudah masuk → chip non-aktif
                          // "Menunggu Verifikasi" (ganti tombol Bayar
                          // Sekarang). Kartu tetap bisa di-tap ke detail
                          // untuk upload ulang kalau perlu.
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 9,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFFCD34D),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.schedule_rounded,
                                  size: 15,
                                  color: Color(0xFFB45309),
                                ),
                                SizedBox(width: 5),
                                Text(
                                  'Menunggu Verifikasi',
                                  style: TextStyle(
                                    color: Color(0xFFB45309),
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
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OrderQuickAction {
  final IconData icon;
  final String title;

  /// Null = neutral action → resolve ke cs.onSurface di tile (adaptif
  /// dark/light). Non-null = brand/semantic color (brandBlue, green, red).
  final Color? color;
  final VoidCallback onTap;

  const _OrderQuickAction({
    required this.icon,
    required this.title,
    required this.onTap,
    this.color,
  });
}

class _OrderOptionsSheet extends StatelessWidget {
  final OrderSummary order;
  final List<_OrderQuickAction> actions;
  final ValueChanged<_OrderQuickAction> onActionTap;

  const _OrderOptionsSheet({
    required this.order,
    required this.actions,
    required this.onActionTap,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF0B7FEA).withValues(alpha: 0.20)
                        : const Color(0xFFEAF5FF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.receipt_long_outlined,
                    color: _brandBlue,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.orderNumber,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _statusLabel(order.status),
                        style: TextStyle(
                          color: _statusColor(order.status),
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            for (final action in actions)
              _OrderQuickActionTile(
                action: action,
                onTap: () => onActionTap(action),
              ),
          ],
        ),
      ),
    );
  }
}

class _OrderQuickActionTile extends StatelessWidget {
  final _OrderQuickAction action;
  final VoidCallback onTap;

  const _OrderQuickActionTile({
    required this.action,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = action.color ?? Theme.of(context).colorScheme.onSurface;
    return ListTile(
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
      minLeadingWidth: 0,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(action.icon, color: color, size: 20),
      ),
      title: Text(
        action.title,
        style: TextStyle(
          color: color,
          fontSize: 14.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _OrderProductPreview extends StatelessWidget {
  final OrderSummary order;

  const _OrderProductPreview({required this.order});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = order.items;
    if (items.isEmpty) {
      return Row(
        children: [
          Container(
            height: 58,
            width: 58,
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF0B7FEA).withValues(alpha: 0.20)
                  : const Color(0xFFEAF5FF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.inventory_2_outlined,
              color: _brandBlue,
              size: 26,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Produk pesanan',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Detail item akan dimuat di halaman detail.',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final first = items.first;
    final second = items.length > 1 ? items[1] : null;
    final extraCount = (_displayItemCount(order) - 1).clamp(0, 999).toInt();
    final subtitle = extraCount > 0
        ? '+$extraCount produk lainnya'
        : first.variantLabel ??
            _paymentLabel(
              order.paymentStatus,
              hasProof: (order.paymentProofUrl ?? '').isNotEmpty,
            );

    return Row(
      children: [
        SizedBox(
          height: 64,
          width: 90,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                top: 2,
                child: _PreviewImage(item: first, size: 58),
              ),
              if (second != null)
                Positioned(
                  left: 38,
                  top: 16,
                  child: _PreviewImage(item: second, size: 44),
                ),
              if (extraCount > 0)
                Positioned(
                  left: second == null ? 48 : 62,
                  top: second == null ? 24 : 30,
                  child: Container(
                    height: 34,
                    width: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFC8CED8), Color(0xFF929AA8)],
                      ),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Text(
                      '+$extraCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                first.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 13.5,
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

class _PreviewImage extends StatelessWidget {
  final OrderItemSummary item;
  final double size;

  const _PreviewImage({required this.item, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: AppProductImage(
        imageUrl: item.imageUrl,
        height: size,
        width: size,
      ),
    );
  }
}

class _EmptyOrdersState extends StatelessWidget {
  final Future<void> Function() onRefresh;

  const _EmptyOrdersState({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return NataloPawRefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 100),
          const AppLottieAsset(
            asset: 'assets/lottie/empty_box.json',
            size: 132,
          ),
          const SizedBox(height: 10),
          Text(
            'Belum ada pesanan',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Yuk belanja kebutuhan hewan peliharaanmu — kasih makan, vitamin, '
              'dan mainan favorit. Pesanan kamu akan muncul di sini.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                height: 1.55,
              ),
            ),
          ),
          const SizedBox(height: 20),
          // CTA pill primary "Mulai Belanja" — drive user ke catalog
          Center(
            child: SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () =>
                    Navigator.pushReplacementNamed(context, '/products'),
                icon: const Icon(Icons.shopping_bag_rounded, size: 18),
                label: const Text(
                  'Mulai Belanja',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0B7FEA),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilteredOrdersEmptyState extends StatelessWidget {
  final _OrderFilter filter;
  final Future<void> Function() onRefresh;

  const _FilteredOrdersEmptyState({
    required this.filter,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return NataloPawRefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 100, 24, 24),
        children: [
          Center(
            child: Container(
              height: 76,
              width: 76,
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF0B7FEA).withValues(alpha: 0.20)
                    : const Color(0xFFEAF5FF),
                borderRadius: BorderRadius.circular(26),
              ),
              child: const Icon(
                Icons.receipt_long_outlined,
                color: _brandBlue,
                size: 34,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Tidak ada pesanan ${filter.label.toLowerCase()}',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tarik ke bawah untuk refresh atau pilih tab status lainnya.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

String _statusLabel(String status) {
  return switch (status.toUpperCase()) {
    'UNPAID' => 'Belum Bayar',
    'PENDING' => 'Belum Bayar',
    'PAID' => 'Lunas',
    'PROCESSING' => 'Diproses',
    'READY_TO_PICKUP' || 'READY_FOR_PICKUP' || 'READY_PICKUP' => 'Siap Diambil',
    'SHIPPED' => 'Dikirim',
    'DELIVERED' => 'Selesai',
    'COMPLETED' => 'Selesai',
    'CANCELLED' || 'CANCELED' => 'Dibatalkan',
    'REFUNDED' => 'Refund',
    'EXPIRED' => 'Kedaluwarsa',
    _ => status,
  };
}

/// Label status bayar (lihat penjelasan di member_order_detail_screen).
/// hasProof = order MANUAL sudah upload bukti → "Menunggu verifikasi".
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

int _displayItemCount(OrderSummary order) {
  if (order.itemCount > 0) return order.itemCount;
  final summed = order.items.fold<int>(
    0,
    (total, item) => total + item.quantity,
  );
  return summed > 0 ? summed : order.items.length;
}

Color _statusColor(String status) {
  return switch (status.toUpperCase()) {
    'UNPAID' || 'PENDING' => const Color(0xFFF59E0B),
    'PAID' || 'PROCESSING' => _brandBlue,
    'READY_TO_PICKUP' || 'READY_FOR_PICKUP' || 'READY_PICKUP' => _brandBlue,
    'SHIPPED' => _brandBlue,
    'DELIVERED' || 'COMPLETED' => const Color(0xFF16A34A),
    'CANCELLED' ||
    'CANCELED' ||
    'REFUNDED' ||
    'EXPIRED' =>
      const Color(0xFFEF4444),
    _ => const Color(0xFF6B7280),
  };
}

void _showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
  );
}

BoxDecoration _cardDecoration() {
  return BoxDecoration(
    borderRadius: BorderRadius.circular(24),
    boxShadow: [
      BoxShadow(
        color: const Color(0xFF111111).withValues(alpha: 0.04),
        blurRadius: 18,
        offset: const Offset(0, 8),
      ),
    ],
  );
}

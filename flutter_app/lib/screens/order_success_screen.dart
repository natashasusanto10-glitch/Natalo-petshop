import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/member_profile.dart';
import '../models/product.dart';
import '../services/member_service.dart';
import '../services/order_service.dart';
import '../services/product_service.dart';
import '../state/cart_store.dart';
import '../theme/app_gradients.dart';
import '../theme/app_radius.dart';
import '../theme/natalo_colors.dart';
import '../theme/natalo_text.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import '../utils/payment_url_policy.dart';
import '../widgets/app_toast.dart';
import '../widgets/app_ui.dart';
import '../widgets/compact_commerce_product_card.dart';
import '../widgets/skeleton_product_card.dart';

const _brandBlue = NataloColors.nataloBlue;
const _pendingAmber = NataloColors.warning;
const _successGreen = NataloColors.successDark;

class OrderSuccessArgs {
  final OrderSummary order;
  final List<String> purchasedProductIds;

  const OrderSuccessArgs({
    required this.order,
    required this.purchasedProductIds,
  });
}

/// Satu-satunya konfirmasi setelah checkout berhasil.
///
/// Status pembayaran di-refresh saat layar dibuka, ditarik turun, dan saat
/// app kembali dari halaman Midtrans. Data awal dari checkout menjaga layar
/// tetap langsung terisi ketika request detail belum selesai.
class OrderSuccessScreen extends StatefulWidget {
  final OrderSummary initialOrder;
  final List<String> purchasedProductIds;

  const OrderSuccessScreen({
    super.key,
    required this.initialOrder,
    required this.purchasedProductIds,
  });

  @override
  State<OrderSuccessScreen> createState() => _OrderSuccessScreenState();
}

class _OrderSuccessScreenState extends State<OrderSuccessScreen>
    with WidgetsBindingObserver {
  late OrderSummary _order;
  List<Product> _recommendations = const [];
  MemberVoucher? _voucher;
  bool _loadingOrder = false;
  bool _loadingRecommendations = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _order = widget.initialOrder;
    _loadSupportingContent();
    _refreshOrder();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshOrder();
  }

  Future<void> _loadSupportingContent() async {
    final ids = widget.purchasedProductIds
        .where((id) => id.trim().isNotEmpty)
        .toSet()
        .toList();
    final recommendationsFuture = () async {
      try {
        return await productService.fetchRecommendations(
          cartIds: ids,
          excludeIds: ids,
          limit: 12,
        );
      } catch (_) {
        return <Product>[];
      }
    }();
    final vouchersFuture = () async {
      try {
        return await memberService.fetchCartVouchers(
          _order.total.round(),
          ids,
        );
      } catch (_) {
        return (
          available: <MemberVoucher>[],
          unavailable: <MemberVoucher>[],
        );
      }
    }();
    final results = await Future.wait<dynamic>([
      recommendationsFuture,
      vouchersFuture,
    ]);
    if (!mounted) return;

    final vouchers = results[1] as ({
      List<MemberVoucher> available,
      List<MemberVoucher> unavailable
    });
    final now = DateTime.now();
    final validVouchers = vouchers.available
        .where((voucher) =>
            voucher.applicable &&
            voucher.code.isNotEmpty &&
            voucher.expiresAt.isAfter(now))
        .toList()
      ..sort((a, b) => a.expiresAt.compareTo(b.expiresAt));

    setState(() {
      _recommendations = (results[0] as List<Product>).take(12).toList();
      _voucher = validVouchers.firstOrNull;
      _loadingRecommendations = false;
    });
  }

  Future<void> _refreshOrder() async {
    if (_loadingOrder) return;
    setState(() => _loadingOrder = true);
    try {
      final fresh = await orderService.fetchOrderDetail(
        _order.orderNumber,
        trackingToken: _order.trackingToken,
      );
      if (mounted) setState(() => _order = fresh);
    } catch (_) {
      // Data checkout tetap valid sebagai fallback. Refresh manual tersedia
      // melalui pull-to-refresh tanpa mengubah halaman sukses menjadi error.
    } finally {
      if (mounted) setState(() => _loadingOrder = false);
    }
  }

  Future<void> _openMidtrans() async {
    final paymentUrl = _order.paymentUrl;
    if (paymentUrl == null || paymentUrl.isEmpty) {
      // Kind-inference: tidak ada literal keyword match → info (default
      // "else" migrasi ini; lihat juga "Produk sudah tidak tersedia." di
      // member_order_detail_screen.dart yang juga default info tanpa kind).
      _showSnack('Link pembayaran belum tersedia. Buka detail pesanan.');
      return;
    }
    // Payment links only ever load in the OS browser after exact validation —
    // never inside the embedded WebView, so a spoofed/foreign URL from the
    // order payload can't render inside the app session.
    if (!PaymentUrlPolicy.isValidMidtransPaymentUrl(paymentUrl)) {
      _showSnack(
        'Link pembayaran tidak valid atau tidak tepercaya.',
        kind: ToastKind.error,
      );
      return;
    }
    final opened = await launchUrl(
      Uri.parse(paymentUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!mounted) return;
    if (!opened) {
      _showSnack('Tidak bisa membuka pembayaran.', kind: ToastKind.error);
      return;
    }
    await _refreshOrder();
  }

  void _openDetail() {
    Navigator.pushNamed(context, '/member/order-detail', arguments: _order);
  }

  void _goHome() {
    Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
  }

  void _goToOrders() {
    Navigator.pushNamedAndRemoveUntil(
      context,
      '/member/orders',
      ModalRoute.withName('/'),
    );
  }

  void _showSnack(String message, {ToastKind kind = ToastKind.info}) {
    AppToast.showBanner(context, message, kind: kind);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: RefreshIndicator(
        onRefresh: _refreshOrder,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _SuccessHero(order: _order)),
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                    child: Column(
                      children: [
                        _OrderStatusCard(
                          order: _order,
                          refreshing: _loadingOrder,
                        ),
                        _PrimaryActions(
                          order: _order,
                          onPayNow: _openMidtrans,
                          onOpenDetail: _openDetail,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _NavigationButton(
                                icon: Icons.home_outlined,
                                label: 'Beranda',
                                onPressed: _goHome,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _NavigationButton(
                                icon: Icons.receipt_long_outlined,
                                label: 'Pesanan Saya',
                                onPressed: _goToOrders,
                              ),
                            ),
                          ],
                        ),
                        if (_voucher != null) ...[
                          const SizedBox(height: 16),
                          _VoucherCard(
                            voucher: _voucher!,
                            onTap: () => Navigator.pushNamed(
                              context,
                              '/member/vouchers',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_loadingRecommendations || _recommendations.isNotEmpty)
              SliverToBoxAdapter(
                child: _RecommendationsSection(
                  products: _recommendations,
                  loading: _loadingRecommendations,
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }
}

class _SuccessHero extends StatelessWidget {
  final OrderSummary order;

  const _SuccessHero({required this.order});

  @override
  Widget build(BuildContext context) {
    final subtitle = switch (_visualState(order)) {
      _PaymentVisualState.unpaid =>
        'Selesaikan pembayaran agar pesananmu dapat diproses.',
      _PaymentVisualState.verifying =>
        'Bukti pembayaranmu sedang kami verifikasi.',
      _PaymentVisualState.paid => 'Kami akan segera memproses pesananmu.',
      _PaymentVisualState.expired =>
        'Batas waktu pembayaran pesanan ini telah berakhir.',
      _PaymentVisualState.cancelled => 'Pesanan ini telah dibatalkan.',
    };

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.paddingOf(context).top + 12,
        20,
        34,
      ),
      decoration: const BoxDecoration(
        gradient: NataloGradients.headerWash,
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(AppRadius.xxl),
        ),
      ),
      child: Column(
        children: [
          const AppLottieAsset(
            asset: 'assets/lottie/order_created.json',
            size: 126,
            repeat: false,
            fallbackIcon: Icons.pets_rounded,
          ),
          const SizedBox(height: 2),
          const Text(
            'Pesanan Berhasil Dibuat',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: NataloColors.heroTop,
              fontSize: NataloTextSize.headline,
              height: 1.15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: NataloColors.textSecondary,
              fontSize: NataloTextSize.bodyLg,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

enum _PaymentVisualState { unpaid, verifying, paid, expired, cancelled }

_PaymentVisualState _visualState(OrderSummary order) {
  if (order.status.toUpperCase() == 'CANCELLED') {
    return _PaymentVisualState.cancelled;
  }
  if (order.paymentStatus.toUpperCase() == 'PAID') {
    return _PaymentVisualState.paid;
  }
  if ((order.paymentProofUrl ?? '').trim().isNotEmpty) {
    return _PaymentVisualState.verifying;
  }
  if (order.paymentProvider.toUpperCase() == 'MANUAL' &&
      order.paymentDeadline != null &&
      DateTime.now().isAfter(order.paymentDeadline!)) {
    return _PaymentVisualState.expired;
  }
  return _PaymentVisualState.unpaid;
}

class _OrderStatusCard extends StatelessWidget {
  final OrderSummary order;
  final bool refreshing;

  const _OrderStatusCard({required this.order, required this.refreshing});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final state = _visualState(order);
    final manual = order.paymentProvider.toUpperCase() == 'MANUAL';
    final total = manual ? order.total + (order.uniqueCode ?? 0) : order.total;
    final details = switch (state) {
      _PaymentVisualState.paid => (
          'Pembayaran Berhasil',
          'Pesanan akan segera diproses.',
          _successGreen,
          Icons.check_circle_outline_rounded,
        ),
      _PaymentVisualState.verifying => (
          'Menunggu Verifikasi',
          'Bukti transfer sudah diterima.',
          _brandBlue,
          Icons.fact_check_outlined,
        ),
      _PaymentVisualState.expired => (
          'Batas Waktu Habis',
          'Instruksi transfer sudah tidak aktif.',
          cs.onSurfaceVariant,
          Icons.timer_off_outlined,
        ),
      _PaymentVisualState.cancelled => (
          'Pesanan Dibatalkan',
          'Pesanan ini sudah tidak aktif.',
          cs.error,
          Icons.cancel_outlined,
        ),
      _PaymentVisualState.unpaid => (
          'Menunggu Pembayaran',
          manual
              ? 'Transfer sesuai nominal lalu unggah bukti.'
              : 'Pembayaran online melalui Midtrans.',
          _pendingAmber,
          Icons.schedule_rounded,
        ),
    };

    return Transform.translate(
      offset: const Offset(0, -18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: cs.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nomor Pesanan',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: NataloTextSize.body,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        order.orderNumber,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: NataloTextSize.title,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                Semantics(
                  button: true,
                  label: 'Salin nomor pesanan',
                  child: IconButton.outlined(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: order.orderNumber),
                      );
                      if (!context.mounted) return;
                      AppToast.showBanner(
                        context,
                        'Nomor pesanan tersalin.',
                        kind: ToastKind.success,
                      );
                    },
                    icon: const Icon(Icons.copy_all_outlined),
                    color: _brandBlue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Divider(height: 1, color: cs.outlineVariant),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: details.$3.withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(details.$4, color: details.$3),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              details.$1,
                              style: TextStyle(
                                color: details.$3,
                                fontSize: NataloTextSize.bodyLg,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          if (refreshing) ...[
                            const SizedBox(width: 8),
                            const SizedBox(
                              width: 13,
                              height: 13,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        details.$2,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: NataloTextSize.caption,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Divider(height: 1, color: cs.outlineVariant),
            const SizedBox(height: 12),
            _InfoRow(
              label: manual ? 'Total Transfer' : 'Total Pembayaran',
              value: formatRupiah(total),
              strong: true,
            ),
            const SizedBox(height: 8),
            _InfoRow(
              label: manual ? 'Bank Tujuan' : 'Metode Pembayaran',
              value: manual ? _bankLabel(order.manualBank) : 'Midtrans',
            ),
            if (state == _PaymentVisualState.unpaid &&
                manual &&
                order.paymentDeadline != null) ...[
              const SizedBox(height: 8),
              _InfoRow(
                label: 'Bayar Sebelum',
                value: formatDateTime(order.paymentDeadline!.toLocal()),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _bankLabel(String? value) {
  final normalized = (value ?? '').toUpperCase();
  if (normalized.startsWith('BCA')) return 'BCA';
  return value?.trim().isNotEmpty == true ? value! : 'BCA';
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool strong;

  const _InfoRow({
    required this.label,
    required this.value,
    this.strong = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: NataloTextSize.caption,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              color: strong ? _brandBlue : cs.onSurface,
              fontSize: strong ? NataloTextSize.bodyLg : NataloTextSize.caption,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _PrimaryActions extends StatelessWidget {
  final OrderSummary order;
  final VoidCallback onPayNow;
  final VoidCallback onOpenDetail;

  const _PrimaryActions({
    required this.order,
    required this.onPayNow,
    required this.onOpenDetail,
  });

  @override
  Widget build(BuildContext context) {
    final state = _visualState(order);
    final manual = order.paymentProvider.toUpperCase() == 'MANUAL';
    final canPayMidtrans = state == _PaymentVisualState.unpaid &&
        !manual &&
        (order.paymentUrl ?? '').isNotEmpty;
    final showManualInstruction = state == _PaymentVisualState.unpaid && manual;
    final primaryLabel = canPayMidtrans
        ? 'Bayar Sekarang'
        : showManualInstruction
            ? 'Lihat Instruksi Transfer'
            : 'Lihat Detail Pesanan';
    final primaryAction = canPayMidtrans ? onPayNow : onOpenDetail;

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: primaryAction,
            style: ElevatedButton.styleFrom(
              backgroundColor: _brandBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              textStyle: const TextStyle(
                fontSize: NataloTextSize.bodyLg,
                fontWeight: FontWeight.w900,
              ),
            ),
            child: Text(primaryLabel),
          ),
        ),
        if (canPayMidtrans || showManualInstruction) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton(
              onPressed: onOpenDetail,
              child: const Text('Lihat Detail Pesanan'),
            ),
          ),
        ],
      ],
    );
  }
}

class _NavigationButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _NavigationButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        style: OutlinedButton.styleFrom(
          foregroundColor: _brandBlue,
          side: const BorderSide(color: _brandBlue),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),
    );
  }
}

class _VoucherCard extends StatelessWidget {
  final MemberVoucher voucher;
  final VoidCallback onTap;

  const _VoucherCard({required this.voucher, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _brandBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: _brandBlue.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _brandBlue,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: const Icon(
              Icons.confirmation_number_outlined,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  voucher.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: NataloTextSize.bodyLg,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Berlaku sampai ${formatTanggal(voucher.expiresAt.toLocal())}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: NataloTextSize.caption,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: const Text('Lihat Voucher'),
          ),
        ],
      ),
    );
  }
}

class _RecommendationsSection extends StatelessWidget {
  final List<Product> products;
  final bool loading;

  const _RecommendationsSection({
    required this.products,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'Mungkin Kamu Juga Butuh',
            style: TextStyle(
              color: cs.onSurface,
              fontSize: NataloTextSize.title,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 12),
        ColoredBox(
          color: commerceGridSurfaceTint(context),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: loading
                ? const SkeletonProductGrid(
                    count: 4,
                    showAddToCart: true,
                    squareImage: true,
                  )
                : Column(
                    children: [
                      for (var row = 0; row < (products.length + 1) ~/ 2; row++)
                        Padding(
                          padding: EdgeInsets.only(
                            bottom:
                                row == (products.length + 1) ~/ 2 - 1 ? 0 : 6,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _ProductCard(product: products[row * 2]),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: row * 2 + 1 < products.length
                                    ? _ProductCard(
                                        product: products[row * 2 + 1],
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _ProductCard extends StatelessWidget {
  final Product product;

  const _ProductCard({required this.product});

  @override
  Widget build(BuildContext context) {
    return CompactCommerceProductCard(
      product: product,
      squareImage: true,
      onTap: () {
        AppHaptics.tap();
        Navigator.pushNamed(context, '/product-detail', arguments: product);
      },
      onAddToCart: () async {
        if (product.hasVariants) {
          Navigator.pushNamed(context, '/product-detail', arguments: product);
          _showProductSnack(context, 'Pilih varian produk dulu.');
          return;
        }
        final added = await cartStore.addProduct(product);
        if (!context.mounted || !added) return;
        _showProductSnack(context, '${product.title} masuk keranjang.');
      },
    );
  }
}

void _showProductSnack(BuildContext context, String message) {
  AppToast.showBanner(context, message, kind: ToastKind.info);
}

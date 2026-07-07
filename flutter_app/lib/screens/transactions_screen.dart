import 'dart:async';

import 'package:flutter/material.dart';

import '../models/member_profile.dart';
import '../services/api_client.dart';
import '../services/member_service.dart';
import '../state/member_store.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import '../widgets/app_cart_button.dart';
import '../widgets/app_notification_button.dart';
import '../widgets/app_ui.dart';
import '../widgets/bottom_nav.dart';

const _brandBlue = Color(0xFF2563EB);
const _danger = Color(0xFFEF4444);
const _warning = Color(0xFFF97316);
// Feature flag — Saldo Refund sekarang AKTIF (backend phase 1+2 ready).
// User bisa tap menu → masuk halaman aktif RefundBalanceScreen.
// Admin issue refund via /admin/orders/[id] page.
const _refundBalanceEnabled = true;

class TransactionsScreen extends StatelessWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: memberStore,
      builder: (context, _) {
        if (!memberStore.isLoggedIn) {
          return const _LoginRequiredScaffold();
        }

        return Scaffold(
          // Page bg off-white (#F8FAFC light) seperti semula — pakai
          // scaffoldBackgroundColor, BUKAN colorScheme.surface (putih) yang
          // bikin kartu putih hilang kontras & border tampak seperti garis.
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          // extendBody: konten tembus di belakang floating glass nav.
          extendBody: true,
          body: const _TransactionsBody(),
          bottomNavigationBar: const BottomNavBar(currentIndex: 3),
        );
      },
    );
  }
}

class _TransactionsBody extends StatelessWidget {
  const _TransactionsBody();

  @override
  Widget build(BuildContext context) {
    final bottomGap = MediaQuery.of(context).padding.bottom + 96;
    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        physics: Theme.of(context).platform == TargetPlatform.iOS
            ? const BouncingScrollPhysics()
            : const ClampingScrollPhysics(),
        slivers: [
          const SliverToBoxAdapter(child: _TransactionsHeader()),
          const SliverToBoxAdapter(child: _TransactionAlerts()),
          const SliverToBoxAdapter(child: _OrderStatusCard()),
          const SliverToBoxAdapter(child: _BalancePointsCard()),
          const SliverToBoxAdapter(child: _TransactionMenuList()),
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, bottomGap),
              child: const Column(
                children: [
                  Spacer(),
                  _HelpCard(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionsHeader extends StatelessWidget {
  const _TransactionsHeader();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 14, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Transaksi',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Kelola pesanan dan aktivitas belanjamu',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const AppNotificationButton(),
          const SizedBox(width: 2),
          const AppCartButton(),
        ],
      ),
    );
  }
}

class _TransactionAlerts extends StatefulWidget {
  const _TransactionAlerts();

  @override
  State<_TransactionAlerts> createState() => _TransactionAlertsState();
}

class _TransactionAlertsState extends State<_TransactionAlerts> {
  static const _paymentWindow = Duration(hours: 24);
  static const _tickInterval = Duration(seconds: 1);
  static const _refreshInterval = Duration(seconds: 30);

  Future<_AlertData>? _future;
  Timer? _tick;
  Timer? _refreshTimer;
  bool _refreshInFlight = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _tick = Timer.periodic(_tickInterval, (_) {
      if (mounted) setState(() {});
    });
    _refreshTimer = Timer.periodic(
      _refreshInterval,
      (_) => _refreshSilently(),
    );
  }

  @override
  void dispose() {
    _tick?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<_AlertData> _load() async {
    var orders = memberStore.orders;
    var vouchers = const <MemberVoucher>[];
    try {
      orders = await memberService.fetchOrders();
    } catch (_) {
      orders = memberStore.orders;
    }

    try {
      vouchers = await memberService.fetchVouchers();
    } catch (_) {
      vouchers = const <MemberVoucher>[];
    }

    return _AlertData(orders: orders, vouchers: vouchers);
  }

  Future<void> _refreshSilently() async {
    if (!mounted || _refreshInFlight || !memberStore.isLoggedIn) return;
    _refreshInFlight = true;
    try {
      final data = await _load();
      if (!mounted) return;
      setState(() => _future = Future.value(data));
    } finally {
      _refreshInFlight = false;
    }
  }

  List<OrderSummary> _activeUnpaidOrders(List<OrderSummary> orders) {
    final now = DateTime.now();
    return orders.where((order) {
      final status = order.status.toUpperCase();
      final payment = order.paymentStatus.toUpperCase();
      if (status == 'CANCELLED' || status == 'REFUNDED') return false;
      final unpaid = status == 'PENDING' ||
          status == 'UNPAID' ||
          payment == 'UNPAID' ||
          payment == 'PENDING';
      if (!unpaid) return false;
      return order.createdAt.add(_paymentWindow).isAfter(now);
    }).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  List<MemberVoucher> _expiringVouchers(List<MemberVoucher> vouchers) {
    final now = DateTime.now();
    return vouchers.where((voucher) {
      if (!voucher.applicable) return false;
      final remaining = voucher.expiresAt.difference(now);
      return remaining.inSeconds > 0 && remaining <= const Duration(hours: 24);
    }).toList()
      ..sort((a, b) => a.expiresAt.compareTo(b.expiresAt));
  }

  void _openUnpaid(List<OrderSummary> unpaid) {
    AppHaptics.tap();
    if (unpaid.isEmpty) return;
    if (unpaid.length == 1) {
      Navigator.pushNamed(
        context,
        '/member/order-detail',
        arguments: unpaid.first,
      );
      return;
    }
    Navigator.pushNamed(context, '/member/orders', arguments: 'unpaid');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AlertData>(
      future: _future,
      initialData: _AlertData(
        orders: memberStore.orders,
        vouchers: const <MemberVoucher>[],
      ),
      builder: (context, snapshot) {
        final data = snapshot.data ??
            const _AlertData(
              orders: <OrderSummary>[],
              vouchers: <MemberVoucher>[],
            );
        final unpaid = _activeUnpaidOrders(data.orders);
        final vouchers = _expiringVouchers(data.vouchers);

        return AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: (unpaid.isEmpty && vouchers.isEmpty)
                ? const SizedBox.shrink(key: ValueKey('no-alerts'))
                : Padding(
                    key: ValueKey('${unpaid.length}-${vouchers.length}'),
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Column(
                      children: [
                        if (unpaid.isNotEmpty) ...[
                          _TransactionAlertCard(
                            icon: Icons.receipt_long_rounded,
                            title: '${unpaid.length} Pesanan belum dibayar',
                            subtitle:
                                'Selesaikan pembayaran sebelum ${formatCountdownHms(unpaid.first.createdAt.add(_paymentWindow).difference(DateTime.now()))}',
                            cta: 'Lanjut Bayar',
                            background: const Color(0xFFFFF5F5),
                            border: const Color(0xFFFECACA),
                            iconBackground: const Color(0xFFFEE2E2),
                            color: _danger,
                            filledCta: true,
                            onTap: () => _openUnpaid(unpaid),
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (vouchers.isNotEmpty)
                          _TransactionAlertCard(
                            icon: Icons.local_activity_rounded,
                            title:
                                '${vouchers.length} Voucher akan kedaluwarsa',
                            subtitle:
                                'Gunakan sebelum ${formatCountdownHms(vouchers.first.expiresAt.difference(DateTime.now()))}',
                            cta: 'Lihat Voucher',
                            background: const Color(0xFFFFF7ED),
                            border: const Color(0xFFFED7AA),
                            iconBackground: const Color(0xFFFFEDD5),
                            color: _warning,
                            onTap: () {
                              AppHaptics.tap();
                              Navigator.pushNamed(context, '/member/vouchers');
                            },
                          ),
                      ],
                    ),
                  ),
          ),
        );
      },
    );
  }
}

class _AlertData {
  final List<OrderSummary> orders;
  final List<MemberVoucher> vouchers;

  const _AlertData({
    required this.orders,
    required this.vouchers,
  });
}

class _TransactionAlertCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String cta;
  final Color background;
  final Color border;
  final Color iconBackground;
  final Color color;
  final bool filledCta;
  final VoidCallback onTap;

  const _TransactionAlertCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.cta,
    required this.background,
    required this.border,
    required this.iconBackground,
    required this.color,
    required this.onTap,
    this.filledCta = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: iconBackground,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: color, size: 25),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          filledCta
              ? ElevatedButton(
                  onPressed: onTap,
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                  child: Text(
                    cta,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                )
              : OutlinedButton(
                  onPressed: onTap,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: color,
                    side: BorderSide(color: color.withValues(alpha: 0.7)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                  child: Text(
                    cta,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

class _OrderStatusCard extends StatefulWidget {
  const _OrderStatusCard();

  @override
  State<_OrderStatusCard> createState() => _OrderStatusCardState();
}

class _OrderStatusCardState extends State<_OrderStatusCard> {
  static const _pollInterval = Duration(seconds: 30);

  late Future<List<OrderSummary>> _ordersFuture;
  Timer? _pollTimer;
  bool _pollingRefreshInFlight = false;

  @override
  void initState() {
    super.initState();
    _ordersFuture = _loadOrders();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _refreshOrdersSilently());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<List<OrderSummary>> _loadOrders() async {
    try {
      return await memberService.fetchOrders();
    } catch (_) {
      return memberStore.orders;
    }
  }

  Future<void> _refreshOrdersSilently() async {
    if (!mounted || _pollingRefreshInFlight || !memberStore.isLoggedIn) return;
    _pollingRefreshInFlight = true;
    try {
      final orders = await _loadOrders();
      if (!mounted) return;
      setState(() => _ordersFuture = Future.value(orders));
    } finally {
      _pollingRefreshInFlight = false;
    }
  }

  void _openOrdersByStatus(String status) {
    AppHaptics.tap();
    Navigator.pushNamed(context, '/member/orders', arguments: status);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: FutureBuilder<List<OrderSummary>>(
        future: _ordersFuture,
        initialData: memberStore.orders,
        builder: (context, snapshot) {
          final orders = snapshot.data ?? const <OrderSummary>[];
          final loading = snapshot.connectionState == ConnectionState.waiting;
          final counts = loading && orders.isEmpty
              ? const _OrderStatusCounts.empty()
              : _OrderStatusCounts.fromOrders(orders);

          return _PremiumCard(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(child: _SectionTitle('Pesanan Saya')),
                    if (loading)
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    TextButton(
                      onPressed: () => Navigator.pushNamed(
                        context,
                        '/member/orders',
                      ),
                      child: const Text('Lihat semua'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _OrderStatusItem(
                      icon: Icons.account_balance_wallet_rounded,
                      iconColor: const Color(0xFFF59E0B),
                      iconBg: const Color(0xFFFFF7E0),
                      label: 'Belum Bayar',
                      count: counts.unpaid,
                      onTap: () => _openOrdersByStatus('unpaid'),
                    ),
                    _OrderStatusItem(
                      icon: Icons.inventory_2_rounded,
                      iconColor: _brandBlue,
                      iconBg: const Color(0xFFEAF2FF),
                      label: 'Diproses',
                      count: counts.processing,
                      onTap: () => _openOrdersByStatus('processing'),
                    ),
                    _OrderStatusItem(
                      icon: Icons.local_shipping_rounded,
                      iconColor: const Color(0xFF22C55E),
                      iconBg: const Color(0xFFE8F8EC),
                      label: 'Dikirim',
                      count: counts.shipped,
                      onTap: () => _openOrdersByStatus('shipped'),
                    ),
                    _OrderStatusItem(
                      icon: Icons.check_circle_rounded,
                      iconColor: const Color(0xFF8B5CF6),
                      iconBg: const Color(0xFFF3E8FF),
                      label: 'Selesai',
                      count: counts.recentCompleted,
                      onTap: () => _openOrdersByStatus('delivered'),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Premium card "Saldo & Poin" — display saldo refund + poin loyalty.
///
/// Saldo refund di-fetch dari `/api/member/refund-balance` saat init.
/// Poin di-baca dari `memberStore.profile` (sudah ada di state).
///
/// Refresh strategy:
///  - Initial fetch saat widget mount.
///  - Auto-refetch saat memberStore notifyListeners (login/profile update).
///  - Tidak ada pull-to-refresh di card ini — user bisa pull seluruh
///    halaman Transaksi untuk refresh.
class _BalancePointsCard extends StatefulWidget {
  const _BalancePointsCard();

  @override
  State<_BalancePointsCard> createState() => _BalancePointsCardState();
}

class _BalancePointsCardState extends State<_BalancePointsCard> {
  int? _refundBalance; // null = loading, int = loaded

  @override
  void initState() {
    super.initState();
    _fetchRefundBalance();
  }

  Future<void> _fetchRefundBalance() async {
    // Skip kalau feature flag off OR user belum login (tetap tampil Rp0).
    if (!_refundBalanceEnabled) {
      if (mounted) setState(() => _refundBalance = 0);
      return;
    }
    if (!memberStore.isLoggedIn) {
      if (mounted) setState(() => _refundBalance = 0);
      return;
    }
    try {
      final data = await apiClient.getJson('/api/member/refund-balance');
      if (!mounted) return;
      int balance = 0;
      if (data is Map<String, dynamic>) {
        final wallet = data['wallet'];
        if (wallet is Map) {
          balance = (wallet['availableBalance'] as num?)?.toInt() ?? 0;
        }
      }
      setState(() => _refundBalance = balance);
    } catch (_) {
      // Defensive: kalau API error (network / 500), tampilkan Rp0
      // bukan crash. User tetap bisa tap menu untuk masuk detail screen.
      if (mounted) setState(() => _refundBalance = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final points = memberStore.profile?.points ?? 0;
    final balance = _refundBalance;
    final balanceText = balance == null
        ? '...' // Loading placeholder (singkat, tidak intrusive)
        : balance == 0
            ? 'Rp0'
            : _formatRupiahShort(balance);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: _PremiumCard(
        padding: const EdgeInsets.all(16),
        borderColor: const Color(0xFFDBEAFE),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle('Saldo & Poin'),
            const SizedBox(height: 12),
            IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(
                    child: _BalanceItem(
                      icon: Icons.account_balance_wallet_rounded,
                      iconColor: _brandBlue,
                      iconBg: const Color(0xFFEAF2FF),
                      title: 'Saldo Refund',
                      value: balanceText,
                      trailing: _refundBalanceEnabled
                          ? null
                          : const _SmallChip(
                              text: 'Segera hadir',
                              color: _brandBlue,
                              background: Color(0xFFEFF6FF),
                            ),
                      onTap: () => _openRefundBalance(context),
                    ),
                  ),
                  VerticalDivider(
                    width: 24,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  Expanded(
                    child: _BalanceItem(
                      icon: Icons.stars_rounded,
                      iconColor: const Color(0xFFF59E0B),
                      iconBg: const Color(0xFFFFF7E0),
                      title: 'Poin Natalo',
                      value: '${_formatNumber(points)} poin',
                      onTap: () => Navigator.pushNamed(
                        context,
                        '/member/loyalty',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Format Rupiah singkat untuk display di card kecil.
/// 32000 → "Rp32rb"
/// 1500000 → "Rp1,5jt"
/// 500 → "Rp500"
/// Untuk display formal pakai formatRupiah dari utils/formatters.
String _formatRupiahShort(int value) {
  if (value >= 1000000) {
    final m = value / 1000000;
    final fixed = m >= 10 ? m.toStringAsFixed(0) : m.toStringAsFixed(1);
    return 'Rp${fixed.replaceAll('.', ',').replaceAll(',0', '')}jt';
  }
  if (value >= 1000) {
    final k = value / 1000;
    final fixed = k >= 10 ? k.toStringAsFixed(0) : k.toStringAsFixed(1);
    return 'Rp${fixed.replaceAll('.', ',').replaceAll(',0', '')}rb';
  }
  return 'Rp$value';
}

class _BalanceItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String value;
  final Widget? trailing;
  final VoidCallback onTap;

  const _BalanceItem({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.value,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

class _TransactionMenuList extends StatelessWidget {
  const _TransactionMenuList();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: _PremiumCard(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle('Menu Transaksi'),
            const SizedBox(height: 12),
            const _TransactionMenuItem(
              route: '/member/vouchers',
              icon: Icons.confirmation_number_rounded,
              iconColor: _warning,
              iconBg: Color(0xFFFFF7E0),
              title: 'Voucher',
              subtitle: 'Promo & diskon belanja',
            ),
            const _TransactionMenuItem(
              route: '/wishlist',
              icon: Icons.favorite_rounded,
              iconColor: Color(0xFFEF4444),
              iconBg: Color(0xFFFFE4E6),
              title: 'Wishlist',
              subtitle: 'Produk favoritmu',
            ),
            const _TransactionMenuItem(
              route: '/member/reviews',
              icon: Icons.rate_review_rounded,
              iconColor: Color(0xFF8B5CF6),
              iconBg: Color(0xFFF3E8FF),
              title: 'Ulasan',
              subtitle: 'Beri ulasan untuk produk yang kamu beli',
            ),
            _TransactionMenuItem(
              icon: Icons.account_balance_wallet_rounded,
              iconColor: _brandBlue,
              iconBg: const Color(0xFFEAF2FF),
              title: 'Saldo Refund',
              subtitle: 'Dana pengembalian pesanan',
              chip: _refundBalanceEnabled
                  ? null
                  : const _SmallChip(
                      text: 'Segera hadir',
                      color: _brandBlue,
                      background: Color(0xFFEFF6FF),
                    ),
              muted: !_refundBalanceEnabled,
              onTap: () => _openRefundBalance(context),
            ),
            const _TransactionMenuItem(
              route: '/member/loyalty',
              icon: Icons.stars_rounded,
              iconColor: Color(0xFFF59E0B),
              iconBg: Color(0xFFFFF7E0),
              title: 'Tukar Poin',
              subtitle: 'Tukar poin dengan voucher menarik',
            ),
            const _TransactionMenuItem(
              route: '/member/loyalty/history',
              icon: Icons.history_rounded,
              iconColor: Color(0xFF0EA5E9),
              iconBg: Color(0xFFE0F2FE),
              title: 'Riwayat Poin',
              subtitle: 'Riwayat masuk & tukar poin',
              showDivider: false,
            ),
          ],
        ),
      ),
    );
  }
}

class _TransactionMenuItem extends StatelessWidget {
  final String? route;
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final Widget? chip;
  final bool muted;
  final bool showDivider;
  final VoidCallback? onTap;

  const _TransactionMenuItem({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    this.route,
    this.chip,
    this.muted = false,
    this.showDivider = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final opacity = muted ? 0.72 : 1.0;
    return Opacity(
      opacity: opacity,
      child: Column(
        children: [
          AppPressable(
            onTap: () {
              AppHaptics.tap();
              if (onTap != null) {
                onTap!();
                return;
              }
              if (route != null) Navigator.pushNamed(context, route!);
            },
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: iconBg,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: iconColor, size: 23),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 14,
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
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (chip != null) ...[
                    const SizedBox(width: 8),
                    chip!,
                  ],
                  const SizedBox(width: 8),
                  Icon(
                    muted ? Icons.info_outline_rounded : Icons.chevron_right,
                    color: cs.onSurfaceVariant,
                    size: muted ? 19 : 22,
                  ),
                ],
              ),
            ),
          ),
          if (showDivider)
            Divider(
              height: 1,
              thickness: 1,
              // Divider antar-menu sengaja super halus (nyaris tak terlihat)
              // di light seperti semula; di dark pakai border gelap.
              color: Theme.of(context).brightness == Brightness.dark
                  ? cs.outlineVariant
                  : const Color(0xFFEEF2F7),
              indent: 55,
            ),
        ],
      ),
    );
  }
}

class _HelpCard extends StatelessWidget {
  const _HelpCard();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF0B7FEA).withValues(alpha: 0.20)
                  : const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(
              Icons.support_agent_rounded,
              color: _brandBlue,
              size: 25,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Butuh bantuan?',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Kami siap membantumu',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pushNamed(context, '/help'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _brandBlue,
              side: const BorderSide(color: Color(0xFFBFDBFE)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
            ),
            child: const Text(
              'Hubungi Kami',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginRequiredScaffold extends StatelessWidget {
  const _LoginRequiredScaffold();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      extendBody: true,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.receipt_long_outlined,
                color: _brandBlue,
                size: 64,
              ),
              const SizedBox(height: 16),
              Text(
                'Login dulu yuk',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Masuk untuk lihat pesanan, voucher, dan menu transaksi lainnya.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () =>
                      Navigator.pushNamed(context, '/member/login'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _brandBlue,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Masuk Member',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const BottomNavBar(currentIndex: 3),
    );
  }
}

class _OrderStatusCounts {
  final int unpaid;
  final int processing;
  final int shipped;
  final int recentCompleted;

  const _OrderStatusCounts({
    required this.unpaid,
    required this.processing,
    required this.shipped,
    required this.recentCompleted,
  });

  const _OrderStatusCounts.empty()
      : unpaid = 0,
        processing = 0,
        shipped = 0,
        recentCompleted = 0;

  factory _OrderStatusCounts.fromOrders(List<OrderSummary> orders) {
    final now = DateTime.now();
    var unpaid = 0;
    var processing = 0;
    var shipped = 0;
    var recentCompleted = 0;

    for (final order in orders) {
      final status = order.status.toUpperCase();
      final payment = order.paymentStatus.toUpperCase();

      if (status == 'CANCELLED' || status == 'REFUNDED') {
        continue;
      }

      if (status == 'PENDING' ||
          status == 'UNPAID' ||
          payment == 'UNPAID' ||
          payment == 'PENDING') {
        unpaid++;
        continue;
      }

      if (status == 'PAID' || status == 'PROCESSING') {
        processing++;
        continue;
      }

      if (status == 'SHIPPED') {
        shipped++;
        continue;
      }

      if (status == 'DELIVERED' || status == 'COMPLETED') {
        final completedDate = order.deliveredAt ??
            order.completedAt ??
            order.statusUpdatedAt ??
            order.updatedAt;
        if (completedDate != null) {
          final ageInDays = now.difference(completedDate).inDays;
          if (ageInDays >= 0 && ageInDays <= 7) {
            recentCompleted++;
          }
        }
      }
    }

    return _OrderStatusCounts(
      unpaid: unpaid,
      processing: processing,
      shipped: shipped,
      recentCompleted: recentCompleted,
    );
  }
}

class _OrderStatusItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String label;
  final int count;
  final VoidCallback onTap;

  const _OrderStatusItem({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.label,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: AppPressable(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    height: 50,
                    width: 50,
                    decoration: BoxDecoration(
                      color: iconBg,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(icon, color: iconColor, size: 25),
                  ),
                  Positioned(
                    right: -4,
                    top: -5,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, animation) {
                        return ScaleTransition(
                          scale: CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOutBack,
                          ),
                          child: child,
                        );
                      },
                      child: count > 0
                          ? _OrderStatusBadge(
                              key: ValueKey(count),
                              count: count,
                            )
                          : const SizedBox.shrink(key: ValueKey('empty')),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  height: 1.12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderStatusBadge extends StatelessWidget {
  final int count;

  const _OrderStatusBadge({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    final text = count > 99 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Color(0xFFFF2D3D),
        shape: BoxShape.circle,
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}

class _PremiumCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? borderColor;

  const _PremiumCard({
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor ?? cs.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SmallChip extends StatelessWidget {
  final String text;
  final Color color;
  final Color background;

  const _SmallChip({
    required this.text,
    required this.color,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurface,
        fontSize: 18,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

String _formatNumber(int value) {
  final raw = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    final remaining = raw.length - i;
    buffer.write(raw[i]);
    if (remaining > 1 && remaining % 3 == 1) {
      buffer.write('.');
    }
  }
  return buffer.toString();
}

void _openRefundBalance(BuildContext context) {
  if (_refundBalanceEnabled) {
    Navigator.pushNamed(context, '/member/refund-balance');
    return;
  }
  _showRefundBalanceInfo(context);
}

void _showRefundBalanceInfo(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) {
      final cs = Theme.of(context).colorScheme;
      return SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(26),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 46,
                  height: 5,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'Saldo Refund',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Saldo Refund adalah dana pengembalian dari pesanan Natalo, misalnya jika produk kosong, pesanan dibatalkan sebagian, atau refund disetujui admin.\n\nSaldo ini nantinya dapat digunakan untuk mengurangi pembayaran pesanan berikutnya.',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 14,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    backgroundColor: _brandBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Mengerti',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
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

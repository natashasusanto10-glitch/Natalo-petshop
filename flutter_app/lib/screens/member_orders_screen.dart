import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/member_profile.dart';
import '../models/product.dart';
import '../services/home_widget_service.dart';
import '../services/member_service.dart';
import '../state/cart_store.dart';
import '../state/member_store.dart';
import '../utils/formatters.dart';
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
    try {
      final orders = await memberService.fetchOrders();
      // Sync most-recent order ke Android home widget (silent no-op iOS).
      if (orders.isNotEmpty) {
        AppHomeWidgetService.updateLastOrder(orders.first);
      } else {
        AppHomeWidgetService.updateLastOrder(null);
      }
      return orders;
    } catch (_) {
      return [];
    }
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
      backgroundColor: const Color(0xFFF6F8FC),
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
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
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
                          color: active ? _brandBlue : const Color(0xFF4B5563),
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
                  color: const Color(0xFFEAF5FF),
                  borderRadius: BorderRadius.circular(26),
                ),
                child: const Icon(
                  Icons.lock_outline_rounded,
                  color: _brandBlue,
                  size: 36,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Login member diperlukan',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF17202A),
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Masuk untuk melihat data terbaru dari akun Natalo kamu.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF6B7280),
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

class _OrderCard extends StatelessWidget {
  final OrderSummary order;
  final int index;

  const _OrderCard({required this.order, required this.index});

  void _openOrderDetail(BuildContext context) {
    Navigator.pushNamed(
      context,
      '/member/order-detail',
      arguments: order,
    );
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

  void _buyAgain(BuildContext context) {
    if (order.items.isEmpty) {
      _openOrderDetail(context);
      return;
    }

    for (final item in order.items) {
      cartStore.addProduct(
        Product(
          id: item.productId,
          slug: item.productId,
          title: item.name,
          category: item.categoryName ?? '',
          brand: 'Natalo',
          imageUrl: item.imageUrl ?? '',
          price: item.price.toDouble(),
          rating: 0,
          reviewCount: 0,
          stock: 999,
          description: item.variantLabel ?? '',
        ),
        quantity: item.quantity,
      );
    }
    AppToast.showCartAdded(
      context,
      'Produk masuk keranjang',
      onTap: () => Navigator.pushNamed(context, '/cart'),
    );
  }

  bool get _isUnpaid {
    final status = order.status.toUpperCase();
    final payment = order.paymentStatus.toUpperCase();

    return payment == 'UNPAID' || payment == 'PENDING' || status == 'PENDING';
  }

  bool get _isDelivered => order.status.toUpperCase() == 'DELIVERED';

  String? get _actionLabel {
    if (_isUnpaid) return 'Bayar Sekarang';
    if (_isDelivered) return 'Beli Lagi';
    return null;
  }

  void _handleOrderAction(BuildContext context) {
    if (_isUnpaid) {
      _openPayment(context);
      return;
    }
    if (_isDelivered) {
      _buyAgain(context);
    }
  }

  @override
  Widget build(BuildContext context) {
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
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: const BorderSide(color: Color(0xFFEEF3FB)),
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
                            style: const TextStyle(
                              color: Color(0xFF17202A),
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
                          onPressed: () => _openOrderDetail(context),
                          icon: const Icon(Icons.more_vert_rounded),
                          color: const Color(0xFF9CA3AF),
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
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _OrderProductPreview(order: order),
                    const SizedBox(height: 12),
                    const Divider(height: 1, color: Color(0xFFE5E7EB)),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Total Belanja',
                                style: TextStyle(
                                  color: Color(0xFF6B7280),
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
                            ],
                          ),
                        ),
                        if (actionLabel != null) ...[
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: () => _handleOrderAction(context),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(0, 40),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              backgroundColor: _brandBlue,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              actionLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
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

class _OrderProductPreview extends StatelessWidget {
  final OrderSummary order;

  const _OrderProductPreview({required this.order});

  @override
  Widget build(BuildContext context) {
    final items = order.items;
    if (items.isEmpty) {
      return Row(
        children: [
          Container(
            height: 58,
            width: 58,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF5FF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.inventory_2_outlined,
              color: _brandBlue,
              size: 26,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Produk pesanan',
                  style: TextStyle(
                    color: Color(0xFF17202A),
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'Detail item akan dimuat di halaman detail.',
                  style: TextStyle(
                    color: Color(0xFF6B7280),
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
        : first.variantLabel ?? _paymentLabel(order.paymentStatus);

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
                style: const TextStyle(
                  color: Color(0xFF17202A),
                  fontSize: 14.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF6B7280),
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
        color: Colors.white,
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
          const Text(
            'Belum ada pesanan',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF111111),
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Yuk belanja kebutuhan hewan peliharaanmu — kasih makan, vitamin, '
              'dan mainan favorit. Pesanan kamu akan muncul di sini.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF6B7280),
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
                color: const Color(0xFFEAF5FF),
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
            style: const TextStyle(
              color: Color(0xFF17202A),
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Tarik ke bawah untuk refresh atau pilih tab status lainnya.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF6B7280),
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
    'SHIPPED' => 'Dikirim',
    'DELIVERED' => 'Selesai',
    'CANCELLED' => 'Dibatalkan',
    _ => status,
  };
}

String _paymentLabel(String status) {
  return switch (status.toUpperCase()) {
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
    'SHIPPED' => _brandBlue,
    'DELIVERED' => const Color(0xFF16A34A),
    'CANCELLED' => const Color(0xFFEF4444),
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

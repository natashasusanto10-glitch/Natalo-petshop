import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../theme/admin_theme.dart';
import 'order_detail_screen.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const _statuses = <_OrderStatus>[
    _OrderStatus(key: 'all', label: 'Semua'),
    _OrderStatus(key: 'PENDING_PAYMENT', label: 'Belum Bayar'),
    _OrderStatus(key: 'PAID', label: 'Perlu Kirim'),
    _OrderStatus(key: 'SHIPPED', label: 'Dikirim'),
    _OrderStatus(key: 'DELIVERED', label: 'Selesai'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _statuses.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pesanan'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: AdminColors.primary,
          labelColor: AdminColors.primary,
          unselectedLabelColor: AdminColors.textSecondary,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          unselectedLabelStyle:
              const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
          tabs: _statuses.map((s) => Tab(text: s.label)).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _statuses
            .map((s) => _OrdersList(statusKey: s.key))
            .toList(),
      ),
    );
  }
}

class _OrderStatus {
  final String key;
  final String label;
  const _OrderStatus({required this.key, required this.label});
}

class _OrdersList extends StatefulWidget {
  final String statusKey;
  const _OrdersList({required this.statusKey});

  @override
  State<_OrdersList> createState() => _OrdersListState();
}

class _OrdersListState extends State<_OrdersList>
    with AutomaticKeepAliveClientMixin {
  bool _loading = true;
  String? _error;
  List<_OrderRow> _orders = [];

  @override
  bool get wantKeepAlive => true;

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
        '/api/admin/orders',
        query: {
          if (widget.statusKey != 'all') 'status': widget.statusKey,
          'limit': 50,
        },
      );
      final list = _extractList(data);
      _orders = list.map(_OrderRow.fromJson).toList();
    } on AdminApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Tidak bisa load pesanan. Cek koneksi.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _extractList(dynamic data) {
    if (data is Map<String, dynamic>) {
      final candidates = ['orders', 'items', 'data', 'results'];
      for (final key in candidates) {
        final v = data[key];
        if (v is List) {
          return v.whereType<Map<String, dynamic>>().toList();
        }
      }
    }
    if (data is List) {
      return data.whereType<Map<String, dynamic>>().toList();
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AdminColors.primary),
      );
    }
    if (_error != null) {
      return _ErrorBox(message: _error!, onRetry: _load);
    }
    if (_orders.isEmpty) {
      return _EmptyBox(
        icon: Icons.receipt_long_outlined,
        label: 'Belum ada pesanan',
      );
    }
    return RefreshIndicator(
      color: AdminColors.primary,
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _orders.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _OrderCard(order: _orders[i]),
      ),
    );
  }
}

class _OrderRow {
  final String orderNumber;
  final String customerName;
  final int total;
  final String status;
  final int itemCount;
  final String? createdAt;

  const _OrderRow({
    required this.orderNumber,
    required this.customerName,
    required this.total,
    required this.status,
    required this.itemCount,
    this.createdAt,
  });

  factory _OrderRow.fromJson(Map<String, dynamic> json) {
    final items = json['items'];
    return _OrderRow(
      orderNumber: (json['orderNumber'] ?? json['id'] ?? '-').toString(),
      customerName: (json['customerName'] ??
              json['userName'] ??
              json['memberName'] ??
              '-')
          .toString(),
      total: (json['total'] ?? json['totalAmount'] ?? json['grandTotal'] ?? 0)
          is num
          ? (json['total'] ??
                  json['totalAmount'] ??
                  json['grandTotal'] ??
                  0)
              .toInt()
          : 0,
      status: (json['status'] ?? 'UNKNOWN').toString(),
      itemCount: items is List ? items.length : 0,
      createdAt: json['createdAt']?.toString(),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final _OrderRow order;
  const _OrderCard({required this.order});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                OrderDetailScreen(orderNumber: order.orderNumber),
          ),
        );
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AdminColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '#${order.orderNumber}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AdminColors.textPrimary,
                    ),
                  ),
                ),
                _StatusChip(status: order.status),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              order.customerName,
              style: const TextStyle(
                fontSize: 13,
                color: AdminColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.shopping_bag_outlined,
                    size: 14, color: AdminColors.textMuted),
                const SizedBox(width: 4),
                Text(
                  '${order.itemCount} item',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AdminColors.textMuted,
                  ),
                ),
                const Spacer(),
                Text(
                  formatRupiah(order.total),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AdminColors.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (bg, fg, label) = switch (status.toUpperCase()) {
      'PENDING_PAYMENT' => (
        const Color(0xFFFFF8E1),
        AdminColors.warning,
        'Belum Bayar'
      ),
      'PAID' => (
        const Color(0xFFFFF3F0),
        AdminColors.primary,
        'Perlu Kirim'
      ),
      'SHIPPED' || 'IN_TRANSIT' => (
        const Color(0xFFE3F2FD),
        AdminColors.info,
        'Dikirim'
      ),
      'DELIVERED' || 'COMPLETED' => (
        const Color(0xFFE6F7F4),
        AdminColors.success,
        'Selesai'
      ),
      'CANCELLED' || 'REFUNDED' => (
        const Color(0xFFFEE2E2),
        AdminColors.danger,
        'Batal'
      ),
      _ => (
        const Color(0xFFEEEEEE),
        AdminColors.textSecondary,
        status
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBox({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 48,
              color: AdminColors.textMuted,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AdminColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onRetry, child: const Text('Coba lagi')),
          ],
        ),
      ),
    );
  }
}

class _EmptyBox extends StatelessWidget {
  final IconData icon;
  final String label;
  const _EmptyBox({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: AdminColors.textMuted),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: AdminColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

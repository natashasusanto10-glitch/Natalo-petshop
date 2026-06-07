import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/export_service.dart';
import '../services/notification_counts.dart';
import '../theme/admin_theme.dart';
import '../widgets/skeletons.dart';
import 'order_detail_screen.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  // Tab key = status enum yang dikirim ke backend (comma-separated untuk
  // multi-status). Mapping:
  // - "PENDING" → order baru dibuat, belum dibayar
  // - "PAID,PROCESSING,READY_FOR_PICKUP" → sudah bayar, butuh dikirim
  //   (cover seluruh lifecycle pre-shipment, bukan cuma PAID)
  // - "SHIPPED" → sudah dikirim, dalam perjalanan
  // - "DELIVERED" → sudah sampai/selesai
  // - "CANCELLED,REFUNDED" → order yang dibatalkan / di-refund
  //   (admin bisa audit history pembatalan; cancellation request yang
  //   masih PENDING ada di tab "Perlu Kirim" karena status order belum
  //   berubah sampai admin approve)
  static const _statuses = <_OrderStatus>[
    _OrderStatus(key: 'all', label: 'Semua'),
    _OrderStatus(key: 'PENDING', label: 'Belum Bayar'),
    _OrderStatus(
        key: 'PAID,PROCESSING,READY_FOR_PICKUP', label: 'Perlu Kirim'),
    _OrderStatus(key: 'SHIPPED', label: 'Dikirim'),
    _OrderStatus(key: 'DELIVERED', label: 'Selesai'),
    _OrderStatus(key: 'CANCELLED,REFUNDED', label: 'Pembatalan'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _statuses.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchSubmit(String value) {
    final trimmed = value.trim();
    if (trimmed == _searchQuery) return;
    setState(() => _searchQuery = trimmed);
  }

  void _clearSearch() {
    if (_searchQuery.isEmpty && _searchController.text.isEmpty) return;
    _searchController.clear();
    setState(() => _searchQuery = '');
  }

  /// Dialog pilih range tanggal untuk export CSV. Default: bulan ini.
  /// Lalu fetch + generate + share via system dialog (WA/Drive/Email).
  Future<void> _showExportDialog(BuildContext context) async {
    final now = DateTime.now();
    DateTime start = DateTime(now.year, now.month, 1);
    DateTime end = now;
    final result = await showModalBottomSheet<({DateTime s, DateTime e})>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSt) => Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Export Order ke CSV',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Pilih rentang tanggal. File akan di-share via WhatsApp/Email/Drive.',
                  style: TextStyle(
                      fontSize: 12, color: AdminColors.textSecondary),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today_outlined),
                  title: const Text('Dari Tanggal'),
                  subtitle: Text(
                    '${start.day} ${_monthName(start.month)} ${start.year}',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: start,
                      firstDate: DateTime(2020),
                      lastDate: now,
                    );
                    if (picked != null) setSt(() => start = picked);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: const Text('Sampai Tanggal'),
                  subtitle: Text(
                    '${end.day} ${_monthName(end.month)} ${end.year}',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: end,
                      firstDate: start,
                      lastDate: now,
                    );
                    if (picked != null) setSt(() => end = picked);
                  },
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.file_download_outlined),
                    label: const Text('Export & Share'),
                    onPressed: () => Navigator.pop(ctx, (s: start, e: end)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (result == null) return;
    if (!context.mounted) return;

    // Show loading snackbar — CSV bisa lambat kalau banyak order.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(children: [
          SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white)),
          SizedBox(width: 12),
          Text('Mengumpulkan data order...'),
        ]),
        duration: Duration(seconds: 30),
      ),
    );
    try {
      await AdminExportService.instance.shareOrdersCsv(
        startDate: result.s,
        endDate: result.e,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal export: $e')),
        );
      }
    }
  }

  String _monthName(int m) {
    const names = [
      'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
    ];
    return names[(m - 1).clamp(0, 11)];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pesanan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Export Order CSV',
            onPressed: () => _showExportDialog(context),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(108),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  onSubmitted: _onSearchSubmit,
                  decoration: InputDecoration(
                    hintText: 'Cari No. order / nama / HP customer',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _searchQuery.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: _clearSearch,
                          ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              TabBar(
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
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _statuses
            .map((s) =>
                _OrdersList(statusKey: s.key, searchQuery: _searchQuery))
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
  final String searchQuery;
  const _OrdersList({required this.statusKey, required this.searchQuery});

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

  @override
  void didUpdateWidget(covariant _OrdersList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload kalau search query berubah — biarkan tab keepAlive lainnya
    // ikut update saat user pindah tab.
    if (oldWidget.searchQuery != widget.searchQuery) {
      _load();
    }
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
          if (widget.searchQuery.isNotEmpty) 'q': widget.searchQuery,
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
      return SkeletonList(
        count: 6,
        builder: (_) => const OrderCardSkeleton(),
      );
    }
    if (_error != null) {
      return _ErrorBox(message: _error!, onRetry: _load);
    }
    if (_orders.isEmpty) {
      final searching = widget.searchQuery.isNotEmpty;
      return _EmptyBox(
        icon: searching ? Icons.search_off_rounded : Icons.receipt_long_outlined,
        label: searching
            ? 'Tidak ada hasil untuk "${widget.searchQuery}"'
            : 'Belum ada pesanan',
        hint: searching ? 'Coba kata kunci lain' : null,
      );
    }
    return RefreshIndicator(
      color: AdminColors.primary,
      onRefresh: () async {
        // Pull-to-refresh juga update badge counter — admin pulling
        // di tab Pesanan biasanya untuk cek "ada order baru kah?"
        await Future.wait([
          _load(),
          NotificationCounts.instance.refresh(),
        ]);
      },
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
      'PENDING' || 'PENDING_PAYMENT' => (
        const Color(0xFFFFF8E1),
        AdminColors.warning,
        'Belum Bayar'
      ),
      'PAID' => (
        const Color(0xFFFFF3F0),
        AdminColors.primary,
        'Perlu Kirim'
      ),
      'PROCESSING' => (
        const Color(0xFFFFF3F0),
        AdminColors.primary,
        'Diproses'
      ),
      'READY_FOR_PICKUP' => (
        const Color(0xFFFFF3F0),
        AdminColors.primary,
        'Siap Kirim'
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
  final String? hint;
  const _EmptyBox({required this.icon, required this.label, this.hint});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AdminColors.textMuted),
            const SizedBox(height: 14),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AdminColors.textSecondary,
              ),
            ),
            if (hint != null) ...[
              const SizedBox(height: 4),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: AdminColors.textMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

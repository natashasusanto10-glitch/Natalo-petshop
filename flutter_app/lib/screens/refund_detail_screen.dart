import 'package:flutter/material.dart';

import '../models/member_profile.dart';
import '../services/api_client.dart';
import '../utils/formatters.dart';
import '../widgets/app_ui.dart';

const _brandBlue = Color(0xFF0B7FEA);
const _success = Color(0xFF059669);
const _danger = Color(0xFFEF4444);

/// Halaman detail refund — show breakdown lengkap dari 1 RefundCase.
///
/// Source: GET /api/member/refund-cases/{caseId}
///
/// Layout:
///  1. Header status (icon + amount + tanggal credited)
///  2. Alasan refund (translated enum + reason label)
///  3. Item yang di-refund (kalau partial, satu item card)
///  4. Perhitungan refund (kalau voucherAllocations data tersedia) —
///     OPSI A: hide kalau data null, show full breakdown kalau ada.
///  5. Catatan admin (kalau ada)
///  6. Pesanan asal (orderNumber + button "Lihat Detail Pesanan")
///  7. Timeline (dibuat, disetujui, masuk saldo)
class RefundDetailScreen extends StatefulWidget {
  final String caseId;

  const RefundDetailScreen({super.key, required this.caseId});

  @override
  State<RefundDetailScreen> createState() => _RefundDetailScreenState();
}

class _RefundDetailScreenState extends State<RefundDetailScreen> {
  late Future<_RefundDetail> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<_RefundDetail> _fetch() async {
    try {
      final data =
          await apiClient.getJson('/api/member/refund-cases/${widget.caseId}');
      if (data is! Map<String, dynamic>) {
        throw const _RefundDetailException('Data tidak valid');
      }
      return _RefundDetail.fromJson(data);
    } catch (e) {
      if (e is _RefundDetailException) rethrow;
      throw _RefundDetailException(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detail Refund')),
      body: FutureBuilder<_RefundDetail>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppSkeletonList(itemCount: 6);
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return _ErrorView(
              message: snapshot.error is _RefundDetailException
                  ? (snapshot.error as _RefundDetailException).message
                  : 'Gagal memuat detail refund.',
              onRetry: () => setState(() => _future = _fetch()),
            );
          }
          final d = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              _StatusHeader(detail: d),
              const SizedBox(height: 16),
              _Section(
                title: 'Alasan',
                child: Text(
                  _reasonLabel(d.case_.reason),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (d.item != null) ...[
                const SizedBox(height: 12),
                _Section(
                  title: 'Item yang di-refund',
                  child: _ItemCard(item: d.item!),
                ),
              ],
              // Perhitungan refund — OPSI A: hanya tampil kalau ada
              // voucherAllocations data. Saat ini admin manual entry
              // tanpa breakdown, jadi section ini biasanya hidden.
              // Future (auto-calc): akan muncul lengkap.
              if (d.case_.voucherAllocations != null &&
                  d.case_.voucherAllocations!.isNotEmpty) ...[
                const SizedBox(height: 12),
                _Section(
                  title: 'Perhitungan Refund',
                  child: _CalcBreakdown(
                    itemGrossPrice: d.item?.lineTotal ?? d.case_.amount,
                    voucherAllocations: d.case_.voucherAllocations!,
                    refundAmount: d.case_.amount,
                  ),
                ),
              ],
              if (d.case_.adminNote != null &&
                  d.case_.adminNote!.isNotEmpty) ...[
                const SizedBox(height: 12),
                _Section(
                  title: 'Catatan Admin',
                  child: _AdminNote(
                    note: d.case_.adminNote!,
                    adminName: d.admin?.name,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _Section(
                title: 'Pesanan Asal',
                child: _OrderSummary(order: d.order),
              ),
              const SizedBox(height: 12),
              _Section(
                title: 'Timeline',
                child: _Timeline(case_: d.case_),
              ),
            ],
          );
        },
      ),
    );
  }
}

String _reasonLabel(String reason) {
  switch (reason) {
    case 'OUT_OF_STOCK':
      return 'Produk kosong saat packing';
    case 'PARTIAL_CANCEL':
      return 'Pesanan dibatalkan sebagian';
    case 'RETURN_APPROVED':
      return 'Return disetujui';
    case 'ORDER_CANCELLED':
      return 'Pesanan dibatalkan';
    case 'OTHER':
      return 'Refund lainnya';
    default:
      return reason;
  }
}

String _statusLabel(String status) {
  switch (status) {
    case 'CREDITED':
      return 'Refund Berhasil';
    case 'APPROVED':
      return 'Refund Disetujui';
    case 'PENDING':
      return 'Refund Diproses';
    case 'REJECTED':
      return 'Refund Ditolak';
    default:
      return status;
  }
}

String _formatDateTime(DateTime dt) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
    'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
  ];
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  return '${dt.day} ${months[dt.month - 1]} ${dt.year}, $h:$m';
}

// ─── Components ──────────────────────────────────────────────────────

class _StatusHeader extends StatelessWidget {
  final _RefundDetail detail;

  const _StatusHeader({required this.detail});

  @override
  Widget build(BuildContext context) {
    final status = detail.case_.status;
    final isSuccess = status == 'CREDITED';
    final isFail = status == 'REJECTED';
    final color =
        isSuccess ? _success : (isFail ? _danger : const Color(0xFFF59E0B));
    final icon = isSuccess
        ? Icons.check_circle_rounded
        : (isFail ? Icons.cancel_rounded : Icons.access_time_rounded);
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 36),
          const SizedBox(height: 10),
          Text(
            _statusLabel(status),
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '+${formatRupiah(detail.case_.amount.toDouble())}',
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _formatDateTime(detail.case_.creditedAt ?? detail.case_.createdAt),
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;

  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  final _RefundItem item;

  const _ItemCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF0B7FEA).withValues(alpha: 0.20)
                  : const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.inventory_2_outlined,
              color: _brandBlue,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (item.variantLabel != null &&
                    item.variantLabel!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Varian: ${item.variantLabel}',
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  '${item.quantity}× ${formatRupiah(item.price.toDouble())} = ${formatRupiah(item.lineTotal.toDouble())}',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
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

class _CalcBreakdown extends StatelessWidget {
  final int itemGrossPrice;
  final Map<String, dynamic> voucherAllocations;
  final int refundAmount;

  const _CalcBreakdown({
    required this.itemGrossPrice,
    required this.voucherAllocations,
    required this.refundAmount,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final totalVoucherDeduction = voucherAllocations.values
        .map((v) => v is num ? v.toInt() : 0)
        .fold<int>(0, (a, b) => a + b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _calcLine(
          cs,
          'Harga item',
          formatRupiah(itemGrossPrice.toDouble()),
        ),
        const SizedBox(height: 6),
        for (final entry in voucherAllocations.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 4, left: 12),
            child: _calcLine(
              cs,
              '• ${entry.key}',
              '-${formatRupiah((entry.value as num).toDouble())}',
              dimmed: true,
            ),
          ),
        if (voucherAllocations.isNotEmpty) ...[
          const SizedBox(height: 2),
          _calcLine(
            cs,
            'Total alokasi voucher',
            '-${formatRupiah(totalVoucherDeduction.toDouble())}',
          ),
        ],
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Divider(height: 1),
        ),
        _calcLine(
          cs,
          'Nominal refund',
          formatRupiah(refundAmount.toDouble()),
          bold: true,
        ),
      ],
    );
  }

  Widget _calcLine(ColorScheme cs, String label, String value,
      {bool bold = false, bool dimmed = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: dimmed ? cs.onSurfaceVariant : cs.onSurface,
              fontSize: 13,
              fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: TextStyle(
            color: bold ? _success : cs.onSurface,
            fontSize: bold ? 14 : 13,
            fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _AdminNote extends StatelessWidget {
  final String note;
  final String? adminName;

  const _AdminNote({required this.note, this.adminName});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '"$note"',
            style: const TextStyle(
              color: Color(0xFF78350F),
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.45,
            ),
          ),
          if (adminName != null && adminName!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '— $adminName',
              style: const TextStyle(
                color: Color(0xFF92400E),
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OrderSummary extends StatelessWidget {
  final _RefundOrderRef order;

  const _OrderSummary({required this.order});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '#${order.orderNumber}',
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Status: ${order.status} • ${_formatDateTime(order.createdAt)}',
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Total Pesanan ${formatRupiah(order.total.toDouble())}',
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 40,
          child: OutlinedButton.icon(
            onPressed: () {
              // Buat OrderSummary stub dari _RefundOrderRef (sudah ada
              // orderNumber + status + createdAt). MemberOrderDetailScreen
              // initState panggil `orderService.fetchOrderDetail(orderNumber)`
              // yang langsung replace stub dengan data fresh dari server
              // (items, customer info, address, shipping, payment, dll).
              // User pengalaman "tap → loading sebentar → detail full"
              // bukan "tap → snackbar useless".
              final stub = OrderSummary(
                id: order.id,
                orderNumber: order.orderNumber,
                status: order.status,
                paymentStatus: 'PAID',
                subtotal: order.subtotal.toDouble(),
                discount:
                    (order.productDiscount + order.shippingDiscount).toDouble(),
                total: order.total.toDouble(),
                createdAt: order.createdAt,
              );
              Navigator.pushNamed(
                context,
                '/member/order-detail',
                arguments: stub,
              );
            },
            icon: const Icon(Icons.receipt_long_rounded, size: 18),
            label: const Text('Lihat Detail Pesanan'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _brandBlue,
              side: const BorderSide(color: _brandBlue),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Timeline extends StatelessWidget {
  final _RefundCase case_;

  const _Timeline({required this.case_});

  @override
  Widget build(BuildContext context) {
    final events = <_TimelineEvent>[
      _TimelineEvent(
        title: 'Refund diminta',
        timestamp: case_.createdAt,
        completed: true,
      ),
      if (case_.approvedAt != null)
        _TimelineEvent(
          title: 'Disetujui admin',
          timestamp: case_.approvedAt!,
          completed: true,
        ),
      if (case_.creditedAt != null)
        _TimelineEvent(
          title: 'Saldo masuk',
          timestamp: case_.creditedAt!,
          completed: true,
        ),
    ];
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: events.reversed.map((e) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.check_circle_rounded,
                color: _success,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.title,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      _formatDateTime(e.timestamp),
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _TimelineEvent {
  final String title;
  final DateTime timestamp;
  final bool completed;

  const _TimelineEvent({
    required this.title,
    required this.timestamp,
    required this.completed,
  });
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: _danger,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              child: const Text('Coba Lagi'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Models ──────────────────────────────────────────────────────────

class _RefundDetail {
  final _RefundCase case_;
  final _RefundOrderRef order;
  final _RefundItem? item;
  final _RefundAdmin? admin;

  const _RefundDetail({
    required this.case_,
    required this.order,
    this.item,
    this.admin,
  });

  factory _RefundDetail.fromJson(Map<String, dynamic> json) {
    return _RefundDetail(
      case_: _RefundCase.fromJson(
        (json['case'] as Map<String, dynamic>?) ?? const {},
      ),
      order: _RefundOrderRef.fromJson(
        (json['order'] as Map<String, dynamic>?) ?? const {},
      ),
      item: json['item'] is Map<String, dynamic>
          ? _RefundItem.fromJson(json['item'] as Map<String, dynamic>)
          : null,
      admin: json['admin'] is Map<String, dynamic>
          ? _RefundAdmin.fromJson(json['admin'] as Map<String, dynamic>)
          : null,
    );
  }
}

class _RefundCase {
  final String id;
  final String reason;
  final int amount;
  final String status;
  final String? adminNote;
  final Map<String, dynamic>? voucherAllocations;
  final DateTime createdAt;
  final DateTime? approvedAt;
  final DateTime? creditedAt;

  const _RefundCase({
    required this.id,
    required this.reason,
    required this.amount,
    required this.status,
    required this.createdAt,
    this.adminNote,
    this.voucherAllocations,
    this.approvedAt,
    this.creditedAt,
  });

  factory _RefundCase.fromJson(Map<String, dynamic> json) {
    return _RefundCase(
      id: (json['id'] ?? '').toString(),
      reason: (json['reason'] ?? 'OTHER').toString(),
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      status: (json['status'] ?? 'PENDING').toString(),
      adminNote: json['adminNote']?.toString(),
      voucherAllocations: json['voucherAllocations'] is Map<String, dynamic>
          ? json['voucherAllocations'] as Map<String, dynamic>
          : null,
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString())
              ?.toLocal() ??
          DateTime.now(),
      approvedAt: json['approvedAt'] != null
          ? DateTime.tryParse(json['approvedAt'].toString())?.toLocal()
          : null,
      creditedAt: json['creditedAt'] != null
          ? DateTime.tryParse(json['creditedAt'].toString())?.toLocal()
          : null,
    );
  }
}

class _RefundOrderRef {
  final String id;
  final String orderNumber;
  final String status;
  final int subtotal;
  final int total;
  final int productDiscount;
  final int shippingDiscount;
  final int refundBalanceUsed;
  final DateTime createdAt;

  const _RefundOrderRef({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.subtotal,
    required this.total,
    required this.productDiscount,
    required this.shippingDiscount,
    required this.refundBalanceUsed,
    required this.createdAt,
  });

  factory _RefundOrderRef.fromJson(Map<String, dynamic> json) {
    return _RefundOrderRef(
      id: (json['id'] ?? '').toString(),
      orderNumber: (json['orderNumber'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      subtotal: (json['subtotal'] as num?)?.toInt() ?? 0,
      total: (json['total'] as num?)?.toInt() ?? 0,
      productDiscount: (json['productDiscount'] as num?)?.toInt() ?? 0,
      shippingDiscount: (json['shippingDiscount'] as num?)?.toInt() ?? 0,
      refundBalanceUsed: (json['refundBalanceUsed'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString())
              ?.toLocal() ??
          DateTime.now(),
    );
  }
}

class _RefundItem {
  final String id;
  final String name;
  final String? variantLabel;
  final int price;
  final int quantity;
  final int lineTotal;

  const _RefundItem({
    required this.id,
    required this.name,
    required this.price,
    required this.quantity,
    required this.lineTotal,
    this.variantLabel,
  });

  factory _RefundItem.fromJson(Map<String, dynamic> json) {
    return _RefundItem(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      variantLabel: json['variantLabel']?.toString(),
      price: (json['price'] as num?)?.toInt() ?? 0,
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      lineTotal: (json['lineTotal'] as num?)?.toInt() ?? 0,
    );
  }
}

class _RefundAdmin {
  final String name;

  const _RefundAdmin({required this.name});

  factory _RefundAdmin.fromJson(Map<String, dynamic> json) {
    return _RefundAdmin(name: (json['name'] ?? '').toString());
  }
}

class _RefundDetailException implements Exception {
  final String message;

  const _RefundDetailException(this.message);
}

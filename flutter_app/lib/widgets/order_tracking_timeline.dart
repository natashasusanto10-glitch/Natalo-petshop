import 'package:flutter/material.dart';

import '../models/member_profile.dart';
import '../theme/natalo_colors.dart';

/// Timeline status order: Dibayar → Diproses → Dikirim → Selesai.
/// Stub minimal — derive step dari order.status, render dot + connector.
class OrderTrackingTimeline extends StatelessWidget {
  /// Either pass [order] OR [status] (with optional [createdAt]).
  final OrderSummary? order;
  final String? status;
  final DateTime? createdAt;

  const OrderTrackingTimeline({
    super.key,
    this.order,
    this.status,
    this.createdAt,
  }) : assert(
          order != null || status != null,
          'OrderTrackingTimeline butuh `order` atau `status`',
        );

  static const _steps = ['UNPAID', 'PROCESSING', 'SHIPPED', 'DELIVERED'];
  static const _labels = ['Belum Bayar', 'Diproses', 'Dikirim', 'Selesai'];

  String get _statusValue => (status ?? order?.status ?? 'PENDING').toUpperCase();
  String get _paymentStatus => order?.paymentStatus.toUpperCase() ?? '';

  int get _activeIndex {
    final s = _statusValue;
    if (s == 'CANCELLED') return -1;
    final idx = _steps.indexOf(s);
    if (idx >= 0) return idx;
    if (s == 'PENDING' || _paymentStatus == 'UNPAID') return 0;
    if (s == 'PAID') return 1;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final active = _activeIndex;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(_steps.length, (i) {
        final reached = i <= active;
        final dot = Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: reached ? NataloColors.primary : NataloColors.border,
            shape: BoxShape.circle,
          ),
          child: reached
              ? const Icon(Icons.check, color: Colors.white, size: 14)
              : null,
        );
        return Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  dot,
                  if (i < _steps.length - 1)
                    Expanded(
                      child: Container(
                        height: 2,
                        color: i < active
                            ? NataloColors.primary
                            : NataloColors.border,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _labels[i],
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: reached ? FontWeight.w700 : FontWeight.w500,
                  color: reached
                      ? NataloColors.textPrimary
                      : NataloColors.textTertiary,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

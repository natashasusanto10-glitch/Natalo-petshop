import 'package:flutter/material.dart';

import '../theme/natalo_colors.dart';

enum OrderTimelineType { delivery, pickup }

class OrderTrackingTimeline extends StatelessWidget {
  final String status;
  final DateTime createdAt;
  final OrderTimelineType type;

  const OrderTrackingTimeline({
    super.key,
    required this.status,
    required this.createdAt,
    this.type = OrderTimelineType.delivery,
  });

  List<_TimelineStep> get _steps {
    if (type == OrderTimelineType.pickup) {
      return const [
        _TimelineStep('PENDING', 'Belum Bayar'),
        _TimelineStep('PROCESSING', 'Diproses'),
        _TimelineStep('READY_TO_PICKUP', 'Siap Diambil'),
        _TimelineStep('COMPLETED', 'Selesai'),
      ];
    }
    return const [
      _TimelineStep('PENDING', 'Belum Bayar'),
      _TimelineStep('PROCESSING', 'Diproses'),
      _TimelineStep('SHIPPED', 'Dikirim'),
      _TimelineStep('DELIVERED', 'Selesai'),
    ];
  }

  int get _activeIndex {
    final normalized = status.toUpperCase();
    if (normalized == 'CANCELLED' || normalized == 'REFUNDED') return -1;

    if (normalized == 'UNPAID' ||
        normalized == 'WAITING_PAYMENT' ||
        normalized == 'PENDING_PAYMENT') {
      return 0;
    }
    if (normalized == 'PAID') return 1;
    if (normalized == 'READY_FOR_PICKUP' || normalized == 'READY_PICKUP') {
      return 2;
    }
    if (normalized == 'PICKED_UP') return 3;

    final index = _steps.indexWhere((step) => step.status == normalized);
    return index < 0 ? 0 : index;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = _activeIndex;
    if (active < 0) {
      return const _CancelledTimeline();
    }

    final steps = _steps;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            type == OrderTimelineType.pickup
                ? 'Status Pengambilan'
                : 'Status Pengiriman',
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(steps.length, (index) {
              final reached = index <= active;
              return Expanded(
                child: Column(
                  children: [
                    Row(
                      children: [
                        _TimelineDot(reached: reached),
                        if (index < steps.length - 1)
                          Expanded(
                            child: Container(
                              height: 2,
                              color: index < active
                                  ? NataloColors.primary
                                  : cs.outlineVariant,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        steps[index].label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: reached
                              ? cs.onSurface
                              : cs.onSurfaceVariant,
                          fontSize: 11,
                          fontWeight:
                              reached ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _TimelineStep {
  final String status;
  final String label;

  const _TimelineStep(this.status, this.label);
}

class _TimelineDot extends StatelessWidget {
  final bool reached;

  const _TimelineDot({required this.reached});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: reached ? NataloColors.primary : cs.outlineVariant,
        shape: BoxShape.circle,
      ),
      child: reached
          ? const Icon(Icons.check_rounded, color: Colors.white, size: 15)
          : null,
    );
  }
}

class _CancelledTimeline extends StatelessWidget {
  const _CancelledTimeline();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: const Row(
        children: [
          Icon(Icons.cancel_rounded, color: Color(0xFFEF4444)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Pesanan dibatalkan',
              style: TextStyle(
                color: Color(0xFFEF4444),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../models/member_profile.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/natalo_colors.dart';

enum OrderTimelineType { delivery, pickup }

class OrderTrackingTimeline extends StatelessWidget {
  final String status;
  final DateTime createdAt;
  final OrderTimelineType type;
  final List<OrderTimelineEvent> timelineEvents;
  final DateTime? readyForPickupAt;
  final DateTime? pickedUpAt;
  final DateTime? shippedAt;
  final DateTime? deliveredAt;

  const OrderTrackingTimeline({
    super.key,
    required this.status,
    required this.createdAt,
    this.type = OrderTimelineType.delivery,
    this.timelineEvents = const [],
    this.readyForPickupAt,
    this.pickedUpAt,
    this.shippedAt,
    this.deliveredAt,
  });

  List<_TimelineStep> get _steps {
    if (type == OrderTimelineType.pickup) {
      return const [
        _TimelineStep('PENDING', 'Pesanan dibuat'),
        _TimelineStep('PROCESSING', 'Diproses'),
        _TimelineStep('READY_FOR_PICKUP', 'Siap diambil'),
        _TimelineStep('DELIVERED', 'Diambil dan selesai'),
      ];
    }
    return const [
      _TimelineStep('PENDING', 'Pesanan dibuat'),
      _TimelineStep('PROCESSING', 'Diproses'),
      _TimelineStep('SHIPPED', 'Dikirim'),
      _TimelineStep('DELIVERED', 'Diterima dan selesai'),
    ];
  }

  int get _activeIndex {
    final normalized = normalizeOrderStatus(status);
    if (normalized == 'CANCELLED' || normalized == 'REFUNDED') return -1;

    if (normalized == 'PAID') return 1;

    final index = _steps.indexWhere((step) => step.status == normalized);
    return index < 0 ? 0 : index;
  }

  DateTime? _timestampFor(String stepStatus) {
    for (final event in timelineEvents.reversed) {
      if (normalizeOrderStatus(event.status) == stepStatus) {
        return event.occurredAt;
      }
    }
    return switch (stepStatus) {
      'PENDING' => createdAt,
      'READY_FOR_PICKUP' => readyForPickupAt,
      'SHIPPED' => shippedAt,
      'DELIVERED' => type == OrderTimelineType.pickup
          ? pickedUpAt ?? deliveredAt
          : deliveredAt,
      _ => null,
    };
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
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: AppRadius.large,
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
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          ...List.generate(steps.length, (index) {
            final reached = index <= active;
            final timestamp = _timestampFor(steps[index].status);
            return _TimelineRow(
              step: steps[index],
              reached: reached,
              current: index == active,
              isLast: index == steps.length - 1,
              timestamp: timestamp,
            );
          }),
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
  final bool current;

  const _TimelineDot({required this.reached, required this.current});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: reached ? NataloColors.primary : cs.surfaceContainerHighest,
        shape: BoxShape.circle,
        border: current
            ? Border.all(color: NataloColors.primaryLight, width: 3)
            : Border.all(
                color: reached ? NataloColors.primary : cs.outlineVariant,
              ),
      ),
      child: reached
          ? const Icon(Icons.check_rounded, color: NataloColors.white, size: 18)
          : null,
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final _TimelineStep step;
  final bool reached;
  final bool current;
  final bool isLast;
  final DateTime? timestamp;

  const _TimelineRow({
    required this.step,
    required this.reached,
    required this.current,
    required this.isLast,
    required this.timestamp,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final timestampLabel = timestamp == null ? null : _formatWib(timestamp!);
    final semanticState = current
        ? 'status saat ini'
        : reached
            ? 'selesai'
            : 'belum berlangsung';

    return Semantics(
      container: true,
      label: '${step.label}, $semanticState'
          '${timestampLabel == null ? '' : ', $timestampLabel'}',
      child: ExcludeSemantics(
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 32,
                child: Column(
                  children: [
                    _TimelineDot(reached: reached, current: current),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          color: reached && !current
                              ? NataloColors.primary
                              : cs.outlineVariant,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    top: AppSpacing.xs,
                    bottom: isLast ? 0 : AppSpacing.xl,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step.label,
                        style: TextStyle(
                          color: reached ? cs.onSurface : cs.onSurfaceVariant,
                          fontSize: 14,
                          fontWeight:
                              reached ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        timestampLabel ??
                            (reached
                                ? 'Waktu belum tersedia'
                                : 'Menunggu proses'),
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatWib(DateTime value) {
  final jakarta = value.isUtc ? value.add(const Duration(hours: 7)) : value;
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
  String two(int number) => number.toString().padLeft(2, '0');
  return '${jakarta.day} ${months[jakarta.month - 1]} ${jakarta.year}, '
      '${two(jakarta.hour)}.${two(jakarta.minute)} WIB';
}

class _CancelledTimeline extends StatelessWidget {
  const _CancelledTimeline();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: NataloColors.dangerSoft,
        borderRadius: AppRadius.large,
        border: Border.all(color: NataloColors.danger.withValues(alpha: 0.3)),
      ),
      child: Semantics(
        label: 'Pesanan dibatalkan',
        child: const ExcludeSemantics(
          child: Row(
            children: [
              Icon(Icons.cancel_rounded, color: NataloColors.danger),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Pesanan dibatalkan',
                  style: TextStyle(
                    color: NataloColors.dangerDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

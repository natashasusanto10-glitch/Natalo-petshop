import 'package:flutter/material.dart';

import '../models/member_profile.dart';
import '../theme/natalo_colors.dart';

enum OrderTimelineType { delivery, pickup }

/// Visual timeline tracker untuk status pesanan.
/// 4 stage: PENDING → PROCESSING → SHIPPED → DELIVERED.
///
/// Stage yang sudah lewat ditandai dengan icon + warna brand,
/// stage yang aktif punya pulse animation, stage future grayed out.
///
/// Native superpower: animated icon + connector lines yang lebih
/// expressive dari static list di PWA. Build ngambil insight order
/// status → render full timeline tanpa scroll.
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

  int get _currentIndex {
    final normalized = status.toUpperCase();
    if (normalized == 'CANCELLED' || normalized == 'REFUNDED') return -1;

    if (type == OrderTimelineType.pickup) {
      switch (normalized) {
        case 'PENDING':
        case 'UNPAID':
        case 'WAITING_PAYMENT':
        case 'PENDING_PAYMENT':
          return 0;
        case 'PAID':
        case 'PROCESSING':
          return 1;
        case 'READY_TO_PICKUP':
        case 'READY_FOR_PICKUP':
        case 'READY_PICKUP':
          return 2;
        case 'PICKED_UP':
        case 'DELIVERED':
        case 'COMPLETED':
          return 3;
        default:
          return 0;
      }
    }

    switch (normalized) {
      case 'PENDING':
      case 'UNPAID':
      case 'WAITING_PAYMENT':
      case 'PENDING_PAYMENT':
        return 0;
      case 'PAID':
      case 'PROCESSING':
        return 1;
      case 'SHIPPED':
        return 2;
      case 'DELIVERED':
      case 'COMPLETED':
        return 3;
      default:
        return 0;
    }
  }

  String get _statusValue => (status ?? order?.status ?? 'PENDING').toUpperCase();
  String get _paymentStatus => order?.paymentStatus.toUpperCase() ?? '';

  static const _pickupStages = [
    _Stage(
      label: 'Pesanan Diterima',
      sublabel: 'Menunggu pembayaran',
      icon: Icons.receipt_long_rounded,
      color: Color(0xFFF59E0B),
    ),
    _Stage(
      label: 'Sedang Diproses',
      sublabel: 'Tim sedang menyiapkan pesanan',
      icon: Icons.inventory_2_rounded,
      color: Color(0xFF7C3AED),
    ),
    _Stage(
      label: 'Siap Diambil',
      sublabel: 'Pesanan siap diambil di toko',
      icon: Icons.storefront_rounded,
      color: Color(0xFF1E5FBF),
    ),
    _Stage(
      label: 'Sudah Diambil',
      sublabel: 'Pesanan sudah diterima customer',
      icon: Icons.check_circle_rounded,
      color: Color(0xFF16A34A),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final current = _currentIndex;
    final stages = type == OrderTimelineType.pickup ? _pickupStages : _stages;
    final title = type == OrderTimelineType.pickup
        ? 'Status Pengambilan'
        : 'Status Pengiriman';

    // Cancelled / refunded — render banner berbeda.
    if (current < 0) {
      return const GlassSurface(
        radius: 20,
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              Icons.cancel_rounded,
              color: Color(0xFFEF4444),
              size: 28,
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pesanan dibatalkan',
                    style: TextStyle(
                      color: Color(0xFFEF4444),
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Hubungi CS jika butuh refund',
                    style: TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return GlassSurface(
      radius: 20,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.timeline_rounded,
                color: Color(0xFF1E5FBF),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF111111),
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              Text(
                '${current + 1}/${stages.length}',
                style: const TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...List.generate(stages.length, (i) {
            final stage = stages[i];
            final state = i < current
                ? _StageState.done
                : i == current
                    ? _StageState.active
                    : _StageState.pending;
            final isLast = i == stages.length - 1;
            return _StageRow(
              stage: stage,
              state: state,
              isLast: isLast,
            );
          }),
        ],
      ),
    );
  }
}

enum _StageState { done, active, pending }

class _Stage {
  final String label;
  final String sublabel;
  final IconData icon;
  final Color color;

  const _Stage({
    required this.label,
    required this.sublabel,
    required this.icon,
    required this.color,
  });
}

class _StageRow extends StatefulWidget {
  final _Stage stage;
  final _StageState state;
  final bool isLast;

  const _StageRow({
    required this.stage,
    required this.state,
    required this.isLast,
  });

  @override
  State<_StageRow> createState() => _StageRowState();
}

class _StageRowState extends State<_StageRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (widget.state == _StageState.active) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(_StageRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state == _StageState.active && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (widget.state != _StageState.active && _pulse.isAnimating) {
      _pulse.stop();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
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
                      if (isDone || isActive)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: (isActive
                                    ? stage.color
                                    : const Color(0xFF16A34A))
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            isActive ? 'Sekarang' : 'Selesai',
                            style: TextStyle(
                              color: isActive
                                  ? stage.color
                                  : const Color(0xFF16A34A),
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    stage.sublabel,
                    style: TextStyle(
                      color: subColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
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

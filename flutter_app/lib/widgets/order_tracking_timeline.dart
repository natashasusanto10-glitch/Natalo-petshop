import 'package:flutter/material.dart';

import '../widgets/glass_surface.dart';

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

  const OrderTrackingTimeline({
    super.key,
    required this.status,
    required this.createdAt,
  });

  int get _currentIndex {
    switch (status.toUpperCase()) {
      case 'PENDING':
        return 0;
      case 'PROCESSING':
        return 1;
      case 'SHIPPED':
        return 2;
      case 'DELIVERED':
      case 'COMPLETED':
        return 3;
      case 'CANCELLED':
      case 'REFUNDED':
        return -1;
      default:
        return 0;
    }
  }

  static const _stages = [
    _Stage(
      label: 'Pesanan Diterima',
      sublabel: 'Menunggu pembayaran',
      icon: Icons.receipt_long_rounded,
      color: Color(0xFFF59E0B),
    ),
    _Stage(
      label: 'Sedang Diproses',
      sublabel: 'Tim sedang packing',
      icon: Icons.inventory_2_rounded,
      color: Color(0xFF7C3AED),
    ),
    _Stage(
      label: 'Dalam Perjalanan',
      sublabel: 'Kurir sedang menuju alamat',
      icon: Icons.local_shipping_rounded,
      color: Color(0xFF1E5FBF),
    ),
    _Stage(
      label: 'Pesanan Sampai',
      sublabel: 'Selamat berbelanja kembali',
      icon: Icons.check_circle_rounded,
      color: Color(0xFF16A34A),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final current = _currentIndex;

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
                const Text(
                  'Status Pengiriman',
                  style: TextStyle(
                    color: Color(0xFF111111),
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Spacer(),
                Text(
                  '${current + 1}/${_stages.length}',
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...List.generate(_stages.length, (i) {
              final stage = _stages[i];
              final state = i < current
                  ? _StageState.done
                  : i == current
                      ? _StageState.active
                      : _StageState.pending;
              final isLast = i == _stages.length - 1;
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
    final stage = widget.stage;
    final isDone = widget.state == _StageState.done;
    final isActive = widget.state == _StageState.active;
    final isPending = widget.state == _StageState.pending;

    final iconColor = isPending ? const Color(0xFF9CA3AF) : stage.color;
    final bg = isPending
        ? const Color(0xFFEFF2F6)
        : stage.color.withValues(alpha: 0.12);
    final textColor =
        isPending ? const Color(0xFF9CA3AF) : const Color(0xFF111111);
    final subColor =
        isPending ? const Color(0xFFE5E7EB) : const Color(0xFF6B7280);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon + connector column
          Column(
            children: [
              AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) {
                  final scale = isActive ? 1 + (_pulse.value * 0.08) : 1.0;
                  final glow = isActive
                      ? (0.45 + _pulse.value * 0.25)
                      : (isDone ? 0.25 : 0.0);
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: bg,
                        shape: BoxShape.circle,
                        boxShadow: [
                          if (glow > 0)
                            BoxShadow(
                              color: stage.color.withValues(alpha: glow * 0.5),
                              blurRadius: 16,
                              spreadRadius: 1,
                            ),
                        ],
                      ),
                      child: Icon(
                        isDone ? Icons.check_rounded : stage.icon,
                        color: iconColor,
                        size: 22,
                      ),
                    ),
                  );
                },
              ),
              if (!widget.isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: isDone
                        ? stage.color.withValues(alpha: 0.35)
                        : const Color(0xFFE2E8F0),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          // Text column
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: widget.isLast ? 8 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          stage.label,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (isActive)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: stage.color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'Sekarang',
                            style: TextStyle(
                              color: stage.color,
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
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

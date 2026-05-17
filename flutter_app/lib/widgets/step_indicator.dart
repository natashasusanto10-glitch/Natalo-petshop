import 'package:flutter/material.dart';

import '../utils/motion_prefs.dart';

/// Step indicator horizontal — pakai di checkout flow:
/// Cart → Alamat → Pembayaran → Selesai
///
/// Stage selesai = filled brand color + check icon
/// Stage aktif = filled + number + pulse glow
/// Stage future = outline + gray
class StepIndicator extends StatelessWidget {
  final List<String> labels;
  final int currentIndex;

  const StepIndicator({
    super.key,
    required this.labels,
    required this.currentIndex,
  });

  @override
  Widget build(BuildContext context) {
    const brandBlue = Color(0xFF1E5FBF);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: List.generate(labels.length * 2 - 1, (i) {
          if (i.isOdd) {
            // Connector line.
            final left = i ~/ 2;
            final reached = left < currentIndex;
            return Expanded(
              child: AnimatedContainer(
                duration: MotionPrefs.effective(
                  context,
                  const Duration(milliseconds: 320),
                ),
                margin: const EdgeInsets.symmetric(horizontal: 6),
                height: 2,
                color:
                    reached ? brandBlue : const Color(0xFFE2E8F0),
              ),
            );
          }
          final index = i ~/ 2;
          final isDone = index < currentIndex;
          final isActive = index == currentIndex;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _StageDot(
                isDone: isDone,
                isActive: isActive,
                index: index,
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: 64,
                child: Text(
                  labels[index],
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isDone || isActive
                        ? brandBlue
                        : const Color(0xFF9CA3AF),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _StageDot extends StatefulWidget {
  final bool isDone;
  final bool isActive;
  final int index;

  const _StageDot({
    required this.isDone,
    required this.isActive,
    required this.index,
  });

  @override
  State<_StageDot> createState() => _StageDotState();
}

class _StageDotState extends State<_StageDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (widget.isActive) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_StageDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!widget.isActive && _pulse.isAnimating) {
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
    const brandBlue = Color(0xFF1E5FBF);
    final reduce = MotionPrefs.shouldReduce(context);
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final glow = widget.isActive && !reduce
            ? (0.35 + _pulse.value * 0.4)
            : 0.0;
        return Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: widget.isDone || widget.isActive
                ? brandBlue
                : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
              color: widget.isDone || widget.isActive
                  ? brandBlue
                  : const Color(0xFFE2E8F0),
              width: 1.6,
            ),
            boxShadow: glow > 0
                ? [
                    BoxShadow(
                      color: brandBlue.withValues(alpha: glow * 0.5),
                      blurRadius: 14,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: widget.isDone
              ? const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 16,
                )
              : Text(
                  '${widget.index + 1}',
                  style: TextStyle(
                    color: widget.isActive
                        ? Colors.white
                        : const Color(0xFF9CA3AF),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
        );
      },
    );
  }
}

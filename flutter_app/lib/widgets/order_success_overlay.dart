import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/haptics.dart';
import '../utils/motion_prefs.dart';

/// Order success overlay — celebrate moment setelah checkout sukses.
///
/// - Animated checkmark dengan circle scale + draw
/// - Particle confetti (no Lottie asset needed — custom painter)
/// - Auto-dismiss setelah 2.5 detik atau tap layar
///
/// Pakai:
/// ```dart
/// await showOrderSuccess(context, orderNumber: 'NAT-2026...');
/// ```
Future<void> showOrderSuccess(
  BuildContext context, {
  required String orderNumber,
  String? message,
}) {
  AppHaptics.success();
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, __, ___) => _OrderSuccessOverlay(
        orderNumber: orderNumber,
        message: message,
      ),
    ),
  );
}

class _OrderSuccessOverlay extends StatefulWidget {
  final String orderNumber;
  final String? message;

  const _OrderSuccessOverlay({
    required this.orderNumber,
    this.message,
  });

  @override
  State<_OrderSuccessOverlay> createState() => _OrderSuccessOverlayState();
}

class _OrderSuccessOverlayState extends State<_OrderSuccessOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _check;
  late final AnimationController _confetti;

  @override
  void initState() {
    super.initState();
    _check = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    _confetti = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..forward();

    // Auto-dismiss setelah 2.5 detik.
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  void dispose() {
    _check.dispose();
    _confetti.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MotionPrefs.shouldReduce(context);
    return GestureDetector(
      onTap: () => Navigator.of(context).maybePop(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            // Confetti — full screen behind card.
            if (!reduce)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _confetti,
                  builder: (context, _) {
                    return CustomPaint(
                      painter: _ConfettiPainter(progress: _confetti.value),
                    );
                  },
                ),
              ),
            // Success card center.
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: AnimatedBuilder(
                  animation: _check,
                  builder: (context, _) {
                    final t = Curves.easeOutBack.transform(
                      _check.value.clamp(0.0, 1.0),
                    );
                    return Transform.scale(
                      scale: reduce ? 1.0 : t,
                      child: Container(
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              blurRadius: 32,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 88,
                              height: 88,
                              decoration: const BoxDecoration(
                                color: Color(0xFF16A34A),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.check_rounded,
                                color: Colors.white,
                                size: 56,
                              ),
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              'Pesanan Diterima!',
                              style: TextStyle(
                                color: Color(0xFF111111),
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              widget.message ?? 'Order ${widget.orderNumber}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF6B7280),
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                height: 1.4,
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
          ],
        ),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  final double progress;
  static const _count = 36;
  static const _colors = [
    Color(0xFF1E5FBF),
    Color(0xFF16A34A),
    Color(0xFFEF4444),
    Color(0xFFF59E0B),
    Color(0xFF7C3AED),
    Color(0xFFEAB308),
  ];

  const _ConfettiPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final rng = math.Random(42);
    for (var i = 0; i < _count; i++) {
      // Stagger start offset per particle.
      final delay = rng.nextDouble() * 0.3;
      final t = (progress - delay).clamp(0.0, 1.0);
      if (t <= 0) continue;
      final startX = rng.nextDouble() * size.width;
      // Fall from top (-50) to bottom (size.height + 50) with arc.
      final yEnd = size.height + 50;
      final y = -50 + (yEnd + 50) * Curves.easeIn.transform(t);
      final swayAmp = 24 + rng.nextDouble() * 36;
      final sway = math.sin(t * math.pi * 4 + i) * swayAmp;
      final x = startX + sway;
      final rotate = t * (rng.nextDouble() * 8 - 4);
      final fade = (1 - t).clamp(0.0, 1.0);
      paint.color = _colors[i % _colors.length].withValues(alpha: fade);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rotate);
      // Mix rect + circle confetti shapes.
      if (i.isEven) {
        canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: 8, height: 12),
          paint,
        );
      } else {
        canvas.drawCircle(Offset.zero, 4, paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

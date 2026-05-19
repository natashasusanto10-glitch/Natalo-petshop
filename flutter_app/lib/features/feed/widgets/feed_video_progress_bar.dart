import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class FeedVideoProgressBar extends StatefulWidget {
  final VideoPlayerController controller;
  final double height;
  final BorderRadius? borderRadius;

  const FeedVideoProgressBar({
    super.key,
    required this.controller,
    this.height = 2.0,
    this.borderRadius,
  });

  @override
  State<FeedVideoProgressBar> createState() => _FeedVideoProgressBarState();
}

class _FeedVideoProgressBarState extends State<FeedVideoProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _visualProgressController;

  VideoPlayerController get _videoController => widget.controller;

  @override
  void initState() {
    super.initState();

    _visualProgressController = AnimationController(
      vsync: this,
      lowerBound: 0.0,
      upperBound: 1.0,
    );

    _videoController.addListener(_handleVideoValueChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncFromVideo(force: true);
    });
  }

  @override
  void didUpdateWidget(covariant FeedVideoProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleVideoValueChanged);
      widget.controller.addListener(_handleVideoValueChanged);
      _syncFromVideo(force: true);
    }
  }

  void _handleVideoValueChanged() {
    _syncFromVideo();
  }

  void _syncFromVideo({bool force = false}) {
    final value = _videoController.value;

    if (!value.isInitialized) {
      _visualProgressController.stop();
      _setVisualProgress(0.0);
      return;
    }

    final duration = value.duration;
    final position = value.position;

    if (duration <= Duration.zero) {
      _visualProgressController.stop();
      _setVisualProgress(0.0);
      return;
    }

    final realProgress = _calculateProgress(position, duration);
    final shouldPauseVisualProgress =
        !value.isPlaying || value.isBuffering || value.hasError;

    if (shouldPauseVisualProgress) {
      _visualProgressController.stop();
      _setVisualProgress(realProgress);
      return;
    }

    final visualProgress = _visualProgressController.value;
    final drift = (visualProgress - realProgress).abs();
    final needsResync = force || drift > 0.025;

    if (needsResync) {
      _setVisualProgress(realProgress);
    }

    if (!_visualProgressController.isAnimating || needsResync) {
      final remainingMs = math.max(
        1,
        duration.inMilliseconds - position.inMilliseconds,
      );
      _visualProgressController.duration = Duration(milliseconds: remainingMs);
      _visualProgressController.forward(from: _visualProgressController.value);
    }

    final isNearEnd = duration.inMilliseconds > 0 &&
        position.inMilliseconds >= duration.inMilliseconds - 120;

    if (isNearEnd && !value.isLooping) {
      _visualProgressController.stop();
      _setVisualProgress(1.0);
    }
  }

  double _calculateProgress(Duration position, Duration duration) {
    final durationMs = duration.inMilliseconds;
    if (durationMs <= 0) return 0.0;

    final progress = position.inMilliseconds / durationMs;
    return progress.clamp(0.0, 1.0);
  }

  void _setVisualProgress(double value) {
    final safeValue = value.clamp(0.0, 1.0);

    if ((_visualProgressController.value - safeValue).abs() > 0.001) {
      _visualProgressController.value = safeValue;
    }
  }

  @override
  void dispose() {
    _videoController.removeListener(_handleVideoValueChanged);
    _visualProgressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: ClipRRect(
          borderRadius: widget.borderRadius ?? BorderRadius.circular(999),
          child: AnimatedBuilder(
            animation: _visualProgressController,
            builder: (context, _) {
              return CustomPaint(
                painter: _FeedVideoProgressPainter(
                  progress: _visualProgressController.value,
                ),
                child: const SizedBox.expand(),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _FeedVideoProgressPainter extends CustomPainter {
  final double progress;

  const _FeedVideoProgressPainter({
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final y = size.height / 2;

    final backgroundPaint = Paint()
      ..color = const Color(0x55FFFFFF)
      ..strokeWidth = size.height
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    final progressPaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..strokeWidth = size.height
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      backgroundPaint,
    );

    canvas.drawLine(
      Offset(0, y),
      Offset(size.width * progress.clamp(0.0, 1.0), y),
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _FeedVideoProgressPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

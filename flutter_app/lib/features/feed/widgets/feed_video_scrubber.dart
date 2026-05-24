import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'feed_video_progress_bar.dart';

/// Draggable progress bar untuk Feed/Reels video.
///
/// Wrap `FeedVideoProgressBar` existing (preserve smooth interpolation
/// animation) dengan `GestureDetector` untuk handle drag + tap-to-seek.
///
/// Layout:
///  - Touch hit area: 28px tall (Material design min 44px tidak realistis
///    untuk thin scrubber — 28px adalah kompromis IG Reels-like).
///  - Visual line: 2px (4px saat scrubbing) di tengah hit area.
///  - Thumb circle: 12px, visible hanya saat scrubbing.
///  - Time preview: "M:SS" tooltip di atas thumb, visible saat scrubbing.
///
/// Gesture conflict:
///  - Vertical PageView swipe (next/prev video) tidak conflict — scrubber
///    pakai `onHorizontalDragXxx` saja, PageView vertical.
///  - Long-press di media (pause / 2x speed) — caller harus guard
///    `if (isScrubbing) return` di handler-nya. Scrubber notify parent
///    via `onScrubbingChanged(bool)` callback.
///  - Tap di scrubber hit area → seek-jump (bukan toggle play/pause
///    media). Scrubber pakai `HitTestBehavior.opaque` → absorb tap
///    sebelum reach media GestureDetector di bawah-nya di Stack.
///
/// Visual state:
///  - Normal: thin white bar with low-opacity track.
///  - Scrubbing: thicker bar + visible thumb + time tooltip.
class FeedVideoScrubber extends StatefulWidget {
  final VideoPlayerController controller;

  /// Hanya widget yang `isCurrent` yang process scrub (paranoid guard —
  /// prevent stale post yang masih ke-render menerima gesture).
  final bool isCurrent;

  /// Notify parent saat scrub state berubah. Parent harus guard
  /// long-press handler dengan `if (isScrubbing) return`.
  final ValueChanged<bool> onScrubbingChanged;

  const FeedVideoScrubber({
    super.key,
    required this.controller,
    required this.isCurrent,
    required this.onScrubbingChanged,
  });

  @override
  State<FeedVideoScrubber> createState() => _FeedVideoScrubberState();
}

class _FeedVideoScrubberState extends State<FeedVideoScrubber> {
  bool _isScrubbing = false;
  bool _wasPlayingBeforeScrub = false;
  Duration _scrubPosition = Duration.zero;

  void _startScrub(double dx, double width) {
    if (!widget.isCurrent) return;
    final ctrl = widget.controller;
    if (!ctrl.value.isInitialized) return;
    if (ctrl.value.duration <= Duration.zero) return;

    _wasPlayingBeforeScrub = ctrl.value.isPlaying;
    if (_wasPlayingBeforeScrub) {
      ctrl.pause();
    }
    setState(() => _isScrubbing = true);
    widget.onScrubbingChanged(true);
    _updateScrub(dx, width);
  }

  void _updateScrub(double dx, double width) {
    if (!_isScrubbing) return;
    final duration = widget.controller.value.duration;
    if (duration <= Duration.zero || width <= 0) return;

    final progress = (dx / width).clamp(0.0, 1.0);
    final targetMs = (duration.inMilliseconds * progress).round();
    setState(() => _scrubPosition = Duration(milliseconds: targetMs));
  }

  Future<void> _endScrub() async {
    if (!_isScrubbing) return;
    final ctrl = widget.controller;
    final wasPlaying = _wasPlayingBeforeScrub;
    final target = _scrubPosition;

    // Reset scrub state SEBELUM seek supaya parent gesture handler
    // (long-press dll) bisa langsung aktif lagi setelah scrub release.
    setState(() {
      _isScrubbing = false;
      _wasPlayingBeforeScrub = false;
    });
    widget.onScrubbingChanged(false);

    try {
      await ctrl.seekTo(target);
      if (wasPlaying && mounted) {
        await ctrl.play();
      }
    } catch (_) {
      // Defensive: seek bisa fail kalau controller di-dispose tengah jalan
      // (mis. user swipe ke post lain saat masih scrub). Silent ignore.
    }
  }

  /// Tap-to-seek (no drag) — seek instant ke posisi tap.
  void _onTap(double dx, double width) {
    if (!widget.isCurrent) return;
    final ctrl = widget.controller;
    if (!ctrl.value.isInitialized) return;
    final duration = ctrl.value.duration;
    if (duration <= Duration.zero || width <= 0) return;

    final progress = (dx / width).clamp(0.0, 1.0);
    final targetMs = (duration.inMilliseconds * progress).round();
    final target = Duration(milliseconds: targetMs);
    final wasPlaying = ctrl.value.isPlaying;

    ctrl.seekTo(target).then((_) {
      if (wasPlaying && mounted) ctrl.play();
    }).catchError((_) {
      // Same defensive as endScrub.
    });
  }

  @override
  void didUpdateWidget(covariant FeedVideoScrubber oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset scrub kalau widget berubah controller / pindah ke non-current.
    if (oldWidget.controller != widget.controller || !widget.isCurrent) {
      if (_isScrubbing) {
        setState(() {
          _isScrubbing = false;
          _wasPlayingBeforeScrub = false;
          _scrubPosition = Duration.zero;
        });
        widget.onScrubbingChanged(false);
      }
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Duration _displayPosition() {
    if (_isScrubbing) return _scrubPosition;
    return widget.controller.value.position;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // 28px hit area dengan visual bar di bottom (line up dengan bottom
        // edge video frame). Thumb + tooltip overlay di atas.
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (details) =>
              _startScrub(details.localPosition.dx, width),
          onHorizontalDragUpdate: (details) =>
              _updateScrub(details.localPosition.dx, width),
          onHorizontalDragEnd: (_) => _endScrub(),
          onHorizontalDragCancel: _endScrub,
          onTapUp: (details) => _onTap(details.localPosition.dx, width),
          child: SizedBox(
            height: 28,
            width: width,
            child: ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: widget.controller,
              builder: (context, value, _) {
                if (!value.isInitialized ||
                    value.duration <= Duration.zero) {
                  return const SizedBox.shrink();
                }
                final pos = _displayPosition();
                final progress = (pos.inMilliseconds /
                        value.duration.inMilliseconds)
                    .clamp(0.0, 1.0);
                final thumbLeft = (width * progress - 6).clamp(0.0, width - 12);

                return Stack(
                  alignment: Alignment.bottomLeft,
                  clipBehavior: Clip.none,
                  children: [
                    // ── Progress bar visual ──
                    // Saat scrubbing: bar 4px + freeze (FeedVideoProgressBar
                    // pakai value listener — saat controller di-pause +
                    // seek manual, animation tetap track posisi current).
                    // Aku pakai 2 strategi:
                    // - Normal: pakai FeedVideoProgressBar (smooth animated).
                    // - Scrubbing: pakai static `_StaticProgressBar` yang
                    //   render progress dari _scrubPosition (real-time
                    //   user input, tidak ke-affect controller listener).
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _isScrubbing
                          ? _StaticProgressBar(
                              progress: progress,
                              height: 4,
                            )
                          : FeedVideoProgressBar(
                              controller: widget.controller,
                              height: 2,
                            ),
                    ),
                    // ── Thumb circle (hanya saat scrubbing) ──
                    if (_isScrubbing)
                      Positioned(
                        left: thumbLeft,
                        bottom: -4,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.32),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                    // ── Time tooltip (hanya saat scrubbing) ──
                    if (_isScrubbing)
                      Positioned(
                        left: (width * progress - 28)
                            .clamp(0.0, width - 56),
                        bottom: 14,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.70),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${_formatDuration(pos)} / ${_formatDuration(value.duration)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// Static progress bar (no animation) untuk render selama scrubbing.
/// Pakai progress value langsung dari scrub position user, bukan dari
/// VideoPlayerController.position (controller di-pause saat scrub).
class _StaticProgressBar extends StatelessWidget {
  final double progress;
  final double height;

  const _StaticProgressBar({
    required this.progress,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: CustomPaint(
          painter: _StaticProgressPainter(progress: progress),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _StaticProgressPainter extends CustomPainter {
  final double progress;

  const _StaticProgressPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final y = size.height / 2;
    final trackPaint = Paint()
      ..color = const Color(0x55FFFFFF)
      ..strokeWidth = size.height
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    final progressPaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..strokeWidth = size.height
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), trackPaint);
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width * progress.clamp(0.0, 1.0), y),
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _StaticProgressPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

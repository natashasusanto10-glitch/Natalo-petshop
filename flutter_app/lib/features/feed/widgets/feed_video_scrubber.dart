import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'feed_video_progress_bar.dart';

/// Draggable progress bar untuk Feed/Reels video.
///
/// Performance design:
///  - **No setState pada drag update** — pakai `ValueNotifier<double>`
///    untuk scrub progress. Hanya widget kecil (progress paint + thumb +
///    tooltip) yang rebuild via `ValueListenableBuilder`. Parent Stack,
///    LayoutBuilder, dan controller listener TIDAK rebuild per drag event.
///  - **CustomPaint dengan shouldRepaint comparison** — paint cuma terjadi
///    kalau progress berubah aktual.
///  - **RepaintBoundary** wraps animated subtree — isolasi repaint dari
///    parent video frame.
///
/// Sebelumnya pakai `setState` pada `_updateScrub` → setiap drag event
/// (60-120 fps) rebuild seluruh widget tree termasuk
/// `ValueListenableBuilder<VideoPlayerValue>` + `LayoutBuilder` + Stack.
/// Result: laggy/jumpy scrub. Fix: isolate hot-path ke notifier.
///
/// Layout:
///  - Touch hit area: 28px tall.
///  - Visual line: 2px (4px saat scrubbing) di bottom.
///  - Thumb circle: 12px, visible hanya saat scrubbing.
///  - Time tooltip: "M:SS / M:SS" di atas thumb saat scrubbing.
class FeedVideoScrubber extends StatefulWidget {
  final VideoPlayerController controller;
  final bool isCurrent;
  final ValueChanged<bool> onScrubbingChanged;

  /// Kontrak §2.1 (KUNCI USER) — `true` saat playback dikuasai coordinator
  /// (controller pinjaman). Dalam mode ini scrubber HANYA seek: TIDAK
  /// memanggil `pause()`/`play()` langsung ke controller. Alasannya: pause
  /// saat drag lalu app ke background (coordinator set `_suspended`) lalu
  /// lepas drag → `play()` menembus suspend = audio hantu di background.
  /// Seek tetap aman (coordinator baca posisi live). Default `false` =
  /// perilaku lama (pause-saat-drag + resume-setelah-drag), nol perubahan.
  final bool managed;

  const FeedVideoScrubber({
    super.key,
    required this.controller,
    required this.isCurrent,
    required this.onScrubbingChanged,
    this.managed = false,
  });

  @override
  State<FeedVideoScrubber> createState() => _FeedVideoScrubberState();
}

class _FeedVideoScrubberState extends State<FeedVideoScrubber> {
  // Scrub progress (0.0 - 1.0). Updated tiap drag event via
  // ValueNotifier — bypass setState supaya repaint terisolasi ke
  // progress bar visual only, bukan full widget tree.
  final ValueNotifier<double> _scrubProgress = ValueNotifier<double>(0.0);

  // Scrub state flag — pakai setState karena rebuild jarang (start/end).
  // Switch antara FeedVideoProgressBar (smooth animated) vs static
  // progress bar yang listen ke _scrubProgress notifier.
  bool _isScrubbing = false;

  bool _wasPlayingBeforeScrub = false;

  // Cached layout width — di-set sekali via LayoutBuilder di build, reused
  // di drag handlers. Hindari rebuild LayoutBuilder di hot path.
  double _cachedWidth = 0;

  void _startScrub(double dx) {
    if (!widget.isCurrent || _cachedWidth <= 0) return;
    final ctrl = widget.controller;
    if (!ctrl.value.isInitialized) return;
    if (ctrl.value.duration <= Duration.zero) return;

    // Managed: JANGAN pause controller (coordinator pemilik). Biarkan video
    // tetap jalan saat scrub — hanya seek. Nol ctrl.pause/play dari scrubber.
    _wasPlayingBeforeScrub = ctrl.value.isPlaying;
    if (!widget.managed && _wasPlayingBeforeScrub) {
      ctrl.pause();
    }
    setState(() => _isScrubbing = true);
    widget.onScrubbingChanged(true);
    _writeProgress(dx);
  }

  void _writeProgress(double dx) {
    if (_cachedWidth <= 0) return;
    final progress = (dx / _cachedWidth).clamp(0.0, 1.0);
    // No setState — direct write ke notifier. Builder yang subscribe
    // di-rebuild secara lokal (cuma paint + thumb + tooltip).
    _scrubProgress.value = progress;
  }

  Future<void> _endScrub() async {
    if (!_isScrubbing) return;
    final ctrl = widget.controller;
    final wasPlaying = _wasPlayingBeforeScrub;
    final progress = _scrubProgress.value;
    final duration = ctrl.value.duration;
    final targetMs = (duration.inMilliseconds * progress).round();
    final target = Duration(milliseconds: targetMs);

    setState(() {
      _isScrubbing = false;
      _wasPlayingBeforeScrub = false;
    });
    widget.onScrubbingChanged(false);

    try {
      await ctrl.seekTo(target);
      // Managed: jangan resume — video tak pernah di-pause oleh scrubber, dan
      // resume di sini bisa menembus suspend coordinator (audio hantu).
      if (!widget.managed && wasPlaying && mounted) {
        await ctrl.play();
      }
    } catch (_) {
      // Defensive: seek bisa fail kalau controller di-dispose.
    }
  }

  /// Tap-to-seek (no drag) — seek instant ke posisi tap.
  void _onTap(double dx) {
    if (!widget.isCurrent || _cachedWidth <= 0) return;
    final ctrl = widget.controller;
    if (!ctrl.value.isInitialized) return;
    final duration = ctrl.value.duration;
    if (duration <= Duration.zero) return;

    final progress = (dx / _cachedWidth).clamp(0.0, 1.0);
    final targetMs = (duration.inMilliseconds * progress).round();
    final target = Duration(milliseconds: targetMs);
    final wasPlaying = ctrl.value.isPlaying;

    ctrl.seekTo(target).then((_) {
      // Managed: seek-only, jangan play (lihat _endScrub) — coordinator
      // pemilik playback, resume langsung bisa menembus suspend.
      if (!widget.managed && wasPlaying && mounted) ctrl.play();
    }).catchError((_) {});
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
        });
        _scrubProgress.value = 0.0;
        widget.onScrubbingChanged(false);
      }
    }
  }

  @override
  void dispose() {
    _scrubProgress.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Cache width supaya drag handlers tidak butuh LayoutBuilder
        // rebuild. LayoutBuilder ini hanya rebuild saat parent resize
        // (rare), bukan per drag event.
        _cachedWidth = constraints.maxWidth;
        final width = _cachedWidth;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (details) =>
              _startScrub(details.localPosition.dx),
          onHorizontalDragUpdate: (details) =>
              _writeProgress(details.localPosition.dx),
          onHorizontalDragEnd: (_) => _endScrub(),
          onHorizontalDragCancel: _endScrub,
          onTapUp: (details) => _onTap(details.localPosition.dx),
          child: SizedBox(
            height: 28,
            width: width,
            child: RepaintBoundary(
              child: Stack(
                alignment: Alignment.bottomLeft,
                clipBehavior: Clip.none,
                children: [
                  // ── Progress bar visual ──
                  // Normal: FeedVideoProgressBar yang smooth animated
                  // dari controller listener.
                  // Scrubbing: static bar yang track _scrubProgress
                  // notifier (real-time user input).
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _isScrubbing
                        ? _ScrubbingProgressBar(
                            progressNotifier: _scrubProgress,
                            height: 4,
                          )
                        : FeedVideoProgressBar(
                            controller: widget.controller,
                            height: 2,
                          ),
                  ),
                  // ── Thumb circle + Time tooltip (hanya saat scrubbing) ──
                  // Listen ke _scrubProgress notifier supaya rebuild
                  // tanpa setState. Cuma 2 widget kecil yang rebuild
                  // per drag event, bukan full Stack.
                  if (_isScrubbing)
                    ValueListenableBuilder<double>(
                      valueListenable: _scrubProgress,
                      builder: (context, progress, _) {
                        final ctrl = widget.controller;
                        final duration = ctrl.value.duration;
                        final pos = Duration(
                          milliseconds:
                              (duration.inMilliseconds * progress).round(),
                        );
                        final thumbLeft =
                            (width * progress - 6).clamp(0.0, width - 12);
                        final tooltipLeft = (width * progress - 28)
                            .clamp(0.0, width - 56);
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
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
                                      color: Colors.black
                                          .withValues(alpha: 0.32),
                                      blurRadius: 4,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Positioned(
                              left: tooltipLeft,
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
                                  '${_formatDuration(pos)} / ${_formatDuration(duration)}',
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
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Progress bar yang listen ke `ValueNotifier<double>` — dipakai saat
/// scrubbing untuk render real-time dari user input tanpa setState
/// parent.
///
/// CustomPainter `shouldRepaint` compares old/new progress → skip paint
/// kalau identical. Plus `RepaintBoundary` di parent → repaint terisolasi.
class _ScrubbingProgressBar extends StatelessWidget {
  final ValueListenable<double> progressNotifier;
  final double height;

  const _ScrubbingProgressBar({
    required this.progressNotifier,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: ValueListenableBuilder<double>(
          valueListenable: progressNotifier,
          builder: (context, progress, _) {
            return CustomPaint(
              painter: _ScrubProgressPainter(progress: progress),
              child: const SizedBox.expand(),
            );
          },
        ),
      ),
    );
  }
}

class _ScrubProgressPainter extends CustomPainter {
  final double progress;

  const _ScrubProgressPainter({required this.progress});

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
  bool shouldRepaint(covariant _ScrubProgressPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

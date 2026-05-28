import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:video_player/video_player.dart';

/// Progress bar smooth untuk Feed/Reels video.
///
/// **Pendekatan: Ticker-based extrapolation (bukan AnimationController).**
///
/// VideoPlayerController hanya report `value.position` di cadence kasar
/// (~setiap beberapa ratus ms, platform-dependent). Kalau progress bar
/// paint langsung dari position → choppy (freeze lalu loncat tiap poll).
/// Kalau pakai AnimationController yang tween ke 1.0 dengan asumsi rate
/// 1x → loncat saat 2x (animasi ketinggalan, lalu resync paksa).
///
/// Solusi di sini: Ticker fire tiap frame (~60fps). Setiap frame kita
/// EKSTRAPOLASI posisi dari anchor (posisi + wall-clock terakhir yang
/// di-observe) pakai `playbackSpeed` REAL-TIME:
///
///   estimasi = anchorPosition + (now - anchorWall) * playbackSpeed
///
/// Karena speed dibaca tiap frame, 1x/2x/berapapun otomatis benar — tidak
/// ada asumsi rate. Saat controller report posisi baru, kita re-anchor:
///   - Forward-only smooth correction (estimasi ketinggalan → maju mulus)
///   - Overshoot kecil → rebase anchor ke estimasi (TIDAK loncat mundur)
///   - Jump besar (seek / loop) → hard re-anchor (snap memang diharapkan)
///
/// Hasil: smooth di semua speed, no resync jump, no backward micro-jump.
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
  late final Ticker _ticker;

  /// Progress 0.0–1.0 untuk render. ValueNotifier → repaint terisolasi
  /// (hanya CustomPaint subtree), bukan setState full widget.
  final ValueNotifier<double> _progress = ValueNotifier<double>(0.0);

  // Anchor untuk ekstrapolasi: posisi video (ms) + wall-clock (ticker
  // elapsed) saat anchor itu di-set. Estimasi posisi = anchorPos +
  // (elapsedSekarang - anchorWall) * speed.
  int _anchorPositionMs = 0;
  Duration _anchorWall = Duration.zero;
  int _lastReportedMs = -1;
  bool _hasAnchor = false;

  // Toleransi (ms) untuk distinguish drift normal vs seek/loop. Di atas
  // ini = hard snap (posisi melompat karena seek/loop/stall).
  static const int _hardReanchorThresholdMs = 400;

  VideoPlayerController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(covariant FeedVideoProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      // Controller baru (post lain) → reset anchor.
      _hasAnchor = false;
      _lastReportedMs = -1;
    }
  }

  void _onTick(Duration elapsed) {
    final v = _c.value;
    if (!v.isInitialized) {
      _set(0);
      return;
    }
    final durMs = v.duration.inMilliseconds;
    if (durMs <= 0) {
      _set(0);
      return;
    }

    final reportedMs = v.position.inMilliseconds;
    final isPlaying = v.isPlaying && !v.isBuffering && !v.hasError;
    final speed = v.playbackSpeed > 0 ? v.playbackSpeed : 1.0;

    // First run — anchor langsung ke posisi sekarang.
    if (!_hasAnchor) {
      _anchorPositionMs = reportedMs;
      _anchorWall = elapsed;
      _lastReportedMs = reportedMs;
      _hasAnchor = true;
      _set((reportedMs / durMs).clamp(0.0, 1.0));
      return;
    }

    // Paused / buffering → track posisi report apa adanya, freeze anchor.
    if (!isPlaying) {
      _anchorPositionMs = reportedMs;
      _anchorWall = elapsed;
      _lastReportedMs = reportedMs;
      _set((reportedMs / durMs).clamp(0.0, 1.0));
      return;
    }

    // Ekstrapolasi dari anchor pakai speed real-time.
    final dt = (elapsed - _anchorWall).inMilliseconds;
    double estMs = _anchorPositionMs + dt * speed;

    // Controller report posisi baru → reconcile (forward-only / hard snap).
    if (reportedMs != _lastReportedMs) {
      _lastReportedMs = reportedMs;
      final diff = reportedMs - estMs; // + = report di depan estimasi
      if (diff.abs() > _hardReanchorThresholdMs) {
        // Seek / loop / stall besar → snap ke report (memang diharapkan).
        estMs = reportedMs.toDouble();
        _anchorPositionMs = reportedMs;
        _anchorWall = elapsed;
      } else if (diff > 0) {
        // Playback sedikit di depan estimasi → maju mulus ke report.
        estMs = reportedMs.toDouble();
        _anchorPositionMs = reportedMs;
        _anchorWall = elapsed;
      } else {
        // Estimasi overshoot sedikit → JANGAN loncat mundur. Rebase anchor
        // ke estimasi sekarang, lanjut dari sini (estMs tetap).
        _anchorPositionMs = estMs.round();
        _anchorWall = elapsed;
      }
    }

    if (estMs > durMs) estMs = durMs.toDouble();
    _set((estMs / durMs).clamp(0.0, 1.0));
  }

  void _set(double p) {
    final clamped = p.clamp(0.0, 1.0);
    // Hanya update kalau berubah cukup signifikan → skip repaint redundan
    // (mis. saat paused, progress identik tiap tick = no repaint).
    if ((_progress.value - clamped).abs() > 0.0001) {
      _progress.value = clamped;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _progress.dispose();
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
          child: ValueListenableBuilder<double>(
            valueListenable: _progress,
            builder: (context, progress, _) {
              return CustomPaint(
                painter: _FeedVideoProgressPainter(progress: progress),
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

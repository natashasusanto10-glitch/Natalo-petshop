import 'dart:async';

import 'package:flutter/material.dart';

import '../state/feed_upload_store.dart';

/// Mini upload relay card — IG-style background upload indicator yang
/// muncul di Beranda (di bawah search bar) saat user submit posting.
///
/// User langsung kembali ke Beranda setelah tap "Upload" — bisa scroll,
/// pindah tab, lihat produk. Card ini surface progress upload tanpa
/// blocking interaksi. Auto-dismiss saat success/waiting-review.
///
/// States:
/// - idle/null         → SizedBox.shrink (card hidden)
/// - preparing         → "Menyiapkan postingan..." + indeterminate bar
/// - uploading         → "Mengirim postingan..." + progress % + bar
/// - processing        → "Memproses postingan..." + 95% bar
/// - success           → "Postingan berhasil dipublikasikan" + check
/// - waitingReview     → "Postingan berhasil dikirim" + "Menunggu review"
/// - failed            → "Gagal mengirim postingan" + "Coba Lagi"
/// - cancelled         → "Upload dibatalkan"
class UploadRelayCard extends StatelessWidget {
  const UploadRelayCard({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: feedUploadStore,
      builder: (context, _) {
        final task = feedUploadStore.activeTask;
        return AnimatedSize(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, anim) {
              return FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, -0.1),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              );
            },
            child: task == null
                ? const SizedBox.shrink(key: ValueKey('upload-relay-empty'))
                : _RelayCardBody(
                    key: ValueKey('upload-relay-${task.localId}-${task.status}'),
                    task: task,
                  ),
          ),
        );
      },
    );
  }
}

class _RelayCardBody extends StatefulWidget {
  final FeedUploadTask task;
  const _RelayCardBody({super.key, required this.task});

  @override
  State<_RelayCardBody> createState() => _RelayCardBodyState();
}

class _RelayCardBodyState extends State<_RelayCardBody> {
  static const _nataloBlue = Color(0xFF1E5BFF);
  static const _textDark = Color(0xFF111827);
  static const _textMuted = Color(0xFF6B7280);
  static const _border = Color(0xFFE5EAF2);
  static const _errorRed = Color(0xFFEF4444);

  // ── Smooth progress (2-layer display) ──
  //
  // realProgress = widget.task.progress (source of truth dari upload).
  // displayProgress = visual yang ditampilkan ke user — kejar realProgress
  // dengan easing kecil per tick. Tujuan: hilangkan "10% → 20% → selesai"
  // jumpy feel, ganti dengan motion 1-100% yang halus + premium tapi
  // tetap jujur (tidak fake).
  double _displayProgress = 0;
  Timer? _smoother;

  // Tick interval — 16ms ≈ 60fps. Cukup smooth untuk eye.
  static const _tickInterval = Duration(milliseconds: 16);
  // Coefficient kejar — diff × 0.18 per tick. Spec recommend.
  // Lower = lebih halus tapi lebih lambat kejar realProgress.
  // Higher = lebih responsive tapi terasa "snappy" / kurang halus.
  static const _easeRate = 0.18;
  // Min step per tick supaya display tetap kelihatan gerak (no static feel).
  static const _minStep = 0.002;
  // Max step per tick supaya tidak loncat kasar (cap 3% jump).
  static const _maxStep = 0.03;

  @override
  void initState() {
    super.initState();
    // Init displayProgress dari realProgress di first build — kalau widget
    // mount setelah upload progress sudah berjalan (mis. user balik dari
    // tab lain), jangan reset ke 0.
    _displayProgress = widget.task.progress;
    _maybeStartSmoother();
  }

  @override
  void didUpdateWidget(covariant _RelayCardBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Saat task baru / status berubah → kick off smoother kalau diff > 0.
    _maybeStartSmoother();
  }

  @override
  void dispose() {
    _smoother?.cancel();
    super.dispose();
  }

  /// Start ticker kalau displayProgress < realProgress (perlu kejar).
  /// Idempotent — kalau timer sudah jalan, no-op.
  void _maybeStartSmoother() {
    final real = widget.task.progress.clamp(0.0, 1.0);
    if (_displayProgress >= real - 0.001) return;
    if (_smoother != null && _smoother!.isActive) return;

    _smoother = Timer.periodic(_tickInterval, (_) {
      if (!mounted) {
        _smoother?.cancel();
        return;
      }
      final realNow = widget.task.progress.clamp(0.0, 1.0);
      final diff = realNow - _displayProgress;
      if (diff <= 0.001) {
        // Sudah kejar — kalau realProgress tetap 1.0 lock display 1.0
        // dan stop ticker. Kalau masih in-progress (real < 1.0), stop
        // tunggu next update via didUpdateWidget.
        _smoother?.cancel();
        _smoother = null;
        if (realNow >= 0.999) {
          setState(() => _displayProgress = 1.0);
        }
        return;
      }
      // Step = diff × 0.18, clamp min 0.002 max 0.03 supaya tidak terlalu
      // pelan saat dekat target / tidak loncat kasar saat diff besar.
      final step = (diff * _easeRate).clamp(_minStep, _maxStep);
      setState(() {
        _displayProgress = (_displayProgress + step).clamp(0.0, 1.0);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final isFailed = task.status == FeedUploadStatus.failed;
    final isSuccess = task.status == FeedUploadStatus.success ||
        task.status == FeedUploadStatus.waitingReview;
    final isUploading = task.status == FeedUploadStatus.uploading ||
        task.status == FeedUploadStatus.preparing ||
        task.status == FeedUploadStatus.processing;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        elevation: 0,
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _LeadingIcon(
                  isFailed: isFailed,
                  isSuccess: isSuccess,
                ),
                const SizedBox(width: 12),
                Expanded(child: _buildContent(context, isFailed, isUploading)),
                if (isFailed) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    color: _textMuted,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 32,
                    ),
                    onPressed: () => feedUploadStore.dismissFailed(),
                    tooltip: 'Tutup',
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, bool isFailed, bool isUploading) {
    final task = widget.task;
    final title = _titleText();
    final subtitle = _subtitleText();
    // Tampilkan percent saat uploading + processing — supaya transisi
    // 90% → 95% (processing step) tetap visible smooth dari display layer.
    final showPercent = task.status == FeedUploadStatus.uploading ||
        task.status == FeedUploadStatus.processing;

    // Display value untuk percent + bar — dari _displayProgress, BUKAN
    // task.progress langsung. Saat success/waitingReview, force 1.0
    // supaya tidak stuck di 99% kalau smoother belum sempat reach 1.0.
    final isComplete = task.status == FeedUploadStatus.success ||
        task.status == FeedUploadStatus.waitingReview;
    final displayValue = isComplete ? 1.0 : _displayProgress;
    final percentInt = (displayValue * 100).round().clamp(0, 100);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _textDark,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
            ),
            if (showPercent && displayValue > 0)
              Text(
                '$percentInt%',
                style: const TextStyle(
                  color: _nataloBlue,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
        ),
        if (isFailed) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => feedUploadStore.retry(),
            behavior: HitTestBehavior.opaque,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.refresh_rounded, color: _errorRed, size: 16),
                SizedBox(width: 4),
                Text(
                  'Coba Lagi',
                  style: TextStyle(
                    color: _errorRed,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ] else if (isUploading) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              minHeight: 4,
              value: displayValue > 0 ? displayValue : null,
              backgroundColor: _border,
              valueColor: const AlwaysStoppedAnimation<Color>(_nataloBlue),
            ),
          ),
        ],
      ],
    );
  }

  String _titleText() {
    switch (widget.task.status) {
      case FeedUploadStatus.preparing:
        return 'Menyiapkan postingan...';
      case FeedUploadStatus.uploading:
        return 'Mengirim postingan...';
      case FeedUploadStatus.processing:
        // Spec: saat upload selesai tapi server masih proses,
        // tetap pakai pesan "Mengirim postingan..." supaya user tidak
        // bingung dengan istilah "Memproses". Lihat: spec final.
        return 'Mengirim postingan...';
      case FeedUploadStatus.success:
      case FeedUploadStatus.waitingReview:
        // Spec final state: "Postingan terkirim".
        return 'Postingan terkirim';
      case FeedUploadStatus.failed:
        return 'Gagal mengirim postingan';
      case FeedUploadStatus.cancelled:
        return 'Upload dibatalkan';
      case FeedUploadStatus.idle:
        return '';
    }
  }

  String _subtitleText() {
    switch (widget.task.status) {
      case FeedUploadStatus.waitingReview:
      case FeedUploadStatus.success:
        // Spec final state: "Menunggu review admin" — match flow Natalo
        // dimana customer post selalu PENDING_REVIEW sebelum visible.
        return 'Menunggu review admin';
      case FeedUploadStatus.failed:
        return widget.task.errorMessage ?? 'Periksa koneksi lalu coba lagi';
      case FeedUploadStatus.cancelled:
        return 'Upload dibatalkan oleh sistem';
      case FeedUploadStatus.processing:
      case FeedUploadStatus.uploading:
      case FeedUploadStatus.preparing:
      default:
        return 'Kamu tetap bisa lihat-lihat di Beranda';
    }
  }
}

class _LeadingIcon extends StatelessWidget {
  final bool isFailed;
  final bool isSuccess;
  const _LeadingIcon({required this.isFailed, required this.isSuccess});

  @override
  Widget build(BuildContext context) {
    if (isFailed) {
      return _circle(
        icon: Icons.error_outline_rounded,
        color: const Color(0xFFEF4444),
        bg: const Color(0xFFFEE2E2),
      );
    }
    if (isSuccess) {
      return _circle(
        icon: Icons.check_rounded,
        color: const Color(0xFF22C55E),
        bg: const Color(0xFFDCFCE7),
      );
    }
    return _circle(
      icon: Icons.cloud_upload_rounded,
      color: const Color(0xFF1E5BFF),
      bg: const Color(0xFFEAF3FF),
    );
  }

  Widget _circle({
    required IconData icon,
    required Color color,
    required Color bg,
  }) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Icon(icon, color: color, size: 22),
    );
  }
}

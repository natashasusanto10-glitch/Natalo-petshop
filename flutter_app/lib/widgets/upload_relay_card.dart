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

class _RelayCardBody extends StatelessWidget {
  final FeedUploadTask task;
  const _RelayCardBody({super.key, required this.task});

  static const _nataloBlue = Color(0xFF1E5BFF);
  static const _textDark = Color(0xFF111827);
  static const _textMuted = Color(0xFF6B7280);
  static const _border = Color(0xFFE5EAF2);
  static const _errorRed = Color(0xFFEF4444);

  @override
  Widget build(BuildContext context) {
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
    final title = _titleText();
    final subtitle = _subtitleText();
    final showPercent = task.status == FeedUploadStatus.uploading;

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
            if (showPercent && task.progress > 0)
              Text(
                '${(task.progress * 100).round()}%',
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
              value: task.progress > 0 ? task.progress : null,
              backgroundColor: _border,
              valueColor: const AlwaysStoppedAnimation<Color>(_nataloBlue),
            ),
          ),
        ],
      ],
    );
  }

  String _titleText() {
    switch (task.status) {
      case FeedUploadStatus.preparing:
        return 'Menyiapkan postingan...';
      case FeedUploadStatus.uploading:
        return 'Mengirim postingan...';
      case FeedUploadStatus.processing:
        return 'Memproses postingan...';
      case FeedUploadStatus.success:
        return 'Postingan berhasil dipublikasikan';
      case FeedUploadStatus.waitingReview:
        return 'Postingan berhasil dikirim';
      case FeedUploadStatus.failed:
        return 'Gagal mengirim postingan';
      case FeedUploadStatus.cancelled:
        return 'Upload dibatalkan';
      case FeedUploadStatus.idle:
        return '';
    }
  }

  String _subtitleText() {
    switch (task.status) {
      case FeedUploadStatus.waitingReview:
        return 'Menunggu review admin';
      case FeedUploadStatus.success:
        return 'Selesai';
      case FeedUploadStatus.failed:
        return task.errorMessage ?? 'Periksa koneksi lalu coba lagi';
      case FeedUploadStatus.cancelled:
        return 'Upload dibatalkan oleh sistem';
      case FeedUploadStatus.processing:
        return 'Kamu tetap bisa lihat-lihat di Beranda';
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

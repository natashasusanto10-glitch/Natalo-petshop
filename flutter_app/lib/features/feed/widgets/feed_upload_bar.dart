import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../state/feed_upload_store.dart';

/// Bar unggahan feed ramping ala IG — pengganti `UploadRelayCard` lama.
/// Spec §2A-5 (2026-07-10-feed-posting-fase2-ig-parity-design.md):
/// satu baris (thumbnail + copy + progress tipis + indikator kanan +
/// tombol batal), tinggi ±56px, muncul dipin di atas feed selama upload
/// background, single-flight mengikuti `FeedUploadStore`.
class FeedUploadBar extends StatelessWidget {
  const FeedUploadBar({super.key});

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
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, -0.08),
                  end: Offset.zero,
                ).animate(anim),
                child: child,
              ),
            ),
            child: task == null
                ? const SizedBox.shrink(key: ValueKey('feed-upload-bar-empty'))
                : _FeedUploadBarBody(
                    key: ValueKey('feed-upload-bar-${task.localId}'),
                    task: task,
                  ),
          ),
        );
      },
    );
  }
}

class _FeedUploadBarBody extends StatefulWidget {
  final FeedUploadTask task;
  const _FeedUploadBarBody({super.key, required this.task});

  @override
  State<_FeedUploadBarBody> createState() => _FeedUploadBarBodyState();
}

class _FeedUploadBarBodyState extends State<_FeedUploadBarBody>
    with TickerProviderStateMixin {
  // Sheen bergerak di progress bar ~1.7s, repeat.
  late final AnimationController _sheenController;
  // Cross-fade copy uploading — bergantian ~2s.
  Timer? _copyTicker;
  int _copyIndex = 0;

  static const _blue = Color(0xFF1E5BFF);
  static const _blueLight = Color(0xFF5B8CFF);
  static const _waitingBlue = Color(0xFF3B7BFF);
  static const _cardBg = Color(0xFF12151D);
  static const _hairline = Color.fromRGBO(255, 255, 255, 0.11);
  static const _tintBlueBg = Color.fromRGBO(91, 140, 255, 0.10);
  static const _tintBlueBorder = Color.fromRGBO(91, 140, 255, 0.38);
  static const _tintRedBg = Color.fromRGBO(255, 107, 107, 0.06);
  static const _tintRedBorder = Color.fromRGBO(255, 107, 107, 0.30);

  @override
  void initState() {
    super.initState();
    _sheenController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..repeat();
    _maybeStartCopyTicker();
  }

  @override
  void didUpdateWidget(covariant _FeedUploadBarBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.status != widget.task.status) {
      _copyIndex = 0;
      _maybeStartCopyTicker();
    }
  }

  @override
  void dispose() {
    _sheenController.dispose();
    _copyTicker?.cancel();
    super.dispose();
  }

  bool get _isUploadingPhase =>
      widget.task.status == FeedUploadStatus.uploading;

  void _maybeStartCopyTicker() {
    _copyTicker?.cancel();
    if (!_isUploadingPhase) return;
    _copyTicker = Timer.periodic(const Duration(milliseconds: 2000), (_) {
      if (!mounted) return;
      setState(() => _copyIndex = 1 - _copyIndex);
    });
  }

  String _mediaWord(FeedUploadTask task) {
    if (task.kind == FeedUploadKind.photo) {
      final n = task.photoFiles.length;
      return n > 1 ? '$n fotomu' : 'fotomu';
    }
    return 'videomu';
  }

  String _titleText() {
    final task = widget.task;
    switch (task.status) {
      case FeedUploadStatus.preparing:
        return 'Sebentar ya, ${_mediaWord(task)} lagi diposting…';
      case FeedUploadStatus.uploading:
        final alt = [
          'Sabar ya, jangan tutup aplikasinya dulu',
          '${_capitalize(_mediaWordSubject(task))} lagi jalan ke feed…',
        ];
        return alt[_copyIndex % alt.length];
      case FeedUploadStatus.processing:
        return 'Dikit lagi selesai nih…';
      case FeedUploadStatus.waitingReview:
        return 'Terkirim! Menunggu review admin dulu ya';
      case FeedUploadStatus.success:
        return 'Postingan kamu sudah tayang';
      case FeedUploadStatus.failed:
        return 'Gagal mengunggah';
      case FeedUploadStatus.cancelled:
        return 'Upload dibatalkan';
      case FeedUploadStatus.idle:
        return '';
    }
  }

  String _mediaWordSubject(FeedUploadTask task) {
    if (task.kind == FeedUploadKind.photo) {
      final n = task.photoFiles.length;
      return n > 1 ? '$n fotomu' : 'fotomu';
    }
    return 'videomu';
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final isFailed = task.status == FeedUploadStatus.failed;
    final isWaitingReview = task.status == FeedUploadStatus.waitingReview;
    final isSuccess = task.status == FeedUploadStatus.success;
    final isTerminal = isFailed || isWaitingReview || isSuccess;
    final showCancel = task.status == FeedUploadStatus.preparing ||
        task.status == FeedUploadStatus.uploading;
    final showBar = !isTerminal && task.status != FeedUploadStatus.cancelled;

    Color bg = _cardBg;
    Color border = _hairline;
    if (isWaitingReview || isSuccess) {
      bg = _tintBlueBg;
      border = _tintBlueBorder;
    } else if (isFailed) {
      bg = _tintRedBg;
      border = _tintRedBorder;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border),
          boxShadow: const [
            BoxShadow(
              color: Color.fromRGBO(0, 0, 0, 0.28),
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _Thumbnail(task: task, isTerminal: isTerminal, isFailed: isFailed),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      _titleText(),
                      key: ValueKey('${task.status}-$_copyIndex'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                  ),
                  if (isFailed) ...[
                    const SizedBox(height: 2),
                    const Text(
                      'Periksa koneksi lalu coba lagi',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Color(0xFFAEB7C7),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  if (showBar) ...[
                    const SizedBox(height: 6),
                    _ProgressTrack(
                      progress: task.progress,
                      sheenController: _sheenController,
                      colorStart: _blue,
                      colorEnd: _blueLight,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            _TrailingIndicator(
              task: task,
              waitingBlue: _waitingBlue,
            ),
            if (isFailed) ...[
              const SizedBox(width: 8),
              _RetryPill(onTap: () => feedUploadStore.retry()),
            ],
            if (showCancel) ...[
              const SizedBox(width: 6),
              _CancelButton(onTap: () => feedUploadStore.cancelActive()),
            ],
          ],
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  final FeedUploadTask task;
  final bool isTerminal;
  final bool isFailed;
  const _Thumbnail({
    required this.task,
    required this.isTerminal,
    required this.isFailed,
  });

  @override
  Widget build(BuildContext context) {
    Widget base;
    if (task.kind == FeedUploadKind.photo && task.photoFiles.length > 1) {
      base = _CarouselStack(count: task.photoFiles.length);
    } else if (task.kind == FeedUploadKind.photo &&
        task.photoFiles.isNotEmpty) {
      base = _PhotoThumb(file: task.photoFiles.first);
    } else {
      base = _VideoThumb(path: task.videoDraft?.thumbnailPath);
    }

    if (!isTerminal) return base;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Opacity(opacity: 0.55, child: base),
        Positioned.fill(
          child: Center(
            child: Icon(
              isFailed ? Icons.error_rounded : Icons.check_circle_rounded,
              color: isFailed ? const Color(0xFFFF6B6B) : const Color(0xFF22C55E),
              size: 20,
            ),
          ),
        ),
      ],
    );
  }
}

class _VideoThumb extends StatelessWidget {
  final String? path;
  const _VideoThumb({this.path});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: SizedBox(
        width: 32,
        height: 40,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (path != null && File(path!).existsSync())
              Image.file(
                File(path!),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) =>
                    const _ThumbFallback(),
              )
            else
              const _ThumbFallback(),
            Center(
              child: Container(
                width: 18,
                height: 18,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color.fromRGBO(255, 255, 255, 0.28),
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  final File file;
  const _PhotoThumb({required this.file});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: SizedBox(
        width: 34,
        height: 34,
        child: file.existsSync()
            ? Image.file(
                file,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) =>
                    const _ThumbFallback(),
              )
            : const _ThumbFallback(),
      ),
    );
  }
}

class _CarouselStack extends StatelessWidget {
  final int count;
  const _CarouselStack({required this.count});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 6,
            child: _stackTile(),
          ),
          Positioned(
            left: 4,
            top: 3,
            child: _stackTile(),
          ),
          Positioned(
            left: 8,
            top: 0,
            child: _stackTile(),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFF1E5BFF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF12151D), width: 1.5),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stackTile() => Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: const Color(0xFF252A35),
          border: Border.all(color: const Color(0xFF12151D), width: 1),
        ),
      );
}

class _ThumbFallback extends StatelessWidget {
  const _ThumbFallback();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF252A35),
      child: Icon(Icons.image_outlined, color: Color(0xFFAEB7C7), size: 16),
    );
  }
}

class _ProgressTrack extends StatelessWidget {
  final double progress;
  final AnimationController sheenController;
  final Color colorStart;
  final Color colorEnd;

  const _ProgressTrack({
    required this.progress,
    required this.sheenController,
    required this.colorStart,
    required this.colorEnd,
  });

  @override
  Widget build(BuildContext context) {
    final value = progress.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        height: 4,
        child: Stack(
          children: [
            Container(color: const Color.fromRGBO(255, 255, 255, 0.09)),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value == 0 ? 0.02 : value,
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [colorStart, colorEnd],
                      ),
                    ),
                  ),
                  AnimatedBuilder(
                    animation: sheenController,
                    builder: (context, _) {
                      return LayoutBuilder(
                        builder: (context, constraints) {
                          final w = constraints.maxWidth;
                          final t = sheenController.value;
                          // Strip translasi kiri→kanan, lebar ~40% dari bar.
                          final stripWidth = w * 0.4;
                          final dx = (w + stripWidth) * t - stripWidth;
                          return Stack(
                            children: [
                              Positioned(
                                left: dx,
                                top: 0,
                                bottom: 0,
                                width: stripWidth,
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.white.withValues(alpha: 0),
                                        Colors.white.withValues(alpha: 0.35),
                                        Colors.white.withValues(alpha: 0),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrailingIndicator extends StatelessWidget {
  final FeedUploadTask task;
  final Color waitingBlue;
  const _TrailingIndicator({required this.task, required this.waitingBlue});

  @override
  Widget build(BuildContext context) {
    switch (task.status) {
      case FeedUploadStatus.preparing:
        return const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1E5BFF)),
          ),
        );
      case FeedUploadStatus.uploading:
      case FeedUploadStatus.processing:
        if (task.kind == FeedUploadKind.photo &&
            task.photoFiles.length > 1) {
          final total = task.photoFiles.length;
          final done = (task.progress * total).round().clamp(0, total);
          return Text(
            'Foto $done/$total',
            style: const TextStyle(
              color: Color(0xFFAEB7C7),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          );
        }
        final percent = (task.progress * 100).round().clamp(0, 100);
        return Text(
          '$percent%',
          style: const TextStyle(
            color: Color(0xFFAEB7C7),
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        );
      case FeedUploadStatus.waitingReview:
        return Icon(Icons.watch_later_rounded, color: waitingBlue, size: 18);
      case FeedUploadStatus.success:
        return const Icon(Icons.check_circle_rounded,
            color: Color(0xFF22C55E), size: 18);
      case FeedUploadStatus.failed:
      case FeedUploadStatus.cancelled:
      case FeedUploadStatus.idle:
        return const SizedBox.shrink();
    }
  }
}

class _RetryPill extends StatelessWidget {
  final VoidCallback onTap;
  const _RetryPill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color.fromRGBO(255, 107, 107, 0.14),
          borderRadius: BorderRadius.circular(99),
        ),
        child: const Text(
          'Coba lagi',
          style: TextStyle(
            color: Color(0xFFFF6B6B),
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _CancelButton extends StatelessWidget {
  final VoidCallback onTap;
  const _CancelButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 24,
        height: 24,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color.fromRGBO(255, 255, 255, 0.10),
        ),
        child: const Icon(Icons.close_rounded, color: Colors.white, size: 14),
      ),
    );
  }
}

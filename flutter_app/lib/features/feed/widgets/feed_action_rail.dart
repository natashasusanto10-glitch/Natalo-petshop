import 'package:flutter/material.dart';

import '../../../utils/action_throttle.dart';

const _feedActionForegroundColor = Color(0xFFFFFFFF);
const _feedActionShadowColor = Color(0x99000000);
const _feedActionTextShadowColor = Color(0xB3000000);
// Ikon action rail — proporsi ala IG Reels: ukuran 30 + stroke 2.2.
// Sempat diturunkan ke 1.7 tapi terasa terlalu kurus di atas video;
// kesan "gemuk" dulu datang dari count w900 (kini w600), bukan stroke.
const _feedActionIconSize = 30.0;
const _feedActionStrokeWidth = 2.2;
const _feedActionCountFontSize = 12.0;
const _feedActionItemSpacing = 6.0;

/// Rail aksi kanan feed video/foto — like, comment, share, save, more.
/// Ekstraksi 1:1 dari feed_screen (ikon CustomPaint 30px stroke 2.2,
/// angka 12 w600 putih ber-shadow). Cart item
/// DIHAPUS dari rail — duplikat dengan cart kanan-atas (satu-satunya
/// pintu keranjang di feed, spec PR #78/#80 upstream).
class FeedActionRail extends StatelessWidget {
  final int likeCount;
  final bool liked;
  final int commentCount;
  final int shareCount;
  final bool saved;
  final VoidCallback? onLike;
  final VoidCallback? onComment;
  final VoidCallback? onShare;
  final VoidCallback? onSave;
  final VoidCallback? onMore;

  /// Key pada tombol like — dipakai overlay burst double-tap untuk tahu
  /// posisi target "terbang ke rail" (lihat _buildFlyingBurstHeart).
  final Key? likeKey;

  const FeedActionRail({
    super.key,
    required this.likeCount,
    required this.liked,
    required this.commentCount,
    required this.shareCount,
    this.saved = false,
    this.onLike,
    this.onComment,
    this.onShare,
    this.onSave,
    this.onMore,
    this.likeKey,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ReelsAction(
          key: likeKey,
          iconChild: _ReelsHeartGlyph(liked: liked),
          count: likeCount,
          onTap: onLike ?? () {},
          semanticLabel: liked ? 'Batal menyukai' : 'Sukai',
          selected: liked,
          // Pop membal hanya saat LIKE — unlike cukup fill merah memudar
          // (ala IG). `liked` di sini nilai saat build = state sebelum tap.
          shouldPulse: () => !liked,
        ),
        const SizedBox(height: _feedActionItemSpacing),
        _ReelsAction(
          key: const ValueKey('feed-comment-action'),
          iconChild: const _ReelsCommentGlyph(),
          count: commentCount,
          onTap: onComment ?? () {},
          semanticLabel: 'Komentar',
        ),
        const SizedBox(height: _feedActionItemSpacing),
        _ReelsAction(
          iconChild: const _ReelsShareGlyph(),
          count: shareCount,
          onTap: onShare ?? () {},
          semanticLabel: 'Bagikan',
        ),
        const SizedBox(height: _feedActionItemSpacing),
        _ReelsAction(
          iconChild: Icon(
            saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
            color: _feedActionForegroundColor,
            size: _feedActionIconSize,
            shadows: const [
              Shadow(color: _feedActionShadowColor, blurRadius: 3),
            ],
          ),
          onTap: onSave ?? () {},
          semanticLabel: saved ? 'Hapus dari tersimpan' : 'Simpan postingan',
          selected: saved,
        ),
        const SizedBox(height: _feedActionItemSpacing),
        // More actions (Report/Block) — Google Play UGC policy.
        _ReelsAction(
          iconChild: const _ReelsMoreGlyph(),
          onTap: onMore ?? () {},
          semanticLabel: 'Opsi lainnya',
        ),
      ],
    );
  }
}

class _ReelsAction extends StatefulWidget {
  final Widget iconChild;
  final int? count;
  final VoidCallback onTap;
  final String semanticLabel;
  final bool? selected;

  /// Dievaluasi tepat sebelum onTap — return false untuk melewatkan pulse
  /// membal (mis. unlike: cukup fade, tanpa pop). Default: selalu pulse.
  final bool Function()? shouldPulse;

  const _ReelsAction({
    super.key,
    required this.iconChild,
    this.count,
    required this.onTap,
    required this.semanticLabel,
    this.selected,
    this.shouldPulse,
  });

  @override
  State<_ReelsAction> createState() => _ReelsActionState();
}

class _ReelsActionState extends State<_ReelsAction>
    with SingleTickerProviderStateMixin {
  late final ActionThrottle _throttle;
  late final AnimationController _tapPulseController;
  late final Animation<double> _tapPulseScale;

  @override
  void initState() {
    super.initState();
    _throttle = ActionThrottle(interval: const Duration(milliseconds: 220));
    _tapPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _tapPulseScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.18)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.18, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 55,
      ),
    ]).animate(_tapPulseController);
  }

  @override
  void dispose() {
    _tapPulseController.dispose();
    super.dispose();
  }

  void _handleTap() {
    // Evaluasi SEBELUM onTap — onTap bisa langsung flip state parent
    // (optimistic) sehingga nilai sesudahnya sudah bukan state pra-tap.
    final pulse = widget.shouldPulse?.call() ?? true;
    final accepted = _throttle.run(widget.onTap);
    if (!accepted) return;
    if (pulse) _tapPulseController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    // Count 0 disembunyikan ala IG Reels — label baru muncul saat >0.
    // PENTING: slot count SELALU di-render (opacity 0 saat kosong) supaya
    // tinggi item konstan — dulu 44↔60 bikin ikon tersentak naik 16px
    // tepat saat like pertama ("ikon loncat dulu baru merah"). Sekarang
    // ikon diam, angka fade-in ke ruang kosong di bawahnya (ala IG).
    final showCount = widget.count != null && widget.count! > 0;
    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.semanticLabel,
      excludeSemantics: true,
      child: SizedBox(
        width: 54,
        child: Material(
          color: Colors.transparent,
          child: InkResponse(
            onTap: _handleTap,
            radius: 28,
            splashFactory: NoSplash.splashFactory,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            overlayColor:
                const WidgetStatePropertyAll<Color>(Colors.transparent),
            child: ScaleTransition(
              scale: _tapPulseScale,
              child: SizedBox(
                height: widget.count == null ? 44 : 54,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    widget.iconChild,
                    if (widget.count != null) ...[
                      const SizedBox(height: 2),
                      AnimatedOpacity(
                        opacity: showCount ? 1 : 0,
                        duration: const Duration(milliseconds: 150),
                        child: RepaintBoundary(
                          child: Text(
                            // Saat 0 (invisible) tampilkan nilai terakhir yang
                            // masuk akal (1) supaya fade-out unlike 1→0 tidak
                            // sempat flash "0".
                            _formatCount(
                              widget.count! > 0 ? widget.count! : 1,
                            ),
                            style: const TextStyle(
                              color: _feedActionForegroundColor,
                              fontSize: _feedActionCountFontSize,
                              // Ikut halus ala IG: w600 (dari w900). Shadow
                              // tetap menjaga keterbacaan di atas video.
                              fontWeight: FontWeight.w600,
                              height: 1,
                              shadows: [
                                Shadow(
                                  color: _feedActionTextShadowColor,
                                  blurRadius: 2.4,
                                  offset: Offset(0, 0.8),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    }
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return '$count';
  }
}

/// Heart rail — like toggle ala IG: heart TERISI merah, bukan ganti bentuk.
///
/// Dulu unliked = stroke / liked = fill pada path yang sama → siluet
/// benar-benar berubah (stroke center mengembang keluar strokeWidth/2 dan
/// round-join membulatkan ujung lancip; fill memakai path mentah yang lebih
/// kecil + tajam) → tap terbaca "ganti bentuk". Sekarang stroke round-join
/// digambar di KEDUA state (siluet identik piksel), dan fill merah masuk
/// dengan animasi progress 0→1 (180ms) — stroke ikut lerp ke merah.
class _ReelsHeartGlyph extends StatefulWidget {
  final bool liked;

  const _ReelsHeartGlyph({
    required this.liked,
  });

  @override
  State<_ReelsHeartGlyph> createState() => _ReelsHeartGlyphState();
}

class _ReelsHeartGlyphState extends State<_ReelsHeartGlyph>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fillController;
  late final Animation<double> _fill;

  @override
  void initState() {
    super.initState();
    _fillController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      value: widget.liked ? 1 : 0,
    );
    _fill = CurvedAnimation(
      parent: _fillController,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void didUpdateWidget(covariant _ReelsHeartGlyph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.liked != widget.liked) {
      // Unlike balik lebih cepat (tanpa easing panjang) — IG juga begitu.
      widget.liked ? _fillController.forward() : _fillController.reverse();
    }
  }

  @override
  void dispose() {
    _fillController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _feedActionIconSize,
      width: _feedActionIconSize,
      child: CustomPaint(painter: _HeartGlyphPainter(fillProgress: _fill)),
    );
  }
}

class _HeartGlyphPainter extends CustomPainter {
  final Animation<double> fillProgress;

  _HeartGlyphPainter({
    required this.fillProgress,
  }) : super(repaint: fillProgress);

  static const _likedRed = Color(0xFFEF4444);

  @override
  void paint(Canvas canvas, Size size) {
    final t = fillProgress.value;
    final path = buildFeedHeartPath(size);
    // Shadow SELALU stroke — silhouette shadow konstan di kedua state.
    final shadowPaint = Paint()
      ..color = _feedActionShadowColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = _feedActionStrokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.8);

    canvas.drawPath(path.shift(const Offset(0, 1.2)), shadowPaint);

    // Fill merah masuk di dalam stroke — opacity mengikuti progress.
    if (t > 0) {
      final fillPaint = Paint()
        ..color = _likedRed.withValues(alpha: t)
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, fillPaint);
    }

    // Stroke digambar TERAKHIR di kedua state — dialah siluet konstan.
    // Warnanya lerp putih → merah supaya rim menyatu saat liked.
    final strokePaint = Paint()
      ..color = Color.lerp(_feedActionForegroundColor, _likedRed, t)!
      ..style = PaintingStyle.stroke
      ..strokeWidth = _feedActionStrokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _HeartGlyphPainter oldDelegate) {
    return oldDelegate.fillProgress != fillProgress;
  }
}

/// Path heart bersama — dipakai rail glyph (stroke+fill) DAN burst
/// double-tap (fill putih besar) di feed_screen.dart supaya seluruh feed
/// satu bentuk hati. Exported (bukan private) supaya bisa dipakai lintas
/// file.
Path buildFeedHeartPath(Size size) {
  return Path()
    ..moveTo(size.width * 0.50, size.height * 0.844)
    ..cubicTo(
      size.width * 0.469,
      size.height * 0.815,
      size.width * 0.342,
      size.height * 0.698,
      size.width * 0.244,
      size.height * 0.592,
    )
    ..cubicTo(
      size.width * 0.158,
      size.height * 0.498,
      size.width * 0.129,
      size.height * 0.425,
      size.width * 0.129,
      size.height * 0.346,
    )
    ..cubicTo(
      size.width * 0.129,
      size.height * 0.231,
      size.width * 0.219,
      size.height * 0.150,
      size.width * 0.338,
      size.height * 0.150,
    )
    ..cubicTo(
      size.width * 0.406,
      size.height * 0.150,
      size.width * 0.460,
      size.height * 0.179,
      size.width * 0.500,
      size.height * 0.231,
    )
    ..cubicTo(
      size.width * 0.540,
      size.height * 0.179,
      size.width * 0.594,
      size.height * 0.150,
      size.width * 0.662,
      size.height * 0.150,
    )
    ..cubicTo(
      size.width * 0.781,
      size.height * 0.150,
      size.width * 0.871,
      size.height * 0.231,
      size.width * 0.871,
      size.height * 0.346,
    )
    ..cubicTo(
      size.width * 0.871,
      size.height * 0.425,
      size.width * 0.842,
      size.height * 0.498,
      size.width * 0.756,
      size.height * 0.592,
    )
    ..cubicTo(
      size.width * 0.658,
      size.height * 0.698,
      size.width * 0.531,
      size.height * 0.815,
      size.width * 0.50,
      size.height * 0.844,
    )
    ..close();
}

class _ReelsCommentGlyph extends StatelessWidget {
  const _ReelsCommentGlyph();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: _feedActionIconSize,
      width: _feedActionIconSize,
      child: CustomPaint(painter: _CommentGlyphPainter()),
    );
  }
}

class _CommentGlyphPainter extends CustomPainter {
  const _CommentGlyphPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final shadowPaint = Paint()
      ..color = _feedActionShadowColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = _feedActionStrokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.8);
    final paint = Paint()
      ..color = _feedActionForegroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = _feedActionStrokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      ..moveTo(size.width * 0.519, size.height * 0.169)
      ..cubicTo(
        size.width * 0.731,
        size.height * 0.169,
        size.width * 0.879,
        size.height * 0.300,
        size.width * 0.879,
        size.height * 0.469,
      )
      ..cubicTo(
        size.width * 0.879,
        size.height * 0.640,
        size.width * 0.731,
        size.height * 0.765,
        size.width * 0.519,
        size.height * 0.765,
      )
      ..cubicTo(
        size.width * 0.473,
        size.height * 0.765,
        size.width * 0.431,
        size.height * 0.758,
        size.width * 0.392,
        size.height * 0.746,
      )
      ..lineTo(size.width * 0.185, size.height * 0.850)
      ..lineTo(size.width * 0.252, size.height * 0.660)
      ..cubicTo(
        size.width * 0.179,
        size.height * 0.610,
        size.width * 0.131,
        size.height * 0.544,
        size.width * 0.131,
        size.height * 0.469,
      )
      ..cubicTo(
        size.width * 0.131,
        size.height * 0.300,
        size.width * 0.279,
        size.height * 0.169,
        size.width * 0.519,
        size.height * 0.169,
      )
      ..close();

    canvas.drawPath(path.shift(const Offset(0, 1.2)), shadowPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ReelsShareGlyph extends StatelessWidget {
  const _ReelsShareGlyph();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: _feedActionIconSize,
      width: _feedActionIconSize,
      child: CustomPaint(painter: _ShareGlyphPainter()),
    );
  }
}

class _ShareGlyphPainter extends CustomPainter {
  const _ShareGlyphPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final shadowPaint = Paint()
      ..color = _feedActionShadowColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = _feedActionStrokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.8);
    final paint = Paint()
      ..color = _feedActionForegroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = _feedActionStrokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      ..moveTo(size.width * 0.167, size.height * 0.800)
      ..cubicTo(
        size.width * 0.183,
        size.height * 0.512,
        size.width * 0.350,
        size.height * 0.333,
        size.width * 0.563,
        size.height * 0.333,
      )
      ..lineTo(size.width * 0.563, size.height * 0.154)
      ..lineTo(size.width * 0.875, size.height * 0.433)
      ..lineTo(size.width * 0.563, size.height * 0.713)
      ..lineTo(size.width * 0.563, size.height * 0.538)
      ..cubicTo(
        size.width * 0.400,
        size.height * 0.542,
        size.width * 0.275,
        size.height * 0.625,
        size.width * 0.167,
        size.height * 0.800,
      );

    canvas.drawPath(path.shift(const Offset(0, 1.2)), shadowPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ReelsMoreGlyph extends StatelessWidget {
  const _ReelsMoreGlyph();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: _feedActionIconSize,
      width: _feedActionIconSize,
      child: CustomPaint(painter: _MoreGlyphPainter()),
    );
  }
}

class _MoreGlyphPainter extends CustomPainter {
  const _MoreGlyphPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width * 0.067;
    final centers = [
      Offset(size.width * 0.30, size.height * 0.50),
      Offset(size.width * 0.50, size.height * 0.50),
      Offset(size.width * 0.70, size.height * 0.50),
    ];
    final shadowPaint = Paint()
      ..color = _feedActionShadowColor
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.8);
    final paint = Paint()
      ..color = _feedActionForegroundColor
      ..style = PaintingStyle.fill;

    for (final center in centers) {
      canvas.drawCircle(center.translate(0, 1.2), radius, shadowPaint);
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

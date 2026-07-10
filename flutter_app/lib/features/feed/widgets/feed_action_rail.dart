import 'package:flutter/material.dart';

import '../../../utils/action_throttle.dart';

const _feedActionForegroundColor = Color(0xFFFFFFFF);
const _feedActionShadowColor = Color(0x99000000);
const _feedActionTextShadowColor = Color(0xB3000000);
// Ikon action rail — disetel setipis IG Reels: stroke 1.7 (dari 2.2) +
// ukuran 30 (dari 32). Garis lebih halus/elegan, tidak lagi terlihat
// "gemuk" di atas video.
const _feedActionIconSize = 30.0;
const _feedActionStrokeWidth = 1.7;
const _feedActionCountFontSize = 12.0;
const _feedActionItemSpacing = 18.0;
// Aksen commerce oranye — dipakai untuk badge cart di rail. Duplikat dari
// `_feedCommerceOrange` di feed_screen.dart (tetap dipakai di tempat lain di
// sana), sama persis nilainya supaya visual identik.
const _feedActionCartBadgeOrange = Color(0xFFFF7A00);

/// Rail aksi kanan feed video/foto — like, comment, share, cart, more.
/// Ekstraksi 1:1 dari feed_screen (ikon CustomPaint 30px stroke 1.7,
/// angka 12 w600 putih ber-shadow, spacing antar item 18).
class FeedActionRail extends StatelessWidget {
  final int likeCount;
  final bool liked;
  final int commentCount;
  final int shareCount;
  /// Tampilkan tombol cart (feed: hanya bila post punya produk).
  final bool showCart;
  /// Angka badge oranye di ikon cart (jumlah item keranjang).
  final int cartBadgeCount;
  final VoidCallback? onLike;
  final VoidCallback? onComment;
  final VoidCallback? onShare;
  final VoidCallback? onCart;
  final VoidCallback? onMore;

  const FeedActionRail({
    super.key,
    required this.likeCount,
    required this.liked,
    required this.commentCount,
    required this.shareCount,
    this.showCart = false,
    this.cartBadgeCount = 0,
    this.onLike,
    this.onComment,
    this.onShare,
    this.onCart,
    this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ReelsAction(
          iconChild: _ReelsHeartGlyph(liked: liked),
          count: likeCount,
          onTap: onLike ?? () {},
        ),
        const SizedBox(height: _feedActionItemSpacing),
        _ReelsAction(
          iconChild: const _ReelsCommentGlyph(),
          count: commentCount,
          onTap: onComment ?? () {},
        ),
        const SizedBox(height: _feedActionItemSpacing),
        _ReelsAction(
          iconChild: const _ReelsShareGlyph(),
          count: shareCount,
          onTap: onShare ?? () {},
        ),
        const SizedBox(height: _feedActionItemSpacing),
        if (showCart) ...[
          _ReelsAction(
            iconChild: _ReelsCartGlyph(count: cartBadgeCount),
            onTap: onCart ?? () {},
          ),
          const SizedBox(height: _feedActionItemSpacing),
        ],
        // More actions (Report/Block) — Google Play UGC policy.
        _ReelsAction(
          iconChild: const _ReelsMoreGlyph(),
          onTap: onMore ?? () {},
        ),
      ],
    );
  }
}

class _ReelsAction extends StatefulWidget {
  final Widget iconChild;
  final int? count;
  final VoidCallback onTap;

  const _ReelsAction({
    required this.iconChild,
    this.count,
    required this.onTap,
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
    final accepted = _throttle.run(widget.onTap);
    if (!accepted) return;
    _tapPulseController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 54,
      child: Material(
        color: Colors.transparent,
        child: InkResponse(
          onTap: _handleTap,
          radius: 28,
          child: ScaleTransition(
            scale: _tapPulseScale,
            child: SizedBox(
              height: widget.count == null ? 44 : 60,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  widget.iconChild,
                  if (widget.count != null) ...[
                    const SizedBox(height: 2),
                    RepaintBoundary(
                      child: Text(
                        _formatCount(widget.count!),
                        style: const TextStyle(
                          color: _feedActionForegroundColor,
                          fontSize: _feedActionCountFontSize,
                          // Ikut halus ala IG: w600 (dari w900). Shadow tetap
                          // menjaga keterbacaan di atas video.
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
                  ],
                ],
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

class _ReelsHeartGlyph extends StatelessWidget {
  final bool liked;

  const _ReelsHeartGlyph({
    required this.liked,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _feedActionIconSize,
      width: _feedActionIconSize,
      child: CustomPaint(painter: _HeartGlyphPainter(liked: liked)),
    );
  }
}

class _HeartGlyphPainter extends CustomPainter {
  final bool liked;

  const _HeartGlyphPainter({
    required this.liked,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path = _buildHeartPath(size);
    final shadowPaint = Paint()
      ..color = _feedActionShadowColor
      ..style = liked ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = _feedActionStrokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.8);

    canvas.drawPath(path.shift(const Offset(0, 1.2)), shadowPaint);

    final paint = Paint()
      ..color = liked ? const Color(0xFFEF4444) : _feedActionForegroundColor
      ..style = liked ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = _feedActionStrokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, paint);
  }

  Path _buildHeartPath(Size size) {
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

  @override
  bool shouldRepaint(covariant _HeartGlyphPainter oldDelegate) {
    return oldDelegate.liked != liked;
  }
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

class _ReelsCartGlyph extends StatelessWidget {
  final int count;

  const _ReelsCartGlyph({required this.count});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Icon(
          Icons.shopping_cart,
          color: _feedActionForegroundColor,
          size: _feedActionIconSize,
          shadows: [
            Shadow(
              color: _feedActionShadowColor,
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
        if (count > 0)
          Positioned(
            top: -5,
            right: -7,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: _feedActionCartBadgeOrange,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: Colors.black.withValues(alpha: 0.35),
                  width: 1.2,
                ),
              ),
              constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
              child: Text(
                count > 99 ? '99+' : '$count',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w900,
                  height: 1.2,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

/// Hasil layout pill: offset kiri-atas badan pill (px, relatif area foto)
/// + apakah panah pointer di bawah pill (flip karena dekat tepi bawah).
class TagPillPlacement {
  final Offset topLeft;
  final bool arrowBelow;
  const TagPillPlacement(this.topLeft, this.arrowBelow);
}

/// Pure function — clamp badan pill agar utuh dalam batas foto + flip
/// panah. anchor = titik tap/simpan (px). Aturan sama untuk composer &
/// viewer (konstrain spec §2/§3): badan pill selalu utuh dalam batas foto;
/// default badan di BAWAH anchor dengan panah menunjuk ke atas (ke titik),
/// kalau tidak muat di bawah → badan di ATAS anchor dengan panah di bawah
/// pill.
TagPillPlacement placeTagPill({
  required Offset anchor,
  required Size pillSize,
  required Size photoSize,
  double arrowHeight = 6,
  double margin = 4,
}) {
  final belowTop = anchor.dy + arrowHeight;
  final fitsBelow = belowTop + pillSize.height + margin <= photoSize.height;
  final arrowBelow = !fitsBelow;
  final rawTop =
      arrowBelow ? anchor.dy - arrowHeight - pillSize.height : belowTop;

  final maxLeft = (photoSize.width - pillSize.width - margin);
  final left = (anchor.dx - pillSize.width / 2)
      .clamp(margin, maxLeft < margin ? margin : maxLeft)
      .toDouble();

  final maxTop = (photoSize.height - pillSize.height - margin);
  final top =
      rawTop.clamp(margin, maxTop < margin ? margin : maxTop).toDouble();

  return TagPillPlacement(Offset(left, top), arrowBelow);
}

/// Pill gelap username putih + panah pointer, ala IG. Muncul dengan pop
/// scale-fade easeOutCubic (dibungkus caller via animasi implicit di sini).
class FeedUserTagPill extends StatelessWidget {
  final String username;
  final bool arrowBelow;
  final bool showRemove;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  const FeedUserTagPill({
    super.key,
    required this.username,
    this.arrowBelow = false,
    this.showRemove = false,
    this.onTap,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final arrow = CustomPaint(
      size: const Size(10, 6),
      painter: _TagArrowPainter(pointsUp: !arrowBelow),
    );
    final body = GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              username,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (showRemove) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: onRemove,
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ],
          ],
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: arrowBelow ? [body, arrow] : [arrow, body],
    );
  }
}

class _TagArrowPainter extends CustomPainter {
  final bool pointsUp;
  const _TagArrowPainter({required this.pointsUp});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.78);
    final path = Path();
    if (pointsUp) {
      path
        ..moveTo(size.width / 2, 0)
        ..lineTo(0, size.height)
        ..lineTo(size.width, size.height);
    } else {
      path
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width / 2, size.height);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TagArrowPainter old) =>
      old.pointsUp != pointsUp;
}

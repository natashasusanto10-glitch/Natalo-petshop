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

/// Pure function (final review Spec B fix — koordinat tag drift) — koordinat
/// tag disimpan sebagai fraksi 0-1 RELATIF TERHADAP FOTO, tapi media
/// dirender di dalam sebuah container yang bisa saja beda aspect ratio dari
/// foto itu sendiri (mis. foto landscape di container portrait). Di bawah
/// `BoxFit.contain`, itu artinya ada letterbox bar (kiri-kanan ATAU
/// atas-bawah) yang BUKAN bagian dari foto — kalau fraksi tag dihitung
/// relatif terhadap [container] penuh (bukan area foto yang benar-benar
/// ter-render), posisi tag drift, makin parah makin beda aspect ratio-nya.
///
/// [container] = ukuran area yang tersedia untuk media (biasanya dari
/// LayoutBuilder). [aspectRatio] = width/height foto ASLI (bukan container).
/// [fit] = BoxFit yang dipakai render media (composer & viewer keduanya
/// pakai `BoxFit.contain` — lihat feed_tag_people_screen.dart &
/// feed_screen.dart).
///
/// Return: Rect (dalam koordinat [container], origin kiri-atas container)
/// yang benar-benar ditempati piksel foto:
///   - `BoxFit.contain`: foto discale supaya utuh masuk container →
///     di-tengah pada sumbu yang berlebih (letterbox), ukurannya BISA lebih
///     kecil dari container.
///   - `BoxFit.cover`: foto mengisi SELURUH container (kelebihan di-crop di
///     luar container) → rect = container itu sendiri (semua piksel
///     container menampilkan sebagian foto, tak ada letterbox).
///
/// Input tak valid (container kosong / aspectRatio <= 0 / non-finite) →
/// fallback aman: seluruh container (setara perilaku lama sebelum fix ini,
/// dipakai juga untuk post lama yang tidak punya width/height tersimpan).
Rect fittedPhotoRect(Size container, double aspectRatio, BoxFit fit) {
  if (container.width <= 0 ||
      container.height <= 0 ||
      !aspectRatio.isFinite ||
      aspectRatio <= 0) {
    return Offset.zero & container;
  }
  if (fit == BoxFit.cover) {
    // Foto mengisi penuh container (kelebihan di-crop off-screen) — setiap
    // piksel container menampilkan piksel foto, jadi rect = container.
    return Offset.zero & container;
  }
  // BoxFit.contain (default/satu-satunya fit lain yang dipakai codebase ini
  // untuk tag people — lihat feed_tag_people_screen.dart & feed_screen.dart).
  final containerAspect = container.width / container.height;
  double width;
  double height;
  if (containerAspect > aspectRatio) {
    // Container relatif lebih LEBAR dari foto → letterbox KIRI-KANAN;
    // tinggi foto = tinggi container penuh.
    height = container.height;
    width = height * aspectRatio;
  } else {
    // Container relatif lebih SEMPIT/TINGGI dari foto → letterbox
    // ATAS-BAWAH; lebar foto = lebar container penuh.
    width = container.width;
    height = width / aspectRatio;
  }
  final dx = (container.width - width) / 2;
  final dy = (container.height - height) / 2;
  return Rect.fromLTWH(dx, dy, width, height);
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

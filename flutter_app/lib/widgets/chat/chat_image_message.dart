import 'package:flutter/material.dart';

import '../../screens/image_viewer_screen.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/natalo_colors.dart';
import '../app_product_image.dart';

/// Thumbnail foto chat (pesan `type: image`) → tap buka fullscreen viewer
/// (reuse `ImageViewerScreen` yang sudah ada, dipakai juga oleh galeri
/// produk — pinch-zoom + swipe gratis tanpa kode baru).
///
/// Alignment (customer kanan / staff kiri) ditentukan caller (`ChatRoomScreen`)
/// lewat `Row`/`Align` di list pesan — widget ini hanya render thumbnail +
/// bingkai, tidak tahu posisi sendiri di layar.
class ChatImageMessage extends StatelessWidget {
  final String? imageUrl;

  const ChatImageMessage({super.key, required this.imageUrl});

  static const double _thumbSize = 180;

  /// Padding bingkai putih di sekeliling thumbnail (kartu → foto).
  static const double _framePad = AppSpacing.xs;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    return GestureDetector(
      onTap: url == null || url.isEmpty
          ? null
          : () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ImageViewerScreen(url: url),
                ),
              );
            },
      child: Container(
        width: _thumbSize,
        height: _thumbSize,
        padding: const EdgeInsets.all(_framePad),
        decoration: BoxDecoration(
          color: NataloColors.white,
          borderRadius: AppRadius.medium,
          border: Border.all(color: NataloColors.border),
        ),
        child: url == null || url.isEmpty
            ? const Center(
                child: Icon(
                  Icons.image_not_supported_outlined,
                  color: NataloColors.textTertiary,
                ),
              )
            : AppProductImage(
                imageUrl: url,
                width: _thumbSize - _framePad * 2,
                height: _thumbSize - _framePad * 2,
                fit: BoxFit.cover,
                // Radius dalam = radius luar (md) minus padding bingkai, biar
                // lengkung foto konsentris dgn kartu (= AppRadius.sm).
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
      ),
    );
  }
}

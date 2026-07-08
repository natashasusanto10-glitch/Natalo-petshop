import 'dart:io';

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

  /// File lokal foto yang SEDANG/BARU SAJA dikirim (`status: sending` atau
  /// `failed`) — `ChatMessage` (Task 1, frozen) cuma punya field network
  /// `imageUrl`, tidak ada field path lokal, jadi `ChatRoomScreen` (Task 5)
  /// mengoper file lokal terpisah lewat parameter ini supaya thumbnail
  /// optimistic bisa tampil SEBELUM upload selesai (tanpa `imageUrl` sama
  /// sekali di awal). Diprioritaskan di atas [imageUrl] kalau keduanya ada
  /// (retry sukses tapi belum sempat direkonsiliasi oleh poll berikutnya) —
  /// menghindari "flash" balik ke placeholder sebelum versi server benar2
  /// dikonfirmasi datang.
  final File? localFile;

  const ChatImageMessage({
    super.key,
    required this.imageUrl,
    this.localFile,
  });

  static const double _thumbSize = 180;

  /// Padding bingkai putih di sekeliling thumbnail (kartu → foto).
  static const double _framePad = AppSpacing.xs;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    final local = localFile;
    final hasNetwork = url != null && url.isNotEmpty;
    final hasLocal = local != null;
    return GestureDetector(
      // Fullscreen viewer butuh URL network — foto yang masih lokal murni
      // (belum ke-upload) sengaja tidak tappable dulu.
      onTap: !hasNetwork
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
        child: hasLocal
            ? ClipRRect(
                // Radius dalam = radius luar (md) minus padding bingkai, biar
                // lengkung foto konsentris dgn kartu (= AppRadius.sm).
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Image.file(
                  local,
                  width: _thumbSize - _framePad * 2,
                  height: _thumbSize - _framePad * 2,
                  fit: BoxFit.cover,
                  // File temp bisa terhapus/tak terbaca (OS bersihkan cache,
                  // atau kompresi tadi gagal tulis) — tanpa errorBuilder
                  // Image.file THROW saat paint (kotak merah di debug, tile
                  // rusak di release). Degradasi ke placeholder yang SAMA
                  // dgn jalur gambar network rusak.
                  errorBuilder: (context, error, stack) =>
                      const _BrokenImagePlaceholder(),
                ),
              )
            : hasNetwork
                ? AppProductImage(
                    imageUrl: url,
                    width: _thumbSize - _framePad * 2,
                    height: _thumbSize - _framePad * 2,
                    fit: BoxFit.cover,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  )
                : const _BrokenImagePlaceholder(),
      ),
    );
  }
}

/// Placeholder "gambar tak tersedia" — dipakai bersama oleh jalur
/// gambar-tak-ada (`imageUrl` & `localFile` sama-sama kosong) dan jalur
/// `Image.file` yang gagal render (`errorBuilder`), supaya kedua kegagalan
/// tampil identik. (`AppProductImage` sendiri sudah punya fallback internal
/// utk gambar network rusak — tak perlu diduplikasi di sini.)
class _BrokenImagePlaceholder extends StatelessWidget {
  const _BrokenImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Icon(
        Icons.image_not_supported_outlined,
        color: NataloColors.textTertiary,
      ),
    );
  }
}

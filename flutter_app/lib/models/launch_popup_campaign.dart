/// Nada visual popup — menentukan warna chip/aksen. Merah untuk promo,
/// hijau untuk pengumuman (paritas dengan announcement_detail_screen.dart).
enum LaunchPopupTone { promo, announcement }

/// Satu konten popup pembuka aplikasi. Model murni — sumber datanya
/// (hardcoded sekarang, API nanti) tidak tercermin di sini.
class LaunchPopupCampaign {
  final String id;
  final LaunchPopupTone tone;

  /// Hero opsional. Boleh asset path ('assets/...') ATAU URL http.
  /// null / kosong = mode teks (tanpa gambar).
  final String? imageUrl;
  final String title;
  final String body;
  final String categoryLabel;

  /// Label tombol utama. null/kosong = sembunyikan tombol utama (mode info).
  final String? ctaLabel;

  /// Target tombol utama, mis. '/produk/<slug>' — diteruskan ke
  /// deepLinkService.handleExternalUri().
  final String? ctaHref;
  final String dismissLabel;

  const LaunchPopupCampaign({
    required this.id,
    required this.tone,
    this.imageUrl,
    required this.title,
    required this.body,
    required this.categoryLabel,
    this.ctaLabel,
    this.ctaHref,
    this.dismissLabel = 'Nanti saja',
  });

  bool get hasImage => imageUrl != null && imageUrl!.isNotEmpty;
  bool get hasCta =>
      ctaLabel != null &&
      ctaLabel!.isNotEmpty &&
      ctaHref != null &&
      ctaHref!.isNotEmpty;
}

import '../config/api_config.dart';

/// Popup promo bergambar saat cold start (gaya Shopee: satu gambar kreatif
/// penuh + tombol X) — admin-managed via GET /api/launch-popup.
/// Menggantikan LaunchPopupCampaign hardcoded (kartu teks) yang dihapus.
class LaunchPopup {
  final String id;

  /// URL gambar absolute (path relatif di-resolve via ApiConfig.baseUrl).
  final String imageUrl;

  /// Alt text — dipakai Semantics (aksesibilitas).
  final String imageAlt;

  /// Deep link tujuan saat gambar di-tap (mis. `/products?diskon=1`).
  /// Null = gambar tidak bisa di-tap (linkType "none" di admin).
  final String? href;

  /// true = hanya tampil untuk user login (audience "member" di admin).
  final bool memberOnly;

  const LaunchPopup({
    required this.id,
    required this.imageUrl,
    this.imageAlt = '',
    this.href,
    this.memberOnly = true,
  });

  factory LaunchPopup.fromApiJson(Map<String, dynamic> json) {
    final href = json['href']?.toString().trim();
    return LaunchPopup(
      id: (json['id'] ?? '').toString(),
      imageUrl: _absoluteUrl((json['image'] ?? '').toString()),
      imageAlt: (json['imageAlt'] ?? '').toString(),
      href: (href == null || href.isEmpty) ? null : href,
      memberOnly: (json['audience'] ?? 'member').toString() != 'all',
    );
  }
}

String _absoluteUrl(String url) {
  if (url.isEmpty || url.startsWith('http')) return url;
  final base = Uri.parse(ApiConfig.baseUrl);
  final origin =
      '${base.scheme}://${base.host}${base.hasPort ? ':${base.port}' : ''}';
  return url.startsWith('/') ? '$origin$url' : '$origin/$url';
}

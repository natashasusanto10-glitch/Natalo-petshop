/// Konfigurasi endpoint API + URL publik.
///
/// Backend tetap Next.js di domain produksi yang sama dengan web. Flutter app
/// hit endpoint REST yang sama (`/api/...`) dan handle auth via JWT cookie
/// (kalau pakai cookie_jar) atau Bearer header.
class ApiConfig {
  ApiConfig._();

  /// Base URL untuk fetch API dari Flutter. Default ke domain produksi.
  /// Override saat development lokal via `--dart-define=API_BASE_URL=...`.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://www.natalopetshop.com',
  );

  /// Alias `apiBaseUrl` — beberapa code pakai `baseUrl`. Keep both untuk
  /// backward compat. Sama nilainya.
  static const String baseUrl = apiBaseUrl;

  /// URL publik website — dipakai untuk share link produk, deep link, dll.
  /// Biasanya sama dengan apiBaseUrl di production.
  static const String publicSiteUrl = String.fromEnvironment(
    'PUBLIC_SITE_URL',
    defaultValue: 'https://www.natalopetshop.com',
  );

  /// Build endpoint full dari path relatif. `/api/products` →
  /// `https://www.natalopetshop.com/api/products`.
  static Uri uri(String path, [Map<String, dynamic>? query]) {
    final base = Uri.parse(apiBaseUrl);
    final segments = [
      ...base.pathSegments,
      ...path.split('/').where((s) => s.isNotEmpty),
    ];
    final queryParameters = query?.map(
      (k, v) => MapEntry(k, v?.toString() ?? ''),
    );
    return base.replace(
      pathSegments: segments,
      queryParameters: queryParameters?.isEmpty == true ? null : queryParameters,
    );
  }
}

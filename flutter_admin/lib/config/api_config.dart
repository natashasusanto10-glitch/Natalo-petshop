/// Konfigurasi endpoint admin app.
///
/// Admin app pakai backend yang sama dengan customer Flutter app
/// (production = natalopetshop.com), tapi route /api/admin/* + /api/auth/admin-login.
///
/// Untuk dev local, ubah [baseUrl] ke localhost / ngrok kalau testing
/// dengan backend dev.
class ApiConfig {
  ApiConfig._();

  /// Base URL backend Natalo. Production deployment di Vercel.
  static const String baseUrl = 'https://www.natalopetshop.com';

  /// Public site URL (untuk deep link share).
  static const String publicSiteUrl = baseUrl;

  static Uri uri(String path, [Map<String, dynamic>? query]) {
    final qp = <String, String>{};
    if (query != null) {
      for (final entry in query.entries) {
        if (entry.value == null) continue;
        qp[entry.key] = entry.value.toString();
      }
    }
    return Uri.parse('$baseUrl$path').replace(
      queryParameters: qp.isEmpty ? null : qp,
    );
  }
}

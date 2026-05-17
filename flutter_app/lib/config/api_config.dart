import 'package:flutter/foundation.dart';

class ApiConfig {
  /// Identitas client untuk backend shared dengan Capacitor/Next.js.
  /// Backend boleh mengabaikan header ini, tapi saat testing ini membantu
  /// membedakan order, voucher, feed, review, dan upload dari Flutter.
  static const appClient = String.fromEnvironment(
    'APP_CLIENT',
    defaultValue: 'flutter',
  );

  static String get appBuildMode => kReleaseMode ? 'release' : 'debug';

  /// Base URL backend. Default behavior:
  /// - **Release build** → production `https://www.natalopetshop.com`
  /// - **Debug build** → emulator-friendly `http://10.0.2.2:3000` (Android
  ///   emulator localhost → host PC) dengan fallback ke production kalau
  ///   local backend tidak ada.
  ///
  /// Override saat build:
  /// `flutter build apk --dart-define=API_BASE_URL=https://staging.natalo...`
  static const _envOverride = String.fromEnvironment('API_BASE_URL');
  static String get baseUrl {
    if (_envOverride.isNotEmpty) return _envOverride;
    return kReleaseMode
        ? 'https://www.natalopetshop.com'
        : 'http://10.0.2.2:3000';
  }

  /// URL publik (produksi) untuk share link product, deep link, dll.
  /// Beda dengan baseUrl yang bisa pakai 10.0.2.2 untuk emulator dev —
  /// share URL HARUS resolvable di browser orang lain.
  ///
  /// Override saat build: `flutter build apk --dart-define=PUBLIC_SITE_URL=https://www.natalopetshop.com`
  static const publicSiteUrl = String.fromEnvironment(
    'PUBLIC_SITE_URL',
    defaultValue: 'https://www.natalopetshop.com',
  );

  static Uri uri(String path, [Map<String, String?> query = const {}]) {
    return _uriForBase(baseUrl, path, query);
  }

  static List<Uri> uris(String path, [Map<String, String?> query = const {}]) {
    // Fallback chain: di debug build kita coba beberapa localhost
    // formats supaya jalan di Android emulator + iOS simulator + physical.
    // Di release, fallback ke production saja (sudah baseUrl).
    const devFallbacks = kReleaseMode
        ? <String>[]
        : [
            'http://10.0.2.2:3000',
            'http://127.0.0.1:3000',
            'http://localhost:3000',
            // Last-resort: kalau local backend tidak jalan, app tetap bisa
            // demo dengan data production read-only.
            'https://www.natalopetshop.com',
          ];

    final seen = <String>{};
    final candidates = [
      baseUrl,
      ...devFallbacks,
    ].where(seen.add).toList();

    return candidates.map((url) => _uriForBase(url, path, query)).toList();
  }

  static Uri _uriForBase(
    String baseUrl,
    String path,
    Map<String, String?> query,
  ) {
    final base = Uri.parse(baseUrl);
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    final normalizedBasePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    final normalizedPath = [
      if (normalizedBasePath.isNotEmpty) normalizedBasePath,
      cleanPath,
    ].join('/');

    return base.replace(
      path: normalizedPath,
      queryParameters: {
        for (final entry in query.entries)
          if (entry.value != null && entry.value!.trim().isNotEmpty)
            entry.key: entry.value,
      },
    );
  }
}

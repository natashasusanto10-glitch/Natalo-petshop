import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../state/member_store.dart';

/// Reusable HTTP client untuk semua service. Wrap auth headers, timeout,
/// response decoding, dan ApiException mapping. Real implementation perlu
/// retry + cancel token; saat ini minimal.
class ApiClient {
  ApiClient._();

  /// Cookie jar — simpan Set-Cookie response (mis. natalo_session=...)
  /// supaya request berikutnya bisa kirim balik. Persisted via SharedPreferences
  /// di key [_sessionCookieKey] supaya survive app restart.
  String? _cookie;
  static const String _sessionCookieKey = 'natalo_session_cookie';

  /// Fire callback kalau response 401 Unauthorized — UI layer bisa
  /// subscribe untuk redirect ke /member/login.
  VoidCallback? onUnauthorized;

  Map<String, String> _headers(
      {bool json = false, Map<String, String>? extra}) {
    final token = memberStore.sessionToken;
    return {
      if (json) 'content-type': 'application/json',
      'accept': 'application/json',
      if (token != null) 'authorization': 'Bearer $token',
      if (token != null) 'cookie': 'member_session=$token',
      ...?extra,
    };
  }

  Future<dynamic> getJson(
    String path, {
    Map<String, dynamic>? query,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final uri = ApiConfig.uri(path, query);
    try {
      final res = await http.get(uri, headers: _headers()).timeout(timeout);
      return _decode(res);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(e.toString(), cause: e);
    }
  }

  /// Clear session token + cookies (logout). Beberapa code pakai
  /// `apiClient.clearSession()` saat user logout / 401 response.
  Future<void> clearSession() async {
    // TODO: clear cookie jar kalau pakai dio cookie_jar. Saat ini no-op
    // karena auth via memberStore.sessionToken yang di-clear di memberStore.logout().
    if (kDebugMode) debugPrint('[apiClient.clearSession] called');
  }

  Future<void> _captureCookie(http.Response response) async {
    final rawCookie = response.headers['set-cookie'];
    if (rawCookie == null || rawCookie.isEmpty) return;

    // ── Parse Set-Cookie ────────────────────────────────────────────────
    // http package join multiple Set-Cookie headers dengan ", ". TAPI
    // value dalam cookie attribute (mis. `Expires=Wed, 21 Oct 2026...`)
    // juga punya ", ".
    //
    // Naive split(',') broke parsing untuk cookie dengan Expires/Max-Age.
    // Pakai lookahead regex: split di koma + spasi yang **diikuti** oleh
    // pattern cookie name baru (token=). Date di Expires tidak ada `=`
    // setelah koma, jadi safe.
    final splitPattern = RegExp(r',(?=\s*[a-zA-Z0-9!#$%&\x27*+\-.^_`|~]+=)');
    final freshCookies = <String, String>{};
    for (final entry in rawCookie.split(splitPattern)) {
      final firstPair = entry.trim().split(';').first.trim();
      final eqIdx = firstPair.indexOf('=');
      if (eqIdx <= 0) continue; // skip malformed
      final name = firstPair.substring(0, eqIdx).trim();
      final value = firstPair.substring(eqIdx + 1).trim();
      if (name.isEmpty) continue;
      // Skip cleared cookies (server signal logout via empty value + past
      // Expires). Caller juga clear via apiClient.clearSession().
      freshCookies[name] = value;
    }
    if (freshCookies.isEmpty) return;

    // ── Merge dengan existing cookie jar ────────────────────────────────
    // Server tidak selalu re-send semua cookies di setiap response. Mis.
    // setelah login, request berikut mungkin cuma set csrf token, bukan
    // session token. Naive replace = lose session. Merge = stable.
    final existingCookies = <String, String>{};
    if (_cookie != null && _cookie!.isNotEmpty) {
      for (final pair in _cookie!.split(';')) {
        final trimmed = pair.trim();
        final eqIdx = trimmed.indexOf('=');
        if (eqIdx <= 0) continue;
        existingCookies[trimmed.substring(0, eqIdx).trim()] =
            trimmed.substring(eqIdx + 1).trim();
      }
    }
    existingCookies.addAll(freshCookies); // fresh overrides

    _cookie =
        existingCookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionCookieKey, _cookie!);
  }

  Future<http.Response> _sendWithFallback(
    String path, {
    Object? body,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final uri = ApiConfig.uri(path);
    try {
      final res = await http
          .put(
            uri,
            headers: _headers(json: true),
            body: body == null ? null : jsonEncode(body),
          )
          .timeout(timeout);
      return _decode(res);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(e.toString(), cause: e);
    }
  }

  Map<String, dynamic> _decodeObject(http.Response response) {
    final text = response.body.trim();
    final Object? decoded;
    try {
      decoded = text.isEmpty ? <String, dynamic>{} : jsonDecode(text);
    } on FormatException {
      _handleUnauthorized(response);
      throw ApiException(
        _nonJsonMessage(response, text),
        statusCode: response.statusCode,
      );
    }
    final data = decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{'data': decoded};

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }

    // 401 Unauthorized — session expired atau cookie invalid. Auto-clear
    // session lokal + fire callback supaya UI layer bisa redirect ke login.
    // Tidak block error throw — caller tetap dapat ApiException untuk
    // handle inline (mis. retry button di screen).
    _handleUnauthorized(response);
    throw ApiException(
      _nonJsonMessage(response, response.body),
      statusCode: response.statusCode,
    );
  }

  Future<dynamic> deleteJson(
    String path, {
    Object? body,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final uri = ApiConfig.uri(path);
    try {
      final req = http.Request('DELETE', uri)
        ..headers.addAll(_headers(json: body != null))
        ..body = body == null ? '' : jsonEncode(body);
      final streamed = await req.send().timeout(timeout);
      final res = await http.Response.fromStream(streamed);
      return _decode(res);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(e.toString(), cause: e);
    }
  }

  Future<dynamic> putJson(
    String path, {
    Object? body,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final uri = ApiConfig.uri(path);
    try {
      final res = await http
          .put(
            uri,
            headers: _headers(json: true),
            body: body == null ? null : jsonEncode(body),
          )
          .timeout(timeout);
      return _decode(res);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(e.toString(), cause: e);
    }
  }

  Future<dynamic> postJson(
    String path, {
    Object? body,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final uri = ApiConfig.uri(path);
    try {
      final res = await http
          .post(
            uri,
            headers: _headers(json: true),
            body: body == null ? null : jsonEncode(body),
          )
          .timeout(timeout);
      return _decode(res);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(e.toString(), cause: e);
    }
  }


  Future<dynamic> patchJson(
    String path, {
    Object? body,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final uri = ApiConfig.uri(path);
    try {
      final res = await http
          .patch(
            uri,
            headers: _headers(json: true),
            body: body == null ? null : jsonEncode(body),
          )
          .timeout(timeout);
      return _decode(res);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(e.toString(), cause: e);
    }
  }

  Future<dynamic> postMultipartFile(
    String path, {
    Map<String, dynamic>? query,
    required String fieldName,
    required String filePath,
    String? filename,
    String? contentType,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final uri = ApiConfig.uri(path, query);
    try {
      final request = http.MultipartRequest('POST', uri)
        ..headers.addAll(_headers());
      request.files.add(
        await http.MultipartFile.fromPath(
          fieldName,
          filePath,
          filename: filename,
          contentType:
              contentType == null ? null : MediaType.parse(contentType),
        ),
      );
      final streamed = await request.send().timeout(timeout);
      final response = await http.Response.fromStream(streamed);
      return _decode(response);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(e.toString(), cause: e);
    }
  }

  dynamic _decode(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(
        'request failed: ${res.reasonPhrase}',
        statusCode: res.statusCode,
      );
    }
    if (res.body.isEmpty) return null;
    try {
      return jsonDecode(res.body);
    } catch (_) {
      return res.body;
    }
  }

  void _handleUnauthorized(http.Response response) {
    if (response.statusCode != 401) return;
    // Fire-and-forget clear (async tapi tidak di-await — non-blocking).
    clearSession();
    // Trigger callback kalau ada subscriber.
    onUnauthorized?.call();
  }

  String _nonJsonMessage(http.Response response, String text) {
    final status = response.statusCode;
    if (status == 404) {
      return 'Endpoint belum tersedia di server.';
    }
    if (status == 401) {
      return 'Sesi berakhir. Silakan login ulang.';
    }
    if (status >= 500) {
      return 'Server sedang bermasalah. Coba lagi nanti.';
    }
    if (text.startsWith('<!DOCTYPE html') || text.startsWith('<html')) {
      return 'Server membalas halaman web, bukan data aplikasi.';
    }
    return 'Response server tidak sesuai format aplikasi.';
  }
}

/// Singleton — dipakai semua service untuk konsistensi auth + error mapping.
final ApiClient apiClient = ApiClient._();

class ApiException implements Exception {
  final int? statusCode;
  final String message;
  final Object? cause;

  const ApiException(this.message, {this.statusCode, this.cause});

  /// Subset helpers — dipakai screen untuk mapping ke user-facing message.
  bool get isNetworkError => statusCode == null;
  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isServerError => (statusCode ?? 0) >= 500;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

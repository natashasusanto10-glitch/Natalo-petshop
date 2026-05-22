import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../config/api_config.dart';
import '../state/member_store.dart';

/// Reusable HTTP client untuk semua service. Wrap auth headers, timeout,
/// response decoding, dan ApiException mapping. Real implementation perlu
/// retry + cancel token; saat ini minimal.
class ApiClient {
  ApiClient._();

  /// Fire callback kalau response 401 Unauthorized — UI layer bisa
  /// subscribe untuk redirect ke /member/login.
  VoidCallback? onUnauthorized;
  String? _lastSessionToken;

  String? get lastSessionToken => _lastSessionToken;

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
    _lastSessionToken = null;
    // TODO: clear cookie jar kalau pakai dio cookie_jar. Saat ini no-op
    // karena auth via memberStore.sessionToken yang di-clear di memberStore.logout().
    if (kDebugMode) debugPrint('[apiClient.clearSession] called');
  }

  Future<dynamic> deleteJson(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final uri = ApiConfig.uri(path, query);
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
    _captureSessionToken(res);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _handleUnauthorized(res);
      throw ApiException(
        _nonJsonMessage(res, res.body.trim()),
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

  void _captureSessionToken(http.Response response) {
    final setCookie = response.headers['set-cookie'];
    if (setCookie == null || setCookie.isEmpty) return;
    final match =
        RegExp(r'(?:^|,\s*)(?:member_session|admin_session)=([^;,\s]+)')
            .firstMatch(setCookie);
    final token = match?.group(1);
    if (token == null || token.isEmpty) return;
    _lastSessionToken = token;
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
    try {
      final body = jsonDecode(text);
      if (body is Map) {
        final message = body['error'] ?? body['message'];
        if (message != null && message.toString().trim().isNotEmpty) {
          return message.toString();
        }
      }
    } catch (_) {}
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

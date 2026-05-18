import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../state/member_store.dart';

/// Reusable HTTP client untuk semua service. Wrap auth headers, timeout,
/// response decoding, dan ApiException mapping. Real implementation perlu
/// retry + cancel token; saat ini minimal.
class ApiClient {
  ApiClient._();

  Map<String, String> _headers({bool json = false, Map<String, String>? extra}) {
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

  Future<dynamic> patchJson(
    String path, {
    Object? body,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final uri = ApiConfig.uri(path);
    try {
      final req = http.Request('PATCH', uri)
        ..headers.addAll(_headers(json: true))
        ..body = body == null ? '' : jsonEncode(body);
      final streamed = await req.send().timeout(timeout);
      final res = await http.Response.fromStream(streamed);
      return _decode(res);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(e.toString(), cause: e);
    }
  }

  /// Multipart file upload. `fields` untuk form data, `filePath` path file
  /// di disk, `fieldName` name field di FormData, `filename` nama file di
  /// upload, `contentType` MIME type. Return decoded JSON response.
  Future<dynamic> postMultipartFile(
    String path, {
    required String filePath,
    String fieldName = 'file',
    String? filename,
    Map<String, String>? fields,
    String? contentType,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final uri = ApiConfig.uri(path);
    try {
      final req = http.MultipartRequest('POST', uri)
        ..headers.addAll(_headers())
        ..files.add(await http.MultipartFile.fromPath(
          fieldName,
          filePath,
          filename: filename,
        ));
      if (fields != null) req.fields.addAll(fields);
      final streamed = await req.send().timeout(timeout);
      final res = await http.Response.fromStream(streamed);
      return _decode(res);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(e.toString(), cause: e);
    }
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

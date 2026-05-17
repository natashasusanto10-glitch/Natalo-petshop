import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  const ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class ApiClient {
  static const _sessionCookieKey = 'natalo_member_session_cookie';

  String? _cookie;

  /// Callback yang dipanggil saat server response 401 (session expired/
  /// invalid). UI layer (mis. memberStore) bisa subscribe untuk:
  /// - Auto logout (clear in-memory profile)
  /// - Show snackbar "Sesi habis, login ulang"
  /// - Navigate ke /member/login
  ///
  /// Daripada hardcode dependency ke memberStore (creates cycle), pakai
  /// callback pattern supaya api_client tetap pure infrastructure layer.
  void Function()? onUnauthorized;

  Map<String, String> get _headers {
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'X-App-Client': ApiConfig.appClient,
      'X-App-Build-Mode': ApiConfig.appBuildMode,
      if (_cookie != null) 'Cookie': _cookie!,
    };
  }

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String?> query = const {},
  }) async {
    final response = await _sendWithFallback(
      path,
      query: query,
      timeout: const Duration(seconds: 8),
      send: (uri) => http.get(uri, headers: _headers),
    );
    await _captureCookie(response);
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> postJson(
    String path, {
    required Map<String, dynamic> body,
  }) async {
    final encodedBody = jsonEncode(body);
    final response = await _sendWithFallback(
      path,
      timeout: const Duration(seconds: 10),
      send: (uri) => http.post(
        uri,
        headers: _headers,
        body: encodedBody,
      ),
    );
    await _captureCookie(response);
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> putJson(
    String path, {
    required Map<String, dynamic> body,
  }) async {
    final encodedBody = jsonEncode(body);
    final response = await _sendWithFallback(
      path,
      timeout: const Duration(seconds: 10),
      send: (uri) => http.put(
        uri,
        headers: _headers,
        body: encodedBody,
      ),
    );
    await _captureCookie(response);
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> patchJson(
    String path, {
    required Map<String, dynamic> body,
  }) async {
    final encodedBody = jsonEncode(body);
    final response = await _sendWithFallback(
      path,
      timeout: const Duration(seconds: 10),
      send: (uri) => http.patch(
        uri,
        headers: _headers,
        body: encodedBody,
      ),
    );
    await _captureCookie(response);
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> deleteJson(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final encodedBody = body == null ? null : jsonEncode(body);
    final response = await _sendWithFallback(
      path,
      timeout: const Duration(seconds: 10),
      send: (uri) => http.delete(
        uri,
        headers: _headers,
        body: encodedBody,
      ),
    );
    await _captureCookie(response);
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> postMultipartFile(
    String path, {
    Map<String, String?> query = const {},
    required String fieldName,
    required String filePath,
    required String filename,
    required String contentType,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final response = await _sendWithFallback(
      path,
      query: query,
      timeout: timeout,
      send: (uri) async {
        final request = http.MultipartRequest('POST', uri);
        request.headers.addAll({
          'Accept': 'application/json',
          'X-App-Client': ApiConfig.appClient,
          'X-App-Build-Mode': ApiConfig.appBuildMode,
          if (_cookie != null) 'Cookie': _cookie!,
        });
        request.files.add(
          await http.MultipartFile.fromPath(
            fieldName,
            filePath,
            filename: filename,
            contentType: MediaType.parse(contentType),
          ),
        );
        final streamedResponse = await request.send();
        return http.Response.fromStream(streamedResponse);
      },
    );
    await _captureCookie(response);
    return _decodeObject(response);
  }

  Future<void> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final cookie = prefs.getString(_sessionCookieKey);
    if (cookie != null && cookie.trim().isNotEmpty) {
      _cookie = cookie;
    }
  }

  Future<void> clearSession() async {
    _cookie = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionCookieKey);
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

    _cookie = existingCookies.entries
        .map((e) => '${e.key}=${e.value}')
        .join('; ');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionCookieKey, _cookie!);
  }

  Future<http.Response> _sendWithFallback(
    String path, {
    Map<String, String?> query = const {},
    required Duration timeout,
    required Future<http.Response> Function(Uri uri) send,
  }) async {
    Object? lastError;
    StackTrace? lastStack;

    for (final uri in ApiConfig.uris(path, query)) {
      // Dev-only network logging — log request + response timing via
      // dart:developer (DevTools Network tab + IDE log console). Release
      // build di-strip otomatis oleh kDebugMode constant.
      final stopwatch = kDebugMode ? (Stopwatch()..start()) : null;
      try {
        final response = await send(uri).timeout(timeout);
        if (kDebugMode) {
          stopwatch!.stop();
          developer.log(
            '${response.statusCode} ${uri.path} '
            '(${stopwatch.elapsedMilliseconds}ms)',
            name: 'api',
          );
        }
        return response;
      } catch (error, stackTrace) {
        if (kDebugMode) {
          stopwatch!.stop();
          developer.log(
            'FAILED ${uri.path} (${stopwatch.elapsedMilliseconds}ms): $error',
            name: 'api',
            level: 1000, // SEVERE
          );
        }
        lastError = error;
        lastStack = stackTrace;
      }
    }

    Error.throwWithStackTrace(lastError!, lastStack!);
  }

  Map<String, dynamic> _decodeObject(http.Response response) {
    final text = response.body.trim();
    final decoded = text.isEmpty ? <String, dynamic>{} : jsonDecode(text);
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
    if (response.statusCode == 401) {
      // Fire-and-forget clear (async tapi tidak di-await — non-blocking).
      clearSession();
      // Trigger callback kalau ada subscriber.
      onUnauthorized?.call();
    }

    final message = data['message'] ?? data['error'] ?? 'Request gagal.';
    throw ApiException(message.toString(), statusCode: response.statusCode);
  }
}

final apiClient = ApiClient();

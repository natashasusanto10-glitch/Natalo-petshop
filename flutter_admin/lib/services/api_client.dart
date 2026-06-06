import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';

/// HTTP client wrapper untuk admin app.
///
/// Auth: backend pakai cookie `admin_session` yang di-set saat
/// `POST /api/auth/admin-login`. Flutter http package tidak auto-handle
/// cookie persistence, jadi kita extract `set-cookie` header dari
/// login response, simpan di SharedPreferences, dan attach ke request
/// berikutnya sebagai `cookie: admin_session=<token>`.
class AdminApiClient {
  AdminApiClient._();

  static const _prefsKey = 'natalo.admin.session_cookie_v1';
  String? _sessionCookie;
  bool _hydrated = false;

  String? get sessionCookie => _sessionCookie;
  bool get isAuthenticated => _sessionCookie != null;

  Future<void> _ensureHydrated() async {
    if (_hydrated) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _sessionCookie = prefs.getString(_prefsKey);
    } catch (_) {}
    _hydrated = true;
  }

  Future<void> _persistSession(String? value) async {
    _sessionCookie = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value == null) {
        await prefs.remove(_prefsKey);
      } else {
        await prefs.setString(_prefsKey, value);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[adminApi.persist] $e');
    }
  }

  /// Login admin — POST /api/auth/admin-login dengan email + password.
  /// Backend balikan {ok: true} + Set-Cookie admin_session=<jwt>.
  Future<AdminAuthResult> login({
    required String email,
    required String password,
  }) async {
    await _ensureHydrated();
    try {
      final uri = ApiConfig.uri('/api/auth/admin-login');
      final res = await http
          .post(
            uri,
            headers: {
              'content-type': 'application/json',
              'accept': 'application/json',
            },
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        // Extract admin_session=... dari Set-Cookie header.
        final setCookie = res.headers['set-cookie'];
        if (setCookie == null || setCookie.isEmpty) {
          return const AdminAuthResult.failure(
            'Backend tidak set session cookie. Hubungi admin.',
          );
        }
        final token = _extractAdminSessionToken(setCookie);
        if (token == null) {
          return const AdminAuthResult.failure(
            'Token admin tidak ditemukan di response.',
          );
        }
        await _persistSession('admin_session=$token');
        return const AdminAuthResult.success();
      }
      if (res.statusCode == 401) {
        return const AdminAuthResult.failure(
          'Email atau password salah.',
        );
      }
      if (res.statusCode == 429) {
        return const AdminAuthResult.failure(
          'Terlalu banyak percobaan login. Coba lagi nanti.',
        );
      }
      return AdminAuthResult.failure('Login gagal (${res.statusCode}).');
    } catch (e) {
      if (kDebugMode) debugPrint('[adminApi.login] $e');
      return AdminAuthResult.failure(
        'Tidak bisa terhubung ke server. Cek koneksi.',
      );
    }
  }

  Future<void> logout() async {
    try {
      await http
          .post(
            ApiConfig.uri('/api/auth/logout'),
            headers: await _headers(),
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Best-effort — clear lokal apapun yang terjadi.
    }
    await _persistSession(null);
  }

  Future<dynamic> getJson(
    String path, {
    Map<String, dynamic>? query,
    Duration timeout = const Duration(seconds: 10),
  }) {
    return _send(
      () async => http
          .get(ApiConfig.uri(path, query), headers: await _headers())
          .timeout(timeout),
    );
  }

  Future<dynamic> postJson(
    String path, {
    Object? body,
    Duration timeout = const Duration(seconds: 10),
  }) {
    return _send(
      () async => http
          .post(
            ApiConfig.uri(path),
            headers: await _headers(json: true),
            body: body == null ? null : jsonEncode(body),
          )
          .timeout(timeout),
    );
  }

  Future<dynamic> patchJson(
    String path, {
    Object? body,
    Duration timeout = const Duration(seconds: 10),
  }) {
    return _send(
      () async => http
          .patch(
            ApiConfig.uri(path),
            headers: await _headers(json: true),
            body: body == null ? null : jsonEncode(body),
          )
          .timeout(timeout),
    );
  }

  Future<dynamic> putJson(
    String path, {
    Object? body,
    Duration timeout = const Duration(seconds: 10),
  }) {
    return _send(
      () async => http
          .put(
            ApiConfig.uri(path),
            headers: await _headers(json: true),
            body: body == null ? null : jsonEncode(body),
          )
          .timeout(timeout),
    );
  }

  Future<dynamic> deleteJson(
    String path, {
    Duration timeout = const Duration(seconds: 10),
  }) {
    return _send(
      () async =>
          http.delete(ApiConfig.uri(path), headers: await _headers()).timeout(timeout),
    );
  }

  /// Wrapper sentralized untuk semua HTTP call. Translate
  /// SocketException / TimeoutException ke AdminApiException dengan
  /// pesan ramah supaya UI bisa tampilkan message konsisten tanpa
  /// duplicate try/catch di tiap caller.
  Future<dynamic> _send(Future<http.Response> Function() request) async {
    await _ensureHydrated();
    try {
      final res = await request();
      return _decode(res);
    } on AdminApiException {
      rethrow;
    } on SocketException catch (e) {
      if (kDebugMode) debugPrint('[adminApi] socket: $e');
      throw const AdminApiException(
        'Tidak ada koneksi internet. Cek WiFi/data.',
        statusCode: -1,
      );
    } on TimeoutException catch (e) {
      if (kDebugMode) debugPrint('[adminApi] timeout: $e');
      throw const AdminApiException(
        'Koneksi lambat — request timeout. Coba lagi.',
        statusCode: -2,
      );
    } on http.ClientException catch (e) {
      if (kDebugMode) debugPrint('[adminApi] client: $e');
      throw const AdminApiException(
        'Tidak bisa terhubung ke server. Coba lagi.',
        statusCode: -3,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[adminApi] unknown: $e');
      throw const AdminApiException('Terjadi kesalahan tidak terduga.');
    }
  }

  Future<Map<String, String>> _headers({bool json = false}) async {
    await _ensureHydrated();
    return {
      if (json) 'content-type': 'application/json',
      'accept': 'application/json',
      if (_sessionCookie != null) 'cookie': _sessionCookie!,
    };
  }

  dynamic _decode(http.Response res) {
    final body = res.body.trim();
    if (res.statusCode == 401) {
      // Session expired / invalid.
      _persistSession(null);
      throw AdminApiException(
        'Sesi admin berakhir. Login ulang.',
        statusCode: 401,
      );
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw AdminApiException(
        _extractErrorMessage(body) ?? 'Request gagal (${res.statusCode}).',
        statusCode: res.statusCode,
      );
    }
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } catch (e) {
      throw AdminApiException('Response server tidak valid JSON.');
    }
  }

  String? _extractErrorMessage(String body) {
    if (body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final err = decoded['error'];
        final detail = decoded['detail'];
        // Kalau backend kirim {error: "...", detail: "..."}, gabungkan
        // jadi "error: detail" supaya admin lihat root cause bukan cuma
        // generic message. Pattern ini cocok untuk endpoint yang kasih
        // try/catch dengan detail Prisma error / validation msg.
        if (err is String && detail is String && detail.isNotEmpty) {
          return '$err: $detail';
        }
        if (err is String) return err;
        if (detail is String) return detail;
      }
    } catch (_) {}
    return null;
  }

  String? _extractAdminSessionToken(String setCookieHeader) {
    // Set-Cookie header format: "admin_session=<value>; Path=/; HttpOnly; ..."
    // Bisa juga multiple cookies separated by comma (kadang).
    final cookies = setCookieHeader.split(RegExp(r',\s*(?=[a-zA-Z_]+=)'));
    for (final cookie in cookies) {
      final match = RegExp(r'admin_session=([^;]+)').firstMatch(cookie);
      if (match != null) {
        return match.group(1);
      }
    }
    return null;
  }
}

class AdminAuthResult {
  final bool ok;
  final String? errorMessage;

  const AdminAuthResult.success()
      : ok = true,
        errorMessage = null;
  const AdminAuthResult.failure(String message)
      : ok = false,
        errorMessage = message;
}

class AdminApiException implements Exception {
  final int? statusCode;
  final String message;

  const AdminApiException(this.message, {this.statusCode});

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isServerError => (statusCode ?? 0) >= 500;

  @override
  String toString() => 'AdminApiException($statusCode): $message';
}

final AdminApiClient adminApi = AdminApiClient._();

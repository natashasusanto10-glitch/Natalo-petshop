import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../config/api_config.dart';
import 'api_client.dart';

/// Upload helper untuk admin app — pakai backend yang sudah ada
/// (`/api/admin/upload` untuk produk, `/api/feed/upload-photo` untuk feed).
///
/// Cookie session diambil dari [adminApi] supaya backend auth jalan.
class AdminUploadService {
  AdminUploadService._();
  static final AdminUploadService instance = AdminUploadService._();

  /// Upload foto produk ke UploadThing via `/api/admin/upload`.
  /// Backend constraint: max 2MB, image/jpeg|png|webp|gif.
  /// Returns absolute URL hasil upload.
  Future<String> uploadProductImage(File file) async {
    return _uploadMultipart(
      path: '/api/admin/upload',
      file: file,
      timeout: const Duration(seconds: 45),
    ).then((res) {
      final url = res['url']?.toString();
      if (url == null || url.isEmpty) {
        throw const AdminUploadException('Response upload tidak punya url.');
      }
      return url;
    });
  }

  /// Upload satu foto feed ke `/api/feed/upload-photo`.
  /// Backend constraint: max 8MB, image/jpeg|png|webp.
  Future<FeedPhotoUploadResult> uploadFeedPhoto(File file) async {
    final res = await _uploadMultipart(
      path: '/api/feed/upload-photo',
      file: file,
      timeout: const Duration(seconds: 60),
    );
    final url = res['url']?.toString();
    if (url == null || url.isEmpty) {
      throw const AdminUploadException('Response upload tidak punya url.');
    }
    return FeedPhotoUploadResult(
      url: url,
      key: res['key']?.toString(),
    );
  }

  Future<Map<String, dynamic>> _uploadMultipart({
    required String path,
    required File file,
    required Duration timeout,
  }) async {
    final uri = ApiConfig.uri(path);
    final request = http.MultipartRequest('POST', uri);

    // Attach admin session cookie (sama seperti AdminApiClient._headers).
    final cookie = adminApi.sessionCookie;
    if (cookie != null && cookie.isNotEmpty) {
      request.headers['cookie'] = cookie;
    }
    request.headers['accept'] = 'application/json';

    final filename = file.uri.pathSegments.isNotEmpty
        ? file.uri.pathSegments.last
        : 'upload.jpg';
    final ext = filename.contains('.')
        ? filename.split('.').last.toLowerCase()
        : 'jpg';
    final mimeType = switch (ext) {
      'png' => MediaType('image', 'png'),
      'webp' => MediaType('image', 'webp'),
      'gif' => MediaType('image', 'gif'),
      _ => MediaType('image', 'jpeg'),
    };

    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        file.path,
        filename: filename,
        contentType: mimeType,
      ),
    );

    try {
      final streamed = await request.send().timeout(timeout);
      final res = await http.Response.fromStream(streamed);
      if (res.statusCode == 401) {
        throw const AdminUploadException(
          'Sesi admin berakhir. Login ulang.',
          statusCode: 401,
        );
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw AdminUploadException(
          _extractError(res.body) ?? 'Upload gagal (${res.statusCode}).',
          statusCode: res.statusCode,
        );
      }
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) {
        throw const AdminUploadException('Response upload tidak valid.');
      }
      return decoded;
    } on AdminUploadException {
      rethrow;
    } catch (e) {
      if (kDebugMode) debugPrint('[adminUpload] $e');
      throw const AdminUploadException('Tidak bisa upload. Cek koneksi.');
    }
  }

  String? _extractError(String body) {
    if (body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is String) {
        return decoded['error'] as String;
      }
    } catch (_) {}
    return null;
  }
}

class FeedPhotoUploadResult {
  final String url;
  final String? key;
  const FeedPhotoUploadResult({required this.url, this.key});
}

class AdminUploadException implements Exception {
  final String message;
  final int? statusCode;
  const AdminUploadException(this.message, {this.statusCode});

  @override
  String toString() => 'AdminUploadException($statusCode): $message';
}

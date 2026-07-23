import 'dart:convert';
import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../config/api_config.dart';
import '../models/new_post_user_tag.dart';
import '../state/member_store.dart';

/// Service untuk fitur Posting Foto di Feed (1-8 foto carousel).
///
/// Flow:
///   1. Client (Flutter) pick foto via image_picker multi-select
///   2. Loop: upload satu foto per request ke /api/feed/upload-photo
///      → receive {url, key} per foto
///   3. Collect semua {url, key} → POST /api/feed/posts dengan
///      kind=PHOTO_CAROUSEL + images array
///   4. Backend create FeedPost + bulk insert FeedMedia rows
///   5. Status PENDING_REVIEW (customer) atau ACTIVE (admin)
class FeedPhotoService {
  FeedPhotoService._();

  Map<String, String> get _headers {
    final token = memberStore.sessionToken;
    return {
      'accept': 'application/json',
      if (token != null) 'authorization': 'Bearer $token',
      if (token != null) 'cookie': 'member_session=$token',
    };
  }

  /// Compress photo file sebelum upload supaya tidak kena Vercel 4.5MB
  /// platform limit. iPhone camera default 4032×3024 = ~5MB JPEG; setelah
  /// compress ke 1920×1920 quality 75 → ~500KB-1MB.
  ///
  /// Skip kalau file sudah kecil (<1.5MB) — sudah aman untuk Vercel.
  /// Return compressed File di temp directory, atau original kalau compress
  /// gagal (graceful fallback supaya upload tetap jalan untuk foto kecil).
  Future<File> _compressForUpload(File source) async {
    try {
      final originalBytes = await source.length();
      // Skip compression kalau foto sudah ≤1.5MB — sweet spot di bawah
      // Vercel 4.5MB limit dengan headroom. Hemat CPU + battery + waktu.
      if (originalBytes <= 1.5 * 1024 * 1024) return source;

      final tempDir = await getTemporaryDirectory();
      final outputPath =
          '${tempDir.path}/feed_compressed_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final compressed = await FlutterImageCompress.compressAndGetFile(
        source.path,
        outputPath,
        // 1920×1920 max — match image_picker config di flow lama, juga
        // ideal untuk display feed (max viewport phone ~1170px actual).
        minWidth: 1920,
        minHeight: 1920,
        // Quality 75 — sweet spot. iOS HEIC asli sudah quality ~95, drop
        // 20 point negligible visual diff tapi 3-5x file size reduction.
        quality: 75,
        // Force JPEG output — Vercel + UploadThing optimal di JPEG, plus
        // gampang preview di image viewer. PNG/WebP support diabaikan
        // untuk uniformity.
        format: CompressFormat.jpeg,
      );

      if (compressed == null) return source;
      return File(compressed.path);
    } catch (_) {
      // Compression fail jangan break upload — fallback ke original. Kalau
      // file kebesaran, backend tetap return 413 dengan pesan jelas.
      return source;
    }
  }

  Future<({int? width, int? height})> _readImageSize(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return (width: null, height: null);
      return (width: image.width, height: image.height);
    } catch (_) {
      return (width: null, height: null);
    }
  }

  /// Upload 1 foto ke UploadThing via backend, return UploadThing URL +
  /// key. Throws kalau status != 200.
  Future<({String url, String? key, int? width, int? height})>
      uploadSinglePhoto(File file) async {
    // Compress dulu supaya tidak kena Vercel 4.5MB request body limit.
    // Original file 4-6MB (iPhone HEIC + ProRAW + DSLR) di-compress ke
    // 1920×1920 JPEG quality 75 → ~500KB-1MB.
    final fileToUpload = await _compressForUpload(file);
    final imageSize = await _readImageSize(fileToUpload);

    final uri = ApiConfig.uri('/api/feed/upload-photo');
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(_headers);

    final filename = fileToUpload.uri.pathSegments.last;
    final ext = filename.split('.').last.toLowerCase();
    final mimeType = switch (ext) {
      'png' => MediaType('image', 'png'),
      'webp' => MediaType('image', 'webp'),
      _ => MediaType('image', 'jpeg'),
    };

    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        fileToUpload.path,
        filename: filename,
        contentType: mimeType,
      ),
    );

    final streamed = await request.send().timeout(
          const Duration(seconds: 60),
        );
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode != 200) {
      String message;
      try {
        final decoded = jsonDecode(res.body);
        message = decoded is Map<String, dynamic>
            ? (decoded['error']?.toString() ?? 'Upload foto gagal.')
            : 'Upload foto gagal.';
      } catch (_) {
        message = 'Upload foto gagal.';
      }
      throw FeedPhotoUploadException(message);
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FeedPhotoUploadException('Response upload tidak valid.');
    }
    final url = decoded['url']?.toString();
    final key = decoded['key']?.toString();
    if (url == null || url.isEmpty) {
      throw const FeedPhotoUploadException('URL upload kosong.');
    }
    return (
      url: url,
      key: key,
      width: imageSize.width,
      height: imageSize.height,
    );
  }

  /// Batch upload 1-8 foto dengan concurrency cap 4 — 4 upload paralel
  /// jalan bersamaan, sisanya queue setelah ada slot kosong. Cap 4 karena:
  ///   - HTTP/1.1 default cap connection per host = 6, kasih 2 spare untuk
  ///     other traffic (analytics, push refresh)
  ///   - Backend rate limit /api/feed/upload-photo masih comfortable
  ///   - Concurrent encode overhead Vercel function tetap acceptable
  ///
  /// Result list di-preserve urutan SAMA dengan input files via index
  /// pre-allocation (penting untuk sortOrder carousel).
  ///
  /// Performance gain (8 foto × ~4s upload via Vercel proxy):
  ///   - Sebelum (serial): ~32 detik
  ///   - Sesudah (parallel cap 4): ~8-12 detik
  ///
  /// Kalau ada upload yang gagal, throw exception — partial upload
  /// tidak commit ke backend. UploadThing assets yang terlanjur upload
  /// dianggap orphan (cleanup periodik via UploadThing dashboard atau
  /// API delete-key).
  Future<List<({String url, String? key, int? width, int? height})>>
      uploadAllPhotos(
    List<File> files, {
    void Function(int done, int total)? onProgress,
  }) async {
    if (files.isEmpty) return [];
    const concurrency = 4;
    final results =
        List<({String url, String? key, int? width, int? height})?>.filled(
      files.length,
      null,
      growable: false,
    );
    var done = 0;
    final pending = List.generate(files.length, (i) => i);

    Future<void> worker() async {
      while (true) {
        if (pending.isEmpty) return;
        final index = pending.removeAt(0);
        final file = files[index];
        final uploaded = await uploadSinglePhoto(file);
        results[index] = uploaded;
        done++;
        onProgress?.call(done, files.length);
      }
    }

    // Spawn N workers, semua kerja dari shared queue. Future.wait
    // bubble-up exception dari worker manapun → seluruh batch fail.
    await Future.wait(
      List.generate(
        concurrency.clamp(1, files.length),
        (_) => worker(),
      ),
    );

    // results sudah pasti non-null karena worker isi semua slot sebelum
    // return. Cast aman.
    return results.cast<({String url, String? key, int? width, int? height})>();
  }

  /// Create PHOTO_CAROUSEL FeedPost dengan media + caption + product tags.
  ///
  /// Semua konten kini auto-ACTIVE (tanpa review admin) — langsung tayang.
  /// Moderasi reaktif via report/Hide.
  Future<({String postId, String status})> createPhotoPost({
    required List<({String url, String? key, int? width, int? height})> images,
    required String title,
    String? description,
    List<String> productIds = const [],
    List<NewPostUserTag> taggedUsers = const [],
  }) async {
    if (images.isEmpty) {
      throw const FeedPhotoUploadException(
        'Pilih minimal 1 foto untuk melanjutkan.',
      );
    }
    if (images.length > 8) {
      throw const FeedPhotoUploadException(
        'Maksimal 8 foto dalam 1 postingan.',
      );
    }

    final uri = ApiConfig.uri('/api/feed/posts');
    final body = <String, dynamic>{
      'kind': 'PHOTO_CAROUSEL',
      'title': title,
      if (description != null && description.isNotEmpty)
        'description': description,
      'images': images
          .map((img) => {
                'url': img.url,
                if (img.key != null) 'key': img.key,
                if (img.width != null) 'width': img.width,
                if (img.height != null) 'height': img.height,
              })
          .toList(),
      if (productIds.isNotEmpty) 'productIds': productIds,
      if (taggedUsers.isNotEmpty)
        'taggedUsers': taggedUsers.map((t) => t.toApiJson()).toList(),
    };

    final res = await http
        .post(
          uri,
          headers: {
            ..._headers,
            'content-type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));

    if (res.statusCode != 200) {
      String message;
      try {
        final decoded = jsonDecode(res.body);
        message = decoded is Map<String, dynamic>
            ? (decoded['error']?.toString() ?? 'Gagal kirim postingan.')
            : 'Gagal kirim postingan.';
      } catch (_) {
        message = 'Gagal kirim postingan.';
      }
      throw FeedPhotoUploadException(message);
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FeedPhotoUploadException('Response post tidak valid.');
    }
    final post = decoded['post'];
    if (post is! Map<String, dynamic>) {
      throw const FeedPhotoUploadException('Post object tidak valid.');
    }
    return (
      postId: post['id']?.toString() ?? '',
      status: post['status']?.toString() ?? 'ACTIVE',
    );
  }
}

class FeedPhotoUploadException implements Exception {
  final String message;
  const FeedPhotoUploadException(this.message);

  @override
  String toString() => message;
}

final feedPhotoService = FeedPhotoService._();

/// Draft model untuk photo post — mirror FeedCreatePostDraft tapi
/// khusus carousel foto. Disimpan in-memory selama upload flow.
class FeedPhotoDraft {
  final List<File> localFiles;
  final String caption;
  final List<String> taggedProductIds;

  const FeedPhotoDraft({
    required this.localFiles,
    this.caption = '',
    this.taggedProductIds = const [],
  });

  FeedPhotoDraft copyWith({
    List<File>? localFiles,
    String? caption,
    List<String>? taggedProductIds,
  }) {
    return FeedPhotoDraft(
      localFiles: localFiles ?? this.localFiles,
      caption: caption ?? this.caption,
      taggedProductIds: taggedProductIds ?? this.taggedProductIds,
    );
  }
}

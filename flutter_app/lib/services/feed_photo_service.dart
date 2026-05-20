import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../config/api_config.dart';
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

  /// Upload 1 foto ke UploadThing via backend, return UploadThing URL +
  /// key. Throws kalau status != 200.
  Future<({String url, String? key})> uploadSinglePhoto(File file) async {
    final uri = ApiConfig.uri('/api/feed/upload-photo');
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(_headers);

    final filename = file.uri.pathSegments.last;
    final ext = filename.split('.').last.toLowerCase();
    final mimeType = switch (ext) {
      'png' => MediaType('image', 'png'),
      'webp' => MediaType('image', 'webp'),
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
    return (url: url, key: key);
  }

  /// Batch upload 1-8 foto paralel via Future.wait. Return list of
  /// uploaded photo data (url + key) dengan urutan SAMA dengan input
  /// files (penting untuk sortOrder carousel).
  ///
  /// Kalau ada upload yang gagal, throw exception — partial upload
  /// tidak commit ke backend. UploadThing assets yang terlanjur upload
  /// dianggap orphan (cleanup periodik via UploadThing dashboard atau
  /// API delete-key).
  Future<List<({String url, String? key})>> uploadAllPhotos(
    List<File> files, {
    void Function(int done, int total)? onProgress,
  }) async {
    if (files.isEmpty) return [];
    final results = <({String url, String? key})>[];
    var done = 0;
    for (final file in files) {
      // Serial upload (bukan parallel) supaya:
      //  1. Backend rate limit aman
      //  2. Progress indicator akurat
      //  3. User punya time untuk cancel kalau perlu (future)
      final uploaded = await uploadSinglePhoto(file);
      results.add(uploaded);
      done++;
      onProgress?.call(done, files.length);
    }
    return results;
  }

  /// Create PHOTO_CAROUSEL FeedPost dengan media + caption + product tags.
  ///
  /// Customer: status auto-PENDING_REVIEW, dispatch ke admin moderation.
  /// Admin: status auto-ACTIVE, langsung tayang di feed.
  Future<({String postId, String status})> createPhotoPost({
    required List<({String url, String? key})> images,
    required String title,
    String? description,
    List<String> productIds = const [],
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
              })
          .toList(),
      if (productIds.isNotEmpty) 'productIds': productIds,
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
      status: post['status']?.toString() ?? 'PENDING_REVIEW',
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

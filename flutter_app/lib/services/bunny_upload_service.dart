import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:tus_client_dart/tus_client_dart.dart';

import 'api_client.dart';
import 'feed_service.dart';

/// Hasil provision dari server — credential + endpoint untuk upload
/// direct ke Bunny CDN tanpa lewat Vercel serverless.
class BunnyUploadProvision {
  final String postId;
  final String videoGuid;
  final String? uploadUrl; // Legacy single PUT URL
  final Map<String, String> uploadHeaders;
  final BunnyTusCredentials? tus;

  const BunnyUploadProvision({
    required this.postId,
    required this.videoGuid,
    this.uploadUrl,
    required this.uploadHeaders,
    this.tus,
  });

  factory BunnyUploadProvision.fromJson(Map<String, dynamic> json) {
    final tusRaw = json['tus'];
    return BunnyUploadProvision(
      postId: (json['postId'] ?? '').toString(),
      videoGuid: (json['videoGuid'] ?? '').toString(),
      uploadUrl: json['uploadUrl']?.toString(),
      uploadHeaders: Map<String, String>.from(
        (json['uploadHeaders'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), v?.toString() ?? ''),
            ) ??
            const {},
      ),
      tus: tusRaw is Map
          ? BunnyTusCredentials.fromJson(Map<String, dynamic>.from(tusRaw))
          : null,
    );
  }
}

/// TUS credentials dari Bunny — signature SHA256 (library + key + expire
/// + guid) di-generate server-side, client tinggal kirim header standar
/// TUS protocol plus 4 header auth Bunny.
class BunnyTusCredentials {
  final String endpoint;
  final String videoId;
  final String libraryId;
  final String authSignature;
  final int authExpire;

  const BunnyTusCredentials({
    required this.endpoint,
    required this.videoId,
    required this.libraryId,
    required this.authSignature,
    required this.authExpire,
  });

  factory BunnyTusCredentials.fromJson(Map<String, dynamic> json) {
    return BunnyTusCredentials(
      endpoint: (json['endpoint'] ?? '').toString(),
      videoId: (json['videoId'] ?? '').toString(),
      libraryId: (json['libraryId'] ?? '').toString(),
      authSignature: (json['authSignature'] ?? '').toString(),
      authExpire: (json['authExpire'] is int)
          ? json['authExpire'] as int
          : int.tryParse(json['authExpire']?.toString() ?? '') ?? 0,
    );
  }
}

/// Service untuk upload video direct ke Bunny Stream CDN — bypass Vercel
/// serverless yang punya 4.5 MB body limit + 60s timeout.
///
/// Flow:
///   1. POST /api/feed/bunny/upload-url → server create Bunny placeholder
///      + FeedPost row (status=uploading), return signed URL + TUS creds.
///   2. Upload via TUS (resumable, chunked) atau simple PUT (fallback).
///   3. Bunny webhook → server update encodingStatus=ready saat encoding
///      kelar. Client tidak perlu tunggu — post sudah ACTIVE.
///
/// Replace endpoint legacy /api/feed/upload-video yang lewat serverless.
class BunnyUploadService {
  final ApiClient apiClient;
  final FeedService feedService;

  BunnyUploadService({required this.apiClient, required this.feedService});

  /// Provision Bunny upload — backend create placeholder + FeedPost row.
  /// Body fields match dengan PWA /api/feed/bunny/upload-url.
  Future<BunnyUploadProvision> provisionUpload({
    required String title,
    required String? description,
    String? petType,
    int? videoDurationSec,
    List<String> productIds = const [],
    String? thumbnailUrl,
  }) async {
    final data = await apiClient.postJson(
      '/api/feed/bunny/upload-url',
      body: {
        'title': title,
        if (description != null && description.isNotEmpty)
          'description': description,
        if (petType != null && petType.isNotEmpty) 'petType': petType,
        if (videoDurationSec != null) 'videoDurationSec': videoDurationSec,
        'productIds': productIds,
        if (thumbnailUrl != null && thumbnailUrl.isNotEmpty)
          'thumbnailUrl': thumbnailUrl,
      },
    );
    return BunnyUploadProvision.fromJson(data);
  }

  /// Upload video file via TUS resumable protocol ke Bunny endpoint.
  ///
  /// Benefit utama vs simple PUT:
  ///   - Koneksi putus di tengah → resume otomatis dari byte terakhir
  ///   - Background-tolerant (kalau lifecycle aware)
  ///   - Progress reliable per-chunk
  ///
  /// Chunk size default 5 MB — balance antara granularity resume vs
  /// overhead per request. Naikkan kalau koneksi stabil (WiFi).
  Future<void> uploadViaTus({
    required File videoFile,
    required BunnyTusCredentials credentials,
    String? filetype,
    String? title,
    int chunkSize = 5 * 1024 * 1024,
    void Function(int percent, int loaded, int total)? onProgress,
  }) async {
    final client = TusClient(
      XFile(videoFile.path),
      store: TusMemoryStore(), // In-memory store — cukup untuk single session
      maxChunkSize: chunkSize,
    );

    await client.upload(
      uri: Uri.parse(credentials.endpoint),
      headers: {
        'AuthorizationSignature': credentials.authSignature,
        'AuthorizationExpire': credentials.authExpire.toString(),
        'VideoId': credentials.videoId,
        'LibraryId': credentials.libraryId,
      },
      metadata: {
        'filetype': filetype ?? 'video/mp4',
        'title': title ?? 'feed-video',
      },
      measureUploadSpeed: false,
      onProgress: (progress, estimate) {
        final percent = progress.toInt().clamp(0, 100);
        if (onProgress != null) {
          onProgress(percent, 0, 0); // tus_client_dart tidak expose byte
        }
      },
      onComplete: () {
        if (kDebugMode) {
          debugPrint('[bunny-tus] upload complete');
        }
      },
    );
  }

  /// Fallback single PUT upload — pakai kalau provision tidak return TUS
  /// credentials (Bunny config error) atau file kecil yang tidak butuh
  /// resume. Lewat http client, no streaming progress reliable.
  Future<void> uploadViaPut({
    required File videoFile,
    required String uploadUrl,
    required Map<String, String> headers,
    void Function(int percent, int loaded, int total)? onProgress,
  }) async {
    final bytes = await videoFile.readAsBytes();
    final client = HttpClient();
    final req = await client.putUrl(Uri.parse(uploadUrl));
    headers.forEach((k, v) => req.headers.set(k, v));
    req.contentLength = bytes.length;
    req.add(bytes);
    final resp = await req.close();
    final body = await resp.transform(const _ByteStreamTransformer()).join();
    client.close();
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw ApiException(
        'Bunny PUT failed: ${resp.statusCode} $body',
        statusCode: resp.statusCode,
      );
    }
    onProgress?.call(100, bytes.length, bytes.length);
  }

  /// Finalize: tidak ada step server "create post" karena server sudah
  /// buat FeedPost row di provisionUpload step. Bunny webhook handle
  /// encoding completion → encodingStatus=ready saat selesai.
  ///
  /// Helper ini hanya placeholder kalau nanti perlu signal ke server
  /// "upload kelar, mulai poll" (saat ini server tidak butuh).
  Future<void> finalize(String postId) async {
    // No-op — Bunny webhook akan update post status saat encoding done.
    // Kalau mau force poll, panggil reconcile endpoint di sini.
    if (kDebugMode) {
      debugPrint('[bunny-upload] finalize postId=$postId — waiting webhook');
    }
  }
}

/// Transform raw byte stream ke String — utility internal untuk read
/// response body sederhana.
class _ByteStreamTransformer extends StreamTransformerBase<List<int>, String> {
  const _ByteStreamTransformer();

  @override
  Stream<String> bind(Stream<List<int>> stream) async* {
    final buffer = <int>[];
    await for (final chunk in stream) {
      buffer.addAll(chunk);
    }
    yield String.fromCharCodes(buffer);
  }
}

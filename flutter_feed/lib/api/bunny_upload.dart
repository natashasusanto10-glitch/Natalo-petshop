import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'feed_api.dart';

// Mirror of lib/feed/tus-upload.ts + lib/feed/bunny.ts (server credentials).
//
// Wave 3 — TUS resumable upload to Bunny Stream.
//
// Flow:
//  1. Client POST /api/feed/bunny/upload-url → returns { uploadUrl, tus: {
//       endpoint, headers: { AuthorizationSignature, AuthorizationExpire,
//       VideoId, LibraryId } }, videoGuid }
//  2. Client runs TUS protocol against `tus.endpoint` with provided headers.
//  3. Bunny webhook → server marks FeedPost.encodingStatus = ready when done.
//
// Settings (mirror web):
//  - chunk size: 5 MB
//  - retry delays: [0, 1, 3, 5, 10, 20, 30] seconds
//  - resume: store upload URL keyed by file fingerprint in shared_preferences

const int kTusChunkSize = 5 * 1024 * 1024; // 5 MB
const List<Duration> kTusRetryDelays = [
  Duration.zero,
  Duration(seconds: 1),
  Duration(seconds: 3),
  Duration(seconds: 5),
  Duration(seconds: 10),
  Duration(seconds: 20),
  Duration(seconds: 30),
];

class BunnyUploadCredentials {
  final String videoGuid;
  final String tusEndpoint;
  final Map<String, String> tusHeaders;
  final String simplePutUrl; // fallback non-resumable

  const BunnyUploadCredentials({
    required this.videoGuid,
    required this.tusEndpoint,
    required this.tusHeaders,
    required this.simplePutUrl,
  });

  factory BunnyUploadCredentials.fromJson(Map<String, dynamic> j) {
    final tus = (j['tus'] as Map<String, dynamic>?) ?? const {};
    final hdrs = ((tus['headers'] as Map?) ?? const {}).map(
      (k, v) => MapEntry(k.toString(), v.toString()),
    );
    return BunnyUploadCredentials(
      videoGuid: j['videoGuid'] as String,
      tusEndpoint:
          (tus['endpoint'] as String?) ?? 'https://video.bunnycdn.com/tusupload',
      tusHeaders: hdrs,
      simplePutUrl: j['uploadUrl'] as String,
    );
  }
}

class BunnyUploader {
  final FeedApi api;
  BunnyUploader(this.api);

  /// Request fresh upload credentials. Server creates Bunny video placeholder
  /// and signs TUS auth header (SHA256 of library_id + api_key + expire +
  /// video_guid). 1-hour expiry covers 200 MB upload on 3G (~30 min).
  Future<BunnyUploadCredentials> requestCredentials({
    required String title,
  }) async {
    final res = await api.rawDio.post<Map<String, dynamic>>(
      '/api/feed/bunny/upload-url',
      data: {'title': title},
    );
    return BunnyUploadCredentials.fromJson(res.data!);
  }

  /// Resumable upload via TUS protocol.
  ///
  /// [onProgress] receives (bytesSent, totalBytes).
  /// [resumeUploadUrl] — pass previously persisted URL to resume; null = fresh.
  /// Returns the upload URL (persist for resume across app restarts).
  Future<String> uploadResumable({
    required File file,
    required BunnyUploadCredentials creds,
    String? resumeUploadUrl,
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final dio = Dio();
    final total = await file.length();
    String uploadUrl = resumeUploadUrl ?? '';

    // 1. Create upload (POST) if no resume URL yet.
    if (uploadUrl.isEmpty) {
      final createRes = await dio.post<void>(
        creds.tusEndpoint,
        options: Options(
          headers: {
            ...creds.tusHeaders,
            'Tus-Resumable': '1.0.0',
            'Upload-Length': total.toString(),
            'Content-Length': '0',
          },
          validateStatus: (s) => s != null && s < 400,
        ),
        cancelToken: cancelToken,
      );
      final location = createRes.headers.value('location');
      if (location == null) {
        throw Exception('Bunny TUS: missing Location header on create');
      }
      uploadUrl = _resolveUrl(creds.tusEndpoint, location);
    }

    // 2. Discover current offset (HEAD) — handles resume case.
    int offset = await _fetchOffset(dio, uploadUrl, creds.tusHeaders);

    // 3. Stream PATCH chunks.
    final raf = await file.open();
    try {
      while (offset < total) {
        final chunkLen =
            (offset + kTusChunkSize > total) ? total - offset : kTusChunkSize;
        await raf.setPosition(offset);
        final chunk = await raf.read(chunkLen);
        await _patchChunkWithRetry(
          dio: dio,
          uploadUrl: uploadUrl,
          chunk: chunk,
          offset: offset,
          headers: creds.tusHeaders,
          cancelToken: cancelToken,
        );
        offset += chunkLen;
        onProgress?.call(offset, total);
      }
    } finally {
      await raf.close();
    }

    return uploadUrl;
  }

  /// Fallback non-resumable PUT — used when TUS init fails. Web equivalent:
  /// XHR PUT to creds.simplePutUrl with progress events.
  Future<void> uploadSimplePut({
    required File file,
    required BunnyUploadCredentials creds,
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final dio = Dio();
    final total = await file.length();
    await dio.put<void>(
      creds.simplePutUrl,
      data: file.openRead(),
      options: Options(
        headers: {
          'Content-Type': 'application/octet-stream',
          'Content-Length': total.toString(),
        },
      ),
      cancelToken: cancelToken,
      onSendProgress: (sent, _) => onProgress?.call(sent, total),
    );
  }

  Future<int> _fetchOffset(
      Dio dio, String url, Map<String, String> baseHeaders) async {
    final res = await dio.head<void>(
      url,
      options: Options(
        headers: {
          ...baseHeaders,
          'Tus-Resumable': '1.0.0',
        },
        validateStatus: (s) => s != null && s < 400,
      ),
    );
    final v = res.headers.value('upload-offset') ?? '0';
    return int.tryParse(v) ?? 0;
  }

  Future<void> _patchChunkWithRetry({
    required Dio dio,
    required String uploadUrl,
    required Uint8List chunk,
    required int offset,
    required Map<String, String> headers,
    CancelToken? cancelToken,
  }) async {
    Object? lastError;
    for (final delay in kTusRetryDelays) {
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      try {
        await dio.patch<void>(
          uploadUrl,
          data: Stream.value(chunk),
          options: Options(
            headers: {
              ...headers,
              'Tus-Resumable': '1.0.0',
              'Upload-Offset': offset.toString(),
              'Content-Type': 'application/offset+octet-stream',
              'Content-Length': chunk.length.toString(),
            },
            validateStatus: (s) => s != null && s < 400,
          ),
          cancelToken: cancelToken,
        );
        return;
      } catch (e) {
        lastError = e;
        // Re-fetch offset before next attempt (server may have partial commit).
        try {
          final fresh = await _fetchOffset(dio, uploadUrl, headers);
          if (fresh != offset) {
            // server ahead of us — drop this chunk's first (fresh - offset)
            // bytes on retry. Simplest: throw to caller to reload from file.
            throw _OffsetAdvancedError(fresh);
          }
        } catch (_) {
          // ignore offset re-fetch error, try next retry
        }
      }
    }
    throw Exception('Bunny TUS upload failed after retries: $lastError');
  }
}

class _OffsetAdvancedError implements Exception {
  final int newOffset;
  _OffsetAdvancedError(this.newOffset);
  @override
  String toString() => 'Server offset advanced to $newOffset';
}

String _resolveUrl(String base, String location) {
  if (location.startsWith('http')) return location;
  final baseUri = Uri.parse(base);
  return baseUri.resolve(location).toString();
}

// ─────────────────────────────────────────────────────────────────────────────
// Bunny CDN URL helpers — mirror of lib/feed/bunny.ts URL transforms.
// Use these when you have a Bunny video GUID and want to construct
// playback URLs without round-tripping the server.

String bunnyPlaylistUrl(String cdnHost, String guid) =>
    'https://$cdnHost/$guid/playlist.m3u8';

String bunnyMp4Url(String cdnHost, String guid, int height) =>
    'https://$cdnHost/$guid/play_${height}p.mp4';

String bunnyThumbnailUrl(String cdnHost, String guid) =>
    'https://$cdnHost/$guid/thumbnail.jpg';

/// Convert HLS playlist URL to MP4 progressive at given height.
String bunnyHlsToMp4(String hlsUrl, int height) {
  return hlsUrl.replaceFirst('/playlist.m3u8', '/play_${height}p.mp4');
}

/// Convert MP4 URL to HLS playlist.
String bunnyMp4ToHls(String mp4Url) {
  return mp4Url.replaceFirst(RegExp(r'/play_\d+p\.mp4$'), '/playlist.m3u8');
}

/// Rewrite MP4 quality (240/360/480/720/1080).
String rewriteBunnyMp4Quality(String mp4Url, int height) {
  return mp4Url.replaceFirst(
    RegExp(r'/play_\d+p\.mp4$'),
    '/play_${height}p.mp4',
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/services/video_quality_service.dart';

/// Fokus: guard signed-URL di [VideoQualityService.resolvePlaybackUrl].
///
/// Produksi feed pakai HLS *directory token* dari `signBunnyUrl`:
///   https://host/bcdn_token=<t>&token_path=<enc /guid/>&expires=<ts>/<guid>/playlist.m3u8
/// Token Bunny ditandatangani atas DIREKTORI (token_path), jadi rewrite
/// nama file dalam direktori yang sama (playlist.m3u8 → play_480p.mp4)
/// tetap valid — preferensi `data_saver` HARUS tetap dihormati.
///
/// Sebaliknya URL signed file-spesifik (query `token=` tanpa `token_path`)
/// tandatangannya terikat path file persis → rewrite = 403, harus di-skip.
void main() {
  final svc = VideoQualityService();

  const guid = 'abcd1234-5678-90ab-cdef-1234567890ab';
  // Bentuk persis output signBunnyUrl untuk HLS (path-based directory token).
  const signedHls =
      'https://vz-xyz.b-cdn.net/bcdn_token=SGVsbG9Xb3JsZFRva2Vu'
      '&token_path=%2F$guid%2F&expires=1799999999/$guid/playlist.m3u8';

  // URL signed file-spesifik (MP4, query-param token — TANPA token_path).
  const signedFileMp4 =
      'https://vz-xyz.b-cdn.net/$guid/play_720p.mp4'
      '?token=SGVsbG9Xb3JsZFRva2Vu&expires=1799999999';

  group('data_saver pada URL signed', () {
    test('HLS directory-token → rewrite ke play_480p.mp4, prefix token utuh',
        () {
      final out = svc.resolvePlaybackUrl(signedHls, userPreference: 'data_saver');
      expect(out, contains('play_480p.mp4'));
      expect(out, isNot(contains('playlist.m3u8')));
      // Token prefix + expires + token_path harus tetap ada (signature valid).
      expect(out, contains('bcdn_token=SGVsbG9Xb3JsZFRva2Vu'));
      expect(out, contains('token_path=%2F$guid%2F'));
      expect(out, contains('expires=1799999999'));
      // Tetap di direktori guid yang sama.
      expect(out, contains('/$guid/play_480p.mp4'));
    });

    test('file-spesifik token (tanpa token_path) → JANGAN diubah', () {
      final out =
          svc.resolvePlaybackUrl(signedFileMp4, userPreference: 'data_saver');
      expect(out, signedFileMp4);
    });
  });

  group('high pada URL signed', () {
    test('HLS directory-token → rewrite ke play_720p.mp4', () {
      final out = svc.resolvePlaybackUrl(signedHls, userPreference: 'high');
      expect(out, contains('play_720p.mp4'));
      expect(out, isNot(contains('playlist.m3u8')));
      expect(out, contains('bcdn_token=SGVsbG9Xb3JsZFRva2Vu'));
      expect(out, contains('token_path=%2F$guid%2F'));
    });

    test('file-spesifik token → JANGAN diubah', () {
      final out = svc.resolvePlaybackUrl(signedFileMp4, userPreference: 'high');
      expect(out, signedFileMp4);
    });
  });

  group('auto pada URL signed HLS directory-token — Opsi A: tak berubah', () {
    test('auto/null tetap kembalikan HLS apa adanya (tier unknown default)',
        () {
      final out = svc.resolvePlaybackUrl(signedHls, userPreference: 'auto');
      expect(out, signedHls);
    });

    test('null preference juga tak menyentuh signed HLS', () {
      final out = svc.resolvePlaybackUrl(signedHls);
      expect(out, signedHls);
    });
  });

  group('URL legacy tak signed tetap jalan seperti sebelumnya', () {
    const legacyHls = 'https://vz-xyz.b-cdn.net/$guid/playlist.m3u8';
    test('data_saver rewrite ke 480p', () {
      final out =
          svc.resolvePlaybackUrl(legacyHls, userPreference: 'data_saver');
      expect(out, 'https://vz-xyz.b-cdn.net/$guid/play_480p.mp4');
    });

    test('string kosong tetap kosong', () {
      expect(svc.resolvePlaybackUrl(''), '');
    });
  });
}

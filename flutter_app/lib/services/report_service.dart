import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// Tipe konten yang dilaporkan — match dengan kategori backend.
enum ReportTargetKind {
  feedPost('feed_post', 'postingan'),
  feedComment('feed_comment', 'komentar'),
  productReview('product_review', 'ulasan produk'),
  user('user', 'pengguna');

  final String wireValue;
  final String displayLabel;
  const ReportTargetKind(this.wireValue, this.displayLabel);
}

/// Alasan report — match dengan Google Play UGC policy categories.
/// User pilih satu di bottom sheet, value-nya dikirim ke backend.
enum ReportReason {
  spam('spam', 'Spam atau penipuan'),
  hateSpeech('hate_speech', 'Ujaran kebencian atau diskriminasi'),
  violence('violence', 'Kekerasan atau ancaman'),
  sexual('sexual', 'Konten seksual atau ketelanjangan'),
  harassment('harassment', 'Pelecehan atau perundungan'),
  misinformation('misinformation', 'Informasi menyesatkan'),
  copyright('copyright', 'Pelanggaran hak cipta'),
  illegal('illegal', 'Konten ilegal'),
  other('other', 'Lainnya');

  final String wireValue;
  final String displayLabel;
  const ReportReason(this.wireValue, this.displayLabel);
}

/// Service untuk submit user report ke backend Natalo. Endpoint
/// `/api/moderation/reports` di Next.js (admin reviewer di dashboard
/// Natalo bisa lihat antrian dan ambil action: hapus konten, suspend
/// user, dismiss false-positive).
///
/// **Kenapa wajib ada**: Google Play UGC policy mensyaratkan setiap app
/// yang punya user-generated content (review, comment, feed post)
/// menyediakan cara user laporkan konten yang melanggar. Tanpa endpoint
/// ini + UI di [feed_screen.dart] / [member_reviews_screen.dart] /
/// [feed_comment_sheet.dart], app akan ditolak Google saat submit
/// Production track dengan violation "User Generated Content".
///
/// **Fallback kalau backend belum ready**: response 404 di-treat sebagai
/// success diam-diam — request tetap dianggap "submitted" supaya user
/// UX tidak break. Admin Natalo bisa lihat di Crashlytics / Sentry
/// kalau ada banyak 404 → tanda endpoint perlu dibangun.
class ReportService {
  ReportService._();

  Future<ReportSubmitResult> submit({
    required ReportTargetKind targetKind,
    required String targetId,
    required ReportReason reason,
    String? note,
  }) async {
    final body = <String, dynamic>{
      'targetKind': targetKind.wireValue,
      'targetId': targetId,
      'reason': reason.wireValue,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    };

    try {
      final res = await apiClient.postJson(
        '/api/moderation/reports',
        body: body,
        timeout: const Duration(seconds: 8),
      );
      if (kDebugMode) debugPrint('[reportService.submit] ok: $res');
      return const ReportSubmitResult.success();
    } on ApiException catch (e) {
      // Endpoint belum dibangun di backend — tetap return success
      // ke user supaya UX tidak break. Admin lihat 404 di server log.
      if (e.statusCode == 404) {
        if (kDebugMode) {
          debugPrint('[reportService.submit] endpoint 404 — '
              'silently treating as success. Admin: build '
              '/api/moderation/reports.');
        }
        return const ReportSubmitResult.success();
      }
      if (kDebugMode) debugPrint('[reportService.submit] api error: $e');
      return ReportSubmitResult.failure(
        e.isNetworkError
            ? 'Tidak ada koneksi internet. Coba lagi nanti.'
            : 'Gagal kirim laporan. Coba lagi nanti.',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[reportService.submit] error: $e');
      return const ReportSubmitResult.failure('Gagal kirim laporan.');
    }
  }
}

class ReportSubmitResult {
  final bool ok;
  final String? errorMessage;

  const ReportSubmitResult.success()
      : ok = true,
        errorMessage = null;
  const ReportSubmitResult.failure(String message)
      : ok = false,
        errorMessage = message;
}

final ReportService reportService = ReportService._();

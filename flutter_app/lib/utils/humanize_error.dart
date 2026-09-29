library;

import '../services/api_client.dart';

/// Translate technical error ke pesan user-friendly (Bahasa Indonesia).
///
/// Backend Capacitor biasanya return pesan Indonesia yang sudah ramah via
/// ApiException (mis. "Password salah"). Yang perlu diterjemahkan:
/// network/timeout error mentah (`SocketException: ...`, `Failed host
/// lookup`) yang TIDAK boleh sampai ke user sebagai-teks di momen kritis
/// (checkout, simpan alamat, dsb.).
///
/// [actionPrefix] dipakai untuk fallback terakhir, mis. "Checkout gagal".
String humanizeError(Object error, {String actionPrefix = 'Operasi'}) {
  final raw = error.toString();
  if (error is ApiException) {
    if (error.statusCode == 401) {
      return 'Sesi kamu berakhir. Silakan login ulang lalu coba lagi.';
    }
    if (error.statusCode == 429) {
      return 'Terlalu banyak percobaan. Tunggu beberapa menit lalu coba lagi.';
    }
    if (error.statusCode != null && error.statusCode! >= 500) {
      return 'Server sedang bermasalah. Coba lagi nanti.';
    }
    // 400/404 dst — pesan server biasanya sudah user-friendly.
    return error.message;
  }
  final lower = raw.toLowerCase();
  if (lower.contains('socketexception') ||
      lower.contains('failed host lookup') ||
      lower.contains('connection refused') ||
      lower.contains('network is unreachable') ||
      lower.contains('connection reset') ||
      lower.contains('software caused connection abort')) {
    return 'Tidak bisa connect ke server. Cek koneksi internet kamu.';
  }
  if (lower.contains('timeout') || lower.contains('timed out')) {
    return 'Server butuh waktu lebih lama. Coba lagi sebentar.';
  }
  if (lower.contains('handshakeexception') ||
      lower.contains('certificate_verify_failed')) {
    return 'Koneksi aman ke server gagal. Cek waktu/tanggal HP kamu lalu coba lagi.';
  }
  if (lower.contains('formatexception')) {
    return 'Data dari server tidak valid. Coba lagi atau hubungi bantuan.';
  }
  return '$actionPrefix gagal: $raw';
}

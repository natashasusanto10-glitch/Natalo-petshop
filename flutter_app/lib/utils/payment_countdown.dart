/// Tingkat urgensi hitung mundur batas bayar.
enum PaymentCountdownTone {
  /// Masih longgar — amber.
  normal,

  /// Kurang dari [kPaymentCountdownUrgentThreshold] — merah.
  urgent,

  /// Sudah lewat batas; pesanan akan/sudah dibatalkan otomatis — abu.
  expired,
}

/// Ambang "mendesak". Satu sumber supaya banner di halaman detail dan pill di
/// daftar pesanan tidak pernah menyatakan urgensi yang berbeda untuk pesanan
/// yang sama.
const Duration kPaymentCountdownUrgentThreshold = Duration(hours: 1);

/// Tentukan nada hitung mundur dari sisa waktu.
///
/// Sisa waktu tepat nol dihitung sudah kedaluwarsa: pada detik itu backend
/// sudah boleh membatalkan, jadi menampilkan "bayar dalam 00:00" akan
/// menjanjikan sesuatu yang tidak lagi berlaku.
PaymentCountdownTone paymentCountdownTone(Duration remaining) {
  if (remaining <= Duration.zero) return PaymentCountdownTone.expired;
  if (remaining < kPaymentCountdownUrgentThreshold) {
    return PaymentCountdownTone.urgent;
  }
  return PaymentCountdownTone.normal;
}

/// Aksi auto-hide "chrome" keranjang (baris "N terpilih" atas + voucher bar
/// bawah) untuk satu update scroll drag-driven. Dipisah jadi fungsi murni
/// supaya keputusannya bisa dites tanpa widget.
enum ChromeAction { hide, show, none }

/// [scrollDelta] > 0 = user scroll ke BAWAH (konten naik) → sembunyikan chrome;
/// < 0 = ke ATAS → tampilkan lagi. Ambang [threshold] mencegah thrash dari
/// gerakan mikro.
///
/// Tidak menyembunyikan saat dekat PUNCAK (`pixels <= minExtent + 24`) supaya
/// chrome tetap tampil ketika user melihat kartu keranjang paling atas, dan
/// saat tepat di DASAR (`pixels >= maxExtent - 8`) supaya collapse bar tidak
/// memicu clamp yang menarik konten.
ChromeAction chromeActionForScroll({
  required double scrollDelta,
  required double pixels,
  required double minExtent,
  required double maxExtent,
  required bool currentlyVisible,
  double threshold = 4.0,
}) {
  if (scrollDelta > threshold &&
      currentlyVisible &&
      pixels < maxExtent - 8 &&
      pixels > minExtent + 24) {
    return ChromeAction.hide;
  }
  if (scrollDelta < -threshold && !currentlyVisible) {
    return ChromeAction.show;
  }
  return ChromeAction.none;
}

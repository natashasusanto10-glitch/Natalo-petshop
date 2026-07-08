/// Aksi auto-hide "chrome" keranjang (baris "N terpilih" atas + voucher bar
/// + summary bar bawah yang melipat jadi pil) untuk satu update scroll
/// drag-driven. Dipisah jadi fungsi murni supaya keputusannya bisa dites
/// tanpa widget.
enum ChromeAction { hide, show, none }

/// Semantik condense-pill: gerakan drag ARAH APA PUN (|delta| > [threshold])
/// di tengah list → hide (melipat jadi pil). Reveal TIDAK pernah dipicu
/// gerakan — itu urusan idle timer yang di-arm saat ScrollEnd (= jari sudah
/// diangkat). Satu-satunya show dari sini: mentok PUNCAK cart
/// (`pixels <= minExtent + 24`) → chrome langsung mengembang karena user
/// sedang melihat item cart paling atas.
///
/// Tidak hide saat tepat di DASAR (`pixels >= maxExtent - 8`) supaya
/// collapse bar tidak memicu clamp yang menarik konten.
ChromeAction chromeActionForScroll({
  required double scrollDelta,
  required double pixels,
  required double minExtent,
  required double maxExtent,
  required bool currentlyVisible,
  double threshold = 4.0,
}) {
  if (pixels <= minExtent + 24) {
    return currentlyVisible ? ChromeAction.none : ChromeAction.show;
  }
  if (scrollDelta.abs() > threshold &&
      currentlyVisible &&
      pixels < maxExtent - 8) {
    return ChromeAction.hide;
  }
  return ChromeAction.none;
}

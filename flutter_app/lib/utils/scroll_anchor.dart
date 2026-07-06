/// Hitung offset scroll target yang mempertahankan JARAK-DARI-DASAR konstan
/// setelah konten baru nyelip DI ATAS viewport (mis. kartu item baru masuk
/// ke keranjang saat user lagi lihat grid rekomendasi di bawah).
///
/// `ListView` biasa tidak nge-anchor posisi scroll saat konten disisipkan di
/// atas titik pandang → offset angka tetap sama → semua yang dilihat "loncat
/// ke bawah". Dengan menjaga `maxExtent - pixels` konstan, elemen di bagian
/// bawah (yang jaraknya ke dasar konten tidak berubah) tetap di posisi layar
/// yang sama. Pendekatan ini card-height-agnostic: cukup dari delta maxExtent,
/// tak perlu mengukur tinggi kartu yang masuk.
///
/// Return `null` kalau user berada di puncak list (`oldPixels <= 0`) — di sana
/// item baru muncul di atas memang wajar, jadi biarkan tampilan natural tanpa
/// digeser. Hasil selalu ter-clamp ke rentang `[0, newMaxExtent]`.
double? anchoredOffsetAfterInsert({
  required double oldMaxExtent,
  required double oldPixels,
  required double newMaxExtent,
}) {
  if (oldPixels <= 0) return null;
  final fromBottom = oldMaxExtent - oldPixels;
  final target = newMaxExtent - fromBottom;
  return target.clamp(0.0, newMaxExtent);
}

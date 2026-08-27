import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/services/places_service.dart';

/// Menjaga pembedaan yang hilang di produksi 2026-08-27: layanan pencarian
/// alamat MATI (billing Google nonaktif) tampil identik dengan "alamat
/// tidak ditemukan" — kotak kosong, tanpa pesan, tanpa jejak log.
///
/// CAKUPAN TERBATAS DENGAN SADAR: `placesService` adalah singleton `final`
/// tanpa jalur injeksi, jadi widget test AddressAutocompleteField yang
/// sungguhan akan menembak jaringan. Yang diuji di sini kontrak
/// exception-nya; tampilan pesan di widget perlu device-verify.
void main() {
  test('PlacesUnavailableException membawa pesan siap-tampil', () {
    const e = PlacesUnavailableException(
        'Layanan pencarian alamat sedang tidak tersedia.');
    expect(e.message, contains('tidak tersedia'));
    // toString dipakai kalau ada yang menampilkannya langsung — jangan
    // sampai keluar "Instance of 'PlacesUnavailableException'".
    expect(e.toString(), e.message);
    expect(e.toString(), isNot(contains('Instance of')));
  });

  test('wajib Exception, bukan Error — supaya bisa ditangkap widget', () {
    const e = PlacesUnavailableException('x');
    expect(e, isA<Exception>());
  });
}

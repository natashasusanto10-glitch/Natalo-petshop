import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/brand.dart';

PetBrand b(String name) =>
    PetBrand(name: name, color: const Color(0xFF1E5FBF));

List<String> namesOf(List<PetBrand> brands) =>
    brands.map((x) => x.name).toList();

void main() {
  group('sortBrandsByName', () {
    test('mengurutkan A-Z', () {
      final hasil = sortBrandsByName([b('Whiskas'), b('Acana'), b('Me-O')]);
      expect(namesOf(hasil), ['Acana', 'Me-O', 'Whiskas']);
    });

    test('nama BERHURUF BESAR tidak menyembul ke atas', () {
      // Ini bug yang paling mungkin muncul lagi: `compareTo` mentah
      // membandingkan kode unit, jadi 'C' (67) < 'a' (97) dan "CIAO"
      // akan mendahului "Angels Pet" walau A lebih dulu dari C.
      final hasil = sortBrandsByName([
        b('CIAO / INABA'),
        b('Angels Pet'),
        b('SOBO'),
        b('Royal Canin'),
      ]);
      expect(namesOf(hasil), [
        'Angels Pet',
        'CIAO / INABA',
        'Royal Canin',
        'SOBO',
      ]);
    });

    test('urutan kurasi dari server benar-benar dibuang', () {
      // /api/brands mengirim urutan `position asc` untuk carousel Beranda.
      // Persis 6 brand pertama yang dikirimnya hari ini — kalau fungsi ini
      // diam-diam mengembalikan daftar apa adanya, test ini yang menahan.
      final dariServer = [
        b('Angels Pet'),
        b('Happy Dog'),
        b('Happy Cat'),
        b('Pro Plan'),
        b('Royal Canin'),
        b('Bravery'),
      ];
      expect(namesOf(sortBrandsByName(dariServer)), [
        'Angels Pet',
        'Bravery',
        'Happy Cat',
        'Happy Dog',
        'Pro Plan',
        'Royal Canin',
      ]);
    });

    test('daftar asli TIDAK ikut berubah', () {
      // Pemanggilnya memegang `widget.allBrands` milik parent. Kalau
      // fungsi ini mengurutkan di tempat, urutan kurasi Beranda ikut
      // teracak lewat referensi yang sama.
      final asli = [b('Whiskas'), b('Acana')];
      sortBrandsByName(asli);
      expect(namesOf(asli), ['Whiskas', 'Acana']);
    });

    test('daftar kosong aman', () {
      expect(sortBrandsByName(const []), isEmpty);
    });
  });
}

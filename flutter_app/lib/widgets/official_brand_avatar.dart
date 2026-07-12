import 'package:flutter/material.dart';

/// Logo brand persegi (NL + paw) — dipakai sebagai foto profil untuk akun
/// official "Natalo Petshop" di SEMUA permukaan (feed, likers, komentar,
/// daftar follow, profil). Server sudah null-kan foto asli pemilik untuk
/// akun admin; klien menggantinya dengan logo ini supaya identitas brand
/// konsisten dan nama/foto asli (Natasha) tidak pernah tampil.
const String kOfficialBrandLogoAsset = 'assets/native/icon-only.png';

/// Avatar brand official — logo NL di dalam lingkaran, ukuran bebas.
/// Tidak membawa ring/border sendiri supaya pemanggil bisa menyematkannya
/// ke dekorasi avatar masing-masing (feed/profil/list) tanpa dobel ring.
class OfficialBrandAvatar extends StatelessWidget {
  final double size;

  const OfficialBrandAvatar({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Image.asset(
        kOfficialBrandLogoAsset,
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }
}

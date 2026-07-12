import 'package:flutter/material.dart';

import '../theme/natalo_colors.dart';

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

/// Lencana "verified" akun official — rosette bergerigi emas metalik
/// (gradasi [NataloColors.officialRosette*]) dengan centang knockout yang
/// mengikuti latar. Dipakai SERAGAM di feed, komentar, likers, follow
/// list, dan profil supaya identitas brand konsisten & premium.
///
/// Implementasi: ShaderMask gradasi emas di atas `Icons.verified_rounded`
/// (rosette Material dgn centang transparan) → rosette emas + centang
/// tembus latar. Satu warna emas di semua tempat.
class OfficialVerifiedBadge extends StatelessWidget {
  final double size;

  const OfficialVerifiedBadge({super.key, this.size = 16});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (rect) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          NataloColors.officialRosetteTop,
          NataloColors.officialRosetteMid,
          NataloColors.officialRosetteBottom,
        ],
      ).createShader(rect),
      blendMode: BlendMode.srcIn,
      child: Icon(Icons.verified_rounded, size: size, color: Colors.white),
    );
  }
}

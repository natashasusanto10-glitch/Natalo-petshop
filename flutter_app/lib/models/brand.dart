import 'package:flutter/material.dart';

import '../config/api_config.dart';

class PetBrand {
  final String name;
  final Color color;
  final String? imageAsset;
  // URL logo dari API (kalau ada). Beda dengan imageAsset yang dari local
  // asset/brands/. Network image fetch saat brand di-render dari API.
  final String? logoUrl;
  final String? slug;
  final int productCount;

  const PetBrand({
    required this.name,
    required this.color,
    this.imageAsset,
    this.logoUrl,
    this.slug,
    this.productCount = 0,
  });

  factory PetBrand.fromApiJson(Map<String, dynamic> json) {
    final logoRaw = (json['logoUrl'] ?? '').toString();
    final logo = logoRaw.isEmpty
        ? null
        : (logoRaw.startsWith('http') || logoRaw.startsWith('data:'))
            ? logoRaw
            : _absoluteUrl(logoRaw);
    final countRaw = json['productCount'];
    final count = countRaw is int
        ? countRaw
        : countRaw is num
            ? countRaw.round()
            : int.tryParse(countRaw?.toString() ?? '') ?? 0;
    return PetBrand(
      name: (json['name'] ?? 'Brand').toString(),
      // Color tidak dipakai untuk brand dari API (kita pakai logo).
      // Default brand blue sebagai fallback untuk inisial.
      color: const Color(0xFF1E5FBF),
      logoUrl: logo,
      slug: (json['slug'] ?? '').toString().isEmpty
          ? null
          : json['slug'].toString(),
      productCount: count,
    );
  }
}

/// Salinan `brands` urut A-Z, tanpa mengubah daftar aslinya.
///
/// Dipakai daftar brand yang DIPINDAI MATA untuk mencari satu nama —
/// mis. Filter di halaman Produk (65 brand). Jangan dipakai untuk
/// carousel "Brand Favorit" di Beranda: di sana brand tampil sebagai
/// logo dan urutannya kurasi (`Brand.position` di server), disengaja.
///
/// GOTCHA: `compareTo` pada String membandingkan kode unit, jadi SEMUA
/// huruf besar mendahului huruf kecil — "CIAO / INABA" akan menyembul
/// di atas "Angels Pet". Karena itu dibandingkan dalam huruf kecil.
List<PetBrand> sortBrandsByName(List<PetBrand> brands) {
  return List<PetBrand>.from(brands)
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}

String _absoluteUrl(String url) {
  if (url.isEmpty || url.startsWith('http')) return url;
  final base = Uri.parse(ApiConfig.baseUrl);
  final origin =
      '${base.scheme}://${base.host}${base.hasPort ? ':${base.port}' : ''}';
  return url.startsWith('/') ? '$origin$url' : '$origin/$url';
}

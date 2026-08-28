import '../models/product.dart';

List<String> productCarouselImages(Product product) {
  final candidates = <String>[
    product.imageUrl.trim(),
    ...product.gallery.map((url) => url.trim()),
    ...product.variants.map((variant) => variant.imageUrl?.trim() ?? ''),
  ];
  final seen = <String>{};
  return candidates
      .where((url) => url.isNotEmpty && seen.add(url))
      .toList(growable: false);
}

/// Foto per opsi varian, untuk thumbnail di chip picker varian.
///
/// HANYA produk beratribut TUNGGAL yang dilayani. Pada produk dua atribut
/// (mis. Rasa × Ukuran) satu opsi seperti "1KG" mencakup beberapa varian
/// sekaligus, jadi tidak ada satu foto yang mewakilinya — memaksakan foto
/// varian pertama akan menyesatkan ("1KG" menampilkan foto Tuna padahal
/// user mau Salmon). Map kosong = chip tetap tampil sebagai teks.
Map<String, String> variantOptionThumbnails(Product product) {
  if (product.variantAttrs.length != 1) return const {};
  final thumbnails = <String, String>{};
  for (final option in product.variantAttrs.first.options) {
    for (final variant in product.variants) {
      if (!variant.isActive) continue;
      if (!variant.optionIds.contains(option.id)) continue;
      final url = variant.imageUrl?.trim() ?? '';
      // Varian tanpa foto dilewati, bukan menghentikan pencarian — varian
      // lain dengan opsi yang sama masih bisa menyumbang foto.
      if (url.isEmpty) continue;
      thumbnails[option.id] = url;
      break;
    }
  }
  return thumbnails;
}

int productMediaSlideIndex({
  required List<String> images,
  required String imageUrl,
  required bool hasVideo,
}) {
  final imageIndex = images.indexOf(imageUrl.trim());
  if (imageIndex < 0) return -1;
  return imageIndex + (hasVideo ? 1 : 0);
}

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

int productMediaSlideIndex({
  required List<String> images,
  required String imageUrl,
  required bool hasVideo,
}) {
  final imageIndex = images.indexOf(imageUrl.trim());
  if (imageIndex < 0) return -1;
  return imageIndex + (hasVideo ? 1 : 0);
}

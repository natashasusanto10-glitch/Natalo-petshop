import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/product.dart';
import 'package:natalo_petshop_flutter/utils/product_media.dart';

Product _product({
  required String imageUrl,
  List<String> gallery = const [],
  List<ProductVariant> variants = const [],
}) {
  return Product(
    id: 'product-1',
    slug: 'fleatick-plus',
    title: 'Fleatick Plus',
    imageUrl: imageUrl,
    gallery: gallery,
    variants: variants,
    hasVariants: variants.isNotEmpty,
    price: 14900,
    rating: 5,
    reviewCount: 6,
    category: 'Obat Hewan',
    brand: 'Alliance',
    stock: 10,
    weightGram: 10,
    description: 'Obat kutu hewan.',
  );
}

void main() {
  test('carousel keeps main and gallery order, then appends variant images',
      () {
    final product = _product(
      imageUrl: 'main.jpg',
      gallery: const ['main.jpg', 'gallery.jpg'],
      variants: const [
        ProductVariant(
          id: 'variant-1',
          price: 14900,
          stock: 5,
          imageUrl: 'variant.jpg',
        ),
        ProductVariant(
          id: 'variant-2',
          price: 15900,
          stock: 5,
          imageUrl: 'gallery.jpg',
        ),
      ],
    );

    expect(
      productCarouselImages(product),
      ['main.jpg', 'gallery.jpg', 'variant.jpg'],
    );
  });

  test('selected variant image stays after video in slide ordering', () {
    final images = ['main.jpg', 'variant.jpg'];

    expect(
      productMediaSlideIndex(
        images: images,
        imageUrl: 'variant.jpg',
        hasVideo: true,
      ),
      2,
    );
    expect(
      productMediaSlideIndex(
        images: images,
        imageUrl: 'variant.jpg',
        hasVideo: false,
      ),
      1,
    );
  });
}

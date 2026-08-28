import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/product.dart';
import 'package:natalo_petshop_flutter/utils/product_media.dart';

Product _product({
  List<ProductVariantAttribute> attrs = const [],
  List<ProductVariant> variants = const [],
}) {
  return Product(
    id: 'product-1',
    slug: 'catto-mother-kitten',
    title: 'Catto Mother & Kitten',
    imageUrl: 'main.jpg',
    variants: variants,
    variantAttrs: attrs,
    hasVariants: variants.isNotEmpty,
    price: 55000,
    rating: 5,
    reviewCount: 6,
    category: 'Makanan Kucing',
    brand: 'Catto',
    stock: 10,
    weightGram: 400,
    description: 'Makanan kucing.',
  );
}

const _rasa = ProductVariantAttribute(
  id: 'attr-rasa',
  name: 'Rasa',
  options: [
    VariantOption(id: 'opt-tuna', value: 'Real Tuna'),
    VariantOption(id: 'opt-salmon', value: 'Real Salmon'),
  ],
);

const _ukuran = ProductVariantAttribute(
  id: 'attr-ukuran',
  name: 'Ukuran',
  options: [
    VariantOption(id: 'opt-400', value: '400GR'),
    VariantOption(id: 'opt-1kg', value: '1KG'),
  ],
);

void main() {
  test('atribut tunggal: tiap opsi dapat foto varian yang cocok', () {
    final product = _product(
      attrs: const [_rasa],
      variants: const [
        ProductVariant(
          id: 'v-tuna',
          price: 55000,
          stock: 5,
          imageUrl: 'tuna.jpg',
          optionIds: ['opt-tuna'],
        ),
        ProductVariant(
          id: 'v-salmon',
          price: 55000,
          stock: 5,
          imageUrl: 'salmon.jpg',
          optionIds: ['opt-salmon'],
        ),
      ],
    );

    expect(variantOptionThumbnails(product), {
      'opt-tuna': 'tuna.jpg',
      'opt-salmon': 'salmon.jpg',
    });
  });

  test('dua atribut: kosong, karena satu opsi mencakup banyak varian', () {
    // "1KG" mencakup Tuna 1KG DAN Salmon 1KG — tidak ada satu foto yang
    // mewakilinya, jadi chip harus tetap teks daripada menampilkan foto
    // rasa yang salah.
    final product = _product(
      attrs: const [_rasa, _ukuran],
      variants: const [
        ProductVariant(
          id: 'v-tuna-400',
          price: 55000,
          stock: 5,
          imageUrl: 'tuna-400.jpg',
          optionIds: ['opt-tuna', 'opt-400'],
        ),
        ProductVariant(
          id: 'v-salmon-1kg',
          price: 130000,
          stock: 5,
          imageUrl: 'salmon-1kg.jpg',
          optionIds: ['opt-salmon', 'opt-1kg'],
        ),
      ],
    );

    expect(variantOptionThumbnails(product), isEmpty);
  });

  test('varian tanpa foto dilewati, bukan bikin entri kosong', () {
    final product = _product(
      attrs: const [_rasa],
      variants: const [
        ProductVariant(
          id: 'v-tuna',
          price: 55000,
          stock: 5,
          optionIds: ['opt-tuna'],
        ),
        ProductVariant(
          id: 'v-salmon',
          price: 55000,
          stock: 5,
          imageUrl: 'salmon.jpg',
          optionIds: ['opt-salmon'],
        ),
      ],
    );

    expect(variantOptionThumbnails(product), {'opt-salmon': 'salmon.jpg'});
  });

  test('varian nonaktif tidak menyumbang foto', () {
    final product = _product(
      attrs: const [_rasa],
      variants: const [
        ProductVariant(
          id: 'v-tuna-mati',
          price: 55000,
          stock: 0,
          imageUrl: 'tuna-lama.jpg',
          optionIds: ['opt-tuna'],
          isActive: false,
        ),
        ProductVariant(
          id: 'v-tuna',
          price: 55000,
          stock: 5,
          imageUrl: 'tuna-baru.jpg',
          optionIds: ['opt-tuna'],
        ),
      ],
    );

    expect(variantOptionThumbnails(product)['opt-tuna'], 'tuna-baru.jpg');
  });

  test('produk tanpa varian: kosong', () {
    expect(variantOptionThumbnails(_product()), isEmpty);
  });
}

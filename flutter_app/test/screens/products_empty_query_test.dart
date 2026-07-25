import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/product.dart';

/// Keputusan 15 spec Belanja: "Cari di Natalo"/"Cari serupa" yang 0 hasil
/// tidak boleh mendarat di grid kosong tanpa penjelasan. ProductsScreen sudah
/// punya _EmptyProductsState; test ini menjaga kontrak argumennya.
void main() {
  test('ProductCatalogArgs membawa initialQuery ke layar Produk', () {
    const args = ProductCatalogArgs(initialQuery: 'Bravecto');
    expect(args.initialQuery, 'Bravecto');
    expect(args.selectedBrand, isNull);
    expect(args.discountOnly, isFalse);
  });

  test('ProductCatalogArgs membawa initialCategory utk Cari serupa', () {
    const args = ProductCatalogArgs(initialCategory: 'Obat & Suplemen');
    expect(args.initialCategory, 'Obat & Suplemen');
  });
}

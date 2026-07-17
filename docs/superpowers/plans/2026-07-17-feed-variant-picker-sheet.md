# Variant Picker In-Sheet (Postingan video) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tap ikon keranjang pada produk bervarian di sheet Links (video Postingan) membuka sheet pilih-varian di atas sheet Links — bukan navigasi keluar ke halaman detail — lalu add-to-cart menutup kedua sheet dan kembali ke video.

**Architecture:** Ekstrak mesin variant-picker yang sudah ada di `cart_screen.dart` (`_CartVariantPickerSheet`) menjadi widget publik berbasis `Product` (`ProductVariantPickerSheet`) dengan seam fetcher untuk test. Cart dan feed sama-sama memakainya. Logika add-to-cart feed dipindah ke fungsi publik kecil `addFeedLinkToCart` agar testable tanpa me-mount `FeedVideoPostView`.

**Tech Stack:** Flutter, Dart, `showModalBottomSheet`, `FractionallySizedBox`, widget test (`flutter_test`).

## Global Constraints

- **Tidak ada dependency baru.** Hanya widget internal.
- **Ekstraksi faithful:** perilaku & tampilan variant sheet di halaman Cart TIDAK berubah untuk user (tombol tetap "Simpan" hijau, pre-select varian existing, swap qty sama). Hanya kode internalnya yang pindah ke widget bersama.
- **Error state text-only, TANPA tombol retry** (mengikuti pola `_CartVariantPickerSheet` existing). TIDAK ada fallback diam ke alur navigasi lama.
- **Path non-varian di feed TIDAK berubah:** `cartStore.addProduct` langsung + toast; sheet Links TETAP terbuka (user bisa tambah beberapa produk berturut-turut).
- **Pop sheet Links hanya pada path varian** setelah confirm add-to-cart.
- **Logika pause/resume video existing tidak disentuh** (`_pauseForProductSheet`/`_resumeAfterProductSheet` + `onOpened`/`onClosed`). Sheet varian numpang siklus hidup sheet Links (parent tetap terbuka secara logis).
- **Tap foto/nama produk (`onOpenProduct`) tetap navigasi ke halaman detail penuh** — tidak berubah.
- `productService` adalah global non-injectable → widget/fungsi baru menerima seam `ProductFetcher? productFetcher` (default null → global) untuk test.
- Warna: `_brandBlue = NataloColors.nataloBlue`, `_shippingGreen = Color(0xFF12A66A)`, `_discountRed = Color(0xFFE53958)` (nilai sama seperti di `cart_screen.dart`).

## File Structure

- **Create** `flutter_app/lib/widgets/product_variant_picker_sheet.dart` — widget publik `ProductVariantPickerSheet` + `ProductVariantPickResult` + `typedef ProductFetcher`. Satu tanggung jawab: pilih varian dari sebuah produk (by slug), kembalikan `(product, variant)`.
- **Create** `flutter_app/lib/features/feed/widgets/feed_link_cart_actions.dart` — fungsi publik `addFeedLinkToCart(...)`. Satu tanggung jawab: aksi add-to-cart dari sebuah `FeedProductLink` (guard unavailable, cabang varian→sheet, non-varian→add langsung).
- **Modify** `flutter_app/lib/screens/cart_screen.dart` — `_openVariantSheet` pakai widget baru; hapus `_CartVariantPickerSheet`, `_CartVariantPickerSheetState`, `_CartVariantPickResult`, `_CartVariantSummary`.
- **Modify** `flutter_app/lib/features/feed/widgets/feed_video_post_view.dart` — `_addFeedLinkToCart` jadi delegasi ke `addFeedLinkToCart`.
- **Create** tests: `flutter_app/test/widgets/product_variant_picker_sheet_test.dart`, `flutter_app/test/features/feed/widgets/feed_link_cart_actions_test.dart`.

---

## Task 1: Widget bersama `ProductVariantPickerSheet`

**Files:**
- Create: `flutter_app/lib/widgets/product_variant_picker_sheet.dart`
- Test: `flutter_app/test/widgets/product_variant_picker_sheet_test.dart`

**Interfaces:**
- Consumes: `productService.fetchProductBySlug` (dari `../services/product_service.dart`), `cartVariantOptionLabel` + `effectiveCartVariantPrice` (dari `../state/cart_store.dart`), `Product`/`ProductVariant`/`ProductVariantAttribute`/`VariantOption` (dari `../models/product.dart`), `AppProductImage`, `formatRupiah`, `AppHaptics`, `NataloColors`.
- Produces (dipakai Task 2 & 3):
  - `typedef ProductFetcher = Future<Product?> Function(String slug);`
  - `class ProductVariantPickResult { final Product product; final ProductVariant variant; const ProductVariantPickResult({required this.product, required this.variant}); }`
  - `class ProductVariantPickerSheet extends StatefulWidget` dengan constructor param `{Key? key, required String productSlug, ProductVariant? preselectedVariant, required String confirmLabel, required Color confirmColor, ProductFetcher? productFetcher}`.
  - `static Future<ProductVariantPickResult?> ProductVariantPickerSheet.show(BuildContext context, {required String productSlug, ProductVariant? preselectedVariant, required String confirmLabel, required Color confirmColor, ProductFetcher? productFetcher})` — memakai `showModalBottomSheet<ProductVariantPickResult>(isScrollControlled: true, backgroundColor: Colors.transparent, builder: ...)`.

- [ ] **Step 1: Tulis test yang gagal**

Buat `flutter_app/test/widgets/product_variant_picker_sheet_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/product.dart';
import 'package:natalo_petshop_flutter/widgets/product_variant_picker_sheet.dart';

Product _variantProduct() {
  const size = ProductVariantAttribute(
    id: 'attr-size',
    name: 'Ukuran',
    options: [
      VariantOption(id: 'o-1kg', value: '1kg'),
      VariantOption(id: 'o-3kg', value: '3kg'),
    ],
  );
  const flavor = ProductVariantAttribute(
    id: 'attr-flavor',
    name: 'Rasa',
    options: [
      VariantOption(id: 'o-ayam', value: 'Ayam'),
      VariantOption(id: 'o-salmon', value: 'Salmon'),
    ],
  );
  return Product(
    id: 'p1',
    slug: 'makanan-kucing',
    title: 'Makanan Kucing',
    category: 'Makanan',
    brand: 'Natalo',
    imageUrl: '',
    price: 100000,
    rating: 0,
    reviewCount: 0,
    stock: 0,
    description: '',
    hasVariants: true,
    variantAttrs: const [size, flavor],
    variants: const [
      ProductVariant(
        id: 'v-1kg-ayam', price: 90000, stock: 5,
        optionIds: ['o-1kg', 'o-ayam'],
      ),
      ProductVariant(
        id: 'v-3kg-ayam', price: 150000, stock: 3,
        optionIds: ['o-3kg', 'o-ayam'],
      ),
      // Salmon hanya tersedia untuk 1kg → 3kg+Salmon tidak ada varian.
      ProductVariant(
        id: 'v-1kg-salmon', price: 95000, stock: 2,
        optionIds: ['o-1kg', 'o-salmon'],
      ),
    ],
  );
}

Future<ProductVariantPickResult?> _openSheet(
  WidgetTester tester, {
  required ProductFetcher fetcher,
  ProductVariant? preselected,
}) async {
  ProductVariantPickResult? result;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () async {
              result = await ProductVariantPickerSheet.show(
                context,
                productSlug: 'makanan-kucing',
                preselectedVariant: preselected,
                confirmLabel: 'Tambah ke Keranjang',
                confirmColor: Colors.blue,
                productFetcher: fetcher,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  // Bounded pump (AppProductImage shimmer tak pernah settle → jangan pumpAndSettle).
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
  return result;
}

void main() {
  testWidgets('pilih kombinasi lengkap → tombol enable → confirm balikin varian benar',
      (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final product = _variantProduct();
    await _openSheet(tester, fetcher: (_) async => product);

    // Sheet terbuka, header terlihat.
    expect(find.text('Variasi Produk'), findsOneWidget);

    // Tombol confirm awalnya disabled (belum ada kombinasi lengkap).
    final buttonBefore = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Tambah ke Keranjang'),
    );
    expect(buttonBefore.onPressed, isNull);

    // Pilih 1kg + Ayam.
    await tester.tap(find.text('1kg'));
    await tester.pump();
    await tester.tap(find.text('Ayam'));
    await tester.pump();

    final buttonAfter = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Tambah ke Keranjang'),
    );
    expect(buttonAfter.onPressed, isNotNull);
  });

  testWidgets('opsi tanpa kombinasi valid ter-disable', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final product = _variantProduct();
    await _openSheet(tester, fetcher: (_) async => product);

    // Pilih 3kg dulu → Salmon jadi tak tersedia (tak ada varian 3kg+Salmon).
    await tester.tap(find.text('3kg'));
    await tester.pump();
    await tester.tap(find.text('Salmon'));
    await tester.pump();

    // Salmon tak boleh terpilih → kombinasi tetap tak lengkap/invalid → tombol disabled.
    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Tambah ke Keranjang'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('fetch gagal → tampil teks error, tanpa tombol confirm', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openSheet(tester, fetcher: (_) async => null);

    expect(find.text('Produk tidak ditemukan.'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Tambah ke Keranjang'), findsNothing);
  });
}
```

- [ ] **Step 2: Jalankan test — pastikan GAGAL (belum ada file widget)**

Run: `flutter test test/widgets/product_variant_picker_sheet_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'natalo_petshop_flutter/widgets/product_variant_picker_sheet.dart'` (file belum ada).

**Catatan model (sudah diverifikasi saat menulis plan):** kelasnya `ProductVariantAttribute` (field `options: List<VariantOption>`), `VariantOption` (field `id`, `value`), `ProductVariant` (field `id`, `price`, `stock`, `optionIds`, `isActive`). `Product` WAJIB isi field required: `id, slug, title, category, brand, imageUrl, price, rating, reviewCount, stock, description` (fixture di atas sudah lengkap). Kalau ada beda saat kompil, sesuaikan test fixture — JANGAN ubah model.

- [ ] **Step 3: Tulis widget `product_variant_picker_sheet.dart`**

Buat `flutter_app/lib/widgets/product_variant_picker_sheet.dart`. Ini ekstraksi 1:1 dari `_CartVariantPickerSheet` (cart_screen.dart:1804-2244) dengan perubahan: API `productSlug`+`preselectedVariant` (bukan `CartItem`), `confirmLabel`+`confirmColor` (bukan hardcoded "Simpan"/hijau), seam `productFetcher`, dan static `show`. Summary (`_VariantSummary`) juga di-inline ke file ini.

```dart
import 'package:flutter/material.dart';

import '../models/product.dart';
import '../services/product_service.dart';
import '../state/cart_store.dart';
import '../theme/natalo_colors.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import 'app_product_image.dart';

const _brandBlue = NataloColors.nataloBlue;
const _discountRed = Color(0xFFE53958);

typedef ProductFetcher = Future<Product?> Function(String slug);

/// Hasil pilih varian: produk penuh + varian terpilih.
class ProductVariantPickResult {
  final Product product;
  final ProductVariant variant;

  const ProductVariantPickResult({
    required this.product,
    required this.variant,
  });
}

/// Bottom sheet pilih varian sebuah produk (fetch penuh by slug). Dipakai
/// halaman Cart (ganti varian) dan sheet Links feed (tambah ke keranjang
/// produk bervarian tanpa keluar dari video).
class ProductVariantPickerSheet extends StatefulWidget {
  final String productSlug;
  final ProductVariant? preselectedVariant;
  final String confirmLabel;
  final Color confirmColor;
  final ProductFetcher? productFetcher;

  const ProductVariantPickerSheet({
    super.key,
    required this.productSlug,
    this.preselectedVariant,
    required this.confirmLabel,
    required this.confirmColor,
    this.productFetcher,
  });

  static Future<ProductVariantPickResult?> show(
    BuildContext context, {
    required String productSlug,
    ProductVariant? preselectedVariant,
    required String confirmLabel,
    required Color confirmColor,
    ProductFetcher? productFetcher,
  }) {
    return showModalBottomSheet<ProductVariantPickResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => ProductVariantPickerSheet(
        productSlug: productSlug,
        preselectedVariant: preselectedVariant,
        confirmLabel: confirmLabel,
        confirmColor: confirmColor,
        productFetcher: productFetcher,
      ),
    );
  }

  @override
  State<ProductVariantPickerSheet> createState() =>
      _ProductVariantPickerSheetState();
}

class _ProductVariantPickerSheetState extends State<ProductVariantPickerSheet> {
  Product? _fullProduct;
  bool _loading = true;
  String? _error;
  final Map<String, String> _selectedOptions = {};

  @override
  void initState() {
    super.initState();
    _loadFullProduct();
  }

  Future<void> _loadFullProduct() async {
    try {
      final fetch = widget.productFetcher ?? productService.fetchProductBySlug;
      final result = await fetch(widget.productSlug);
      if (!mounted) return;
      if (result == null) {
        setState(() {
          _loading = false;
          _error = 'Produk tidak ditemukan.';
        });
        return;
      }
      final preselect = widget.preselectedVariant;
      if (preselect != null) {
        // Cari varian yang cocok id-nya di data penuh (untuk optionIds lengkap).
        ProductVariant current = preselect;
        for (final variant in result.variants) {
          if (variant.id == preselect.id) {
            current = variant;
            break;
          }
        }
        for (final attr in result.variantAttrs) {
          for (final opt in attr.options) {
            if (current.optionIds.contains(opt.id)) {
              _selectedOptions[attr.id] = opt.id;
              break;
            }
          }
        }
      }
      setState(() {
        _fullProduct = result;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Gagal memuat varian. Coba lagi.';
      });
    }
  }

  ProductVariant? get _matchedVariant {
    final product = _fullProduct;
    if (product == null) return null;
    if (_selectedOptions.length < product.variantAttrs.length) return null;
    for (final variant in product.variants) {
      if (!variant.isActive) continue;
      final matches = product.variantAttrs.every((attr) {
        final selectedOpt = _selectedOptions[attr.id];
        return selectedOpt != null && variant.optionIds.contains(selectedOpt);
      });
      if (matches) return variant;
    }
    return null;
  }

  bool _isOptionAvailable(String attrId, String optionId) {
    final product = _fullProduct;
    if (product == null) return false;
    final otherSelected = Map<String, String>.from(_selectedOptions);
    otherSelected.remove(attrId);
    for (final variant in product.variants) {
      if (!variant.isActive) continue;
      if (!variant.optionIds.contains(optionId)) continue;
      final matchesOthers = otherSelected.entries
          .every((entry) => variant.optionIds.contains(entry.value));
      if (matchesOthers) return true;
    }
    return false;
  }

  void _onSelect(String attrId, String optionId) {
    AppHaptics.selection();
    setState(() {
      _selectedOptions[attrId] = optionId;
    });
  }

  void _confirm() {
    final variant = _matchedVariant;
    final product = _fullProduct;
    if (variant == null || product == null) return;
    AppHaptics.tap();
    Navigator.pop(
      context,
      ProductVariantPickResult(product: product, variant: variant),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final variant = _matchedVariant;
    return FractionallySizedBox(
      heightFactor: 0.78,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Container(
          color: cs.surface,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Variasi Produk',
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      color: cs.onSurfaceVariant,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: cs.outlineVariant),
              Expanded(child: _buildBody()),
              if (_fullProduct != null && _error == null)
                SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      border: Border(top: BorderSide(color: cs.outlineVariant)),
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: variant != null ? _confirm : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.confirmColor,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(0xFFCBD5E1),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        child: Text(widget.confirmLabel),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final cs = Theme.of(context).colorScheme;
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }
    if (_error != null || _fullProduct == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            _error ?? 'Produk tidak ditemukan.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
    final product = _fullProduct!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      children: [
        _VariantSummary(product: product, variant: _matchedVariant),
        const SizedBox(height: 22),
        for (final attr in product.variantAttrs) ...[
          Text(
            attr.name,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: attr.options.map((opt) {
              final selected = _selectedOptions[attr.id] == opt.id;
              final available = _isOptionAvailable(attr.id, opt.id);
              return GestureDetector(
                onTap: available ? () => _onSelect(attr.id, opt.id) : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? _brandBlue.withValues(alpha: 0.10)
                        : available
                            ? cs.surface
                            : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: selected ? _brandBlue : cs.outlineVariant,
                      width: selected ? 1.4 : 1,
                    ),
                  ),
                  child: Text(
                    opt.value,
                    style: TextStyle(
                      color: selected ? _brandBlue : cs.onSurfaceVariant,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
        ],
      ],
    );
  }
}

class _VariantSummary extends StatelessWidget {
  final Product product;
  final ProductVariant? variant;

  const _VariantSummary({required this.product, required this.variant});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selectedVariant = variant;
    final selectedVariantLabel = selectedVariant == null
        ? null
        : cartVariantOptionLabel(product, selectedVariant);
    final imageUrl = selectedVariant?.imageUrl?.trim().isNotEmpty == true
        ? selectedVariant!.imageUrl!
        : product.imageUrl;
    final displayPrice = selectedVariant == null
        ? product.finalPrice.round()
        : effectiveCartVariantPrice(product, selectedVariant);
    final originalPrice = selectedVariant?.price ?? product.price.round();
    final hasDiscount = originalPrice > displayPrice;
    final discountPercent = hasDiscount && originalPrice > 0
        ? (((originalPrice - displayPrice) / originalPrice) * 100).round()
        : 0;
    final stock = selectedVariant?.stock;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 92,
          height: 92,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(10),
          ),
          clipBehavior: Clip.antiAlias,
          child: AppProductImage(imageUrl: imageUrl, fit: BoxFit.cover),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (selectedVariantLabel != null &&
                  selectedVariantLabel.isNotEmpty) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    selectedVariantLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Text(
                formatRupiah(displayPrice.toDouble()),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (hasDiscount) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        formatRupiah(originalPrice.toDouble()),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$discountPercent%',
                      style: const TextStyle(
                        color: _discountRed,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 6),
              Text(
                stock == null ? 'Pilih varian' : 'Stok: $stock',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
```

**Catatan implementer:** verifikasi setiap simbol yang di-import benar-benar ada dengan signature yang dipakai: `formatRupiah` di `utils/formatters.dart`, `AppHaptics.selection`/`AppHaptics.tap` di `utils/haptics.dart`, `NataloColors.nataloBlue`, `AppProductImage({required imageUrl, fit})`, `cartVariantOptionLabel`/`effectiveCartVariantPrice` di `state/cart_store.dart`, dan field `Product`/`ProductVariant` (`finalPrice`, `variantAttrs`, `variants`, `isActive`, `optionIds`, `imageUrl`, `price`, `stock`). Jika ada beda kecil (mis. `withValues` vs `withOpacity`), samakan dengan yang sudah dipakai di `cart_screen.dart` (referensi asli — kode di atas disalin dari sana).

- [ ] **Step 4: Jalankan test — pastikan LULUS**

Run: `flutter test test/widgets/product_variant_picker_sheet_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Analyze**

Run: `flutter analyze lib/widgets/product_variant_picker_sheet.dart test/widgets/product_variant_picker_sheet_test.dart`
Expected: No issues found.

- [ ] **Step 6: Commit**

```bash
git add flutter_app/lib/widgets/product_variant_picker_sheet.dart flutter_app/test/widgets/product_variant_picker_sheet_test.dart
git commit -m "feat(variant): widget bersama ProductVariantPickerSheet (ekstrak dari cart)"
```

---

## Task 2: Refactor `cart_screen.dart` pakai widget bersama

**Files:**
- Modify: `flutter_app/lib/screens/cart_screen.dart` (`_openVariantSheet` ~1445-1466; hapus `_CartVariantPickResult` ~1804-1812, `_CartVariantPickerSheet`+state ~1814-2116, `_CartVariantSummary` ~2118-2244)

**Interfaces:**
- Consumes dari Task 1: `ProductVariantPickerSheet.show`, `ProductVariantPickResult`.
- Produces: tidak ada API baru; perilaku cart tetap.

- [ ] **Step 1: Tambah import widget baru**

Di `cart_screen.dart` bagian import, tambah:
```dart
import '../widgets/product_variant_picker_sheet.dart';
```

- [ ] **Step 2: Ganti isi `_openVariantSheet`**

Ganti body method `_openVariantSheet` (cart_screen.dart:1445-1466) menjadi:
```dart
  Future<void> _openVariantSheet(BuildContext context) async {
    AppHaptics.tap();
    final picked = await ProductVariantPickerSheet.show(
      context,
      productSlug: item.product.slug,
      preselectedVariant: item.variant,
      confirmLabel: 'Simpan',
      confirmColor: _shippingGreen,
    );
    if (picked == null) return;
    await cartStore.remove(item.key);
    await cartStore.addProduct(
      picked.product,
      variant: picked.variant,
      variantLabel: _composeVariantLabel(picked.product, picked.variant),
      quantity: item.quantity,
    );
  }
```

- [ ] **Step 3: Hapus kelas privat lama**

Hapus seluruh definisi berikut dari `cart_screen.dart` (sudah pindah ke widget bersama): `class _CartVariantPickResult` (~1804-1812), `class _CartVariantPickerSheet` + `_CartVariantPickerSheetState` (~1814-2116), `class _CartVariantSummary` (~2118-2244).

- [ ] **Step 4: Analyze — pastikan tak ada simbol menggantung**

Run: `flutter analyze lib/screens/cart_screen.dart`
Expected: No issues found. (Kalau ada "unused import" untuk simbol yang tadinya cuma dipakai kelas terhapus — mis. `AppProductImage` masih dipakai bagian lain? cek — hapus import yang benar-benar tak terpakai lagi. JANGAN hapus import yang masih dipakai.)

- [ ] **Step 5: Jalankan test cart existing**

Run: `flutter test test/cart_screen_anchor_test.dart`
Expected: PASS (perilaku cart tak berubah; ini regression guard bahwa refactor tak merusak kompilasi/behavior halaman cart).

- [ ] **Step 6: Commit**

```bash
git add flutter_app/lib/screens/cart_screen.dart
git commit -m "refactor(cart): pakai ProductVariantPickerSheet bersama, hapus sheet varian privat"
```

---

## Task 3: Fungsi `addFeedLinkToCart` + wiring feed video view

**Files:**
- Create: `flutter_app/lib/features/feed/widgets/feed_link_cart_actions.dart`
- Modify: `flutter_app/lib/features/feed/widgets/feed_video_post_view.dart` (`_addFeedLinkToCart` ~2770-2790 → delegasi)
- Test: `flutter_app/test/features/feed/widgets/feed_link_cart_actions_test.dart`

**Interfaces:**
- Consumes: `ProductVariantPickerSheet.show` + `ProductFetcher` (Task 1), `feedPostProductFromFeedLink` (`feed_post_shared_widgets.dart`), `cartStore` (`state/cart_store.dart`), `cartVariantOptionLabel` (`state/cart_store.dart`), `AppToast` (`widgets/app_toast.dart`), `FeedProductLink` (`models/feed_post.dart`), `NataloColors`.
- Produces (dipakai feed view):
  - `Future<void> addFeedLinkToCart(BuildContext context, FeedProductLink link, {int quantity = 1, ProductFetcher? productFetcher})`.

- [ ] **Step 1: Tulis test yang gagal**

Buat `flutter_app/test/features/feed/widgets/feed_link_cart_actions_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_link_cart_actions.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/models/product.dart';
import 'package:natalo_petshop_flutter/state/cart_store.dart';

FeedProductLink _link({required bool hasVariants}) => FeedProductLink(
      id: 'p1',
      slug: 'makanan-kucing',
      name: 'Makanan Kucing',
      price: 100000,
      stock: 5,
      hasVariants: hasVariants,
    );

Product _variantProduct() {
  const size = ProductVariantAttribute(
    id: 'attr-size',
    name: 'Ukuran',
    options: [VariantOption(id: 'o-1kg', value: '1kg')],
  );
  return Product(
    id: 'p1',
    slug: 'makanan-kucing',
    title: 'Makanan Kucing',
    category: 'Makanan',
    brand: 'Natalo',
    imageUrl: '',
    price: 100000,
    rating: 0,
    reviewCount: 0,
    stock: 0,
    description: '',
    hasVariants: true,
    variantAttrs: const [size],
    variants: const [
      ProductVariant(
        id: 'v-1kg', price: 90000, stock: 5, optionIds: ['o-1kg'],
      ),
    ],
  );
}

class _RecordingObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushed = [];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
    super.didPush(route, previousRoute);
  }
}

void main() {
  setUp(() => cartStore.clear());

  testWidgets('produk NON-varian → langsung masuk cart, tak buka sheet',
      (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => addFeedLinkToCart(
                context,
                _link(hasVariants: false),
                productFetcher: (_) async => _variantProduct(),
              ),
              child: const Text('add'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('add'));
    await tester.pump();

    expect(find.text('Variasi Produk'), findsNothing);
    expect(cartStore.items.length, 1);
  });

  testWidgets('produk BERVARIAN → buka sheet varian (bukan navigasi)',
      (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final observer = _RecordingObserver();
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [observer],
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => addFeedLinkToCart(
                context,
                _link(hasVariants: true),
                productFetcher: (_) async => _variantProduct(),
              ),
              child: const Text('add'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('add'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }

    // Sheet varian terbuka.
    expect(find.text('Variasi Produk'), findsOneWidget);
    // Tidak ada push ke named route '/product-detail'.
    expect(
      observer.pushed.any((r) => r.settings.name == '/product-detail'),
      isFalse,
    );
    // Belum ada item cart (belum confirm varian).
    expect(cartStore.items, isEmpty);
  });
}
```

- [ ] **Step 2: Jalankan test — pastikan GAGAL (file belum ada)**

Run: `flutter test test/features/feed/widgets/feed_link_cart_actions_test.dart`
Expected: FAIL — package `feed_link_cart_actions.dart` belum ada.

**Catatan:** verifikasi `cartStore.clear()` dan `cartStore.items` benar ada di `state/cart_store.dart` (kalau nama beda, mis. `cartStore.itemsList` atau perlu `SharedPreferences.setMockInitialValues({})` sebelum akses — cek `cart_screen_anchor_test.dart` untuk pola setup cartStore yang sudah dipakai, dan ikuti pola itu). Sesuaikan test setup, bukan produksi.

- [ ] **Step 3: Tulis `feed_link_cart_actions.dart`**

```dart
import 'package:flutter/material.dart';

import '../../../models/feed_post.dart';
import '../../../state/cart_store.dart';
import '../../../theme/natalo_colors.dart';
import '../../../widgets/app_toast.dart';
import '../../../widgets/product_variant_picker_sheet.dart';
import 'feed_post_shared_widgets.dart';

/// Aksi tap ikon keranjang pada sebuah [FeedProductLink] di sheet Links.
///
/// - Produk tak tersedia → toast peringatan.
/// - Produk bervarian → buka [ProductVariantPickerSheet] di atas sheet Links;
///   setelah user pilih varian & confirm: masuk keranjang, tutup sheet Links
///   (kembali ke video), toast. Batal → tidak terjadi apa-apa (sheet Links
///   tetap terbuka).
/// - Produk tanpa varian → langsung masuk keranjang + toast; sheet Links TETAP
///   terbuka supaya user bisa menambah beberapa produk.
Future<void> addFeedLinkToCart(
  BuildContext context,
  FeedProductLink link, {
  int quantity = 1,
  ProductFetcher? productFetcher,
}) async {
  if (!link.isAvailable || link.stock <= 0) {
    AppToast.show(
      context,
      'Produk sedang tidak tersedia.',
      kind: ToastKind.warning,
    );
    return;
  }

  if (link.hasVariants) {
    final result = await ProductVariantPickerSheet.show(
      context,
      productSlug: link.slug,
      preselectedVariant: null,
      confirmLabel: 'Tambah ke Keranjang',
      confirmColor: NataloColors.nataloBlue,
      productFetcher: productFetcher,
    );
    if (result == null || !context.mounted) return;
    await cartStore.addProduct(
      result.product,
      variant: result.variant,
      variantLabel: cartVariantOptionLabel(result.product, result.variant),
      quantity: quantity,
    );
    if (!context.mounted) return;
    // Tutup sheet Links yang masih terbuka di baliknya → kembali ke video,
    // onClosed sheet Links memicu resume video (jalur existing).
    Navigator.of(context).pop();
    AppToast.showCartAdded(context, '${result.product.title} masuk keranjang');
    return;
  }

  final product = feedPostProductFromFeedLink(link);
  await cartStore.addProduct(product, quantity: quantity);
  if (!context.mounted) return;
  AppToast.showCartAdded(
    context,
    quantity > 1
        ? '$quantity x ${link.name} masuk keranjang'
        : '${link.name} masuk keranjang',
  );
}
```

**Catatan implementer:**
- Konfirmasi `AppToast.show(context, String, {kind})` dan `ToastKind.warning` persis seperti dipakai `_showProductUnavailable` di `feed_video_post_view.dart:2797`.
- Konfirmasi `result.product.title` adalah nama produk yang benar (di `feed_video_post_view` toast non-varian pakai `link.name`; untuk varian pakai nama `Product` — cek field: `title` vs `name` pada `Product`). Kalau `Product` tak punya `title`, pakai `link.name`.
- `context.mounted` (Flutter ≥3.7) valid untuk `BuildContext`. Jika versi lint menolak, pola alternatif: cek `if (!context.mounted)` — SDK di pubspec `>=3.0.0` jadi harus ada; kalau analyzer mengeluh, gunakan pengecekan yang setara yang sudah dipakai di codebase.

- [ ] **Step 4: Jalankan test — pastikan LULUS**

Run: `flutter test test/features/feed/widgets/feed_link_cart_actions_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Wire `_addFeedLinkToCart` di feed video view jadi delegasi**

Di `feed_video_post_view.dart`, tambah import:
```dart
import 'feed_link_cart_actions.dart';
```
Ganti method `_addFeedLinkToCart` (baris ~2770-2790) menjadi:
```dart
  void _addFeedLinkToCart(FeedProductLink link, {int quantity = 1}) {
    unawaited(addFeedLinkToCart(context, link, quantity: quantity));
  }
```
Pastikan `unawaited` sudah ter-import (`package:flutter/foundation.dart` atau `dart:async` — cek yang sudah dipakai di file ini; `unawaited` dipakai di tempat lain file ini, mis. `unawaited(_playLegacy(...))`, jadi sudah tersedia).

Kalau `_showProductUnavailable` jadi tak terpakai lagi setelah perubahan ini, cek pemakaian lain di file — kalau memang tak dipakai di tempat lain, hapus method itu untuk hindari warning `unused_element`; kalau masih dipakai, biarkan.

- [ ] **Step 6: Analyze**

Run: `flutter analyze lib/features/feed/widgets/feed_link_cart_actions.dart lib/features/feed/widgets/feed_video_post_view.dart test/features/feed/widgets/feed_link_cart_actions_test.dart`
Expected: No issues found.

- [ ] **Step 7: Commit**

```bash
git add flutter_app/lib/features/feed/widgets/feed_link_cart_actions.dart flutter_app/lib/features/feed/widgets/feed_video_post_view.dart flutter_app/test/features/feed/widgets/feed_link_cart_actions_test.dart
git commit -m "feat(feed): produk bervarian di sheet Links buka picker varian in-sheet (tak keluar video)"
```

---

## Task 4: Verifikasi menyeluruh

**Files:** tidak ada perubahan kode; hanya menjalankan cek.

- [ ] **Step 1: Analyze seluruh lib**

Run: `flutter analyze lib/`
Expected: No issues found (atau tidak ada issue BARU dibanding baseline; kalau ada issue pre-existing yang tak berhubungan, catat tapi jangan perbaiki di luar scope).

- [ ] **Step 2: Jalankan test yang terdampak**

Run: `flutter test test/widgets/product_variant_picker_sheet_test.dart test/features/feed/widgets/feed_link_cart_actions_test.dart test/cart_screen_anchor_test.dart test/features/feed/widgets/feed_product_links_sheet_test.dart`
Expected: semua PASS.

- [ ] **Step 3: Commit (kalau ada penyesuaian)**

Kalau Step 1-2 memicu perbaikan kecil, commit dengan pesan `test(variant): stabilkan verifikasi variant picker feed`. Kalau tidak ada perubahan, lewati.

## Catatan device-verify (di luar plan otomatis)

Fitur ini tak bisa diverifikasi lewat web-preview (app Flutter native). Setelah merge, WAJIB device-verify manual di iOS + Android:
1. Buka video Postingan yang punya produk tag bervarian → tap pill Links → tap ikon keranjang produk bervarian → sheet varian naik di atas sheet Links, video pause.
2. Pilih varian lengkap → "Tambah ke Keranjang" → kedua sheet tutup, kembali ke video, toast muncul, video resume.
3. Tap ikon keranjang produk TANPA varian → langsung masuk cart, sheet Links tetap terbuka.
4. Tap foto/nama produk (bukan keranjang) → tetap navigasi ke halaman detail penuh.
5. Halaman Cart: tap "Ubah"/ganti varian item → sheet varian sama, tombol "Simpan" hijau, perilaku swap tak berubah.

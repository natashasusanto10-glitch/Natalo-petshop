# Bottom Sheet "Lengkapi belanjaanmu" — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Setelah user tap "+ Keranjang" di halaman detail produk, tampilkan bottom sheet konfirmasi + carousel rekomendasi berbasis isi keranjang + tombol "Cek Keranjang".

**Architecture:** Widget sheet baru mandiri (`added_to_cart_sheet.dart`) dipanggil dari `_addToCart` di `product_detail_screen.dart` **setelah** animasi fly-to-cart selesai. `fly_to_cart.dart` diberi sinyal completion (Completer) + diperlambat. Fetch rekomendasi dibuat injectable supaya sheet bisa di-widget-test tanpa network.

**Tech Stack:** Flutter/Dart, `flutter_test`, `shared_preferences` (mock di test). Package: `natalo_petshop_flutter`. Semua perintah dijalankan dari direktori `flutter_app/`.

## Global Constraints

- Package name: `natalo_petshop_flutter`. Test import prefix: `package:natalo_petshop_flutter/...`.
- Semua perintah `flutter` dijalankan dari `flutter_app/` (mis. `cd flutter_app && flutter test ...`).
- Scope trigger: **halaman detail produk saja**. Jangan sentuh tombol keranjang di grid/home/feed.
- **Halaman Feed tidak boleh diubah sama sekali.**
- Warna (verbatim): tombol/harga biru `Color(0xFF1565D8)`, centang sukses hijau `Color(0xFF16A34A)`. Konsisten dengan `product_detail_screen.dart`.
- Teks verbatim: judul sheet `Lengkapi belanjaanmu`, konfirmasi `Masuk ke keranjang!`, judul carousel `Cek keperluan anabulmu yang lain yuk`, tombol `Cek Keranjang`.
- Jumlah rekomendasi: `limit: 10`, carousel **horizontal** 1 baris.
- Durasi animasi fly-to-cart: **900ms**.
- Sumber rekomendasi: `fetchRecommendations(cartIds: <isi cart>, excludeIds: <isi cart>, limit: 10)`; kalau `cartIds` kosong → fallback `viewedIds: [product.id]`, `excludeIds: [product.id]`.
- Route yang dipakai: `/cart` dan `/product-detail` (sudah terdaftar di app).

---

## File Structure

- **Create** `flutter_app/lib/widgets/added_to_cart_sheet.dart` — helper `showAddedToCartSheet` + widget sheet + kartu rekomendasi. Satu tanggung jawab: UI + logika sheet konfirmasi keranjang.
- **Create** `flutter_app/test/added_to_cart_sheet_test.dart` — widget test sheet.
- **Create** `flutter_app/test/fly_to_cart_test.dart` — guard test completion.
- **Modify** `flutter_app/lib/utils/fly_to_cart.dart` — completion Completer + durasi 900ms.
- **Modify** `flutter_app/lib/screens/product_detail_screen.dart` — `_addToCart` memicu sheet setelah animasi; hapus toast sukses lama; tambah guard flag + import.

---

## Task 1: Fly-to-cart — sinyal completion + perlambat animasi

**Files:**
- Modify: `flutter_app/lib/utils/fly_to_cart.dart`
- Test: `flutter_app/test/fly_to_cart_test.dart`

**Interfaces:**
- Produces: `Future<void> flyImageToCart({required BuildContext context, required String imageUrl, required GlobalKey sourceKey})` — Future kini complete saat animasi **selesai** (atau langsung, di no-op path).

- [ ] **Step 1: Tulis guard test (no-op path complete)**

Create `flutter_app/test/fly_to_cart_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/utils/fly_to_cart.dart';

void main() {
  testWidgets('flyImageToCart future complete di no-op path (tanpa cart icon)',
      (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        ctx = context;
        return const Scaffold(body: SizedBox());
      }),
    ));

    // sourceKey tidak ter-attach + tidak ada AppCartButton di tree → path
    // no-op. Future harus tetap complete (tidak hang) supaya caller yang
    // await tidak menggantung.
    var completed = false;
    await flyImageToCart(
      context: ctx,
      imageUrl: 'https://example.com/x.jpg',
      sourceKey: GlobalKey(),
    ).then((_) => completed = true).timeout(const Duration(seconds: 2));

    expect(completed, isTrue);
  });
}
```

- [ ] **Step 2: Jalankan test — pastikan lulus baseline**

Run: `cd flutter_app && flutter test test/fly_to_cart_test.dart`
Expected: PASS (path no-op memang sudah return cepat; test ini guard supaya perubahan Completer di Step 3 tidak membuat future menggantung).

- [ ] **Step 3: Tambah Completer + ubah durasi**

Di `flutter_app/lib/utils/fly_to_cart.dart`, tambah import paling atas:

```dart
import 'dart:async';
```

Ganti isi fungsi `flyImageToCart` (blok `late OverlayEntry entry; ... overlay.insert(entry);`) menjadi:

```dart
  // Completer supaya caller bisa await sampai animasi BENAR-BENAR selesai
  // (bukan sekadar overlay ter-insert) — dipakai product detail untuk
  // memunculkan sheet "Lengkapi belanjaanmu" tepat setelah animasi tuntas.
  final completer = Completer<void>();
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _FlyToCartOverlay(
      imageUrl: imageUrl,
      from: fromCenter,
      to: toCenter,
      onComplete: () {
        entry.remove();
        if (!completer.isCompleted) completer.complete();
      },
    ),
  );
  overlay.insert(entry);
  await completer.future;
```

Di `_FlyToCartOverlayState.initState`, ubah durasi controller:

```dart
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
```

(Opsional rapikan: komentar dokumentasi yang menyebut "600ms total" boleh diperbarui jadi 900ms.)

- [ ] **Step 4: Jalankan test + analyze**

Run: `cd flutter_app && flutter test test/fly_to_cart_test.dart && flutter analyze lib/utils/fly_to_cart.dart`
Expected: test PASS; analyze `No issues found!` untuk file itu.

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/utils/fly_to_cart.dart flutter_app/test/fly_to_cart_test.dart
git commit -m "feat(fly-to-cart): sinyal completion + perlambat animasi ke 900ms

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Widget `AddedToCartSheet`

**Files:**
- Create: `flutter_app/lib/widgets/added_to_cart_sheet.dart`
- Test: `flutter_app/test/added_to_cart_sheet_test.dart`

**Interfaces:**
- Consumes: `Product` model; `cartStore` (global) `.items`, `.addProduct`, `.clear`; `ProductSavingsBadge`, `ProductRatingSoldMeta`, `AppProductImage`, `AppToast`, `AppHaptics`, `formatRupiah`; `productService.fetchRecommendations`.
- Produces:
  - `typedef RecommendationsFetcher = Future<List<Product>> Function({List<String> cartIds, List<String> viewedIds, List<String> excludeIds, int limit});`
  - `Future<void> showAddedToCartSheet(BuildContext context, {required Product product, List<Product> initialRelated = const [], RecommendationsFetcher? fetchRecommendations})`.
  - Test keys: `ValueKey('cek-keranjang-button')`, `ValueKey('add-to-cart-<productId>')`.

- [ ] **Step 1: Tulis test lengkap (failing dulu)**

Create `flutter_app/test/added_to_cart_sheet_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:natalo_petshop_flutter/models/product.dart';
import 'package:natalo_petshop_flutter/state/cart_store.dart';
import 'package:natalo_petshop_flutter/widgets/added_to_cart_sheet.dart';

Product makeProduct(
  String id, {
  String? name,
  bool hasVariants = false,
  int stock = 10,
  int soldCount = 0,
  num price = 100000,
}) {
  return Product.fromApiJson({
    'id': id,
    'slug': id,
    'name': name ?? 'Produk $id',
    'price': price,
    'image_url': 'https://example.com/$id.jpg',
    'stock': stock,
    'hasVariants': hasVariants,
    'soldCount': soldCount,
  });
}

Future<List<Product>> _emptyFetcher({
  List<String> cartIds = const [],
  List<String> viewedIds = const [],
  List<String> excludeIds = const [],
  int limit = 10,
}) async =>
    const [];

Future<void> pumpSheet(
  WidgetTester tester, {
  Product? product,
  List<Product> initialRelated = const [],
  RecommendationsFetcher? fetcher,
}) async {
  await tester.pumpWidget(MaterialApp(
    routes: {
      '/cart': (_) => const Scaffold(body: Text('CART SCREEN')),
      '/product-detail': (_) => const Scaffold(body: Text('DETAIL SCREEN')),
    },
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => showAddedToCartSheet(
              context,
              product: product ?? makeProduct('main'),
              initialRelated: initialRelated,
              fetchRecommendations: fetcher ?? _emptyFetcher,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await cartStore.clear();
  });

  testWidgets('menampilkan nama produk & konfirmasi masuk keranjang',
      (tester) async {
    await pumpSheet(tester, product: makeProduct('main', name: 'Happy Dog 15kg'));
    expect(find.text('Lengkapi belanjaanmu'), findsOneWidget);
    expect(find.text('Happy Dog 15kg'), findsOneWidget);
    expect(find.text('Masuk ke keranjang!'), findsOneWidget);
  });

  testWidgets('menampilkan carousel rekomendasi saat ada data', (tester) async {
    await pumpSheet(tester,
        initialRelated: [makeProduct('r1', name: 'Rekom Satu')]);
    expect(find.text('Cek keperluan anabulmu yang lain yuk'), findsOneWidget);
    expect(find.text('Rekom Satu'), findsOneWidget);
  });

  testWidgets('carousel disembunyikan saat tidak ada rekomendasi',
      (tester) async {
    await pumpSheet(tester, initialRelated: const []);
    expect(find.text('Cek keperluan anabulmu yang lain yuk'), findsNothing);
    expect(find.text('Masuk ke keranjang!'), findsOneWidget);
    expect(find.byKey(const ValueKey('cek-keranjang-button')), findsOneWidget);
  });

  testWidgets('fetch rekomendasi pakai isi keranjang & refresh carousel',
      (tester) async {
    await cartStore.addProduct(makeProduct('incart', name: 'Di Keranjang'));
    List<String>? capturedCartIds;
    Future<List<Product>> fake({
      List<String> cartIds = const [],
      List<String> viewedIds = const [],
      List<String> excludeIds = const [],
      int limit = 10,
    }) async {
      capturedCartIds = cartIds;
      return [makeProduct('rNew', name: 'Rekom Baru')];
    }

    await pumpSheet(tester,
        initialRelated: [makeProduct('rOld', name: 'Rekom Lama')],
        fetcher: fake);

    expect(capturedCartIds, contains('incart'));
    expect(find.text('Rekom Baru'), findsOneWidget);
    expect(find.text('Rekom Lama'), findsNothing);
  });

  testWidgets('pertahankan initialRelated kalau fetch kosong', (tester) async {
    await pumpSheet(tester,
        initialRelated: [makeProduct('rOld', name: 'Rekom Lama')],
        fetcher: _emptyFetcher);
    expect(find.text('Rekom Lama'), findsOneWidget);
  });

  testWidgets('tombol Cek Keranjang buka halaman cart', (tester) async {
    await pumpSheet(tester, initialRelated: const []);
    await tester.tap(find.byKey(const ValueKey('cek-keranjang-button')));
    await tester.pumpAndSettle();
    expect(find.text('CART SCREEN'), findsOneWidget);
  });

  testWidgets('+ Keranjang kartu non-varian menambah ke cart & sheet tetap',
      (tester) async {
    await pumpSheet(tester,
        initialRelated: [makeProduct('rec1', name: 'Rekom', hasVariants: false)]);
    await tester.tap(find.byKey(const ValueKey('add-to-cart-rec1')));
    await tester.pumpAndSettle();
    expect(cartStore.items.any((it) => it.product.id == 'rec1'), isTrue);
    expect(find.text('Masuk ke keranjang!'), findsOneWidget);
  });

  testWidgets('+ Keranjang kartu varian membuka detail produk',
      (tester) async {
    await pumpSheet(tester,
        initialRelated: [makeProduct('recV', name: 'Varian', hasVariants: true)]);
    await tester.tap(find.byKey(const ValueKey('add-to-cart-recV')));
    await tester.pumpAndSettle();
    expect(find.text('DETAIL SCREEN'), findsOneWidget);
    expect(cartStore.items.any((it) => it.product.id == 'recV'), isFalse);
  });
}
```

- [ ] **Step 2: Jalankan test — verifikasi gagal**

Run: `cd flutter_app && flutter test test/added_to_cart_sheet_test.dart`
Expected: FAIL — `added_to_cart_sheet.dart` belum ada (compile error `Target of URI doesn't exist` / `showAddedToCartSheet` undefined).

- [ ] **Step 3: Tulis implementasi sheet**

Create `flutter_app/lib/widgets/added_to_cart_sheet.dart`:

```dart
import 'package:flutter/material.dart';

import '../models/product.dart';
import '../services/product_service.dart';
import '../state/cart_store.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import 'app_product_image.dart';
import 'app_toast.dart';
import 'product_card.dart' show ProductSavingsBadge, ProductRatingSoldMeta;

/// Warna disamakan dengan halaman detail produk (product_detail_screen.dart)
/// supaya sheet konsisten dengan tombol "+ Keranjang" di bottom bar.
const _brandBlue = Color(0xFF1565D8);
const _successGreen = Color(0xFF16A34A);

/// Signature fetch rekomendasi — dibuat injectable supaya sheet bisa
/// di-test tanpa memanggil network. Default: productService.fetchRecommendations.
typedef RecommendationsFetcher = Future<List<Product>> Function({
  List<String> cartIds,
  List<String> viewedIds,
  List<String> excludeIds,
  int limit,
});

/// Bottom sheet "Lengkapi belanjaanmu" — muncul setelah user add product ke
/// keranjang dari halaman detail. Menampilkan konfirmasi + carousel
/// rekomendasi (berbasis isi keranjang) + tombol "Cek Keranjang".
///
/// `initialRelated` dipakai sebagai isi awal carousel (instan, dari
/// `_related` yang sudah ter-load di halaman detail). Saat sheet dibuka,
/// carousel di-refresh dengan rekomendasi berbasis isi keranjang.
Future<void> showAddedToCartSheet(
  BuildContext context, {
  required Product product,
  List<Product> initialRelated = const [],
  RecommendationsFetcher? fetchRecommendations,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _AddedToCartSheet(
      product: product,
      initialRelated: initialRelated,
      fetchRecommendations:
          fetchRecommendations ?? productService.fetchRecommendations,
    ),
  );
}

class _AddedToCartSheet extends StatefulWidget {
  final Product product;
  final List<Product> initialRelated;
  final RecommendationsFetcher fetchRecommendations;

  const _AddedToCartSheet({
    required this.product,
    required this.initialRelated,
    required this.fetchRecommendations,
  });

  @override
  State<_AddedToCartSheet> createState() => _AddedToCartSheetState();
}

class _AddedToCartSheetState extends State<_AddedToCartSheet> {
  late List<Product> _related = widget.initialRelated;

  @override
  void initState() {
    super.initState();
    _loadCartRecommendations();
  }

  Future<void> _loadCartRecommendations() async {
    final cartIds =
        cartStore.items.map((it) => it.product.id).toList(growable: false);
    final result = await widget.fetchRecommendations(
      cartIds: cartIds,
      viewedIds: cartIds.isEmpty ? [widget.product.id] : const [],
      excludeIds: cartIds.isEmpty ? [widget.product.id] : cartIds,
      limit: 10,
    );
    // Kalau gagal / kosong, pertahankan initialRelated (jangan dikosongkan).
    if (!mounted || result.isEmpty) return;
    setState(() => _related = result);
  }

  void _openDetail(Product product) {
    AppHaptics.tap();
    final nav = Navigator.of(context);
    nav.pop();
    nav.pushNamed('/product-detail', arguments: product);
  }

  void _addRecommendation(Product product) {
    if (product.hasVariants) {
      // Produk varian tidak bisa langsung ditambah — buka detailnya.
      AppHaptics.tap();
      AppToast.show(
        context,
        'Pilih varian produk dulu.',
        kind: ToastKind.info,
      );
      final nav = Navigator.of(context);
      nav.pop();
      nav.pushNamed('/product-detail', arguments: product);
      return;
    }
    AppHaptics.success();
    cartStore.addProduct(product);
    AppToast.showCartAdded(
      context,
      '${product.title} masuk keranjang',
    );
  }

  void _goToCart() {
    AppHaptics.tap();
    final nav = Navigator.of(context);
    nav.pop();
    nav.pushNamed('/cart');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Lengkapi belanjaanmu',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.of(context).maybePop(),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 46,
                  height: 46,
                  color: cs.surfaceContainerHighest,
                  child: AppProductImage(
                    imageUrl: widget.product.imageUrl,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.product.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 3),
                    const Row(
                      children: [
                        Icon(Icons.check_circle_rounded,
                            size: 16, color: _successGreen),
                        SizedBox(width: 5),
                        Text(
                          'Masuk ke keranjang!',
                          style: TextStyle(
                            color: _successGreen,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_related.isNotEmpty) ...[
            const SizedBox(height: 14),
            Divider(height: 1, color: cs.outlineVariant),
            const SizedBox(height: 14),
            Text(
              'Cek keperluan anabulmu yang lain yuk',
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 296,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _related.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, index) => _SheetRecommendationCard(
                  product: _related[index],
                  onOpenDetail: () => _openDetail(_related[index]),
                  onAddToCart: () => _addRecommendation(_related[index]),
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Divider(height: 1, color: cs.outlineVariant),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  key: const ValueKey('cek-keranjang-button'),
                  onPressed: _goToCart,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _brandBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  child: const Text('Cek Keranjang'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetRecommendationCard extends StatelessWidget {
  final Product product;
  final VoidCallback onOpenDetail;
  final VoidCallback onAddToCart;

  const _SheetRecommendationCard({
    required this.product,
    required this.onOpenDetail,
    required this.onAddToCart,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 150,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: onOpenDetail,
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      height: 118,
                      width: double.infinity,
                      color: cs.surfaceContainerHighest,
                      padding: const EdgeInsets.all(6),
                      child: AppProductImage(
                        imageUrl: product.imageUrl,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 32,
                    child: Text(
                      product.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    formatRupiah(product.finalPrice),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _brandBlue,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  ProductSavingsBadge(product: product),
                  ProductRatingSoldMeta(product: product),
                ],
              ),
            ),
            const Spacer(),
            const SizedBox(height: 8),
            _AddPill(
              key: ValueKey('add-to-cart-${product.id}'),
              onTap: onAddToCart,
            ),
          ],
        ),
      ),
    );
  }
}

class _AddPill extends StatelessWidget {
  final VoidCallback onTap;

  const _AddPill({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          decoration: BoxDecoration(
            color: _brandBlue,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const SizedBox(
            height: 32,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_rounded, size: 16, color: Colors.white),
                SizedBox(width: 4),
                Text(
                  'Keranjang',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Jalankan test — verifikasi lulus**

Run: `cd flutter_app && flutter test test/added_to_cart_sheet_test.dart`
Expected: PASS (8 tests).

- [ ] **Step 5: Analyze file baru**

Run: `cd flutter_app && flutter analyze lib/widgets/added_to_cart_sheet.dart test/added_to_cart_sheet_test.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add flutter_app/lib/widgets/added_to_cart_sheet.dart flutter_app/test/added_to_cart_sheet_test.dart
git commit -m "feat(cart): sheet 'Lengkapi belanjaanmu' + carousel rekomendasi cart-based

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Wire sheet ke `_addToCart` (product detail)

**Files:**
- Modify: `flutter_app/lib/screens/product_detail_screen.dart` (import; field `_addedSheetVisible`; method `_addToCart` ~ baris 287-316)

**Interfaces:**
- Consumes: `showAddedToCartSheet(...)` (Task 2), `flyImageToCart(...)` (Task 1).

**Catatan verifikasi:** `ProductDetailScreen` memanggil Firebase Analytics + beberapa service network di `initState`, jadi tidak praktis di-widget-test terisolasi. Task ini diverifikasi lewat `flutter analyze` + QA manual (Task 4). Perilaku sheet-nya sendiri sudah ditutup unit test di Task 2.

- [ ] **Step 1: Tambah import**

Di `flutter_app/lib/screens/product_detail_screen.dart`, tambahkan bersama import widget lain (mis. setelah baris `import '../widgets/app_toast.dart';`):

```dart
import '../widgets/added_to_cart_sheet.dart';
```

- [ ] **Step 2: Tambah guard flag**

Di `_ProductDetailScreenState`, dekat field `bool _buyNowPushing = false;`, tambahkan:

```dart
  // Guard supaya tidak menumpuk dua sheet "Lengkapi belanjaanmu" kalau user
  // tap "+ Keranjang" dua kali cepat (animasi fly ~900ms sebelum sheet naik).
  bool _addedSheetVisible = false;
```

- [ ] **Step 3: Ubah blok akhir `_addToCart`**

Di method `_addToCart`, ganti blok dari `AppHaptics.success();` sampai penutup `}` sebelum `bool _buyNowPushing = false;`. Blok LAMA:

```dart
    AppHaptics.success();
    // Fire fly-to-cart animation dulu (Overlay-based, tidak block UI).
    // Mini product image fly dari posisi hero image → cart icon di AppBar
    // dengan parabolic arc. Match Tokopedia / Shopee pattern.
    flyImageToCart(
      context: context,
      imageUrl: product.imageUrl,
      sourceKey: _heroImageKey,
    );
    cartStore.addProduct(
      product,
      variant: variant,
      variantLabel: _variantLabelFor(variant),
      quantity: quantity,
    );
    // Kalau jumlah yang diminta melebihi stok → ke-clamp di store, beri tahu.
    if (stock > 0 && currentQty + quantity > stock) {
      AppToast.show(
        context,
        'Stok tinggal $stock, jumlah disesuaikan.',
        kind: ToastKind.info,
      );
    } else {
      AppToast.showCartAdded(
        context,
        '${product.title} masuk keranjang',
        onTap: () => Navigator.pushNamed(context, '/cart'),
      );
    }
  }
```

Diganti dengan blok BARU:

```dart
    AppHaptics.success();
    // Tambah ke keranjang DULU supaya rekomendasi di sheet (berbasis isi
    // keranjang) sudah termasuk produk yang barusan ditambahkan.
    cartStore.addProduct(
      product,
      variant: variant,
      variantLabel: _variantLabelFor(variant),
      quantity: quantity,
    );
    // Kalau jumlah yang diminta melebihi stok → ke-clamp di store, beri tahu.
    if (stock > 0 && currentQty + quantity > stock) {
      AppToast.show(
        context,
        'Stok tinggal $stock, jumlah disesuaikan.',
        kind: ToastKind.info,
      );
    }
    // Animasi fly-to-cart dulu (mini image fly dari hero image → cart icon
    // dengan parabolic arc), lalu naikkan sheet "Lengkapi belanjaanmu"
    // sebagai konfirmasi — menggantikan toast lama. Guard mencegah dua sheet
    // menumpuk kalau user tap cepat dua kali.
    flyImageToCart(
      context: context,
      imageUrl: product.imageUrl,
      sourceKey: _heroImageKey,
    ).then((_) async {
      if (!mounted || _addedSheetVisible) return;
      _addedSheetVisible = true;
      await showAddedToCartSheet(
        context,
        product: product,
        initialRelated: _related,
      );
      if (mounted) _addedSheetVisible = false;
    });
  }
```

- [ ] **Step 4: Analyze**

Run: `cd flutter_app && flutter analyze lib/screens/product_detail_screen.dart`
Expected: `No issues found!` (khususnya tidak ada `unused_import` / `unused_field`; `AppToast` masih dipakai untuk toast clamp).

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/screens/product_detail_screen.dart
git commit -m "feat(product-detail): tampilkan sheet 'Lengkapi belanjaanmu' setelah add to cart

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: Verifikasi penuh + QA manual

**Files:** (tidak ada perubahan kode; hanya kalau ada temuan)

- [ ] **Step 1: Analyze seluruh project**

Run: `cd flutter_app && flutter analyze`
Expected: `No issues found!` (atau hanya warning yang sudah ada sebelumnya di file lain — tidak ada isu baru dari file yang disentuh).

- [ ] **Step 2: Jalankan seluruh test suite**

Run: `cd flutter_app && flutter test`
Expected: semua test PASS, termasuk `fly_to_cart_test.dart` dan `added_to_cart_sheet_test.dart`.

- [ ] **Step 3: QA manual di device/emulator**

Run: `cd flutter_app && flutter run`
Checklist (jalankan berurutan):
- Buka satu produk **tanpa varian** → tap **+ Keranjang**. Amati: animasi fly-to-cart terasa lebih pelan (~0,9s), lalu sheet naik. Tidak ada toast "masuk keranjang" lama yang dobel.
- Sheet menampilkan judul **Lengkapi belanjaanmu**, thumbnail + nama produk + **Masuk ke keranjang!** (centang hijau), judul **Cek keperluan anabulmu yang lain yuk**, dan tombol biru **Cek Keranjang**.
- Carousel = 1 baris horizontal, di-scroll ke samping. Tiap kartu ada pill biru **+ Keranjang**.
- Tap **+ Keranjang** di salah satu kartu (non-varian) → badge cart naik, toast mini muncul, sheet tetap terbuka.
- Tap **body kartu** → pindah ke detail produk itu (sheet tertutup).
- Buka produk **dengan varian** → tap **+ Keranjang** → pilih varian → setelah add, sheet muncul.
- Tap **Cek Keranjang** → masuk halaman keranjang, produk ada di sana.
- Tap **✕** / geser ke bawah → sheet tertutup tanpa error.
- Cek dark mode: warna teks tetap terbaca, CTA biru & centang hijau konsisten.
- (Regresi) Buka **Feed** → pastikan tidak ada perubahan.

- [ ] **Step 4: Fine-tune bila perlu**

Kalau durasi 900ms masih terasa cepat/lambat, sesuaikan konstanta di `flutter_app/lib/utils/fly_to_cart.dart` (Task 1 Step 3). Kalau ada temuan lain dari QA, perbaiki lalu commit dengan pesan deskriptif.

- [ ] **Step 5: Commit (kalau ada penyesuaian)**

```bash
git add -A
git commit -m "chore(cart): penyesuaian QA sheet add-to-cart

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review (diisi penulis plan)

**Spec coverage:**
- Trigger detail-only → Task 3. ✓
- Fly dulu lalu sheet, animasi diperlambat → Task 1 + Task 3. ✓
- Toast lama diganti sheet (clamp toast tetap) → Task 3 Step 3. ✓
- Konfirmasi + carousel + Cek Keranjang → Task 2. ✓
- Judul carousel baru + teks verbatim → Task 2 (Global Constraints). ✓
- Sumber data cart-based + fallback viewed + limit 10 → Task 2 `_loadCartRecommendations`. ✓
- Pill biru "+ Keranjang", warna #1565D8, feed dikecualikan → Task 2 + Global Constraints. ✓
- Edge: keranjang "kosong" (fallback), varian, kosong→carousel hidden → Task 2 tests. ✓

**Placeholder scan:** tidak ada TBD/TODO; semua step berisi kode/komando nyata.

**Type consistency:** `RecommendationsFetcher` signature sama di typedef, `showAddedToCartSheet`, dan fake test. `_related`, keys `cek-keranjang-button` / `add-to-cart-<id>` konsisten antara implementasi & test. `productService.fetchRecommendations` punya named params `{cartIds, viewedIds, excludeIds, limit}` yang cocok dengan typedef.

# Feed TikTok Product Pill + Links Sheet — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ganti kartu produk anchor lebar di feed video+foto dengan pill glass mungil ala TikTok (ikon keranjang biru, judul bergilir, `·N ⌄`, badge `Diskon s/d {maks}%`) yang tap-nya membuka sheet grid produk (Opsi-2) dan menjeda video.

**Architecture:** Tiga widget baru presentational (`FeedProductPill`, `FeedProductGridCard`, `FeedProductLinksSheet`) + dua helper murni di `feed_post_shared_widgets.dart` (`feedMaxDiscountPercent`, `feedProductPillFor`). Dua host feed (video `feed_video_post_view.dart`, foto `feed_screen.dart`) repoint dari builder anchor lama ke pill + sheet baru; sheet menjeda video meniru mekanisme comment-sheet (branch managed/legacy). `FeedProductAnchorCard` DIPERTAHANKAN untuk preview (di luar cakupan).

**Tech Stack:** Flutter/Dart, `flutter_test`, `AppProductImage` (cached_network_image + shimmer), `PostVideoCoordinator` (managed playback), `cartStore`, `productService`.

## Global Constraints

- **Nama package Dart = `natalo_petshop_flutter`** — semua import test: `package:natalo_petshop_flutter/...` (bukan `natalo_petshop`).
- Sumber produk overlay: `post.taggedProducts` via `_rotatingProductsForPost(post)` = **admin 5 / non-admin 3** — dipakai untuk pill (judul, count, maxDiscount) DAN grid sheet, supaya count == isi sheet == rotasi.
- Warna biru brand: `NataloColors.primary` = `Color(0xFF1E5FBF)`.
- Persen diskon: **selalu** `FeedProductLink.discountPercent` (round+clamp 1..99). JANGAN `productDiscountPercent` (floor → beda 1%).
- Label badge pill agregat: `Diskon s/d {n}%` netral — JANGAN warisi "Flash Sale" (`isFlashSale` per-produk).
- Merah badge pill = `0xFFFF4D4F` (konvensi feed). Merah badge/harga kartu grid = `0xFFE11D48` (token Katalog). Ini dua merah berbeda yang disengaja; JANGAN pakai `NataloColors.discountRed` (0xFFEF4444).
- `AppProductImage` full-bleed 1:1 WAJIB `borderRadius: BorderRadius.zero` (default 12 memasang ClipRRect internal → double-round).
- Tes video/produk: **JANGAN `pumpAndSettle`** (shimmer `AppProductImage` tak pernah settle) — pakai `tester.pump()` sekali atau bounded pump loop. Set `VisibilityDetectorController.instance.updateInterval = Duration.zero` di setUp bila memakai harness video.
- Playback dual-mode: bila `_managed` (`widget.playbackManagedExternally`) JANGAN sentuh controller — lapor via `onRequestPause`/`onRequestPlay`. Bila legacy → `ctrl.pause()` / `_playLegacy(...)` di-gate `_canAutoplayNow()`. Pakai flag sekali-transisi.
- Perubahan pill/cart/rotasi WAJIB diterapkan di **kedua** file host (`feed_video_post_view.dart` + `feed_screen.dart`) atau kedua surface drift. Surface ke-3 `scoped_video_feed_screen.dart` ikut otomatis (reuse `FeedVideoPostView`).
- Commit di worktree branch `claude/tiktok-flow-discussion-341a86`. Akhiri pesan commit dengan `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

---

### Task 1: Helper `feedMaxDiscountPercent` (pure)

**Files:**
- Modify: `flutter_app/lib/features/feed/widgets/feed_post_shared_widgets.dart` (tambah fungsi top-level dekat `feedPostProductPricing`, ~line 1461)
- Test: `flutter_app/test/features/feed/feed_max_discount_percent_test.dart` (create)

**Interfaces:**
- Consumes: `FeedProductLink.discountPercent` (getter, `flutter_app/lib/models/feed_post.dart:150`, returns 0..99)
- Produces: `int feedMaxDiscountPercent(List<FeedProductLink> products)` — 0 bila tak ada produk promo.

- [ ] **Step 1: Write the failing test**

```dart
// flutter_app/test/features/feed/feed_max_discount_percent_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_post_shared_widgets.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';

FeedProductLink _link({required int price, int? discountPrice}) => FeedProductLink(
      id: 'p$price',
      slug: 'p$price',
      name: 'Produk $price',
      price: price,
      discountPrice: discountPrice,
      stock: 10,
    );

void main() {
  test('empty list -> 0', () {
    expect(feedMaxDiscountPercent(const []), 0);
  });

  test('no promo -> 0', () {
    expect(
      feedMaxDiscountPercent([_link(price: 50000), _link(price: 20000)]),
      0,
    );
  });

  test('mixed -> highest discount percent', () {
    // 55000->44500 = 19%, 100000->70000 = 30%, plus one non-promo
    final products = [
      _link(price: 55000, discountPrice: 44500),
      _link(price: 100000, discountPrice: 70000),
      _link(price: 20000),
    ];
    expect(feedMaxDiscountPercent(products), 30);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd flutter_app && flutter test test/features/feed/feed_max_discount_percent_test.dart`
Expected: FAIL — `feedMaxDiscountPercent` tak terdefinisi (compile error).

- [ ] **Step 3: Write minimal implementation**

Tambah tepat di atas `feedPostProductPricing` (feed_post_shared_widgets.dart:1461):

```dart
/// Diskon tertinggi (0..99) di antara produk tag yang promo. 0 = tak ada promo.
/// Pakai getter FeedProductLink.discountPercent (round+clamp) supaya konsisten
/// dengan badge kartu; produk non-promo return 0 sehingga otomatis terabaikan.
int feedMaxDiscountPercent(List<FeedProductLink> products) => products.fold<int>(
      0,
      (max, p) => p.discountPercent > max ? p.discountPercent : max,
    );
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd flutter_app && flutter test test/features/feed/feed_max_discount_percent_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/features/feed/widgets/feed_post_shared_widgets.dart flutter_app/test/features/feed/feed_max_discount_percent_test.dart
git commit -m "feat(feed): helper feedMaxDiscountPercent utk badge 'Diskon s/d maks%'

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Widget `FeedProductPill`

**Files:**
- Create: `flutter_app/lib/features/feed/widgets/feed_product_pill.dart`
- Test: `flutter_app/test/features/feed/widgets/feed_product_pill_test.dart` (create)

**Interfaces:**
- Consumes: `NataloColors.primary` (`flutter_app/lib/theme/natalo_colors.dart`)
- Produces: `FeedProductPill({required String title, required int count, required VoidCallback onTap, int maxDiscountPercent = 0})`

- [ ] **Step 1: Write the failing test**

```dart
// flutter_app/test/features/feed/widgets/feed_product_pill_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_product_pill.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('renders title, count, and discount badge', (tester) async {
    await tester.pumpWidget(_host(FeedProductPill(
      title: 'Happy Cat Sensitive Skin & Coat',
      count: 5,
      maxDiscountPercent: 20,
      onTap: () {},
    )));
    await tester.pump();
    expect(find.text('Happy Cat Sensitive Skin & Coat'), findsOneWidget);
    expect(find.text('·5'), findsOneWidget);
    expect(find.text('Diskon s/d 20%'), findsOneWidget);
  });

  testWidgets('no badge when maxDiscountPercent is 0', (tester) async {
    await tester.pumpWidget(_host(FeedProductPill(
      title: 'Produk', count: 1, maxDiscountPercent: 0, onTap: () {},
    )));
    await tester.pump();
    expect(find.textContaining('Diskon'), findsNothing);
  });

  testWidgets('tap invokes onTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(_host(FeedProductPill(
      title: 'Produk', count: 2, onTap: () => tapped = true,
    )));
    await tester.pump();
    await tester.tap(find.text('Produk'));
    expect(tapped, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd flutter_app && flutter test test/features/feed/widgets/feed_product_pill_test.dart`
Expected: FAIL — `feed_product_pill.dart` belum ada.

- [ ] **Step 3: Write minimal implementation**

```dart
// flutter_app/lib/features/feed/widgets/feed_product_pill.dart
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../theme/natalo_colors.dart';

/// Pill produk mungil ala TikTok untuk overlay feed (video & foto).
///
/// Glass netral transparan + blur ringan supaya tidak menutup isi video;
/// ikon keranjang kotak biru brand (bukan kuning TikTok); judul produk
/// (rotasi dikendalikan pemanggil lewat [title] — AnimatedSwitcher crossfade
/// saat judul berganti); `·N` jumlah produk tag + chevron; badge
/// `Diskon s/d {maks}%` terpisah di atas pill bila [maxDiscountPercent] > 0.
///
/// API primitif (tak terikat model) supaya dipakai video & foto lewat builder
/// bersama `feedProductPillFor`.
class FeedProductPill extends StatelessWidget {
  final String title;
  final int count;
  final int maxDiscountPercent;
  final VoidCallback onTap;

  const FeedProductPill({
    super.key,
    required this.title,
    required this.count,
    required this.onTap,
    this.maxDiscountPercent = 0,
  });

  @override
  Widget build(BuildContext context) {
    final white80 = Colors.white.withValues(alpha: 0.8);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (maxDiscountPercent > 0) ...[
          _PillDiscountBadge(percent: maxDiscountPercent),
          const SizedBox(height: 5),
        ],
        Material(
          color: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(3, 3, 9, 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.40),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.14),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 19,
                        height: 19,
                        decoration: BoxDecoration(
                          color: NataloColors.primary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.shopping_bag_outlined,
                          size: 12,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 150),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 260),
                          transitionBuilder: (child, animation) =>
                              FadeTransition(opacity: animation, child: child),
                          child: Text(
                            title,
                            key: ValueKey<String>(title),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              height: 1.2,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '·$count',
                        style: TextStyle(
                          color: white80,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          height: 1,
                        ),
                      ),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 13,
                        color: white80,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PillDiscountBadge extends StatelessWidget {
  final int percent;

  const _PillDiscountBadge({required this.percent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFF4D4F),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_offer, size: 10, color: Colors.white),
          const SizedBox(width: 3),
          Text(
            'Diskon s/d $percent%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9.5,
              fontWeight: FontWeight.w500,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd flutter_app && flutter test test/features/feed/widgets/feed_product_pill_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/features/feed/widgets/feed_product_pill.dart flutter_app/test/features/feed/widgets/feed_product_pill_test.dart
git commit -m "feat(feed): FeedProductPill glass ramping + badge diskon s/d

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Builder `feedProductPillFor`

**Files:**
- Modify: `flutter_app/lib/features/feed/widgets/feed_post_shared_widgets.dart` (tambah fungsi + import `feed_product_pill.dart`)
- Test: `flutter_app/test/features/feed/widgets/feed_product_pill_for_test.dart` (create)

**Interfaces:**
- Consumes: `FeedProductPill` (Task 2), `feedMaxDiscountPercent` (Task 1)
- Produces: `Widget feedProductPillFor(List<FeedProductLink> products, int featuredIndex, {required VoidCallback onTap})`

- [ ] **Step 1: Write the failing test**

```dart
// flutter_app/test/features/feed/widgets/feed_product_pill_for_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_post_shared_widgets.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';

FeedProductLink _link(String name, {required int price, int? discountPrice}) =>
    FeedProductLink(
      id: name, slug: name, name: name, price: price,
      discountPrice: discountPrice, stock: 10,
    );

void main() {
  testWidgets('builds pill for featured index with count + max discount',
      (tester) async {
    final products = [
      _link('A', price: 55000, discountPrice: 44500), // 19%
      _link('B', price: 100000, discountPrice: 70000), // 30%
      _link('C', price: 20000),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: feedProductPillFor(products, 1, onTap: () {}),
      ),
    ));
    await tester.pump();
    expect(find.text('B'), findsOneWidget); // featuredIndex 1
    expect(find.text('·3'), findsOneWidget); // count = list length
    expect(find.text('Diskon s/d 30%'), findsOneWidget); // max across list
  });

  testWidgets('index wraps modulo length', (tester) async {
    final products = [_link('A', price: 1000), _link('B', price: 1000)];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: feedProductPillFor(products, 3, onTap: () {})),
    ));
    await tester.pump();
    expect(find.text('B'), findsOneWidget); // 3 % 2 == 1 -> 'B'
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd flutter_app && flutter test test/features/feed/widgets/feed_product_pill_for_test.dart`
Expected: FAIL — `feedProductPillFor` tak terdefinisi.

- [ ] **Step 3: Write minimal implementation**

Tambah import di bagian atas `feed_post_shared_widgets.dart` (dekat import widget lain):

```dart
import 'feed_product_pill.dart';
```

Tambah fungsi (dekat `feedPostProductAnchorCardFor`, ~line 1487):

```dart
/// Bangun `FeedProductPill` (widget bersama) dari daftar produk tag + index
/// yang sedang tampil. Count = jumlah produk; badge diskon = persen tertinggi.
/// Rotasi index dikendalikan pemanggil (host feed). `onTap` membuka sheet Links.
Widget feedProductPillFor(
  List<FeedProductLink> products,
  int featuredIndex, {
  required VoidCallback onTap,
}) {
  final featured = products[featuredIndex % products.length];
  return FeedProductPill(
    title: featured.name,
    count: products.length,
    maxDiscountPercent: feedMaxDiscountPercent(products),
    onTap: onTap,
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd flutter_app && flutter test test/features/feed/widgets/feed_product_pill_for_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/features/feed/widgets/feed_post_shared_widgets.dart flutter_app/test/features/feed/widgets/feed_product_pill_for_test.dart
git commit -m "feat(feed): builder feedProductPillFor (produk+index -> pill)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Widget `FeedProductGridCard` (kartu Opsi-2)

**Files:**
- Create: `flutter_app/lib/features/feed/widgets/feed_product_links_sheet.dart` (kartu di sini; sheet ditambah Task 5)
- Test: `flutter_app/test/features/feed/widgets/feed_product_grid_card_test.dart` (create)

**Interfaces:**
- Consumes: `FeedProductLink`, `feedPostProductPricing` (`feed_post_shared_widgets.dart:1461`), `AppProductImage` (`flutter_app/lib/widgets/app_product_image.dart`), `formatRupiah` (`flutter_app/lib/utils/formatters.dart`), `NataloColors`, `ActionThrottle` (`flutter_app/lib/utils/action_throttle.dart`)
- Produces: `FeedProductGridCard({required FeedProductLink product, required VoidCallback onTap, required VoidCallback onAddToCart})`

- [ ] **Step 1: Write the failing test**

```dart
// flutter_app/test/features/feed/widgets/feed_product_grid_card_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_product_links_sheet.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: SizedBox(width: 180, child: child)));

void main() {
  testWidgets('promo product: strike + red price + -N% badge', (tester) async {
    final p = FeedProductLink(
      id: '1', slug: 'happy-cat', name: 'Happy Cat Sensitive',
      price: 55000, discountPrice: 44500, stock: 10,
      avgRating: 4.8, soldCount: 120,
    );
    await tester.pumpWidget(_host(
      FeedProductGridCard(product: p, onTap: () {}, onAddToCart: () {}),
    ));
    await tester.pump();
    expect(find.text('-19%'), findsOneWidget);
    expect(find.text('Rp44.500'), findsOneWidget);
    expect(find.text('Rp55.000'), findsOneWidget); // strike original
    expect(find.textContaining('terjual'), findsOneWidget);
  });

  testWidgets('non-promo product: plain price, no badge, no rating row',
      (tester) async {
    final p = FeedProductLink(
      id: '2', slug: 'plain', name: 'Plain Product', price: 30000, stock: 5,
    );
    await tester.pumpWidget(_host(
      FeedProductGridCard(product: p, onTap: () {}, onAddToCart: () {}),
    ));
    await tester.pump();
    expect(find.text('Rp30.000'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
    expect(find.textContaining('terjual'), findsNothing);
  });

  testWidgets('cart button invokes onAddToCart; card invokes onTap',
      (tester) async {
    var added = false, opened = false;
    final p = FeedProductLink(
      id: '3', slug: 'x', name: 'X', price: 10000, stock: 5,
    );
    await tester.pumpWidget(_host(
      FeedProductGridCard(
        product: p, onTap: () => opened = true, onAddToCart: () => added = true),
    ));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.shopping_cart_outlined));
    expect(added, isTrue);
    await tester.tap(find.text('X'));
    expect(opened, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd flutter_app && flutter test test/features/feed/widgets/feed_product_grid_card_test.dart`
Expected: FAIL — file/kelas belum ada.

- [ ] **Step 3: Write minimal implementation**

```dart
// flutter_app/lib/features/feed/widgets/feed_product_links_sheet.dart
import 'package:flutter/material.dart';

import '../../../models/feed_post.dart';
import '../../../theme/natalo_colors.dart';
import '../../../utils/action_throttle.dart';
import '../../../utils/formatters.dart';
import '../../../widgets/app_product_image.dart';
import 'feed_post_shared_widgets.dart';

// Token kartu Katalog (Opsi 2). Literal lokal — di file asal (compact_commerce
// _product_card.dart) juga literal privat; redeklarasi di sini disengaja.
const _discountRed = Color(0xFFE11D48);
const _starAmber = Color(0xFFF59E0B);
const _cartBorder = Color(0xFFBFD5FF);

/// Kartu grid produk di sheet Links (Opsi 2) — meniru token kartu Katalog
/// (`CompactCommerceProductCard` squareImage), tapi diisi `FeedProductLink`.
/// Foto 1:1 cover full-bleed, badge -N%, harga coret+merah, rating•terjual
/// (sembunyi kalau 0), tombol keranjang biru.
class FeedProductGridCard extends StatelessWidget {
  final FeedProductLink product;
  final VoidCallback onTap;
  final VoidCallback onAddToCart;

  const FeedProductGridCard({
    super.key,
    required this.product,
    required this.onTap,
    required this.onAddToCart,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pricing = feedPostProductPricing(product);
    final percent = product.discountPercent;
    final showRating = product.avgRating > 0 || product.soldCount > 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: cs.outlineVariant, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.045),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: AppProductImage(
                        imageUrl: product.imageUrl,
                        fit: BoxFit.cover,
                        borderRadius: BorderRadius.zero,
                      ),
                    ),
                    if (percent > 0)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: _NBadge(percent: percent),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 13.5,
                        height: 1.22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (showRating) ...[
                      const SizedBox(height: 7),
                      _RatingSoldRow(product: product),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(child: _PriceBlock(pricing: pricing)),
                        const SizedBox(width: 8),
                        _CartButton(
                          enabled: product.isAvailable && product.stock > 0,
                          onTap: onAddToCart,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NBadge extends StatelessWidget {
  final int percent;
  const _NBadge({required this.percent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: const BoxDecoration(
        color: _discountRed,
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(16),
          bottomLeft: Radius.circular(14),
        ),
      ),
      child: Text(
        '-$percent%',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          height: 1,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _PriceBlock extends StatelessWidget {
  final FeedPostProductPricing pricing;
  const _PriceBlock({required this.pricing});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (!pricing.hasPromo) {
      return Text(
        formatRupiah(pricing.displayPrice),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: cs.onSurface,
          fontSize: 20,
          height: 1.04,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.25,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          formatRupiah(pricing.originalPrice),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 12.5,
            height: 1.05,
            fontWeight: FontWeight.w700,
            decoration: TextDecoration.lineThrough,
            decorationThickness: 1.5,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          formatRupiah(pricing.displayPrice),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _discountRed,
            fontSize: 20,
            height: 1.04,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.25,
          ),
        ),
      ],
    );
  }
}

class _RatingSoldRow extends StatelessWidget {
  final FeedProductLink product;
  const _RatingSoldRow({required this.product});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasRating = product.avgRating > 0;
    final hasSold = product.soldCount > 0;
    return Row(
      children: [
        if (hasRating) ...[
          const Icon(Icons.star_rounded, color: _starAmber, size: 15),
          const SizedBox(width: 3),
          Text(
            product.avgRating.toStringAsFixed(1),
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 11.8,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ],
        if (hasRating && hasSold) ...[
          const SizedBox(width: 6),
          Text('•',
              style: TextStyle(
                  color: cs.onSurfaceVariant, fontSize: 11.5, height: 1,
                  fontWeight: FontWeight.w900)),
          const SizedBox(width: 6),
        ],
        if (hasSold)
          Flexible(
            child: Text(
              '${product.soldCount} terjual',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 11.8,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
          ),
      ],
    );
  }
}

class _CartButton extends StatefulWidget {
  final bool enabled;
  final VoidCallback onTap;
  const _CartButton({required this.enabled, required this.onTap});

  @override
  State<_CartButton> createState() => _CartButtonState();
}

class _CartButtonState extends State<_CartButton> {
  final ActionThrottle _throttle =
      ActionThrottle(interval: const Duration(milliseconds: 650));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: widget.enabled ? () => _throttle.run(widget.onTap) : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: widget.enabled ? _cartBorder : cs.outlineVariant,
              width: 1.2,
            ),
          ),
          child: Icon(
            widget.enabled
                ? Icons.shopping_cart_outlined
                : Icons.block_rounded,
            size: 22,
            color: widget.enabled ? NataloColors.primary : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
```

> Verifikasi nama field pricing: `FeedPostProductPricing` punya `originalPrice`,
> `displayPrice`, `hasPromo`, `discountPercent` (feed_post_shared_widgets.dart:1447).
> Jika `AppProductImage` param bukan `imageUrl` (cek `flutter_app/lib/widgets/app_product_image.dart`),
> sesuaikan. `formatRupiah` di `flutter_app/lib/utils/formatters.dart`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd flutter_app && flutter test test/features/feed/widgets/feed_product_grid_card_test.dart`
Expected: PASS (3 tests). (Pakai `pump()` bukan `pumpAndSettle` — shimmer.)

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/features/feed/widgets/feed_product_links_sheet.dart flutter_app/test/features/feed/widgets/feed_product_grid_card_test.dart
git commit -m "feat(feed): FeedProductGridCard (token Katalog, diisi FeedProductLink)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: `FeedProductLinksSheet` + `showFeedProductLinksSheet`

**Files:**
- Modify: `flutter_app/lib/features/feed/widgets/feed_product_links_sheet.dart` (tambah sheet + fungsi show; tambah import `sheet_drag_handle.dart` + `compact_commerce_product_card.dart` utk `commerceGridSurfaceTint`)
- Test: `flutter_app/test/features/feed/widgets/feed_product_links_sheet_test.dart` (create)

**Interfaces:**
- Consumes: `FeedProductGridCard` (Task 4), `SheetDragHandle` (`flutter_app/lib/widgets/sheet_drag_handle.dart`), `commerceGridSurfaceTint` (`flutter_app/lib/widgets/compact_commerce_product_card.dart:21`)
- Produces:
  - `Future<void> showFeedProductLinksSheet(BuildContext context, {required List<FeedProductLink> products, required void Function(FeedProductLink) onOpenProduct, required void Function(FeedProductLink) onAddToCart, VoidCallback? onOpened, VoidCallback? onClosed})`

- [ ] **Step 1: Write the failing test**

```dart
// flutter_app/test/features/feed/widgets/feed_product_links_sheet_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_product_links_sheet.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';

FeedProductLink _link(String name) => FeedProductLink(
      id: name, slug: name, name: name, price: 10000, stock: 5);

void main() {
  testWidgets('opens grid, fires onOpened, cards call callbacks',
      (tester) async {
    final products = [_link('A'), _link('B'), _link('C')];
    FeedProductLink? added;
    FeedProductLink? opened;
    var openedFired = false, closedFired = false;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showFeedProductLinksSheet(
                context,
                products: products,
                onOpenProduct: (l) => opened = l,
                onAddToCart: (l) => added = l,
                onOpened: () => openedFired = true,
                onClosed: () => closedFired = true,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pump(); // start sheet route
    await tester.pump(const Duration(milliseconds: 400)); // settle-ish, no shimmer settle
    expect(openedFired, isTrue);
    expect(find.text('Produk (3)'), findsOneWidget);
    expect(find.byType(FeedProductGridCard), findsNWidgets(3));

    await tester.tap(find.byIcon(Icons.shopping_cart_outlined).first);
    expect(added?.name, 'A');

    await tester.tap(find.text('A'));
    await tester.pump();
    expect(opened?.name, 'A'); // sheet popped + onOpenProduct invoked
    await tester.pump(const Duration(milliseconds: 400));
    expect(closedFired, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd flutter_app && flutter test test/features/feed/widgets/feed_product_links_sheet_test.dart`
Expected: FAIL — `showFeedProductLinksSheet` belum ada.

- [ ] **Step 3: Write minimal implementation**

Tambah import di atas `feed_product_links_sheet.dart`:

```dart
import '../../../widgets/compact_commerce_product_card.dart' show commerceGridSurfaceTint;
import '../../../widgets/sheet_drag_handle.dart';
```

Tambah di bawah `FeedProductGridCard`:

```dart
/// Sheet Links ala TikTok — grid 2 kolom produk tag. Draggable (naik/ikut jari,
/// snap), latar abu muda supaya kartu putih menonjol. Pemanggil (host feed)
/// bertanggung jawab menjeda video via [onOpened]/[onClosed].
Future<void> showFeedProductLinksSheet(
  BuildContext context, {
  required List<FeedProductLink> products,
  required void Function(FeedProductLink) onOpenProduct,
  required void Function(FeedProductLink) onAddToCart,
  VoidCallback? onOpened,
  VoidCallback? onClosed,
}) {
  onOpened?.call();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.40),
    enableDrag: false, // DraggableScrollableSheet yang pegang gesture
    builder: (sheetContext) => _FeedProductLinksSheet(
      products: products,
      onOpenProduct: (link) {
        Navigator.of(sheetContext).pop();
        onOpenProduct(link);
      },
      onAddToCart: onAddToCart,
    ),
  ).whenComplete(() => onClosed?.call());
}

class _FeedProductLinksSheet extends StatelessWidget {
  final List<FeedProductLink> products;
  final void Function(FeedProductLink) onOpenProduct;
  final void Function(FeedProductLink) onAddToCart;

  const _FeedProductLinksSheet({
    required this.products,
    required this.onOpenProduct,
    required this.onAddToCart,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.66,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: commerceGridSurfaceTint(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                const SheetDragHandle(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                  child: Row(
                    children: [
                      Text(
                        'Produk (${products.length})',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 0.62,
                    ),
                    itemCount: products.length,
                    itemBuilder: (context, i) {
                      final product = products[i];
                      return FeedProductGridCard(
                        product: product,
                        onTap: () => onOpenProduct(product),
                        onAddToCart: () => onAddToCart(product),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
```

> `childAspectRatio: 0.62` adalah titik awal; sesuaikan bila kartu overflow saat
> device-verify (foto 1:1 + judul 2 baris + rating + harga + tombol 42). Kalau
> RenderFlow overflow di layar sempit, turunkan rasio (mis. 0.58).

- [ ] **Step 4: Run test to verify it passes**

Run: `cd flutter_app && flutter test test/features/feed/widgets/feed_product_links_sheet_test.dart`
Expected: PASS. Jika ada overflow assertion di test env, longgarkan tinggi host / turunkan `childAspectRatio`.

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/features/feed/widgets/feed_product_links_sheet.dart flutter_app/test/features/feed/widgets/feed_product_links_sheet_test.dart
git commit -m "feat(feed): FeedProductLinksSheet grid draggable (TikTok Links)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: Wire feed video → pill + sheet + pause

**Files:**
- Modify: `flutter_app/lib/features/feed/widgets/feed_video_post_view.dart`
  - enum `CoverPauseReason` (line 79) + doc block (lines 70-78)
  - state flag near `_pausedByCommentSheet` (declared ~line 384)
  - `_addFeedLinkToCart` variant branch (line 2699-2702)
  - new methods near `_onProductsTap` (after line 2687)
  - overlay call site `_ProductCommerceOverlayGroup(...)` (lines 3449-3467) → `feedProductPillFor(...)`
  - import `feed_product_links_sheet.dart`
- Test: `flutter_app/test/features/feed/widgets/feed_video_post_view_pill_test.dart` (create — reuse harness from `feed_video_post_view_test.dart`)

**Interfaces:**
- Consumes: `feedProductPillFor` (Task 3), `showFeedProductLinksSheet` (Task 5), existing `_rotatingProductsForPost`, `_featuredProductIndex`, `_managed`, `_videoController`, `_canAutoplayNow`, `_playLegacy`, `_openProductDetail`, `productService`, `_addFeedLinkToCart`
- Produces: `CoverPauseReason.productSheet`; methods `_openProductLinksSheet`, `_pauseForProductSheet`, `_resumeAfterProductSheet`, `_openProductLinkDetail`

- [ ] **Step 1: Write the failing test**

Buat file baru meniru harness `feed_video_post_view_test.dart`. Fakta harness terverifikasi:
- Salin `_FakeVideoPlayerPlatform` (test:34, ctor `{this.manualInit=false}`). Untuk HLS (.m3u8) **TIDAK perlu** `_NoopCacheManager`/`_NoopMetadataStorage` (itu hanya untuk MP4 yang lewat cache wrapper).
- `_fakeVideoPost` (test:388) **belum** menerima produk — tambah param `List<Map<String,dynamic>>? taggedProducts` lalu inject key `'taggedProducts'` ke map JSON-nya (FeedPost.fromJson feed_post.dart:584 membaca `json['taggedProducts']`; tiap elemen boleh map produk datar atau `{'product': {...}}`; **`id` wajib** atau `FeedProductLink.fromJson` throw).
- **Tidak ada** wrapper bersama yang forward `onRequestPause`/`onRequestPlay`/`coordinator`. Jangan pakai `_hostVideo` (fiktif) — pakai `pumpWidget(MaterialApp(home: Scaffold(body: FeedVideoPostView(...))))` inline meniru pola test:973-983 + wiring pause inline test:1079-1082 (`onRequestPause: (r)=>..., onRequestPlay: ()=>...`), teruskan `post`, `isActive:true`, `playbackManagedExternally:true`, `onOverlayStateChanged:(_){}`, `onMediaZoomChanged:(_){}`.
- setUp: `SharedPreferences.setMockInitialValues(<String,Object>{});` + `VisibilityDetectorController.instance.updateInterval = Duration.zero;` + `VideoPlayerPlatform.instance = _FakeVideoPlayerPlatform();` + `await appSettingsStore.setFeedAutoplay(true);`. `cartStore` **tak** ada di harness ini — import `package:natalo_petshop_flutter/state/cart_store.dart` + `await cartStore.clear();` hanya bila menguji add-to-cart.

Assertion inti (ganti `_hostVideo(...)` dengan pumpWidget inline di atas):

```dart
// flutter_app/test/features/feed/widgets/feed_video_post_view_pill_test.dart

// ... di dalam group (pumpWidget inline, BUKAN _hostVideo):
testWidgets('pill tap opens links sheet and requests pause (managed)',
    (tester) async {
  CoverPauseReason? pausedReason;
  var resumed = false;
  final post = _fakeVideoPost(hls: true, taggedProducts: [
    {'id': '1', 'slug': 'a', 'name': 'Produk A', 'price': 55000,
     'discountPrice': 44500, 'stock': 10},
    {'id': '2', 'slug': 'b', 'name': 'Produk B', 'price': 30000, 'stock': 5},
  ]);
  await tester.pumpWidget(_hostVideo(
    post: post,
    isActive: true,
    playbackManagedExternally: true,
    onRequestPause: (r) => pausedReason = r,
    onRequestPlay: () => resumed = true,
  ));
  // bounded pump loop (JANGAN pumpAndSettle)
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.text('Produk A').evaluate().isNotEmpty) break;
  }
  expect(find.text('·2'), findsOneWidget); // pill count

  await tester.tap(find.text('Produk A'));
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.text('Produk (2)').evaluate().isNotEmpty) break;
  }
  expect(find.text('Produk (2)'), findsOneWidget); // sheet open
  expect(pausedReason, CoverPauseReason.productSheet);

  // close sheet -> resume
  await tester.tap(find.byIcon(Icons.close_rounded));
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (resumed) break;
  }
  expect(resumed, isTrue);
});
```

(Signature `_hostVideo` menyesuaikan pembungkus `FeedVideoPostView` di harness yang ada; gunakan pembungkus setara dari `feed_video_post_view_test.dart`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `cd flutter_app && flutter test test/features/feed/widgets/feed_video_post_view_pill_test.dart`
Expected: FAIL — masih render anchor card lama (`·2`/`Produk (2)`/`productSheet` belum ada).

- [ ] **Step 3a: Add enum value + doc**

Ubah baris 78-79 di `feed_video_post_view.dart`:

```dart
///  - [commentSheetFull] → `pauseAll` (comment sheet full menutup video).
///  - [productSheet] → `pauseAll` (sheet Links produk terbuka menutup video).
enum CoverPauseReason { routePush, appBackground, commentSheetFull, productSheet }
```

(Host `scoped_video_feed_screen.dart:736` sudah `onRequestPause: (_) => pauseAll()` — abaikan reason, tak perlu diubah.)

- [ ] **Step 3b: Add state flag**

Dekat deklarasi `bool _pausedByCommentSheet` (~line 384), tambah:

```dart
bool _pausedByProductSheet = false;
```

- [ ] **Step 3c: Add methods** (setelah `_onProductsTap`, sebelum `_quickAddProduct`, ~line 2688)

```dart
  Future<void> _openProductLinksSheet(List<FeedProductLink> products) async {
    if (products.isEmpty) return;
    AppHaptics.tap();
    await showFeedProductLinksSheet(
      context,
      products: products,
      onOpenProduct: (link) => _openProductLinkDetail(link),
      onAddToCart: (link) => _addFeedLinkToCart(link),
      onOpened: () {
        widget.onOverlayStateChanged(true);
        _pauseForProductSheet();
      },
      onClosed: () {
        widget.onOverlayStateChanged(false);
        _resumeAfterProductSheet();
      },
    );
  }

  void _pauseForProductSheet() {
    if (_managed) {
      if (!_pausedByProductSheet) {
        _pausedByProductSheet = true;
        widget.onRequestPause?.call(CoverPauseReason.productSheet);
      }
      return;
    }
    final ctrl = _videoController;
    if (!_pausedByProductSheet &&
        ctrl != null &&
        ctrl.value.isInitialized &&
        ctrl.value.isPlaying) {
      _pausedByProductSheet = true;
      ctrl.pause();
    }
  }

  void _resumeAfterProductSheet() {
    if (!_pausedByProductSheet) return;
    _pausedByProductSheet = false;
    if (_managed) {
      widget.onRequestPlay?.call();
      return;
    }
    final ctrl = _videoController;
    if (_canAutoplayNow() && ctrl != null && ctrl.value.isInitialized) {
      unawaited(_playLegacy(ctrl, 'product-sheet-close'));
    }
  }

  Future<void> _openProductLinkDetail(FeedProductLink link) async {
    final product = await productService.fetchProductBySlug(link.slug);
    if (!mounted) return;
    if (product == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Produk tidak ditemukan.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    _openProductDetail(product);
  }
```

- [ ] **Step 3d: Route variant to detail (D13)**

Ubah `_addFeedLinkToCart` cabang varian (lines 2699-2702):

```dart
    if (link.hasVariants) {
      _openProductLinkDetail(link);
      return;
    }
```

- [ ] **Step 3e: Add import** (bagian import atas file)

```dart
import 'feed_product_links_sheet.dart';
```

- [ ] **Step 3f: Repoint overlay call site to pill**

Ganti blok `_ProductCommerceOverlayGroup(...)` (lines 3449-3467) dengan:

```dart
                                                child: feedProductPillFor(
                                                  products,
                                                  _featuredProductIndex,
                                                  onTap: () =>
                                                      _openProductLinksSheet(
                                                    products,
                                                  ),
                                                ),
```

(Biarkan `_ProductCommerceOverlayGroup`, `_EndOfVideoProductCta`, dll untuk saat ini — dihapus di Task 7. `feedProductPillFor` sudah ter-import via `feed_post_shared_widgets.dart` yang sudah dipakai file ini.)

- [ ] **Step 4: Run test to verify it passes**

Run: `cd flutter_app && flutter test test/features/feed/widgets/feed_video_post_view_pill_test.dart`
Expected: PASS. Lalu `cd flutter_app && flutter analyze` — akan muncul warning "unused" untuk EOV (dibersihkan Task 7); pastikan **tak ada error**.

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/features/feed/widgets/feed_video_post_view.dart flutter_app/test/features/feed/widgets/feed_video_post_view_pill_test.dart
git commit -m "feat(feed): video overlay pakai pill + sheet Links yang pause video

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: Hapus kartu akhir-video (`_EndOfVideoProductCta`) + dead code

**Files:**
- Modify: `flutter_app/lib/features/feed/widgets/feed_video_post_view.dart`

**Interfaces:**
- Consumes: hasil Task 6 (pill sudah menggantikan overlay group di call site)
- Produces: tak ada simbol baru; menghapus `_ProductCommerceOverlayGroup`, `_EndOfVideoProductCta`, `_ProductCardArrowPointer`, state `_endOfVideoCtaVisible` + pemicunya, `_dismissEndOfVideoCta`, `_quickAddProduct` (bila sudah tak dipakai)

- [ ] **Step 1: Identify dead symbols**

Run: `cd flutter_app && flutter analyze` — catat semua warning "unused element/field" di `feed_video_post_view.dart` setelah Task 6 (a.l. `_ProductCommerceOverlayGroup`, `_EndOfVideoProductCta`, `_ProductCardArrowPointer`, `_endOfVideoCtaVisible`, `_dismissEndOfVideoCta`, `_quickAddProduct`, mungkin `_onProductsTap`).

- [ ] **Step 2: Delete the end-of-video CTA classes + dead state**

Hapus definisi kelas `_ProductCommerceOverlayGroup` (lines 3974-4034), `_EndOfVideoProductCta` (~line 4415, sampai akhir kelasnya), dan `_ProductCardArrowPointer`. Hapus field `_endOfVideoCtaVisible` (deklarasi :406) + baris yang men-set-nya `true` di `_handleVideoPositionForCta` (:1268-1289 — dipicu **mid-video** saat posisi melewati `min(4000ms, durasi/2)`, bukan saat video selesai; hapus juga pemanggilan `_handleVideoPositionForCta` bila jadi tak terpakai) dan method `_dismissEndOfVideoCta` (:1316). Hapus `_quickAddProduct` (:2689) dan `_onProductsTap` (:2657) **hanya jika** `flutter analyze` menandainya unused (grep dulu: `git grep -n "_quickAddProduct\|_onProductsTap\|_handleVideoPositionForCta" flutter_app/lib/features/feed/widgets/feed_video_post_view.dart`).

> JANGAN hapus `_commentSheetOpen` (dipakai comment sheet), `_onProductTap` /
> `FeedPostProductSheet` (masih dipakai jalur lain), atau `_addFeedLinkToCart`.

- [ ] **Step 3: Verify analyze clean + tests green**

Run: `cd flutter_app && flutter analyze`
Expected: **No issues** (tak ada unused, tak ada referensi menggantung ke simbol yang dihapus).

Run: `cd flutter_app && flutter test test/features/feed/widgets/feed_video_post_view_test.dart test/features/feed/widgets/feed_video_post_view_pill_test.dart`
Expected: PASS (harness lama tetap hijau — fixture-nya tanpa produk; pill test hijau).

- [ ] **Step 4: Commit**

```bash
git add flutter_app/lib/features/feed/widgets/feed_video_post_view.dart
git commit -m "refactor(feed): hapus _EndOfVideoProductCta + dead code (pill gantikan)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 8: Wire feed foto (`_PhotoCarouselPostView`) → pill + sheet

**Files:**
- Modify: `flutter_app/lib/screens/feed_screen.dart`
  - call site `feedPostProductAnchorCardFor(...)` (line 2343) → `feedProductPillFor(...)`
  - tambah handler `_openProductLinksSheet(products)` di state `_PhotoCarouselPostView` (tanpa pause — foto tak punya video) + `_openProductLinkDetail`
  - ubah cabang varian di twin `_addFeedLinkToCart` (foto) → `_openProductLinkDetail`
  - import `feed_product_links_sheet.dart`
- Test: `flutter_app/test/screens/feed_photo_pill_test.dart` (create, best-effort) atau perluas test foto yang ada bila lebih murah.

**Interfaces:**
- Consumes: `feedProductPillFor`, `showFeedProductLinksSheet`, twin `_rotatingProductsForPost`/`_featuredProductIndex`/`_addFeedLinkToCart`/`_openProductDetail`/`productService` di state foto
- Produces: (di state foto) `_openProductLinksSheet`, `_openProductLinkDetail`

- [ ] **Step 1: Write the failing test** (best-effort widget test)

Pump `_PhotoCarouselPostView` (atau `FeedScreen` dengan post foto ber-taggedProducts, sesuai harness foto yang ada), bounded pump loop, assert:
- pill muncul (`find.text('<nama produk featured>')`, `find.text('·N')`)
- tap pill → `find.text('Produk (N)')` muncul (sheet), `find.byType(FeedProductGridCard)` == N

Jika harness foto belum ada dan mahal dibuat, ganti Step 1-2 dengan **verifikasi manual via `flutter analyze` + reuse test video** dan catat gap di deskripsi commit (device-verify wajib).

- [ ] **Step 2: Run test to verify it fails** (bila ditulis)

Run: `cd flutter_app && flutter test test/screens/feed_photo_pill_test.dart`
Expected: FAIL — foto masih anchor card.

- [ ] **Step 3a: Add import** (feed_screen.dart, bagian import)

```dart
import '../features/feed/widgets/feed_product_links_sheet.dart';
```

- [ ] **Step 3b: Add handlers in `_PhotoCarouselPostView` state**

Salin pola dari video (tanpa pause). Letakkan dekat twin `_addFeedLinkToCart` foto:

```dart
  Future<void> _openProductLinksSheet(List<FeedProductLink> products) async {
    if (products.isEmpty) return;
    AppHaptics.tap();
    await showFeedProductLinksSheet(
      context,
      products: products,
      onOpenProduct: (link) => _openProductLinkDetail(link),
      onAddToCart: (link) => _addFeedLinkToCart(link),
      onOpened: () => widget.onOverlayStateChanged(true),
      onClosed: () => widget.onOverlayStateChanged(false),
    );
  }

  Future<void> _openProductLinkDetail(FeedProductLink link) async {
    final product = await productService.fetchProductBySlug(link.slug);
    if (!mounted) return;
    if (product == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Produk tidak ditemukan.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    _openProductDetail(product);
  }
```

> Cek nama exact twin di feed_screen.dart: `_addFeedLinkToCart`, `_openProductDetail`,
> `productService`, `widget.onOverlayStateChanged` — sesuaikan bila berbeda. Jika
> foto tak punya `onOverlayStateChanged`, hilangkan callback `onOpened`/`onClosed`.

- [ ] **Step 3c: Route variant to detail (twin)**

Di twin `_addFeedLinkToCart` foto, ubah cabang `if (link.hasVariants)` agar memanggil `_openProductLinkDetail(link)` (konsisten dgn video D13).

- [ ] **Step 3d: Repoint call site to pill** (feed_screen.dart:2343)

Ganti `feedPostProductAnchorCardFor(featuredProduct, onTap: ..., onAddToCart: ...)` dengan:

```dart
                                    child: feedProductPillFor(
                                      products,
                                      _featuredProductIndex,
                                      onTap: () =>
                                          _openProductLinksSheet(products),
                                    ),
```

> `products` = hasil `_rotatingProductsForPost(...)` di scope build foto (cek nama
> variabel lokalnya; mungkin sudah dihitung, atau panggil helper twin).

- [ ] **Step 4: Run test + analyze**

Run: `cd flutter_app && flutter analyze`
Expected: No issues.

Run: `cd flutter_app && flutter test test/screens/feed_photo_pill_test.dart` (bila ada)
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/screens/feed_screen.dart flutter_app/test/screens/feed_photo_pill_test.dart
git commit -m "feat(feed): postingan foto pakai pill + sheet Links (paritas video)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 9: Regression — suite penuh + tes fullscreen scoped

**Files:**
- Verify/Modify: `flutter_app/test/screens/member_post_detail_screen_fullscreen_test.dart` (line ~373-378) bila perlu

**Interfaces:**
- Consumes: seluruh hasil Task 1-8

- [ ] **Step 1: Run the full feed test suite**

Run: `cd flutter_app && flutter test test/features/feed test/screens/member_post_detail_screen_fullscreen_test.dart test/feed_product_anchor_card_test.dart test/feed_post_preview_screen_test.dart`
Expected: Sebagian besar PASS. `feed_product_anchor_card_test` & `feed_post_preview_screen_test` **tetap hijau** (anchor card dipertahankan untuk preview).

- [ ] **Step 2: Fix fullscreen scoped assertion if needed**

`member_post_detail_screen_fullscreen_test.dart` render scoped feed (`FeedVideoPostView`) → kini pill. Assertion `find.text('Magic Bites 1KG')` **harus tetap lolos** karena pill menampilkan nama produk featured. Jika gagal (mis. karena rotasi/ellipsis), ubah assertion menjadi:

```dart
      // Pill menampilkan nama produk featured; jika 1 produk, statis.
      expect(find.text('Magic Bites 1KG'), findsOneWidget,
          reason: 'pill harus menampilkan nama produk tag');
```

atau, bila layout memotong teks, tap pill lalu assert nama di dalam sheet:

```dart
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find.text('Magic Bites 1KG').evaluate().isNotEmpty) break;
      }
      expect(find.text('Magic Bites 1KG'), findsOneWidget);
```

- [ ] **Step 3: Full analyze + broad test**

Run: `cd flutter_app && flutter analyze`
Expected: No issues.

Run: `cd flutter_app && flutter test`
Expected: PASS (seluruh suite). Perbaiki regresi tak terduga sebelum lanjut.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "test(feed): regresi pill+sheet — suite penuh hijau

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Catatan device-verify (setelah semua task, sebelum rilis)

Verifikasi manual di iOS + Android (tak tercakup unit/widget test):
- Pill terbaca di latar terang & gelap; rotasi judul ±2.5s saat >1 produk, statis saat 1.
- Badge `Diskon s/d N%` muncul hanya saat ada promo; angka = maksimum.
- Tap pill → sheet naik ikut jari + snap; video **jeda**; tutup → video **lanjut** (cek tak ada audio-hantu di main feed legacy DAN scoped feed managed).
- Kartu grid: foto 1:1 cover tanpa double-round; `-N%`, harga coret+merah, rating•terjual sembunyi saat 0; tak overflow di layar sempit (sesuaikan `childAspectRatio`).
- Tap kartu → detail produk; produk varian → detail (pilih varian); stock 0 → tombol disabled.
- Postingan foto: paritas perilaku dengan video (tanpa jeda).

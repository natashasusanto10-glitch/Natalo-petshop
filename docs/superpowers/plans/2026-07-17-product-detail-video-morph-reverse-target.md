# Detail Produk — reverse-target morph video Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Saat menutup viewer video dari "Postingan Terkait" di Detail Produk, morph mengecil balik ke thumbnail post yang sedang tampil (bukan yang pertama di-tap) dan rail auto-scroll ke sana — paritas perilaku Instagram.

**Architecture:** Ekstrak controller kecil `RelatedPostsRail` ke file publik sendiri (bebas jaringan, bisa diuji unit). Kedua permukaan yang me-render `_CustomerPostCard` (rail `_ProductCustomerPostsSection` + layar "Lihat semua" `_ProductCustomerPostsScreen`) memiliki satu instance controller, memasang `scroll`-nya ke list/grid, dan meneruskannya ke kartu. Kartu memakai `controller.keyFor(postId)` untuk key thumbnail dan, di jalur video, meneruskan `reverseTarget`/`reverseMorphEnabled` ke `pushScaledVideoFeed` — mengikuti pola `member_post_detail_screen.dart:966`.

**Tech Stack:** Flutter/Dart, `flutter_test`.

## Global Constraints

- Tanpa warm handoff: `coordinator: null`, `originPostId: null` pada `pushScaledVideoFeed`.
- `thumbnailBorderRadius: 14` (nilai eksisting kartu).
- `Scrollable.ensureVisible` memakai `duration: Duration.zero` (instan, morph menutupi scroll).
- Tidak mengubah: tampilan kartu, thumbnail, jalur tap-foto (non-video), fetch siblings, durasi/kurva morph (260/220ms).
- Return type route: `ScaledVideoFeedReverseTarget` dari `lib/widgets/scaled_video_feed_route.dart`; hasil push bertipe `ScopedVideoFeedResult` dari `lib/screens/scoped_video_feed_screen.dart`.

---

### Task 1: Controller `RelatedPostsRail` (unit teruji, bebas jaringan)

**Files:**
- Create: `flutter_app/lib/widgets/related_posts_rail.dart`
- Test: `flutter_app/test/widgets/related_posts_rail_test.dart`

**Interfaces:**
- Consumes: `ScaledVideoFeedReverseTarget` dari `package:.../widgets/scaled_video_feed_route.dart`.
- Produces:
  - `class RelatedPostsRail` dengan:
    - `final ScrollController scroll`
    - `GlobalKey keyFor(String postId)` — memoized, key stabil per-post.
    - `Future<ScaledVideoFeedReverseTarget?> resolveReturnTarget(String postId, {required String imageUrl, double borderRadius = 14})`
    - `void dispose()` — dispose `scroll`.

- [ ] **Step 1: Tulis test yang gagal**

Buat `flutter_app/test/widgets/related_posts_rail_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/widgets/related_posts_rail.dart';

Widget _harness(RelatedPostsRail rail, List<String> ids) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 190,
        child: ListView.builder(
          controller: rail.scroll,
          scrollDirection: Axis.horizontal,
          itemCount: ids.length,
          itemBuilder: (context, i) => SizedBox(
            key: rail.keyFor(ids[i]),
            width: 118,
            child: ColoredBox(color: Colors.black, child: Text(ids[i])),
          ),
        ),
      ),
    ),
  );
}

void main() {
  test('keyFor mengembalikan key yang sama untuk id yang sama', () {
    final rail = RelatedPostsRail();
    expect(identical(rail.keyFor('a'), rail.keyFor('a')), isTrue);
    expect(identical(rail.keyFor('a'), rail.keyFor('b')), isFalse);
    rail.dispose();
  });

  testWidgets('resolveReturnTarget mengukur rect kartu yang terlihat',
      (tester) async {
    final rail = RelatedPostsRail();
    final ids = List.generate(20, (i) => 'id-$i');
    await tester.pumpWidget(_harness(rail, ids));
    await tester.pumpAndSettle();

    final target = await rail.resolveReturnTarget('id-0', imageUrl: 'x');
    await tester.pumpAndSettle();

    expect(target, isNotNull);
    expect(target!.imageUrl, 'x');
    expect(target.borderRadius, 14);
    expect(target.rect.width, closeTo(118, 1));
    rail.dispose();
  });

  testWidgets('resolveReturnTarget men-scroll kartu jauh agar terlihat',
      (tester) async {
    final rail = RelatedPostsRail();
    final ids = List.generate(20, (i) => 'id-$i');
    await tester.pumpWidget(_harness(rail, ids));
    await tester.pumpAndSettle();
    expect(rail.scroll.offset, 0);

    final target = await rail.resolveReturnTarget('id-18', imageUrl: 'x');
    await tester.pumpAndSettle();

    expect(rail.scroll.offset, greaterThan(0));
    expect(target, isNotNull);
    rail.dispose();
  });

  testWidgets('resolveReturnTarget mengembalikan null untuk id tak dikenal',
      (tester) async {
    final rail = RelatedPostsRail();
    await tester.pumpWidget(_harness(rail, ['id-0']));
    await tester.pumpAndSettle();

    final target = await rail.resolveReturnTarget('hantu', imageUrl: 'x');
    expect(target, isNull);
    rail.dispose();
  });
}
```

> Nama paket terverifikasi: `natalo_petshop_flutter` (dari `flutter_app/pubspec.yaml`).

- [ ] **Step 2: Jalankan test — pastikan GAGAL**

Run: `cd flutter_app && flutter test test/widgets/related_posts_rail_test.dart`
Expected: FAIL — `related_posts_rail.dart` / `RelatedPostsRail` belum ada (compile error).

- [ ] **Step 3: Implementasi minimal**

Buat `flutter_app/lib/widgets/related_posts_rail.dart`:

```dart
import 'package:flutter/material.dart';

import 'scaled_video_feed_route.dart';

/// Koordinator kecil untuk rail "Postingan Terkait": menyimpan key stabil
/// per-post sehingga kartu manapun bisa menemukan rect kartu lain, dan
/// menyediakan target morph-balik saat viewer video ditutup.
class RelatedPostsRail {
  final ScrollController scroll = ScrollController();
  final Map<String, GlobalKey> _keys = {};

  /// Key stabil (memoized) untuk thumbnail sebuah post.
  GlobalKey keyFor(String postId) =>
      _keys.putIfAbsent(postId, () => GlobalKey());

  /// Scroll kartu [postId] agar terlihat, ukur rect-nya, dan bangun target
  /// morph-balik. Mengembalikan null bila kartu tidak ter-render (mis. post
  /// dari load-more yang belum ada di rail) — route jatuh ke morph default.
  Future<ScaledVideoFeedReverseTarget?> resolveReturnTarget(
    String postId, {
    required String imageUrl,
    double borderRadius = 14,
  }) async {
    final key = _keys[postId];
    final context = key?.currentContext;
    if (context == null) return null;

    await Scrollable.ensureVisible(
      context,
      duration: Duration.zero,
      alignment: 0.5,
    );
    await WidgetsBinding.instance.endOfFrame;

    final box = key!.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return ScaledVideoFeedReverseTarget(
      rect: box.localToGlobal(Offset.zero) & box.size,
      imageUrl: imageUrl,
      borderRadius: borderRadius,
    );
  }

  void dispose() => scroll.dispose();
}
```

- [ ] **Step 4: Jalankan test — pastikan LULUS**

Run: `cd flutter_app && flutter test test/widgets/related_posts_rail_test.dart`
Expected: PASS (4 test).

- [ ] **Step 5: Analyze + commit**

```bash
cd flutter_app && flutter analyze lib/widgets/related_posts_rail.dart test/widgets/related_posts_rail_test.dart
git add flutter_app/lib/widgets/related_posts_rail.dart flutter_app/test/widgets/related_posts_rail_test.dart
git commit -m "feat(product): controller RelatedPostsRail untuk reverse-target morph"
```

---

### Task 2: Wire controller ke Detail Produk (rail + "Lihat semua")

**Files:**
- Modify: `flutter_app/lib/screens/product_detail_screen.dart`
  - `_ProductCustomerPostsSection` (~2375): Stateless → Stateful, punya `RelatedPostsRail`.
  - `_ProductCustomerPostsScreenState` (~2488): tambah `RelatedPostsRail`, pakai `rail.scroll` untuk `GridView`.
  - `_CustomerPostCard` (~2656): terima `rail`, pakai `rail.keyFor(post.id)`, jalur video pakai `reverseTarget`/`reverseMorphEnabled`.

**Interfaces:**
- Consumes: `RelatedPostsRail`, `ScaledVideoFeedReverseTarget`, `ScopedVideoFeedResult`.
- Produces: (tidak ada API baru untuk task lain.)

- [ ] **Step 1: Import controller**

Di bagian import `product_detail_screen.dart`, tambahkan (samakan gaya import relatif/absolut dengan import lain di file ini):

```dart
import '../widgets/related_posts_rail.dart';
```

Pastikan `scaled_video_feed_route.dart` dan `scoped_video_feed_screen.dart` sudah ter-import (untuk `ScaledVideoFeedReverseTarget`/`ScopedVideoFeedResult`); jika belum, tambahkan importnya.

- [ ] **Step 2: `_ProductCustomerPostsSection` → Stateful dengan rail**

Ganti deklarasi `class _ProductCustomerPostsSection extends StatelessWidget` menjadi Stateful, pertahankan field `posts/total/loading/onViewAll`:

```dart
class _ProductCustomerPostsSection extends StatefulWidget {
  final List<_ProductCustomerPost> posts;
  final int total;
  final bool loading;
  final VoidCallback onViewAll;

  const _ProductCustomerPostsSection({
    required this.posts,
    required this.total,
    required this.loading,
    required this.onViewAll,
  });

  @override
  State<_ProductCustomerPostsSection> createState() =>
      _ProductCustomerPostsSectionState();
}

class _ProductCustomerPostsSectionState
    extends State<_ProductCustomerPostsSection> {
  final RelatedPostsRail _rail = RelatedPostsRail();

  @override
  void dispose() {
    _rail.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.loading && widget.posts.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    // ... (isi Column/Row/Text SAMA seperti sebelumnya, ganti setiap
    //      `posts`/`total`/`loading`/`onViewAll` menjadi `widget.posts` dst.)
    // Pada ListView.separated:
    //   controller: _rail.scroll,
    //   itemBuilder: (context, index) => _CustomerPostCard(
    //       post: widget.posts[index],
    //       allPosts: widget.posts,
    //       index: index,
    //       rail: _rail,
    //   ),
  }
}
```

Terapkan penggantian `posts→widget.posts`, `total→widget.total`, `loading→widget.loading`, `onViewAll→widget.onViewAll` di seluruh body build yang lama, tambahkan `controller: _rail.scroll` ke `ListView.separated`, dan tambahkan `rail: _rail` ke pemanggilan `_CustomerPostCard`.

- [ ] **Step 3: `_ProductCustomerPostsScreenState` pakai rail**

Di `_ProductCustomerPostsScreenState`, ganti `final ScrollController _controller = ScrollController();` menjadi memakai rail, agar key & scroll konsisten dengan resolusi target:

```dart
final RelatedPostsRail _rail = RelatedPostsRail();
ScrollController get _controller => _rail.scroll;
```

Di `dispose()` ganti `_controller..removeListener(_handleScroll)..dispose();` menjadi:

```dart
_controller.removeListener(_handleScroll);
_rail.dispose();
```

Pada `GridView.builder`, `controller: _controller` tetap (kini menunjuk `_rail.scroll`). Pada pemanggilan `_CustomerPostCard` (~2599) tambahkan `rail: _rail`.

- [ ] **Step 4: `_CustomerPostCard` terima rail + pakai keyFor**

Ubah field & konstruktor `_CustomerPostCard`; buang `_thumbnailKey` lokal:

```dart
class _CustomerPostCard extends StatelessWidget {
  final _ProductCustomerPost post;
  final List<_ProductCustomerPost> allPosts;
  final int index;
  final RelatedPostsRail rail;

  const _CustomerPostCard({
    required this.post,
    required this.allPosts,
    required this.index,
    required this.rail,
  });
```

Di `build`, ganti `key: _thumbnailKey` pada `ClipRRect` thumbnail menjadi `key: rail.keyFor(post.id)`.

- [ ] **Step 5: Jalur video pakai reverse-target**

Di `_openPost`, ganti blok video (mulai `final tappedIndex = fetched.indexWhere(...)` s/d `pushScaledVideoFeed(...)`) menjadi:

```dart
    final tappedIndex = fetched.indexWhere((fp) => fp.id == post.id);
    final reverseMorphEnabled = ValueNotifier<bool>(true);
    final reverseTarget = ValueNotifier<ScaledVideoFeedReverseTarget?>(null);
    try {
      await pushScaledVideoFeed<ScopedVideoFeedResult>(
        context,
        thumbnailKey: rail.keyFor(post.id),
        thumbnailImageUrl: post.thumbnailUrl,
        thumbnailBorderRadius: 14,
        reverseMorphEnabled: reverseMorphEnabled,
        reverseTarget: reverseTarget,
        destinationBuilder: (_) => ScopedVideoFeedScreen(
          posts: fetched,
          initialIndex: tappedIndex >= 0 ? tappedIndex : 0,
          coordinator: null,
          originPostId: null,
          onActivePostChanged: (id) {
            reverseMorphEnabled.value = id == post.id;
          },
          onPrepareClose: (result, _) async {
            final returned = allPosts.cast<_ProductCustomerPost?>().firstWhere(
                  (p) => p?.id == result.postId,
                  orElse: () => null,
                );
            if (returned == null) return;
            reverseTarget.value = await rail.resolveReturnTarget(
              result.postId,
              imageUrl: returned.thumbnailUrl,
            );
            reverseMorphEnabled.value = true;
          },
        ),
      );
    } finally {
      reverseMorphEnabled.dispose();
      reverseTarget.dispose();
    }
```

> `onPrepareClose` signature: `Future<void> Function(ScopedVideoFeedResult result, <CloseSignal> signal)` — cek tipe param kedua di `scoped_video_feed_screen.dart` (sekitar baris 88-92) dan pakai `_` bila tak dipakai. Jangan meluncurkan seek/scroll kedua di sini.

- [ ] **Step 6: Analyze**

Run: `cd flutter_app && flutter analyze lib/screens/product_detail_screen.dart`
Expected: No issues (0 error). Perbaiki bila ada referensi `_thumbnailKey`/`_controller` yang tertinggal.

- [ ] **Step 7: Test regresi rail controller + suite widget terdampak**

Run: `cd flutter_app && flutter test test/widgets/related_posts_rail_test.dart test/screens/product_detail_screen_related_posts_test.dart`
Expected: PASS (test related-posts tetap `skip: true` — tak diubah; rail test hijau).

- [ ] **Step 8: Commit**

```bash
git add flutter_app/lib/screens/product_detail_screen.dart
git commit -m "feat(product): morph balik video mendarat ke post yang tampil + auto-scroll rail"
```

---

## Catatan verifikasi akhir (device)

Widget test end-to-end viewer tak tersedia (tak ada seam DI jaringan di `ProductDetailScreen` — lihat header `product_detail_screen_related_posts_test.dart`). Logika inti (`resolveReturnTarget`, key stabil, scroll-into-view) tercakup unit test Task 1. Paritas visual final butuh **device-verify**: tap video Postingan Terkait → swipe ke video lain → tutup → morph harus mengecil ke thumbnail post yang tampil, rail tergeser ke sana.

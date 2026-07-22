# PostViewerRoute Hero Rewrite — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ganti transisi grid→viewer custom (`OriginExpansionRoute`) dengan `Hero` bawaan Flutter di semua origin (Profil sendiri, Profil publik, Postingan Saya, Postingan Tersimpan); composer `+` pindah ke route fade standar; `origin_expansion_route.dart` dihapus total.

**Architecture:** Widget bersama `PostHero` (tag ter-scope + `transitionOnUserGestures: true` + shuttle radius-lerp) dipasang di tile grid dan slot media viewer. Route baru `PostViewerRoute` = `PageRouteBuilder` fade standar (chrome fade, hero terbang di overlay framework). Reverse target = post aktif: viewer memanggil callback `onWillClose(activePostId)` saat pop dimulai; origin jumpTo posisi tile tanpa menunggu — tile absen → framework fade otomatis.

**Tech Stack:** Flutter stable (repo ini), `Hero`/`PageRouteBuilder` bawaan, `video_player` via `PostVideoCoordinator` existing.

## Global Constraints

- Kerja di worktree TERISOLASI branch BARU dari `origin/main` (JANGAN checkout utama; JANGAN branch PR #206). Setup sekali di Task 1.
- Spec: `docs/superpowers/specs/2026-07-21-post-viewer-hero-rewrite-design.md` (ada di branch `claude/postingan-full-page-zoom-8f8586`, copy masuk di Task 1).
- TDD ketat: test RED dulu (jalankan, lihat gagal), baru implementasi, lalu GREEN.
- Tiap task diakhiri: `flutter analyze` pada file tersentuh (bersih), `dart format` file tersentuh, `git diff --check`, commit.
- Test konvensi repo: `SharedPreferences.setMockInitialValues({})`, bounded pump loop (`for (var i=0;i<N;i++) await tester.pump(const Duration(milliseconds:100));`) — JANGAN `pumpAndSettle` (shimmer/video tak pernah settle).
- Semua `Hero` WAJIB `transitionOnUserGestures: true` (dua sisi). Tag WAJIB lewat `postHeroTag(scope, postId)` — jangan hardcode string.
- Jangan sentuh: feed utama, Detail Produk, fullscreen video route, `PostVideoCoordinator` internals.

---

### Task 1: Worktree + `PostHero` + `PostViewerRoute` (fondasi)

**Files:**
- Create: worktree `.worktrees/post-viewer-hero` branch `codex/post-viewer-hero` dari `origin/main`
- Create: `flutter_app/lib/features/feed/transition/post_hero.dart`
- Create: `flutter_app/lib/features/feed/transition/post_viewer_route.dart`
- Create: `docs/superpowers/specs/2026-07-21-post-viewer-hero-rewrite-design.md` (copy dari branch `claude/postingan-full-page-zoom-8f8586`, commit `5112db3c`)
- Test: `flutter_app/test/features/feed/transition/post_hero_test.dart`

**Interfaces:**
- Produces: `String postHeroTag(String scope, String postId)` → `'post-hero/$scope/$postId'`.
- Produces: `class PostHero extends StatelessWidget` — ctor `const PostHero({super.key, required String scope, required String postId, BorderRadius borderRadius = BorderRadius.zero, required Widget child})`.
- Produces: `class PostViewerRoute<T> extends PageRouteBuilder<T>` — ctor `PostViewerRoute({required WidgetBuilder builder})`; fade 280ms buka / 240ms tutup, `opaque: true`, back-swipe iOS standar aktif.
- Produces: helper `Future<T?> pushPostViewer<T>(BuildContext context, {required WidgetBuilder builder})`.

- [ ] **Step 1: Setup worktree**

```bash
cd C:/Users/USER/Desktop/natalopetshopflutter
git fetch origin main
git worktree add .worktrees/post-viewer-hero -b codex/post-viewer-hero origin/main
cd .worktrees/post-viewer-hero
git show 5112db3c:docs/superpowers/specs/2026-07-21-post-viewer-hero-rewrite-design.md > docs/superpowers/specs/2026-07-21-post-viewer-hero-rewrite-design.md
git add docs/superpowers/specs/2026-07-21-post-viewer-hero-rewrite-design.md
git commit -m "docs(postingan): spec rewrite transisi grid-viewer ke Hero bawaan"
```

- [ ] **Step 2: Test RED**

```dart
// test/features/feed/transition/post_hero_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_app/features/feed/transition/post_hero.dart';
import 'package:natalo_app/features/feed/transition/post_viewer_route.dart';

void main() {
  testWidgets('postHeroTag ter-scope dan unik per permukaan', (tester) async {
    expect(postHeroTag('profile', 'p1'), 'post-hero/profile/p1');
    expect(postHeroTag('saved', 'p1'), isNot(postHeroTag('profile', 'p1')));
  });

  testWidgets('PostHero memasang Hero dengan transitionOnUserGestures true', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: PostHero(scope: 'profile', postId: 'p1', child: SizedBox(width: 10, height: 10)),
    ));
    final hero = tester.widget<Hero>(find.byType(Hero));
    expect(hero.tag, 'post-hero/profile/p1');
    expect(hero.transitionOnUserGestures, isTrue);
    expect(hero.flightShuttleBuilder, isNotNull);
  });

  testWidgets('push PostViewerRoute menerbangkan hero tile ke slot (shuttle hadir mid-flight)', (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navKey,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: PostHero(scope: 'profile', postId: 'p1',
            child: SizedBox(width: 40, height: 40, child: ColoredBox(color: Colors.blue, key: const Key('tile-media')))),
        ),
      ),
    ));
    navKey.currentState!.push(PostViewerRoute<void>(builder: (_) => const Scaffold(
      body: Center(child: PostHero(scope: 'profile', postId: 'p1',
        child: SizedBox(width: 300, height: 300, child: ColoredBox(color: Colors.blue)))),
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 140)); // mid-flight
    // Hero flight = widget media digambar di overlay, ukurannya di antara 40 dan 300.
    final rects = tester.widgetList(find.byType(ColoredBox)).length;
    expect(rects, greaterThanOrEqualTo(1));
    final flightSize = tester.getSize(find.byKey(const Key('tile-media')).hitTestable(at: Alignment.center).first
        , warnIfMissed: false);
    expect(flightSize.width, greaterThan(40));
    expect(flightSize.width, lessThan(300));
    await tester.pump(const Duration(milliseconds: 400)); // selesai
  });

  testWidgets('pop tanpa pasangan tag → fade tanpa error (mode gagal jinak)', (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navKey,
      home: const Scaffold(body: SizedBox()), // grid TANPA hero
    ));
    navKey.currentState!.push(PostViewerRoute<void>(builder: (_) => const Scaffold(
      body: PostHero(scope: 'profile', postId: 'nope', child: SizedBox(width: 300, height: 300)),
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    navKey.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 3: Run RED** — `cd flutter_app && flutter test test/features/feed/transition/post_hero_test.dart` → FAIL (file lib belum ada).

- [ ] **Step 4: Implementasi**

```dart
// lib/features/feed/transition/post_hero.dart
import 'package:flutter/material.dart';

/// Tag hero ter-scope per permukaan. Tag duplikat di satu layar membuat
/// framework menonaktifkan hero DIAM-DIAM — selalu lewat helper ini.
String postHeroTag(String scope, String postId) => 'post-hero/$scope/$postId';

class PostHero extends StatelessWidget {
  const PostHero({
    super.key,
    required this.scope,
    required this.postId,
    this.borderRadius = BorderRadius.zero,
    required this.child,
  });

  final String scope;
  final String postId;
  final BorderRadius borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: postHeroTag(scope, postId),
      transitionOnUserGestures: true,
      flightShuttleBuilder: _shuttle,
      child: ClipRRect(borderRadius: borderRadius, child: child),
    );
  }

  /// Shuttle: gambar surface sisi VIEWER sepanjang penerbangan (push: tujuan,
  /// pop: asal) — untuk video berarti VideoPlayer(controller) yang sama, satu
  /// texture, tanpa swap thumbnail. Radius di-lerp antara kedua endpoint.
  static Widget _shuttle(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection direction,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    final Hero fromHero = fromHeroContext.widget as Hero;
    final Hero toHero = toHeroContext.widget as Hero;
    final Widget content =
        direction == HeroFlightDirection.push ? toHero.child : fromHero.child;
    BorderRadius radiusOf(Hero h) =>
        h.child is ClipRRect ? ((h.child as ClipRRect).borderRadius as BorderRadius) : BorderRadius.zero;
    final BorderRadius fromRadius = radiusOf(fromHero);
    final BorderRadius toRadius = radiusOf(toHero);
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) => ClipRRect(
        borderRadius: BorderRadius.lerp(fromRadius, toRadius, animation.value)!,
        child: content is ClipRRect ? (content).child : content,
      ),
    );
  }
}
```

```dart
// lib/features/feed/transition/post_viewer_route.dart
import 'package:flutter/material.dart';

/// Route standar untuk semua alur grid→viewer post. Chrome fade; media
/// terbang via [PostHero] di overlay framework. TANPA state machine, TANPA
/// pengukuran geometri manual, TANPA gesture kustom.
class PostViewerRoute<T> extends PageRouteBuilder<T> {
  PostViewerRoute({required WidgetBuilder builder})
      : super(
          transitionDuration: const Duration(milliseconds: 280),
          reverseTransitionDuration: const Duration(milliseconds: 240),
          pageBuilder: (context, animation, secondaryAnimation) => builder(context),
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            child: child,
          ),
        );
}

Future<T?> pushPostViewer<T>(BuildContext context, {required WidgetBuilder builder}) {
  return Navigator.of(context).push<T>(PostViewerRoute<T>(builder: builder));
}
```

Catatan implementer: kalau assertion mid-flight di test 3 rapuh (struktur overlay), boleh diganti assert `find.byType(Hero)` di overlay / ukuran via `tester.getSize(find.byType(ColoredBox).last)` — yang WAJIB dipertahankan: ada bukti ukuran interpolasi antara 40 dan 300 di tengah animasi, dan test 4 bebas exception.

- [ ] **Step 5: Run GREEN** — command sama → PASS.
- [ ] **Step 6: analyze + format + commit**

```bash
cd flutter_app && flutter analyze lib/features/feed/transition/ test/features/feed/transition/post_hero_test.dart
dart format lib/features/feed/transition/post_hero.dart lib/features/feed/transition/post_viewer_route.dart test/features/feed/transition/post_hero_test.dart
cd .. && git add -A && git diff --check && git commit -m "feat(postingan): PostHero + PostViewerRoute — fondasi transisi hero bawaan"
```

---

### Task 2: Viewer — slot media pakai `PostHero` (foto/carousel/VIDEO) + `heroScope` + `onWillClose`

**Files:**
- Modify: `flutter_app/lib/screens/member_post_detail_screen.dart` (ctor + `_PostMediaSurface` L2706-2780 + PopScope)
- Test: `flutter_app/test/screens/member_post_detail_hero_test.dart` (baru)

**Interfaces:**
- Consumes: `PostHero`, `postHeroTag` (Task 1).
- Produces: `MemberPostDetailScreen` param baru `String? heroScope` (null = tanpa hero, mis. deep-link) dan `void Function(String activePostId)? onWillClose`.
- Produces: slot media (photo/carousel/**video**) dibungkus `PostHero(scope: heroScope!, postId: post.id)` bila `heroScope != null`; tag lama `'post-thumb-${post.id}'` DIHAPUS dari layar ini.
- Produces: saat pop dimulai (PopScope `onPopInvokedWithResult`, `didPop == true`), panggil `widget.onWillClose?.call(<activePostId>)` SINKRON — activePostId = `_videoCoordinator.activePostId ?? widget.post.id` fallback post pertama terlihat.

- [ ] **Step 1: Test RED**

```dart
// test/screens/member_post_detail_hero_test.dart
// Konvensi: SharedPreferences.setMockInitialValues({}); debugScopedFeedPostFetcher seam;
// bounded pump. Buat FeedPost foto p1 + video p2 (pola dari member_post_detail_screen_coordinator_test.dart).
testWidgets('slot foto & video dibungkus PostHero ber-scope saat heroScope diberikan', (tester) async {
  // mount MemberPostDetailScreen(postFoto, [postFoto, postVideo], heroScope: 'profile', ...)
  // pump bounded 8x100ms
  final heroes = tester.widgetList<Hero>(find.byType(Hero)).toList();
  expect(heroes.map((h) => h.tag), contains('post-hero/profile/p1'));
  expect(heroes.every((h) => h.transitionOnUserGestures), isTrue);
  expect(find.byWidgetPredicate((w) => w is Hero && w.tag == 'post-thumb-p1'), findsNothing);
});

testWidgets('tanpa heroScope tidak ada PostHero (deep-link aman dari tag duplikat)', (tester) async {
  // mount tanpa heroScope → find Hero dengan prefix 'post-hero/' findsNothing
});

testWidgets('onWillClose menerima post AKTIF saat back', (tester) async {
  String? closedWith;
  // mount dengan onWillClose: (id) => closedWith = id; heroScope 'profile'
  // pop via tester.pageBack() atau Navigator; pump bounded
  expect(closedWith, 'p1');
});
```

- [ ] **Step 2: Run RED** — `flutter test test/screens/member_post_detail_hero_test.dart` → FAIL (param tak ada).
- [ ] **Step 3: Implementasi** — tambah 2 param ctor; di `_PostMediaSurface.build` ganti `Hero(tag:'post-thumb-…')` → wrapper kondisional:

```dart
Widget _wrapHero(Widget child, FeedPost post) {
  final scope = heroScope; // diteruskan turun dari screen ke _PostMediaSurface
  if (scope == null) return child;
  return PostHero(scope: scope, postId: post.id, child: child);
}
// photo: _wrapHero(_ImageSurface(...), post)
// carousel: _wrapHero(_CarouselSurface(...), post)
// video (BARU di-hero): _wrapHero(_InlineVideoPlayer(...), post)
```

PopScope di root screen (pertahankan handler pop yang sudah ada bila ada; gabungkan):

```dart
PopScope(
  canPop: true,
  onPopInvokedWithResult: (didPop, _) {
    if (!didPop) return;
    widget.onWillClose?.call(_videoCoordinator.activePostId ?? widget.post.id);
  },
  child: ...,
)
```

- [ ] **Step 4: Run GREEN** + regresi `flutter test test/screens/member_post_detail_screen_coordinator_test.dart`.
- [ ] **Step 5: analyze/format/diff-check/commit** — `feat(postingan): viewer pakai PostHero ber-scope + video ikut hero + onWillClose`

---

### Task 3: Origin `member_screen` — ganti route + scroll-ke-post-aktif

**Files:**
- Create: `flutter_app/lib/features/feed/transition/profile_tile_visibility.dart` — **port utuh** dari branch `codex/postingan-full-page-zoom` (`git show origin/codex/postingan-full-page-zoom:flutter_app/lib/features/feed/transition/profile_tile_visibility.dart`) — sudah direview bersih di PR #206: `ensureProfileTileVisible(BuildContext tileContext, {double topPadding = 0, double bottomPadding = 0})`, early-out bila tile penuh terlihat, minimal-move `jumpTo` pada scrollable TERDEKAT saja.
- Modify: `flutter_app/lib/screens/member_screen.dart` — `_openPostDetail` (L327-356), `_PostThumbnail` (L807-870)
- Test: port test `profile_tile_visibility_test.dart` dari branch yang sama + `flutter_app/test/screens/member_screen_hero_open_test.dart` (baru)

**Interfaces:**
- Consumes: `pushPostViewer`, `PostHero`, `postHeroTag('profile', id)` (T1); `heroScope`/`onWillClose` (T2); `ensureProfileTileVisible`.
- Produces: `_PostThumbnail` membungkus thumbnail dengan `PostHero(scope: 'profile', postId: post.id)`; `OriginSnapshotSource` + `RepaintBoundary(originKey)` + Hero `'post-thumb-'` lama DIHAPUS dari tile.
- Produces: `_openPostDetail` memanggil `pushPostViewer` dengan `heroScope: 'profile'` dan `onWillClose: (id) => _revealTile(id)` — `_revealTile` cari BuildContext tile via `_tileKeys` yang ada; bila context null (belum dibangun) cukup `jumpTo` estimasi baris `(index ~/ 3) * extent` di controller grid, TANPA menunggu.

- [ ] **Step 1: Port file + test visibility, run** — `flutter test test/features/feed/transition/profile_tile_visibility_test.dart` → PASS. Commit `feat(postingan): port ensureProfileTileVisible (reviewed) dari PR 206`.
- [ ] **Step 2: Test RED** (`member_screen_hero_open_test.dart`, pola `member_screen_profile_restore_test.dart`: mock prefs, `MemberScreen.debugMyPostsFetcher`, `memberStore.setProfile`, pumpBounded):

```dart
testWidgets('tile grid punya PostHero scope profile; tap membuka PostViewerRoute', (tester) async {
  // mount MemberScreen dgn 3 post; pumpBounded
  expect(find.byWidgetPredicate((w) => w is Hero && w.tag == 'post-hero/profile/p1'), findsOneWidget);
  // tap tile p1; pumpBounded
  // assert: MemberPostDetailScreen tampil; TIDAK ada OriginExpansionTransition di tree
});
testWidgets('back memanggil reveal tile post aktif (grid ter-scroll)', (tester) async {
  // buka p1, pop; assert tanpa exception + grid masih merender p1 terlihat
});
```

- [ ] **Step 3: Run RED → implementasi → GREEN.** Di `_PostThumbnail`: hapus `OriginSnapshotSource`/`RepaintBoundary(originKey)`, bungkus `CachedNetworkImage` dgn `PostHero(scope: 'profile', postId: post.id)`. `_openPostDetail`: ganti `pushOriginExpansion` → `pushPostViewer(context, builder: (_) => MemberPostDetailScreen(..., heroScope: 'profile', onWillClose: _revealTile))`; pertahankan warm-handoff take/dispose + `_loadAll()` sesudahnya.
- [ ] **Step 4: Regresi** `flutter test test/screens/member_screen_test.dart test/screens/member_screen_profile_restore_test.dart`.
- [ ] **Step 5: analyze/format/diff-check/commit** — `feat(postingan): member_screen buka viewer via PostViewerRoute + hero + reveal tile aktif`

---

### Task 4: Origin `public_profile_screen` + `member_posts_screen` (+ `GalleryPostTile` dukung hero)

**Files:**
- Modify: `flutter_app/lib/features/feed/widgets/gallery_post_tile.dart` — param baru `String? heroScope`; bila non-null bungkus thumbnail dgn `PostHero(scope: heroScope!, postId: post.id)`.
- Modify: `flutter_app/lib/screens/public_profile_screen.dart` (`_openPost` L572-…, `_PostTile` L1034) — scope `'publicProfile/${widget.username}'`; ganti `pushOriginExpansion`→`pushPostViewer(..., heroScope: scope, onWillClose: reveal)`.
- Modify: `flutter_app/lib/screens/member_posts_screen.dart` (L442-473, tile L605-616) — scope `'myPosts'`; sama.
- Test: `flutter_app/test/features/feed/widgets/gallery_post_tile_hero_test.dart`, tambah kasus di `public_profile_screen_test.dart` + `member_posts_screen_test.dart`.

**Interfaces:**
- Consumes: T1–T3. Produces: `GalleryPostTile.heroScope`; kedua screen buka via `pushPostViewer` dgn scope masing-masing (`publicProfile/<username>` — WAJIB mengandung username supaya profil A di atas profil B tidak bentrok tag).

- [ ] **Step 1: Test RED** — `GalleryPostTile(heroScope: 'saved', post: p)` → Hero tag `post-hero/saved/p1`; tanpa heroScope → findsNothing. Kasus screen: tag scope benar + `pushPostViewer` terpakai (assert `PostViewerRoute` di `Navigator`) + tidak ada `OriginExpansionTransition`.
- [ ] **Step 2: RED → implementasi → GREEN.** Reveal di kedua screen: cari tile context via key/`_tileKeys` yang ada → `ensureProfileTileVisible(ctx)`; bila null → `jumpTo` estimasi indeks. Hapus pemakaian originKey utk route (key tile boleh tetap utk reveal).
- [ ] **Step 3: Regresi** kedua test screen existing.
- [ ] **Step 4: analyze/format/diff-check/commit** — `feat(postingan): public profile + postingan saya via PostViewerRoute + hero`

---

### Task 5: Origin Postingan Tersimpan (`saved_posts_screen` via mixin `PostGalleryOpener`)

**Files:**
- Modify: `flutter_app/lib/features/feed/widgets/post_gallery_opener.dart` — `openPostGallery` param baru `required String heroScope`; ganti `pushOriginExpansion`→`pushPostViewer(..., heroScope: heroScope, onWillClose: …)`; `tileKeyFor` dipertahankan utk reveal.
- Modify: `flutter_app/lib/screens/saved_posts_screen.dart` — kirim `heroScope: 'saved'` + `GalleryPostTile(heroScope: 'saved', …)`.
- Test: tambah kasus di `flutter_app/test/screens/saved_posts_screen_test.dart`.

**Interfaces:** Consumes T1/T2/T4. Produces: mixin bebas dari `pushOriginExpansion`.

- [ ] **Step 1: Test RED** (mount `SavedPostsScreen(fetchPosts: …)` pola test existing): tile ber-tag `post-hero/saved/p1`; tap → `MemberPostDetailScreen` tampil via `PostViewerRoute`.
- [ ] **Step 2: RED → implementasi → GREEN → regresi suite saved existing.**
- [ ] **Step 3: analyze/format/diff-check/commit** — `feat(postingan): saved posts via PostViewerRoute + hero scope saved`

---

### Task 6: Composer `+` → fade standar; HAPUS `origin_expansion_route.dart`

**Files:**
- Modify: `flutter_app/lib/screens/feed_media_picker_screen.dart` — `openFromOrigin` (L109-113) ganti isi: `Navigator.push(PostViewerRoute<bool>(builder: (_) => const FeedMediaPickerScreen()))`; param `originKey` DIHAPUS dari signature.
- Modify call sites: `flutter_app/lib/screens/feed_screen.dart:729` + `member_screen.dart:253` (hapus arg originKey; `_createPostOriginKey` yang jadi yatim dihapus sekalian: feed_screen L209/L896, member_screen L141/L386).
- Delete: `flutter_app/lib/widgets/origin_expansion_route.dart`, `flutter_app/test/widgets/origin_expansion_route_test.dart`, `flutter_app/test/widgets/origin_expansion_route_dismiss_test.dart`.
- Test: tambah kasus di test feed/composer existing bila ada; minimal kompilasi + grep.

**Interfaces:** Consumes `PostViewerRoute` (T1). Produces: nol referensi `pushOriginExpansion`/`OriginSnapshotSource`/`OriginExpansionTransition` di seluruh lib/ dan test/.

- [ ] **Step 1: Ganti composer entry + hapus file + hapus import yatim.**
- [ ] **Step 2: Verifikasi total:**

```bash
cd flutter_app
grep -rn "pushOriginExpansion\|OriginSnapshotSource\|OriginExpansionTransition\|origin_expansion_route" lib/ test/ ; # WAJIB kosong
flutter analyze
```

- [ ] **Step 3: Regresi** `flutter test test/screens/ test/features/` → hijau (bandingkan baseline kegagalan pre-existing bila ada, catat).
- [ ] **Step 4: format/diff-check/commit** — `feat(postingan): composer fade standar + hapus OriginExpansionRoute total`

---

### Task 7: Sweep verifikasi penuh + goldens + review final

**Files:**
- Test: regenerate goldens yang berubah (`flutter test --update-goldens test/golden/` bila ada diff); full suite.

- [ ] **Step 1:** `cd flutter_app && flutter analyze` (bersih) + `flutter test` penuh; catat & bandingkan kegagalan pre-existing (baseline main).
- [ ] **Step 2:** `dart format --set-exit-if-changed lib test` (atau format file tersentuh), `git diff --check`.
- [ ] **Step 3:** Review checklist spec: semua Hero `transitionOnUserGestures:true` (grep `Hero(` di lib/ — hanya via `PostHero` utk post); tag hanya via `postHeroTag`; tak ada `Scrollable.ensureVisible` baru utk grid (hanya `ensureProfileTileVisible`/jumpTo).
- [ ] **Step 4: Commit final** — `test(postingan): sweep verifikasi hero rewrite` — lalu laporkan siap device-verify (checklist di spec §Testing).

---

## Self-Review (dijalankan penulis plan)

- **Spec coverage:** scope 4 origin grid (T3/T4/T5) ✓; composer fade (T6) ✓; hapus OriginExpansionRoute (T6) ✓; PostPageZoomRoute tidak ada di main → tidak perlu dihapus ✓; video ikut hero + controller sama (T2 + shuttle T1) ✓; reverse target post aktif + reveal + fade jinak (T2 onWillClose + T3-T5 reveal + T1 test-4) ✓; `transitionOnUserGestures` dua sisi (T1 widget tunggal dipakai semua sisi) ✓; tag scope per permukaan termasuk username utk profil publik (T4) ✓; reduced-motion tanpa branch khusus (bawaan) ✓.
- **Placeholder scan:** tidak ada TBD; test RED T2-T5 ditulis pola-lengkap dgn acuan file konvensi eksplisit — implementer mengisi boilerplate mount dari file acuan yang disebut.
- **Type consistency:** `postHeroTag(scope, postId)`, `PostHero(scope:, postId:, child:)`, `pushPostViewer(context, builder:)`, `heroScope`, `onWillClose(String)` — konsisten T1→T6.

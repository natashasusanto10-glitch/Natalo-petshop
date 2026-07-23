# Spec A — Tutup Tag Belanja + Tab "Ditandai" (Shell) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sembunyikan input "Tag Produk Pernah Dibeli" di layar New Post (reversibel lewat flag) dan ganti tab ke-3 Profil dari "Belanja" jadi cangkang kosong "Ditandai", dengan gaya tab-aktif baru (fill biru + gerak naik tipis) diterapkan konsisten ke ketiga tab.

**Architecture:** Satu flag konstan baru (`kShopTagEnabled`) menggerbangi UI New Post tanpa menyentuh backend. Widget tab bar bersama (`PublicProfileContentTabBar`) dipakai baik oleh profil sendiri (`MemberScreen`, mode selalu-expanded) maupun profil publik (`PublicProfileScreen`, mode pill saat scroll) — perubahan ikon/animasi di satu file itu otomatis konsisten di kedua layar. Konten tab "Ditandai" jadi statis-kosong di kedua layar, tapi dengan mekanisme berbeda sesuai arsitektur data masing-masing (client-side getter vs network fetch).

**Tech Stack:** Flutter/Dart, `flutter_test` (widget tests), Material Icons (`Icons.people_outline_rounded`/`Icons.people_rounded`, dll — semua konstanta bawaan Flutter SDK, tidak ada icon font tambahan).

## Global Constraints

- Tidak mengubah backend/model: `FeedPostProduct`, `app/api/feed/posts/route.ts`, `app/api/feed/pinnable-products/route.ts` tetap seperti sekarang.
- Tidak mengubah `FeedPost.products`/`productsInVideo`/`taggedProducts`, `FeedProductPill`, `showFeedProductLinksSheet`.
- Jumlah tab profil tetap 3 di kedua layar — jangan ubah `TabController(length: ...)` atau pembagian `/3` di perhitungan posisi indikator.
- Flag `kShopTagEnabled` default `false`; membalikkannya ke `true` HANYA menghidupkan lagi input New Post, TIDAK otomatis mengembalikan tab Profil ke "Belanja" (trade-off yang sudah disetujui user).
- Semua teks UI berbahasa Indonesia, sentence case, konsisten dengan copy existing di file yang sama.
- Branch SUDAH di-rebase ke `main` terkini (memuat kebijakan clean-icon + freeze-header profil sepi). Nomor baris di plan ini mengacu kode pasca-rebase; kalau meleset sedikit, cari lewat string/nama simbol yang dikutip, bukan baris mentah.
- Konvensi app-wide "Global Icon Clean Interaction": kontrol ikon TANPA tooltip/ripple/splash/overlay. Task 3 menghapus `Tooltip` tab profil agar patuh; JANGAN menambah splash/tooltip baru pada elemen ikon mana pun.
- Spec sumber: `docs/superpowers/specs/2026-07-22-tutup-tag-belanja-spec-a-design.md` — baca dulu kalau ada keraguan konteks.

---

### Task 1: Feature flag + sembunyikan input New Post

**Files:**
- Create: `flutter_app/lib/config/feature_flags.dart`
- Modify: `flutter_app/lib/screens/feed_new_post_screen.dart:1-21` (import), `:139-162` (initState), `:598-624` (section UI)
- Test: `flutter_app/test/feed_new_post_screen_test.dart`

**Interfaces:**
- Produces: top-level `const bool kShopTagEnabled` di `flutter_app/lib/config/feature_flags.dart`, dipakai Task ini dan disebut di spec sebagai satu-satunya titik toggle.

- [ ] **Step 1: Buat file flag baru**

Buat `flutter_app/lib/config/feature_flags.dart`:

```dart
/// Feature flags sederhana, di-hardcode (bukan remote-config). Ubah nilai
/// lalu rebuild app untuk mengaktifkan/menonaktifkan.

/// Menampilkan section "Tag Produk Pernah Dibeli" di layar New Post dan
/// memicu query pinnable-products terkait. Non-aktif sejak Spec A
/// (2026-07-22) — tab "Belanja" di Profil sudah diganti "Ditandai".
/// Membalikkan flag ini ke `true` HANYA menghidupkan lagi input New Post;
/// tab Profil TIDAK otomatis kembali "Belanja" (perlu revert manual
/// terpisah). Lihat
/// docs/superpowers/specs/2026-07-22-tutup-tag-belanja-spec-a-design.md.
const kShopTagEnabled = false;
```

- [ ] **Step 2: Tulis test yang gagal — section tidak boleh ada**

Tambahkan di `flutter_app/test/feed_new_post_screen_test.dart` (dalam blok `main()`, dekat test lain yang memakai `pumpScreen`):

```dart
  testWidgets('section Tag Produk Pernah Dibeli tersembunyi (flag off)',
      (tester) async {
    await pumpScreen(tester);
    expect(find.text('Tag Produk Pernah Dibeli'), findsNothing);
  });
```

- [ ] **Step 3: Jalankan test, pastikan gagal**

Run: `cd flutter_app && flutter test test/feed_new_post_screen_test.dart -n "section Tag Produk Pernah Dibeli tersembunyi"`
Expected: FAIL — `find.text('Tag Produk Pernah Dibeli')` masih `findsOneWidget` (section belum disembunyikan).

- [ ] **Step 4: Tambah import flag di `feed_new_post_screen.dart`**

Di baris 18-21 (`feed_new_post_screen.dart`), tambahkan satu baris import baru setelah import lain:

```dart
import '../config/feature_flags.dart';
import 'feed_caption_edit_screen.dart';
import 'feed_post/feed_cover_picker_screen.dart';
import 'feed_post/feed_post_preview_screen.dart'
    show FeedPostPreviewScreen, FeedPreviewResult;
```

- [ ] **Step 5: Gerbangi pemanggilan fetch di `initState`**

Ganti baris 161 (`_loadPurchasedProducts();`) dengan:

```dart
    if (kShopTagEnabled) {
      _loadPurchasedProducts();
    }
```

- [ ] **Step 6: Gerbangi section UI**

Ganti blok baris 607-624 (dari `const SizedBox(height: 26),` sampai penutup `if (_error != null) [...]`) menjadi:

```dart
                    if (kShopTagEnabled) ...[
                      const SizedBox(height: 26),
                      const _SectionTitle('Tag Produk Pernah Dibeli'),
                      const SizedBox(height: 12),
                      _PurchasedProductSearch(
                        controller: _productSearchController,
                        onChanged: _searchPurchasedProducts,
                      ),
                      const SizedBox(height: 14),
                      _PurchasedProducts(
                        products: _visibleProducts,
                        loading: _loadingProducts,
                        selectedIds: _selectedProductIds,
                        onTap: _toggleProduct,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        _ErrorBox(message: _error!),
                      ],
                    ],
```

Kode lain di file ini (`_selectedProductIds`, `_toggleProduct`, `prefilledProductIds`, `_visibleProducts`, dll) **tidak disentuh** — biarkan tetap ada meski tidak lagi dipanggil dari UI saat flag `false`.

- [ ] **Step 7: Jalankan test, pastikan lulus**

Run: `cd flutter_app && flutter test test/feed_new_post_screen_test.dart`
Expected: PASS — semua test termasuk yang baru.

- [ ] **Step 8: Commit**

```bash
git add flutter_app/lib/config/feature_flags.dart flutter_app/lib/screens/feed_new_post_screen.dart flutter_app/test/feed_new_post_screen_test.dart
git commit -m "feat: sembunyikan tag produk di New Post di balik flag kShopTagEnabled"
```

---

### Task 2: Ganti label & ikon tab ke-3 (Belanja → Ditandai)

**Files:**
- Modify: `flutter_app/lib/widgets/public_profile_content_tab_bar.dart:92-105`
- Modify (existing test, perlu diupdate): `flutter_app/test/widgets/public_profile_content_tab_bar_test.dart` (baris 39, 42, 87, 102, 136, 282)
- Modify (existing test, perlu diupdate): `flutter_app/test/screens/public_profile_screen_test.dart:204`

**Interfaces:**
- Consumes: tidak ada dari Task 1.
- Produces: `Key('public_tab_tagged_pill')` (pengganti `public_tab_shop_pill`) dan label `'Ditandai'` — dipakai Task 3 & Task 5 untuk mencari widget ini di test.

- [ ] **Step 1: Update test lama supaya mengharapkan label baru (akan gagal dulu)**

Di `flutter_app/test/widgets/public_profile_content_tab_bar_test.dart`, ganti setiap kemunculan berikut:
- Baris 39: `expect(find.text('Belanja'), findsOneWidget);` → `expect(find.text('Ditandai'), findsOneWidget);`
- Baris 42: `expect(find.byKey(const Key('public_tab_shop_pill')), findsOneWidget);` → `expect(find.byKey(const Key('public_tab_tagged_pill')), findsOneWidget);`
- Baris 87: `('Belanja', false),` → `('Ditandai', false),`
- Baris 102: ``for (final label in const ['Postingan', 'Video', 'Belanja']) {`` → ``for (final label in const ['Postingan', 'Video', 'Ditandai']) {``
- Baris 136: `expect(find.text('Belanja page'), findsOneWidget);` → `expect(find.text('Ditandai page'), findsOneWidget);`
- Baris 282 (di dalam `_PublicTabsHarnessState.build`, list children `TabBarView`): `Center(child: Text('Belanja page')),` → `Center(child: Text('Ditandai page')),`

Di `flutter_app/test/screens/public_profile_screen_test.dart` baris 204:
```dart
    expect(find.descendant(of: tabGroup, matching: find.text('Ditandai')),
        findsOneWidget);
```

- [ ] **Step 2: Jalankan kedua test file, pastikan gagal**

Run: `cd flutter_app && flutter test test/widgets/public_profile_content_tab_bar_test.dart test/screens/public_profile_screen_test.dart`
Expected: FAIL — widget masih render `'Belanja'`/`public_tab_shop_pill`, bukan `'Ditandai'`/`public_tab_tagged_pill`.

- [ ] **Step 3: Ubah tab index 2 di widget sungguhan**

Di `flutter_app/lib/widgets/public_profile_content_tab_bar.dart` baris 92-105, ganti:

```dart
              _PublicProfileTab(
                pillKey: const Key('public_tab_shop_pill'),
                controller: controller,
                index: 2,
                icon: Icons.shopping_bag_outlined,
                label: 'Belanja',
```

menjadi:

```dart
              _PublicProfileTab(
                pillKey: const Key('public_tab_tagged_pill'),
                controller: controller,
                index: 2,
                icon: Icons.people_outline_rounded,
                label: 'Ditandai',
```

(baris-baris parameter lain di bawahnya — `labelOpacity`, `pillOpacity`, `reducedMotion`, `expandedForeground`, `activeSurface`, `activeForeground`, `inactiveForeground` — tidak berubah).

- [ ] **Step 4: Jalankan test, pastikan lulus**

Run: `cd flutter_app && flutter test test/widgets/public_profile_content_tab_bar_test.dart test/screens/public_profile_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/widgets/public_profile_content_tab_bar.dart flutter_app/test/widgets/public_profile_content_tab_bar_test.dart flutter_app/test/screens/public_profile_screen_test.dart
git commit -m "feat: ganti tab profil ke-3 dari Belanja jadi Ditandai (label+ikon)"
```

---

### Task 3: Fix warna tab aktif + animasi outline→filled + gerak naik

**Files:**
- Modify: `flutter_app/lib/widgets/public_profile_content_tab_bar.dart:1-7` (import), `:61-105` (ketiga `_PublicProfileTab`), `:157-260` (field+build `_PublicProfileTab`), `:262-290` (hapus `Tooltip`)
- Modify (existing test, assersi perlu diperbarui): `flutter_app/test/widgets/public_profile_content_tab_bar_test.dart:7-24` (test warna), `:84-100` (anchor semantics → pill key)
- Modify (existing test, anchor byTooltip → pill key): `flutter_app/test/screens/public_profile_screen_test.dart:185,210,222,229`

**Interfaces:**
- Consumes: `Key('public_tab_tagged_pill')`, label `'Ditandai'` dari Task 2.
- Produces: field baru `activeIcon` pada `_PublicProfileTab` (dipakai ketiga tab). Menghapus `Tooltip` dari tab → task lain (4 & 5) yang meng-tap tab HARUS pakai `find.byKey(public_tab_*_pill)`, bukan `find.byTooltip`.

- [ ] **Step 1: Tulis test baru untuk warna tab aktif di mode expanded (akan gagal)**

Tambahkan di `flutter_app/test/widgets/public_profile_content_tab_bar_test.dart`, gantikan isi test `'expanded public tabs are icon-only and neutral'` (baris 7-24) — ganti nama & body-nya:

```dart
  testWidgets('expanded tabs: tab aktif jadi biru brand, lainnya netral', (
    tester,
  ) async {
    await tester.pumpWidget(
      tabHarness(
        labelOpacity: 0,
        pillOpacity: 0,
        underlineOpacity: 1,
      ),
    );

    expect(find.text('Postingan'), findsNothing);
    expect(find.byKey(const Key('public_tab_posts_pill')), findsOneWidget);
    expect(
      find.byKey(const Key('public_tab_sliding_underline')),
      findsOneWidget,
    );
    expect(find.byType(BackdropFilter), findsNothing);

    // TabController default index 0 → "Postingan" aktif.
    for (final icon in tester.widgetList<Icon>(
      find.descendant(
        of: find.byKey(const Key('public_tab_posts_pill')),
        matching: find.byType(Icon),
      ),
    )) {
      expect(icon.color, NataloColors.primary);
    }
    for (final key in ['public_tab_video_pill', 'public_tab_tagged_pill']) {
      for (final icon in tester.widgetList<Icon>(
        find.descendant(
          of: find.byKey(Key(key)),
          matching: find.byType(Icon),
        ),
      )) {
        expect(icon.color, isNot(NataloColors.primary));
      }
    }
  });
```

Test `'collapsed tabs render three individual neutral pills'` (baris 26-49) **tidak berubah** — mode pill tetap pakai skema warna lama (tidak disentuh spec ini).

- [ ] **Step 2: Jalankan test, pastikan gagal**

Run: `cd flutter_app && flutter test test/widgets/public_profile_content_tab_bar_test.dart -n "tab aktif jadi biru brand"`
Expected: FAIL — semua ikon masih warna netral (bug lama: `foreground` tidak ikut `emphasis` saat `pillOpacity == 0`).

- [ ] **Step 3: Tambah import `NataloColors`**

Di `flutter_app/lib/widgets/public_profile_content_tab_bar.dart` baris 1-6, tambahkan:

```dart
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../theme/natalo_colors.dart';
import '../theme/natalo_text.dart';
import 'liquid_glass.dart';
```

- [ ] **Step 4: Tambah field `activeIcon` ke `_PublicProfileTab`**

Ubah bagian field + constructor kelas `_PublicProfileTab` (sekitar baris 157-184):

```dart
class _PublicProfileTab extends StatelessWidget {
  final Key pillKey;
  final TabController controller;
  final int index;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final double labelOpacity;
  final double pillOpacity;
  final bool reducedMotion;
  final Color expandedForeground;
  final Color activeSurface;
  final Color activeForeground;
  final Color inactiveForeground;

  const _PublicProfileTab({
    required this.pillKey,
    required this.controller,
    required this.index,
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.labelOpacity,
    required this.pillOpacity,
    required this.reducedMotion,
    required this.expandedForeground,
    required this.activeSurface,
    required this.activeForeground,
    required this.inactiveForeground,
  });
```

- [ ] **Step 5: Kirim `activeIcon` dari ketiga pemanggil di `PublicProfileContentTabBar`**

Ubah ketiga `_PublicProfileTab(...)` di baris 62-105 jadi (tambahkan baris `activeIcon:` setelah `icon:` di masing-masing, TIDAK ada perubahan lain):

```dart
              _PublicProfileTab(
                pillKey: const Key('public_tab_posts_pill'),
                controller: controller,
                index: 0,
                icon: Icons.grid_on_rounded,
                activeIcon: Icons.grid_on_rounded,
                label: 'Postingan',
                labelOpacity: labelOpacity,
                pillOpacity: pillOpacity,
                reducedMotion: reducedMotion,
                expandedForeground: expandedForeground,
                activeSurface: activeSurface,
                activeForeground: activeForeground,
                inactiveForeground: inactiveForeground,
              ),
              _PublicProfileTab(
                pillKey: const Key('public_tab_video_pill'),
                controller: controller,
                index: 1,
                icon: Icons.play_circle_outline_rounded,
                activeIcon: Icons.play_circle_fill_rounded,
                label: 'Video',
                labelOpacity: labelOpacity,
                pillOpacity: pillOpacity,
                reducedMotion: reducedMotion,
                expandedForeground: expandedForeground,
                activeSurface: activeSurface,
                activeForeground: activeForeground,
                inactiveForeground: inactiveForeground,
              ),
              _PublicProfileTab(
                pillKey: const Key('public_tab_tagged_pill'),
                controller: controller,
                index: 2,
                icon: Icons.people_outline_rounded,
                activeIcon: Icons.people_rounded,
                label: 'Ditandai',
                labelOpacity: labelOpacity,
                pillOpacity: pillOpacity,
                reducedMotion: reducedMotion,
                expandedForeground: expandedForeground,
                activeSurface: activeSurface,
                activeForeground: activeForeground,
                inactiveForeground: inactiveForeground,
              ),
```

`Icons.grid_on_rounded` dipakai sebagai `icon` maupun `activeIcon` (sengaja sama — tidak ada padanan outline yang natural untuk glyph ini, jadi tab Postingan hanya beranimasi warna+gerak, tanpa ganti bentuk). `Icons.play_circle_fill_rounded` sudah dipakai sebagai ikon Feed aktif di `bottom_nav.dart` — dipakai ulang di sini untuk konsistensi glyph filled yang sama persis di seluruh app.

- [ ] **Step 6: Perbaiki bug warna + tambah crossfade & gerak naik di `build()`**

Di dalam `_PublicProfileTab.build()`, ganti blok berikut (sekitar baris 194-231 versi lama):

```dart
          final position = controller.animation?.value ?? controller.index;
          final emphasis =
              (1 - (position - index).abs()).clamp(0.0, 1.0).toDouble();
          final collapsedForeground = Color.lerp(
            inactiveForeground,
            activeForeground,
            emphasis,
          )!;
          final foreground = Color.lerp(
            expandedForeground,
            collapsedForeground,
            pillOpacity,
          )!;
```

menjadi:

```dart
          final position = controller.animation?.value ?? controller.index;
          final emphasis =
              (1 - (position - index).abs()).clamp(0.0, 1.0).toDouble();
          // PREMIUM: emphasis mentah linear terhadap posisi jari saat swipe —
          // terasa "menempel" ke gerakan. Bungkus dengan easeOutCubic supaya
          // treatment visual (warna, gerak naik, crossfade) MENGENDAP di
          // ujung transisi, bukan tracking 1:1. Underline geser TIDAK pakai
          // ini (mekanismenya sendiri, sudah mulus).
          final curvedEmphasis = Curves.easeOutCubic.transform(emphasis);
          // Mode expanded (pillOpacity 0, dipakai MemberScreen & profil
          // publik sebelum scroll): dulu foreground SELALU = expandedForeground
          // konstan (bug — tidak pernah ikut emphasis). Sekarang warna
          // melebur abu→biru brand mengikuti curvedEmphasis, sama seperti mode
          // pill di bawahnya.
          final expandedDynamic = Color.lerp(
            expandedForeground,
            NataloColors.primary,
            curvedEmphasis,
          )!;
          final collapsedForeground = Color.lerp(
            inactiveForeground,
            activeForeground,
            curvedEmphasis,
          )!;
          final foreground = Color.lerp(
            expandedDynamic,
            collapsedForeground,
            pillOpacity,
          )!;
```

Lalu cari baris `final iconSize = lerpDouble(27, 23, pillOpacity)!;` dan ganti jadi ukuran tetap:

```dart
          const iconSize = 24.0;
```

Lalu cari baris `Icon(icon, color: foreground, size: iconSize),` di dalam `Row` (bagian `pillContent`) dan ganti jadi:

```dart
                  Transform.translate(
                    // Gerak naik 3px di-ease supaya terasa "terangkat lalu
                    // mengendap", bukan meluncur linear. Crossfade outline↔
                    // filled memakai kurva yang sama supaya bentuk & posisi
                    // berubah serempak (premium: satu gerakan, bukan dua
                    // animasi yang balapan).
                    offset: Offset(0, lerpDouble(0, -3, curvedEmphasis)!),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Opacity(
                          opacity: (1 - curvedEmphasis).clamp(0.0, 1.0),
                          child: Icon(icon, color: foreground, size: iconSize),
                        ),
                        Opacity(
                          opacity: curvedEmphasis.clamp(0.0, 1.0),
                          child: Icon(
                            activeIcon,
                            color: foreground,
                            size: iconSize,
                          ),
                        ),
                      ],
                    ),
                  ),
```

Catatan performa: `Transform.translate` + `Opacity` + `Icon` semuanya murah (tidak ada layout/clip mahal), aman 60fps. `AnimatedBuilder` yang membungkus (sudah ada di widget) rebuild hanya sub-tree ini, bukan seluruh tab bar.

- [ ] **Step 7: Hapus `Tooltip` pada tab (konsistensi clean-icon)**

Sesuai keputusan user, tab profil ikut kehilangan tooltip agar konsisten dengan kebijakan app-wide "Global Icon Clean Interaction". Aksesibilitas tetap lewat `Semantics(label:...)` yang membungkusnya. Di `flutter_app/lib/widgets/public_profile_content_tab_bar.dart` baris ~262-290, ganti:

```dart
          return Semantics(
            label: label,
            button: true,
            selected: emphasis > 0.5,
            excludeSemantics: true,
            child: Tooltip(
              message: label,
              excludeFromSemantics: true,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 7,
                    ),
                    child: LiquidGlass(
                      // Glass memudar saat pill aktif jadi solid gelap —
                      // opacity kaca mengikuti seberapa "inactive" pill.
                      opacity: pillOpacity * (1 - emphasis),
                      reducedMotion: reducedMotion,
                      borderRadius: BorderRadius.circular(19),
                      child: pillContent,
                    ),
                  ),
                ],
              ),
            ),
          );
```

menjadi (buang wrapper `Tooltip`, jadikan `Stack` langsung child `Semantics`):

```dart
          return Semantics(
            label: label,
            button: true,
            selected: emphasis > 0.5,
            excludeSemantics: true,
            // Tooltip long-press SENGAJA dihapus mengikuti kebijakan
            // "Global Icon Clean Interaction" — nama tetap terbaca screen
            // reader lewat Semantics.label di atas. Lihat
            // docs/superpowers/specs/2026-07-22-tutup-tag-belanja-spec-a-design.md.
            child: Stack(
              alignment: Alignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 7,
                  ),
                  child: LiquidGlass(
                    // Glass memudar saat pill aktif jadi solid gelap —
                    // opacity kaca mengikuti seberapa "inactive" pill.
                    opacity: pillOpacity * (1 - emphasis),
                    reducedMotion: reducedMotion,
                    borderRadius: BorderRadius.circular(19),
                    child: pillContent,
                  ),
                ),
              ],
            ),
          );
```

- [ ] **Step 8: Update test existing yang meng-anchor lewat `find.byTooltip`**

Karena tooltip tab hilang, ganti anchor ke pill key yang robust.

Di `flutter_app/test/widgets/public_profile_content_tab_bar_test.dart`, test `'full tab semantics remain buttons and selected outside visual scale cap'` (loop baris ~84-100), ubah tuple list + anchor jadi memakai pill key. Ganti blok:

```dart
      for (final (label, selected) in <(String, bool)>[
        ('Postingan', true),
        ('Video', false),
        ('Ditandai', false),
      ]) {
        final semantics = tester.widget<Semantics>(
          find
              .ancestor(
                of: find.byTooltip(label),
                matching: find.byType(Semantics),
              )
              .first,
        );
        expect(semantics.properties.label, label);
        expect(semantics.properties.button, isTrue);
        expect(semantics.properties.selected, selected);
      }
```

menjadi:

```dart
      for (final (label, pillKey, selected) in <(String, String, bool)>[
        ('Postingan', 'public_tab_posts_pill', true),
        ('Video', 'public_tab_video_pill', false),
        ('Ditandai', 'public_tab_tagged_pill', false),
      ]) {
        final semantics = tester.widget<Semantics>(
          find
              .ancestor(
                of: find.byKey(Key(pillKey)),
                matching: find.byType(Semantics),
              )
              .first,
        );
        expect(semantics.properties.label, label);
        expect(semantics.properties.button, isTrue);
        expect(semantics.properties.selected, selected);
      }
```

Di `flutter_app/test/screens/public_profile_screen_test.dart`, ganti keempat pemakaian `find.byTooltip(...)` yang menarget tab:
- Baris ~185: `of: find.byTooltip('Video'),` → `of: find.byKey(const Key('public_tab_video_pill')),`
- Baris ~210: `of: find.byTooltip('Video'),` → `of: find.byKey(const Key('public_tab_video_pill')),`
- Baris ~222: `of: find.byTooltip('Video'),` → `of: find.byKey(const Key('public_tab_video_pill')),`
- Baris ~229: `await tester.tap(find.byTooltip('Postingan'));` → `await tester.tap(find.byKey(const Key('public_tab_posts_pill')));`

JANGAN sentuh `find.byTooltip('Buat postingan')`/`'Postingan tersimpan'`/`'Pengaturan akun'` di `member_screen_test.dart:66-68` — itu tooltip IconButton top bar, BUKAN tab, dan di luar scope perubahan ini.

- [ ] **Step 9: Jalankan test, pastikan lulus**

Run: `cd flutter_app && flutter test test/widgets/public_profile_content_tab_bar_test.dart`
Expected: PASS — termasuk test semantics yang di-anchor ulang ke pill key.

- [ ] **Step 10: Jalankan seluruh suite tab bar + profil untuk regresi**

Run: `cd flutter_app && flutter test test/screens/public_profile_screen_test.dart test/screens/member_screen_test.dart`
Expected: PASS.

- [ ] **Step 11: Commit**

```bash
git add flutter_app/lib/widgets/public_profile_content_tab_bar.dart flutter_app/test/widgets/public_profile_content_tab_bar_test.dart flutter_app/test/screens/public_profile_screen_test.dart
git commit -m "feat: animasi tab aktif (fill biru + easing) + hapus tooltip tab (clean-icon)"
```

---

### Task 4: Konten tab "Ditandai" kosong — profil sendiri

**Files:**
- Modify: `flutter_app/lib/screens/member_screen.dart:420-423` (getter `_taggedPosts`), `:538-557` (teks empty state), `:946-959` (badge tas belanja di thumbnail grid), `:490-493` (haptic tab di `_AccountTabHeaderDelegate`)
- Test: `flutter_app/test/screens/member_screen_test.dart`

**Interfaces:**
- Consumes: `Key('public_tab_tagged_pill')` dari Task 2 (dipakai untuk tap tab; tooltip sudah dihapus di Task 3 sehingga `find.byTooltip` tidak lagi berlaku untuk tab).

- [ ] **Step 1: Tulis test yang gagal — teks empty state baru**

Tambahkan di `flutter_app/test/screens/member_screen_test.dart` (dalam `main()`, dekat test lain yang memakai `pumpScreen`):

```dart
  testWidgets('tab Ditandai selalu kosong dengan copy baru', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byKey(const Key('public_tab_tagged_pill')));
    await tester.pumpAndSettle();

    expect(
      find.text('Belum ada postingan yang menandaimu'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Saat orang lain menandaimu di sebuah postingan, itu akan muncul di sini.',
      ),
      findsOneWidget,
    );
  });
```

- [ ] **Step 2: Jalankan test, pastikan gagal**

Run: `cd flutter_app && flutter test test/screens/member_screen_test.dart -n "tab Ditandai selalu kosong"`
Expected: FAIL — teks masih `'Belum ada postingan belanja'` / subteks lama.

- [ ] **Step 3: Ganti getter `_taggedPosts` jadi selalu kosong**

Di `flutter_app/lib/screens/member_screen.dart` baris 420-423, ganti:

```dart
  List<FeedPost> get _videoPosts => _allPosts.where((p) => p.isVideo).toList();

  List<FeedPost> get _taggedPosts =>
      _allPosts.where((p) => p.productIds.isNotEmpty).toList();
```

menjadi:

```dart
  List<FeedPost> get _videoPosts => _allPosts.where((p) => p.isVideo).toList();

  // Tab "Ditandai" (dulu "Belanja") sengaja selalu kosong sampai Spec B
  // (Tag People) membangun data tag-orang sungguhan. Lihat
  // docs/superpowers/specs/2026-07-22-tutup-tag-belanja-spec-a-design.md.
  List<FeedPost> get _taggedPosts => const [];
```

- [ ] **Step 4: Ganti teks empty state**

Di `flutter_app/lib/screens/member_screen.dart` sekitar baris 538-544, ganti:

```dart
                        _PostGrid(
                          posts: _taggedPosts,
                          loading: _loadingPosts,
                          errorText: _postsError,
                          emptyText: 'Belum ada postingan belanja',
                          emptySubtext:
                              'Postingan yang terhubung ke produk Natalo akan muncul di sini.',
```

menjadi:

```dart
                        _PostGrid(
                          posts: _taggedPosts,
                          loading: _loadingPosts,
                          errorText: _postsError,
                          emptyText: 'Belum ada postingan yang menandaimu',
                          emptySubtext:
                              'Saat orang lain menandaimu di sebuah postingan, itu akan muncul di sini.',
```

(parameter lain di `_PostGrid` ini — `showCreateCta: false`, `onCreateCta`, `onRetry`, `onTapPost`, dst — tidak berubah.)

- [ ] **Step 5: Hapus badge tas belanja di thumbnail grid "Postingan"**

Tulis dulu test yang gagal — tambahkan di `flutter_app/test/screens/member_screen_test.dart`:

```dart
  testWidgets('badge tas belanja tidak lagi muncul di thumbnail grid',
      (tester) async {
    await pumpScreen(tester);
    expect(find.byIcon(Icons.shopping_bag_outlined), findsNothing);
  });
```

Run: `cd flutter_app && flutter test test/screens/member_screen_test.dart -n "badge tas belanja"` — expected FAIL kalau kebetulan ada post lama dengan produk tertaut ter-render (di test env network gagal cepat sehingga `_allPosts` biasanya kosong dan test ini PASS secara trivial; tetap tulis sebagai regression guard).

Lalu di `flutter_app/lib/screens/member_screen.dart` baris 946-959, ganti:

```dart
            // Type indicators top-right (video play OR shopping bag).
            // Priority: video > tagged products (kalau dua-duanya, video win).
            if (post.isVideo)
              const Positioned(
                top: 8,
                right: 8,
                child: _ThumbnailIcon(icon: Icons.play_arrow_rounded),
              )
            else if (post.productIds.isNotEmpty)
              const Positioned(
                top: 8,
                right: 8,
                child: _ThumbnailIcon(icon: Icons.shopping_bag_outlined),
              ),
          ],
```

menjadi:

```dart
            // Type indicator top-right: video play saja. Badge tas belanja
            // utk post lama yang punya produk tertaut sengaja dihapus
            // (Spec A) — tidak ada lagi jejak visual "tag belanja" di
            // Profil. Lihat
            // docs/superpowers/specs/2026-07-22-tutup-tag-belanja-spec-a-design.md.
            if (post.isVideo)
              const Positioned(
                top: 8,
                right: 8,
                child: _ThumbnailIcon(icon: Icons.play_arrow_rounded),
              ),
          ],
```

- [ ] **Step 6: Matikan haptic saat ganti tab (permintaan user)**

User minta haptic pada tap tab profil dimatikan. Di `flutter_app/lib/screens/member_screen.dart` baris ~490-493, ganti:

```dart
                        delegate: _AccountTabHeaderDelegate(
                          controller: _tabController,
                          onTap: (_) => AppHaptics.tap(),
                        ),
```

menjadi:

```dart
                        delegate: _AccountTabHeaderDelegate(
                          controller: _tabController,
                          // Haptic ganti-tab sengaja dimatikan (permintaan
                          // user) — pindah tab profil harus terasa halus,
                          // tanpa getar. AppHaptics.tap tetap dipakai di
                          // aksi lain (buka post, edit profil, dll).
                          onTap: null,
                        ),
```

Cek: `_AccountTabHeaderDelegate.onTap` bertipe `ValueChanged<int>?` (sudah nullable — lihat definisinya) dan `PublicProfileContentTabBar` menerima `onTap` nullable, jadi `null` aman. JANGAN sentuh `AppHaptics.tap()` di method lain (`_openEditProfile`, `_shareProfile`, `_openFollowList`, `_openPostDetail`) — hanya haptic tab yang dimatikan.

- [ ] **Step 7: Jalankan test, pastikan lulus**

Run: `cd flutter_app && flutter test test/screens/member_screen_test.dart`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add flutter_app/lib/screens/member_screen.dart flutter_app/test/screens/member_screen_test.dart
git commit -m "feat: tab Ditandai profil sendiri kosong + hapus badge belanja + matikan haptic tab"
```

---

### Task 5: Konten tab "Ditandai" kosong — profil publik (tanpa network call)

**Files:**
- Modify: `flutter_app/lib/screens/public_profile_screen.dart:480-487` (`_activateContent`), `:1438-1483` (`_EmptyPosts` — nomor baris setelah rebase ke main; cari `class _EmptyPosts` untuk memastikan), `:489-493` (haptic tab di `_onTabTapped`)
- Test: `flutter_app/test/screens/public_profile_screen_test.dart`

**Interfaces:**
- Consumes: `PublicProfileContentFilter.shoppable` (enum sudah ada, tidak berubah namanya — cuma makna tampilannya yang berganti jadi "Ditandai"); `Key('public_tab_tagged_pill')` dari Task 2 untuk tap tab (tooltip sudah dihapus Task 3).

- [ ] **Step 1: Tulis test yang gagal — no network call + teks orang-ketiga**

Tambahkan di `flutter_app/test/screens/public_profile_screen_test.dart` (dalam `main()`, pola serupa test lain yang memakai `initialResult`):

```dart
  testWidgets(
      'tab Ditandai di profil publik langsung kosong tanpa network call',
      (tester) async {
    const result = PublicProfileResult(
      profile: PublicProfile(
        id: 'creator-1',
        name: 'Creator',
        username: 'creator',
        isOwner: false,
      ),
      posts: [],
    );
    await tester.pumpWidget(MaterialApp(
      home: PublicProfileScreen(
        username: 'creator',
        initialResult: result,
        fetchChatConfig: _noOpFetch,
      ),
    ));
    await tester.pump();

    // Tap langsung tab "Ditandai" via pill key (tooltip sudah dihapus di
    // Task 3). Bukan drag TabBarView — drag gesture pada PageView biasanya
    // cuma pindah satu halaman per drag, tidak reliable untuk lompat dari
    // tab 0 ke tab 2 dalam satu gerakan.
    await tester.tap(find.byKey(const Key('public_tab_tagged_pill')));
    // Satu pump tanpa delay — kalau masih ada fetch async sungguhan,
    // spinner loading akan sempat kelihatan di frame ini.
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      find.text('Belum ada postingan yang menandai akun ini'),
      findsOneWidget,
    );

    await tester.pumpAndSettle();
  });
```

- [ ] **Step 2: Jalankan test, pastikan gagal**

Run: `cd flutter_app && flutter test test/screens/public_profile_screen_test.dart -n "langsung kosong tanpa network call"`
Expected: FAIL — teks masih `'Belum ada postingan belanja'` dan/atau spinner sempat muncul.

- [ ] **Step 3: Intercept fetch untuk konten "Ditandai" (shoppable) di `_activateContent`**

Di `flutter_app/lib/screens/public_profile_screen.dart` baris 480-487, ganti:

```dart
  void _activateContent(PublicProfileContentFilter content) {
    if (content == _selectedContent) return;
    setState(() => _selectedContent = content);
    final contentState = _contentStates[content]!;
    if (!contentState.loaded && !contentState.loading) {
      unawaited(_loadSelectedContent(content));
    }
  }
```

menjadi:

```dart
  void _activateContent(PublicProfileContentFilter content) {
    if (content == _selectedContent) return;
    setState(() => _selectedContent = content);
    final contentState = _contentStates[content]!;
    // Tab "Ditandai" (enum lama: shoppable) sengaja selalu kosong sampai
    // Spec B membangun data tag-orang — jangan pernah memanggil network
    // fetch untuk filter ini. Lihat
    // docs/superpowers/specs/2026-07-22-tutup-tag-belanja-spec-a-design.md.
    if (content == PublicProfileContentFilter.shoppable) {
      if (!contentState.loaded) {
        setState(() {
          contentState
            ..loaded = true
            ..posts = const [];
        });
      }
      return;
    }
    if (!contentState.loaded && !contentState.loading) {
      unawaited(_loadSelectedContent(content));
    }
  }
```

- [ ] **Step 4: Update ikon + teks di `_EmptyPosts`**

Di `flutter_app/lib/screens/public_profile_screen.dart` (di dalam `class _EmptyPosts`, cari `Icons.shopping_bag_outlined` dan `'Belum ada postingan belanja'` — sekitar baris 1452-1470 setelah rebase), ganti:

```dart
            Icon(
              switch (content) {
                PublicProfileContentFilter.all => Icons.photo_library_outlined,
                PublicProfileContentFilter.video =>
                  Icons.play_circle_outline_rounded,
                PublicProfileContentFilter.shoppable =>
                  Icons.shopping_bag_outlined,
              },
              color: cs.onSurfaceVariant,
              size: 32,
            ),
            const SizedBox(height: 10),
            Text(
              switch (content) {
                PublicProfileContentFilter.all => 'Belum ada postingan',
                PublicProfileContentFilter.video => 'Belum ada video',
                PublicProfileContentFilter.shoppable =>
                  'Belum ada postingan belanja',
              },
```

menjadi:

```dart
            Icon(
              switch (content) {
                PublicProfileContentFilter.all => Icons.photo_library_outlined,
                PublicProfileContentFilter.video =>
                  Icons.play_circle_outline_rounded,
                PublicProfileContentFilter.shoppable =>
                  Icons.people_outline_rounded,
              },
              color: cs.onSurfaceVariant,
              size: 32,
            ),
            const SizedBox(height: 10),
            Text(
              switch (content) {
                PublicProfileContentFilter.all => 'Belum ada postingan',
                PublicProfileContentFilter.video => 'Belum ada video',
                PublicProfileContentFilter.shoppable =>
                  'Belum ada postingan yang menandai akun ini',
              },
```

Catatan: teks ini SENGAJA beda dari versi `member_screen.dart` ("...menandaimu") karena ini profil ORANG LAIN — "menandaimu" salah tata bahasa di konteks ini (lihat spec, bagian koreksi review).

- [ ] **Step 5: Matikan haptic saat ganti tab (permintaan user)**

Di `flutter_app/lib/screens/public_profile_screen.dart` baris ~489-493, ganti:

```dart
  void _onTabTapped(int index) {
    if (index == _profileContentTabs.indexOf(_selectedContent)) return;
    AppHaptics.tap();
    _activateContent(_profileContentTabs[index]);
  }
```

menjadi:

```dart
  void _onTabTapped(int index) {
    if (index == _profileContentTabs.indexOf(_selectedContent)) return;
    // Haptic ganti-tab sengaja dimatikan (permintaan user) — pindah tab
    // profil harus terasa halus, tanpa getar. AppHaptics.tap tetap dipakai
    // di aksi lain (buka post, share, follow, dll).
    _activateContent(_profileContentTabs[index]);
  }
```

JANGAN sentuh `AppHaptics.tap()` di method lain di file ini (share, follow, open post, moderation) — hanya haptic tab yang dimatikan. `AppHaptics` import tetap dipakai, jadi tidak ada unused-import.

- [ ] **Step 6: Jalankan test, pastikan lulus**

Run: `cd flutter_app && flutter test test/screens/public_profile_screen_test.dart`
Expected: PASS — termasuk test lama (baris 204, `find.text('Ditandai')` dari Task 2) dan test baru.

- [ ] **Step 7: Commit**

```bash
git add flutter_app/lib/screens/public_profile_screen.dart flutter_app/test/screens/public_profile_screen_test.dart
git commit -m "feat: tab Ditandai profil publik kosong tanpa network call + matikan haptic tab"
```

---

### Task 6: Golden regen + regresi penuh

**Files:**
- Modify (golden image, hasil regenerasi): `flutter_app/test/golden/member_screen_akun_ig_white.png` (dan golden lain yang terpengaruh tab bar, ditemukan dari langkah 1)
- Tidak ada file kode baru.

**Interfaces:**
- Consumes: seluruh perubahan Task 1-5.

- [ ] **Step 1: Cari semua golden test yang menyentuh tab bar profil**

Run: `cd flutter_app && grep -rl "public_profile_content_tab_bar\|PublicProfileContentTabBar\|MemberScreen\|PublicProfileScreen" test/golden/`
Expected output: daftar file golden test (minimal `test/golden/member_screen_akun_test.dart`, kemungkinan ada golden lain terkait `public_profile_premium_test.dart` kalau ada di `test/golden/` atau `test/screens/`).

- [ ] **Step 2: Regenerasi golden**

Run: `cd flutter_app && flutter test --update-goldens test/golden/member_screen_akun_test.dart`

(Ulangi untuk tiap file golden lain yang ditemukan di Step 1 dengan path masing-masing.)

- [ ] **Step 3: Review diff golden secara visual**

Buka file `.png` yang berubah (mis. `flutter_app/test/golden/member_screen_akun_ig_white.png`) dan pastikan perubahan HANYA pada: ikon+label tab ke-3 (Ditandai, ikon people, biru saat aktif), tidak ada regresi tak terduga di bagian lain layar (avatar, tombol, grid).

- [ ] **Step 4: Jalankan golden test, pastikan lulus tanpa `--update-goldens`**

Run: `cd flutter_app && flutter test test/golden/`
Expected: PASS.

- [ ] **Step 5: Jalankan seluruh suite Flutter untuk regresi penuh**

Run: `cd flutter_app && flutter test`
Expected: PASS — semua test hijau, termasuk yang tidak berkaitan langsung (memastikan tidak ada efek samping tak terduga dari perubahan shared widget `PublicProfileContentTabBar`).

- [ ] **Step 6: Jalankan `flutter analyze`**

Run: `cd flutter_app && flutter analyze`
Expected: No issues found (atau tidak ada issue baru dibanding sebelum Task 1).

- [ ] **Step 7: Commit golden**

```bash
git add flutter_app/test/golden/
git commit -m "test: regenerasi golden setelah tab Ditandai (Spec A)"
```

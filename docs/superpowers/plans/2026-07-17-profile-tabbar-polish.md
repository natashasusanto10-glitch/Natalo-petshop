# Polish tab bar & header profil — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hilangkan garis panjang divider TabBar + rongga ~45px di atas tab + jadikan indikator tab aktif menggeser mulus, di semua halaman profil.

**Architecture:** Semua halaman profil (publik official, publik user biasa, tab Akun) memakai `PublicProfileContentTabBar` yang sama, jadi perbaikan divider + indikator satu tempat. Rongga berasal dari over-reservation `PublicProfileHeaderMetrics._identityHeight` di `PublicProfileScreen` — dirapatkan dengan mengukur tinggi bio sebenarnya via `TextPainter`.

**Tech Stack:** Flutter, `flutter_test`, golden tests.

## Global Constraints

- Berlaku untuk KETIGA jenis profil: publik official, publik user biasa, profil sendiri (tab Akun) — semuanya lewat `PublicProfileContentTabBar`.
- Tab bar lama `ProfileContentTabBar` + `_AnimatedProfileTab` + `ProfileContentTabHeaderDelegate` di `lib/widgets/profile_content_tab_bar.dart` sudah TIDAK dipakai (redesign Akun menggantinya) → hapus sebagai dead code, tapi konfirmasi via grep dulu.
- Indikator tab aktif: garis pendek (~24px) yang MENGGESER posisinya mengikuti `controller.animation`, opacity mengikuti `underlineOpacity` (0 saat fully collapsed di profil publik; 1 di tab Akun).
- Gap: `identityHeight` harus ≈ tinggi konten header (target selisih 0..~14px, TIDAK boleh negatif/clip) untuk kasus: official 1-baris bio, regular 1-baris, regular 2-baris, dengan/tanpa mutual, di text-scale 1.0 dan 1.3.
- Test bounded pump-loop, bukan `pumpAndSettle`. Golden diregenerasi + diinspeksi controller di akhir (bukan di tiap task).
- Jangan ubah layout avatar/stats/tombol, chrome Liquid Glass, atau logika follow.

---

### Task 1: Hapus divider panjang TabBar + hapus dead ProfileContentTabBar

**Files:**
- Modify: `flutter_app/lib/widgets/public_profile_content_tab_bar.dart` (TabBar props ~47-55)
- Delete: `flutter_app/lib/widgets/profile_content_tab_bar.dart`
- Delete: `flutter_app/test/widgets/profile_content_tab_bar_test.dart`
- Test: `flutter_app/test/widgets/public_profile_content_tab_bar_test.dart` (tambah)

**Interfaces:** none baru.

- [ ] **Step 1: Konfirmasi dead code benar tak terpakai**

Run: `cd flutter_app && grep -rn "ProfileContentTabBar\|ProfileContentTabHeaderDelegate\|_AnimatedProfileTab" lib --include="*.dart" | grep -v "PublicProfileContentTabBar" | grep -v "lib/widgets/profile_content_tab_bar.dart:"`
Expected: TIDAK ada output (kosong = aman dihapus). Kalau ada output, STOP dan lapor — jangan hapus.

- [ ] **Step 2: Tulis test yang gagal — TabBar tidak menggambar divider full-width**

Tambah di `test/widgets/public_profile_content_tab_bar_test.dart` (baca file itu dulu untuk pola harness TabController yang sudah ada; pakai pola yang sama):

```dart
testWidgets('tab bar draws no full-width Material divider', (tester) async {
  final controller = TabController(length: 3, vsync: const TestVSync());
  addTearDown(controller.dispose);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: PublicProfileContentTabBar(
        controller: controller,
        labelOpacity: 0,
        pillOpacity: 0,
        underlineOpacity: 1,
      ),
    ),
  ));
  final tabBar = tester.widget<TabBar>(find.byType(TabBar));
  expect(tabBar.dividerColor, Colors.transparent);
  expect(tabBar.dividerHeight, 0);
});
```

- [ ] **Step 3: Jalankan test → GAGAL**

Run: `cd flutter_app && flutter test test/widgets/public_profile_content_tab_bar_test.dart -n "no full-width"`
Expected: FAIL — `dividerColor` null (bukan transparent), `dividerHeight` null.

- [ ] **Step 4: Set dividerColor/dividerHeight di TabBar**

Di `public_profile_content_tab_bar.dart`, pada `TabBar(...)`, tambahkan dua properti setelah `overlayColor:`:

```dart
        dividerColor: Colors.transparent,
        dividerHeight: 0,
```

- [ ] **Step 5: Jalankan test → LULUS**

Run: `cd flutter_app && flutter test test/widgets/public_profile_content_tab_bar_test.dart`
Expected: PASS.

- [ ] **Step 6: Hapus dead code**

```bash
git rm flutter_app/lib/widgets/profile_content_tab_bar.dart flutter_app/test/widgets/profile_content_tab_bar_test.dart
```

- [ ] **Step 7: analyze (pastikan tak ada import yang menggantung)**

Run: `cd flutter_app && flutter analyze lib/ test/`
Expected: No issues (kalau ada error "uri doesn't exist" untuk import profile_content_tab_bar.dart, cari file yang masih meng-import dan hapus import-nya — seharusnya tidak ada karena Step 1 kosong).

- [ ] **Step 8: Commit**

```bash
git add flutter_app/lib/widgets/public_profile_content_tab_bar.dart flutter_app/test/widgets/public_profile_content_tab_bar_test.dart
git commit -m "fix(profile): hapus divider panjang TabBar + hapus tab bar lama yang mati"
```

---

### Task 2: Indikator tab aktif menggeser mulus (bukan snap)

**Files:**
- Modify: `flutter_app/lib/widgets/public_profile_content_tab_bar.dart` (`PublicProfileContentTabBar.build` bungkus TabBar dengan Stack + indikator; `_PublicProfileTab` hapus underline per-tab ~231-254)
- Test: `flutter_app/test/widgets/public_profile_content_tab_bar_test.dart` (tambah)

**Interfaces:** Key baru `Key('public_tab_sliding_underline')` menggantikan `Key('public_tab_expanded_underline')`.

- [ ] **Step 1: Tulis test yang gagal — indikator bergeser di antara tab saat transisi**

Tambah:

```dart
testWidgets('active tab indicator slides between tabs (no snap)', (tester) async {
  final controller = TabController(length: 3, vsync: const TestVSync());
  addTearDown(controller.dispose);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 300,
        child: PublicProfileContentTabBar(
          controller: controller,
          labelOpacity: 0,
          pillOpacity: 0,
          underlineOpacity: 1,
        ),
      ),
    ),
  ));
  await tester.pump();
  final underline = find.byKey(const Key('public_tab_sliding_underline'));
  expect(underline, findsOneWidget);
  final atTab0 = tester.getCenter(underline).dx;

  // Mulai transisi ke tab 1, pump SEBAGIAN (belum selesai).
  controller.animateTo(1);
  await tester.pump(const Duration(milliseconds: 100));
  final midway = tester.getCenter(underline).dx;

  // Indikator sudah bergeser dari tab 0, tapi belum sampai pusat tab 1.
  final tab1Center = 300 / 3 * 1.5; // slot width * (1 + 0.5)
  expect(midway, greaterThan(atTab0), reason: 'indikator harus bergeser, bukan snap');
  expect(midway, lessThan(tab1Center), reason: 'belum sampai tab 1 di tengah transisi');

  await tester.pump(const Duration(milliseconds: 400)); // selesaikan animasi
});
```

- [ ] **Step 2: Jalankan test → GAGAL**

Run: `cd flutter_app && flutter test test/widgets/public_profile_content_tab_bar_test.dart -n "slides between"`
Expected: FAIL — key `public_tab_sliding_underline` belum ada (underline lama per-tab pakai key `public_tab_expanded_underline` dan snap).

- [ ] **Step 3: Hapus underline per-tab di `_PublicProfileTab`**

Di `_PublicProfileTab.build`, hapus seluruh blok indikator per-tab (yang diawali `if (underlineOpacity > 0.001 && emphasis > 0.5)` dan berisi `Positioned(bottom: 3, ... key: Key('public_tab_expanded_underline') ...)`). Setelah dihapus, `Stack` di dalam `_PublicProfileTab` hanya berisi pill (Padding→LiquidGlass→pillContent).

- [ ] **Step 4: Tambah indikator geser tunggal di `PublicProfileContentTabBar`**

Di `PublicProfileContentTabBar.build`, ganti `child: TabBar(...)` menjadi `child: Stack(children: [ TabBar(...), <indikator> ])`. Yaitu bungkus `TabBar(...)` yang sudah ada ke dalam `Stack`, lalu tambahkan indikator sebagai anak kedua:

```dart
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          TabBar(
            // ... SEMUA properti TabBar yang sudah ada, TIDAK diubah ...
          ),
          if (underlineOpacity > 0.001)
            Positioned(
              left: 0,
              right: 0,
              bottom: 3,
              height: 2.4,
              child: IgnorePointer(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return AnimatedBuilder(
                      animation: controller.animation ?? controller,
                      builder: (context, _) {
                        final pos = controller.animation?.value ??
                            controller.index.toDouble();
                        final slot = constraints.maxWidth / 3;
                        const indicatorWidth = 24.0;
                        final centerX = slot * (pos + 0.5);
                        return Stack(
                          children: [
                            Positioned(
                              left: centerX - indicatorWidth / 2,
                              top: 0,
                              bottom: 0,
                              width: indicatorWidth,
                              child: Opacity(
                                opacity: underlineOpacity.clamp(0.0, 1.0),
                                child: DecoratedBox(
                                  key: const Key('public_tab_sliding_underline'),
                                  decoration: BoxDecoration(
                                    color: expandedForeground,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
```

Catatan: `expandedForeground` sudah dihitung di awal `build` (dari `foregroundColor`/tema) — pakai variabel yang sama.

- [ ] **Step 5: Jalankan test → LULUS**

Run: `cd flutter_app && flutter test test/widgets/public_profile_content_tab_bar_test.dart`
Expected: PASS semua (test divider Task 1 + slide Task 2).

- [ ] **Step 6: analyze**

Run: `cd flutter_app && flutter analyze lib/widgets/public_profile_content_tab_bar.dart`
Expected: No issues (parameter `underlineOpacity`/`expandedForeground` yang tadinya dipakai per-tab kini dipakai di indikator tunggal; kalau ada field `_PublicProfileTab` yang jadi tak terpakai setelah hapus underline — mis. `underlineOpacity`, `expandedForeground` — hapus dari `_PublicProfileTab` dan pemanggilannya).

- [ ] **Step 7: Commit**

```bash
git add flutter_app/lib/widgets/public_profile_content_tab_bar.dart flutter_app/test/widgets/public_profile_content_tab_bar_test.dart
git commit -m "feat(profile): indikator tab aktif menggeser mulus (bukan snap)"
```

---

### Task 3: Rapatkan rongga tab — ukur tinggi bio via TextPainter

**Files:**
- Modify: `flutter_app/lib/widgets/public_profile_chrome_overlay.dart` (`PublicProfileHeaderMetrics.resolve` ~28-56 + `_identityHeight` ~62-79)
- Test: `flutter_app/test/widgets/public_profile_gap_test.dart` (baru — pengukuran)

**Interfaces:** `_identityHeight` ganti param `hasBio` (bool) menjadi `bioBlockHeight` (double, tinggi blok bio terukur termasuk gap atas, 0 kalau tak ada bio).

- [ ] **Step 1: Tulis test pengukuran yang gagal — selisih identityHeight vs konten kecil**

Buat `test/widgets/public_profile_gap_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/public_profile.dart';
import 'package:natalo_petshop_flutter/widgets/public_profile_chrome_overlay.dart';
import 'package:natalo_petshop_flutter/widgets/public_profile_expanded_header.dart';

Future<double> _gapFor(WidgetTester tester, PublicProfile profile,
    {double textScale = 1.0}) async {
  late double allocated;
  await tester.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(393, 852),
        padding: const EdgeInsets.only(top: 59, bottom: 34),
        textScaler: TextScaler.linear(textScale),
      ),
      child: Builder(builder: (context) {
        allocated =
            PublicProfileHeaderMetrics.resolve(context, profile).identityHeight;
        return Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 393,
              child: IntrinsicHeight(
                child: PublicProfileExpandedHeader(
                  profile: profile,
                  followBusy: false,
                  chatEnabled: true,
                ),
              ),
            ),
          ),
        );
      }),
    ),
  ));
  final content =
      tester.getSize(find.byType(PublicProfileExpandedHeader)).height;
  return allocated - content;
}

void main() {
  const officialShortBio = PublicProfile(
    id: 'o', name: 'Natalo Petshop Official', username: 'natalopetshop',
    bio: 'Akun resmi Natalo Petshop & Aquarium', isOfficial: true,
    isFollowing: true, postCount: 17, followersCount: 1, followingCount: 1,
  );
  const regularShortBio = PublicProfile(
    id: 'r', name: 'Mona', username: 'mona', bio: 'Cat mom',
    postCount: 3, followersCount: 5, followingCount: 9,
  );
  const regularLongBio = PublicProfile(
    id: 'r2', name: 'Mona', username: 'mona',
    bio: 'Keseharian dua anabul, camilan favorit, tips bermain, dan cerita '
        'lucu setiap hari yang panjang sampai dua baris penuh pasti',
    postCount: 3, followersCount: 5, followingCount: 9,
  );

  for (final (label, profile) in [
    ('official short bio', officialShortBio),
    ('regular short bio', regularShortBio),
    ('regular long bio', regularLongBio),
  ]) {
    testWidgets('gap $label is tight and non-negative', (tester) async {
      final gap = await _gapFor(tester, profile);
      expect(gap, greaterThanOrEqualTo(0),
          reason: '$label: konten tidak boleh ter-clip (gap<0)');
      expect(gap, lessThanOrEqualTo(14),
          reason: '$label: rongga harus rapat (≤14px)');
    });
  }

  testWidgets('gap official at text-scale 1.3 stays non-negative',
      (tester) async {
    final gap = await _gapFor(tester, officialShortBio, textScale: 1.3);
    expect(gap, greaterThanOrEqualTo(0));
  });
}
```

- [ ] **Step 2: Jalankan test → GAGAL**

Run: `cd flutter_app && flutter test test/widgets/public_profile_gap_test.dart`
Expected: FAIL pada kasus bio 1-baris (gap ~45 > 14), karena `_identityHeight` sekarang mereservasi bio 2 baris + slack.

- [ ] **Step 3: Ukur bio via TextPainter di `resolve` + ubah `_identityHeight`**

Di `PublicProfileHeaderMetrics.resolve`, sebelum memanggil `_identityHeight`, ukur tinggi blok bio memakai lebar konten sebenarnya (lebar layar − padding kiri-kanan `AppSpacing.lg` masing-masing). Perlu import `dart:ui` untuk `TextDirection`? Tidak — pakai `TextDirection.ltr` dari `dart:ui` yang sudah terekspor via material. Tambah:

```dart
    final bioText = profile.bio?.trim() ?? '';
    double bioBlockHeight = 0;
    if (bioText.isNotEmpty) {
      final availableWidth =
          MediaQuery.sizeOf(context).width - (16 * 2); // AppSpacing.lg kiri+kanan
      final painter = TextPainter(
        text: TextSpan(
          text: bioText,
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        maxLines: 2,
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout(maxWidth: availableWidth);
      bioBlockHeight = 8 + painter.height; // 8 = AppSpacing.sm gap sebelum bio
    }
```

(`scaler` sudah ada di `resolve`: `final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 2);`.)

Lalu ganti pemanggilan `_identityHeight(... hasBio: hasBio ...)` menjadi `_identityHeight(... bioBlockHeight: bioBlockHeight ...)`.

Ubah signature + body `_identityHeight`:

```dart
  static double _identityHeight({
    required double scale,
    required double bioBlockHeight,
    required bool hasMutuals,
    required bool isOfficial,
  }) {
    const fixedRows = 12.0 + 72 + 12 + 12 + 44 + 12;
    final nameRow = (15 * 1.15 * scale).clamp(16.0, double.infinity);
    final chip = isOfficial ? 6 + (10.5 * 1.25 * scale) + 10 : 0.0;
    final mutuals = hasMutuals ? 8 + 30.0 : 0.0;
    final safety = 2 + (scale - 1) * 6;
    return fixedRows + nameRow + chip + bioBlockHeight + mutuals + safety;
  }
```

- [ ] **Step 4: Jalankan test pengukuran → LULUS (kalibrasi bila perlu)**

Run: `cd flutter_app && flutter test test/widgets/public_profile_gap_test.dart`
Expected: PASS semua. Kalau ADA kasus gap masih > 14 (mis. slack di `fixedRows`/`nameRow`/`chip`/`safety` masih menyisakan rongga), turunkan slack seperlunya: kurangi konstanta `safety` (mis. `2` → `1`) atau sesuaikan estimasi yang jelas kelebihan, JALANKAN ULANG test, sampai semua kasus 0 ≤ gap ≤ 14. JANGAN sampai ada gap < 0 (clip). Iterasi kecil, ukur tiap kali.

- [ ] **Step 5: Regresi metrics/chrome test**

Run: `cd flutter_app && flutter test test/widgets/public_profile_chrome_overlay_test.dart test/widgets/public_profile_header_motion_test.dart`
Expected: PASS (test overflow "identity fits" harus tetap hijau — identityHeight yang lebih rapat masih ≥ konten).

- [ ] **Step 6: analyze**

Run: `cd flutter_app && flutter analyze lib/widgets/public_profile_chrome_overlay.dart`
Expected: No issues (param `hasBio` lama sudah diganti; tak ada yang menggantung).

- [ ] **Step 7: Commit**

```bash
git add flutter_app/lib/widgets/public_profile_chrome_overlay.dart flutter_app/test/widgets/public_profile_gap_test.dart
git commit -m "fix(profile): rapatkan rongga tab — ukur tinggi bio via TextPainter"
```

---

### Task 4: Regenerasi golden + verifikasi menyeluruh (controller)

**Files:** golden PNG (regenerasi).

- [ ] **Step 1: Regenerasi golden profil**

Run: `cd flutter_app && flutter test --update-goldens test/golden/public_profile_premium_test.dart test/golden/member_screen_akun_test.dart`
Expected: All tests passed (goldens ditulis ulang).

- [ ] **Step 2: Inspeksi visual (controller)** — buka `public_profile_official_expanded.png`, `public_profile_regular_expanded.png`, `public_profile_official_collapsed.png`, `member_screen_akun_ig_white.png`. Pastikan: tab rapat di bawah tombol (rongga hilang), tak ada garis panjang di bawah pill, indikator di bawah tab aktif. Kalau ada yang aneh, kembalikan ke task terkait.

- [ ] **Step 3: Full suite**

Run: `cd flutter_app && flutter test`
Expected: Hanya kegagalan pre-existing yang dikenal (`feed_comment_drawer_terminal_state_test.dart` 2 fail; `origin_expansion_route_test.dart` bila muncul). Tidak ada kegagalan baru pada `public_profile_*` / `member_screen_*`.

- [ ] **Step 4: Commit golden**

```bash
git add flutter_app/test/golden/
git commit -m "test(profile): regenerasi golden setelah polish tab bar"
```

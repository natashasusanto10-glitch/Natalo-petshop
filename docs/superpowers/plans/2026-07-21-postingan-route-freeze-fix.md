# OriginExpansionRoute Freeze Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Animasi `_OriginExpansionPageRoute` tidak pernah bisa beku — menghilangkan ghost viewer semi-transparan, layar menelan input, dan profil "terdorong ke atas".

**Architecture:** Tiga guard kecil di mesin gesture `lib/widgets/origin_expansion_route.dart` (dragUpdate guard+clamp; abort melanjutkan animasi; gesture hanya mulai saat animasi buka selesai) + widget test dismiss-reliability + test restore profil (fix kondisional berbasis bukti test).

**Tech Stack:** Flutter/Dart, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-07-21-postingan-route-freeze-ghost-design.md`
**Branch:** `claude/postingan-route-freeze-fix` (off origin/main; spec ter-commit)
**Working dir:** perintah flutter dari `flutter_app/`

## Global Constraints

- Kurva/durasi morph TIDAK berubah: `_kOriginOpenCurve`/`_kOriginCloseCurve`, 300ms buka / 250ms tutup (baris 15-16, 104-107).
- Ambang gesture TIDAK berubah: `_originBackGestureWidth 28` / `_originBackCompletionFraction 0.25` / `_originBackFlingVelocity 800`.
- Arsitektur route tetap non-opaque + snapshot morph; TIDAK ada watchdog timer (gotcha comment-drawer: watchdog menutupi kegagalan test).
- Invariant yang ditegakkan (dari spec): I1 route ter-pop wajib mencapai dismissed; I2 tiap jalur akhir gesture = current@1.0 ATAU popped→0.0, tak pernah beku; I3 gesture hanya mulai saat `status == completed`; I4 profil pulih posisi + responsif setelah back.
- Test: bounded pump (JANGAN pumpAndSettle di layar app dengan animasi abadi; untuk harness route sintetis boleh pump berdurasi).
- Suite penuh dibandingkan dengan baseline 9 kegagalan pre-existing terdokumentasi (feed/video/member/golden) — kegagalan baru = regresi.

---

### Task 1: Guard mesin gesture + widget test dismiss-reliability

**Files:**
- Modify: `flutter_app/lib/widgets/origin_expansion_route.dart`
- Test (create): `flutter_app/test/widgets/origin_expansion_route_dismiss_test.dart`

**Interfaces:**
- Consumes: `debugOriginExpansionStatusObserver` (hook test existing, baris 8-10), `pushOriginExpansion` (baris 37).
- Produces: perilaku route yang dipakai semua layar pemakai; tidak ada API baru.

- [ ] **Step 1: Tulis failing test**

Buat `flutter_app/test/widgets/origin_expansion_route_dismiss_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/widgets/origin_expansion_route.dart';

/// Harness: home + tombol buka viewer via pushOriginExpansion (originKey
/// tidak ter-attach → jalur fade-only, cukup untuk menguji mesin dismiss).
class _Harness extends StatelessWidget {
  const _Harness({required this.navKey, required this.onHomeTap});
  final GlobalKey<NavigatorState> navKey;
  final VoidCallback onHomeTap;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navKey,
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                key: const ValueKey('home-tap-probe'),
                onPressed: onHomeTap,
                child: const Text('probe'),
              ),
              Builder(
                builder: (context) => TextButton(
                  key: const ValueKey('open-viewer'),
                  onPressed: () => pushOriginExpansion<void>(
                    context,
                    originKey: GlobalKey(),
                    destinationBuilder: (_) => const Scaffold(
                      backgroundColor: Colors.black,
                      body: Center(
                        child: Text('VIEWER',
                            style: TextStyle(color: Colors.white)),
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _openViewer(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('open-viewer')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350)); // buka 300ms selesai
  expect(find.text('VIEWER'), findsOneWidget);
}

void main() {
  late List<AnimationStatus> statuses;

  setUp(() {
    statuses = [];
    debugOriginExpansionStatusObserver = (status, _) => statuses.add(status);
  });

  tearDown(() => debugOriginExpansionStatusObserver = null);

  testWidgets('pop programatik saat drag aktif → route tetap tuntas tertutup',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    var probeTaps = 0;
    await tester.pumpWidget(
        _Harness(navKey: navKey, onHomeTap: () => probeTaps++));
    await _openViewer(tester);

    // Mulai drag tepi kiri.
    final gesture = await tester.startGesture(const Offset(10, 300));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();

    // Pop datang dari sumber lain (tombol back AppBar / back sistem).
    navKey.currentState!.pop();
    await tester.pump();

    // Jari masih bergerak lalu lepas — dulu ini membekukan animasi.
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    await gesture.up();

    // Beri waktu animasi penutup selesai (reverse 250ms) + finalisasi.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('VIEWER'), findsNothing,
        reason: 'viewer tidak boleh menyisa (ghost)');
    expect(statuses.last, AnimationStatus.dismissed,
        reason: 'route wajib mencapai dismissed (I1)');
    // Barrier tidak boleh menyisa menelan input.
    await tester.tap(find.byKey(const ValueKey('home-tap-probe')));
    expect(probeTaps, 1);
  });

  testWidgets('drag mentok penuh lalu lepas → route terfinalisasi, tanpa '
      'barrier menyisa', (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    var probeTaps = 0;
    await tester.pumpWidget(
        _Harness(navKey: navKey, onHomeTap: () => probeTaps++));
    await _openViewer(tester);

    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final gesture = await tester.startGesture(const Offset(10, 300));
    // Drag melebihi lebar layar → tanpa clamp, nilai menyentuh 0 pra-pop.
    await gesture.moveBy(Offset(width + 200, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('VIEWER'), findsNothing);
    expect(statuses.last, AnimationStatus.dismissed);
    await tester.tap(find.byKey(const ValueKey('home-tap-probe')));
    expect(probeTaps, 1, reason: 'input tidak boleh dimakan barrier mati');
  });

  testWidgets('drag tanggung lalu lepas → spring back, viewer utuh',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_Harness(navKey: navKey, onHomeTap: () {}));
    await _openViewer(tester);

    final gesture = await tester.startGesture(const Offset(10, 300));
    await gesture.moveBy(const Offset(50, 0)); // < 25% lebar, tanpa fling
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('VIEWER'), findsOneWidget);
    expect(statuses.last, AnimationStatus.completed,
        reason: 'spring back wajib berakhir completed (I2)');
  });

  testWidgets('drag tepi saat animasi BUKA berjalan → tidak membekukan buka',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_Harness(navKey: navKey, onHomeTap: () {}));
    await tester.tap(find.byKey(const ValueKey('open-viewer')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100)); // buka masih jalan

    final gesture = await tester.startGesture(const Offset(10, 300));
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 500));

    expect(statuses.last, AnimationStatus.completed,
        reason: 'animasi buka wajib mencapai completed (I3)');
    expect(find.text('VIEWER'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Jalankan — pastikan gagal karena perilaku lama**

Run: `cd flutter_app && flutter test test/widgets/origin_expansion_route_dismiss_test.dart`
Expected: test 1 dan/atau 2 FAIL (viewer menyisa / status bukan dismissed / probe tap tertelan); test 3 diharapkan PASS (regresi existing); test 4 kemungkinan FAIL.

- [ ] **Step 3: Terapkan 3 guard di `origin_expansion_route.dart`**

3a. `dragUpdate` (baris 273-276) GANTI menjadi:

```dart
  void dragUpdate(double delta) {
    if (!_active) return;
    // Route sudah ter-pop dari sumber lain saat jari masih di layar —
    // reverse() yang sedang berjalan TIDAK boleh dihentikan oleh drag.
    if (!getIsCurrent()) return;
    // Clamp bawah ke epsilon: nilai tidak boleh menyentuh 0.0 selagi
    // route masih current — status `dismissed` prematur membuat pop
    // berikutnya tidak menghasilkan notifikasi status baru → route tak
    // pernah difinalisasi (mati-tak-terlihat + barrier menelan input).
    controller.value = (controller.value - delta).clamp(0.001, 1.0);
  }
```

3b. `abort` (baris 296-298) GANTI menjadi:

```dart
  void abort() {
    // Route sudah ter-pop tapi animasi penutup terhenti/belum selesai →
    // lanjutkan sampai dismissed supaya framework memfinalisasi route
    // (overlay + barrier dilepas). Tanpa ini: ghost beku permanen.
    // Guard navigator.mounted: abort juga dipanggil dari route.dispose()
    // saat navigator dibongkar — jangan memulai animasi di situ.
    if (navigator.mounted &&
        !getIsCurrent() &&
        controller.status != AnimationStatus.dismissed &&
        !controller.isAnimating) {
      controller.animateBack(0, curve: _kOriginCloseCurve);
    }
    _finish();
  }
```

3c. `buildTransitions` → `enabledCallback` (baris 131) GANTI menjadi:

```dart
      enabledCallback: () =>
          popGestureEnabled &&
          controller!.status == AnimationStatus.completed,
```

- [ ] **Step 4: Jalankan test — pastikan pass**

Run: `cd flutter_app && flutter test test/widgets/origin_expansion_route_dismiss_test.dart`
Expected: 4/4 PASS.

- [ ] **Step 5: Regresi test existing route**

Run: `cd flutter_app && flutter test test/widgets/origin_expansion_route_test.dart`
Expected: semua PASS tanpa perubahan.

- [ ] **Step 6: Analyze + commit**

Run: `cd flutter_app && flutter analyze lib/widgets/origin_expansion_route.dart test/widgets/origin_expansion_route_dismiss_test.dart`
Expected: No issues found.

```bash
git add flutter_app/lib/widgets/origin_expansion_route.dart flutter_app/test/widgets/origin_expansion_route_dismiss_test.dart
git commit -m "fix(postingan): animasi OriginExpansionRoute tak bisa beku — 3 guard mesin gesture"
```

---

### Task 2: Test restore profil (I4) + fix kondisional

**Files:**
- Test (create): `flutter_app/test/screens/member_screen_profile_restore_test.dart`
- Modify (KONDISIONAL — hanya bila test membuktikan penyebab kedua): `flutter_app/lib/screens/member_screen.dart`

**Interfaces:**
- Consumes: harness mount MemberScreen dari test existing `flutter_app/test/screens/member_screen_test.dart` (pelajari dan tiru seam mock/fetcher-nya persis), perilaku route hasil Task 1.

- [ ] **Step 1: Pelajari harness `member_screen_test.dart`** — cara mount MemberScreen (mock prefs, memberStore, feedService seam, bounded pump). Tiru pola yang sama.

- [ ] **Step 2: Tulis test restore profil**

Skenario (kode konkret mengikuti harness yang dipelajari di Step 1 — struktur wajib):

```dart
// 1. Mount MemberScreen (profil sendiri) dengan ≥1 post di grid.
// 2. Pastikan blok identitas terlihat (mis. find tombol 'Edit Profil').
// 3. Tap tile grid pertama → viewer terbuka (pump 350ms).
// 4. Pop (navKey.currentState!.pop()) → pump 400ms + 100ms.
// 5. Assert: find 'Edit Profil' MASIH terlihat (identitas tidak hilang);
//    tap satu elemen profil (mis. tab bar) BERFUNGSI (tidak dimakan
//    barrier). Bounded pump saja — JANGAN pumpAndSettle.
```

- [ ] **Step 3: Jalankan**

Run: `cd flutter_app && flutter test test/screens/member_screen_profile_restore_test.dart`

- Bila PASS → hipotesis utama benar (gejala profil = hilir bug barrier, sudah sembuh oleh Task 1). Lanjut Step 5.
- Bila FAIL karena offset outer NestedScrollView bergeser setelah rebuild `_loadAll()` → Step 4.

- [ ] **Step 4 (KONDISIONAL): Fix pergeseran offset di `member_screen.dart`**

Hanya bila Step 3 membuktikan: pertahankan offset outer saat grid di-rebuild pasca pop (mis. tunda `_loadAll()` refresh yang menggeser layout, atau pertahankan `PageStorageKey`/posisi scroll). JANGAN mengubah struktur NestedScrollView. Jalankan ulang test sampai pass; dokumentasikan temuan di report.

- [ ] **Step 5: Commit**

```bash
git add flutter_app/test/screens/member_screen_profile_restore_test.dart
# + member_screen.dart bila Step 4 terjadi
git commit -m "test(postingan): bukti profil pulih posisi + responsif setelah back dari viewer"
```

---

### Task 3: Verifikasi akhir

- [ ] **Step 1:** `cd flutter_app && flutter analyze` → tidak ada issue BARU di file yang disentuh.
- [ ] **Step 2:** `cd flutter_app && flutter test` → bandingkan dengan baseline (865 pass / 2 skip / 9 fail pre-existing per 2026-07-19; angka pass bisa bertambah oleh test baru). Kegagalan baru = regresi, wajib dibereskan.
- [ ] **Step 3:** Checklist device-verify (dokumentasi, eksekusi oleh user di iOS + Android): profil→post→back berulang; tombol back ditekan SAAT jari men-drag tepi; swipe tanggung; swipe cepat penuh; buka post lalu langsung sentuh tepi kiri saat animasi buka; scroll antar-post di viewer (ghost header hilang).
- [ ] **Step 4:** Commit sisa perbaikan bila ada.

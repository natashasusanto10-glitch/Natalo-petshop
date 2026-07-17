# Feed morph polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Morph video terasa halus seperti IG: media tak meregang saat membesar (clip-window), framing entry = fullscreen, opacity crossfade bersumber satu formula, dan sheet komentar simetris buka/tutup.

**Architecture:** Ganti mekanik snapshot di `scaled_video_feed_route.dart` dari "lerp width/height bebas + BoxFit.cover" menjadi clip-window: media dirender seukuran layar (fitWidth+topCenter) di dalam `OverflowBox`, hanya jendela `Positioned`+`ClipRRect` yang membesar. Geometri clip tetap dihitung di dalam `AnimatedBuilder` (agar `Positioned` tetap anak-langsung Stack); isi jendela diekstrak ke widget teruji `ScaledVideoFeedMorphContent` dengan seam `imageBuilder` untuk menghindari `CachedNetworkImage` di test. Terpisah: satu baris kurva simetri di `feed_comment_sheet.dart`.

**Tech Stack:** Flutter/Dart, `flutter_test`.

## Global Constraints

- Fit & align morph disamakan dengan fullscreen `_MediaLayer`: `BoxFit.fitWidth` + `Alignment.topCenter` (lihat `feed_video_post_view.dart:3527,3534`).
- Media di dalam jendela SELALU berukuran `screenSize` (via OverflowBox) — tak pernah meregang.
- Opacity crossfade bersumber satu formula: `const Interval(0.55, 1.0, curve: Curves.easeIn).transform(animation.value)` — snapshot pakai `1 - itu`, destinasi pakai `itu`. Tidak boleh ada objek `CurvedAnimation` baru per-build.
- `borderRadius` jendela = `activeBorderRadius * (1 - t)` dengan `t = curved.value` (sama seperti rect).
- `Positioned` WAJIB anak langsung dari `AnimatedBuilder` yang duduk langsung di Stack — JANGAN sisipkan RenderObjectWidget (IgnorePointer/Opacity/dll) antara Stack dan Positioned. Widget baru ditempatkan sebagai anak DI DALAM Positioned.
- Durasi 260/220ms tidak diubah. `mainFeed` (`BoxFit.cover`) tidak diubah. `origin_expansion_route.dart` tidak diubah.
- Nama paket: `natalo_petshop_flutter`.

---

### Task 1: Clip-window morph + opacity satu sumber (#2 + #3 + #4)

**Files:**
- Modify: `flutter_app/lib/widgets/scaled_video_feed_route.dart`
- Test: `flutter_app/test/widgets/scaled_video_feed_morph_content_test.dart` (create)

**Interfaces:**
- Produces:
  - `typedef ScaledVideoFeedImageBuilder = Widget Function(BuildContext, String imageUrl);`
  - `class ScaledVideoFeedMorphContent extends StatelessWidget` dengan named params `{required Size screenSize, required String imageUrl, required double borderRadius, required double opacity, ScaledVideoFeedImageBuilder? imageBuilder}`.

- [ ] **Step 1: Tulis test yang gagal**

Buat `flutter_app/test/widgets/scaled_video_feed_morph_content_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/widgets/scaled_video_feed_route.dart';

void main() {
  const screen = Size(400, 900);
  final childKey = GlobalKey();

  Widget harness({required Size window}) {
    return MaterialApp(
      home: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: 0,
              top: 0,
              width: window.width,
              height: window.height,
              child: ScaledVideoFeedMorphContent(
                screenSize: screen,
                imageUrl: 'x',
                borderRadius: 8,
                opacity: 1,
                imageBuilder: (_, __) =>
                    SizedBox(key: childKey, width: screen.width, height: screen.height),
              ),
            ),
          ],
        ),
      ),
    );
  }

  testWidgets('media child stays screen-sized in a small window (no stretch)',
      (tester) async {
    await tester.pumpWidget(harness(window: const Size(120, 150)));
    // OverflowBox memaksa child ke ukuran layar penuh walau jendela kecil.
    expect(tester.getSize(find.byKey(childKey)), screen);
  });

  testWidgets('media child stays screen-sized in a large window (no stretch)',
      (tester) async {
    await tester.pumpWidget(harness(window: const Size(400, 900)));
    expect(tester.getSize(find.byKey(childKey)), screen);
  });

  testWidgets('opacity is applied to the morph content', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                left: 0,
                top: 0,
                width: 120,
                height: 150,
                child: ScaledVideoFeedMorphContent(
                  screenSize: screen,
                  imageUrl: 'x',
                  borderRadius: 8,
                  opacity: 0.3,
                  imageBuilder: (_, __) => const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final opacity = tester.widget<Opacity>(
      find.descendant(
        of: find.byType(ScaledVideoFeedMorphContent),
        matching: find.byType(Opacity),
      ),
    );
    expect(opacity.opacity, 0.3);
  });
}
```

- [ ] **Step 2: Jalankan test — GAGAL**

Run: `cd flutter_app && flutter test test/widgets/scaled_video_feed_morph_content_test.dart`
Expected: FAIL — `ScaledVideoFeedMorphContent` belum ada (compile error).

- [ ] **Step 3: Tambah widget `ScaledVideoFeedMorphContent`**

Di `flutter_app/lib/widgets/scaled_video_feed_route.dart`, tambahkan sebelum `pushScaledVideoFeed` (setelah class `ScaledVideoFeedReverseTarget`):

```dart
typedef ScaledVideoFeedImageBuilder = Widget Function(
    BuildContext context, String imageUrl);

/// Isi jendela morph. Media dirender SEUKURAN [screenSize] (fitWidth + topCenter,
/// identik framing fullscreen `_MediaLayer`) di dalam OverflowBox, sehingga saat
/// jendela luar (Positioned) membesar/mengecil, media TIDAK meregang — hanya
/// tersingkap (clip-window ala IG).
class ScaledVideoFeedMorphContent extends StatelessWidget {
  const ScaledVideoFeedMorphContent({
    super.key,
    required this.screenSize,
    required this.imageUrl,
    required this.borderRadius,
    required this.opacity,
    this.imageBuilder,
  });

  final Size screenSize;
  final String imageUrl;
  final double borderRadius;
  final double opacity;
  final ScaledVideoFeedImageBuilder? imageBuilder;

  @override
  Widget build(BuildContext context) {
    final image = (imageBuilder ?? _defaultImage)(context, imageUrl);
    return IgnorePointer(
      child: Opacity(
        opacity: opacity,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: OverflowBox(
            alignment: Alignment.topCenter,
            minWidth: screenSize.width,
            maxWidth: screenSize.width,
            minHeight: screenSize.height,
            maxHeight: screenSize.height,
            child: image,
          ),
        ),
      ),
    );
  }

  static Widget _defaultImage(BuildContext context, String imageUrl) =>
      CachedNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.fitWidth,
        alignment: Alignment.topCenter,
        errorWidget: (_, __, ___) => const ColoredBox(color: Colors.black),
      );
}
```

- [ ] **Step 4: Jalankan test — LULUS**

Run: `cd flutter_app && flutter test test/widgets/scaled_video_feed_morph_content_test.dart`
Expected: PASS (3 test).

- [ ] **Step 5: Ganti mekanik snapshot di route builder**

Di `scaled_video_feed_route.dart`, di dalam `buildTransition`, ganti blok `AnimatedBuilder(... Positioned ... CachedNetworkImage fit: BoxFit.cover ...)` (blok snapshot, saat ini sekitar baris 95-137) dengan:

```dart
                AnimatedBuilder(
                  animation: animation,
                  builder: (context, _) {
                    final t = curved.value;
                    final left =
                        activeOrigin.left + (0 - activeOrigin.left) * t;
                    final top = activeOrigin.top + (0 - activeOrigin.top) * t;
                    final width = activeOrigin.width +
                        (screenSize.width - activeOrigin.width) * t;
                    final height = activeOrigin.height +
                        (screenSize.height - activeOrigin.height) * t;
                    final revealT = const Interval(0.55, 1.0,
                            curve: Curves.easeIn)
                        .transform(animation.value);
                    return Positioned(
                      left: left,
                      top: top,
                      width: width,
                      height: height,
                      child: ScaledVideoFeedMorphContent(
                        screenSize: screenSize,
                        imageUrl: activeImageUrl,
                        borderRadius: activeBorderRadius * (1 - t),
                        opacity: 1 - revealT,
                      ),
                    );
                  },
                ),
```

Catatan: `Positioned` tetap anak langsung dari `AnimatedBuilder` (yang duduk di Stack) — struktur ini dipertahankan persis; `ScaledVideoFeedMorphContent` berada DI DALAM Positioned. JANGAN memindah IgnorePointer/Opacity ke luar Positioned.

- [ ] **Step 6: Satukan sumber opacity destinasi (#4)**

Di `buildTransition`, ganti `FadeTransition` yang membungkus `child` (destinasi, saat ini sekitar baris 78-84, memakai `CurvedAnimation(parent: animation, curve: Interval(0.55,1.0,easeIn))`) dengan `AnimatedBuilder` yang memakai formula yang sama, tanpa objek CurvedAnimation:

```dart
              AnimatedBuilder(
                animation: animation,
                builder: (context, child) => Opacity(
                  opacity: const Interval(0.55, 1.0, curve: Curves.easeIn)
                      .transform(animation.value),
                  child: child,
                ),
                child: child,
              ),
```

- [ ] **Step 7: Analyze**

Run: `cd flutter_app && flutter analyze lib/widgets/scaled_video_feed_route.dart test/widgets/scaled_video_feed_morph_content_test.dart`
Expected: No issues. (Pastikan tak ada import `FadeTransition`/`CurvedAnimation` yatim atau variabel tak terpakai.)

- [ ] **Step 8: Test morph content + regresi route yang ada**

Run: `cd flutter_app && flutter test test/widgets/scaled_video_feed_morph_content_test.dart`
Expected: PASS (3). (Tak ada test route lama yang perlu diubah; jika `flutter test` menemukan test lain yang menyentuh file ini, jalankan dan pastikan hijau.)

- [ ] **Step 9: Commit**

```bash
git add flutter_app/lib/widgets/scaled_video_feed_route.dart flutter_app/test/widgets/scaled_video_feed_morph_content_test.dart
git commit -m "feat(feed): morph video clip-window (anti-melar) + opacity satu sumber"
```

---

### Task 2: Simetri kurva buka/tutup comment media frame (#6)

**Files:**
- Modify: `flutter_app/lib/widgets/feed_comment_sheet.dart:375`
- Test: `flutter_app/test/widgets/feed_comment_media_frame_test.dart` (perluas)

**Interfaces:**
- Consumes: `FeedCommentMediaFrame` (tak berubah signature).

- [ ] **Step 1: Tulis test simetri yang gagal**

Tambahkan test ke `flutter_app/test/widgets/feed_comment_media_frame_test.dart`:

```dart
  testWidgets('media frame uses easeOutCubic for both open and close',
      (tester) async {
    for (final open in [true, false]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              fit: StackFit.expand,
              children: [
                FeedCommentMediaFrame(
                  open: open,
                  extentListenable: ValueNotifier<double>(0.60),
                  dragOffsetPx: 0,
                  keyboardInsetPx: 0,
                  screenSize: const Size(400, 900),
                  child: const ColoredBox(color: Colors.orange),
                ),
              ],
            ),
          ),
        ),
      );
      final anim = tester.widget<TweenAnimationBuilder<double>>(
        find.byType(TweenAnimationBuilder<double>),
      );
      expect(anim.curve, Curves.easeOutCubic,
          reason: 'open=$open harus easeOutCubic');
    }
  });
```

- [ ] **Step 2: Jalankan test — GAGAL**

Run: `cd flutter_app && flutter test test/widgets/feed_comment_media_frame_test.dart`
Expected: FAIL pada iterasi `open=false` (kurva saat ini `easeInOutCubic`).

- [ ] **Step 3: Samakan kurva**

Di `flutter_app/lib/widgets/feed_comment_sheet.dart:375`, ganti:

```dart
      curve: open ? Curves.easeOutCubic : Curves.easeInOutCubic,
```

menjadi:

```dart
      curve: Curves.easeOutCubic,
```

(Durasi `Duration(milliseconds: open ? 260 : 220)` di baris 374 DIBIARKAN.)

- [ ] **Step 4: Jalankan test — LULUS**

Run: `cd flutter_app && flutter test test/widgets/feed_comment_media_frame_test.dart`
Expected: PASS (test lama + test simetri baru).

- [ ] **Step 5: Analyze + commit**

```bash
cd flutter_app && flutter analyze lib/widgets/feed_comment_sheet.dart
git add flutter_app/lib/widgets/feed_comment_sheet.dart flutter_app/test/widgets/feed_comment_media_frame_test.dart
git commit -m "fix(feed): comment media frame simetris (easeOutCubic buka & tutup)"
```

---

## Catatan verifikasi akhir (device)

Geometri anti-melar & passthrough opacity/radius tercakup unit test Task 1;
simetri #6 tercakup Task 2. Yang TIDAK ter-unit-test: rect-lerp jendela &
penyatuan sumber opacity destinasi di route builder (mekanikal, dinilai via
review diff — bukan test baru, karena mem-pump route penuh butuh infra video
destinasi). Paritas visual final butuh **device-verify**: tap video (Detail
Produk & Postingan) → morph membesar tanpa media melar, mulus ke fullscreen;
buka/tutup sheet komentar terasa simetris.

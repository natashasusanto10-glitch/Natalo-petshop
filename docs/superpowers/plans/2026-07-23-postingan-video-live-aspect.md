# Postingan Video Live-Aspect (Opsi A) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hilangkan bar hitam kiri-kanan pada video di halaman Postingan dengan membangun kotak video dari ukuran video ASLI (controller.value.size) begitu tersedia, bukan dari metadata dimensi tersimpan yang kadang salah (landscape untuk video portrait — sisa bug rotasi Bunny).

**Architecture:** Ekstrak pemilihan aspect-ratio jadi fungsi murni `resolvePostinganVideoBoxAspectRatio` (mudah diuji unit). Tambah widget reaktif `_VideoAspectBox` yang mendengarkan coordinator (registry + session.revision) dan me-rebuild `AspectRatio` video memakai ukuran asli controller begitu siap, fallback ke rasio tersimpan sebelum siap. HANYA jalur VIDEO yang berubah; foto & carousel tetap memakai rasio tersimpan; file feed/fullscreen TIDAK disentuh.

**Tech Stack:** Flutter (Dart), `PostVideoCoordinator`/`VideoPlayerSession` (registryListenable + revision), flutter_test.

## Global Constraints

- Semua kerja di branch `claude/postingan-video-live-aspect` (sudah dibuat off `origin/main`).
- Working dir test/analyze: `flutter_app/` (jalankan `flutter test`/`flutter analyze` dari situ).
- HANYA edit `flutter_app/lib/screens/member_post_detail_screen.dart` dan `flutter_app/lib/features/feed/layout/postingan_media_aspect_ratio.dart` (+ file test terkait). JANGAN sentuh `feed_video_post_view.dart`, `feed_screen.dart`, `scoped_video_feed_screen.dart` — feed & fullscreen sudah benar dan harus tetap.
- JANGAN mengubah mode fit video Postingan dari `BoxFit.contain` → tetap contain (tidak memotong konten). Yang diperbaiki hanya BENTUK KOTAK.
- Foto & carousel di halaman Postingan TIDAK boleh berubah perilakunya (tetap rasio tersimpan).
- Landscape (video lebih lebar dari kotak) HARUS tetap letterbox hitam ATAS-BAWAH seperti sekarang.
- Gaya komentar kode: bahasa Indonesia, jelaskan KENAPA (ikuti konvensi file sekitar).
- Setelah semua task: `flutter analyze` bersih pada file yang diubah + seluruh test suite `test/screens/member_post_detail_*` + `test/screens/postingan_landscape_framing_test.dart` + `test/features/feed/layout/` lolos. WAJIB device-verify oleh user sebelum final; PR JANGAN di-merge sebelum itu.

## Konteks untuk implementer (kenapa desain ini)

Bug: video portrait dengan metadata dimensi SALAH (landscape) → `resolvePostinganMediaAspectRatio` menghasilkan kotak LEBAR → `FittedBox(contain)` memasukkan video portrait ke kotak lebar → **bar hitam kiri-kanan** (pillarbox). Feed/fullscreen tidak kena karena mereka menghitung rasio dari `controller.value.size` (ukuran asli, sudah dirotasi benar player) di dalam viewport penuh — bukan dari metadata.

Perbaikan: halaman Postingan ikut memakai ukuran asli controller untuk BENTUK KOTAK-nya. Pola listen mengikuti `_HeroVideoFlightSurface` yang sudah ada (member_post_detail_screen.dart ~3350): `coordinator.sessionFor(postId)` → cast `is VideoPlayerSession` → `session.revision` (ValueNotifier<int>, fire saat init selesai) → baca `controller.value.size`. Sesi bisa BELUM ada saat build pertama (attach lazily saat terlihat) → dengarkan juga `coordinator.registryListenable` (ValueListenable<int>, fire saat sesi register/unregister) untuk re-bind (lihat komentar coordinator ~line 162).

Konsekuensi yang SUDAH disetujui user: saat controller belum siap, kotak sekilas memakai rasio tersimpan lalu "loncat" ke rasio asli saat video muncul. Ini diterima. `_estimatedPostExtent` (estimasi tinggi untuk scroll) tetap pakai rasio tersimpan — hanya estimasi awal, Flutter mengoreksi saat item ter-build; JANGAN diubah di plan ini.

---

### Task 1: Fungsi murni `resolvePostinganVideoBoxAspectRatio` + unit test

**Files:**
- Modify: `flutter_app/lib/features/feed/layout/postingan_media_aspect_ratio.dart`
- Test: `flutter_app/test/features/feed/layout/postingan_media_aspect_ratio_test.dart`

**Interfaces:**
- Consumes: `resolvePostinganMediaAspectRatio` (sudah ada di file yang sama), `FeedContentType` (dari `feed_post.dart`), `Size` (dart:ui via flutter widgets).
- Produces (dipakai Task 2): `double resolvePostinganVideoBoxAspectRatio({required double fallbackAspectRatio, Size? liveSize})`.

- [ ] **Step 1: Tulis failing unit test**

Tambahkan group baru di akhir `main()` file `postingan_media_aspect_ratio_test.dart` (pertahankan import yang ada; tambahkan `import 'dart:ui' show Size;` bila belum ada — bila sudah ada `package:flutter/...` yang mengekspor Size, pakai itu):

```dart
  group('resolvePostinganVideoBoxAspectRatio — pilih ukuran asli vs fallback', () {
    // fallback landscape 16:9 = 1.7778 (mensimulasikan metadata SALAH).
    const fallbackLandscape = 16 / 9;

    test('liveSize null (controller belum siap) → pakai fallback', () {
      expect(
        resolvePostinganVideoBoxAspectRatio(
          fallbackAspectRatio: fallbackLandscape,
          liveSize: null,
        ),
        fallbackLandscape,
      );
    });

    test('KUNCI: liveSize portrait walau fallback landscape → rasio portrait '
        '(kotak portrait → tak ada bar kiri-kanan)', () {
      final r = resolvePostinganVideoBoxAspectRatio(
        fallbackAspectRatio: fallbackLandscape,
        liveSize: const Size(1080, 1920),
      );
      expect(r, closeTo(9 / 16, 1e-9));
    });

    test('liveSize landscape lebih lebar dari 1.91 → clamp 1.91 '
        '(letterbox atas-bawah tetap)', () {
      final r = resolvePostinganVideoBoxAspectRatio(
        fallbackAspectRatio: 9 / 16,
        liveSize: const Size(2560, 1080), // 2.37
      );
      expect(r, closeTo(1.91, 1e-9));
    });

    test('liveSize 0/invalid → pakai fallback', () {
      expect(
        resolvePostinganVideoBoxAspectRatio(
          fallbackAspectRatio: fallbackLandscape,
          liveSize: const Size(0, 0),
        ),
        fallbackLandscape,
      );
    });

    test('liveSize portrait normal 9:16 → 9:16', () {
      final r = resolvePostinganVideoBoxAspectRatio(
        fallbackAspectRatio: 9 / 16,
        liveSize: const Size(1080, 1920),
      );
      expect(r, closeTo(9 / 16, 1e-9));
    });
  });
```

- [ ] **Step 2: Jalankan test — pastikan GAGAL**

Run: `flutter test test/features/feed/layout/postingan_media_aspect_ratio_test.dart`
Expected: FAIL — `resolvePostinganVideoBoxAspectRatio` belum ada (compile error).

- [ ] **Step 3: Implementasi fungsi**

Tambahkan di `postingan_media_aspect_ratio.dart`. Import `Size` bila belum: `import 'dart:ui' show Size;` di atas. Lalu:

```dart
/// Aspect ratio KOTAK video halaman Postingan.
///
/// Pakai ukuran video ASLI [liveSize] (dari `controller.value.size`, sudah
/// dirotasi benar oleh player) begitu tersedia & valid; sebelum controller
/// siap, fallback ke [fallbackAspectRatio] (dari metadata tersimpan).
///
/// KENAPA: sebagian video punya metadata dimensi SALAH (landscape untuk video
/// portrait — sisa bug rotasi Bunny). Membangun kotak dari metadata itu bikin
/// video portrait masuk kotak lebar → bar hitam kiri-kanan. Ukuran asli
/// controller selalu benar, jadi jadikan itu sumber saat ada.
double resolvePostinganVideoBoxAspectRatio({
  required double fallbackAspectRatio,
  Size? liveSize,
}) {
  if (liveSize != null && liveSize.width > 0 && liveSize.height > 0) {
    return resolvePostinganMediaAspectRatio(
      width: liveSize.width.round(),
      height: liveSize.height.round(),
      type: FeedContentType.video,
    );
  }
  return fallbackAspectRatio;
}
```

- [ ] **Step 4: Jalankan test — pastikan LOLOS**

Run: `flutter test test/features/feed/layout/postingan_media_aspect_ratio_test.dart`
Expected: PASS (semua, termasuk 5 test baru).

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/features/feed/layout/postingan_media_aspect_ratio.dart flutter_app/test/features/feed/layout/postingan_media_aspect_ratio_test.dart
git commit -m "feat(postingan): helper resolvePostinganVideoBoxAspectRatio — pilih ukuran asli video"
```

---

### Task 2: Widget reaktif `_VideoAspectBox` + wire ke `_PostMediaSurface`

**Files:**
- Modify: `flutter_app/lib/screens/member_post_detail_screen.dart`
  - Tambah kelas `_VideoAspectBox` (dekat `_HeroVideoFlightSurface`, ~line 3334).
  - Ubah `_PostMediaSurface.build` (~line 3115–3175): restrukturisasi `AspectRatio` supaya jalur VIDEO memakai `_VideoAspectBox`; foto & carousel TETAP `AspectRatio(aspectRatio, ...)` seperti sekarang.
- Test: `flutter_app/test/screens/member_post_detail_video_live_aspect_test.dart` (baru; pakai infra fake dari `member_post_detail_screen_coordinator_test.dart` sebagai rujukan pola).

**Interfaces:**
- Consumes: `resolvePostinganVideoBoxAspectRatio` (Task 1), `PostVideoCoordinator.registryListenable`/`sessionFor`, `VideoPlayerSession.revision`/`controller`.
- Produces: tidak ada API publik baru keluar file.

- [ ] **Step 1: Implementasi widget `_VideoAspectBox`**

Tambahkan (mis. tepat sebelum `class _HeroVideoFlightSurface`):

```dart
/// Membungkus media video Postingan dengan [AspectRatio] yang MENGIKUTI ukuran
/// video ASLI (`controller.value.size`) begitu controller siap; sebelum itu
/// pakai [fallbackAspectRatio] (metadata tersimpan).
///
/// KENAPA: lihat [resolvePostinganVideoBoxAspectRatio] — metadata dimensi bisa
/// salah (landscape utk video portrait) → kotak lebar → bar hitam kiri-kanan.
/// Feed/fullscreen sudah pakai ukuran asli; ini menyamakan halaman Postingan.
///
/// Pola listen SAMA dengan [_HeroVideoFlightSurface]: [registryListenable]
/// (sesi muncul saat attach lazily) + `session.revision` (init selesai).
class _VideoAspectBox extends StatefulWidget {
  final PostVideoCoordinator coordinator;
  final String postId;
  final double fallbackAspectRatio;
  final Widget Function(BuildContext context, double aspectRatio) builder;

  const _VideoAspectBox({
    required this.coordinator,
    required this.postId,
    required this.fallbackAspectRatio,
    required this.builder,
  });

  @override
  State<_VideoAspectBox> createState() => _VideoAspectBoxState();
}

class _VideoAspectBoxState extends State<_VideoAspectBox> {
  VideoPlayerSession? _session;

  @override
  void initState() {
    super.initState();
    widget.coordinator.registryListenable.addListener(_onRegistry);
    _bind();
  }

  @override
  void didUpdateWidget(covariant _VideoAspectBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coordinator != widget.coordinator) {
      oldWidget.coordinator.registryListenable.removeListener(_onRegistry);
      widget.coordinator.registryListenable.addListener(_onRegistry);
    }
    if (oldWidget.postId != widget.postId ||
        oldWidget.coordinator != widget.coordinator) {
      _bind();
    }
  }

  /// Sesi terdaftar/berubah → re-cek sessionFor (sesi bisa baru muncul).
  void _onRegistry() {
    _bind();
    if (mounted) setState(() {});
  }

  void _bind() {
    final session = widget.coordinator.sessionFor(widget.postId);
    final next = session is VideoPlayerSession ? session : null;
    if (identical(next, _session)) return;
    _session?.revision.removeListener(_onRevision);
    _session = next;
    _session?.revision.addListener(_onRevision);
  }

  void _onRevision() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.coordinator.registryListenable.removeListener(_onRegistry);
    _session?.revision.removeListener(_onRevision);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _session?.controller;
    final liveSize = (controller != null && controller.value.isInitialized)
        ? controller.value.size
        : null;
    final aspectRatio = resolvePostinganVideoBoxAspectRatio(
      fallbackAspectRatio: widget.fallbackAspectRatio,
      liveSize: liveSize,
    );
    return widget.builder(context, aspectRatio);
  }
}
```

CATATAN implementer: pastikan `resolvePostinganVideoBoxAspectRatio` ter-import (fungsi ada di `postingan_media_aspect_ratio.dart`; file layar ini sudah meng-import path itu karena memakai `resolvePostinganMediaAspectRatio` — verifikasi import-nya, tambah bila perlu). `VideoPlayerSession` sudah di-import (dipakai `_HeroVideoFlightSurface`).

- [ ] **Step 2: Restrukturisasi `_PostMediaSurface.build`**

Ubah blok mulai `return AspectRatio(` (~3127). SEBELUM:

```dart
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: switch (post.contentType) {
        FeedContentType.video => _wrapHero(
            context,
            _InlineVideoPlayer(
              ...
              aspectRatio: aspectRatio,
              ...
            ),
            flightChild: _HeroVideoFlightSurface(...),
          ),
        FeedContentType.carousel => _wrapHero(
            context,
            _CarouselSurface(
              ...
              aspectRatio: aspectRatio,
              ...
            ),
          ),
        _ => _wrapHero(
            context,
            ...foto/_ImageSurface...,
          ),
      },
    );
```

SESUDAH — pindahkan `AspectRatio` ke DALAM tiap cabang; VIDEO dibungkus `_VideoAspectBox` (rasio reaktif), foto & carousel tetap rasio tersimpan:

```dart
    return switch (post.contentType) {
      // Video: kotak MENGIKUTI ukuran asli controller (fallback rasio
      // tersimpan sebelum siap) supaya video portrait bermetadata-landscape
      // tak lagi kena bar hitam kiri-kanan. Lihat _VideoAspectBox.
      FeedContentType.video => _VideoAspectBox(
          coordinator: coordinator,
          postId: post.id,
          fallbackAspectRatio: aspectRatio,
          builder: (context, liveAspectRatio) => AspectRatio(
            aspectRatio: liveAspectRatio,
            child: _wrapHero(
              context,
              _InlineVideoPlayer(
                postId: post.id,
                coordinator: coordinator,
                registerVideoUrl: registerVideoUrl,
                dormant: handoffSessionId == post.id,
                mediaUrl: videoQualityService.resolvePlaybackUrl(
                  post.videoPlaybackUrl,
                  dataSaverUrl: post.videoDataSaverUrl,
                  userPreference: appSettingsStore.feedVideoQuality,
                ),
                thumbnailUrl: post.thumbnailUrl,
                aspectRatio: liveAspectRatio,
                onAnchorReady: onVideoAnchorReady,
                onMediaSingleTap: onVideoMediaSingleTap,
                onMediaDoubleTapDown: onVideoMediaDoubleTapDown,
                onMediaDoubleTap: onVideoMediaDoubleTap,
              ),
              flightChild: _HeroVideoFlightSurface(
                postId: post.id,
                coordinator: coordinator,
                thumbnailUrl: post.thumbnailUrl,
              ),
            ),
          ),
        ),
      FeedContentType.carousel => AspectRatio(
          aspectRatio: aspectRatio,
          child: _wrapHero(
            context,
            _CarouselSurface(
              post: post,
              aspectRatio: aspectRatio,
              coordinator: coordinator,
              registerVideoUrl: registerVideoUrl,
              handoffSessionId: handoffSessionId,
            ),
          ),
        ),
      _ => AspectRatio(
          aspectRatio: aspectRatio,
          child: _wrapHero(
            context,
            // ...SALIN PERSIS isi cabang foto/default yang ADA sekarang
            // (mis. _ImageSurface(imageUrl: post.previewMediaUrl, ...)).
          ),
        ),
    };
```

CATATAN implementer: 
- Cabang `_` (foto/default) HARUS menyalin persis isi yang ada sekarang — JANGAN mengarang; baca kode existing dan pindahkan apa adanya ke dalam `AspectRatio`.
- Komentar hero destination lama (~3122) yang menjelaskan Hero tetap relevan — pindahkan/pertahankan di atas `switch` atau di cabang video.
- Verifikasi `_InlineVideoPlayer` benar-benar memakai `widget.aspectRatio` untuk apa (grep `widget.aspectRatio` di `_InlineVideoPlayerState`). Bila TIDAK dipakai visual (fit video lewat `controller.value.size`), passing `liveAspectRatio` aman & konsisten. JANGAN ubah logika fit internal player (tetap `BoxFit.contain`).

- [ ] **Step 3: Tulis widget test**

Buat `flutter_app/test/screens/member_post_detail_video_live_aspect_test.dart`. Tujuan: buktikan kotak video memakai rasio dari ukuran asli controller, bukan metadata. GUNAKAN pola fake session/coordinator dari `test/screens/member_post_detail_screen_coordinator_test.dart` (baca dulu `_FakeSession`/`_WarmSession` di sana).

Bila memasang controller dengan `value.size` spesifik terlalu berat lewat infra fake yang ada, MINIMAL uji jalur logika lewat `_VideoAspectBox` dengan coordinator fake yang `sessionFor` mengembalikan `VideoPlayerSession` ber-`controller.value.size` portrait: assert bahwa `AspectRatio` turunan `_VideoAspectBox` bernilai `closeTo(9/16)` walau `fallbackAspectRatio` landscape. Contoh kerangka (SESUAIKAN ke infra nyata; jangan menambah API produksi demi test):

```dart
// Pseudo-struktur — implementer WAJIB sesuaikan ke _WarmSession/fake yang ada.
testWidgets('kotak video pakai rasio ukuran asli controller (portrait) '
    'walau fallback landscape → tak ada bar kiri-kanan', (tester) async {
  // 1. Siapkan coordinator fake + session portrait (controller size 1080x1920).
  // 2. Pump _VideoAspectBox(coordinator, postId, fallbackAspectRatio: 16/9,
  //    builder: (_, r) => AspectRatio(aspectRatio: r, child: const SizedBox()))
  // 3. Setelah revision fire / pump, temukan AspectRatio dan assert
  //    aspectRatio closeTo(9/16).
  // 4. (opsional) sebelum session ada → aspectRatio == 16/9 (fallback).
});
```

Bila benar-benar tidak feasible menyetel `controller.value.size` di lingkungan test (VideoPlayerController butuh platform), CUKUP andalkan unit test murni Task 1 untuk logika + widget test tipis yang memverifikasi `_VideoAspectBox` memakai `fallbackAspectRatio` saat `sessionFor` null (jalur fallback), dan dokumentasikan di laporan bahwa jalur live-size diverifikasi via unit test Task 1 + device-verify. JANGAN memaksakan test rapuh.

- [ ] **Step 4: Jalankan test + analyze**

Run: `flutter test test/screens/member_post_detail_video_live_aspect_test.dart test/features/feed/layout/postingan_media_aspect_ratio_test.dart`
Expected: PASS.

Run: `flutter analyze lib/screens/member_post_detail_screen.dart lib/features/feed/layout/postingan_media_aspect_ratio.dart`
Expected: No issues baru.

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/screens/member_post_detail_screen.dart flutter_app/test/screens/member_post_detail_video_live_aspect_test.dart
git commit -m "fix(postingan): kotak video ikut ukuran asli controller — hilangkan bar hitam kiri-kanan"
```

---

### Task 3: Sweep regresi + PR (JANGAN merge)

**Files:** tidak ada perubahan kode baru (verifikasi + PR).

- [ ] **Step 1: Suite Postingan + framing + hero**

Run:
```
flutter test test/screens/member_post_detail_screen_coordinator_test.dart test/screens/member_post_detail_screen_fullscreen_test.dart test/screens/member_post_detail_video_hero_flight_test.dart test/screens/member_post_detail_hero_test.dart test/screens/member_post_detail_hero_both_directions_test.dart test/screens/postingan_landscape_framing_test.dart test/features/feed/layout/
```
Expected: PASS semua. Bila ada test hero yang mem-pin ukuran kotak dari metadata tersimpan lalu gagal karena kini reaktif, JANGAN asal ubah — laporkan dulu dengan detail (mungkin butuh penyesuaian ekspektasi ke rasio asli, atau menandakan regresi hero yang harus dibahas).

- [ ] **Step 2: Push + PR (JANGAN merge)**

```bash
git push -u origin claude/postingan-video-live-aspect
gh pr create --title "fix(postingan): video ikut ukuran asli — hilangkan bar hitam kiri-kanan" --body "..."
```

Isi body PR: akar masalah (kotak Postingan dibangun dari metadata dimensi salah vs feed/fullscreen pakai ukuran asli controller), desain helper murni + `_VideoAspectBox` reaktif, penegasan foto/carousel/feed/fullscreen TIDAK berubah & fit tetap contain (tak memotong), hasil test, dan blok **Device-verify wajib** di bawah. JANGAN merge — tunggu hasil device user.

- [ ] **Step 3: Checklist device-verify (user)**

1. Video portrait yang tadinya bar hitam kiri-kanan (mis. Magic Bites/Whiskas) di halaman Postingan → sekarang penuh, TANPA bar kiri-kanan.
2. Video landscape di Postingan → tetap letterbox hitam ATAS-BAWAH (tidak berubah, tidak terpotong).
3. Foto & carousel di Postingan → framing tidak berubah.
4. Feed & fullscreen → tidak berubah sama sekali.
5. Buka video dari grid (hero flight) → transisi mulus, tak ada lompatan aneh; kalau ada "loncat" tinggi kotak sesaat video mulai main, laporkan seberapa mengganggu (trade-off Opsi A yang sudah diketahui).
6. Video yang metadatanya SUDAH benar → tak ada regresi (tetap pas).

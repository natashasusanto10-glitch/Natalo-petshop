# Feed Posting Fase 2B — Lima Layar (Implementation Plan)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Lima layar flow posting menyamai IG secara visual & struktural — picker campur premium, Edit Video fullscreen tunggal, Bagikan dengan Simpan Draft + Bagikan berdampingan, Pratinjau memakai chrome feed ASLI + suara, Ubah Sampul scrubber frame — plus bar unggahan ramping ala IG (spec §2A-5) dan pembersihan ±3.000 baris dead code.

**Architecture:** Layar baru dipecah per file ke `lib/screens/feed_post/`. Pratinjau dibangun di atas widget bersama hasil 2A (`FeedActionRail`, `FeedCreatorIdentity`, `FeedExpandableCaption`, `FeedProductAnchorCard`, `FeedPostScrim`). Editor baru menggantikan pasangan `FeedVideoPreviewScreen`+`FeedVideoTrimScreen`. Draft mendapat `userPickedCover` agar sampul pilihan user tidak ditimpa regenerasi store (rekonsiliasi dengan fix I1 2A).

**Tech Stack:** Flutter/Dart; `photo_manager` (picker existing), `video_player`, `video_thumbnail`, `image_picker`; kompresi HANYA via `videoCompressGate`. Package: `natalo_petshop_flutter`.

**Spec:** `docs/superpowers/specs/2026-07-10-feed-posting-fase2-ig-parity-design.md` (bagian 2B + Standar visual).

## Global Constraints

- **Standar visual (spec, permintaan eksplisit user):** tiap layar dibandingkan berdampingan dengan screenshot IG (`C:\Users\USER\Desktop\IG\`) saat device-verify; pill/tombol frosted `rgba(255,255,255,0.06–0.08)` + border `rgba(255,255,255,0.14)`; tombol bulat header 36–44px; media edge-to-edge di layar gelap; hairline divider; transisi 150–350ms; haptics via `AppHaptics`.
- **Token warna (VERIFIED dari kode):** biru aksi `#1E5BFF` (SATU-SATUNYA biru aksi — picker existing memakai `#2563EB`, WAJIB diunifikasi di Task 6); dark editor bg `#05070D`, card `#11141B`, border `#252A35`, muted `#AEB7C7`; light ink `#101828`, muted `#667085`, border `#E0E7F0`, soft `#F5F8FF`, hint `#98A2B3`, divider `#E5EAF2`.
- **Perilaku feed publik TIDAK berubah.** Widget bersama 2A dipakai apa adanya — kalau butuh varian, tambah parameter opsional yang default ke perilaku lama.
- Kompresi HANYA via `videoCompressGate`; `AppAnalytics.logEvent(name, [params])` fire-and-forget `unawaited(...)`.
- Kerja dari `flutter_app/`; tiap task diakhiri `flutter analyze` (lolos bila satu-satunya isu = lint pre-existing `lib/config/launch_popup_campaigns.dart:10`) + `flutter test` penuh hijau + commit dari worktree root (branch `claude/feed-posting-fase2`).
- **Widget test gotcha (memory proyek):** JANGAN `pumpAndSettle` pada layar yang merender `AppProductImage`/shimmer/network image — pakai bounded pump-loop (`for (var i=0;i<10;i++) { await tester.pump(const Duration(milliseconds: 100)); }`) + `SharedPreferences.setMockInitialValues({})` di setUp.
- Fakta kode terverifikasi 2026-07-11 (nomor baris bisa bergeser — Grep dulu):
  - Entry flow: `FeedUploadSheet.show()` (`lib/widgets/feed_upload_sheet.dart:45-52`) → langsung push `FeedMediaPickerScreen`; 3 caller: `feed_screen.dart:558`, `member_posts_screen.dart:219`, `member_screen.dart:186`. Widget `FeedUploadSheet` sendiri = dead code 1447 baris.
  - Picker (`feed_media_picker_screen.dart`, 1845 baris): grid campur `RequestType.common` 4 kolom, multi-select foto maks 8 (`maxPhotoCarouselItems`, badge nomor `_SelectionBadge`), video single (`_selectVideo`), badge durasi `_DurationBadge`, preview besar 75% 4:5 + `_PhotoCropTransform` pinch/pan + `_AspectToggleButton`, header `_MediaPickerHeader` ("Buat Postingan" + tombol "Next" teks), mode lock via tap pertama (`_mode`), album sheet. `_next()`: foto → isolate crop → `FeedNewPostScreen(NewPostMediaDraft.photos)`; video → `needsTrim` branch (>60s `FeedVideoTrimScreen`, ≤60s `FeedVideoPreviewScreen`).
  - Layar hidup vs mati (`feed_video_upload_flow.dart`, 2647 baris): HIDUP = `FeedVideoPreviewScreen` (:203, dipush picker :809), `FeedVideoTrimScreen` (:389, dipush picker :808 + preview :366), `FeedPostSubmittedScreen` (:1160, dipush `feed_photo_upload_flow.dart:1111`). MATI = `FeedVideoStartScreen` (:41), `FeedPostDetailScreen` (:676), `FeedUploadProgressScreen` (:888, ranjau: kompres full abaikan trimStart).
  - `FeedNewPostScreen` (`feed_new_post_screen.dart`, 1809 baris): `_MediaPreview` widthFactor 0.62 aspect 4:5; `_BottomActions` SATU tombol (param `busy` dead, selalu false); `_editCover`→`_CoverPickerSheet` 3 preset (:1346); `_openPreview` (:267) TIDAK mengirim produk; draft key `natalo-feed-upload-pending`; `_saveDraftAndExit` (:403); `startTrimLoopGuard` (:32).
  - `FeedPostPreviewScreen` (:1462): mockup lokal `_PreviewActionRail` (ikon Material, angka "0" hardcoded), `_PreviewCreatorOverlay` (ProfileAvatar), TANPA scrim, `setVolume(0)` (:1518), satu tombol Bagikan.
  - Widget bersama 2A (`lib/features/feed/widgets/`): `FeedActionRail{likeCount,liked,commentCount,shareCount,showCart=false,cartBadgeCount=0,onLike..onMore}`; `FeedCreatorIdentity{name,avatarInitial,avatarUrl,isOfficial,followState:FeedFollowChipState{none,following,hidden},onFollowTap,onProfileTap}`; `FeedExpandableCaption{text,onMentionTap}`; `FeedProductAnchorCard{title,priceText,imageUrl?,strikePriceText?,discountBadgeText?,onAddToCart?,onTap?}`; `FeedPostScrim{height=330}`.
  - `appSettingsStore.feedMuted` (getter) + `setFeedMuted(bool)` (`settings_store.dart:48,109`), default `true`, key `settings_feed_muted`.
  - `memberStore.profile`: `name`, `initial`, `profilePhotoUrl`, `username`, `displayHandle` (`member_profile.dart`).
  - Model `Product` PUNYA `discountPrice`/`memberPrice`/`finalPrice`/`hasDiscount`/`discountPercent` (`product.dart:361-362,584-599`) — tapi mapping `_loadPurchasedProducts` (`feed_new_post_screen.dart:201-227`) MEMBUANGNYA (hanya `price` mentah).
  - Pola ekstraksi frame reusable: `_extractFrameThumbnails` (`feed_video_upload_flow.dart:482-505`).
  - Store 2A I1: guard regen cover `coverFromUntrimmed = draft.trimStart != null` (`feed_upload_store.dart` step 1) — MENIMPA sampul pilihan user; direkonsiliasi Task 1.
  - Test existing yang menyentuh area: `feed_action_rail_test`, `feed_creator_overlay_test`, `feed_product_anchor_card_test`, `feed_create_post_draft_test` (4 test). TIDAK ada test layar; TIDAK ada golden feed.

### Keputusan desain sadar (deviasi dari mockup v2 — sudah difinalkan, jangan didebat ulang di task):
1. Picker mempertahankan multi-select-selalu-aktif bernomor (tanpa toggle "Pilih banyak") — superset fungsional, lebih sedikit tap.
2. Toolbar editor: pill **Potong** men-toggle panel timeline (bukan dekorasi); pill **Sampul** membuka Ubah Sampul.
3. Rail Pratinjau menampilkan angka 0 (jujur — post baru belum punya like), bukan angka contoh; chip "Ikuti" tampil (`followState: none` = sudut pandang audiens).
4. Thumbnail di Bagikan = gambar sampul statis (bukan video autoplay) — premium + hemat resource; controller video di layar Bagikan DIHAPUS.

---

### Task 1: Fondasi sampul — `userPickedCover` + util frame + layar Ubah Sampul

**Files:**
- Modify: `flutter_app/lib/models/feed_create_post_draft.dart`
- Modify: `flutter_app/lib/state/feed_upload_store.dart` (guard regen cover)
- Create: `flutter_app/lib/utils/video_frame_thumbs.dart`
- Create: `flutter_app/lib/screens/feed_post/feed_cover_picker_screen.dart`
- Test: `flutter_app/test/feed_create_post_draft_test.dart` (tambah), `flutter_app/test/video_frame_thumbs_test.dart` (baru), `flutter_app/test/feed_cover_picker_screen_test.dart` (baru)

**Interfaces:**
- Consumes: `FeedCreatePostDraft` (2A), pola `_extractFrameThumbnails`.
- Produces (dipakai Task 2 & 3):

```dart
// feed_create_post_draft.dart — field baru (ikuti pola field lain):
/// True bila thumbnailPath dipilih user via Ubah Sampul — store TIDAK
/// boleh me-regenerate cover (guard di _runVideoUpload step 1).
final bool userPickedCover; // default false; copyWith biasa

// video_frame_thumbs.dart:
/// Timestamp N frame tersebar merata di [startMs, startMs+spanMs] (pure,
/// testable). N>=2; frame pertama = startMs, terakhir = startMs+spanMs.
List<int> frameTimestampsMs({required int startMs, required int spanMs, required int count});

/// Ekstrak frame progresif — onFrame(i, bytes) dipanggil per frame jadi.
/// extractor injectable untuk test (default VideoThumbnail.thumbnailData).
Future<void> extractVideoFrameThumbs({
  required String videoPath,
  required int startMs,
  required int spanMs,
  int count = 10,
  int maxWidth = 120,
  int quality = 50,
  required void Function(int index, Uint8List? bytes) onFrame,
  Future<Uint8List?> Function(String path, int timeMs)? extractor,
});

// feed_cover_picker_screen.dart:
/// Layar penuh light pilih sampul. Return path JPEG sampul (String) atau
/// null (batal). Frame diambil dari RENTANG TRIM saja (startMs..startMs+spanMs
/// pada file ASLI — offset absolut).
class FeedCoverPickerScreen extends StatefulWidget {
  final String videoPath;
  final Duration rangeStart;   // trimStart ?? Duration.zero
  final Duration rangeSpan;    // finalDuration (wajib non-null di pemanggil)
  final String? currentCoverPath;
  /// Injectable untuk widget test (default VideoThumbnail-based).
  final Future<Uint8List?> Function(String path, int timeMs)? frameExtractor;
  final Future<String?> Function(String path, int timeMs)? coverGenerator; // maxWidth 720 q82
  ...
}
```

- [ ] **Step 1: Test model + util (failing)**

Tambah di `feed_create_post_draft_test.dart`:

```dart
  test('userPickedCover default false, copyWith set & pertahankan', () {
    const d = FeedCreatePostDraft(localVideoPath: 'a.mp4');
    expect(d.userPickedCover, isFalse);
    final picked = d.copyWith(userPickedCover: true);
    expect(picked.userPickedCover, isTrue);
    expect(picked.copyWith(caption: 'x').userPickedCover, isTrue);
  });
```

Buat `test/video_frame_thumbs_test.dart`:

```dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/utils/video_frame_thumbs.dart';

void main() {
  test('frameTimestampsMs merata: pertama=start, terakhir=start+span', () {
    final ts = frameTimestampsMs(startMs: 40000, spanMs: 20000, count: 5);
    expect(ts, [40000, 45000, 50000, 55000, 60000]);
  });

  test('extractVideoFrameThumbs memanggil extractor dengan timestamp absolut '
      'dan meneruskan hasil per-frame', () async {
    final calls = <int>[];
    final got = <int, Uint8List?>{};
    await extractVideoFrameThumbs(
      videoPath: 'v.mp4', startMs: 1000, spanMs: 4000, count: 3,
      extractor: (path, timeMs) async {
        calls.add(timeMs);
        return timeMs == 3000 ? null : Uint8List.fromList([1]);
      },
      onFrame: (i, bytes) => got[i] = bytes,
    );
    expect(calls, [1000, 3000, 5000]);
    expect(got[0], isNotNull);
    expect(got[1], isNull); // frame gagal → null, tidak melempar
    expect(got[2], isNotNull);
  });
}
```

- [ ] **Step 2: Run — fail.** `flutter test test/video_frame_thumbs_test.dart test/feed_create_post_draft_test.dart` → FAIL compile.

- [ ] **Step 3: Implement model + util.** Model: field + konstruktor + copyWith pola existing. Util: implement per API di atas (loop `frameTimestampsMs`, try/catch per frame → null, `extractor` default `(p,t) => VideoThumbnail.thumbnailData(video: p, imageFormat: ImageFormat.JPEG, quality: quality, maxWidth: maxWidth, timeMs: t)`).

- [ ] **Step 4: Guard store.** Di `feed_upload_store.dart` step 1, ganti `final coverFromUntrimmed = draft.trimStart != null;` → `final coverFromUntrimmed = draft.trimStart != null && !draft.userPickedCover;` + perbarui komentar: sampul pilihan user (Ubah Sampul, sudah dari rentang benar) TIDAK ditimpa.

- [ ] **Step 5: Test layar Ubah Sampul (failing)**

`test/feed_cover_picker_screen_test.dart`:

```dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/screens/feed_post/feed_cover_picker_screen.dart';

Uint8List _px() => Uint8List.fromList([137,80,78,71,13,10,26,10]); // dummy

void main() {
  Widget wrap() => MaterialApp(home: FeedCoverPickerScreen(
        videoPath: 'v.mp4',
        rangeStart: const Duration(seconds: 40),
        rangeSpan: const Duration(seconds: 20),
        currentCoverPath: null,
        frameExtractor: (p, t) async => _px(),
        coverGenerator: (p, t) async => '/tmp/cover-$t.jpg',
      ));

  testWidgets('header: judul, tombol tutup, tombol konfirmasi', (tester) async {
    await tester.pumpWidget(wrap());
    for (var i = 0; i < 10; i++) { await tester.pump(const Duration(milliseconds: 60)); }
    expect(find.text('Ubah Sampul'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.text('Ambil dari galeri'), findsOneWidget);
  });

  testWidgets('konfirmasi pop dengan path dari coverGenerator', (tester) async {
    String? popped = 'sentinel';
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      return ElevatedButton(
        onPressed: () async {
          popped = await Navigator.push<String>(context, MaterialPageRoute(
            builder: (_) => FeedCoverPickerScreen(
              videoPath: 'v.mp4',
              rangeStart: Duration.zero,
              rangeSpan: const Duration(seconds: 10),
              currentCoverPath: null,
              frameExtractor: (p, t) async => _px(),
              coverGenerator: (p, t) async => '/tmp/cover.jpg',
            )));
        },
        child: const Text('go'));
    })));
    await tester.tap(find.text('go'));
    for (var i = 0; i < 10; i++) { await tester.pump(const Duration(milliseconds: 60)); }
    await tester.tap(find.byIcon(Icons.check_rounded));
    for (var i = 0; i < 10; i++) { await tester.pump(const Duration(milliseconds: 60)); }
    expect(popped, '/tmp/cover.jpg');
  });
}
```

- [ ] **Step 6: Implement layar** (visual mockup v2 layar 5, tema LIGHT):
- Scaffold putih. Header 36px bulat: X kiri (border `#E0E7F0`), judul "Ubah Sampul" (17 w800 ink `#101828`, center), ✓ kanan lingkaran biru `#1E5BFF` ikon putih → `_confirm()`.
- Helper text center 12.5 w600 `#667085`: "Pilih frame dari video, atau ambil gambar dari galeri."
- Preview sampul: center, lebar ~52% layar, aspect 2:3, radius 20, `Image.memory` frame terpilih (fallback `Image.file(currentCoverPath)` → fallback kotak `#161A24`); badge timecode `m:ss` kanan-atas (pill `rgba(0,0,0,0.5)`).
- Filmstrip: tinggi 54, radius 10, 10 frame via `extractVideoFrameThumbs(startMs: rangeStart.inMilliseconds, spanMs: rangeSpan.inMilliseconds)` progresif; overlay dim putih 0.55 di luar kotak seleksi; kotak seleksi border biru 3px radius 9 lebar `1/10` strip, draggable horizontal (GestureDetector onHorizontalDragUpdate → fraksi 0..1). Marker `0:00` / `m:ss(span)` di bawah strip (10.5 w700 `#98A2B3`).
- Saat drag berhenti (onHorizontalDragEnd) → `frameExtractor(videoPath, absoluteMs)` untuk preview besar (absoluteMs = rangeStart + fraksi*span); state `_selectedMs`.
- `_confirm()`: `coverGenerator(videoPath, _selectedMs)` (default impl `VideoThumbnail.thumbnailFile(video:, imageFormat: JPEG, maxWidth: 720, timeMs:, quality: 82)`) → `Navigator.pop(context, path)`; null → toast gagal.
- "Ambil dari galeri": tombol 52 radius 16 bg `#F5F8FF` border `#E0E7F0` teks+ikon biru; `ImagePicker().pickImage(source: gallery)` → pop dengan path hasil. `AppHaptics.tap()` di aksi.

- [ ] **Step 7: Run semua — pass.** `flutter test` penuh + `flutter analyze`.

- [ ] **Step 8: Commit.**
```bash
git add flutter_app/lib/models/feed_create_post_draft.dart flutter_app/lib/state/feed_upload_store.dart flutter_app/lib/utils/video_frame_thumbs.dart flutter_app/lib/screens/feed_post/feed_cover_picker_screen.dart flutter_app/test/feed_create_post_draft_test.dart flutter_app/test/video_frame_thumbs_test.dart flutter_app/test/feed_cover_picker_screen_test.dart
git commit -m "feat(feed): Ubah Sampul scrubber frame + userPickedCover (sampul user tak ditimpa store)"
```

---

### Task 2: Edit Video fullscreen tunggal (`FeedVideoEditScreen`)

**Files:**
- Create: `flutter_app/lib/screens/feed_post/feed_video_edit_screen.dart`
- Modify: `flutter_app/lib/screens/feed_media_picker_screen.dart` (cabang video `_next()` — hapus `needsTrim`, selalu push layar baru)
- Modify: `flutter_app/lib/screens/feed_video_upload_flow.dart` (hapus event `feed_post_edit_opened` dari `FeedVideoTrimScreen` initState — event pindah ke layar baru)
- Test: `flutter_app/test/feed_video_edit_screen_test.dart`

**Interfaces:**
- Consumes: Task 1 (`FeedCoverPickerScreen`, `extractVideoFrameThumbs`, `userPickedCover`), `startTrimLoopGuard`-pattern TIDAK dipakai di sini (controller di-seek manual), `appSettingsStore.feedMuted/setFeedMuted`, `videoCompressGate` TIDAK dipanggil (Next instan).
- Produces: `class FeedVideoEditScreen extends StatefulWidget { final FeedCreatePostDraft draft; }` — push dari picker untuk SEMUA video (≤60s dan >60s). Next → `FeedNewPostScreen(draft: NewPostMediaDraft.video(nextDraft))`.

- [ ] **Step 1: Test (failing)** — `test/feed_video_edit_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_create_post_draft.dart';
import 'package:natalo_petshop_flutter/screens/feed_post/feed_video_edit_screen.dart';

void main() {
  const draft = FeedCreatePostDraft(
    localVideoPath: '/nonexistent/v.mp4', // init controller gagal di test env → error state
    originalDuration: Duration(seconds: 44),
  );

  Widget wrap() => const MaterialApp(home: FeedVideoEditScreen(draft: draft));

  testWidgets('chrome dasar: judul, back, next, pill Sampul & Potong',
      (tester) async {
    await tester.pumpWidget(wrap());
    for (var i = 0; i < 10; i++) { await tester.pump(const Duration(milliseconds: 80)); }
    expect(find.text('Edit Video'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);
    expect(find.text('Sampul'), findsOneWidget);
    expect(find.text('Potong'), findsOneWidget);
  });

  testWidgets('durasi <=60s: panel timeline tersembunyi, Potong menampilkannya',
      (tester) async {
    await tester.pumpWidget(wrap());
    for (var i = 0; i < 10; i++) { await tester.pump(const Duration(milliseconds: 80)); }
    expect(find.text('Geser pegangan untuk memangkas video'), findsNothing);
    await tester.tap(find.text('Potong'));
    for (var i = 0; i < 5; i++) { await tester.pump(const Duration(milliseconds: 80)); }
    expect(find.text('Geser pegangan untuk memangkas video'), findsOneWidget);
  });

  testWidgets('durasi >60s: timeline langsung tampil', (tester) async {
    const long = FeedCreatePostDraft(
      localVideoPath: '/nonexistent/v.mp4',
      originalDuration: Duration(seconds: 76),
    );
    await tester.pumpWidget(const MaterialApp(home: FeedVideoEditScreen(draft: long)));
    for (var i = 0; i < 10; i++) { await tester.pump(const Duration(milliseconds: 80)); }
    expect(find.text('Geser pegangan untuk memangkas video'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run — fail** (file belum ada).

- [ ] **Step 3: Implement layar** — struktur (mockup v2 layar 2, tema DARK `#05070D`):
- **PINDAHKAN (cut) dari `feed_video_upload_flow.dart`** ke file baru: `_TrimTimeline`, `_TrimRangeBar`, `_TrimHandle`, `_VideoPreviewStage` + typedef `_TimelineDragCallback` + logika `_updateRange`/`_startPlaybackGuard`/`_range` dari `_FeedVideoTrimScreenState` (verbatim semaksimal mungkin; ganti pemanggilan `_extractFrameThumbnails` lokal → util `extractVideoFrameThumbs` Task 1 dengan `startMs: 0, spanMs: durasi penuh`). Sisakan alias/stub di file lama HANYA bila masih dipakai kelas hidup lain (Grep dulu; `FeedVideoPreviewScreen` memakai `_VideoPreviewStage` — biarkan copy lama tetap di file lama sampai Task 5 menghapus layar itu; hindari import silang file layar).
- **Layout:** Column: (1) area video `Expanded` — `_VideoPreviewStage`-based full-bleed (tanpa padding horizontal, TANPA radius — edge-to-edge), overlay atas: back bulat 36 frosted kiri (`Navigator.pop`), Next bulat 36 biru `#1E5BFF` kanan (`_confirmSelection`); overlay bawah video: pill timecode `m:ss / m:ss` (posisi playback / durasi) + pill "Suara"/"Senyap" (ikon `volume_up/off_rounded`) frosted; tap video = play/pause toggle. (2) baris durasi: `"m:ss dipilih"` (15 w800) + `"Maksimal 60 detik"` (11 muted) padding h16. (3) panel timeline (lihat visibility di bawah): `_TrimTimeline` + helper text "Geser pegangan untuk memangkas video" (11.5 w700 muted). (4) toolbar: 2 pill 46px radius 14 frosted (`rgba(255,255,255,0.06)` border `0.14`): "Potong" (ikon `content_cut_rounded`) toggle panel timeline; "Sampul" (ikon `photo_rounded`) → buka `FeedCoverPickerScreen`.
- **Visibility timeline:** `_showTimeline = durasi > 60s` awal; >60s tidak bisa disembunyikan (wajib trim); ≤60s toggle via Potong.
- **Suara:** `_initVideo` set `volume = appSettingsStore.feedMuted ? 0 : 1` (BUKAN 0 hardcode); pill Suara → `appSettingsStore.setFeedMuted(!feedMuted)` + `controller.setVolume(...)` live + setState; `AppHaptics.selection()`.
- **Sampul in-editor:** state `String? _pickedCoverPath; RangeValues? _coverPickedAtRange;` — buka picker dengan `videoPath: draft.localVideoPath!, rangeStart: Duration(ms dari _range.start), rangeSpan: Duration(detik terpilih)`; hasil → simpan + `_coverPickedAtRange = _range`. Saat `_updateRange` mengubah range → jika `_coverPickedAtRange != null && _coverPickedAtRange != _range` maka buang `_pickedCoverPath` (sampul basi di luar rentang) + toast singkat "Sampul direset karena rentang berubah".
- **`_confirmSelection` (Next, instan):** validasi 1..60s (error box existing style); `AppHaptics.tap()`; pause;
  ```dart
  final selectedSeconds = (_range.end - _range.start).round();
  final isFullRange = _range.start == 0 &&
      selectedSeconds >= (_duration.inSeconds);
  var next = widget.draft;
  if (!isFullRange) {
    next = next.copyWith(
      trimStart: Duration(milliseconds: (_range.start * 1000).round()),
      trimmedDuration: Duration(seconds: selectedSeconds),
    );
  }
  if (_pickedCoverPath != null) {
    next = next.copyWith(thumbnailPath: _pickedCoverPath, userPickedCover: true);
  }
  ```
  → push `FeedNewPostScreen(draft: NewPostMediaDraft.video(next))`. `isFullRange` = draft lewat TANPA trimStart → store boleh fallback-original (semantik ≤60s lama dipertahankan).
- **Telemetri:** `initState` → `unawaited(AppAnalytics.logEvent('feed_post_edit_opened'))` (event kini menembak untuk SEMUA video — memperbaiki gap funnel M4 2A). Hapus pemanggilan yang sama dari `FeedVideoTrimScreen.initState` di file lama.
- **Error state:** init controller gagal → error box "Video belum bisa dipreview. Pilih video lain." + Next disabled saat `_loading` (pola trim lama). Timecode default `0:00 / m:ss` dari `originalDuration` (test bergantung ini saat init gagal — layar tetap merender chrome).

- [ ] **Step 4: Rewire picker.** Di `feed_media_picker_screen.dart` `_next()` cabang video: hapus `needsTrim`/branch; selalu:
```dart
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => FeedVideoEditScreen(draft: draft)),
    );
    if (result == true && mounted) Navigator.pop(context, true);
```
Import layar baru; komentar BUGFIX lama boleh diringkas. `FeedVideoPreviewScreen`/`FeedVideoTrimScreen` kini tak terjangkau dari picker (dihapus Task 5).

- [ ] **Step 5: Run semua — pass** (`flutter test` penuh; test lama tidak menyentuh layar ini). `flutter analyze`.

- [ ] **Step 6: Commit.**
```bash
git add flutter_app/lib/screens/feed_post/feed_video_edit_screen.dart flutter_app/lib/screens/feed_media_picker_screen.dart flutter_app/lib/screens/feed_video_upload_flow.dart flutter_app/test/feed_video_edit_screen_test.dart
git commit -m "feat(feed): Edit Video fullscreen tunggal — gabung preview+trim, suara ikut feedMuted, sampul in-editor, Next instan"
```

---

### Task 3: Bagikan — rework `FeedNewPostScreen`

**Files:**
- Modify: `flutter_app/lib/screens/feed_new_post_screen.dart`
- Test: `flutter_app/test/feed_new_post_screen_test.dart` (baru)

**Interfaces:**
- Consumes: Task 1 (`FeedCoverPickerScreen`), draft `userPickedCover`.
- Produces (dipakai Task 4): `_openPreview` memanggil `FeedPostPreviewScreen` dengan parameter baru `products: List<Product>` (produk terpilih) dan menangani result enum `FeedPreviewResult { share, saveDraft }` (pop null = kembali edit). Definisikan enum di `feed_new_post_screen.dart` SEKARANG (Task 4 memindahkannya bila perlu):

```dart
enum FeedPreviewResult { share, saveDraft }
```

- [ ] **Step 1: Test (failing)** — `test/feed_new_post_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_create_post_draft.dart';
import 'package:natalo_petshop_flutter/screens/feed_new_post_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  const videoDraft = FeedCreatePostDraft(
    localVideoPath: '/nonexistent/v.mp4',
    originalDuration: Duration(seconds: 30),
  );

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: FeedNewPostScreen(draft: NewPostMediaDraft.video(videoDraft)),
    ));
    for (var i = 0; i < 12; i++) { await tester.pump(const Duration(milliseconds: 100)); }
  }

  testWidgets('bottom bar: Simpan Draft dan Bagikan berdampingan',
      (tester) async {
    await pumpScreen(tester);
    expect(find.text('Simpan Draft'), findsOneWidget);
    expect(find.text('Bagikan'), findsOneWidget);
  });

  testWidgets('thumbnail video: pill Pratinjau + Ubah sampul', (tester) async {
    await pumpScreen(tester);
    expect(find.text('Pratinjau'), findsOneWidget);
    expect(find.text('Ubah sampul'), findsOneWidget);
  });

  testWidgets('caption trigger tetap ada', (tester) async {
    await pumpScreen(tester);
    expect(find.text('Tulis caption...'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run — fail** (pill/dual-button belum ada).

- [ ] **Step 3: Implement rework** (mockup v2 layar 3, tema LIGHT):
- **Thumbnail block** (ganti pemakaian `_MediaPreview` 0.62): `Center` + lebar ~42% layar, aspect 3:4, radius 18, `ClipRRect`:
  - Video: `Image.file(thumbnailPath)` cover (fallback kotak `#161A24` + ikon `videocam` muted); pill "Pratinjau" kiri-atas (ikon `visibility_outlined` 12 + teks 10.5 w700, bg `rgba(0,0,0,0.52)` radius 999, padding h10 v4) → `_openPreview`; pill "Ubah sampul" bawah-center (ikon `photo_outlined`) → `_editCover` BARU: push `FeedCoverPickerScreen(videoPath: _videoDraft!.localVideoPath!, rangeStart: _videoDraft!.trimStart ?? Duration.zero, rangeSpan: _videoDraft!.finalDuration!)`; hasil non-null → `setState(_videoDraft = _videoDraft!.copyWith(thumbnailPath: path, userPickedCover: true))`. HAPUS `_CoverPickerSheet` + `_editCover` lama (3 preset).
  - Carousel/foto: `PageView` foto (swipe tetap), counter `X/Y` pill kanan-atas + dot indicator bawah bila >1, pill "Pratinjau" kiri-atas; TANPA "Ubah sampul".
  - Tap area thumbnail (di luar pill) → `_openPreview` juga.
- **Video controller DIHAPUS dari layar ini** (keputusan #4): buang `_videoController`, `_initVideo`, `_trimGuard`, dan param terkait `_MediaPreview`; `_MediaPreview`/`_VideoPreview` lama dihapus atau disusutkan sesuai kebutuhan thumbnail baru (bersihkan yang tak terpakai — analyze menjaga).
- **Bottom bar dual:** ganti `_BottomActions`: Row 2 tombol 52px radius 16 gap 10 — "Simpan Draft" (bg `#F5F8FF` border `#E0E7F0` teks biru w800) → `_saveDraftAndExit()` (existing); "Bagikan" (FilledButton biru, teks 15 w900) → `_upload()`. Param `busy` dihapus total.
- **Mapping produk diperbaiki** di `_loadPurchasedProducts`: tambah `discountPrice: (p['discountPrice'] as num?)?.toDouble(), memberPrice: (p['memberPrice'] as num?)?.toDouble(),` dan `price` = harga DASAR murni `(p['price'] as num?)?.toDouble() ?? 0` (JANGAN fallback discountPrice sebagai base — perbaiki bug lama; cek konstruktor `Product` untuk nama param persis).
- **`_openPreview`** kirim produk + tangani result:
```dart
    final selected = _products.where((p) => _selectedProductIds.contains(p.id)).toList();
    final result = await Navigator.push<FeedPreviewResult>(
      context,
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => FeedPostPreviewScreen(
        draft: widget.draft, videoDraft: _videoDraft, caption: caption, products: selected)),
    );
    if (!mounted) return;
    if (result == FeedPreviewResult.share) { await _upload(); }
    else if (result == FeedPreviewResult.saveDraft) { await _saveDraftAndExit(); }
```
  (Task 3 menambah param `products` + pop-enum di `FeedPostPreviewScreen` secara MINIMAL — cukup param diterima + 2 tombol bawah pop enum — visual penuh dirombak Task 4; ini menjaga tiap task compile+hijau.)
- **Draft save**: `_saveDraftAndExit` payload tambah `'trimStartMs': _videoDraft?.trimStart?.inMilliseconds, 'userPickedCover': _videoDraft?.userPickedCover` (dipakai 2C-1; simpan sekarang supaya format stabil).

- [ ] **Step 4: Run semua — pass** + `flutter analyze`.

- [ ] **Step 5: Commit.**
```bash
git add flutter_app/lib/screens/feed_new_post_screen.dart flutter_app/test/feed_new_post_screen_test.dart
git commit -m "feat(feed): Bagikan — Simpan Draft + Bagikan berdampingan, thumbnail pill Pratinjau/Ubah sampul, mapping diskon produk"
```

---

### Task 4: Pratinjau — chrome feed ASLI + suara (`FeedPostPreviewScreen` rebuild)

**Files:**
- Create: `flutter_app/lib/screens/feed_post/feed_post_preview_screen.dart` (pindahkan + rombak dari `feed_new_post_screen.dart`; enum `FeedPreviewResult` ikut pindah, re-export via import di file lama bila perlu)
- Modify: `flutter_app/lib/screens/feed_new_post_screen.dart` (hapus kelas preview lama + import baru)
- Test: `flutter_app/test/feed_post_preview_screen_test.dart` (baru)

**Interfaces:**
- Consumes: SEMUA widget bersama 2A (`FeedActionRail`, `FeedCreatorIdentity`, `FeedExpandableCaption`, `FeedProductAnchorCard`, `FeedPostScrim`), `appSettingsStore`, `memberStore.profile`, `cartStore.totalQuantity`, `formatRupiah`, `startTrimLoopGuard`.
- Produces: `FeedPostPreviewScreen{draft, videoDraft, caption, products}` pop `FeedPreviewResult?`.

- [ ] **Step 1: Test (failing)** — `test/feed_post_preview_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_action_rail.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_product_anchor_card.dart';
import 'package:natalo_petshop_flutter/models/feed_create_post_draft.dart';
import 'package:natalo_petshop_flutter/models/product.dart';
import 'package:natalo_petshop_flutter/screens/feed_new_post_screen.dart' show NewPostMediaDraft;
import 'package:natalo_petshop_flutter/screens/feed_post/feed_post_preview_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  const vd = FeedCreatePostDraft(
    localVideoPath: '/nonexistent/v.mp4',
    originalDuration: Duration(seconds: 20),
  );
  final produk = Product(
    id: 'p1', slug: 'p1', title: 'Majes Magic Bites', category: '', brand: '',
    imageUrl: '', price: 159000, discountPrice: 129000,
    rating: 0, reviewCount: 0, stock: 3, description: '',
  ); // sesuaikan param wajib konstruktor Product bila berbeda — cek model

  Future<void> pumpIt(WidgetTester tester, {List<Product> products = const []}) async {
    await tester.pumpWidget(MaterialApp(home: FeedPostPreviewScreen(
      draft: const NewPostMediaDraft.video(vd),
      videoDraft: vd, caption: 'Halo dunia kucing', products: products,
    )));
    for (var i = 0; i < 12; i++) { await tester.pump(const Duration(milliseconds: 100)); }
  }

  testWidgets('chrome feed asli: FeedActionRail + caption + dual tombol',
      (tester) async {
    await pumpIt(tester);
    expect(find.text('Pratinjau'), findsOneWidget);
    expect(find.byType(FeedActionRail), findsOneWidget);
    expect(find.textContaining('Halo dunia kucing'), findsOneWidget);
    expect(find.text('Simpan Draft'), findsOneWidget);
    expect(find.text('Bagikan'), findsOneWidget);
  });

  testWidgets('rail non-interaktif (IgnorePointer) + kartu produk tampil '
      'saat ada produk tertag', (tester) async {
    await pumpIt(tester, products: [produk]);
    expect(find.byType(FeedProductAnchorCard), findsOneWidget);
    expect(
      find.ancestor(of: find.byType(FeedActionRail), matching: find.byType(IgnorePointer)),
      findsWidgets,
    );
  });

  testWidgets('Bagikan pop FeedPreviewResult.share', (tester) async {
    FeedPreviewResult? out;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      return ElevatedButton(onPressed: () async {
        out = await Navigator.push<FeedPreviewResult>(context, MaterialPageRoute(
          builder: (_) => FeedPostPreviewScreen(
            draft: const NewPostMediaDraft.video(vd), videoDraft: vd,
            caption: '', products: const [])));
      }, child: const Text('go'));
    })));
    await tester.tap(find.text('go'));
    for (var i = 0; i < 12; i++) { await tester.pump(const Duration(milliseconds: 100)); }
    await tester.tap(find.text('Bagikan'));
    for (var i = 0; i < 6; i++) { await tester.pump(const Duration(milliseconds: 100)); }
    expect(out, FeedPreviewResult.share);
  });
}
```

- [ ] **Step 2: Run — fail.**

- [ ] **Step 3: Implement rebuild** (mockup v2 layar 4 + spec chrome `_FeedPostView`):
- Struktur Stack (scaffold hitam):
  1. `Positioned.fill` media — pertahankan `_buildMediaContent` lama (video contain / foto PageView + counter) — pindahkan verbatim.
  2. `Positioned(left:0,right:0,bottom:0)` `IgnorePointer(FeedPostScrim())` — kontras overlay (sebelumnya TIDAK ada scrim).
  3. Top chrome: back bulat 36 frosted → `Navigator.pop(context)` (null = kembali edit); judul "Pratinjau" (15.5 w800) center; pill "Suara"/"Senyap" kanan (frosted, ikon volume) → toggle `appSettingsStore.setFeedMuted` + `controller.setVolume` live.
  4. Rail kanan: `Positioned(right: 4, bottom: <inset bar bawah + 28>)` → `IgnorePointer(child: FeedActionRail(likeCount: 0, liked: false, commentCount: 0, shareCount: 0, showCart: widget.products.isNotEmpty, cartBadgeCount: cartStore.totalQuantity))` — angka 0 jujur (post baru), cart badge = keranjang nyata (persis feed).
  5. Grup kiri-bawah `Positioned(left: 16, right: 78, bottom: <inset + 28>)` Column crossStart:
     - bila `products.isNotEmpty`: `FeedProductAnchorCard(title: p.title, imageUrl: p.imageUrl.isEmpty ? null : p.imageUrl, priceText: formatRupiah(p.finalPrice), strikePriceText: p.hasDiscount ? formatRupiah(p.price) : null, discountBadgeText: p.hasDiscount ? 'Diskon ${p.discountPercent}%' : null)` (p = produk pertama; non-interaktif: onAddToCart/onTap null) + gap 12.
     - `FeedCreatorIdentity(name: profile?.displayHandle ?? 'Kamu', avatarInitial: profile?.initial ?? 'U', avatarUrl: profile?.profilePhotoUrl, isOfficial: false, followState: FeedFollowChipState.none)` (sudut pandang audiens — chip "Ikuti" tampil, non-interaktif karena `onFollowTap` null) + gap 7.
     - bila caption tidak kosong: `FeedExpandableCaption(text: caption)`.
  6. Bottom bar hitam (`SafeArea top:false`, padding 16/13): Row 2 tombol 48 radius 14 gap 9 — "Simpan Draft" (frosted `rgba(255,255,255,0.07)` border `0.15` teks putih w800) → `Navigator.pop(context, FeedPreviewResult.saveDraft)`; "Bagikan" (biru `#1E5BFF` putih w800) → `pop(context, FeedPreviewResult.share)`.
- **Suara AKTIF:** `_initVideo` set `volume = appSettingsStore.feedMuted ? 0 : 1` (hapus `setVolume(0)` hardcode — INI perbaikan bug #3 user); autoplay + `startTrimLoopGuard` dipertahankan.
- Hapus `_PreviewActionRail`, `_PreviewActionIcon`, `_PreviewCreatorOverlay` (mockup lama); `_PreviewRoundButton` boleh ikut pindah/ganti frosted style.
- `feed_post_preview_opened` telemetri tetap di initState (sudah ada — pastikan ikut pindah).

- [ ] **Step 4: Run semua — pass** + analyze. Perhatikan test Task 3 tetap hijau (signature `_openPreview` sudah disiapkan).

- [ ] **Step 5: Commit.**
```bash
git add flutter_app/lib/screens/feed_post/feed_post_preview_screen.dart flutter_app/lib/screens/feed_new_post_screen.dart flutter_app/test/feed_post_preview_screen_test.dart
git commit -m "feat(feed): Pratinjau chrome feed ASLI + suara — FeedActionRail/CreatorIdentity/Caption/AnchorCard/Scrim, dual Simpan Draft+Bagikan"
```

---

### Task 5: Picker premium polish + pensiun legacy + unifikasi biru

**Files:**
- Modify: `flutter_app/lib/screens/feed_media_picker_screen.dart` (polish + biru + counter)
- Modify: `flutter_app/lib/screens/feed_video_upload_flow.dart` (HAPUS kelas mati)
- Delete: `flutter_app/lib/widgets/feed_upload_sheet.dart`
- Modify: `flutter_app/lib/screens/feed_screen.dart`, `member_posts_screen.dart`, `member_screen.dart` (ganti caller)
- Modify: `flutter_app/lib/state/feed_upload_store.dart` (seam test) + Test: `flutter_app/test/feed_upload_store_test.dart` (baru — follow-up review 2A)

**Interfaces:**
- Consumes: semua task sebelumnya.
- Produces: `FeedMediaPickerScreen.open(BuildContext) → Future<bool?>` (pengganti `FeedUploadSheet.show`):

```dart
  /// Entry point flow posting — pengganti FeedUploadSheet.show() (dihapus).
  static Future<bool?> open(BuildContext context) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const FeedMediaPickerScreen(),
        fullscreenDialog: true,
      ),
    );
  }
```

- [ ] **Step 1: Picker premium polish** (mockup v2 layar 1 — perubahan visual TERBATAS ini saja):
- Ganti SEMUA `_natoloBlue = Color(0xFF2563EB)` → `Color(0xFF1E5BFF)` (badge nomor, border seleksi, tombol Next) — unifikasi token.
- Header: judul "Buat Postingan" → **"Post Baru"**; tombol close jadi lingkaran 36 frosted (`rgba(255,255,255,0.08)` border `0.14`); tombol "Next" teks → **lingkaran 36 biru ikon `chevron_right_rounded`** (disabled: bg `rgba(255,255,255,0.08)` ikon muted).
- Preview besar: tambah pill counter kanan-atas `"Foto X dari Y"` saat multi-foto & yang tersorot foto (X = urutan foto tersorot, Y = total terpilih); video tetap badge durasi existing.
- Grid: badge durasi video diberi ikon play kecil (`play_arrow_rounded` 9px) di depan teks (match mockup). JANGAN ubah logic seleksi/mode/crop.

- [ ] **Step 2: Ganti entry point.** Tambah `open()` static di `FeedMediaPickerScreen`; ganti 3 caller `FeedUploadSheet.show(context)` → `FeedMediaPickerScreen.open(context)` (+import); HAPUS `flutter_app/lib/widgets/feed_upload_sheet.dart` (1447 baris dead). Grep `FeedUploadSheet` sisa = 0.

- [ ] **Step 3: Hapus kelas mati di `feed_video_upload_flow.dart`.** Grep-verifikasi 0 call site lalu hapus: `FeedVideoStartScreen`, `FeedPostDetailScreen`, `FeedUploadProgressScreen`, dan — karena Task 2 memutus picker — `FeedVideoPreviewScreen` + `FeedVideoTrimScreen` (verifikasi dulu tak ada pemanggil tersisa). PERTAHANKAN: `FeedPostSubmittedScreen` (HIDUP via `feed_photo_upload_flow.dart:1111` — verifikasi tetap) + helper yang masih dipakainya (`_DarkUploadScaffold`, `_PrimaryUploadButton`, `_SecondaryUploadButton`, dll — analyze memandu; hapus helper yatim: `_VideoPreviewStage` copy lama, `_InfoPanel`, `_TrimTimeline` copy lama, `_ProductTagPicker`, `_FeedVideoFlowException` cek pemakai, `_UnsupportedVideoException` + `_readVideoDuration` + `_copyVideoToCache` + `_generateVideoThumbnail` + `_videoMimeType` — beberapa mungkin masih dipakai `FeedMediaPickerScreen` via import; kalau dipakai lintas file, PINDAHKAN ke `lib/screens/feed_post/feed_video_utils.dart` daripada duplikat). Target: file susut besar; jalankan analyze berulang sampai bersih.
- Telemetri `feed_post_pick_opened{source:'video_start'}` ikut terhapus (dead) — biarkan; sumber `media_picker` tetap.

- [ ] **Step 4: Test store rethrow (follow-up review 2A).** Tambah seam di `FeedUploadStore`:
```dart
  /// Injectable untuk unit test — default gate global.
  @visibleForTesting
  VideoCompressGate gate = videoCompressGate;
```
(ganti pemanggilan `videoCompressGate.compress` → `gate.compress` di `_runVideoUpload` + `_runPhotoUpload` bila ada). Buat `test/feed_upload_store_test.dart`:

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_create_post_draft.dart';
import 'package:natalo_petshop_flutter/services/video_compress_gate.dart';
import 'package:natalo_petshop_flutter/state/feed_upload_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('kompresi gagal + trimStart → task FAILED (tanpa fallback original)',
      () async {
    final tmp = await File(
      '${Directory.systemTemp.path}/store-test-${DateTime.now().microsecondsSinceEpoch}.mp4',
    ).create();
    addTearDown(() => tmp.delete());
    final store = FeedUploadStore.instance;
    store.clear();
    store.gate = VideoCompressGate(
      compressRunner: (path, {quality = VideoQuality.Res1280x720Quality,
          includeAudio = true, startTime, duration}) async {
        throw StateError('compress boom');
      },
      cancelRunner: () async {},
      isPluginBusy: () => false,
      resetPluginFlag: () {},
    );
    await store.startVideoUpload(
      draft: FeedCreatePostDraft(
        localVideoPath: tmp.path,
        originalDuration: const Duration(seconds: 70),
        trimStart: const Duration(seconds: 5),
        trimmedDuration: const Duration(seconds: 60),
      ),
    );
    // startVideoUpload fire-and-forget — tunggu task settle.
    for (var i = 0; i < 50 && store.activeTask?.status != FeedUploadStatus.failed; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(store.activeTask?.status, FeedUploadStatus.failed);
    store.clear();
  });
}
```
(Import `VideoQuality` dari `package:video_compress/video_compress.dart` bila perlu; sesuaikan signature `CompressRunner` persis dengan gate. Test ini juga membuktikan rethrow tidak jatuh ke jalur upload jaringan — gagal SEBELUM ada network call.)

- [ ] **Step 5: Run semua — pass** + analyze bersih. Grep akhir: `FeedUploadSheet|FeedVideoStartScreen|FeedPostDetailScreen|FeedUploadProgressScreen|FeedVideoPreviewScreen|FeedVideoTrimScreen` di lib/ = 0 (kecuali komentar sejarah bila ada).

- [ ] **Step 6: Commit.**
```bash
git add -A flutter_app/lib flutter_app/test
git commit -m "feat(feed): picker premium + biru terunifikasi #1E5BFF, pensiun 5 layar legacy + feed_upload_sheet (±3000 baris), test store rethrow"
```

---

### Task 6: Bar unggahan feed — redesign relay card (spec §2A-5, disetujui user 2026-07-11)

**Files:**
- Create: `flutter_app/lib/features/feed/widgets/feed_upload_bar.dart`
- Modify: konsumer relay card existing (LOKASIKAN via Grep `feedUploadStore` di lib/screens & lib/widgets — komponen relay card lama yang me-render `FeedUploadTask` di atas feed/Beranda; ganti dengan bar baru)
- Modify: `flutter_app/lib/state/feed_upload_store.dart` (API cancel best-effort)
- Test: `flutter_app/test/feed_upload_bar_test.dart`

**Interfaces:**
- Consumes: `feedUploadStore` (`FeedUploadTask{kind, status, progress, photoFiles, videoDraft, errorMessage}`, `retry()`, `dismissFailed()`).
- Produces: `class FeedUploadBar extends StatefulWidget { const FeedUploadBar({super.key}); }` — listen `feedUploadStore`, render bar ±56px per spec §2A-5; `FeedUploadStore.cancelActive()` (best-effort).

- [ ] **Step 1: Test (failing)** — `test/feed_upload_bar_test.dart` (drive via store: set task state lewat metode publik atau `@visibleForTesting` setter `debugSetTask(FeedUploadTask?)` yang ditambahkan ke store):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_upload_bar.dart';
import 'package:natalo_petshop_flutter/state/feed_upload_store.dart';

Widget _wrap() => const MaterialApp(
    home: Scaffold(backgroundColor: Colors.black, body: FeedUploadBar()));

FeedUploadTask _task(FeedUploadStatus s, {double progress = 0.4}) {
  // Semua kasus test pakai kind video (photoFiles kosong) — varian copy
  // foto/carousel diuji manual di device (butuh File nyata utk thumbnail).
  return FeedUploadTask(
    localId: 't1', kind: FeedUploadKind.video,
    status: s, progress: progress, createdAt: DateTime(2026),
  );
}

void main() {
  tearDown(() => feedUploadStore.clear());

  testWidgets('idle: bar tidak dirender', (tester) async {
    await tester.pumpWidget(_wrap());
    expect(find.byType(FeedUploadBar), findsOneWidget);
    expect(find.textContaining('diposting'), findsNothing);
  });

  testWidgets('preparing video: copy + spinner + tombol batal', (tester) async {
    feedUploadStore.debugSetTask(_task(FeedUploadStatus.preparing));
    await tester.pumpWidget(_wrap());
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Sebentar ya, videomu lagi diposting…'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
  });

  testWidgets('waitingReview: copy terkirim, tanpa tombol batal', (tester) async {
    feedUploadStore.debugSetTask(_task(FeedUploadStatus.waitingReview, progress: 1));
    await tester.pumpWidget(_wrap());
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Terkirim! Menunggu review admin dulu ya'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsNothing);
  });

  testWidgets('failed: copy gagal + tombol Coba lagi', (tester) async {
    feedUploadStore.debugSetTask(_task(FeedUploadStatus.failed));
    await tester.pumpWidget(_wrap());
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Gagal mengunggah'), findsOneWidget);
    expect(find.text('Coba lagi'), findsOneWidget);
  });
}
```
(Sesuaikan konstruksi `FeedUploadTask` dengan konstruktor nyata; `debugSetTask` = setter `@visibleForTesting` baru di store yang assign `_task` + `notifyListeners`.)

- [ ] **Step 2: Run — fail.**

- [ ] **Step 3: Implement bar** persis spec §2A-5 (baca ulang section itu — nilai final semua di sana): tinggi ±56, padding 8×10 radius 14, kartu `#12151D` border `rgba(255,255,255,0.11)` + inset highlight; thumbnail per kind (video potret 32×40 dari `videoDraft.thumbnailPath`, foto 34×34, carousel 3 tumpuk + badge jumlah); progress 4px gradasi `#1E5BFF→#5B8CFF` + sheen ~1.7s (AnimationController repeat); copy per status PERSIS tabel spec (video/foto/carousel varian; uploading bergantian 2 teks tiap ~2s cross-fade 300ms); indikator kanan persen / "Foto n/3" (map `progress` & kind) / spinner / ikon status; failed = subteks + pill "Coba lagi" → `feedUploadStore.retry()`; waitingReview/success tint per spec + auto-dismiss (timer existing di store — bar hanya render). JANGAN menjanjikan "langsung tayang" — `waitingReview` = state akhir normal customer.
- **Tombol batal (best-effort, semantik terdefinisi):** tambah di store `Future<void> cancelActive()`: set flag `_cancelRequested`; dicek SETELAH tiap `await` besar di `_runVideoUpload`/`_runPhotoUpload` (setelah compress, setelah thumbnail, SEBELUM provision, SEBELUM finalize) → bila ter-set: transisi `FeedUploadStatus.cancelled`, `_uploading=false`, `_task=null` setelah 400ms, return tanpa melempar. Kompresi in-flight: store membuat `VideoCompressJob` untuk compress-nya → `gate.cancel(job)` (gate 2A sudah scoped). TUS in-flight: JANGAN mencoba abort socket (library tidak expose abort aman) — flag dicek setelah chunk selesai; placeholder Bunny yang telanjur dibuat jadi orphan server-side (sama seperti kegagalan existing — catat di komentar, jujur). Tombol batal hanya render saat `preparing`/`uploading`.
- Ganti pemakaian relay card lama dengan `FeedUploadBar` di lokasi yang sama (posisi/pin existing dipertahankan); komponen lama dihapus bila tak ada pemakai lain.

- [ ] **Step 4: Run semua — pass** + analyze.

- [ ] **Step 5: Commit.**
```bash
git add -A flutter_app/lib flutter_app/test
git commit -m "feat(feed): bar unggahan ramping ala IG — copy ramah per status, progress gradasi+sheen, batal best-effort (spec 2A-5)"
```

---

### Task 7: Regression penuh + checklist device-verify 2B

**Files:** tidak ada perubahan kode.

- [ ] **Step 1: Full suite.** `cd flutter_app && flutter analyze && flutter test` — analyze hanya lint pre-existing; semua test pass (termasuk 10+ test baru 2B).

- [ ] **Step 2: Checklist device-verify 2B (laporkan ke user — JANGAN klaim terverifikasi):**
0. Bar unggahan: muncul saat posting, copy berganti sesuai status, "Foto n/3" untuk carousel, batal saat preparing benar-benar menghentikan, waitingReview tint biru lalu auto-dismiss.
1. **Side-by-side IG** (standar visual spec): tiap layar dibanding screenshot `Desktop/IG` — picker, editor, share, preview, cover.
2. Picker: grid campur mulus scroll 100+ item, badge nomor urut benar, counter "Foto X dari Y", Next bulat biru.
3. Video ≤60s DAN >60s → Edit Video fullscreen: suara terdengar (toggle Suara sinkron dengan mute feed), trim handle mulus, Potong toggle timeline, Next instan.
4. Sampul: pilih frame via scrubber di editor DAN di Bagikan → cover di post final = frame pilihan (BUKAN di-regenerate) — cek juga setelah ganti rentang trim (sampul direset).
5. Bagikan: Simpan Draft + Bagikan berdampingan; draft tersimpan & bisa dilanjutkan (banner existing).
6. Pratinjau: chrome PERSIS feed (rail, kartu produk dengan harga coret bila diskon, identitas, caption, scrim) + SUARA KELUAR (bug #3) + tampilan tidak aneh lagi (bug #4); Bagikan dari pratinjau langsung upload.
7. Carousel foto: pilih 3 foto → Bagikan (counter 1/3 + dots) → Pratinjau swipe → upload sukses.
8. Feed publik tetap identik (regresi ekstraksi 2A + penghapusan legacy).
9. Firebase DebugView: `feed_post_edit_opened` kini muncul juga untuk video ≤60s.

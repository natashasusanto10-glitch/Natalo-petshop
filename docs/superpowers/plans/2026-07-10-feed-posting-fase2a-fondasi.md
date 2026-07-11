# Feed Posting Fase 2A — Fondasi Teknik Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fondasi Fase 2 — chrome feed jadi widget bersama (anti-drift untuk Pratinjau 2B), "Next" instan (kompresi pindah ke background store), pre-flight check format media, dan telemetri funnel posting.

**Architecture:** (1) Ekstraksi murni widget chrome dari `feed_screen.dart` ke 4 file widget publik di `lib/features/feed/widgets/` — perilaku feed publik TIDAK berubah. (2) `FeedCreatePostDraft` dapat field `trimStart`; layar trim berhenti mengkompres — `FeedUploadStore` mengkompres sekali dengan `startTime`/`duration` via `videoCompressGate`. (3) Deteksi format-tak-didukung di titik pick. (4) Event funnel via `AppAnalytics.logEvent` existing.

**Tech Stack:** Flutter/Dart, `video_compress` via `VideoCompressGate` (WAJIB — jangan panggil plugin langsung), Firebase Analytics via `AppAnalytics`. Package: `natalo_petshop_flutter`.

**Spec:** `docs/superpowers/specs/2026-07-10-feed-posting-fase2-ig-parity-design.md` (bagian 2A).

## Global Constraints

- **Perilaku & tampilan feed publik TIDAK BOLEH berubah** — Task 1–3 refactor murni (pindah kode, ganti nama private→public, sambung ulang referensi). Verifikasi: `flutter analyze` bersih + widget test + feed tampil identik.
- Satu-satunya perubahan tampilan yang diizinkan plan ini: hilangnya panel "Sedang memproses video..." + dialog batal-proses di layar Edit Video (konsekuensi Next instan, Task 4–5).
- Semua kompresi lewat `videoCompressGate` (`lib/services/video_compress_gate.dart`) — `compress(path, {quality, includeAudio, startTime, duration, job})`.
- Kerja dari `flutter_app/`; tiap task diakhiri `flutter analyze` (lolos bila satu-satunya isu = lint pre-existing `unnecessary_nullable_for_final_variable_declarations` di `lib/config/launch_popup_campaigns.dart:10`) + `flutter test` hijau + commit.
- `AppAnalytics.logEvent(String name, [Map<String, Object>? params])` — `lib/services/app_analytics.dart:29` (aman dipanggil kapan pun; no-op + debugPrint kalau Firebase belum siap).
- Nomor baris `feed_screen.dart` di bawah = hasil riset 2026-07-10; verifikasi ulang dengan Grep sebelum memindah (file bisa bergeser beberapa baris).

---

### Task 1: Ekstraksi rail aksi → `FeedActionRail`

**Files:**
- Create: `flutter_app/lib/features/feed/widgets/feed_action_rail.dart`
- Modify: `flutter_app/lib/screens/feed_screen.dart` (hapus kelas yang dipindah + pakai widget baru di `_FeedPostView.build` ± :3277-3341)
- Test: `flutter_app/test/feed_action_rail_test.dart`

**Interfaces:**
- Consumes: tidak ada (task pertama).
- Produces (dipakai feed_screen sekarang + layar Pratinjau di 2B):

```dart
/// Rail aksi kanan feed video/foto — like, comment, share, cart, more.
/// Ekstraksi 1:1 dari feed_screen (ikon CustomPaint 30px stroke 1.7,
/// angka 12 w600 putih ber-shadow, spacing antar item 18).
class FeedActionRail extends StatelessWidget {
  final int likeCount;
  final bool liked;
  final int commentCount;
  final int shareCount;
  /// Tampilkan tombol cart (feed: hanya bila post punya produk).
  final bool showCart;
  /// Angka badge oranye di ikon cart (jumlah item keranjang).
  final int cartBadgeCount;
  final VoidCallback? onLike;
  final VoidCallback? onComment;
  final VoidCallback? onShare;
  final VoidCallback? onCart;
  final VoidCallback? onMore;

  const FeedActionRail({
    super.key,
    required this.likeCount,
    required this.liked,
    required this.commentCount,
    required this.shareCount,
    this.showCart = false,
    this.cartBadgeCount = 0,
    this.onLike,
    this.onComment,
    this.onShare,
    this.onCart,
    this.onMore,
  });
  // build(): Column(mainAxisSize: min) berisi item-item _ReelsAction
  // persis susunan feed sekarang (like → comment → share → [cart] → more).
}
```

- [ ] **Step 1: Tulis failing test**

Buat `flutter_app/test/feed_action_rail_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_action_rail.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: child),
      ),
    );

void main() {
  testWidgets('menampilkan angka like/comment/share', (tester) async {
    await tester.pumpWidget(_wrap(const FeedActionRail(
      likeCount: 128,
      liked: false,
      commentCount: 14,
      shareCount: 6,
    )));
    expect(find.text('128'), findsOneWidget);
    expect(find.text('14'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
  });

  testWidgets('cart hanya tampil saat showCart', (tester) async {
    await tester.pumpWidget(_wrap(const FeedActionRail(
      likeCount: 0, liked: false, commentCount: 0, shareCount: 0,
    )));
    expect(find.byIcon(Icons.shopping_cart), findsNothing);

    await tester.pumpWidget(_wrap(const FeedActionRail(
      likeCount: 0, liked: false, commentCount: 0, shareCount: 0,
      showCart: true, cartBadgeCount: 2,
    )));
    expect(find.byIcon(Icons.shopping_cart), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('format angka ribuan pakai K', (tester) async {
    await tester.pumpWidget(_wrap(const FeedActionRail(
      likeCount: 1500, liked: false, commentCount: 0, shareCount: 0,
    )));
    expect(find.text('1.5K'), findsOneWidget);
  });

  testWidgets('callback null tidak crash saat tap (mode pratinjau)',
      (tester) async {
    await tester.pumpWidget(_wrap(const FeedActionRail(
      likeCount: 1, liked: true, commentCount: 1, shareCount: 1,
    )));
    await tester.tap(find.text('1').first);
    await tester.pump();
  });
}
```

- [ ] **Step 2: Jalankan test — pastikan gagal**

Run (dari `flutter_app/`): `flutter test test/feed_action_rail_test.dart`
Expected: FAIL compile — `feed_action_rail.dart` belum ada.

- [ ] **Step 3: Pindahkan kode + buat widget publik**

Di `feed_screen.dart`, temukan dengan Grep lalu PINDAHKAN VERBATIM (cut, bukan copy) ke `feed_action_rail.dart`:
- Konstanta rail: `_feedActionForegroundColor`, `_feedActionShadowColor`, `_feedActionTextShadowColor`, `_feedActionIconSize`, `_feedActionStrokeWidth`, `_feedActionCountFontSize`, `_feedActionItemSpacing` (± :51-60). Yang dipakai file lain tetap di feed_screen bila ada — cek pemakaian dulu.
- Kelas: `_ReelsAction` (± :4366, termasuk logic format angka K/M ± :4470 dan tap-pulse), `_ReelsHeartGlyph`, `_ReelsCommentGlyph`, `_ReelsShareGlyph`, `_ReelsCartGlyph`, `_ReelsMoreGlyph` beserta painter internalnya.
- Kelas pindahan tetap private di file baru; hanya `FeedActionRail` (kode API di atas) yang publik. `build()` menyusun Column persis blok rail lama di `_FeedPostView` (± :3277-3341): like (glyph liked/`likeCount`), comment, share, `if (showCart)` cart dengan `cartBadgeCount`, more tanpa angka, dipisah `SizedBox(height: _feedActionItemSpacing)`.
- Di `_FeedPostView.build`, blok rail lama diganti pemanggilan `FeedActionRail(...)` dengan nilai/handler yang sama persis (like → `_toggleLike` dst.); wrapper posisi + fade animation TETAP di feed_screen.
- Import `../features/feed/widgets/feed_action_rail.dart` di feed_screen.

- [ ] **Step 4: Jalankan test — pastikan lulus**

Run: `flutter test test/feed_action_rail_test.dart`
Expected: PASS (4 tests). Kalau format K memakai koma (`1,5K`) di kode asli, sesuaikan EXPECT test ke perilaku asli — jangan ubah perilaku.

- [ ] **Step 5: Analyze + seluruh test + commit**

```bash
cd flutter_app && flutter analyze && flutter test
git add flutter_app/lib/features/feed/widgets/feed_action_rail.dart flutter_app/lib/screens/feed_screen.dart flutter_app/test/feed_action_rail_test.dart
git commit -m "refactor(feed): ekstraksi rail aksi ke FeedActionRail — widget bersama feed + pratinjau"
```

---

### Task 2: Ekstraksi identitas kreator + caption → `feed_creator_overlay.dart`

**Files:**
- Create: `flutter_app/lib/features/feed/widgets/feed_creator_overlay.dart`
- Modify: `flutter_app/lib/screens/feed_screen.dart` (± :3344-3392 pemakaian; kelas :3491, :3584, :3678, :3757)
- Test: `flutter_app/test/feed_creator_overlay_test.dart`

**Interfaces:**
- Consumes: tidak ada.
- Produces:

```dart
enum FeedFollowChipState { none, following, hidden }

/// Baris identitas kreator: avatar 34 + nama 13.5 w600 (+verified gold
/// bila official) + chip Ikuti/Mengikuti. Ekstraksi 1:1 dari feed_screen.
class FeedCreatorIdentity extends StatelessWidget {
  final String name;
  final String avatarInitial;
  final String? avatarUrl;
  final bool isOfficial;
  final FeedFollowChipState followState;
  final VoidCallback? onFollowTap;
  final VoidCallback? onProfileTap;
  const FeedCreatorIdentity({
    super.key,
    required this.name,
    required this.avatarInitial,
    this.avatarUrl,
    this.isOfficial = false,
    this.followState = FeedFollowChipState.hidden,
    this.onFollowTap,
    this.onProfileTap,
  });
}

/// Caption expandable feed: 13.2 w600 putih, 2 baris + "selengkapnya".
class FeedExpandableCaption extends StatefulWidget {
  final String text;
  final void Function(String username)? onMentionTap;
  const FeedExpandableCaption({super.key, required this.text, this.onMentionTap});
}
```

- [ ] **Step 1: Tulis failing test**

Buat `flutter_app/test/feed_creator_overlay_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_creator_overlay.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Align(alignment: Alignment.bottomLeft, child: child),
      ),
    );

void main() {
  testWidgets('nama + chip Ikuti tampil saat followState none', (tester) async {
    await tester.pumpWidget(_wrap(const FeedCreatorIdentity(
      name: 'Asiong Silalahi',
      avatarInitial: 'A',
      followState: FeedFollowChipState.none,
    )));
    expect(find.text('Asiong Silalahi'), findsOneWidget);
    expect(find.text('Ikuti'), findsOneWidget);
  });

  testWidgets('chip hilang saat hidden; verified tampil saat official',
      (tester) async {
    await tester.pumpWidget(_wrap(const FeedCreatorIdentity(
      name: 'Natalo Petshop',
      avatarInitial: 'N',
      isOfficial: true,
      followState: FeedFollowChipState.hidden,
    )));
    expect(find.text('Ikuti'), findsNothing);
    expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
  });

  testWidgets('caption panjang terpotong 2 baris dengan selengkapnya',
      (tester) async {
    final longText = List.filled(40, 'kata').join(' ');
    await tester.pumpWidget(_wrap(SizedBox(
      width: 240,
      child: FeedExpandableCaption(text: longText),
    )));
    expect(find.textContaining('selengkapnya'), findsOneWidget);
    await tester.tap(find.textContaining('selengkapnya'));
    await tester.pump();
    expect(find.textContaining('lebih sedikit'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Jalankan test — pastikan gagal**

Run: `flutter test test/feed_creator_overlay_test.dart`
Expected: FAIL compile.

- [ ] **Step 3: Pindahkan kode**

PINDAHKAN VERBATIM dari `feed_screen.dart` ke `feed_creator_overlay.dart`: `_FeedCreatorIdentity` (± :3491) → publik `FeedCreatorIdentity` dengan API di atas (parameter menggantikan akses langsung ke model post — pemetaan dilakukan pemanggil), `_FeedCreatorAvatar` (± :3678, tetap private), `_FeedFollowChip` (± :3584, tetap private; `followState` menggantikan bool lama: `none`→"Ikuti", `following`→"Mengikuti", `hidden`→tidak render), `_ExpandableCaption` (± :3757) → publik `FeedExpandableCaption`, plus konstanta `_officialGold` (± :49) bila hanya dipakai kelas-kelas ini (kalau dipakai bagian lain feed_screen, duplikasi sebagai const lokal file baru dengan komentar rujukan).
`_FeedPostView.build` memetakan post → parameter widget baru; caption tap-mention tetap jalan (handler lama diteruskan via `onMentionTap`).

- [ ] **Step 4: Jalankan test — pastikan lulus**

Run: `flutter test test/feed_creator_overlay_test.dart`
Expected: PASS (3 tests). Kalau teks expand asli bukan "lebih sedikit", sesuaikan expect ke teks asli.

- [ ] **Step 5: Analyze + seluruh test + commit**

```bash
cd flutter_app && flutter analyze && flutter test
git add flutter_app/lib/features/feed/widgets/feed_creator_overlay.dart flutter_app/lib/screens/feed_screen.dart flutter_app/test/feed_creator_overlay_test.dart
git commit -m "refactor(feed): ekstraksi identitas kreator + caption ke feed_creator_overlay — widget bersama"
```

---

### Task 3: Ekstraksi kartu produk + scrim → `feed_product_anchor_card.dart` + `feed_post_scrim.dart`

**Files:**
- Create: `flutter_app/lib/features/feed/widgets/feed_product_anchor_card.dart`
- Create: `flutter_app/lib/features/feed/widgets/feed_post_scrim.dart`
- Modify: `flutter_app/lib/screens/feed_screen.dart` (scrim inline ± :3235-3256; `_ProductAnchorCard` ± :4966)
- Test: `flutter_app/test/feed_product_anchor_card_test.dart`

**Interfaces:**
- Consumes: tidak ada.
- Produces:

```dart
/// Kartu produk anchor di atas identitas kreator (blur, bg black .52,
/// border white .16, radius 14; harga merah #FF5A5F; tombol keranjang
/// oranye #FF7A00 34x34). API primitif — decoupled dari model post,
/// supaya Pratinjau (model Product katalog) bisa memakai widget sama.
class FeedProductAnchorCard extends StatelessWidget {
  final String title;
  final String? imageUrl;
  final String priceText;          // sudah diformat rupiah oleh pemanggil
  final String? strikePriceText;   // harga coret opsional
  final String? discountBadgeText; // "Diskon 19%" opsional
  final VoidCallback? onAddToCart;
  final VoidCallback? onTap;
  const FeedProductAnchorCard({
    super.key,
    required this.title,
    required this.priceText,
    this.imageUrl,
    this.strikePriceText,
    this.discountBadgeText,
    this.onAddToCart,
    this.onTap,
  });
}

/// Scrim gradient bawah feed (330px, transparent → black .24 → black .76,
/// stops [0, .54, 1]).
class FeedPostScrim extends StatelessWidget {
  final double height;
  const FeedPostScrim({super.key, this.height = 330});
}
```

- [ ] **Step 1: Tulis failing test**

Buat `flutter_app/test/feed_product_anchor_card_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_product_anchor_card.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: SizedBox(width: 260, child: child)),
      ),
    );

void main() {
  testWidgets('judul + harga + harga coret + badge diskon tampil',
      (tester) async {
    await tester.pumpWidget(_wrap(const FeedProductAnchorCard(
      title: 'Majes Magic Bites',
      priceText: 'Rp129.000',
      strikePriceText: 'Rp159.000',
      discountBadgeText: 'Diskon 19%',
    )));
    expect(find.text('Majes Magic Bites'), findsOneWidget);
    expect(find.text('Rp129.000'), findsOneWidget);
    expect(find.text('Rp159.000'), findsOneWidget);
    expect(find.text('Diskon 19%'), findsOneWidget);
  });

  testWidgets('tanpa harga coret & badge — tidak render elemen opsional',
      (tester) async {
    await tester.pumpWidget(_wrap(const FeedProductAnchorCard(
      title: 'Wild Call',
      priceText: 'Rp98.000',
    )));
    expect(find.text('Wild Call'), findsOneWidget);
    expect(find.textContaining('Diskon'), findsNothing);
  });
}
```

- [ ] **Step 2: Jalankan test — pastikan gagal**

Run: `flutter test test/feed_product_anchor_card_test.dart`
Expected: FAIL compile.

- [ ] **Step 3: Pindahkan kode**

- `_ProductAnchorCard` (± :4966) + badge diskon + `_feedCommerceOrange` → `feed_product_anchor_card.dart`; refactor field model post → parameter primitif API di atas; `_FeedPostView` (dan grup `_ProductCommerceOverlayGroup` ± :4859 yang tetap di feed_screen) memformat harga (`formatRupiah`) lalu memanggil widget baru. CTA end-of-video + arrow pointer TETAP di feed_screen (perilaku feed spesifik, bukan chrome bersama).
- Blok scrim inline (± :3235-3256) → `FeedPostScrim`; feed_screen memakai `FeedPostScrim()` di posisi sama (Positioned + IgnorePointer tetap di pemanggil bila memang di situ).

- [ ] **Step 4: Jalankan test — pastikan lulus**

Run: `flutter test test/feed_product_anchor_card_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Analyze + seluruh test + commit**

```bash
cd flutter_app && flutter analyze && flutter test
git add flutter_app/lib/features/feed/widgets/feed_product_anchor_card.dart flutter_app/lib/features/feed/widgets/feed_post_scrim.dart flutter_app/lib/screens/feed_screen.dart flutter_app/test/feed_product_anchor_card_test.dart
git commit -m "refactor(feed): ekstraksi kartu produk anchor + scrim ke widget bersama"
```

---

### Task 4: Approach B (bagian store) — draft `trimStart` + kompresi ber-range + thumbnail ber-range

**Files:**
- Modify: `flutter_app/lib/models/feed_create_post_draft.dart`
- Modify: `flutter_app/lib/state/feed_upload_store.dart` (`_runVideoUpload` step 0 & step 1)
- Test: `flutter_app/test/feed_create_post_draft_test.dart`

**Interfaces:**
- Consumes: `videoCompressGate.compress(path, {quality, includeAudio, startTime, duration})` (Fase 1).
- Produces (dipakai Task 5): field `Duration? trimStart` di `FeedCreatePostDraft` + helper statis:

```dart
/// Argumen kompresi dari draft — dipakai FeedUploadStore.
/// trimStart null = kompres penuh tanpa potong.
({int? startTimeSec, int? durationSec}) compressRangeOf(FeedCreatePostDraft d) {
  if (d.trimStart == null) return (startTimeSec: null, durationSec: null);
  return (
    startTimeSec: d.trimStart!.inSeconds,
    durationSec: (d.trimmedDuration ?? d.originalDuration)?.inSeconds,
  );
}
```

- [ ] **Step 1: Tulis failing test**

Buat `flutter_app/test/feed_create_post_draft_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_create_post_draft.dart';

void main() {
  test('compressRangeOf: tanpa trimStart → kompres penuh', () {
    const d = FeedCreatePostDraft(
      localVideoPath: 'a.mp4',
      originalDuration: Duration(seconds: 40),
    );
    final r = compressRangeOf(d);
    expect(r.startTimeSec, isNull);
    expect(r.durationSec, isNull);
  });

  test('compressRangeOf: dengan trimStart + trimmedDuration', () {
    const d = FeedCreatePostDraft(
      localVideoPath: 'a.mp4',
      originalDuration: Duration(seconds: 76),
      trimStart: Duration(seconds: 10),
      trimmedDuration: Duration(seconds: 60),
    );
    final r = compressRangeOf(d);
    expect(r.startTimeSec, 10);
    expect(r.durationSec, 60);
  });

  test('copyWith mempertahankan trimStart', () {
    const d = FeedCreatePostDraft(
      localVideoPath: 'a.mp4',
      trimStart: Duration(seconds: 5),
    );
    expect(d.copyWith(caption: 'x').trimStart, const Duration(seconds: 5));
  });

  test('finalDuration fallback tetap: trimmedDuration ?? originalDuration', () {
    const d = FeedCreatePostDraft(
      originalDuration: Duration(seconds: 30),
      trimStart: Duration(seconds: 3),
      trimmedDuration: Duration(seconds: 20),
    );
    expect(d.finalDuration, const Duration(seconds: 20));
  });
}
```

- [ ] **Step 2: Jalankan test — pastikan gagal**

Run: `flutter test test/feed_create_post_draft_test.dart`
Expected: FAIL compile — `trimStart`/`compressRangeOf` belum ada.

- [ ] **Step 3: Implementasi model**

Di `feed_create_post_draft.dart`: tambah `final Duration? trimStart;` (konstruktor + `copyWith`, pola sama field lain) + fungsi top-level `compressRangeOf` persis blok Interfaces di atas, dengan doc-comment: `trimStart` = titik mulai potong pilihan user; kompresi terjadi di store (Approach B), BUKAN di layar trim.

- [ ] **Step 4: Update store**

Di `feed_upload_store.dart` `_runVideoUpload`:

Step 0 (kompresi) — ganti pemanggilan gate menjadi ber-range:

```dart
          final range = compressRangeOf(draft);
          final info = await videoCompressGate.compress(
            originalPath,
            quality: VideoQuality.Res1280x720Quality,
            includeAudio: true,
            startTime: range.startTimeSec,
            duration: range.durationSec,
          );
```

dan guard skip: kompresi tetap DISKIP hanya bila `draft.trimmedVideoPath != null` (hasil kompres lama yang masih valid); bila `trimmedVideoPath == null` selalu kompres (dengan atau tanpa range). PENTING: bila kompresi gagal DAN `range.startTimeSec != null`, JANGAN fallback upload original (original belum terpotong — salah konten). Ganti fallback: `rethrow` bila `range.startTimeSec != null`, fallback-original hanya untuk kasus tanpa trim. Tambah komentar alasan.

Step 1 (thumbnail) — bila `thumbPath` null dan `draft.trimStart != null`, `timeMs` = `draft.trimStart!.inMilliseconds + 500` (bukan 500 dari awal video — frame sampul harus dari bagian terpilih).

- [ ] **Step 5: Jalankan test — pastikan lulus**

Run: `flutter test test/feed_create_post_draft_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 6: Analyze + seluruh test + commit**

```bash
cd flutter_app && flutter analyze && flutter test
git add flutter_app/lib/models/feed_create_post_draft.dart flutter_app/lib/state/feed_upload_store.dart flutter_app/test/feed_create_post_draft_test.dart
git commit -m "feat(feed): Approach B store — draft trimStart, kompresi ber-range via gate, thumbnail dari range"
```

---

### Task 5: Approach B (bagian layar) — Next instan di Edit Video

**Files:**
- Modify: `flutter_app/lib/screens/feed_video_upload_flow.dart` — `_FeedVideoTrimScreenState` (`_exportTrim` ± :563, `dispose`, `build` ± :670-700) dan pemakaian `_exporting`/`_ProcessingPanel`

**Interfaces:**
- Consumes (Task 4): `draft.copyWith(trimStart:, trimmedDuration:)`.
- Produces: Next di layar trim mengembalikan draft ber-range TANPA kompresi; `FeedPostPreviewScreen`/`FeedNewPostScreen` menerima draft dengan `trimmedVideoPath == null` + `trimStart` terisi.

- [ ] **Step 1: Ganti `_exportTrim` → `_confirmSelection`**

Hapus `_exportTrim` (beserta pemakaian `videoCompressGate.compress`, `_exportJob`, `VideoCompressJob`) dan ganti:

```dart
  /// Approach B: Next instan — TIDAK mengkompres di layar ini. Rentang
  /// pilihan disimpan ke draft (trimStart + trimmedDuration); kompresi
  /// terjadi SEKALI di FeedUploadStore saat upload dimulai.
  Future<void> _confirmSelection() async {
    final selectedSeconds = (_range.end - _range.start).round();
    if (selectedSeconds < _minFeedVideoSeconds ||
        selectedSeconds > _maxFeedVideoSeconds) {
      setState(() {
        _error = 'Pilih durasi antara 1 sampai 60 detik.';
      });
      return;
    }
    AppHaptics.tap();
    await _controller?.pause();
    if (!mounted) return;
    final nextDraft = widget.draft.copyWith(
      trimStart: Duration(milliseconds: (_range.start * 1000).round()),
      trimmedDuration: Duration(seconds: selectedSeconds),
    );
    if (widget.returnResultOnNext) {
      Navigator.pop(context, nextDraft);
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FeedNewPostScreen(
          draft: NewPostMediaDraft.video(nextDraft),
        ),
      ),
    );
  }
```

- [ ] **Step 2: Bersihkan state & UI menunggu**

- Field `_exporting` + `_exportJob` dihapus; tombol Next: `onTap: _loading ? null : _confirmSelection`; kondisi `busy:` di `_RoundNextButton` jadi `false` (atau parameter dihapus bila tidak dipakai lagi di tempat lain — cek dulu).
- Blok `if (_exporting) ... _ProcessingPanel()` di build dihapus; kelas `_ProcessingPanel` ikut dihapus BILA tidak dipakai kelas lain di file (Grep dulu).
- `PopScope` + `_confirmCancelExport` dihapus (tidak ada proses yang perlu dilindungi); `onLeading` kembali `() => Navigator.pop(context)`.
- `dispose`: hapus blok cancel job. Import `video_compress_gate.dart` dihapus BILA tak ada pemakai lain di file (layar `FeedUploadProgressScreen` legacy masih memakai gate — cek sebelum hapus import).
- Timeline `onChanged` guard `_exporting` dihapus.

- [ ] **Step 3: Analyze + seluruh test + commit**

```bash
cd flutter_app && flutter analyze && flutter test
git add flutter_app/lib/screens/feed_video_upload_flow.dart
git commit -m "feat(feed): Next instan di Edit Video — rentang trim disimpan ke draft, kompresi pindah ke store (Approach B)"
```

---

### Task 6: Playback preview menghormati rentang trim

**Files:**
- Modify: `flutter_app/lib/screens/feed_new_post_screen.dart` — `_FeedNewPostScreenState._initVideo` (± :142) dan `_FeedPostPreviewScreenState._initVideo` (± :1462)

**Interfaces:**
- Consumes (Task 4/5): `draft.trimStart`, `draft.finalDuration`.
- Produces: preview di "Post Baru" dan layar "Preview" memutar HANYA rentang terpilih (seek ke `trimStart`, loop kembali ke `trimStart` saat melewati `trimStart + finalDuration`) — user tidak melihat bagian video yang dia buang.

- [ ] **Step 1: Helper guard rentang**

Tambah di `feed_new_post_screen.dart` (top-level, bawah konstanta):

```dart
/// Loop playback dalam rentang trim draft (Approach B: file belum
/// terpotong secara fisik sampai upload). Return timer guard — cancel
/// di dispose. Tanpa trimStart → biarkan looping bawaan controller.
Timer? startTrimLoopGuard(
  VideoPlayerController controller,
  FeedCreatePostDraft? draft,
) {
  final start = draft?.trimStart;
  final span = draft?.finalDuration;
  if (start == null || span == null) return null;
  final end = start + span;
  controller.seekTo(start);
  return Timer.periodic(const Duration(milliseconds: 200), (_) {
    if (!controller.value.isInitialized || !controller.value.isPlaying) return;
    if (controller.value.position >= end) controller.seekTo(start);
  });
}
```

(import `dart:async` sudah perlu — tambah bila belum ada.)

- [ ] **Step 2: Pasang di kedua controller**

- `_FeedNewPostScreenState`: field `Timer? _trimGuard;` — setelah init sukses: `_trimGuard = startTrimLoopGuard(controller, _videoDraft);`; `dispose`: `_trimGuard?.cancel();`.
- `_FeedPostPreviewScreenState`: sama, dengan `widget.videoDraft`.

- [ ] **Step 3: Analyze + seluruh test + commit**

```bash
cd flutter_app && flutter analyze && flutter test
git add flutter_app/lib/screens/feed_new_post_screen.dart
git commit -m "feat(feed): preview memutar hanya rentang trim terpilih (guard loop trimStart..end)"
```

---

### Task 7: Pre-flight check format media

**Files:**
- Modify: `flutter_app/lib/screens/feed_video_upload_flow.dart` — `_FeedVideoStartScreenState._pick` (± :53-146) dan `_readVideoDuration` (helper file yang sama)

**Interfaces:**
- Consumes: tidak ada.
- Produces: pesan error spesifik saat format tidak didukung, SEBELUM user lanjut ke langkah berikutnya.

- [ ] **Step 1: Bedakan gagal-init vs error lain**

`_readVideoDuration` saat ini meng-init `VideoPlayerController` untuk membaca durasi. Ubah supaya kegagalan init dilempar sebagai exception spesifik:

```dart
class _UnsupportedVideoException implements Exception {
  const _UnsupportedVideoException();
}
```

Di `_readVideoDuration`: bungkus `controller.initialize()` dengan try/catch → `throw const _UnsupportedVideoException();` (pastikan controller di-dispose di finally). Durasi hasil init `<= Duration.zero` juga dianggap `_UnsupportedVideoException`.

Di `_pick` catch (± :135-145): tambah cabang sebelum fallback generik:

```dart
        _error = error is _FeedVideoFlowException
            ? error.message
            : error is _UnsupportedVideoException
                ? 'Format video ini belum didukung. Coba video lain atau '
                  'rekam ulang dengan kamera.'
                : 'Video tidak bisa dibuka. Pilih video lain.';
```

- [ ] **Step 2: Analyze + seluruh test + commit**

```bash
cd flutter_app && flutter analyze && flutter test
git add flutter_app/lib/screens/feed_video_upload_flow.dart
git commit -m "feat(feed): pre-flight check — pesan spesifik format video tidak didukung saat pick"
```

---

### Task 8: Telemetri funnel posting

**Files:**
- Modify: `flutter_app/lib/screens/feed_video_upload_flow.dart` (`FeedVideoStartScreen`, `FeedVideoTrimScreen`)
- Modify: `flutter_app/lib/screens/feed_media_picker_screen.dart`
- Modify: `flutter_app/lib/screens/feed_new_post_screen.dart` (`FeedNewPostScreen`, `FeedPostPreviewScreen`)
- Modify: `flutter_app/lib/state/feed_upload_store.dart`

**Interfaces:**
- Consumes: `AppAnalytics.logEvent(String name, [Map<String, Object>? params])` — import `../services/app_analytics.dart`. Fire-and-forget: JANGAN di-await di jalur UI, bungkus `unawaited(...)`.
- Produces: event funnel (nama & param PERSIS ini, dipakai dashboard):

| Event | Titik pasang | Params |
|---|---|---|
| `feed_post_pick_opened` | `initState` FeedVideoStartScreen + FeedMediaPickerScreen | `{'source': 'video_start' \| 'media_picker'}` |
| `feed_post_media_selected` | `_pick` sukses (video); konfirmasi picker foto | `{'type': 'video' \| 'photo' \| 'carousel', 'count': n}` |
| `feed_post_edit_opened` | `initState` FeedVideoTrimScreen | — |
| `feed_post_share_opened` | `initState` FeedNewPostScreen | `{'type': ...}` |
| `feed_post_preview_opened` | `initState` FeedPostPreviewScreen | `{'type': ...}` |
| `feed_post_submitted` | `_upload` FeedNewPostScreen tepat sebelum `_goHome()` (kedua cabang) | `{'type': ..., 'product_count': n}` |
| `feed_post_upload_success` | store: sebelum `_scheduleAutoDismiss()` sukses (video & foto) | `{'type': ...}` |
| `feed_post_upload_failed` | store: kedua blok catch | `{'type': ..., 'reason': errorString maks 90 char}` |

- [ ] **Step 1: Pasang semua event**

Contoh pola (ulangi per titik tabel):

```dart
    unawaited(AppAnalytics.logEvent('feed_post_submitted', {
      'type': _isVideo ? 'video' : (files.length > 1 ? 'carousel' : 'photo'),
      'product_count': productIds.length,
    }));
```

Untuk `reason` di store: `error.toString()` dipotong `substring(0, math.min(90, s.length))`.

- [ ] **Step 2: Analyze + seluruh test + commit**

```bash
cd flutter_app && flutter analyze && flutter test
git add flutter_app/lib/screens/feed_video_upload_flow.dart flutter_app/lib/screens/feed_media_picker_screen.dart flutter_app/lib/screens/feed_new_post_screen.dart flutter_app/lib/state/feed_upload_store.dart
git commit -m "feat(feed): telemetri funnel posting — 8 event AppAnalytics dari pick sampai upload"
```

---

### Task 9: Regression penuh + checklist device-verify 2A

**Files:** tidak ada perubahan kode — verifikasi.

- [ ] **Step 1: Full suite**

```bash
cd flutter_app && flutter analyze && flutter test
# Expected: analyze hanya lint pre-existing; semua test pass
```

- [ ] **Step 2: Checklist device-verify 2A (laporkan ke user, JANGAN klaim terverifikasi)**

1. Feed publik tampil & berperilaku IDENTIK dengan sebelum refactor (rail, like/double-tap, follow chip, caption expand, kartu produk, add-to-cart, scrim, scrubber).
2. Video >60s → Edit Video → Next INSTAN (tanpa layar tunggu) → Bagikan → upload sukses; hasil post terpotong sesuai rentang.
3. Preview di Post Baru & layar Preview hanya memutar rentang terpilih.
4. Pilih file non-video/HDR aneh → pesan "Format video ini belum didukung..." muncul di layar pilih.
5. Firebase DebugView menampilkan urutan event funnel saat satu kali posting.

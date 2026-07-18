# Comment Drawer — Remove Pull-to-Refresh, Faster Auto-Poll — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Buang pull-to-refresh dari daftar komentar (Feed + modal Postingan), ganti retry state-error dengan tombol "Coba lagi", dan percepat auto-poll komentar 10s→5s.

**Architecture:** `FeedCommentSheet` di-share semua surface; menghapus pembungkus `NataloPawRefreshIndicator` di `_buildListBody` menghilangkan pull-to-refresh di mana-mana sekaligus. State error memakai widget kecil publik `CommentErrorRetryView` (pesan + tombol "Coba lagi") supaya bisa diuji langsung. Kesegaran datang dari `FeedCommentSyncCoordinator` yang sudah ada; hanya `interval` default yang diturunkan ke 5 detik.

**Tech Stack:** Flutter, Dart, `flutter_test`.

## Global Constraints

- JANGAN ubah visual/warna/tinggi sheet, composer, atau reaction bar.
- JANGAN sentuh Feed video/foto utama (hanya daftar komentar).
- JANGAN ubah logika pull-to-dismiss / terminal-state reliability yang sudah ada.
- `_refresh` TETAP ada (dipakai tombol "Coba lagi" + auto-poll) — jangan dihapus.
- Warna spinner/aksen yang sudah dipakai: `NataloColors.primary`.
- Setiap task diakhiri `flutter analyze` bersih pada file yang disentuh dan test hijau, lalu commit.
- Bekerja di worktree branch `claude/comment-remove-pull-refresh`.

---

### Task 1: Percepat auto-poll komentar 10s → 5s

**Files:**
- Modify: `flutter_app/lib/state/feed_comment_sync_coordinator.dart:30`
- Test: `flutter_app/test/state/feed_comment_sync_coordinator_test.dart`

**Interfaces:**
- Consumes: `FeedCommentSyncCoordinator({Duration interval})` konstruktor yang sudah ada; field publik `final Duration interval`.
- Produces: default `interval` == `Duration(seconds: 5)`.

- [ ] **Step 1: Tulis test yang gagal**

Tambahkan di dalam `void main() { ... }` pada `test/state/feed_comment_sync_coordinator_test.dart`:

```dart
  test('default revalidation interval is 5 seconds', () {
    final coordinator = FeedCommentSyncCoordinator();
    addTearDown(coordinator.clear);
    expect(coordinator.interval, const Duration(seconds: 5));
  });
```

- [ ] **Step 2: Jalankan test, pastikan GAGAL**

Run: `cd flutter_app && flutter test test/state/feed_comment_sync_coordinator_test.dart --plain-name "default revalidation interval is 5 seconds"`
Expected: FAIL — `Expected: Duration:<0:00:05.000000>  Actual: Duration:<0:00:10.000000>`

- [ ] **Step 3: Ubah default interval**

Di `lib/state/feed_comment_sync_coordinator.dart`, ubah konstruktor (baris ~29-31):

```dart
  FeedCommentSyncCoordinator({
    this.interval = const Duration(seconds: 5),
  });
```

Perbarui juga komentar dokumen kelas jika menyebut "10 detik" (baris ~22 "near-realtime comment revalidation") — tidak wajib jika tidak menyebut angka; jika ada angka "10", ganti ke "5".

- [ ] **Step 4: Jalankan test, pastikan LULUS**

Run: `cd flutter_app && flutter test test/state/feed_comment_sync_coordinator_test.dart`
Expected: PASS (semua test file ini, termasuk yang baru)

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/state/feed_comment_sync_coordinator.dart flutter_app/test/state/feed_comment_sync_coordinator_test.dart
git commit -m "feat(feed): percepat auto-poll komentar 10s->5s"
```

---

### Task 2: Buang pull-to-refresh dari daftar komentar (state populated)

**Files:**
- Modify: `flutter_app/lib/widgets/feed_comment_sheet.dart:2178-2244` (state populated di `_buildListBody`)
- Test: `flutter_app/test/widgets/feed_comment_sheet_modal_test.dart`

**Interfaces:**
- Consumes: `FeedCommentSheet(post:, sessionStore:)`; `FeedCommentSessionStore.sessionFor(viewerId:, postId:).replaceComments(List<FeedComment>, String?)`.
- Produces: subtree daftar komentar populated TIDAK lagi mengandung `RefreshProgressIndicator` / `RefreshIndicator`.

- [ ] **Step 1: Tulis test yang gagal**

Tambahkan di `void main()` pada `test/widgets/feed_comment_sheet_modal_test.dart` (memakai helper `_post()` dan `_comment()` yang sudah ada di file itu):

```dart
  testWidgets('daftar komentar populated tidak punya pull-to-refresh',
      (tester) async {
    final sessions = FeedCommentSessionStore();
    sessions
        .sessionFor(viewerId: 'guest', postId: _post().id)
        .replaceComments([_comment(likeCount: 1, viewerLiked: false)], null);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeedCommentSheet(post: _post(), sessionStore: sessions),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(RefreshIndicator), findsNothing,
        reason: 'tarik-bawah di puncak = tutup, bukan refresh');
    expect(find.byType(RefreshProgressIndicator), findsNothing);
  });
```

- [ ] **Step 2: Jalankan test, pastikan GAGAL**

Run: `cd flutter_app && flutter test test/widgets/feed_comment_sheet_modal_test.dart --plain-name "daftar komentar populated tidak punya pull-to-refresh"`
Expected: FAIL — `Expected: no matching candidates  Actual: Found 1 widget with type "RefreshIndicator"` (NataloPawRefreshIndicator memakai RefreshIndicator di dalamnya).

Catatan: jika `NataloPawRefreshIndicator` TIDAK memakai `RefreshIndicator` bawaan, ganti assertion ke `find.byType(NataloPawRefreshIndicator)` dan import widget-nya. Verifikasi dulu dengan:
`grep -n "class NataloPawRefreshIndicator" flutter_app/lib -r`

- [ ] **Step 3: Lepaskan pembungkus refresh (populated)**

Di `lib/widgets/feed_comment_sheet.dart`, state populated saat ini (baris ~2178):

```dart
    return NataloPawRefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        controller: _listController,
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: totalCount,
        itemBuilder: (context, index) {
          // ... (tidak berubah)
        },
      ),
    );
```

Ubah menjadi (hapus pembungkus + satu tingkat kurung penutup):

```dart
    return ListView.builder(
      controller: _listController,
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: totalCount,
      itemBuilder: (context, index) {
        // ... (isi itemBuilder tidak berubah)
      },
    );
```

Jangan sentuh isi `itemBuilder`. Hanya buang `NataloPawRefreshIndicator(onRefresh: _refresh, child: ...)` dan sesuaikan indentasi + kurung penutup `);`.

- [ ] **Step 4: Jalankan test + analyze, pastikan LULUS & bersih**

Run: `cd flutter_app && flutter test test/widgets/feed_comment_sheet_modal_test.dart && flutter analyze lib/widgets/feed_comment_sheet.dart`
Expected: semua test PASS; analyze `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/widgets/feed_comment_sheet.dart flutter_app/test/widgets/feed_comment_sheet_modal_test.dart
git commit -m "feat(feed): buang pull-to-refresh dari daftar komentar populated"
```

---

### Task 3: State error pakai `CommentErrorRetryView` (tombol "Coba lagi", tanpa refresh)

**Files:**
- Modify: `flutter_app/lib/widgets/feed_comment_sheet.dart:2081-2110` (cabang error di `_buildListBody`) + tambah kelas `CommentErrorRetryView` di file yang sama (dekat helper widget lain, mis. setelah `CommentSheetScrollAnchor`).
- Test: `flutter_app/test/widgets/comment_error_retry_view_test.dart` (baru)

**Interfaces:**
- Consumes: `_error` (String), `_listController` (ScrollController), `_refresh` (`Future<void> Function()`), `NataloColors.primary`.
- Produces: `class CommentErrorRetryView extends StatelessWidget` dengan konstruktor `const CommentErrorRetryView({super.key, required String message, required VoidCallback onRetry, ScrollController? scrollController})` yang menampilkan ikon wifi-off, `message`, dan tombol "Coba lagi" (memanggil `onRetry`). TIDAK memakai `RefreshIndicator`.

- [ ] **Step 1: Tulis test yang gagal**

Buat file `flutter_app/test/widgets/comment_error_retry_view_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/widgets/feed_comment_sheet.dart';

void main() {
  testWidgets('menampilkan pesan + tombol Coba lagi tanpa pull-to-refresh',
      (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommentErrorRetryView(
            message: 'Gagal memuat komentar.',
            onRetry: () => retries++,
          ),
        ),
      ),
    );

    expect(find.text('Gagal memuat komentar.'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Coba lagi'), findsOneWidget);
    expect(find.byType(RefreshIndicator), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, 'Coba lagi'));
    await tester.pump();
    expect(retries, 1);
  });
}
```

- [ ] **Step 2: Jalankan test, pastikan GAGAL**

Run: `cd flutter_app && flutter test test/widgets/comment_error_retry_view_test.dart`
Expected: FAIL — kompilasi gagal, `CommentErrorRetryView` belum didefinisikan.

- [ ] **Step 3: Tambah widget `CommentErrorRetryView`**

Di `lib/widgets/feed_comment_sheet.dart`, tambahkan kelas ini (letakkan tepat setelah kelas `CommentSheetScrollAnchor`):

```dart
/// Tampilan error daftar komentar: pesan + tombol "Coba lagi".
///
/// Menggantikan pull-to-refresh di state error supaya gesture tarik-bawah
/// tetap konsisten = tutup sheet, sementara retry tetap tersedia lewat tombol.
class CommentErrorRetryView extends StatelessWidget {
  const CommentErrorRetryView({
    super.key,
    required this.message,
    required this.onRetry,
    this.scrollController,
  });

  final String message;
  final VoidCallback onRetry;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 32),
      children: [
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.wifi_off_rounded,
                color: Colors.white.withValues(alpha: 0.35),
                size: 40,
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  foregroundColor: NataloColors.primary,
                ),
                child: const Text('Coba lagi'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Pakai widget di cabang error `_buildListBody`**

Ganti blok error (baris ~2081-2110) yang saat ini:

```dart
    if (_error != null && _comments.isEmpty) {
      return NataloPawRefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          controller: _listController,
          padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 32),
          children: [
            Center(
              child: Column(
                children: [
                  Icon(Icons.wifi_off_rounded, /* ... */),
                  const SizedBox(height: 10),
                  Text(_error!, /* ... */),
                ],
              ),
            ),
          ],
        ),
      );
    }
```

menjadi:

```dart
    if (_error != null && _comments.isEmpty) {
      return CommentErrorRetryView(
        message: _error!,
        onRetry: () => unawaited(_refresh()),
        scrollController: _listController,
      );
    }
```

Pastikan `unawaited` sudah diimpor (dari `dart:async`) — cek bagian atas file; `dart:async` sudah diimpor di file ini (dipakai `_activeFeedCommentDrawerFlight`). Jika belum, tambahkan `import 'dart:async';`.

- [ ] **Step 5: Jalankan test + analyze**

Run: `cd flutter_app && flutter test test/widgets/comment_error_retry_view_test.dart && flutter analyze lib/widgets/feed_comment_sheet.dart`
Expected: PASS; analyze `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add flutter_app/lib/widgets/feed_comment_sheet.dart flutter_app/test/widgets/comment_error_retry_view_test.dart
git commit -m "feat(feed): state error komentar pakai tombol Coba lagi (tanpa pull-refresh)"
```

---

### Task 4: Regresi penuh + analyze bersih

**Files:**
- Test: seluruh suite comment drawer + video adapter.

- [ ] **Step 1: Jalankan suite terkait**

Run:
```bash
cd flutter_app && flutter test \
  test/state/feed_comment_sync_coordinator_test.dart \
  test/widgets/feed_comment_sheet_modal_test.dart \
  test/widgets/comment_error_retry_view_test.dart \
  test/widgets/comment_sheet_scroll_anchor_test.dart \
  test/feed_comment_sheet_drag_test.dart \
  test/screens/feed_photo_comment_drawer_test.dart \
  test/widgets/feed_comment_media_frame_test.dart \
  test/features/feed/widgets/feed_video_post_view_test.dart
```
Expected: `All tests passed!`

- [ ] **Step 2: Analyze file yang disentuh**

Run: `cd flutter_app && flutter analyze lib/widgets/feed_comment_sheet.dart lib/state/feed_comment_sync_coordinator.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit (jika ada perubahan penyesuaian)**

Jika Step 1/2 memaksa penyesuaian kecil, commit; jika tidak, lewati.

```bash
git commit -am "test(feed): verifikasi regresi drawer komentar pasca-hapus pull-refresh"
```

---

## Catatan verifikasi manual (device — di luar test)

Test tidak menjamin rasa gesture. Setelah build TestFlight: pastikan (1) tarik-bawah daftar komentar di puncak = tutup, tanpa spinner refresh, di Feed & Postingan; (2) komentar orang lain masuk ≤~5 detik saat sheet terbuka; (3) state error menampilkan "Coba lagi" yang berfungsi.

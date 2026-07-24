# Spec D — Tandai Orang di Halaman Edit Postingan Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** User bisa menambah/menghapus orang yang ditandai pada post yang SUDAH dipublish (foto: titik interaktif; video: daftar sederhana), plus badge "Ditandai" video disembunyikan di feed utama (paritas IG).

**Architecture:** Backend menambah dukungan `taggedUsers` di `PATCH /api/feed/posts/[id]` dengan reuse `parseTaggedUsersInput` + replace-total `FeedTaggedUser` dalam transaction (pola sama dengan `productIds`/`resyncPostHashtags`). Flutter menambah baris "Orang ditandai" di `MemberPostEditScreen` yang bercabang: foto → `FeedTagPeopleScreen` (direfactor dari `List<File>` ke `List<ImageProvider>` supaya bisa render foto network), video → `FeedTagPeopleVideoScreen` apa adanya. Badge video dikontrol flag `showTaggedBadge` baru.

**Tech Stack:** Next.js App Router + Prisma (backend), Flutter (app), node:test via tsx (backend test), flutter_test (app test).

## Global Constraints

- Maksimal 20 orang per post: `MAX_TAGGED_USERS_PER_POST` dari `lib/feed/tagged-users.ts` — JANGAN re-implementasi limit; enforcement lewat `parseTaggedUsersInput`.
- Satu orang satu tag per post: `@@unique([feedPostId, taggedUserId])` — dedupe sudah di `parseTaggedUsersInput` (tag pertama menang).
- Kontrak body PATCH: `taggedUsers` array `{userId, mediaIndex?, x?, y?}`; foto WAJIB `mediaIndex` valid (0..mediaCount-1) + `x`/`y` fraksi 0-1; video semua koordinat diabaikan (null). `taggedUsers` tidak dikirim (undefined) = tagged users existing TIDAK disentuh; `[]` = hapus semua.
- Full replace, bukan diff: `deleteMany` lalu `createMany` dalam `$transaction` yang sama dengan update field lain.
- Label baris UI: `'Orang ditandai'` (sejajar `'Produk ditandai'` yang sudah ada, layout identik).
- Badge video: `showTaggedBadge` default `true`; `feed_screen.dart` set `false`; `scoped_video_feed_screen.dart` biarkan default.
- `mediaIndex` di response API dipetakan dari `FeedTaggedUser.mediaId` (lihat `serializeTaggedUsers`); saat MENYIMPAN dari PATCH, `mediaIndex` input harus dikonversi ke `mediaId` via urutan `media` post (`orderBy: { sortOrder: "asc" }`).
- Haptic: tiap tap interaktif baru pakai `AppHaptics.tap()` (konvensi proyek).
- Semua copy bahasa Indonesia.

---

### Task 1: Backend — PATCH /api/feed/posts/[id] terima `taggedUsers`

**Files:**
- Modify: `app/api/feed/posts/[id]/route.ts` (handler PATCH, mulai ±baris 328)
- Test: `tests/feed-tagged-users-patch.test.ts` (create)

**Interfaces:**
- Consumes: `parseTaggedUsersInput(raw, {mediaCount, isVideo})` dari `lib/feed/tagged-users.ts` (sudah ada, JANGAN diubah).
- Produces: PATCH menerima `body.taggedUsers?: Array<{userId: string; mediaIndex?: number; x?: number; y?: number}>`; validasi gagal → 400 `{error}`; sukses → replace total baris `FeedTaggedUser` post itu.

- [ ] **Step 1: Tulis failing test** — logika konversi input→rows di-extract jadi pure helper supaya bisa diuji tanpa HTTP harness (pola sama dengan `resyncPostHashtags` di Spec C). Tambahkan helper di `lib/feed/tagged-users.ts`:

```ts
/**
 * Konversi hasil parseTaggedUsersInput jadi data createMany FeedPostTaggedUser
 * utk jalur EDIT (PATCH). mediaIndex input dipetakan ke mediaId nyata via
 * orderedMediaIds (urutan sortOrder asc). Video: mediaId/x/y null semua.
 */
export function buildTaggedUserRows(
  tags: TaggedUserInput[],
  feedPostId: string,
  orderedMediaIds: readonly string[],
): Array<{
  feedPostId: string;
  taggedUserId: string;
  mediaId: string | null;
  x: number | null;
  y: number | null;
}> {
  return tags.map((tag) => ({
    feedPostId,
    taggedUserId: tag.userId,
    mediaId: tag.mediaIndex != null ? orderedMediaIds[tag.mediaIndex] ?? null : null,
    x: tag.x,
    y: tag.y,
  }));
}
```

Test file `tests/feed-tagged-users-patch.test.ts`:

```ts
import test from "node:test";
import assert from "node:assert/strict";
import {
  parseTaggedUsersInput,
  buildTaggedUserRows,
  MAX_TAGGED_USERS_PER_POST,
} from "../lib/feed/tagged-users";

test("buildTaggedUserRows: foto — mediaIndex dipetakan ke mediaId sesuai urutan", () => {
  const parsed = parseTaggedUsersInput(
    [
      { userId: "u1", mediaIndex: 0, x: 0.5, y: 0.5 },
      { userId: "u2", mediaIndex: 1, x: 0.2, y: 0.8 },
    ],
    { mediaCount: 2, isVideo: false },
  );
  assert.ok(parsed.ok);
  const rows = buildTaggedUserRows(parsed.tags, "post1", ["mA", "mB"]);
  assert.deepEqual(rows, [
    { feedPostId: "post1", taggedUserId: "u1", mediaId: "mA", x: 0.5, y: 0.5 },
    { feedPostId: "post1", taggedUserId: "u2", mediaId: "mB", x: 0.2, y: 0.8 },
  ]);
});

test("buildTaggedUserRows: video — mediaId/x/y null semua", () => {
  const parsed = parseTaggedUsersInput(
    [{ userId: "u1" }, { userId: "u2", mediaIndex: 3, x: 0.4, y: 0.4 }],
    { mediaCount: 0, isVideo: true },
  );
  assert.ok(parsed.ok);
  const rows = buildTaggedUserRows(parsed.tags, "post1", []);
  assert.deepEqual(rows, [
    { feedPostId: "post1", taggedUserId: "u1", mediaId: null, x: null, y: null },
    { feedPostId: "post1", taggedUserId: "u2", mediaId: null, x: null, y: null },
  ]);
});

test("parseTaggedUsersInput: >20 orang ditolak (jalur edit pakai parser sama)", () => {
  const raw = Array.from({ length: MAX_TAGGED_USERS_PER_POST + 1 }, (_, i) => ({
    userId: `u${i}`,
  }));
  const parsed = parseTaggedUsersInput(raw, { mediaCount: 0, isVideo: true });
  assert.equal(parsed.ok, false);
});

test("parseTaggedUsersInput: foto tanpa koordinat ditolak", () => {
  const parsed = parseTaggedUsersInput([{ userId: "u1" }], {
    mediaCount: 2,
    isVideo: false,
  });
  assert.equal(parsed.ok, false);
});
```

- [ ] **Step 2: Run test, verify FAIL** — `npx tsx --test tests/feed-tagged-users-patch.test.ts` → FAIL: `buildTaggedUserRows` is not exported.

- [ ] **Step 3: Implement** — (a) tambahkan `buildTaggedUserRows` di `lib/feed/tagged-users.ts` persis seperti Step 1. (b) Di `app/api/feed/posts/[id]/route.ts` handler PATCH:

1. Di `select` query `post` (±baris 365-374), ubah `media: { select: { id: true } }` jadi `media: { orderBy: { sortOrder: "asc" }, select: { id: true } }` (urutan WAJIB deterministik untuk mediaIndex→mediaId).
2. Tambah `taggedUsers?: unknown;` ke type cast `body` (±baris 398).
3. Setelah blok validasi `productIds` (±sesudah baris 587), tambah:

```ts
// Spec D: edit tagged users — full replace, validasi reuse parser create.
// isVideo: customer kind COMMUNITY = video, PHOTO_CAROUSEL = foto; admin
// post video juga bukan PHOTO_CAROUSEL. Konsisten dgn create routes.
let newTaggedUserRows:
  | ReturnType<typeof buildTaggedUserRows>
  | null = null;
if (typeof body.taggedUsers !== "undefined") {
  const parsedTags = parseTaggedUsersInput(body.taggedUsers, {
    mediaCount: post.media.length,
    isVideo: post.kind !== "PHOTO_CAROUSEL",
  });
  if (!parsedTags.ok) {
    return NextResponse.json({ error: parsedTags.error }, { status: 400 });
  }
  newTaggedUserRows = buildTaggedUserRows(
    parsedTags.tags,
    post.id,
    post.media.map((m) => m.id),
  );
}
```

4. Import `parseTaggedUsersInput, buildTaggedUserRows` dari `@/lib/feed/tagged-users` (file sudah meng-import `serializeTaggedUsers` dkk — tambah ke import yang sama).
5. Di dalam `prisma.$transaction` yang sudah ada (±baris 630), setelah blok `resyncPostHashtags`, tambah:

```ts
if (newTaggedUserRows !== null) {
  await tx.feedTaggedUser.deleteMany({ where: { feedPostId: post.id } });
  if (newTaggedUserRows.length > 0) {
    await tx.feedTaggedUser.createMany({ data: newTaggedUserRows });
  }
}
```

- [ ] **Step 4: Run test, verify PASS** — `npx tsx --test tests/feed-tagged-users-patch.test.ts` → 4 pass. Lalu `npx tsc --noEmit` → tidak ada error BARU (pre-existing vitest/photoUrl errors boleh).

- [ ] **Step 5: Commit** — `git add lib/feed/tagged-users.ts app/api/feed/posts/[id]/route.ts tests/feed-tagged-users-patch.test.ts && git commit -m "feat(api): PATCH post terima taggedUsers — edit tandai orang (Spec D)"`

---

### Task 2: Flutter — FeedService.updateMyPost kirim taggedUsers

**Files:**
- Modify: `flutter_app/lib/services/feed_service.dart:545-564` (`updateMyPost`)
- Test: `flutter_app/test/services/feed_service_update_tagged_test.dart` (create)

**Interfaces:**
- Consumes: `NewPostUserTag` (`flutter_app/lib/models/new_post_user_tag.dart`) — fields `userId`, `mediaIndex`, `x`, `y`.
- Produces: `updateMyPost(postId, {required title, description, productIds, List<NewPostUserTag>? taggedUsers})`. `taggedUsers == null` → key tidak dikirim; `[]` → kirim `[]`.

- [ ] **Step 1: Failing test** — `flutter_app/test/services/feed_service_update_tagged_test.dart`. Pola test service di repo ini: uji serialisasi body murni. Tambahkan static helper yang bisa diuji:

```dart
// Di FeedService (feed_service.dart), method statik:
static List<Map<String, dynamic>> taggedUsersToJson(List<NewPostUserTag> tags) {
  return tags
      .map((t) => <String, dynamic>{
            'userId': t.userId,
            if (t.mediaIndex != null) 'mediaIndex': t.mediaIndex,
            if (t.x != null) 'x': t.x,
            if (t.y != null) 'y': t.y,
          })
      .toList();
}
```

Test:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_app/models/new_post_user_tag.dart';
import 'package:natalo_app/services/feed_service.dart';

void main() {
  test('taggedUsersToJson: foto bawa mediaIndex/x/y, video polos', () {
    final json = FeedService.taggedUsersToJson(const [
      NewPostUserTag(
          userId: 'u1', username: 'a', mediaIndex: 0, x: 0.5, y: 0.25),
      NewPostUserTag(userId: 'u2', username: 'b'),
    ]);
    expect(json, [
      {'userId': 'u1', 'mediaIndex': 0, 'x': 0.5, 'y': 0.25},
      {'userId': 'u2'},
    ]);
  });
}
```

(Cek nama package import di test lain yang sudah ada — samakan prefiksnya.)

- [ ] **Step 2: Run, verify FAIL** — `flutter test test/services/feed_service_update_tagged_test.dart` (dari `flutter_app/`) → FAIL: method tidak ada.

- [ ] **Step 3: Implement** — tambah helper statik di atas ke `FeedService`, lalu ubah `updateMyPost`:

```dart
Future<bool> updateMyPost(
  String postId, {
  required String title,
  String? description,
  List<String>? productIds,
  List<NewPostUserTag>? taggedUsers,
}) async {
  final data = await apiClient.patchJson(
    '/api/feed/posts/$postId',
    body: {
      'title': title,
      'description': description,
      if (productIds != null) 'productIds': productIds,
      if (taggedUsers != null) 'taggedUsers': taggedUsersToJson(taggedUsers),
    },
    timeout: const Duration(seconds: 15),
  );
  if (data is Map<String, dynamic>) {
    return data['ok'] == true;
  }
  return true;
}
```

Tambah import `../models/new_post_user_tag.dart` di `feed_service.dart` kalau belum ada.

- [ ] **Step 4: Run, verify PASS** — test hijau; `flutter analyze lib/services/feed_service.dart` tidak menambah issue baru.

- [ ] **Step 5: Commit** — `git add flutter_app/lib/services/feed_service.dart flutter_app/test/services/feed_service_update_tagged_test.dart && git commit -m "feat(app): updateMyPost kirim taggedUsers (Spec D)"`

---

### Task 3: Flutter — refactor FeedTagPeopleScreen ke ImageProvider

**Files:**
- Modify: `flutter_app/lib/screens/feed_post/feed_tag_people_screen.dart` (param `photoFiles` → `photoImages`)
- Modify: call site create di `flutter_app/lib/screens/feed_new_post_screen.dart` (cari `FeedTagPeopleScreen(` — bungkus tiap `File` dengan `FileImage`)
- Test: file test existing yang menyentuh screen ini (`flutter_app/test/feed_tag_people_screen_test.dart`) — update konstruksi

**Interfaces:**
- Produces: `FeedTagPeopleScreen({required List<ImageProvider> photoImages, List<NewPostUserTag> initialTags, TagUserSearchFn searchUsers})`. Perilaku titik/geser/hapus TIDAK berubah.

- [ ] **Step 1: Update test dulu (failing)** — di `feed_tag_people_screen_test.dart`, ganti semua konstruksi `photoFiles: [file...]` jadi `photoImages: [FileImage(file)...]` (atau `MemoryImage(bytes)` kalau test pakai bytes sintetis — `MemoryImage` lebih stabil di widget test, tidak sentuh disk). Run → FAIL compile (param belum ada).

- [ ] **Step 2: Implement refactor** — di `feed_tag_people_screen.dart`:

1. `final List<File> photoFiles;` → `final List<ImageProvider> photoImages;` (hapus import `dart:io` kalau jadi tak terpakai).
2. Render (±baris 474): `Image.file(widget.photoFiles[index], ...)` → `Image(image: widget.photoImages[index], ...)` — properti `fit`/lainnya dipertahankan persis.
3. Loader aspect-ratio (±baris 122, `readAsBytes` + `ui.instantiateImageCodec`): ganti jadi resolusi via ImageStream — pola standar:

```dart
Future<void> _loadAspectRatio(int i) async {
  final completer = Completer<ui.Image>();
  final stream = widget.photoImages[i].resolve(const ImageConfiguration());
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      if (!completer.isCompleted) completer.complete(info.image);
      stream.removeListener(listener);
    },
    onError: (error, stack) {
      if (!completer.isCompleted) completer.completeError(error, stack);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  try {
    final image = await completer.future;
    if (!mounted) return;
    setState(() => _aspectRatios[i] = image.width / image.height);
  } catch (_) {
    // Fallback: entry absen → pakai aspect container (perilaku existing).
  }
}
```

(Sesuaikan nama map/field aspect-ratio dengan yang sudah ada di file — baca dulu blok komentar ±baris 102-110; JANGAN ubah mekanisme fallback-nya.)
4. Call site di `feed_new_post_screen.dart`: `photoFiles: _photos` (atau nama var aslinya) → `photoImages: _photos.map<ImageProvider>((f) => FileImage(f)).toList()`.

- [ ] **Step 3: Run test, verify PASS** — `flutter test test/feed_tag_people_screen_test.dart` hijau; `flutter analyze` tidak menambah issue baru.

- [ ] **Step 4: Commit** — `git add -A flutter_app/lib/screens/feed_post/feed_tag_people_screen.dart flutter_app/lib/screens/feed_new_post_screen.dart flutter_app/test/feed_tag_people_screen_test.dart && git commit -m "refactor(app): FeedTagPeopleScreen terima ImageProvider (persiapan edit, Spec D)"`

---

### Task 4: Flutter — baris "Orang ditandai" di MemberPostEditScreen

**Files:**
- Modify: `flutter_app/lib/screens/member_post_edit_screen.dart`
- Test: `flutter_app/test/screens/member_post_edit_tagged_row_test.dart` (create)

**Interfaces:**
- Consumes: `FeedTagPeopleScreen(photoImages:, initialTags:)` (Task 3), `FeedTagPeopleVideoScreen(initialTags:)`, `FeedService.updateMyPost(..., taggedUsers:)` (Task 2), `FeedPost.taggedUsers` (`List<FeedTaggedUser>`), `FeedPost.mediaItems` (`List<FeedMedia>`, punya `mediaUrl`), `FeedPost.isVideo`.
- Produces: state `List<NewPostUserTag> _taggedUsers` di `_MemberPostEditScreenState`; dikirim ke `updateMyPost` HANYA kalau user membuka & menutup layar tag (dirty flag `_taggedUsersEdited`) supaya PATCH tanpa perubahan tag tidak menyentuh baris DB.

- [ ] **Step 1: Failing widget test** — `member_post_edit_tagged_row_test.dart`:

```dart
// Uji: (1) baris 'Orang ditandai' muncul; (2) subtitle 'N dipilih' sesuai
// jumlah taggedUsers post; (3) post kosong → 'Tambah'.
// Bangun FeedPost fixture minimal (ikuti pola fixture di
// test/screens/member_posts_screen_test.dart — copy pola pump + mock prefs
// dari sana, termasuk guard shimmer bounded pump-loop kalau perlu).
testWidgets('baris Orang ditandai tampil dengan count', (tester) async {
  final post = FeedPost(/* fixture: 2 taggedUsers, kind PHOTO_CAROUSEL */);
  await tester.pumpWidget(MaterialApp(home: MemberPostEditScreen(post: post)));
  await tester.pump();
  expect(find.text('Orang ditandai'), findsOneWidget);
  expect(find.text('2 dipilih'), findsOneWidget);
});
```

(Isi fixture `FeedPost` dengan constructor asli — lihat field wajib di `models/feed_post.dart` ±baris 355; test file existing `member_posts_screen_test.dart` sudah punya contoh fixture yang bisa disalin.)

- [ ] **Step 2: Run, verify FAIL** — baris belum ada.

- [ ] **Step 3: Implement** — di `member_post_edit_screen.dart`:

1. State baru di `_MemberPostEditScreenState`:

```dart
late List<NewPostUserTag> _taggedUsers = widget.post.taggedUsers
    .map((t) => NewPostUserTag(
          userId: t.userId,
          username: t.username ?? '',
          name: t.name,
          profilePhotoUrl: t.profilePhotoUrl,
          mediaIndex: t.mediaIndex,
          x: t.x,
          y: t.y,
        ))
    .toList();
bool _taggedUsersEdited = false;
```

2. Handler buka layar tag:

```dart
Future<void> _openTagPeople() async {
  AppHaptics.tap();
  final List<NewPostUserTag>? result;
  if (widget.post.isVideo) {
    result = await Navigator.of(context).push<List<NewPostUserTag>>(
      MaterialPageRoute(
        builder: (_) => FeedTagPeopleVideoScreen(initialTags: _taggedUsers),
      ),
    );
  } else {
    final images = widget.post.mediaItems
        .map<ImageProvider>(
            (m) => CachedNetworkImageProvider(m.mediaUrl))
        .toList();
    if (images.isEmpty) return; // defensive: foto tanpa media, jangan crash
    result = await Navigator.of(context).push<List<NewPostUserTag>>(
      MaterialPageRoute(
        builder: (_) => FeedTagPeopleScreen(
          photoImages: images,
          initialTags: _taggedUsers,
        ),
      ),
    );
  }
  if (result == null || !mounted) return;
  setState(() {
    _taggedUsers = result!;
    _taggedUsersEdited = true;
  });
}
```

Import: `feed_post/feed_tag_people_screen.dart`, `feed_post/feed_tag_people_video_screen.dart`, `../models/new_post_user_tag.dart` (cached_network_image sudah di-import file ini).
3. Baris UI — duplikat struktur baris "Produk ditandai" (±baris 276-316) persis, ditempatkan SETELAH baris produk + `Divider`:

```dart
InkWell(
  onTap: _saving ? null : _openTagPeople,
  child: Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('Orang ditandai',
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 15,
              fontWeight: NataloWeight.body,
            )),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Text(
            _taggedUsers.isEmpty ? 'Tambah' : '${_taggedUsers.length} dipilih',
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 13,
              fontWeight: NataloWeight.body,
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
        ]),
      ],
    ),
  ),
),
Divider(height: 1, color: cs.outlineVariant),
```

4. Di `_save()`, tambahkan argumen: `taggedUsers: _taggedUsersEdited ? _taggedUsers : null,` pada panggilan `feedService.updateMyPost`.
5. Setelah sukses save, sinkronkan store: pada `feedStore.applyPostUpdate(base.copyWith(...))` tambah `taggedUsers:` hasil konversi balik `_taggedUsers` → `FeedTaggedUser` (map field 1:1, `mediaId: null` — server yang punya mediaId; grid/detail refetch akan membawa nilai server) HANYA kalau `_taggedUsersEdited`.

- [ ] **Step 4: Run, verify PASS** — `flutter test test/screens/member_post_edit_tagged_row_test.dart` hijau.

- [ ] **Step 5: Commit** — `git add flutter_app/lib/screens/member_post_edit_screen.dart flutter_app/test/screens/member_post_edit_tagged_row_test.dart && git commit -m "feat(app): baris Orang ditandai di halaman edit post (Spec D)"`

---

### Task 5: Flutter — flag showTaggedBadge di FeedVideoPostView

**Files:**
- Modify: `flutter_app/lib/features/feed/widgets/feed_video_post_view.dart` (constructor ±baris 217; render badge ±baris 3541)
- Modify: `flutter_app/lib/screens/feed_screen.dart:852` (call site feed utama)
- Test: `flutter_app/test/screens/feed_video_tagged_badge_test.dart` (create)

**Interfaces:**
- Produces: `FeedVideoPostView({..., bool showTaggedBadge = true})`. `scoped_video_feed_screen.dart` TIDAK diubah (pakai default true).

- [ ] **Step 1: Failing test** — widget `FeedVideoPostView` berat (controller video); uji lewat unit logika render guard. Extract predikat statik:

```dart
// Di FeedVideoPostView:
static bool shouldShowTaggedBadge({
  required bool showTaggedBadge,
  required bool hasTags,
}) => showTaggedBadge && hasTags;
```

Test:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_app/features/feed/widgets/feed_video_post_view.dart';

void main() {
  test('badge tampil hanya saat flag on dan ada tag', () {
    expect(FeedVideoPostView.shouldShowTaggedBadge(showTaggedBadge: true, hasTags: true), isTrue);
    expect(FeedVideoPostView.shouldShowTaggedBadge(showTaggedBadge: false, hasTags: true), isFalse);
    expect(FeedVideoPostView.shouldShowTaggedBadge(showTaggedBadge: true, hasTags: false), isFalse);
    expect(FeedVideoPostView.shouldShowTaggedBadge(showTaggedBadge: false, hasTags: false), isFalse);
  });
}
```

- [ ] **Step 2: Run, verify FAIL** — method belum ada.

- [ ] **Step 3: Implement** — (a) tambah field `final bool showTaggedBadge;` + `this.showTaggedBadge = true` di constructor + predikat statik di atas; (b) ganti guard render badge `if (_tags.isNotEmpty)` (±baris 3541) jadi `if (FeedVideoPostView.shouldShowTaggedBadge(showTaggedBadge: widget.showTaggedBadge, hasTags: _tags.isNotEmpty))`; (c) di `feed_screen.dart:852` tambah `showTaggedBadge: false,` pada konstruksi `FeedVideoPostView(`.

- [ ] **Step 4: Run, verify PASS** — test hijau; `flutter analyze` tidak menambah issue baru.

- [ ] **Step 5: Commit** — `git add flutter_app/lib/features/feed/widgets/feed_video_post_view.dart flutter_app/lib/screens/feed_screen.dart flutter_app/test/screens/feed_video_tagged_badge_test.dart && git commit -m "fix(app): badge Ditandai video hanya di halaman postingan, bukan feed utama (Spec D)"`

---

### Task 6: Regresi penuh

**Files:** tidak ada perubahan kode (kecuali fix regresi yang ditemukan).

- [ ] **Step 1:** Backend — `npx tsx --test tests/feed-tagged-users-patch.test.ts tests/feed-hashtags.test.ts` → semua pass. `npx tsc --noEmit` → tidak ada error baru vs baseline (pre-existing: vitest imports, pets photoUrl).
- [ ] **Step 2:** Flutter — dari `flutter_app/`: `flutter analyze` (bandingkan dengan baseline issue count sebelum branch; tidak boleh bertambah) lalu `flutter test` penuh → semua pass.
- [ ] **Step 3:** Kalau ada kegagalan: fix, ulangi step terkait, commit fix terpisah dengan pesan jelas.
- [ ] **Step 4: Commit** (kalau ada perubahan) — `git commit -m "test: regresi penuh Spec D"`

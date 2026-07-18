# Edit Postingan gaya IG + unifikasi alur — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Satukan edit-postingan ke satu layar `MemberPostEditScreen` bergaya IG "Edit info" (header X/centang, caption borderless), dan gate re-moderasi edit ke video-only di BACKEND + Flutter, supaya foto/carousel yang sudah tayang tidak balik ke review saat di-edit.

**Architecture:** Backend (`app/api/feed/posts/[id]/route.ts`) memutuskan status re-moderasi; kita ekstrak keputusan itu ke helper pure `lib/feed/edit-moderation.ts` (testable) lalu gate ke non-photo-carousel. Flutter merestyle layar edit yang sudah ada dan mengarahkan entry point "..." ke sana, dengan optimistic status + notice yang cocok dengan keputusan server.

**Tech Stack:** Next.js (route handler + Prisma) untuk backend; Flutter/Dart untuk client. Test: `node:test` (backend), `flutter_test` (client).

## Global Constraints

- Batas caption backend = **2000** karakter (`app/api/feed/posts/route.ts:175`); client tidak boleh cap lebih rendah. `MemberPostEditScreen._maxCaptionLength` WAJIB `2000`.
- Server = sumber kebenaran status. Optimistic status client HARUS memprediksi keputusan server yang baru, tidak boleh menyimpang.
- Discriminator video vs foto/carousel: **server** pakai `post.kind` (`COMMUNITY` = video customer, `PHOTO_CAROUSEL` = foto/carousel); **client** pakai `post.isVideo` (`contentType == FeedContentType.video`). Keduanya harus konsisten untuk post yang sama.
- Backend: **HANYA** ubah edit path (`[id]/route.ts`). JANGAN sentuh create path (`posts/route.ts:480`) — itu domain PR #168 (belum merge), akan tabrakan.
- Aturan re-moderasi edit: customer edit post ACTIVE → reset ke `PENDING_REVIEW` HANYA kalau `kind !== "PHOTO_CAROUSEL"` (yakni video). Admin edit tidak pernah reset. Post non-ACTIVE tidak berubah statusnya.
- Judul header layar = "Edit info" (label IG), bukan "Edit Postingan".
- Jangan tambah section IG yang tak relevan (Tag people, Add location, AI Label, Content funding).

---

## File Structure

- **Create** `lib/feed/edit-moderation.ts` — helper pure `editReTriggersModeration(...)` (satu tanggung jawab: keputusan reset status saat edit). Dipakai route handler; diuji unit.
- **Create** `tests/feed-edit-moderation.test.ts` — unit test helper (pola `node:test` seperti `tests/feed-saves.test.ts`).
- **Modify** `app/api/feed/posts/[id]/route.ts` (baris 562-565) — panggil helper alih-alih gate hardcode.
- **Modify** `flutter_app/lib/screens/member_post_edit_screen.dart` — restyle header/caption/produk-row + maxLength 2000 + notice/status video-only + top-level `feedPostEditNeedsReview(...)`.
- **Create** `flutter_app/test/screens/member_post_edit_screen_test.dart` — widget test layar edit.
- **Modify** `flutter_app/lib/screens/member_post_detail_screen.dart` — `_editCaption` navigasi ke route; hapus `_EditCaptionSheet`, `_EditCaptionSheetState`, `_withCaption`.
- **Modify/Create** test navigasi entry point (lihat Task 3).

---

## Task 1: Backend — gate edit re-moderasi ke video-only (helper + wire + test)

**Files:**
- Create: `lib/feed/edit-moderation.ts`
- Create: `tests/feed-edit-moderation.test.ts`
- Modify: `app/api/feed/posts/[id]/route.ts:562-565`

**Interfaces:**
- Produces: `editReTriggersModeration({ isAdmin: boolean, status: FeedPostStatus, kind: FeedKind }): boolean` — dipakai route handler PATCH.

- [ ] **Step 1: Tulis failing test**

Buat `tests/feed-edit-moderation.test.ts`:

```ts
import assert from "node:assert/strict";
import test from "node:test";
import { editReTriggersModeration } from "../lib/feed/edit-moderation";

test("customer edit video (COMMUNITY) ACTIVE re-triggers moderation", () => {
  assert.equal(
    editReTriggersModeration({ isAdmin: false, status: "ACTIVE", kind: "COMMUNITY" }),
    true,
  );
});

test("customer edit photo/carousel ACTIVE does NOT re-trigger moderation", () => {
  assert.equal(
    editReTriggersModeration({ isAdmin: false, status: "ACTIVE", kind: "PHOTO_CAROUSEL" }),
    false,
  );
});

test("admin edit never re-triggers moderation", () => {
  assert.equal(
    editReTriggersModeration({ isAdmin: true, status: "ACTIVE", kind: "COMMUNITY" }),
    false,
  );
});

test("non-ACTIVE post edit does not reset status", () => {
  assert.equal(
    editReTriggersModeration({ isAdmin: false, status: "PENDING_REVIEW", kind: "COMMUNITY" }),
    false,
  );
});
```

- [ ] **Step 2: Jalankan test — harus GAGAL**

Run: `npx tsx --test tests/feed-edit-moderation.test.ts` (atau perintah test backend yang dipakai repo — cek `package.json` scripts `test`; kalau pakai `node --test` dengan loader tsx/ts-node, ikuti itu).
Expected: FAIL — `Cannot find module '../lib/feed/edit-moderation'`.

- [ ] **Step 3: Tulis helper**

Buat `lib/feed/edit-moderation.ts`:

```ts
import type { FeedKind, FeedPostStatus } from "@prisma/client";

/**
 * Apakah edit oleh customer harus mengembalikan post ke antrian review admin?
 *
 * Aturan:
 * - Admin edit: TIDAK pernah re-review (return false).
 * - Hanya post yang sedang ACTIVE yang relevan (non-ACTIVE tidak diubah).
 * - Video customer (kind COMMUNITY, dan kind customer non-foto lainnya)
 *   → re-review (return true).
 * - Foto/carousel (PHOTO_CAROUSEL) → dipercaya, TIDAK re-review (return false).
 *
 * Catatan: create-path auto-approve foto/carousel adalah domain terpisah
 * (PR #168); helper ini khusus edit path.
 */
export function editReTriggersModeration(args: {
  isAdmin: boolean;
  status: FeedPostStatus;
  kind: FeedKind;
}): boolean {
  const { isAdmin, status, kind } = args;
  if (isAdmin) return false;
  if (status !== "ACTIVE") return false;
  return kind !== "PHOTO_CAROUSEL";
}
```

- [ ] **Step 4: Jalankan test — harus LULUS**

Run: `npx tsx --test tests/feed-edit-moderation.test.ts`
Expected: PASS (4/4).

- [ ] **Step 5: Wire ke route handler**

Di `app/api/feed/posts/[id]/route.ts`, tambah import di blok import atas (dekat import `lib/feed/*` lain, mis. setelah baris 6):

```ts
import { editReTriggersModeration } from "@/lib/feed/edit-moderation";
```

Ganti baris 562-565:

```ts
  // Customer edit re-trigger moderation — status ke PENDING_REVIEW.
  // Admin edit stays at current status.
  if (!isAdmin && post.status === "ACTIVE") {
    updates.status = "PENDING_REVIEW";
  }
```

menjadi:

```ts
  // Customer edit re-trigger moderation HANYA untuk video (kind bukan
  // PHOTO_CAROUSEL). Foto/carousel yang sudah ACTIVE tetap ACTIVE saat
  // di-edit — dipercaya, tidak perlu review ulang. Sinkron dgn sisi Flutter
  // (MemberPostEditScreen: notice + optimistic status video-only).
  if (editReTriggersModeration({ isAdmin, status: post.status, kind: post.kind })) {
    updates.status = "PENDING_REVIEW";
  }
```

Verifikasi: `post` di query PATCH sudah `select: { kind: true, status: true, ... }` (sekitar baris 340-347) — `post.kind` dan `post.status` tersedia. `isAdmin` sudah didefinisikan di scope handler (dipakai di gate lama). Kalau tipe `post.kind`/`post.status` bukan `FeedKind`/`FeedPostStatus` langsung (mis. union literal dari select), cast/inferensi harus tetap kompatibel — kalau TS komplain, sesuaikan tipe argumen helper agar menerima tipe hasil select (mis. lebar ke `string` lalu bandingkan literal), TANPA melonggarkan logika.

- [ ] **Step 6: Verifikasi tak ada regresi tipe/lint**

Run: `npx tsc --noEmit` (atau `npm run typecheck` kalau ada) — harus clean untuk file yang disentuh.
Run: `npx tsx --test tests/feed-edit-moderation.test.ts` — tetap 4/4.

- [ ] **Step 7: Commit**

```bash
git add lib/feed/edit-moderation.ts tests/feed-edit-moderation.test.ts "app/api/feed/posts/[id]/route.ts"
git commit -m "feat(feed): edit foto/carousel tidak re-review, gate re-moderasi edit ke video-only (helper editReTriggersModeration)"
```

---

## Task 2: Flutter — restyle MemberPostEditScreen ala IG + gating video-only

**Files:**
- Modify: `flutter_app/lib/screens/member_post_edit_screen.dart`
- Create: `flutter_app/test/screens/member_post_edit_screen_test.dart`

**Interfaces:**
- Consumes: `FeedPost.isVideo`, `FeedPost.statusInfo`, `FeedPostStatus.active` (models/feed_post.dart), `feedStore.applyPostUpdate`, `feedService.updateMyPost`, `NataloColors.primary`, `NataloWeight.strong`.
- Produces: top-level `feedPostEditNeedsReview({ required bool wasActive, required bool isVideo }) : bool` (dipakai internal + diuji).

- [ ] **Step 1: Tambah import NataloWeight**

Di `member_post_edit_screen.dart` blok import, tambah (setelah `import '../theme/natalo_colors.dart';`):

```dart
import '../theme/natalo_text.dart';
```

- [ ] **Step 2: Ganti konstanta caption limit + tambah helper keputusan review**

Ubah baris 33:

```dart
  static const _maxCaptionLength = 280;
```
menjadi:
```dart
  static const _maxCaptionLength = 2000;
```

Tambah fungsi top-level (di luar class, mis. tepat sebelum `class MemberPostEditScreen`):

```dart
/// Apakah edit ini akan mengembalikan post ke antrian review admin?
/// Cocok dengan aturan server (edit-moderation.ts): hanya video yang sudah
/// tayang yang re-review; foto/carousel tetap tayang.
bool feedPostEditNeedsReview({
  required bool wasActive,
  required bool isVideo,
}) =>
    wasActive && isVideo;
```

- [ ] **Step 3: Pakai helper di `_save()` (optimistic status + toast)**

Di `_save()` (baris 62-79), ganti blok:

```dart
      final wasActive = widget.post.statusInfo == FeedPostStatus.active;
      // Sync ke FeedStore — semua screen lain (Reels, grid Postingan Saya,
      // Detail) yang baca caption/status post ini ikut update. Status
      // backend reset ke PENDING_REVIEW kalau wasActive (re-review).
      final existing = feedStore.get(widget.post.id);
      if (existing != null) {
        feedStore.applyPostUpdate(existing.copyWith(
          caption: caption.isEmpty ? null : caption,
          description: caption.isEmpty ? '' : caption,
          status: wasActive ? 'PENDING_REVIEW' : existing.status,
        ));
      }
      AppToast.show(
        context,
        wasActive
            ? 'Perubahan tersimpan. Postingan masuk review ulang.'
            : 'Perubahan tersimpan.',
      );
```

menjadi:

```dart
      final wasActive = widget.post.statusInfo == FeedPostStatus.active;
      final needsReview = feedPostEditNeedsReview(
        wasActive: wasActive,
        isVideo: widget.post.isVideo,
      );
      // Sync ke FeedStore — semua screen lain (Reels, grid Postingan Saya,
      // Detail) yang baca caption/status post ini ikut update. Server hanya
      // re-review VIDEO yang tayang; foto/carousel tetap ACTIVE — optimistic
      // status di sini memprediksi keputusan server itu.
      final existing = feedStore.get(widget.post.id);
      if (existing != null) {
        feedStore.applyPostUpdate(existing.copyWith(
          caption: caption.isEmpty ? null : caption,
          description: caption.isEmpty ? '' : caption,
          status: needsReview ? 'PENDING_REVIEW' : existing.status,
        ));
      }
      AppToast.show(
        context,
        needsReview
            ? 'Perubahan tersimpan. Postingan masuk review ulang.'
            : 'Perubahan tersimpan.',
      );
```

- [ ] **Step 4: Restyle `build()` — header IG X/centang, caption borderless, produk row, notice video-only**

Ganti seluruh method `build()` (baris 180-344) dengan:

```dart
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final showReviewNotice =
        widget.post.statusInfo == FeedPostStatus.active && widget.post.isVideo;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Header IG "Edit info": X (batal) kiri, judul tengah, centang
            // bulat (simpan) kanan.
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: cs.onSurface),
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    tooltip: 'Batal',
                  ),
                  Text(
                    'Edit info',
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 16,
                      fontWeight: NataloWeight.strong,
                    ),
                  ),
                  _SaveCheckButton(
                    saving: _saving,
                    onTap: _saving ? null : _save,
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  // Cover thumbnail + caption borderless dalam satu Row (ala IG).
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _CoverThumb(post: widget.post),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _captionController,
                          minLines: 3,
                          maxLines: 8,
                          maxLength: _maxCaptionLength,
                          enabled: !_saving,
                          style: TextStyle(color: cs.onSurface, fontSize: 14),
                          decoration: const InputDecoration(
                            hintText: 'Tulis caption...',
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            filled: false,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                            counterText: '',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.post.isVideo
                        ? 'Video tidak bisa diganti. Untuk video baru, hapus postingan lalu upload ulang.'
                        : 'Media tidak bisa diganti. Untuk foto baru, hapus postingan lalu upload ulang.',
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 11,
                      fontWeight: NataloWeight.body,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Divider(height: 1, color: cs.outlineVariant),
                  // Baris "Produk ditandai" (list polos + chevron).
                  InkWell(
                    onTap: _saving ? null : _openProductPicker,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Produk ditandai',
                            style: TextStyle(
                              color: cs.onSurface,
                              fontSize: 15,
                              fontWeight: NataloWeight.body,
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _loadingProducts
                                    ? 'Memuat...'
                                    : _selectedProductIds.isEmpty
                                        ? 'Tambah'
                                        : '${_selectedProductIds.length} dipilih',
                                style: TextStyle(
                                  color: cs.onSurfaceVariant,
                                  fontSize: 13,
                                  fontWeight: NataloWeight.body,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: cs.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  Divider(height: 1, color: cs.outlineVariant),
                  if (showReviewNotice) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: const Text(
                        'Catatan: perubahan pada video yang sudah tayang akan masuk review admin lagi sebelum tampil publik.',
                        style: TextStyle(
                          color: Color(0xFF92400E),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
```

Catatan: `isDark` masih dipakai? Kalau tidak lagi (AppBar tint lama dibuang), HAPUS deklarasi `final isDark = ...` supaya tidak jadi unused-variable lint. Cek dan bersihkan.

- [ ] **Step 5: Tambah widget `_CoverThumb` + `_SaveCheckButton`, hapus `_TaggedProductsCard`**

Tambah dua widget kecil (mis. setelah class `_MemberPostEditScreenState`). `_CoverThumb` mengambil thumbnail dari kode cover lama (thumbnail 56×56 rounded-8; pakai `CachedNetworkImage` + `Shimmer` placeholder seperti kode lama, dengan ikon play kecil kalau video):

```dart
class _CoverThumb extends StatelessWidget {
  final FeedPost post;
  const _CoverThumb({required this.post});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final url = post.thumbnailUrl;
    return Container(
      width: 56,
      height: 56,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (url != null && url.isNotEmpty)
            CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              placeholder: (_, __) => Shimmer.fromColors(
                baseColor: cs.surfaceContainerHighest,
                highlightColor: cs.outlineVariant,
                child: Container(color: cs.surfaceContainerHighest),
              ),
              errorWidget: (_, __, ___) => const SizedBox.shrink(),
            ),
          if (post.isVideo)
            const Center(
              child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
            ),
        ],
      ),
    );
  }
}

class _SaveCheckButton extends StatelessWidget {
  final bool saving;
  final VoidCallback? onTap;
  const _SaveCheckButton({required this.saving, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        margin: const EdgeInsets.only(right: 8),
        decoration: const BoxDecoration(
          color: NataloColors.primary,
          shape: BoxShape.circle,
        ),
        child: saving
            ? const Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.check_rounded, color: Colors.white, size: 18),
      ),
    );
  }
}
```

Hapus class `_TaggedProductsCard` (baris 347-448) — tidak dipakai lagi. Kalau `_SelectedProductChip`/`_ProductThumb` hanya dipakai oleh `_TaggedProductsCard`, cek: `_ProductThumb` mungkin masih dipakai `_CoverThumb`? Tidak — `_CoverThumb` di atas mandiri. Cek pemakaian `_SelectedProductChip`/`_ProductThumb` di seluruh file sebelum hapus; hapus yang jadi dead code, PERTAHANKAN yang masih dipakai `_TaggedProductPickerSheet`.

- [ ] **Step 6: Analyze bersih**

Run (dari `flutter_app`): `flutter analyze lib/screens/member_post_edit_screen.dart`
Expected: `No issues found!` (tak ada unused `isDark`, unused widget, dsb).

- [ ] **Step 7: Tulis widget test**

Buat `flutter_app/test/screens/member_post_edit_screen_test.dart`. Ikuti pola widget-test repo (mock `SharedPreferences`, bounded pump, hindari `pumpAndSettle` karena Shimmer/`CachedNetworkImage` tak pernah settle — lihat memory "Widget test shimmer hang"). Test WAJIB deterministik tanpa jaringan (biarkan `_loadTaggableProducts` gagal diam → row tetap render). Sertakan setidaknya:

```dart
// pseudo-struktur — sesuaikan helper pump/pref repo yang ada.
// 1. feedPostEditNeedsReview unit:
test('feedPostEditNeedsReview: video active true, foto active false', () {
  expect(feedPostEditNeedsReview(wasActive: true, isVideo: true), isTrue);
  expect(feedPostEditNeedsReview(wasActive: true, isVideo: false), isFalse);
  expect(feedPostEditNeedsReview(wasActive: false, isVideo: true), isFalse);
});

// 2. widget: header X + centang ada, tidak ada AppBar 'Edit Postingan'
//    maupun tombol 'Simpan Perubahan'.
// 3. widget: caption TextField punya InputDecoration.border == InputBorder.none.
// 4. widget: maxLength field == 2000.
// 5. widget: notice 'review' TAMPIL untuk post video+active; TIDAK tampil
//    untuk post foto+active (dua pump terpisah dgn fixture beda).
// 6. widget: baris 'Produk ditandai' ada; tap → _openProductPicker terpanggil
//    (verifikasi via munculnya sheet / atau lewat efek yang observable).
```

Fixture `FeedPost` video-active dan foto-active dibuat via constructor/`copyWith` yang sudah ada (cek constructor `FeedPost` + `FeedContentType`/`contentType` untuk set `isVideo`). Untuk kasus foto, pastikan `contentType != video`.

- [ ] **Step 8: Jalankan test**

Run: `flutter test test/screens/member_post_edit_screen_test.dart`
Expected: semua pass.

- [ ] **Step 9: Commit**

```bash
git add flutter_app/lib/screens/member_post_edit_screen.dart flutter_app/test/screens/member_post_edit_screen_test.dart
git commit -m "feat(postingan): layar Edit Postingan gaya IG (header X/centang, caption borderless, produk row) + notice/status review video-only + caption 2000"
```

---

## Task 3: Flutter — arahkan entry point "..." ke MemberPostEditScreen + hapus sheet lama

**Files:**
- Modify: `flutter_app/lib/screens/member_post_detail_screen.dart`

**Interfaces:**
- Consumes: route `/member/post-edit` (sudah terdaftar di `main.dart:419`, argumen `FeedPost`), `feedStore.get(id)`.

- [ ] **Step 1: Ganti isi `_editCaption(int index)`**

Ganti method `_editCaption` (baris 658-698) dengan:

```dart
  Future<void> _editCaption(int index) async {
    final post = _posts[index];
    final changed = await Navigator.pushNamed(
      context,
      '/member/post-edit',
      arguments: post,
    );
    if (changed != true || !mounted) return;
    // MemberPostEditScreen sudah PATCH + feedStore.applyPostUpdate. Tarik
    // ulang dari store supaya state lokal halaman ini ikut ter-update.
    final synced = feedStore.get(post.id);
    if (synced != null) {
      setState(() {
        _posts[index] = synced;
      });
    }
  }
```

- [ ] **Step 2: Hapus dead code**

Hapus dari `member_post_detail_screen.dart`:
- Method `_withCaption` (baris ~1149-1156).
- Class `_EditCaptionSheet` + `_EditCaptionSheetState` (baris ~3121-3249).

Cek dulu tak ada pemakai lain (`grep -n "_withCaption\|_EditCaptionSheet"`). Kalau import `apiClient` jadi tak terpakai di file ini setelah `_editCaption` tak lagi PATCH — cek `grep -n "apiClient" member_post_detail_screen.dart`; kalau masih dipakai di tempat lain, BIARKAN importnya. Jangan hapus import yang masih dipakai.

- [ ] **Step 3: Analyze bersih**

Run: `flutter analyze lib/screens/member_post_detail_screen.dart`
Expected: `No issues found!` (tak ada unused member/import).

- [ ] **Step 4: Tambah/olah test navigasi**

Tambah test yang memverifikasi tap "..." → "Edit caption" menavigasi ke `/member/post-edit` dengan `arguments` = post yang benar. Kalau sudah ada test file yang me-render `MemberPostDetailScreen`/`_PostMenuSheet` (mis. `member_posts_screen_test.dart` atau `member_post_detail_*_test.dart`), tempel di situ; kalau tidak, buat `flutter_app/test/screens/member_post_detail_edit_nav_test.dart`. Pakai `NavigatorObserver` mock / `onGenerateRoute` spy untuk menangkap `settings.name == '/member/post-edit'` dan `settings.arguments` bertipe `FeedPost` dengan id yang cocok.

Catatan: `member_post_detail_screen_caption_test.dart` menguji TAMPILAN caption (expand/"selengkapnya"), TIDAK terpengaruh — jangan diubah kecuali gagal kompilasi.

- [ ] **Step 5: Jalankan test terkait**

Run: `flutter test test/screens/member_post_detail_screen_caption_test.dart <file test nav baru>`
Expected: pass (caption display test tetap hijau; nav test baru hijau).

- [ ] **Step 6: Commit**

```bash
git add flutter_app/lib/screens/member_post_detail_screen.dart flutter_app/test/screens/
git commit -m "refactor(postingan): '...'→Edit caption arahkan ke MemberPostEditScreen, hapus _EditCaptionSheet + _withCaption"
```

---

## Self-Review (penulis plan — sudah dijalankan)

1. **Spec coverage:** header IG (T2), caption borderless (T2), produk row (T2), notice+status video-only Flutter (T2), backend gate edit path (T1), caption 2000 (T2 Step 2), unifikasi entry point + hapus sheet (T3), anti-collision create path (T1 Global Constraints) — semua tertutup.
2. **Placeholder scan:** tidak ada TBD/TODO; semua step punya kode konkret. Bagian test Flutter (T2 Step 7, T3 Step 4) sengaja pseudo-struktur karena bergantung pada helper pump/pref repo yang ada — implementer WAJIB pakai pola test existing (bounded pump, mock prefs) alih-alih menebak; ini diarahkan eksplisit, bukan placeholder logika.
3. **Type consistency:** `feedPostEditNeedsReview({wasActive, isVideo})` dipakai konsisten di T2; `editReTriggersModeration({isAdmin, status, kind})` di T1. Route `/member/post-edit` + argumen `FeedPost` konsisten T3 ↔ `main.dart:419`.

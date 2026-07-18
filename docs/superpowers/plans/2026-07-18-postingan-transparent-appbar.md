# Postingan: AppBar transparan + Ikuti chip + bookmark Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans atau eksekusi inline (proyek kecil, satu screen). Steps pakai checkbox (`- [ ]`).

**Goal:** Halaman Postingan (`member_post_detail_screen.dart`) — AppBar jadi overlay transparan permanen (LiquidGlass back button + judul putih-shadow), chip "Ikuti"/"Mengikuti" muncul di kanan saat `!isOwner`, dan tambah ikon bookmark ke action row.

**Architecture:** `Scaffold.extendBodyBehindAppBar: true` + `AppBar(backgroundColor: Colors.transparent, elevation: 0, scrolledUnderElevation: 0)`. Leading = lingkaran `LiquidGlass` berisi ikon back. Title tetap dua baris ("Postingan" / nama) tapi warna putih + text-shadow permanen (bukan `cs.onSurface` adaptif). Actions = pill `LiquidGlass` "Ikuti"/"Mengikuti" (mirror styling `_FeedFollowChip` di `feed_creator_overlay.dart`, tapi state lokal pakai `resolveFollowState`/`setFollowOverride` — bukan replikasi penuh viewer-generation `_FeedPostCreatorIdentityState`, karena chip ini cuma satu instance per screen). Bookmark: tombol baru di action row `_PostFeedItem`, pola sama dengan `_onSavePressed` di `feed_screen.dart`/`feed_video_post_view.dart` (reuse `feedStore.toggleSaved`).

**Tech Stack:** Flutter, `LiquidGlass` widget (`lib/widgets/liquid_glass.dart`), `follow_override_store.dart`, `feedStore` (`state/feed_store.dart`), `followService`.

## Global Constraints

- AppBar transparan **permanen** sepanjang scroll (tidak pernah balik solid) — keputusan user eksplisit, terima risiko judul kurang kebaca di atas latar putih (Opsi B, disetujui).
- Back button DAN chip Ikuti dibungkus `LiquidGlass` asli (bukan bubble/border buatan) — `opacity: 1`, `reducedMotion: MediaQuery.disableAnimationsOf(context)`, `borderRadius` lingkaran penuh untuk back (circle) dan stadium (pill) untuk Ikuti.
- Chip pakai teks "Ikuti"/"Mengikuti" (bukan "Follow"), warna putih, `fontWeight: FontWeight.w600`, `text-shadow` — bukan tombol biru solid.
- Chip tinggi 30px, sejajar top-offset dengan back button (30px juga), padding dirapatkan (bukan lebar-longgar).
- Chip HANYA muncul saat `widget.isOwner == false` (viewer bukan pemilik post).
- Judul "Postingan / nama" selalu putih + `Shadow(color: Colors.black54, blurRadius: ~8-10)`, tidak lagi pakai `cs.onSurface`/`officialGoldOnLight` adaptif untuk teks utama (nama author tetap boleh emas untuk official — pertahankan warna emas, cukup tambah shadow).
- Bookmark: ikon `Icons.bookmark_rounded`/`bookmark_border_rounded`, size 30 (match 3 ikon lain di action row), posisi ujung kanan row (setelah share, `mainAxisAlignment` spaceBetween atau `Spacer` sebelum bookmark).
- TIDAK mengubah `_PostAuthorRow`/`_VideoPostAuthorOverlay` (per-post header, sudah selesai di task sebelumnya) — task ini murni AppBar level-screen + action row.
- TIDAK menyentuh status bar icon color (`AnnotatedRegion`/`SystemUiOverlayStyle`) — di luar scope, dicatat sebagai follow-up.

---

### Task 1: AppBar transparan + LiquidGlass back button + judul shadow

**Files:**
- Modify: `flutter_app/lib/screens/member_post_detail_screen.dart` (build method AppBar, sekitar baris 756-812)
- Test: `flutter_app/test/screens/member_post_detail_appbar_test.dart` (baru)

**Interfaces:**
- Consumes: `LiquidGlass` (`../widgets/liquid_glass.dart`) — sudah ada, cek import sudah ada di file ini (belum — perlu ditambah).

- [ ] **Step 1: Tulis test — AppBar transparan + back button dibungkus LiquidGlass**

```dart
// flutter_app/test/screens/member_post_detail_appbar_test.dart
// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/screens/member_post_detail_screen.dart';
import 'package:natalo_petshop_flutter/widgets/liquid_glass.dart';

FeedPost _photoPost() => FeedPost.fromJson({
      'id': 'appbar-test-photo',
      'slug': 'appbar-test-photo',
      'kind': 'PHOTO',
      'author': {'id': 'author-1', 'name': 'Rani', 'role': 'CUSTOMER'},
      'caption': '',
      'createdAt': '2026-07-18T00:00:00.000Z',
    });

void main() {
  testWidgets('AppBar is transparent and body extends behind it',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: MemberPostDetailScreen(post: _photoPost())),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.extendBodyBehindAppBar, isTrue);

    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.backgroundColor, Colors.transparent);
    expect(appBar.scrolledUnderElevation, 0);

    expect(find.byType(LiquidGlass), findsWidgets);
  });
}
```

- [ ] **Step 2: Jalankan test, pastikan gagal (RED)**

Run: `flutter test test/screens/member_post_detail_appbar_test.dart`
Expected: FAIL — `scaffold.extendBodyBehindAppBar` masih `null`/`false`, `appBar.backgroundColor` masih `cs.surface`.

- [ ] **Step 3: Implementasi — ubah `Scaffold` + `AppBar` di `build()`**

Tambah import di atas file (dekat import `official_brand_avatar.dart`):
```dart
import '../widgets/liquid_glass.dart';
```
(Cek dulu — kemungkinan sudah ada import serupa untuk widget lain; kalau `liquid_glass.dart` belum diimport, tambahkan satu baris ini di blok import.)

Ganti blok `Scaffold`/`AppBar` (baris ~756-812):
```dart
final reducedMotion = MediaQuery.disableAnimationsOf(context);
return Scaffold(
  backgroundColor: cs.surface,
  extendBodyBehindAppBar: true,
  appBar: AppBar(
    backgroundColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    leadingWidth: 56,
    leading: Padding(
      padding: const EdgeInsets.only(left: 10),
      child: Center(
        child: LiquidGlass(
          opacity: 1,
          reducedMotion: reducedMotion,
          borderRadius: BorderRadius.circular(15),
          child: SizedBox(
            width: 30,
            height: 30,
            child: IconButton(
              padding: EdgeInsets.zero,
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(
                Icons.arrow_back_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        ),
      ),
    ),
    centerTitle: true,
    title: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Postingan',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: NataloWeight.strong,
            height: 1.05,
            shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
          ),
        ),
        const SizedBox(height: 3),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                _memberName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: widget.authorIsOfficial
                      ? NataloColors.officialGold
                      : Colors.white,
                  fontSize: 12,
                  fontWeight: NataloWeight.strong,
                  height: 1.05,
                  shadows: const [
                    Shadow(color: Colors.black54, blurRadius: 8),
                  ],
                ),
              ),
            ),
            if (widget.authorIsOfficial) ...[
              const SizedBox(width: 3),
              const OfficialVerifiedBadge(size: 12),
            ],
          ],
        ),
      ],
    ),
  ),
  body: _posts.isEmpty
```
(baris berikutnya — `? Center(...) : NataloPawRefreshIndicator(...)` — TIDAK berubah, biarkan seperti semula persis setelah `body: _posts.isEmpty`.)

- [ ] **Step 4: Jalankan test, pastikan lolos (GREEN)**

Run: `flutter test test/screens/member_post_detail_appbar_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/screens/member_post_detail_screen.dart flutter_app/test/screens/member_post_detail_appbar_test.dart
git commit -m "feat(feed): AppBar Postingan transparan overlay (LiquidGlass back button)"
```

---

### Task 2: Chip "Ikuti"/"Mengikuti" di AppBar (hanya saat !isOwner)

**Files:**
- Modify: `flutter_app/lib/screens/member_post_detail_screen.dart` (tambah widget `_PostDetailFollowChip` + wire ke `actions:` AppBar)
- Test: `flutter_app/test/screens/member_post_detail_appbar_test.dart` (tambah kasus)

**Interfaces:**
- Consumes: `followService.follow(userId)` / `.unfollow(userId)` → `Future<FollowState>`; `resolveFollowState(userId, serverValue)` / `setFollowOverride(userId, following)` (`state/follow_override_store.dart`); `post.author.id`, `post.author.isFollowing` (dari `widget.post` / `_posts[0]` — post yang sedang di-lihat, bukan per-item, karena semua post di screen ini dari author yang sama).
- Produces: widget `_PostDetailFollowChip` dipakai di `actions:` AppBar, hanya dirender saat `!widget.isOwner`.

- [ ] **Step 1: Tulis test — chip muncul saat isOwner=false, tersembunyi saat isOwner=true, tap memicu follow**

```dart
// tambahkan ke member_post_detail_appbar_test.dart

  testWidgets('Ikuti chip shown when viewing another user\'s post, hidden for own',
      (tester) async {
    final post = FeedPost.fromJson({
      'id': 'appbar-test-other',
      'slug': 'appbar-test-other',
      'kind': 'PHOTO',
      'author': {
        'id': 'author-other',
        'name': 'Budi',
        'role': 'CUSTOMER',
        'isFollowing': false,
      },
      'caption': '',
      'createdAt': '2026-07-18T00:00:00.000Z',
    });

    await tester.pumpWidget(MaterialApp(
      home: MemberPostDetailScreen(post: post, isOwner: false, authorName: 'Budi'),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Ikuti'), findsOneWidget);

    await tester.pumpWidget(MaterialApp(
      home: MemberPostDetailScreen(post: post, isOwner: true),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Ikuti'), findsNothing);
    expect(find.text('Mengikuti'), findsNothing);
  });
```

- [ ] **Step 2: Jalankan test, pastikan gagal (RED)**

Run: `flutter test test/screens/member_post_detail_appbar_test.dart`
Expected: FAIL — teks "Ikuti" tidak ditemukan (chip belum ada).

- [ ] **Step 3: Implementasi — tambah `_PostDetailFollowChip` + wire ke `actions:`**

Tambah widget baru di file (dekat `_PostAuthorRow`/setelah helper `_openPostHeaderProfile`):
```dart
class _PostDetailFollowChip extends StatefulWidget {
  final String authorId;
  final bool initialFollowing;

  const _PostDetailFollowChip({
    required this.authorId,
    required this.initialFollowing,
  });

  @override
  State<_PostDetailFollowChip> createState() => _PostDetailFollowChipState();
}

class _PostDetailFollowChipState extends State<_PostDetailFollowChip> {
  bool _busy = false;

  Future<void> _toggle(bool currentlyFollowing) async {
    if (_busy) return;
    if (!memberStore.isLoggedIn) {
      Navigator.pushNamed(context, '/member/login');
      return;
    }
    setState(() => _busy = true);
    final target = !currentlyFollowing;
    setFollowOverride(widget.authorId, target);
    try {
      if (target) {
        await followService.follow(widget.authorId);
      } else {
        await followService.unfollow(widget.authorId);
      }
    } catch (_) {
      if (mounted) {
        setFollowOverride(widget.authorId, currentlyFollowing);
        AppToast.show(context, 'Gagal memperbarui. Coba lagi.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return ValueListenableBuilder<Map<String, bool>>(
      valueListenable: followOverrides,
      builder: (context, _, __) {
        final following =
            resolveFollowState(widget.authorId, widget.initialFollowing);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _toggle(following),
          child: LiquidGlass(
            opacity: 1,
            reducedMotion: reducedMotion,
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 30,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 11),
                child: Center(
                  child: Text(
                    following ? 'Mengikuti' : 'Ikuti',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      shadows: [Shadow(color: Colors.black45, blurRadius: 4)],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
```

Tambah import (kalau belum ada):
```dart
import '../services/follow_service.dart';
import '../state/follow_override_store.dart';
```

Di `AppBar(...)`, tambah `actions:` setelah `title:`:
```dart
    actions: [
      if (!widget.isOwner)
        Padding(
          padding: const EdgeInsets.only(right: 10),
          child: _PostDetailFollowChip(
            authorId: widget.post.author.id,
            initialFollowing: widget.post.author.isFollowing,
          ),
        ),
    ],
```

- [ ] **Step 4: Jalankan test, pastikan lolos (GREEN)**

Run: `flutter test test/screens/member_post_detail_appbar_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/screens/member_post_detail_screen.dart flutter_app/test/screens/member_post_detail_appbar_test.dart
git commit -m "feat(feed): chip Ikuti/Mengikuti di AppBar Postingan (viewer non-owner)"
```

---

### Task 3: Bookmark di action row halaman Postingan

**Files:**
- Modify: `flutter_app/lib/screens/member_post_detail_screen.dart` (`_PostFeedItemState` — action row + state `_saved`)
- Test: `flutter_app/test/screens/member_post_detail_bookmark_test.dart` (baru)

**Interfaces:**
- Consumes: `feedStore.toggleSaved(postId)` → `Future<bool>` (sudah ada, dipakai `feed_screen.dart`/`feed_video_post_view.dart`); `feedStore.get(postId)?.viewerSaved`.

- [ ] **Step 1: Tulis test — bookmark tersedia dan toggle tersimpan**

```dart
// flutter_app/test/screens/member_post_detail_bookmark_test.dart
// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/screens/member_post_detail_screen.dart';

FeedPost _photoPost() => FeedPost.fromJson({
      'id': 'bookmark-test-photo',
      'slug': 'bookmark-test-photo',
      'kind': 'PHOTO',
      'author': {'id': 'author-1', 'name': 'Rani', 'role': 'CUSTOMER'},
      'caption': '',
      'createdAt': '2026-07-18T00:00:00.000Z',
    });

void main() {
  testWidgets('bookmark icon is present in action row', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: MemberPostDetailScreen(post: _photoPost())),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byIcon(Icons.bookmark_border_rounded), findsOneWidget);
  });
}
```

- [ ] **Step 2: Jalankan test, pastikan gagal (RED)**

Run: `flutter test test/screens/member_post_detail_bookmark_test.dart`
Expected: FAIL — ikon bookmark tidak ditemukan.

- [ ] **Step 3: Implementasi**

Di `_PostFeedItemState`, tambah field (dekat `bool liked = widget.liked;` — cek nama variabel state existing untuk like agar konsisten pola) state `_saved` yang sinkron dari `feedStore.get(post.id)?.viewerSaved`, tambah handler `_onSavePressed` (pola sama seperti di `feed_screen.dart` `_onSavePressed`), dan tambah `NataloPostActionButton`-style bookmark button (pakai `Icon` langsung karena `NataloPostActionIconType` belum punya varian bookmark — custom paint bookmark di luar scope task ini) di ujung kanan action row:

```dart
// Di Row([... NataloPostActionButton like/comment/share ...]) tambahkan:
const Spacer(),
IconButton(
  onPressed: _onSavePressed,
  icon: Icon(
    _saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
    color: cs.onSurface,
    size: 26,
  ),
  tooltip: _saved ? 'Hapus dari tersimpan' : 'Simpan postingan',
),
```

`_onSavePressed` mirror `feed_screen.dart`'s `_onSavePressed` (haptic + `feedStore.toggleSaved(post.id)` + 401/404 handling).

- [ ] **Step 4: Jalankan test, pastikan lolos (GREEN)**

Run: `flutter test test/screens/member_post_detail_bookmark_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/screens/member_post_detail_screen.dart flutter_app/test/screens/member_post_detail_bookmark_test.dart
git commit -m "feat(feed): bookmark di action row halaman Postingan"
```

---

### Task 4: Regresi menyeluruh + review akhir

- [ ] Jalankan seluruh suite post-detail terkait:
```bash
flutter test test/screens/member_post_detail_appbar_test.dart test/screens/member_post_detail_bookmark_test.dart test/screens/member_post_detail_screen_caption_test.dart test/screens/member_post_detail_header_tap_test.dart test/screens/member_post_detail_comment_identity_test.dart test/screens/member_post_detail_double_tap_test.dart test/screens/member_post_detail_edit_nav_test.dart test/screens/member_post_detail_screen_coordinator_test.dart test/screens/member_post_detail_screen_fullscreen_test.dart test/screens/product_detail_screen_related_posts_test.dart test/screens/saved_posts_screen_test.dart
```
- [ ] `flutter analyze lib/screens/member_post_detail_screen.dart`
- [ ] Commit final kalau ada fix regresi.

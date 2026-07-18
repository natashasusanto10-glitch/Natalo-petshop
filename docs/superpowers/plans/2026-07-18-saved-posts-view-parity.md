# Postingan Tersimpan — View Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Halaman Postingan Tersimpan memakai kembali view halaman Postingan (grid full-bleed → viewer vertikal swipeable dengan origin-expansion, warm video handoff, fullscreen video, load-more), dengan penampilan pemilik yang benar per post lintas akun.

**Architecture:** Reuse `MemberPostDetailScreen` seutuhnya (ditambah flag `authorPerPost` agar identitas pemilik diambil per post). Ekstrak tile grid `GalleryPostTile` jadi widget bersama. Ekstrak logika buka+warm-handoff jadi mixin `PostGalleryOpener` yang dipakai SavedPostsScreen. SavedPostsScreen dibangun ulang: buang tab & subjudul, pakai `profileGridDelegate()` + tile bersama + mixin.

**Tech Stack:** Flutter/Dart, `flutter_test`, `cached_network_image`, `feedStore`/`feedService`, `pushOriginExpansion`, `PostVideoWarmHandoff`.

## Global Constraints

- Bahasa UI: Indonesia. Judul halaman: **"Postingan Tersimpan"** (verbatim).
- Font weight pakai token `NataloWeight.*` (bukan `FontWeight.w700+` mentah).
- Warna pakai token `NataloColors.*` / `Theme.of(context).colorScheme`.
- Grid delegate WAJIB `profileGridDelegate()` (bersama dgn Postingan/profil), gap 1.5 full-bleed.
- Caller `MemberPostDetailScreen` yang lain (public profile, my-posts) TIDAK boleh berubah perilaku — `authorPerPost` default `false`.
- Widget test: hindari hang shimmer — pakai `feedStore.clear` di setUp/tearDown, bounded pump (jangan `pumpAndSettle` tanpa batas bila ada video/shimmer).
- `flutter analyze` harus bersih.

---

### Task 1: Flag `authorPerPost` di MemberPostDetailScreen

Viewer sekarang me-resolve author dari satu parameter top-level untuk seluruh pager. Untuk saved feed lintas-akun, tiap post harus tampil pemilik aslinya. Tambah flag `authorPerPost` (default false → zero regression) yang membuat identitas author diambil dari `post.author` masing-masing, dan menyembunyikan subtitle author tunggal di AppBar.

**Files:**
- Modify: `flutter_app/lib/screens/member_post_detail_screen.dart`
- Test: `flutter_app/test/screens/member_post_detail_author_per_post_test.dart` (create)

**Interfaces:**
- Produces: `MemberPostDetailScreen({ ..., bool authorPerPost = false })` — konstruktor menerima flag baru.

- [ ] **Step 1: Tulis test yang gagal**

Create `flutter_app/test/screens/member_post_detail_author_per_post_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/screens/member_post_detail_screen.dart';
import 'package:natalo_petshop_flutter/state/feed_store.dart';

FeedPost _post(String id, String authorName) {
  return FeedPost.fromJson({
    'id': id,
    'slug': id,
    'kind': 'PHOTO',
    'author': {'id': 'a-$id', 'name': authorName, 'role': 'CUSTOMER'},
    'mediaItems': [
      {'mediaUrl': 'https://example.com/$id.jpg', 'kind': 'PHOTO'}
    ],
    'viewerSaved': true,
    'createdAt': '2026-07-15T00:00:00.000Z',
  });
}

void main() {
  setUp(feedStore.clear);
  tearDown(feedStore.clear);

  testWidgets('authorPerPost shows each post own author, not "Pengguna"',
      (tester) async {
    final posts = [_post('p1', 'Budi'), _post('p2', 'Sinta')];

    await tester.pumpWidget(
      MaterialApp(
        home: MemberPostDetailScreen(
          post: posts[0],
          posts: posts,
          initialIndex: 0,
          isOwner: false,
          authorPerPost: true,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Budi'), findsWidgets);
    expect(find.text('Pengguna'), findsNothing);
  });
}
```

- [ ] **Step 2: Jalankan test — pastikan GAGAL**

Run: `cd flutter_app && flutter test test/screens/member_post_detail_author_per_post_test.dart`
Expected: FAIL — parameter `authorPerPost` belum ada (compile error), atau setelah field ada tapi belum dipakai, "Budi" tidak ketemu / "Pengguna" muncul.

- [ ] **Step 3: Tambah field `authorPerPost`**

Di `member_post_detail_screen.dart`, setelah field `isOwner` (sekitar baris 99), tambah:

```dart
  /// Cross-account mode. True → identitas author diambil per post dari
  /// `post.author` (dipakai Postingan Tersimpan yang lintas akun). Default
  /// false → perilaku single-author lama (Postingan Saya / public profile).
  final bool authorPerPost;
```

Di konstruktor (`const MemberPostDetailScreen({...})`, sekitar baris 104), tambah setelah `this.isOwner = true,`:

```dart
    this.authorPerPost = false,
```

- [ ] **Step 4: Author per-post di `_postWithResolvedAuthor` + render sites**

Di `_postWithResolvedAuthor` (sekitar baris 615), tambah short-circuit di baris pertama:

```dart
  FeedPost _postWithResolvedAuthor(FeedPost post) {
    if (widget.authorPerPost) return post;
    final source = post.author;
```

Tambah helper getter per-post tepat sebelum `_postWithResolvedAuthor`:

```dart
  String _authorNameFor(FeedPost post) {
    final name = post.author.name.trim();
    return name.isEmpty ? 'Pengguna' : name;
  }

  String _authorInitialFor(FeedPost post) {
    final nm = _authorNameFor(post);
    return nm.isEmpty ? '?' : nm.substring(0, 1).toUpperCase();
  }

  String? _authorPhotoFor(FeedPost post) {
    final photo = (post.author.profilePhotoUrl ?? post.author.avatarUrl)?.trim();
    return photo == null || photo.isEmpty ? null : photo;
  }
```

Di `itemBuilder` `_PostFeedItem` (sekitar baris 848-851), ganti keempat baris identitas agar sadar mode:

```dart
                    memberName:
                        widget.authorPerPost ? _authorNameFor(post) : _memberName,
                    memberInitial: widget.authorPerPost
                        ? _authorInitialFor(post)
                        : _memberInitial,
                    memberPhotoUrl: widget.authorPerPost
                        ? _authorPhotoFor(post)
                        : _memberPhotoUrl,
                    memberIsOfficial: widget.authorPerPost
                        ? post.author.isOfficial
                        : widget.authorIsOfficial,
```

- [ ] **Step 5: Sembunyikan subtitle author tunggal di AppBar saat authorPerPost**

Di AppBar `title` Column (sekitar baris 784-809), bungkus `const SizedBox(height: 3)` + `Row(...)` author dengan guard supaya hanya tampil "Postingan" saat cross-account. Ganti:

```dart
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
```

menjadi:

```dart
            if (!widget.authorPerPost) ...[
              const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
```

dan tutup blok setelah Row selesai (setelah kurung `],` penutup `children` Row + `)` penutup Row) dengan `],` untuk menutup collection-if. Pastikan struktur widget tetap valid (Row menjadi elemen dalam spread-if).

- [ ] **Step 6: Jalankan test — pastikan LULUS**

Run: `cd flutter_app && flutter test test/screens/member_post_detail_author_per_post_test.dart`
Expected: PASS.

- [ ] **Step 7: Regresi caller lama**

Run: `cd flutter_app && flutter test test/screens/member_post_detail_comment_identity_test.dart test/screens/member_posts_screen_test.dart`
Expected: PASS (perilaku single-author lama tak berubah karena default `authorPerPost:false`).

- [ ] **Step 8: Commit**

```bash
cd flutter_app && flutter analyze lib/screens/member_post_detail_screen.dart
git add lib/screens/member_post_detail_screen.dart test/screens/member_post_detail_author_per_post_test.dart
git commit -m "feat(post-viewer): flag authorPerPost untuk feed lintas akun"
```

---

### Task 2: Ekstrak `GalleryPostTile` jadi widget bersama

Tile grid `_GalleryPostTile` sekarang privat di `member_posts_screen.dart`. Ekstrak jadi `GalleryPostTile` publik (opsi `showStatusBadge`) supaya dipakai bersama halaman Postingan & Saved. Halaman Postingan memakai `showStatusBadge: true` (perilaku sekarang); Saved `false`.

**Files:**
- Create: `flutter_app/lib/features/feed/widgets/gallery_post_tile.dart`
- Modify: `flutter_app/lib/screens/member_posts_screen.dart` (hapus class privat + sub-widget yang dipindah, pakai `GalleryPostTile`)
- Test: `flutter_app/test/features/feed/gallery_post_tile_test.dart` (create)

**Interfaces:**
- Produces:
  ```dart
  class GalleryPostTile extends StatelessWidget {
    const GalleryPostTile({
      required Key key,               // GlobalKey originKey (RepaintBoundary)
      required FeedPost post,
      required VoidCallback onTap,
      VoidCallback? onTapDown,
      VoidCallback? onTapCancel,
      bool showStatusBadge = true,
    });
  }
  ```

- [ ] **Step 1: Tulis test yang gagal**

Create `flutter_app/test/features/feed/gallery_post_tile_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/gallery_post_tile.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';

FeedPost _video(String id) => FeedPost.fromJson({
      'id': id,
      'slug': id,
      'kind': 'VIDEO',
      'author': {'id': 'a', 'name': 'Tester', 'role': 'CUSTOMER'},
      'mediaItems': [
        {'mediaUrl': 'https://e.com/$id.mp4', 'kind': 'VIDEO'}
      ],
      'createdAt': '2026-07-15T00:00:00.000Z',
    });

void main() {
  testWidgets('renders video badge and fires onTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GalleryPostTile(
            key: GlobalKey(),
            post: _video('v1'),
            onTap: () => tapped = true,
            showStatusBadge: false,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    await tester.tap(find.byType(GalleryPostTile));
    expect(tapped, isTrue);
  });
}
```

- [ ] **Step 2: Jalankan test — pastikan GAGAL**

Run: `cd flutter_app && flutter test test/features/feed/gallery_post_tile_test.dart`
Expected: FAIL — file `gallery_post_tile.dart` belum ada.

- [ ] **Step 3: Buat file `gallery_post_tile.dart`**

Pindahkan `_GalleryPostTile` (baris 936-990), `_PostThumbnail` (992-1010), `_thumbnailUrlForPost` (1011-1024), `_PostThumbnailFallback` (1025-1043), `_PostMediaTypeIcon` (1044-1066), `_StatusBadge` + `_StatusStyle` (1067-akhir class) dari `member_posts_screen.dart` ke file baru. Jadikan `GalleryPostTile` publik dengan `showStatusBadge`. Isi file:

```dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../models/feed_post.dart';

/// Tile grid foto/video 1:1 full-bleed — dipakai bersama halaman Postingan
/// Saya, profil, dan Postingan Tersimpan. Badge tipe media (video/carousel)
/// selalu tampil; badge status (Menunggu/Ditolak) hanya untuk pemilik post
/// (`showStatusBadge: true`).
class GalleryPostTile extends StatelessWidget {
  final FeedPost post;
  final VoidCallback onTap;
  final VoidCallback? onTapDown;
  final VoidCallback? onTapCancel;
  final bool showStatusBadge;

  const GalleryPostTile({
    required Key key,
    required this.post,
    required this.onTap,
    this.onTapDown,
    this.onTapCancel,
    this.showStatusBadge = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: key,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onTapDown: (_) => onTapDown?.call(),
          onTapCancel: onTapCancel,
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                _PostThumbnail(post: post),
                if (post.isVideo)
                  const Positioned(
                    right: 7,
                    top: 7,
                    child: _PostMediaTypeIcon(icon: Icons.play_arrow_rounded),
                  )
                else if (post.isCarousel || post.mediaItems.length > 1)
                  const Positioned(
                    right: 7,
                    top: 7,
                    child: _PostMediaTypeIcon(icon: Icons.collections_rounded),
                  ),
                if (showStatusBadge)
                  Positioned(
                    left: 7,
                    bottom: 7,
                    child: _StatusBadge(status: post.statusInfo),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PostThumbnail extends StatelessWidget {
  final FeedPost post;
  const _PostThumbnail({required this.post});

  @override
  Widget build(BuildContext context) {
    final imageUrl = _thumbnailUrlForPost(post);
    if (imageUrl == null) return const _PostThumbnailFallback();
    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 180),
      placeholder: (_, __) => const _PostThumbnailFallback(),
      errorWidget: (_, __, ___) => const _PostThumbnailFallback(),
    );
  }
}

String? _thumbnailUrlForPost(FeedPost post) {
  final thumbnail = post.thumbnailUrl;
  if (thumbnail != null && thumbnail.trim().isNotEmpty) return thumbnail.trim();
  for (final item in post.mediaItems) {
    final itemThumb = item.thumbnailUrl;
    if (itemThumb != null && itemThumb.trim().isNotEmpty) {
      return itemThumb.trim();
    }
    if (item.mediaUrl.trim().isNotEmpty) return item.mediaUrl.trim();
  }
  final preview = post.previewMediaUrl;
  return preview.trim().isNotEmpty ? preview.trim() : null;
}

class _PostThumbnailFallback extends StatelessWidget {
  const _PostThumbnailFallback();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceContainerHighest,
      child: Center(
        child: Icon(Icons.photo_library_rounded,
            color: cs.onSurfaceVariant, size: 28),
      ),
    );
  }
}

class _PostMediaTypeIcon extends StatelessWidget {
  final IconData icon;
  const _PostMediaTypeIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 27,
      height: 27,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.72)),
      ),
      child: Icon(icon, color: Colors.white, size: 17),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final FeedPostStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final style = switch (status) {
      FeedPostStatus.pending => const _StatusStyle(
          label: 'Menunggu',
          bg: Color(0xFFFFF4D6),
          fg: Color(0xFFB45309),
          icon: Icons.schedule_rounded,
        ),
      FeedPostStatus.rejected => const _StatusStyle(
          label: 'Ditolak',
          bg: Color(0xFFEF4444),
          fg: Colors.white,
          icon: Icons.cancel_rounded,
        ),
      FeedPostStatus.active || FeedPostStatus.unknown => null,
    };
    if (style == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: style.bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, color: style.fg, size: 12),
          const SizedBox(width: 3),
          Text(
            style.label,
            style: TextStyle(
                color: style.fg, fontSize: 10, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _StatusStyle {
  final String label;
  final Color bg;
  final Color fg;
  final IconData icon;
  const _StatusStyle({
    required this.label,
    required this.bg,
    required this.fg,
    required this.icon,
  });
}
```

> Catatan: sesuaikan isi `_StatusBadge`/`_StatusStyle` dengan versi asli di `member_posts_screen.dart` bila berbeda (salin verbatim badan `build`-nya). Struktur di atas mengikuti pola file sumber.

- [ ] **Step 4: Update `member_posts_screen.dart` memakai `GalleryPostTile`**

Hapus class privat yang sudah dipindah (`_GalleryPostTile`, `_PostThumbnail`, `_thumbnailUrlForPost`, `_PostThumbnailFallback`, `_PostMediaTypeIcon`, `_StatusBadge`, `_StatusStyle`). Tambah import di bagian import:

```dart
import '../features/feed/widgets/gallery_post_tile.dart';
```

Di `itemBuilder` grid (sekitar baris 602-614), ganti `_GalleryPostTile(` → `GalleryPostTile(` dengan `key: _tileKeyFor(post.id)` dan `showStatusBadge: true`:

```dart
                    return GalleryPostTile(
                      key: _tileKeyFor(post.id),
                      post: post,
                      onTap: () => _openPostDetail(
                        visiblePosts,
                        index,
                        _tileKeyFor(post.id),
                      ),
                      onTapDown: () => _preparePostVideo(post),
                      onTapCancel: () => _cancelPreparedPost(post.id),
                      showStatusBadge: true,
                    );
```

(Catatan: `_GalleryPostTile` lama memakai `originKey` sebagai `RepaintBoundary` key; sekarang key itu diteruskan lewat parameter `key`. `_tileKeyFor` mengembalikan `GlobalKey` yang sama — origin-expansion tetap jalan.)

- [ ] **Step 5: Jalankan test tile + regresi Postingan**

Run: `cd flutter_app && flutter test test/features/feed/gallery_post_tile_test.dart test/screens/member_posts_screen_test.dart`
Expected: PASS keduanya.

- [ ] **Step 6: Commit**

```bash
cd flutter_app && flutter analyze lib/features/feed/widgets/gallery_post_tile.dart lib/screens/member_posts_screen.dart
git add lib/features/feed/widgets/gallery_post_tile.dart lib/screens/member_posts_screen.dart test/features/feed/gallery_post_tile_test.dart
git commit -m "refactor(feed): ekstrak GalleryPostTile jadi widget bersama"
```

---

### Task 3: Mixin `PostGalleryOpener` (warm handoff + origin-expansion)

Ekstrak logika buka post (tile-key, warm video prep, `pushOriginExpansion` → `MemberPostDetailScreen`) jadi mixin yang dipakai SavedPostsScreen. Ini menjaga alur buka identik dengan halaman Postingan tanpa menduplikasi glue di dalam SavedPostsScreen.

**Files:**
- Create: `flutter_app/lib/features/feed/widgets/post_gallery_opener.dart`
- Test: `flutter_app/test/features/feed/post_gallery_opener_test.dart` (create)

**Interfaces:**
- Consumes: `PostVideoWarmHandoff`, `pushOriginExpansion`, `MemberPostDetailScreen`, `ScopedPostPageLoader` (`Future<FeedPage> Function(String? cursor)`), `videoQualityService`, `appSettingsStore`, `AppHaptics`.
- Produces:
  ```dart
  mixin PostGalleryOpener<T extends StatefulWidget> on State<T> {
    GlobalKey tileKeyFor(String postId);
    void preparePostVideo(FeedPost post);
    void cancelPreparedPost([String? postId]);
    Future<void> openPostGallery({
      required List<FeedPost> posts,
      required int index,
      required ScopedPostPageLoader loadMore,
      required bool authorIsOfficial,
      required bool isOwner,
      bool authorPerPost,
      String? initialNextCursor,
    });
  }
  ```

- [ ] **Step 1: Tulis test yang gagal**

Create `flutter_app/test/features/feed/post_gallery_opener_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/post_gallery_opener.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/screens/member_post_detail_screen.dart';

FeedPost _p(String id) => FeedPost.fromJson({
      'id': id,
      'slug': id,
      'kind': 'PHOTO',
      'author': {'id': 'a', 'name': 'Tester', 'role': 'CUSTOMER'},
      'mediaItems': [
        {'mediaUrl': 'https://e.com/$id.jpg', 'kind': 'PHOTO'}
      ],
      'createdAt': '2026-07-15T00:00:00.000Z',
    });

class _Host extends StatefulWidget {
  const _Host();
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with PostGalleryOpener<_Host> {
  final posts = [_p('a'), _p('b')];
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          key: tileKeyFor('a'),
          onPressed: () => openPostGallery(
            posts: posts,
            index: 0,
            loadMore: (_) async => FeedPage(items: const []),
            authorIsOfficial: false,
            isOwner: false,
            authorPerPost: true,
          ),
          child: const Text('open'),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('openPostGallery pushes MemberPostDetailScreen with full list',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Host()));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(MemberPostDetailScreen), findsOneWidget);
  });
}
```

- [ ] **Step 2: Jalankan test — pastikan GAGAL**

Run: `cd flutter_app && flutter test test/features/feed/post_gallery_opener_test.dart`
Expected: FAIL — file `post_gallery_opener.dart` belum ada.

- [ ] **Step 3: Buat mixin `post_gallery_opener.dart`**

```dart
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/feed_post.dart';
import '../../../screens/member_post_detail_screen.dart';
import '../../../screens/scoped_video_feed_screen.dart' show ScopedPostPageLoader;
import '../../../services/video_quality_service.dart';
import '../../../state/settings_store.dart';
import '../../../utils/haptics.dart';
import '../../../widgets/origin_expansion_route.dart';
import '../video/post_video_warm_handoff.dart';

/// Alur buka post ala halaman Postingan: tile-key untuk origin-expansion,
/// warm video handoff (buka video instan), dan push `MemberPostDetailScreen`
/// dengan daftar penuh + initialIndex. Dipakai bersama supaya Postingan
/// Tersimpan identik dengan Postingan Saya.
mixin PostGalleryOpener<T extends StatefulWidget> on State<T> {
  final Map<String, GlobalKey> _tileKeys = {};
  bool _openingPost = false;
  PostVideoWarmHandoff? _preparedHandoff;
  String? _preparedPostId;

  GlobalKey tileKeyFor(String postId) =>
      _tileKeys.putIfAbsent(postId, GlobalKey.new);

  PostVideoWarmHandoff? _createWarmHandoff(FeedPost post) {
    return PostVideoWarmHandoff.createIfVideo(
      isVideo: post.isVideo,
      postId: post.id,
      url: videoQualityService.resolvePlaybackUrl(
        post.videoPlaybackUrl,
        dataSaverUrl: post.videoDataSaverUrl,
        userPreference: appSettingsStore.feedVideoQuality,
      ),
      hasAudio: post.hasAudio != false,
    );
  }

  void preparePostVideo(FeedPost post) {
    if (_openingPost || !post.isVideo || _preparedPostId == post.id) return;
    final stale = _preparedHandoff;
    _preparedHandoff = _createWarmHandoff(post);
    _preparedPostId = _preparedHandoff == null ? null : post.id;
    unawaited(stale?.disposeIfUnclaimed());
  }

  void cancelPreparedPost([String? postId]) {
    if (postId != null && _preparedPostId != postId) return;
    final stale = _preparedHandoff;
    _preparedHandoff = null;
    _preparedPostId = null;
    unawaited(stale?.disposeIfUnclaimed());
  }

  PostVideoWarmHandoff? _takePreparedPost(FeedPost post) {
    if (_preparedPostId != post.id) {
      cancelPreparedPost();
      return null;
    }
    final handoff = _preparedHandoff;
    _preparedHandoff = null;
    _preparedPostId = null;
    return handoff;
  }

  Future<void> openPostGallery({
    required List<FeedPost> posts,
    required int index,
    required ScopedPostPageLoader loadMore,
    required bool authorIsOfficial,
    required bool isOwner,
    bool authorPerPost = false,
    String? initialNextCursor,
  }) async {
    if (_openingPost) return;
    _openingPost = true;
    AppHaptics.tap();
    final post = posts[index];
    final originKey = tileKeyFor(post.id);
    final handoff = _takePreparedPost(post) ?? _createWarmHandoff(post);
    try {
      await pushOriginExpansion<void>(
        context,
        originKey: originKey,
        destinationBuilder: (_) => MemberPostDetailScreen(
          post: post,
          posts: posts,
          initialIndex: index,
          authorIsOfficial: authorIsOfficial,
          isOwner: isOwner,
          authorPerPost: authorPerPost,
          warmVideoHandoff: handoff,
          initialNextCursor: initialNextCursor,
          loadMoreScopedPosts: loadMore,
        ),
      );
    } finally {
      await handoff?.disposeIfUnclaimed();
      _openingPost = false;
    }
  }
}
```

> Catatan: verifikasi path import `settings_store.dart` (`appSettingsStore`) & `video_quality_service.dart` (`videoQualityService`) sama dgn yang dipakai `member_posts_screen.dart` (baris 20 & 24). `ScopedPostPageLoader` didefinisikan di `scoped_video_feed_screen.dart:18`.

- [ ] **Step 4: Jalankan test — pastikan LULUS**

Run: `cd flutter_app && flutter test test/features/feed/post_gallery_opener_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd flutter_app && flutter analyze lib/features/feed/widgets/post_gallery_opener.dart
git add lib/features/feed/widgets/post_gallery_opener.dart test/features/feed/post_gallery_opener_test.dart
git commit -m "feat(feed): mixin PostGalleryOpener untuk buka post ala halaman Postingan"
```

---

### Task 4: Bangun ulang SavedPostsScreen (parity + tanpa tab)

Ganti view single-post + tab menjadi: header judul saja, grid `profileGridDelegate()` + `GalleryPostTile` (tanpa status badge), buka via `PostGalleryOpener.openPostGallery` (full list, origin-expansion, warm handoff, fullscreen video, load-more) dengan `authorPerPost:true` & `isOwner:false`.

**Files:**
- Modify (rewrite): `flutter_app/lib/screens/saved_posts_screen.dart`
- Modify: `flutter_app/test/screens/saved_posts_screen_test.dart` (rewrite — tab dibuang)

**Interfaces:**
- Consumes: `GalleryPostTile` (Task 2), `PostGalleryOpener` (Task 3), `MemberPostDetailScreen.authorPerPost` (Task 1), `profileGridDelegate()`, `feedService.fetchSavedPosts`.

- [ ] **Step 1: Tulis ulang test (gagal dulu)**

Ganti isi `flutter_app/test/screens/saved_posts_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/gallery_post_tile.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/screens/member_post_detail_screen.dart';
import 'package:natalo_petshop_flutter/screens/saved_posts_screen.dart';
import 'package:natalo_petshop_flutter/state/feed_store.dart';

FeedPost _post(String id, {String author = 'Tester'}) => FeedPost.fromJson({
      'id': id,
      'slug': id,
      'kind': 'PHOTO',
      'author': {'id': 'a-$id', 'name': author, 'role': 'CUSTOMER'},
      'mediaItems': [
        {'mediaUrl': 'https://e.com/$id.jpg', 'kind': 'PHOTO'}
      ],
      'viewerSaved': true,
      'createdAt': '2026-07-15T00:00:00.000Z',
    });

void main() {
  setUp(feedStore.clear);
  tearDown(feedStore.clear);

  testWidgets('shows title, no tabs, grid tiles', (tester) async {
    final posts = [_post('p1', author: 'Budi'), _post('p2', author: 'Sinta')];
    await tester.pumpWidget(
      MaterialApp(
        home: SavedPostsScreen(
          fetchPosts: ({String? cursor, required int limit}) async =>
              FeedPage(items: posts),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Postingan Tersimpan'), findsOneWidget);
    expect(find.text('Semua'), findsNothing);
    expect(find.text('Belanja'), findsNothing);
    expect(find.byType(GalleryPostTile), findsNWidgets(2));
  });

  testWidgets('tap tile opens MemberPostDetailScreen with full list',
      (tester) async {
    final posts = [_post('p1'), _post('p2')];
    await tester.pumpWidget(
      MaterialApp(
        home: SavedPostsScreen(
          fetchPosts: ({String? cursor, required int limit}) async =>
              FeedPage(items: posts),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(GalleryPostTile).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(MemberPostDetailScreen), findsOneWidget);
  });
}
```

- [ ] **Step 2: Jalankan test — pastikan GAGAL**

Run: `cd flutter_app && flutter test test/screens/saved_posts_screen_test.dart`
Expected: FAIL — masih ada tab / `GalleryPostTile` belum dipakai.

- [ ] **Step 3: Tulis ulang `saved_posts_screen.dart`**

Ganti seluruh isi file. Struktur baru (tanpa `TabController`, tanpa filter belanja, pakai mixin + `profileGridDelegate` + `GalleryPostTile`):

```dart
import 'dart:async';

import 'package:flutter/material.dart';

import '../features/feed/widgets/gallery_post_tile.dart';
import '../features/feed/widgets/post_gallery_opener.dart';
import '../models/feed_post.dart';
import '../services/api_client.dart';
import '../services/feed_service.dart';
import '../state/feed_store.dart';
import '../theme/natalo_colors.dart';
import '../theme/natalo_text.dart';
import '../widgets/natalo_paw_refresh_indicator.dart';
import '../widgets/profile_grid_geometry.dart';

typedef SavedPostsFetcher = Future<FeedPage> Function(
    {String? cursor, required int limit});

class SavedPostsScreen extends StatefulWidget {
  final SavedPostsFetcher fetchPosts;

  SavedPostsScreen({super.key, SavedPostsFetcher? fetchPosts})
      : fetchPosts = fetchPosts ?? feedService.fetchSavedPosts;

  @override
  State<SavedPostsScreen> createState() => _SavedPostsScreenState();
}

class _SavedPostsScreenState extends State<SavedPostsScreen>
    with PostGalleryOpener<SavedPostsScreen> {
  final ScrollController _scrollController = ScrollController();

  List<String> _postIds = const [];
  String? _nextCursor;
  String? _errorText;
  bool _loading = true;
  bool _loadingMore = false;
  bool _loadMoreFailed = false;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    unawaited(_loadInitial());
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients ||
        _loading ||
        _loadingMore ||
        _nextCursor == null) {
      return;
    }
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 360) {
      unawaited(_loadMore());
    }
  }

  List<FeedPost> get _savedPosts => feedStore
      .getMany(_postIds)
      .where((post) => post.viewerSaved)
      .toList(growable: false);

  List<FeedPost> _normalizeSaved(Iterable<FeedPost> posts) => posts
      .map((post) => post.viewerSaved ? post : post.copyWith(viewerSaved: true))
      .toList(growable: false);

  Future<void> _loadInitial() async {
    final generation = ++_loadGeneration;
    if (mounted) {
      setState(() {
        _loading = true;
        _loadingMore = false;
        _errorText = null;
        _loadMoreFailed = false;
      });
    }
    final fetchedAt = DateTime.now();
    try {
      final page = await widget.fetchPosts(limit: 20);
      if (!mounted || generation != _loadGeneration) return;
      final posts = _normalizeSaved(page.items);
      feedStore.mergeFromServer(posts, fetchedAt: fetchedAt);
      setState(() {
        _postIds = posts.map((post) => post.id).toList(growable: false);
        _nextCursor = page.nextCursor;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _errorText = error is ApiException && error.statusCode == 401
            ? 'Masuk kembali untuk melihat postingan tersimpan.'
            : 'Postingan tersimpan belum bisa dimuat.';
      });
    }
  }

  Future<void> _loadMore() async {
    final cursor = _nextCursor;
    if (_loadingMore || cursor == null) return;
    final generation = _loadGeneration;
    setState(() {
      _loadingMore = true;
      _loadMoreFailed = false;
    });
    final fetchedAt = DateTime.now();
    try {
      final page = await widget.fetchPosts(cursor: cursor, limit: 20);
      if (!mounted || generation != _loadGeneration) return;
      final posts = _normalizeSaved(page.items);
      feedStore.mergeFromServer(posts, fetchedAt: fetchedAt);
      final knownIds = _postIds.toSet();
      setState(() {
        _postIds = [
          ..._postIds,
          ...posts.where((post) => knownIds.add(post.id)).map((p) => p.id),
        ];
        _nextCursor = page.nextCursor;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loadingMore = false;
        _loadMoreFailed = true;
      });
    }
  }

  Future<void> _openPost(List<FeedPost> posts, int index) async {
    await openPostGallery(
      posts: posts,
      index: index,
      loadMore: (cursor) => widget.fetchPosts(cursor: cursor, limit: 20),
      authorIsOfficial: false,
      isOwner: false,
      authorPerPost: true,
      initialNextCursor: _nextCursor,
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: cs.surface,
        leading: IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: Icon(Icons.arrow_back_rounded, color: cs.onSurface),
          tooltip: 'Kembali',
        ),
        title: Text(
          'Postingan Tersimpan',
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 18,
            fontWeight: NataloWeight.strong,
          ),
        ),
        centerTitle: false,
        titleSpacing: 0,
      ),
      body: AnimatedBuilder(
        animation: feedStore,
        builder: (context, _) => _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final posts = _savedPosts;
    if (_loading && _postIds.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(
            color: NataloColors.primary, strokeWidth: 2.4),
      );
    }
    if (_errorText != null && _postIds.isEmpty) {
      return _SavedPostsMessage(
        icon: Icons.cloud_off_rounded,
        title: _errorText!,
        actionLabel: 'Coba lagi',
        onAction: _loadInitial,
      );
    }
    if (posts.isEmpty) {
      return _SavedPostsMessage(
        icon: Icons.bookmark_border_rounded,
        title: 'Belum ada postingan tersimpan',
        subtitle: 'Tap ikon simpan di Feed untuk melihatnya lagi di sini.',
        onRefresh: _loadInitial,
      );
    }

    return NataloPawRefreshIndicator(
      onRefresh: _loadInitial,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverGrid.builder(
            gridDelegate: profileGridDelegate(),
            itemCount: posts.length,
            itemBuilder: (context, index) => GalleryPostTile(
              key: tileKeyFor(posts[index].id),
              post: posts[index],
              onTap: () => _openPost(posts, index),
              onTapDown: () => preparePostVideo(posts[index]),
              onTapCancel: () => cancelPreparedPost(posts[index].id),
              showStatusBadge: false,
            ),
          ),
          SliverToBoxAdapter(
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: _loadingMore
                    ? const Center(
                        child: SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(
                              color: NataloColors.primary, strokeWidth: 2.2),
                        ),
                      )
                    : _loadMoreFailed
                        ? Center(
                            child: TextButton.icon(
                              onPressed: _loadMore,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Muat lagi'),
                            ),
                          )
                        : const SizedBox(height: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SavedPostsMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final Future<void> Function()? onAction;
  final Future<void> Function()? onRefresh;

  const _SavedPostsMessage({
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return NataloPawRefreshIndicator(
      onRefresh: onRefresh ?? onAction ?? () async {},
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(32, 88, 32, 32),
        children: [
          Icon(icon, size: 54, color: colors.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.onSurface,
              fontSize: 17,
              fontWeight: NataloWeight.strong,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: colors.onSurfaceVariant, fontSize: 13, height: 1.45),
            ),
          ],
          if (onAction != null && actionLabel != null) ...[
            const SizedBox(height: 20),
            Center(
              child: OutlinedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(actionLabel!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
```

> Catatan: `NataloPawRefreshIndicator` menggantikan `RefreshIndicator` biasa demi konsistensi (sama dgn halaman Postingan). Bila API-nya berbeda dari yang diasumsikan (`onRefresh` + `child`), sesuaikan ke signature aslinya (lihat pemakaian di `member_posts_screen.dart:522`).

- [ ] **Step 4: Jalankan test — pastikan LULUS**

Run: `cd flutter_app && flutter test test/screens/saved_posts_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Hapus test/model usang bila perlu**

Cek `test/models/feed_post_saved_test.dart` masih relevan (model, bukan UI) — biarkan bila lulus:

Run: `cd flutter_app && flutter test test/models/feed_post_saved_test.dart`
Expected: PASS (tak tersentuh perubahan UI).

- [ ] **Step 6: Analyze + full feed test sweep**

Run:
```bash
cd flutter_app && flutter analyze lib/screens/saved_posts_screen.dart && \
flutter test test/screens/saved_posts_screen_test.dart test/screens/member_posts_screen_test.dart test/screens/member_post_detail_author_per_post_test.dart test/features/feed/
```
Expected: semua PASS, analyze bersih.

- [ ] **Step 7: Commit**

```bash
cd flutter_app
git add lib/screens/saved_posts_screen.dart test/screens/saved_posts_screen_test.dart
git commit -m "feat(saved): view parity halaman Postingan — grid+viewer reuse, tanpa tab"
```

---

## Self-Review Notes

- **Spec coverage:** Header judul saja tanpa subjudul/tab (Task 4 build) ✓; grid `profileGridDelegate` + tile bersama tanpa status badge (Task 2 + Task 4) ✓; reuse viewer full-list + origin-expansion + warm handoff + load-more (Task 3 + Task 4) ✓; fullscreen video (otomatis dari reuse `MemberPostDetailScreen`) ✓; author-per-post lintas akun (Task 1) ✓; unsave hilang dari grid (`_savedPosts` filter `viewerSaved` + `AnimatedBuilder(feedStore)` — dipertahankan di Task 4) ✓; endpoint `fetchSavedPosts` (tak berubah) ✓.
- **Cakupan file di luar spec:** spec menyebut 3 file; plan menambah `post_gallery_opener.dart` (mixin) demi menghindari duplikasi glue buka-post di SavedPostsScreen. `member_posts_screen.dart` hanya disentuh untuk memakai `GalleryPostTile` (alur buka miliknya TIDAK di-refactor → risiko regresi minimal).
- **Type consistency:** `openPostGallery(...)`, `tileKeyFor`, `preparePostVideo`, `cancelPreparedPost` konsisten antara Task 3 (definisi) & Task 4 (pemakaian). `GalleryPostTile(key:, post:, onTap:, onTapDown:, onTapCancel:, showStatusBadge:)` konsisten Task 2 ↔ Task 4. `authorPerPost` konsisten Task 1 ↔ Task 3 ↔ Task 4.
- **Verifikasi manual saat eksekusi:** badan `_StatusBadge`/`_StatusStyle` disalin verbatim dari sumber; signature `NataloPawRefreshIndicator` & path import service dicek ke `member_posts_screen.dart`.

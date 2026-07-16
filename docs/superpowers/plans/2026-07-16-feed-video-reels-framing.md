# Feed Video Reels Framing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Menampilkan video feed 9:16 secara penuh seperti Instagram Reels pada layar tinggi tanpa crop horizontal berlebihan.

**Architecture:** Keputusan framing tetap terpusat di `_MediaBackground`. Canvas media memakai viewport rasio 9:16 yang dipusatkan, sementara overlay feed yang sudah ada tetap berada di atasnya. Rasio aktual controller dipakai setelah siap dan rasio post dipakai untuk thumbnail/fallback.

**Tech Stack:** Flutter, `video_player`, `CachedNetworkImage`, Flutter widget tests.

## Global Constraints

- Perubahan hanya menyentuh layout/framing media video.
- Warna, tipografi, spacing, action rail, kartu produk, caption, dan bottom navigation Natalo tetap dipertahankan.
- Jangan merge `claude/feed-video-fit`.
- Tidak mengubah model, API, upload, atau playback lifecycle.

---

### Task 1: Tambahkan helper framing yang dapat diuji

**Files:**
- Modify: `flutter_app/lib/features/feed/widgets/feed_video_post_view.dart` pada `_MediaBackground`
- Test: `flutter_app/test/features/feed/widgets/feed_video_post_view_test.dart`

**Interfaces:**
- Produces a private pure helper that maps source aspect ratio and media viewport to a `BoxFit`/layout decision.
- Existing `_MediaBackground` remains the only consumer; no public API changes.

- [ ] **Step 1: Add failing behavior tests** for 9:16, 4:5, square, and 16:9 thumbnail paths. Assert 9:16 uses the non-cropping Reels viewport decision and other ratios use contain/letterbox.
- [ ] **Step 2: Run the focused test**

```powershell
cd flutter_app
flutter test test/features/feed/widgets/feed_video_post_view_test.dart
```

Expected: the new 9:16 framing assertion fails against the current full-screen `BoxFit.cover` behavior.

- [ ] **Step 3: Implement a private framing decision** that treats ratios within a small tolerance of `9 / 16` as a centered 9:16 canvas and never selects horizontal crop for that case. Keep `contain` for 4:5, square, and landscape.
- [ ] **Step 4: Run the focused test again** and expect all framing assertions to pass.
- [ ] **Step 5: Commit**

```powershell
git add flutter_app/lib/features/feed/widgets/feed_video_post_view.dart flutter_app/test/features/feed/widgets/feed_video_post_view_test.dart
git commit -m "fix(feed): preserve reels framing for portrait video"
```

### Task 2: Apply the same viewport to initialized video and thumbnail

**Files:**
- Modify: `flutter_app/lib/features/feed/widgets/feed_video_post_view.dart` in `_MediaBackground.build`
- Test: `flutter_app/test/features/feed/widgets/feed_video_post_view_test.dart`

**Interfaces:**
- Consumes the helper from Task 1 with actual controller dimensions or `post.aspectRatio`.
- Produces identical framing decisions before and after player initialization.

- [ ] **Step 1: Add a regression test** proving the thumbnail and initialized player use the same source-ratio decision, with a fallback to 9:16 when dimensions are invalid.
- [ ] **Step 2: Run the focused test and verify it fails** before the implementation is unified.
- [ ] **Step 3: Refactor `_MediaBackground.build`** so both branches share the same centered canvas rules, retain the black background, and clip media to the canvas bounds. Do not change controller lifecycle or overlay widgets.
- [ ] **Step 4: Run the focused widget test** and expect PASS.
- [ ] **Step 5: Commit**

```powershell
git add flutter_app/lib/features/feed/widgets/feed_video_post_view.dart flutter_app/test/features/feed/widgets/feed_video_post_view_test.dart
git commit -m "test(feed): keep video thumbnail framing stable"
```

### Task 3: Verify the feed regression surface

**Files:**
- No source changes expected.
- Test: `flutter_app/test/features/feed/widgets/feed_video_post_view_test.dart`
- Test: `flutter_app/test/screens/scoped_video_feed_screen_test.dart`

**Interfaces:**
- Verifies existing playback, visibility, overlay, and scoped feed behavior remain unchanged.

- [ ] **Step 1: Run focused video/widget tests**

```powershell
cd flutter_app
flutter test test/features/feed/widgets/feed_video_post_view_test.dart test/screens/scoped_video_feed_screen_test.dart
```

- [ ] **Step 2: Run analyzer on changed Dart files**

```powershell
flutter analyze lib/features/feed/widgets/feed_video_post_view.dart test/features/feed/widgets/feed_video_post_view_test.dart
```

Expected: no analyzer errors.

- [ ] **Step 3: Perform manual visual verification** on an iPhone 15 Pro-sized viewport using a real 9:16 video, confirming the full subject remains visible and all Natalo overlays remain in their existing positions.
- [ ] **Step 4: Review the final diff** to ensure no colors, copy, spacing, API, or playback lifecycle changes were introduced.


# Feed Photo/Carousel Comment Drawer Instagram Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make photo/carousel comment presentation match Instagram and the existing video behavior without changing comment data or drawer styling.

**Architecture:** Extract the linked media rectangle into a shared Flutter widget, separate photo media from post overlays, and drive both media geometry and drawer movement from the same extent. Keep the existing Feed store, carousel controller, and comment session untouched.

**Tech Stack:** Flutter, Dart, `DraggableScrollableController`, implicit/linked animations, `flutter_test` widget tests.

## Global Constraints

- Do not change drawer colors, initial/max extent, comment API, or composer behavior.
- Preserve the current carousel page through drawer open and close.
- Render images without cropping using `BoxFit.contain`.
- Do not add dependencies or modify backend contracts.
- Preserve unrelated local changes in the main checkout.

---

### Task 1: Lock the Instagram-parity behavior with failing tests

**Files:**
- Modify: `flutter_app/test/screens/feed_photo_comment_drawer_test.dart`

**Interfaces:**
- Consumes: `FeedReelsCommentSurface`, `FeedScreen`, `FeedCommentSheet`.
- Produces: regression coverage for overlay visibility, linked drag geometry, image fit, and carousel state.

- [ ] **Step 1: Add a media/overlay separation test**

Build `FeedReelsCommentSurface` with independently keyed media and overlay children, open it, settle the opening animation, and assert the media remains while overlay content is absent. Close through back, settle, and assert overlay content returns.

- [ ] **Step 2: Add a linked drag geometry test**

Open the surface at 400×900, record media bottom and drawer top, drag `ValueKey('feed-comment-drag-handle')` upward, then assert both edges moved upward and still match within one logical pixel.

- [ ] **Step 3: Add a Feed photo renderer test**

Seed a two-slide cached photo post, render `FeedScreen`, and assert each photo `CachedNetworkImage` uses `BoxFit.contain`. Swipe to page 2, open and close comments, and assert the photo `PageController.page` remains 1.

- [ ] **Step 4: Run the focused test and confirm RED**

Run: `flutter test test/screens/feed_photo_comment_drawer_test.dart`

Expected: failures because `FeedReelsCommentSurface` has no separate overlay interface, the photo renderer still uses `BoxFit.cover`, and the compact-frame safe-area/shared behavior is not implemented.

### Task 2: Extract and adopt the shared linked-media frame

**Files:**
- Modify: `flutter_app/lib/widgets/feed_comment_sheet.dart`
- Modify: `flutter_app/lib/features/feed/widgets/feed_video_post_view.dart`
- Test: `flutter_app/test/screens/feed_photo_comment_drawer_test.dart`
- Test: `flutter_app/test/features/feed/widgets/feed_video_post_view_test.dart`

**Interfaces:**
- Produces: `FeedCommentMediaFrame(open, extentListenable, dragOffsetPx, keyboardInsetPx, compactTopInsetPx, screenSize, child)`.
- Consumes: a drawer-extent `ValueListenable<double>` and immutable media child.

- [ ] **Step 1: Move `_CommentVideoFrame` into the shared comment widget module**

Rename it to `FeedCommentMediaFrame`, add an optional `compactTopInsetPx = 0`, and calculate the compact rectangle from `compactTopInsetPx` to the live drawer top.

- [ ] **Step 2: Replace the private video frame call**

Use `FeedCommentMediaFrame` in `FeedVideoPostView` with the existing extent notifier, drag offset, keyboard inset, and screen size. Preserve the video default top inset of zero.

- [ ] **Step 3: Drive the photo surface through the shared frame**

Replace the photo surface's local `Rect.lerp` with `FeedCommentMediaFrame`, backed by a `ValueNotifier<double>` updated from its existing `DraggableScrollableController`. Pass the photo compact top safe-area inset.

- [ ] **Step 4: Run focused frame tests**

Run: `flutter test test/screens/feed_photo_comment_drawer_test.dart test/features/feed/widgets/feed_video_post_view_test.dart --plain-name "comment"`

Expected: shared geometry tests pass and video comment behavior remains unchanged.

### Task 3: Separate photo media from Feed overlays

**Files:**
- Modify: `flutter_app/lib/widgets/feed_comment_sheet.dart`
- Modify: `flutter_app/lib/screens/feed_screen.dart`
- Test: `flutter_app/test/screens/feed_photo_comment_drawer_test.dart`

**Interfaces:**
- Extends: `FeedReelsCommentSurface` with optional `overlay`.
- Preserves: `open`, `onClosed`, session store, viewer identity, and extent callbacks.

- [ ] **Step 1: Add an overlay slot to `FeedReelsCommentSurface`**

Render media through `FeedCommentMediaFrame`. Render the overlay through a keyed fade switcher only while the drawer is fully closed, and remove its hit testing immediately when opening starts.

- [ ] **Step 2: Split `_PhotoCarouselPostView` composition**

Pass only the black `PageView` photo canvas as `child`. Move heart, caption scrim, carousel dots, action rail, product UI, creator, caption, and social proof into `overlay`.

- [ ] **Step 3: Hide Feed-level chrome while overlay-locked**

Make the existing top chrome opacity depend on `_interactionLocked` as well as `_mediaZooming`; retain its existing `IgnorePointer` rule.

- [ ] **Step 4: Run the overlay regression tests**

Run: `flutter test test/screens/feed_photo_comment_drawer_test.dart`

Expected: overlay is absent in compact mode, caption is not visually duplicated, and it restores after close.

### Task 4: Preserve source image ratio and carousel state

**Files:**
- Modify: `flutter_app/lib/screens/feed_screen.dart`
- Test: `flutter_app/test/screens/feed_photo_comment_drawer_test.dart`

**Interfaces:**
- Consumes: existing `PageController _photoPageController` and `FeedMedia.mediaUrl`.
- Produces: uncropped black-letterboxed image rendering.

- [ ] **Step 1: Replace forced aspect/cover rendering**

Remove the `AspectRatio(feedPostInstagramImageAspectRatio(...))` wrapper from the Feed photo canvas and render `CachedNetworkImage(fit: BoxFit.contain)` within the available media bounds.

- [ ] **Step 2: Keep one persistent page controller**

Do not recreate or jump `_photoPageController` during drawer lifecycle changes. Keep current horizontal paging callbacks unchanged.

- [ ] **Step 3: Run fit and carousel regression tests**

Run: `flutter test test/screens/feed_photo_comment_drawer_test.dart`

Expected: `BoxFit.contain`, selected page survives open/close, and all drawer tests pass.

### Task 5: Review and production verification

**Files:**
- Review all files changed by Tasks 1–4.

**Interfaces:**
- No new interfaces; validates production readiness.

- [ ] **Step 1: Format changed Dart files**

Run: `dart format lib/widgets/feed_comment_sheet.dart lib/features/feed/widgets/feed_video_post_view.dart lib/screens/feed_screen.dart test/screens/feed_photo_comment_drawer_test.dart`

- [ ] **Step 2: Run focused tests**

Run: `flutter test test/screens/feed_photo_comment_drawer_test.dart test/feed_comment_sheet_drag_test.dart test/widgets/feed_comment_sheet_modal_test.dart`

Expected: all focused tests pass.

- [ ] **Step 3: Run analyzer**

Run: `flutter analyze lib/widgets/feed_comment_sheet.dart lib/features/feed/widgets/feed_video_post_view.dart lib/screens/feed_screen.dart test/screens/feed_photo_comment_drawer_test.dart`

Expected: no issues.

- [ ] **Step 4: Re-run relevant video coverage**

Run: `flutter test test/features/feed/widgets/feed_video_post_view_test.dart --plain-name "comment"`

Expected: comment-specific video tests pass. Keep the separately observed baseline retry-coordinator failure out of the completion claim unless the full file also passes on a fresh run.

- [ ] **Step 5: Review the final diff**

Confirm no API, backend, dependency, unrelated formatting, debug logging, or user-owned main-checkout files changed.


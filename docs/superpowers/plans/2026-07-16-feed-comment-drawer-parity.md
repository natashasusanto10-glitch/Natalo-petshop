# Feed Comment Drawer Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make video, photo, and carousel posts in Feed use one comment-drawer controller/state machine with identical resize, snap, scrim, keyboard, and dismiss behavior.

**Architecture:** Extract the shared Feed presentation shell from the video implementation into a reusable widget/controller in `feed_comment_sheet.dart` or a focused sibling file. Media widgets provide only their rendered child and callbacks; the existing `FeedCommentSheet` remains the shared comment/data engine. The member post-detail modal remains unchanged.

**Tech Stack:** Flutter/Dart, `DraggableScrollableController`, widget tests, existing FeedStore/comment session state.

## Global Constraints

- Feed video, photo, and carousel use one drawer state machine.
- `member_post_detail_screen.dart` and its modal drawer remain out of scope.
- Keep `VideoAudioClaim`, playback coordinator ownership, and `_playLegacy()` intact.
- Do not add direct legacy `VideoPlayerController.play()` calls.
- Use shared constants/helpers for extent, duration, curve, threshold, scale, translate, and scrim opacity.
- Preserve carousel `PageController` and horizontal gestures while the drawer is closed.

---

### Task 1: Extract shared Feed drawer presentation

**Files:**
- Create or modify: `flutter_app/lib/widgets/feed_comment_sheet.dart` (or a focused `feed_comment_drawer.dart` sibling)
- Test: `flutter_app/test/widgets/feed_comment_sheet_modal_test.dart`

- [ ] Add focused tests for shared extent constants, opening watchdog, snap/dismiss, and media transform callbacks.
- [ ] Move the common controller/phase/extent lifecycle into one reusable `FeedCommentDrawer` widget.
- [ ] Expose `child`, `post`, `onClosed`, `onExtentChanged`, `onMaximumExtentChanged`, and optional media/playback callbacks with exact typed signatures.
- [ ] Keep `FeedCommentSheet` as the inner comment content and preserve session, keyboard, mention, reply, and back handling.
- [ ] Run `flutter test test/widgets/feed_comment_sheet_modal_test.dart` and commit the extraction.

### Task 2: Adapt video Feed to the shared drawer

**Files:**
- Modify: `flutter_app/lib/features/feed/widgets/feed_video_post_view.dart`
- Test: `flutter_app/test/features/feed/widgets/feed_video_post_view_test.dart`

- [ ] Replace the video-only presentation shell with `FeedCommentDrawer`, retaining video-specific playback pause/resume callbacks.
- [ ] Route extent changes into the existing coordinator/audio-claim logic without changing ownership or autoplay gates.
- [ ] Preserve video transform, mute control, transparent-sheet behavior, and Android back closer semantics.
- [ ] Run the focused video drawer/race tests and commit.

### Task 3: Adapt photo/carousel Feed to the shared drawer

**Files:**
- Modify: `flutter_app/lib/screens/feed_screen.dart`
- Test: `flutter_app/test/screens/feed_photo_comment_drawer_test.dart`

- [ ] Remove the photo-only presentation state machine or reduce it to media state and parent overlay state.
- [ ] Wrap the photo/carousel renderer in the shared `FeedCommentDrawer` using the same transform and extent callbacks as video.
- [ ] Preserve `PageController`, active slide, aspect ratio, product overlay, and horizontal swipe behavior when drawer is closed.
- [ ] Add assertions that photo/carousel transform and snap behavior match video at the same extent.
- [ ] Run the photo drawer tests and commit.

### Task 4: Regression and integration verification

**Files:**
- Modify: `flutter_app/test/widgets/feed_comment_sheet_modal_test.dart`
- Modify: `flutter_app/test/screens/feed_photo_comment_drawer_test.dart`
- Modify: `flutter_app/test/features/feed/widgets/feed_video_post_view_test.dart`

- [ ] Test video/photo/carousel opening, intermediate resize, maximum pause threshold, dismiss, backdrop, keyboard, rapid taps, and reopen.
- [ ] Test carousel slide preservation and no change to member post-detail modal behavior.
- [ ] Run focused suites, `flutter analyze` on changed files, then the full Flutter test suite if shared playback paths changed.
- [ ] Run `git diff --check`, review the final diff for duplicated state machines, and commit verification.

# Feed Action Rail Density Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the shared Feed action rail as compact as Instagram Reels, align its lowest action with the bottom social-proof metadata row, and simplify the scoped-fullscreen back control.

**Architecture:** Keep `FeedActionRail` as the single owner of action-item geometry and expose shared layout constants through `feed_post_shared_widgets.dart`. Photo, carousel, video, and scoped fullscreen continue consuming the same rail. The fullscreen back button keeps its 48dp hit target while removing only its visible circular material background.

**Tech Stack:** Flutter, Dart, widget tests, Material semantics

## Global Constraints

- Action icon size remains 30dp.
- Action item gap is exactly 10dp.
- Counted item visual height is 54dp; non-counted item height remains 44dp.
- Every action keeps at least a 44dp interactive target.
- The lowest More action aligns with the bottom social-proof metadata row.
- Scoped fullscreen back icon is 32dp white with a subtle shadow and no visible black circle.
- Scoped fullscreen back hit target remains 48x48dp and edge-swipe behavior remains unchanged.

---

### Task 1: Compact Shared Action Rail Geometry

**Files:**
- Modify: `flutter_app/lib/features/feed/widgets/feed_action_rail.dart`
- Modify: `flutter_app/lib/features/feed/widgets/feed_post_shared_widgets.dart`
- Modify: `flutter_app/lib/features/feed/widgets/feed_video_post_view.dart`
- Modify: `flutter_app/lib/screens/feed_screen.dart`
- Test: `flutter_app/test/feed_action_rail_test.dart`

**Interfaces:**
- Consumes: `FeedActionRail` and the shared bottom inset constants.
- Produces: `feedPostActionRailBottomGap`, a shared rail anchor used by photo/carousel and video call sites.

- [ ] **Step 1: Write failing geometry tests**

Add widget assertions that the full five-action rail fits inside 290dp, the vertical gap between adjacent action item boxes is 10dp, and each semantic action remains tappable.

- [ ] **Step 2: Run the focused test and verify failure**

Run: `flutter test test/feed_action_rail_test.dart`

Expected: the 290dp compact-height assertion fails with the current 340dp rail.

- [ ] **Step 3: Implement compact item geometry**

Set `_feedActionItemSpacing` to `10.0` and counted `_ReelsAction` height to `54.0`. Keep width `54.0`, non-counted height `44.0`, icon size `30.0`, count spacing `2.0`, semantics, pulse animation, and throttling unchanged.

- [ ] **Step 4: Add and apply the shared bottom anchor**

Define `feedPostActionRailBottomGap = 4.0` alongside `feedPostOverlayBottomGap = 16.0`. Use the rail-specific gap in `feed_video_post_view.dart` and both photo/carousel rail call sites in `feed_screen.dart`. This lowers the More action center by 12dp so it aligns with the bottom metadata/social-proof row while the caption column retains its existing 16dp inset.

- [ ] **Step 5: Run focused rail and Feed tests**

Run: `flutter test test/feed_action_rail_test.dart test/screens/feed_photo_comment_drawer_test.dart test/features/feed/widgets/feed_video_post_view_test.dart`

Expected: all tests pass with no overflow or interaction regression.

### Task 2: Transparent Scoped-Fullscreen Back Control

**Files:**
- Modify: `flutter_app/lib/screens/scoped_video_feed_screen.dart`
- Test: `flutter_app/test/screens/scoped_video_feed_screen_test.dart`

**Interfaces:**
- Consumes: existing `_close` callback and edge-swipe state machine.
- Produces: the same `scoped-video-back-target` key with a transparent 48x48dp target and 32dp icon.

- [ ] **Step 1: Write failing back-control test**

Assert that `scoped-video-back-target` remains 48x48dp, its descendant chevron is 32dp, and no circular `Material` with a non-transparent color wraps it.

- [ ] **Step 2: Run the focused test and verify failure**

Run: `flutter test test/screens/scoped_video_feed_screen_test.dart`

Expected: icon-size/background assertions fail against the current 26dp icon and black circular material.

- [ ] **Step 3: Implement the transparent control**

Replace the black circular `Material` with a transparent `Material`/`InkResponse`, retain the 48x48dp box, set the chevron to 32dp, and add a subtle black shadow. Preserve `SafeArea`, 12dp outer padding, `_close`, and pointer/edge-swipe handling.

- [ ] **Step 4: Run scoped fullscreen tests**

Run: `flutter test test/screens/scoped_video_feed_screen_test.dart`

Expected: all tests pass, including edge swipe and timestamp-return tests.

### Task 3: Verification And Review

**Files:**
- Review all files modified in Tasks 1-2.

**Interfaces:**
- Consumes: compact rail and transparent back control.
- Produces: release-ready Flutter changes.

- [ ] **Step 1: Format and analyze**

Run: `dart format` on modified Dart files, then `flutter analyze` on those files.

Expected: no analyzer issues.

- [ ] **Step 2: Run the complete Flutter suite**

Run: `flutter test`

Expected: all existing tests pass; intentionally skipped tests remain skipped.

- [ ] **Step 3: Review lifecycle and responsive behavior**

Confirm the rail uses one shared geometry on photo, carousel, video, and scoped fullscreen; no action callbacks changed; the back control retains semantics and a 48dp hit target; no fixed screen-height coordinate was introduced.

- [ ] **Step 4: Commit implementation**

Run:

```powershell
git add flutter_app/lib flutter_app/test
git commit -m "fix(feed): compact action rail and simplify fullscreen back"
```

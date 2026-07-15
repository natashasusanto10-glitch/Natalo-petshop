# Profile Grid and Public Header Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give both Natalo profile surfaces an edge-to-edge 4:5 grid and give public profiles a smooth Instagram-inspired collapsible header with right-to-left tab merging.

**Architecture:** Centralize grid geometry and scroll interpolation in small shared Flutter units. Keep `MemberScreen` navigation/header unchanged except for grid geometry; integrate a dedicated public-header sliver into `PublicProfileScreen` while retaining the existing `TabController`, data flow, actions, and official styling.

**Tech Stack:** Flutter/Dart, Material slivers, `NestedScrollView`, `SliverPersistentHeaderDelegate`, Flutter widget/unit tests.

## Global Constraints

- Both profile grids are three columns, edge-to-edge, 4:5 (`childAspectRatio: 0.8`), with exactly 1 logical pixel horizontal and vertical spacing.
- The member's own profile keeps Natalo bottom navigation and existing hero/header.
- Public profiles render no bottom navigation and keep native back/swipe-back behavior.
- Public tabs merge smoothly from right to left based on `shrinkOffset`; no timer, snap, or grid jump.
- Existing Follow/Following, Message, report, block, share, badges, paging, empty/loading/error states, colors, typography, and official profile treatment remain functional.
- Reduced-motion users receive scroll-linked geometry without decorative spring/overshoot.
- Preserve unrelated dirty working-tree files and do not commit them.

---

### Task 1: Shared edge-to-edge profile grid geometry

**Files:**
- Create: `flutter_app/lib/widgets/profile_grid_geometry.dart`
- Modify: `flutter_app/lib/screens/member_screen.dart`
- Modify: `flutter_app/lib/screens/public_profile_screen.dart`
- Create: `flutter_app/test/widgets/profile_grid_geometry_test.dart`

**Interfaces:**
- Produces: `kProfileGridColumns`, `kProfileGridSpacing`, `kProfileGridChildAspectRatio`, and `profileGridDelegate()` returning a `SliverGridDelegateWithFixedCrossAxisCount`.
- Consumed by: both profile screens and later layout tests.

- [ ] **Step 1: Write the failing geometry test**

```dart
test('profile grid geometry matches the shared portrait contract', () {
  final grid = profileGridDelegate();
  expect(grid.crossAxisCount, 3);
  expect(grid.mainAxisSpacing, 1);
  expect(grid.crossAxisSpacing, 1);
  expect(grid.childAspectRatio, .8);
});
```

- [ ] **Step 2: Run the focused test and verify failure**

Run from `flutter_app`: `flutter test test/widgets/profile_grid_geometry_test.dart`

Expected: FAIL because the shared geometry file/function does not exist.

- [ ] **Step 3: Implement the shared delegate**

```dart
const int kProfileGridColumns = 3;
const double kProfileGridSpacing = 1;
const double kProfileGridChildAspectRatio = 4 / 5;

SliverGridDelegateWithFixedCrossAxisCount profileGridDelegate() =>
    const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: kProfileGridColumns,
      mainAxisSpacing: kProfileGridSpacing,
      crossAxisSpacing: kProfileGridSpacing,
      childAspectRatio: kProfileGridChildAspectRatio,
    );
```

Replace the duplicated square delegates in member/public profile grids and loading grids. Remove horizontal grid padding while retaining only required bottom safe-area/loading clearance.

- [ ] **Step 4: Run geometry and existing profile tests**

Run: `flutter test test/widgets/profile_grid_geometry_test.dart test/screens/public_profile_sync_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/widgets/profile_grid_geometry.dart flutter_app/lib/screens/member_screen.dart flutter_app/lib/screens/public_profile_screen.dart flutter_app/test/widgets/profile_grid_geometry_test.dart
git commit -m "feat(profile): share portrait edge-to-edge grid"
```

### Task 2: Pure scroll interpolation contract for public tabs

**Files:**
- Create: `flutter_app/lib/widgets/public_profile_header_motion.dart`
- Create: `flutter_app/test/widgets/public_profile_header_motion_test.dart`

**Interfaces:**
- Produces: `PublicProfileHeaderMotion.resolve(double shrinkOffset, double collapseRange)` returning immutable progress, width factor, horizontal alignment, radius, gap, and label opacity.
- Consumed by: Task 3's sliver delegate.

- [ ] **Step 1: Write failing interpolation tests**

Test progress at 0, 30%, 60%, and 100%; assert clamping, monotonically decreasing width, right-to-left movement, increasing radius, and reversible deterministic output.

```dart
final start = PublicProfileHeaderMotion.resolve(0, 200);
final middle = PublicProfileHeaderMotion.resolve(120, 200);
final end = PublicProfileHeaderMotion.resolve(200, 200);
expect(start.progress, 0);
expect(end.progress, 1);
expect(middle.widthFactor, lessThan(start.widthFactor));
expect(end.horizontalAlignment, lessThan(start.horizontalAlignment));
```

- [ ] **Step 2: Run and verify failure**

Run: `flutter test test/widgets/public_profile_header_motion_test.dart`

Expected: FAIL because the motion model does not exist.

- [ ] **Step 3: Implement deterministic lerp-based motion**

Use `clamp`, `lerpDouble`, and a smoothstep curve derived from normalized scroll progress. Do not allocate an `AnimationController`. Define exact start/end values in named constants so widget tests can assert them.

- [ ] **Step 4: Run focused tests**

Run: `flutter test test/widgets/public_profile_header_motion_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/widgets/public_profile_header_motion.dart flutter_app/test/widgets/public_profile_header_motion_test.dart
git commit -m "feat(profile): model scroll-driven tab merge motion"
```

### Task 3: Integrate collapsible public profile header and segmented tabs

**Files:**
- Create: `flutter_app/lib/widgets/public_profile_collapsing_header.dart`
- Modify: `flutter_app/lib/screens/public_profile_screen.dart`
- Modify: `flutter_app/lib/widgets/profile_content_tab_bar.dart`
- Create: `flutter_app/test/widgets/public_profile_collapsing_header_test.dart`

**Interfaces:**
- Consumes: `PublicProfileHeaderMotion`, existing `TabController`, `PublicProfile`, existing callbacks for back/follow/message/share/moderation.
- Produces: `PublicProfileCollapsingHeader` and a compact-capable `ProfileContentTabBar` that retain the current tab semantics.

- [ ] **Step 1: Write failing widget tests**

Pump the header at expanded, intermediate, and collapsed extents. Assert back/title/overflow semantics, compact pill width decreases, right edge begins moving left, selected tab remains selected, and public header has no bottom navigation.

- [ ] **Step 2: Run and verify failure**

Run: `flutter test test/widgets/public_profile_collapsing_header_test.dart`

Expected: FAIL because the collapsing header widget does not exist.

- [ ] **Step 3: Implement the sliver header**

Create a `SliverPersistentHeaderDelegate` whose `maxExtent` includes expanded profile data plus tabs and whose `minExtent` includes safe-area compact top bar plus compact tabs. Use `LayoutBuilder`/`Stack` and the motion model to interpolate geometry. Keep content clipped to prevent overflow on iPhone 15 Pro and smaller Android widths.

- [ ] **Step 4: Wire existing actions and context rules**

Public profiles: back, title, overflow/report/block/share, follow/message and official treatment. Member profile remains untouched. The compact tab uses the existing controller and semantic labels; do not create a second tab state.

- [ ] **Step 5: Verify scroll stability and tests**

Run: `flutter test test/widgets/public_profile_collapsing_header_test.dart test/screens/public_profile_sync_test.dart test/screens/public_profile_video_prewarm_test.dart`

Expected: PASS and no selected-tab/scroll reset.

- [ ] **Step 6: Commit**

```bash
git add flutter_app/lib/widgets/public_profile_collapsing_header.dart flutter_app/lib/widgets/profile_content_tab_bar.dart flutter_app/lib/screens/public_profile_screen.dart flutter_app/test/widgets/public_profile_collapsing_header_test.dart
git commit -m "feat(profile): add smooth public header collapse"
```

### Task 4: Cross-device regression and accessibility verification

**Files:**
- Modify: `flutter_app/test/widgets/public_profile_collapsing_header_test.dart`
- Modify: `flutter_app/test/widgets/profile_grid_geometry_test.dart`
- Inspect: `flutter_app/lib/screens/member_screen.dart`, `flutter_app/lib/screens/public_profile_screen.dart`

**Interfaces:**
- Consumes: final shared grid and public header.
- Produces: release evidence; no new production API.

- [ ] **Step 1: Add width and reduced-motion cases**

Test 393 logical px (iPhone 15 Pro equivalent), a narrower 360 px Android width, text scaling, dark theme, and `disableAnimations: true`. Assert no overflow exceptions and active-tab semantics remain available.

- [ ] **Step 2: Run the complete focused profile suite**

Run from `flutter_app`:

```bash
flutter test test/widgets/profile_grid_geometry_test.dart test/widgets/public_profile_header_motion_test.dart test/widgets/public_profile_collapsing_header_test.dart test/screens/public_profile_sync_test.dart test/screens/public_profile_video_prewarm_test.dart
```

Expected: PASS.

- [ ] **Step 3: Run static analysis on changed surfaces**

Run: `flutter analyze lib/widgets/profile_grid_geometry.dart lib/widgets/public_profile_header_motion.dart lib/widgets/public_profile_collapsing_header.dart lib/widgets/profile_content_tab_bar.dart lib/screens/public_profile_screen.dart lib/screens/member_screen.dart`

Expected: no new errors or warnings attributable to changed files.

- [ ] **Step 4: Manual iPhone smoke test**

Verify own profile retains bottom nav; public profile hides it; grid is 4:5 edge-to-edge; header collapses without overflow; tabs merge smoothly right-to-left and reverse smoothly; back swipe, overflow, Follow, Message, all tabs, official profile, empty/loading grids, and dark mode still work.

- [ ] **Step 5: Commit only required test refinements**

```bash
git add flutter_app/test/widgets/profile_grid_geometry_test.dart flutter_app/test/widgets/public_profile_collapsing_header_test.dart
git commit -m "test(profile): cover responsive public header motion"
```

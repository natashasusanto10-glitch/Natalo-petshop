# Public Profile Tab Merge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mengubah tab Grid, Video, dan Belanja pada public profile menjadi ikon transparan di posisi awal dan kapsul gelap berlabel ketika header collapse.

**Architecture:** `PublicProfileHeaderMotion` menjadi sumber seluruh nilai transisi: geometri grup, opacity label, opacity underline, dan opacity surface kapsul. `PublicProfileCollapsingHeaderDelegate` meneruskan nilai tersebut ke `ProfileContentTabBar`, yang menggambar surface serta state aktif tanpa mengubah `TabController` atau konten grid.

**Tech Stack:** Flutter, Material `TabBar`, `SliverPersistentHeaderDelegate`, Flutter widget tests.

## Global Constraints

- Berlaku untuk public profile biasa dan Natalo Petshop Official.
- Posisi awal menampilkan ikon saja, tanpa label, bar putih, border, atau kapsul.
- Mode collapsed memakai kapsul navy/charcoal transparan; ikon dan label putih, active state memakai aksen Natalo.
- Underline tidak terlihat ketika tab merged.
- Jangan mengubah isi grid, data, API, tab controller, atau swipe antar-tab.

---

### Task 1: Perbarui motion model untuk mode tab awal dan merged

**Files:**
- Modify: `flutter_app/lib/widgets/public_profile_header_motion.dart`
- Test: `flutter_app/test/widgets/public_profile_header_motion_test.dart`

**Interfaces:**
- Produces `surfaceOpacity` and `underlineOpacity` on `PublicProfileHeaderMotion`.
- `labelOpacity` changes monotonically from `0` expanded to `1` collapsed.

- [ ] **Step 1: Write failing endpoint tests** asserting expanded `labelOpacity == 0`, `surfaceOpacity == 0`, `underlineOpacity == 1`; collapsed `labelOpacity == 1`, `surfaceOpacity == 1`, `underlineOpacity == 0`.
- [ ] **Step 2: Run the motion test**

```powershell
cd flutter_app
flutter test test/widgets/public_profile_header_motion_test.dart
```

Expected: FAIL because current label values run in the opposite direction and surface/underline opacity fields do not exist.

- [ ] **Step 3: Add the immutable opacity fields and smoothstep interpolation** in `PublicProfileHeaderMotion.resolve`; retain right-to-left geometry, radius, and gap behavior.
- [ ] **Step 4: Update the monotonic/reverse-scroll tests** to include the new fields and run the focused motion test until it passes.
- [ ] **Step 5: Commit**

```powershell
git add flutter_app/lib/widgets/public_profile_header_motion.dart flutter_app/test/widgets/public_profile_header_motion_test.dart
git commit -m "feat(profile): animate merged tab presentation"
```

### Task 2: Render transparent icons and merged dark capsule

**Files:**
- Modify: `flutter_app/lib/widgets/profile_content_tab_bar.dart`
- Modify: `flutter_app/lib/widgets/public_profile_collapsing_header.dart`
- Test: `flutter_app/test/widgets/profile_content_tab_bar_test.dart`

**Interfaces:**
- Consumes `labelOpacity`, `surfaceOpacity`, `underlineOpacity`, and an `isOfficial` foreground context.
- Produces a visual-only tab presentation; existing `TabController`, `onTap`, semantics, and tooltip behavior remain unchanged.

- [ ] **Step 1: Write failing widget tests** for an expanded bar with no rendered text/no white surface and a merged bar with labels, no underline, and a dark translucent surface.
- [ ] **Step 2: Run the tab bar test**

```powershell
cd flutter_app
flutter test test/widgets/profile_content_tab_bar_test.dart
```

Expected: FAIL because the current tab bar uses `colors.surface`, visible labels, borders, and `UnderlineTabIndicator` in both states.

- [ ] **Step 3: Extend `ProfileContentTabBar` constructor** with presentation inputs passed from the header. Use `Color.lerp(Colors.transparent, navy/charcoal with alpha, surfaceOpacity)` for the container, hide borders as surface opacity approaches zero, and use `Decoration()` instead of `UnderlineTabIndicator` when `underlineOpacity == 0`.
- [ ] **Step 4: Update `_AnimatedProfileTab` colors** so the expanded foreground follows the profile header, while merged labels/icons are white and only the active tab uses `NataloColors.primary`.
- [ ] **Step 5: Pass motion values from `PublicProfileCollapsingHeaderDelegate`**, preserving all existing geometry, tab callbacks, and scroll behavior.
- [ ] **Step 6: Run the focused widget tests** and commit.

```powershell
git add flutter_app/lib/widgets/profile_content_tab_bar.dart flutter_app/lib/widgets/public_profile_collapsing_header.dart flutter_app/test/widgets/profile_content_tab_bar_test.dart
git commit -m "feat(profile): show labels in merged tab capsule"
```

### Task 3: Regression verification

**Files:**
- Test: `flutter_app/test/widgets/public_profile_header_motion_test.dart`
- Test: `flutter_app/test/widgets/profile_content_tab_bar_test.dart`

- [ ] **Step 1: Run both focused tests**

```powershell
cd flutter_app
flutter test test/widgets/public_profile_header_motion_test.dart test/widgets/profile_content_tab_bar_test.dart
```

- [ ] **Step 2: Run analyzer on the changed implementation files**

```powershell
flutter analyze lib/widgets/public_profile_header_motion.dart lib/widgets/profile_content_tab_bar.dart lib/widgets/public_profile_collapsing_header.dart
```

Expected: no analyzer errors.

- [ ] **Step 3: Perform visual QA** on an official and regular public profile, verifying icons-only expanded mode, dark transparent labelled collapsed capsule, no merged underline, and unchanged tab tapping/swiping.

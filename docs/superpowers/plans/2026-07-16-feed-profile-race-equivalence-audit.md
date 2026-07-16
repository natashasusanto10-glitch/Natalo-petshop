# Feed–Profile Race Recovery Equivalence Audit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove whether `origin/main` already preserves every user-visible race-recovery behavior from `claude/feed-profile-race-recover`, and port only verified gaps.

**Architecture:** Treat `origin/main` as the source of truth. Extract the old branch's production intent and regression scenarios, map each to current guards/coordinator paths, and only modify current playback code when a behavior is genuinely absent. Do not replay the stale branch's direct `play()` implementation.

**Tech Stack:** Git, PowerShell, Flutter/Dart, `flutter test`, `flutter analyze`.

## Global Constraints

- Preserve `VideoAudioClaim`, `_playLegacy()`, `_dependenciesReady`, coordinator playback, and frame/audio protections from `main`.
- Do not cherry-pick or fully rebase `ee1c48ca` into `main`.
- Do not add direct legacy `VideoPlayerController.play()` calls outside the established playback gate.
- Do not change app version solely to reproduce the old branch.
- Preserve unrelated dirty files in the user's `main` worktree.

---

### Task 1: Capture the exact audit inputs

**Files:**
- Read: `flutter_app/lib/features/feed/widgets/feed_video_post_view.dart`
- Read: `flutter_app/test/features/feed/widgets/feed_video_post_view_test.dart`
- Read: commit `ee1c48ca`

- [ ] **Step 1: Record commit-scoped production and test paths**

Run from the isolated worktree:

```powershell
git diff ee1c48ca^ ee1c48ca -- flutter_app/lib/features/feed/widgets/feed_video_post_view.dart flutter_app/lib/features/feed/widgets/feed_post_shared_widgets.dart flutter_app/pubspec.yaml
git diff --name-only ee1c48ca^ ee1c48ca -- flutter_app/test
```

Expected: the two feed widget files, version file, and the feed video test file are identified without modifying the worktree.

- [ ] **Step 2: Extract old branch behavior labels**

Run:

```powershell
rg -n "Race fix|HARDENING|audio hantu|routeCovered|appBackgrounded|transparent|nested|foreground|volume|resume" flutter_app/test/features/feed/widgets/feed_video_post_view_test.dart
```

Expected: every race scenario is listed for mapping in Task 2.

### Task 2: Build the behavior-equivalence matrix

**Files:**
- Create: `docs/superpowers/audits/2026-07-16-feed-profile-race-equivalence.md`

- [ ] **Step 1: Map each old scenario to current code**

Create a table with one row per scenario and these columns:

```text
Scenario | Old branch evidence | Main implementation | Main test evidence | Status | Gap action
```

Required rows: controller-loading navigation to Profile, opaque route, nested route, transparent bottom sheet, background/foreground, mute restoration, controller-null uncover, legacy play paths, managed coordinator resume, and lifecycle/listener cleanup.

- [ ] **Step 2: Verify no stale direct play path is required**

Run:

```powershell
rg -n "\.play\(\)" flutter_app/lib/features/feed/widgets/feed_video_post_view.dart
```

For every match, document whether it is managed coordinator code, wrapped by `_playLegacy()`, or an actionable gap. A raw legacy call is not accepted as equivalent.

- [ ] **Step 3: Write the audit result**

Use only these statuses: `setara langsung`, `setara melalui arsitektur baru`, `belum tercakup`, or `tidak lagi relevan`. Include exact test names and file line references for every `setara` claim.

- [ ] **Step 4: Review the matrix against the spec**

Confirm every requirement in `docs/superpowers/specs/2026-07-16-feed-profile-race-equivalence-audit-design.md` has a row and evidence. If a row has no evidence, mark it `belum tercakup`; do not infer coverage.

### Task 3: Port only verified gaps, if any

**Files:**
- Modify only the current `main` playback files named by the matrix.
- Test: `flutter_app/test/features/feed/widgets/feed_video_post_view_test.dart`

- [ ] **Step 1: Add a failing regression test for each confirmed gap**

Each test must reproduce one behavior from the matrix and assert the current public/state-machine outcome. Run the focused test and record the failure before changing production code.

- [ ] **Step 2: Implement the smallest current-architecture fix**

Use `_routeCovered`, `_appBackgrounded`, `_canAutoplayNow()`, `_playLegacy()`, and coordinator APIs already present in `main`. Do not copy old `ctrl.play()` calls or remove `_dependenciesReady`/audio claims.

- [ ] **Step 3: Run the new focused tests**

```powershell
flutter test test/features/feed/widgets/feed_video_post_view_test.dart
```

Expected: all focused tests pass, including the newly added regression tests.

### Task 4: Verify and close the audit

**Files:**
- Read: `docs/superpowers/audits/2026-07-16-feed-profile-race-equivalence.md`
- Modify: only the audit file if evidence or line references changed

- [ ] **Step 1: Run analyzer**

```powershell
flutter analyze lib/features/feed/widgets/feed_video_post_view.dart lib/features/feed/widgets/feed_post_shared_widgets.dart
```

Expected: no new errors. Existing informational warnings must be recorded, not silently ignored.

- [ ] **Step 2: Run the proportional Flutter suite**

```powershell
flutter test test/features/feed/widgets/feed_video_post_view_test.dart
```

If Task 3 modified shared playback behavior, run the full Flutter suite and record the result.

- [ ] **Step 3: Perform final diff review**

```powershell
git diff --check
git status --short
git diff origin/main...HEAD --stat
```

Expected: only the audit/spec documents and any explicitly justified gap fix are present; no generated artifacts, version bump, direct stale playback path, or unrelated files appear.

- [ ] **Step 4: Decide branch cleanup**

If every row is equivalent and verification passes, report that the stale branch can be deleted. Delete `claude/feed-profile-race-recover` locally and remotely only after explicit user confirmation.

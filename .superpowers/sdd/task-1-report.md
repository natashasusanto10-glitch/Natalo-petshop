# Task 1 — Exact audit inputs

## Scope and baseline

- Worktree: `codex-feed-profile-race-audit`
- Old branch/commit: `ee1c48cae55ad2c111288c2ea9d153d2be07ac7d`
- Commit subject: `fix(feed): race Feed→Profile — audio hantu init-race (tertinggal dari squash PR #135)`
- No production files were modified during this task.

## Commands executed

```powershell
git diff ee1c48ca^ ee1c48ca -- flutter_app/lib/features/feed/widgets/feed_video_post_view.dart flutter_app/lib/features/feed/widgets/feed_post_shared_widgets.dart flutter_app/pubspec.yaml
git diff --name-only ee1c48ca^ ee1c48ca -- flutter_app/test
rg -n "Race fix|HARDENING|audio hantu|routeCovered|appBackgrounded|transparent|nested|foreground|volume|resume" flutter_app/test/features/feed/widgets/feed_video_post_view_test.dart
git show --stat --oneline --decorate ee1c48ca
git show --format=fuller --no-patch ee1c48ca
git status --short
```

## Commit-scoped paths identified

Production paths changed by `ee1c48ca`:

- `flutter_app/lib/features/feed/widgets/feed_video_post_view.dart`
- `flutter_app/lib/features/feed/widgets/feed_post_shared_widgets.dart`
- `flutter_app/pubspec.yaml`

Test path changed by `ee1c48ca`:

- `flutter_app/test/features/feed/widgets/feed_video_post_view_test.dart`

Commit summary reports 4 files changed, 812 insertions, and 32 deletions (the test file contributes 605 inserted lines).

## Old-branch behavior labels captured

The test file contains the following mapping labels/scenarios for Task 2:

- Managed resume guard / `audio hantu` (inactive origin must not resume; active origin may resume).
- Live volume claim behavior (inactive/background controllers stay silent; unmute only affects active claim).
- Legacy delayed volume/play after dispose.
- Race fix for Feed→Profile while controller is loading or uninitialized.
- `_routeCovered` set immediately on opaque route push, before controller readiness.
- `_appBackgrounded` lifecycle gate and resume state-machine.
- Forced uncover resume through `didPopNext`/`AppLifecycleState.resumed`, without waiting for VisibilityDetector.
- Volume restoration after uncover (`feedMuted=false` restores volume 1; muted restores 0).
- Opaque-aware route behavior: Profile/nested routes keep Feed paused and silent until Feed is uncovered.
- Nested Feed→Profile→Post route: popping only the top nested route must not resume Feed while Profile remains above it.
- Background during navigation: init completion behind an opaque route must not play; foreground alone is insufficient until Feed is uncovered.
- Transparent sheet regression: product/cart/tagged transparent route permits Feed playback/resume behind the sheet.
- Opaque-route contrast: foreground while an opaque route remains above Feed must not resume playback.
- Central `_canAutoplayNow` gate across init, adopt, visibility, comment close, tap, long-press, cinema, and cover-resume paths.
- Debug-only `_logPlay` telemetry records source, route-current, covered, background, and active state.

The matching source comments also explicitly identify “GAP #3” (volume stuck at zero after uncover) and “GAP #4” (controller-null-at-cover requiring forced resume).

## Concerns for Task 2

1. The old commit predates the latest `main` playback architecture. Its diff contains legacy direct `ctrl.play()` paths and must not be applied wholesale without checking current `VideoAudioClaim`/coordinator ownership.
2. `_feedRouteIsCurrent` is intentionally telemetry-only in the old commit; treating `ModalRoute.isCurrent` as a playback gate would regress transparent bottom-sheet playback.
3. The old commit claims 295 tests green and clean analysis (with six pre-existing `use_key` infos), but this result must be independently re-run against current `main` after behavior mapping.
4. The worktree currently contains the task brief as an untracked audit input; this is expected and is not production code.

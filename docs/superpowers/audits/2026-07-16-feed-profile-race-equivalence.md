# Feed–Profile Race Recovery: Behavior-Equivalence Audit

Baseline dibandingkan: old branch commit `ee1c48cae55ad2c111288c2ea9d153d2be07ac7d` terhadap source/test tree pada fetched `origin/main` baseline `82a78e7fc59ee066bbbb311e4529324f6436f110` (fetched 2026-07-16 09:50:01 +07:00). “Setara” berarti perilaku yang diamati dan kontrak regresinya dipertahankan melalui arsitektur state-machine/coordinator/audio-claim yang lebih baru di `main`; ini bukan klaim bahwa implementasi lama dan baru identik secara tekstual.

| Scenario | Old branch evidence | Main implementation | Main test evidence | Status | Gap action |
|---|---|---|---|---|---|
| Controller-loading navigation to Profile | Old tests group `race fix — route push sebelum init selesai` line 1896; test “push route SEBELUM init selesai…” line 1907 | `_routeCovered` is set before pause/init completion (`feed_video_post_view.dart:500`, `754-772`); init listener blocks covered playback (`1021-1041`) | Test line 1907 | setara melalui arsitektur baru | None; keep current gate/claim path |
| Opaque route | Old hardening group line 2121 and opaque toggle test line 2056 | `didPushNext` checks `lastPushedRouteIsOpaque()` and marks `_routeCovered` (`754-772`) | Opaque toggle test line 2056; opaque foreground contrast line 2447 | setara melalui arsitektur baru | None |
| Nested route | Old nested test in hardening group line 2151 | `_routeCovered` remains true until adjacent Feed uncover; `didPopNext` clears it (`774-780`) | Nested Feed→Profile→Postingan test line 2151 | setara melalui arsitektur baru | None |
| Transparent bottom sheet | Old transparent-sheet regression group line 2357 | Opaque-aware route check leaves `_routeCovered` false for transparent route (`646-655`, `754-772`) | Transparent sheet background→foreground test line 2392 | setara melalui arsitektur baru | None |
| Background/foreground | Old background navigation test line 2222 | `_appBackgrounded` lifecycle flag and resume state machine (`506`, `784-800`) | Background navigation test line 2222; opaque foreground test line 2447 | setara melalui arsitektur baru | None |
| Mute restoration | Old GAP #3 assertions in race tests; D1 group line 1499 | Resume restores volume from `feedMuted` (`730-749`); live mute listener applies active-only claim behavior (`854-860`) | Race resume volume assertion lines 2047-2049; D1 tests lines 1529+ | setara melalui arsitektur baru | None |
| Controller-null uncover | Old GAP #4 test line 1989 | `didPopNext`/resumed pass `forceIfUncovered` (`774-800`), allowing resume after null-at-cover | GAP #4 test line 1989 | setara melalui arsitektur baru | None |
| Legacy play paths | Old branch added central `_canAutoplayNow` and telemetry | `_playLegacy` is the gated legacy entry (`573-618`, `633-640`); direct `ctrl.play()` at line 602 is after claim validation | Race and playback contract tests lines 1896-2056 | setara melalui arsitektur baru | None for Feed autoplay |
| Managed coordinator resume | Old managed resume guard group line 1394 | `VideoAudioClaim`, `_claimAudio`, and managed `onRequestPlay` route resume through coordinator (`508-571`, `710-723`) | Managed resume guard tests lines 1428 and 1462; managed contracts group line 1036 | setara melalui arsitektur baru | None |
| Lifecycle/listener cleanup | Old delayed dispose/late notifier scenarios in tests lines 465, 673, 827 | Observer/listeners registered (`438-467`) and removed in `dispose` (`1719-1749`); controller listeners removed (`1567`, `1751`) | Cleanup/race tests lines 465, 673, 827 | setara melalui arsitektur baru | None |

## Direct `.play()` audit

Command:

```powershell
rg -n "\.play\(\)" flutter_app/lib/features/feed/widgets/feed_video_post_view.dart
```

Matches:

- `602`: inside `_playLegacy`; claim validity and `_canAutoplayNow` are checked before this call. This is the managed legacy playback primitive, not a stale bypass.
- `3432`: `FeedVideoCinemaScreen.initState` starts the explicitly opened fullscreen cinema controller. This is an intentional user navigation path, outside Feed autoplay/race recovery.
- `3528`: fullscreen cinema play/pause button; explicitly user initiated and outside Feed autoplay/race recovery.

No actionable stale direct-play path remains in the Feed post state. The main implementation uses `VideoAudioClaim`/coordinator ownership for managed sessions and `_playLegacy` for legacy sessions.

## Spec coverage review

All required rows from `docs/superpowers/specs/2026-07-16-feed-profile-race-equivalence-audit-design.md` are present. Evidence is tied to current source/test line references; no row is inferred from commit history alone.

## Baseline freshness

The audit baseline was refreshed with `git fetch origin --prune` before this report was finalized. The recorded `origin/main` SHA is `82a78e7fc59ee066bbbb311e4529324f6436f110`; rerun the fetch and refresh line references if `origin/main` advances before merge review.

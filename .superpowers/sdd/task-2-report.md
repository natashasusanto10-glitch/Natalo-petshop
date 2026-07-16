# Task 2 report — behavior-equivalence matrix

Status: complete. Created `docs/superpowers/audits/2026-07-16-feed-profile-race-equivalence.md` with 10 required scenarios, exact current source/test line references, the direct `.play()` audit, and spec coverage review.

Commands run:

```powershell
Get-Content -Raw .superpowers\sdd\task-2-brief.md
Get-Content -Raw .superpowers\sdd\task-1-report.md
rg -n "_routeCovered|_appBackgrounded|_canAutoplayNow|VideoAudioClaim|_playLegacy|didPushNext|didPopNext|AppLifecycleState|volume|resume" flutter_app/lib/features/feed/widgets/feed_video_post_view.dart flutter_app/test/features/feed/widgets/feed_video_post_view_test.dart
rg -n "testWidgets\(|group\(" flutter_app/test/features/feed/widgets/feed_video_post_view_test.dart
rg -n "\\.play\\(\\)" flutter_app/lib/features/feed/widgets/feed_video_post_view.dart
git diff --stat main...ee1c48ca
git diff --name-status main...ee1c48ca
```

Findings:

- Current `main` contains the old race behavior, but integrated with the newer claim/coordinator architecture.
- The only Feed-state direct play is line 602 inside `_playLegacy`, after gate/claim validation.
- Lines 3432 and 3528 are intentional fullscreen cinema init/control paths, not stale Feed autoplay paths.
- No production source was modified.

Concerns:

1. Line references are against the current audit worktree snapshot; they must be refreshed if source changes before merge review.
2. The audit does not claim a full Flutter test run; it maps existing tests and source evidence only.
3. The old branch remains unsafe to merge wholesale because its direct-play architecture predates current `VideoAudioClaim`/coordinator ownership.


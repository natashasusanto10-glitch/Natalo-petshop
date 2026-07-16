# Task 2: Feature Flag and Privacy-Safe Collision Sink

Status: PASS

Commit: `88f0d74c` (`feat(feed): add social video observation flag`)

## Changes

- Added the startup-stable `SOCIAL_VIDEO_REGISTRY_OBSERVE` flag with a false default.
- Added deterministic FNV-1a-style `anonymousSocialPostKey` output.
- Added `SocialVideoCollisionMetricSink` with injectable test writer and `AppAnalytics.logEvent` production default.
- Emits only `social_video_controller_collision` with `media_key`, `controller_count`, and allowlisted `surface_names`.
- Coalesces consecutive identical collision summaries; a changed or reappearing summary can be sampled again.
- No raw post IDs, URLs, signed tokens, captions, usernames, or user content are included in metric parameters.

## TDD Evidence

- Focused test was run before production files existed and failed at compilation with the expected missing-library and undefined-symbol errors.
- Production implementation was then added and the focused suite passed.

## Verification

- `flutter test test/features/feed/video/social_video_observation_metrics_test.dart`: 5 tests passed.
- `flutter test test/features/feed/video/social_video_session_observer_test.dart test/features/feed/video/social_video_observation_metrics_test.dart`: 19 tests passed.
- `flutter analyze lib/features/feed/video/social_video_registry_config.dart lib/features/feed/video/social_video_observation_metrics.dart test/features/feed/video/social_video_observation_metrics_test.dart`: no issues found.
- `dart format ...`: passed.
- `git diff --check`: clean.
- Forbidden-field scan of the new metric/config source: no matches.

## Concerns

Task 1's public `SocialVideoCollision` contains no surface collection. The sink therefore accepts an optional enum surface set and emits an empty serialized value when callers do not provide one; Task 3 should supply those surfaces from observer context without expanding the collision payload's privacy surface.

## Task 2 Review Fix

Status: PASS

Fix commit: `c83064760c9f0ce07c403ae6098e9bb7ab9da2e7`

### Findings Fixed

- Firebase parameters now contain only `String` and `num` values; sorted enum surfaces serialize as `main_feed|post_detail`.
- Collision summaries are marked sampled only after the awaited writer succeeds. Writer errors are swallowed and the same summary remains retryable.
- Media keys are accepted only when nonempty, lowercase hexadecimal, and at most 64 characters. Unsafe IDs, URLs, tokens, and captions are dropped before telemetry.
- Caller free-form surface strings were replaced with `Set<SocialVideoSurface>` and an internal enum-to-allowlist mapping.
- Added regression coverage for writer failure and retry, serialized parameter types, enum surface ordering, and unsafe media keys.

### TDD Evidence

- The new tests first failed to compile because the production API did not yet accept `Set<SocialVideoSurface>`.
- After the minimal implementation, the focused suite passed with 7 tests.

### Verification

- `flutter test test/features/feed/video/social_video_observation_metrics_test.dart`: 7 tests passed.
- `flutter analyze lib/features/feed/video/social_video_registry_config.dart lib/features/feed/video/social_video_observation_metrics.dart test/features/feed/video/social_video_observation_metrics_test.dart`: no issues found.
- `dart format lib/features/feed/video/social_video_observation_metrics.dart test/features/feed/video/social_video_observation_metrics_test.dart`: passed.
- `git diff --check`: clean.

# Social Video Registry Observation Runbook

## Purpose and safety boundary

This package observes social-video controller lifecycles on the main Feed,
Profile prewarm/grid, Postingan, and scoped fullscreen surfaces. It detects
overlap when more than one distinct live controller identity exists for the
same post.

The package is passive detection only. It does not reduce controller count,
transfer or arbitrate playback ownership, change preload/cache policy, or call
play, pause, seek, set volume, retry, or dispose. A reported collision is a
diagnostic fact, not an automatic remediation.

When disabled, the process-wide observer is a strict no-op and retains no
observation state. When enabled, lifecycle history and live-controller state
are bounded in memory.

## Build modes

Use these exact compile-time flags:

```text
Default/rollback: --dart-define=SOCIAL_VIDEO_REGISTRY_OBSERVE=false
Canary: --dart-define=SOCIAL_VIDEO_REGISTRY_OBSERVE=true
```

`SOCIAL_VIDEO_REGISTRY_OBSERVE` is read with `bool.fromEnvironment` and
defaults to `false`. It is fixed for the life of the process; changing it
requires a new build or launch. It is not a runtime or remote-config switch.

## Privacy-safe collision metric

The observer sends no lifecycle event stream to Analytics. It emits only the
sampled event `social_video_controller_collision` after detecting two or more
distinct live controller identities for the same post.

The event contains only:

- `media_key`: a deterministic eight-character hexadecimal anonymous key
  derived from the post ID. It is not the raw post ID.
- `controller_count`: the number of distinct live controller identities for
  that anonymous media key.
- `surface_names`: pipe-separated allowlisted names when a surface set is
  supplied (`main_feed`, `profile_grid`, `post_detail`, or `fullscreen`). The
  value is empty when surface context is unavailable. The current application
  singleton collision callback does not supply a surface set, so production
  consumers must currently accept an empty value.

The event never includes media URLs, raw post IDs, controller identities,
owner IDs, captions, usernames, tokens, or user-entered content. Consecutive
identical collision summaries are coalesced. A changed controller set, or a
collision that disappears and later returns, can be sampled again. Analytics
write failures do not interrupt playback or observation and remain eligible
for retry.

## Expected identity lifecycle

A controller identity stays the same when an existing controller is adopted or
attached to another surface. Multiple observations for that same identity are
not a collision. A second distinct live identity for the same post is a
collision until one identity is released or disposed.

| Flow point | Expected observation | Identity expectation |
| --- | --- | --- |
| Feed preload | `created`, then `initialized` | One identity for the actual preload controller. |
| Feed preload adoption | `attached` | Reuses the preload identity; no second `created`. |
| Feed local fallback | `created`, then `initialized` | A distinct still-live preload for the same post may produce a collision. |
| Profile video prewarm | `created`, then `initialized` on `profileGrid` | One coordinator session identity. |
| Profile to Postingan warm claim | `attached` on `postDetail` | Reuses the prewarmed coordinator identity. |
| Postingan without a matching warm claim | `created`, then `initialized` | A new identity may overlap with another still-live surface and be reported. |
| Postingan to fullscreen | `attached` on `fullscreen` | Reuses the coordinator session identity; observation does not transfer ownership. |
| Failure, eviction, or final teardown | `failed` plus `released`, or `disposed` | Removes that identity from the live set. |

## Canary enablement

1. Build the Android and iOS baseline with observation disabled.
2. Build a limited internal Android release and iOS TestFlight canary with
   observation enabled.
3. Record the build numbers and canary audience so metrics can be compared with
   the disabled baseline.
4. Complete every row in the device matrix before expanding the canary.
5. Monitor playback behavior and collision event volume before considering an
   active ownership package.

Observation-enabled and disabled builds must have identical visible playback
behavior. The enabled build adds diagnostics only.

## Device validation matrix

Run the exact navigation path `Feed -> Profile -> Postingan -> fullscreen ->
back` on physical Android and iOS devices. Use the same representative video in
both build modes where possible, and repeat the path enough to exercise preload
adoption and teardown.

| Platform | Build mode | Required path | Pass criteria |
| --- | --- | --- | --- |
| Android physical device | Default/rollback (`false`) | Feed -> Profile -> Postingan -> fullscreen -> back | Baseline playback, audio, navigation, and teardown are correct. |
| Android physical device | Canary (`true`) | Feed -> Profile -> Postingan -> fullscreen -> back | Behavior matches the disabled build; collision events, if any, contain only the allowed fields. |
| iOS physical device/TestFlight | Default/rollback (`false`) | Feed -> Profile -> Postingan -> fullscreen -> back | Baseline playback, audio, navigation, and teardown are correct. |
| iOS physical device/TestFlight | Canary (`true`) | Feed -> Profile -> Postingan -> fullscreen -> back | Behavior matches the disabled build; collision events, if any, contain only the allowed fields. |

For each row, verify:

- video startup, scrolling, mute state, and quality selection remain unchanged;
- entering fullscreen and returning does not restart the wrong post, duplicate
  audio, leave ghost playback, or stall navigation;
- returning through Postingan and Profile to Feed does not leave a controller
  visibly active on the wrong surface;
- enabled and disabled builds show no user-visible behavioral difference; and
- any collision event has `controller_count` greater than one and contains no
  raw post ID or URL.

## Monitoring

During the canary:

1. Compare crash-free sessions and social-video playback regressions between
   disabled and enabled builds.
2. Track `social_video_controller_collision` volume and the distribution of
   `controller_count`. A nonzero value is evidence to investigate, not proof
   that this package changed ownership.
3. Confirm sampled payloads contain only `media_key`, `controller_count`, and
   `surface_names`.
4. Correlate device-matrix notes with build number and platform. Do not use the
   anonymous media key to identify a customer or reconstruct a post ID.
5. Escalate unexpected playback changes immediately because observation is
   intended to be behavior-neutral.

## Rollback

1. Rebuild the affected Android and iOS release with:

   ```text
   --dart-define=SOCIAL_VIDEO_REGISTRY_OBSERVE=false
   ```

2. Deploy the rebuilt artifact through the same canary channel.
3. Fully terminate and relaunch the app so the process uses the new compile-time
   value.
4. Repeat the device path `Feed -> Profile -> Postingan -> fullscreen -> back`.
5. Confirm playback matches the baseline and new processes emit no collision
   events or retain observer state.

An already-built `true` artifact cannot be remotely switched off. Rollback
requires a replacement build or launch compiled with the false flag.

## Automated verification

From `flutter_app`, run:

```powershell
flutter analyze
flutter test test/features/feed/video test/features/feed/widgets/feed_video_post_view_test.dart test/screens/feed_screen_preload_race_test.dart test/screens/feed_screen_preload_observation_test.dart test/screens/public_profile_video_prewarm_test.dart test/screens/scoped_video_feed_screen_test.dart
```

If a final broad suite encounters
`retry sukses -> re-adopt controller baru via revision + render` in
`feed_video_post_view_test.dart`, it is a known pre-existing unrelated retry
test: the managed session does not reach its expected error state after two
create failures. Record it as baseline evidence; do not change playback code as
part of this documentation package.

## Gate before active lease migration

Device validation is a release gate before active lease migration. Do not begin
the package that reduces controller count or changes playback ownership until:

- all four device-matrix rows pass;
- enabled and disabled builds have equivalent playback behavior;
- the metric payload has been verified as privacy-safe;
- collision volume and controller-count patterns have been reviewed;
- rollback has been rehearsed successfully; and
- the release owner accepts the device evidence.

This gate separates passive observation from the later, higher-risk ownership
migration.

# Social Video Registry Observation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add bounded, privacy-safe instrumentation and a passive `postId` registry that detects overlapping social-video controllers without changing playback ownership or behavior.

**Architecture:** A plugin-free passive registry receives immutable lifecycle observations from existing Feed and coordinator-owned controllers. It indexes live controller identities by `postId`, keeps a bounded diagnostic ring buffer, and emits only sampled collision summaries to Analytics; it never receives player command callbacks and therefore cannot play, pause, seek, set volume, retry, or dispose a controller.

**Tech Stack:** Flutter/Dart, `video_player`, existing `AppAnalytics`, `flutter_test`, compile-time Dart feature flags.

## Global Constraints

- Scope is limited to main Feed, Profile prewarm, Postingan, and scoped fullscreen.
- Product, review, admin, upload/edit preview, chat, and local-file players remain outside the registry.
- The first package must not change controller ownership, preload policy, quality selection, mute, audio arbitration, gestures, comment drawer behavior, or playback commands.
- The passive registry must never store or log media URLs, captions, usernames, tokens, or user-entered content.
- Instrumentation memory is bounded and observation can be disabled at process startup with `SOCIAL_VIDEO_REGISTRY_OBSERVE=false`.
- Existing user changes and unrelated worktree files must remain untouched.

---

### Task 1: Passive Registry Core

**Files:**
- Create: `flutter_app/lib/features/feed/video/social_video_session_observer.dart`
- Test: `flutter_app/test/features/feed/video/social_video_session_observer_test.dart`

**Interfaces:**
- Produces: `SocialVideoSurface`, `SocialVideoLifecycleType`, `SocialVideoObservation`, `SocialVideoCollision`, and `SocialVideoSessionObserver`.
- `SocialVideoSessionObserver.observeController(...)` accepts only `postId`, `surface`, `ownerId`, `controllerIdentity`, and lifecycle type.
- `SocialVideoSessionObserver.snapshot` returns immutable diagnostic state.
- The core has no imports from `video_player`, widgets, Firebase, or player session classes.

- [ ] **Step 1: Write failing core tests**

Cover these independent behaviors:

```dart
test('tracks one live controller without reporting a collision', () {
  final observer = SocialVideoSessionObserver(enabled: true);
  final controller = Object();

  observer.observeController(
    type: SocialVideoLifecycleType.created,
    postId: 'post-a',
    surface: SocialVideoSurface.mainFeed,
    ownerId: 'feed-slot-a',
    controllerIdentity: controller,
  );

  expect(observer.snapshot.liveControllerCount, 1);
  expect(observer.snapshot.collisions, isEmpty);
});

test('reports different live controller identities for one post', () {
  final observer = SocialVideoSessionObserver(enabled: true);

  observer.observeController(
    type: SocialVideoLifecycleType.created,
    postId: 'post-a',
    surface: SocialVideoSurface.mainFeed,
    ownerId: 'feed',
    controllerIdentity: Object(),
  );
  observer.observeController(
    type: SocialVideoLifecycleType.created,
    postId: 'post-a',
    surface: SocialVideoSurface.postDetail,
    ownerId: 'detail',
    controllerIdentity: Object(),
  );

  expect(observer.snapshot.collisions.single.postId, 'post-a');
  expect(observer.snapshot.collisions.single.controllerCount, 2);
});

test('disabled observer is a strict no-op', () {
  final observer = SocialVideoSessionObserver(enabled: false);
  observer.observeController(
    type: SocialVideoLifecycleType.created,
    postId: 'post-a',
    surface: SocialVideoSurface.mainFeed,
    ownerId: 'feed',
    controllerIdentity: Object(),
  );
  expect(observer.snapshot.liveControllerCount, 0);
  expect(observer.snapshot.events, isEmpty);
});
```

Also test idempotent disposal, stale duplicate disposal, same-controller attach across two surfaces not being a collision, blank `postId` rejection, immutable snapshots, and a hard event limit of 256.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```powershell
cd flutter_app
flutter test test/features/feed/video/social_video_session_observer_test.dart
```

Expected: compilation failure because `social_video_session_observer.dart` and its public types do not exist.

- [ ] **Step 3: Implement the plugin-free passive registry**

Implement:

```dart
enum SocialVideoSurface { mainFeed, profileGrid, postDetail, fullscreen }

enum SocialVideoLifecycleType {
  created,
  initialized,
  attached,
  activated,
  dormant,
  released,
  disposed,
  failed,
}

class SocialVideoSessionObserver {
  SocialVideoSessionObserver({
    required bool enabled,
    int eventLimit = 256,
    void Function(SocialVideoCollision collision)? onCollision,
  });

  void observeController({
    required SocialVideoLifecycleType type,
    required String postId,
    required SocialVideoSurface surface,
    required String ownerId,
    required Object controllerIdentity,
  });

  SocialVideoObserverSnapshot get snapshot;
  void clear();
}
```

Use `Expando<int>` plus a monotonic sequence for process-local controller IDs. Keep maps private. Never serialize `controllerIdentity`. Coalesce repeated identical collision sets so one overlap does not emit on every attach event.

- [ ] **Step 4: Run formatter and focused tests**

```powershell
dart format lib/features/feed/video/social_video_session_observer.dart test/features/feed/video/social_video_session_observer_test.dart
flutter test test/features/feed/video/social_video_session_observer_test.dart
```

Expected: all observer tests pass.

- [ ] **Step 5: Commit Task 1**

```powershell
git add flutter_app/lib/features/feed/video/social_video_session_observer.dart flutter_app/test/features/feed/video/social_video_session_observer_test.dart
git commit -m "feat(feed): add passive social video observer"
```

### Task 2: Feature Flag and Privacy-Safe Collision Sink

**Files:**
- Create: `flutter_app/lib/features/feed/video/social_video_registry_config.dart`
- Create: `flutter_app/lib/features/feed/video/social_video_observation_metrics.dart`
- Test: `flutter_app/test/features/feed/video/social_video_observation_metrics_test.dart`

**Interfaces:**
- Consumes: `SocialVideoCollision` from Task 1.
- Produces: `socialVideoRegistryObservationEnabled`, `anonymousSocialPostKey(String)`, and `SocialVideoCollisionMetricSink`.
- The metric sink accepts an injected event writer for tests and defaults to `AppAnalytics.logEvent` in production.

- [ ] **Step 1: Write failing configuration and privacy tests**

Tests must prove:

```dart
test('post keys are stable and do not expose source text', () {
  final first = anonymousSocialPostKey('post-secret-123');
  final second = anonymousSocialPostKey('post-secret-123');
  expect(first, second);
  expect(first, isNot(contains('post-secret-123')));
});

test('collision metric contains no URL or raw post id', () async {
  final events = <Map<String, Object>>[];
  final sink = SocialVideoCollisionMetricSink(
    writeEvent: (name, params) async => events.add({'name': name, ...params}),
  );

  await sink.record(collisionFixture(postId: 'private-post'));

  expect(events.single['media_key'], isNot('private-post'));
  expect(events.single.keys, isNot(contains('url')));
  expect(events.single.keys, isNot(contains('post_id')));
});
```

Also test surface names, controller count, and repeated collision sampling/coalescing.

- [ ] **Step 2: Run the focused test and verify RED**

```powershell
cd flutter_app
flutter test test/features/feed/video/social_video_observation_metrics_test.dart
```

Expected: compilation failure because config and metric sink do not exist.

- [ ] **Step 3: Implement startup-stable config and metric sink**

Use:

```dart
const bool socialVideoRegistryObservationEnabled = bool.fromEnvironment(
  'SOCIAL_VIDEO_REGISTRY_OBSERVE',
  defaultValue: false,
);
```

Implement a deterministic non-cryptographic anonymous key equivalent to the existing video metric convention. Emit only `social_video_controller_collision` with anonymous media key, controller count, and surface names. Do not emit every lifecycle event to Firebase.

- [ ] **Step 4: Format and run Task 1-2 tests**

```powershell
dart format lib/features/feed/video/social_video_registry_config.dart lib/features/feed/video/social_video_observation_metrics.dart test/features/feed/video/social_video_observation_metrics_test.dart
flutter test test/features/feed/video/social_video_session_observer_test.dart test/features/feed/video/social_video_observation_metrics_test.dart
```

Expected: all tests pass.

- [ ] **Step 5: Commit Task 2**

```powershell
git add flutter_app/lib/features/feed/video/social_video_registry_config.dart flutter_app/lib/features/feed/video/social_video_observation_metrics.dart flutter_app/test/features/feed/video/social_video_observation_metrics_test.dart
git commit -m "feat(feed): add social video observation flag"
```

### Task 3: Application Observer Instance and Coordinator Session Hooks

**Files:**
- Modify: `flutter_app/lib/features/feed/video/social_video_session_observer.dart`
- Modify: `flutter_app/lib/features/feed/video/video_player_session.dart`
- Modify: `flutter_app/lib/features/feed/video/post_video_warm_handoff.dart`
- Test: `flutter_app/test/features/feed/video/video_player_session_observation_test.dart`
- Modify test: `flutter_app/test/features/feed/video/post_video_warm_handoff_test.dart`

**Interfaces:**
- Consumes: registry core and metric sink from Tasks 1-2.
- Produces: singleton `socialVideoSessionObserver` and optional `SocialVideoObservationContext` accepted by `VideoPlayerSession`.
- Existing constructors remain source-compatible; observation parameters are optional.

- [ ] **Step 1: Write failing `VideoPlayerSession` lifecycle tests**

Inject a test observer and debug player operations. Verify that successful init records created/initialized, failed init records failed, and idempotent session disposal records disposed once. Verify the observer cannot invoke debug play, pause, seek, volume, retry, or dispose callbacks merely from observation.

Use a context shaped as:

```dart
const SocialVideoObservationContext(
  postId: 'post-a',
  surface: SocialVideoSurface.postDetail,
  ownerId: 'coordinator-post-a',
)
```

- [ ] **Step 2: Run tests and verify RED**

```powershell
cd flutter_app
flutter test test/features/feed/video/video_player_session_observation_test.dart test/features/feed/video/post_video_warm_handoff_test.dart
```

Expected: compilation failure because observation context injection does not exist.

- [ ] **Step 3: Add passive lifecycle hooks**

- Add optional observer/context constructor parameters to `VideoPlayerSession`.
- Record actual controller identity after the controller exists, initialized after successful initialization, failed after terminal initialization failure, and disposed after real disposal.
- In debug seams without a native controller, use a private stable identity owned by that session instance.
- Have `PostVideoWarmHandoff.create` label prewarm sessions as `profileGrid`.
- Have the existing Postingan session factory label sessions as `postDetail`; fullscreen attachment remains the same controller and must record `attached`, not `created`.
- Do not change any player command ordering.

- [ ] **Step 4: Format and run coordinator-focused regression tests**

```powershell
dart format lib/features/feed/video/social_video_session_observer.dart lib/features/feed/video/video_player_session.dart lib/features/feed/video/post_video_warm_handoff.dart test/features/feed/video/video_player_session_observation_test.dart test/features/feed/video/post_video_warm_handoff_test.dart
flutter test test/features/feed/video/video_player_session_observation_test.dart test/features/feed/video/post_video_warm_handoff_test.dart test/features/feed/video/post_video_coordinator_test.dart test/screens/public_profile_video_prewarm_test.dart test/screens/scoped_video_feed_screen_test.dart
```

Expected: all tests pass and playback tests remain unchanged.

- [ ] **Step 5: Commit Task 3**

```powershell
git add flutter_app/lib/features/feed/video/social_video_session_observer.dart flutter_app/lib/features/feed/video/video_player_session.dart flutter_app/lib/features/feed/video/post_video_warm_handoff.dart flutter_app/test/features/feed/video/video_player_session_observation_test.dart flutter_app/test/features/feed/video/post_video_warm_handoff_test.dart
git commit -m "feat(feed): observe coordinated video sessions"
```

### Task 4: Main Feed Legacy Controller Observation

**Files:**
- Create: `flutter_app/lib/features/feed/video/feed_video_observation.dart`
- Modify: `flutter_app/lib/screens/feed_screen.dart`
- Modify: `flutter_app/lib/features/feed/widgets/feed_video_post_view.dart`
- Test: `flutter_app/test/screens/feed_screen_preload_observation_test.dart`
- Modify test: `flutter_app/test/features/feed/widgets/feed_video_post_view_test.dart`

**Interfaces:**
- Consumes: singleton observer and observation context.
- Feed preload creation records `created` once per actual controller identity.
- Preload adoption records `attached` for the same identity; it never records a second `created` event.
- Local view initialization records lifecycle events under `mainFeed`.

- [ ] **Step 1: Write failing preload/adoption tests**

Define plugin-free `observeFeedPreloadCreated`, `observeFeedPreloadAdopted`,
`observeFeedControllerFailed`, and `observeFeedControllerDisposed` helpers in
`feed_video_observation.dart`, then verify:

```dart
test('adopting a preloaded controller keeps one observed identity', () {
  final observer = SocialVideoSessionObserver(enabled: true);
  final controller = Object();

  observeFeedPreloadCreated(observer, postId: 'post-a', controller: controller);
  observeFeedPreloadAdopted(observer, postId: 'post-a', controller: controller);

  expect(observer.snapshot.liveControllerCount, 1);
  expect(observer.snapshot.collisions, isEmpty);
});
```

Also prove eviction/disposal removes the correct identity, failed preload does not remain live, and local controller creation collides with a distinct still-live preload controller for the same post.

- [ ] **Step 2: Run tests and verify RED**

```powershell
cd flutter_app
flutter test test/screens/feed_screen_preload_observation_test.dart test/features/feed/widgets/feed_video_post_view_test.dart
```

Expected: failure because Feed observation helpers/hooks do not exist.

- [ ] **Step 3: Instrument existing Feed lifecycle without changing ownership**

- Observe HLS and MP4 preload controllers only after an actual controller identity exists.
- Observe preload adoption with the same identity.
- Observe local controller creation, successful initialization, terminal failure, and final disposal.
- Preserve `SingleDisposeGuard`, wrapper disposal ordering, preload generation checks, cache behavior, and all current maps.
- Observation calls must be guarded by the startup-stable flag through the singleton; do not add widget rebuild listeners.

- [ ] **Step 4: Run Feed regression suite**

```powershell
dart format lib/features/feed/video/feed_video_observation.dart lib/screens/feed_screen.dart lib/features/feed/widgets/feed_video_post_view.dart test/screens/feed_screen_preload_observation_test.dart test/features/feed/widgets/feed_video_post_view_test.dart
flutter test test/screens/feed_screen_preload_observation_test.dart test/screens/feed_screen_preload_race_test.dart test/features/feed/widgets/feed_video_post_view_test.dart test/features/feed/video/adaptive_video_preload_policy_test.dart
```

Expected: all tests pass; preload ownership and playback behavior remain unchanged.

- [ ] **Step 5: Commit Task 4**

```powershell
git add flutter_app/lib/features/feed/video/feed_video_observation.dart flutter_app/lib/screens/feed_screen.dart flutter_app/lib/features/feed/widgets/feed_video_post_view.dart flutter_app/test/screens/feed_screen_preload_observation_test.dart flutter_app/test/features/feed/widgets/feed_video_post_view_test.dart
git commit -m "feat(feed): observe main feed video controllers"
```

### Task 5: Final Verification and Operational Documentation

**Files:**
- Modify: `flutter_app/README.md`
- Create: `docs/operations/social-video-registry-observation.md`

**Interfaces:**
- Documents the Dart define, expected collision metric, rollback, and TestFlight/device validation.
- No production behavior changes.

- [ ] **Step 1: Document enablement and rollback**

Document these exact build modes:

```text
Default/rollback: --dart-define=SOCIAL_VIDEO_REGISTRY_OBSERVE=false
Observation canary: --dart-define=SOCIAL_VIDEO_REGISTRY_OBSERVE=true
```

Explain that the first package detects overlap only and must not reduce controller count yet. Include the Android/iOS navigation matrix Feed -> Profile -> Postingan -> fullscreen -> back.

- [ ] **Step 2: Run static analysis and focused social playback suite**

```powershell
cd flutter_app
flutter analyze
flutter test test/features/feed/video test/features/feed/widgets/feed_video_post_view_test.dart test/screens/feed_screen_preload_race_test.dart test/screens/feed_screen_preload_observation_test.dart test/screens/public_profile_video_prewarm_test.dart test/screens/scoped_video_feed_screen_test.dart
```

Expected: analyzer exits 0 and all focused tests pass.

- [ ] **Step 3: Review the complete diff**

Verify:

- no controller command is referenced from passive registry files;
- no raw post ID or URL enters Analytics parameters;
- every listener/resource added by this package is bounded or removed;
- feature flag false produces no retained observation state;
- no unrelated files are staged;
- no playback, cache, quality, or preload ordering changed.

- [ ] **Step 4: Commit documentation and any review fixes**

```powershell
git add flutter_app/README.md docs/operations/social-video-registry-observation.md
git commit -m "docs: document social video observation rollout"
```

- [ ] **Step 5: Device gate before ownership migration**

Build Android and iOS once with observation disabled and once enabled. Confirm identical playback behavior and inspect collision reports during repeated Feed -> Profile -> Postingan -> fullscreen navigation. Do not begin active lease migration until this gate is accepted.

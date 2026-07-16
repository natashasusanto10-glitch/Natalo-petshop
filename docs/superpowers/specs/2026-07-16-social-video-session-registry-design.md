# Social Video Session Registry Design

**Date:** 2026-07-16

**Status:** Proposed for user review

**Scope:** Flutter social video surfaces only

## 1. Purpose

Natalo currently has mature but separate playback ownership systems:

- the main Feed owns its preload controller maps;
- Profile prepares a `PostVideoWarmHandoff` for a selected post;
- Postingan owns a local `PostVideoCoordinator`;
- scoped fullscreen borrows sessions from that coordinator;
- `VideoAudioArbiter` and the mute preference are already application-wide.

This works well inside each flow, but the same `postId` can still be represented by more than one controller across Feed, Profile, and Postingan. The proposed architecture creates one bounded session registry for social videos so those surfaces can eventually transfer playback ownership without creating a second controller.

The migration must preserve current playback behavior and be reversible at every release stage.

## 2. Scope

### Included

- main Feed;
- own and public Profile grids;
- Postingan detail;
- scoped fullscreen feed opened from Profile or Postingan;
- social-video preload and frozen-frame presentation;
- existing global mute and audio focus behavior.

### Excluded

- product detail video;
- product grid video;
- review photo/video viewers;
- admin product media;
- upload, trim, edit, and preview players;
- chat media;
- local files that have not yet become a Feed post.

Excluded players continue to use their current local lifecycle and may still compete for audio through the existing application audio arbiter where applicable.

## 3. Current Baseline

The new registry must build on, not replace indiscriminately, the following proven behavior:

- `PostVideoCoordinator` provides single-owner session disposal for Postingan to fullscreen;
- `PostVideoWarmHandoff` prewarms the selected Profile video;
- the main Feed has network-aware bounded preload behavior;
- `VideoAudioArbiter` permits only the current claim to emit audio;
- `appSettingsStore.feedMuted` is the global mute preference;
- dormant and inactive sessions are already expected to remain paused and muted;
- HLS and MP4 use different creation and cache paths;
- frame-output and playback-stall recovery already exist in the video view.

The first release must not alter any of these behaviors.

## 4. Target Architecture

`SocialVideoSessionRegistry` is an application-scoped service keyed by `postId`.

Each entry contains:

- one playback session/controller identity;
- the resolved media URL and quality variant identity;
- initialization and error state;
- last known playback position;
- active lease token and generation;
- attached surface records;
- pin and transfer state;
- last-used sequence for LRU eviction;
- optional frozen-frame or thumbnail metadata.

Surfaces request a `SocialVideoLease`. They do not dispose registry-owned controllers directly.

The registry owns session creation and disposal only after a migration flag gives it active ownership for that surface. During observation mode it records legacy controllers but cannot control or dispose them.

## 5. Session State Model

Registry-owned sessions use these states:

```text
absent -> creating -> ready -> active
                           -> dormant
                           -> preloaded
                           -> transferring
                           -> error
                           -> disposing -> disposed
```

Rules:

1. A `postId` has at most one registry-owned session.
2. Only one active lease exists for a session.
3. Multiple surfaces may remain attached for rendering metadata, but non-active surfaces are dormant.
4. Dormant surfaces render a frozen frame or thumbnail and cannot call play, pause, seek, volume, retry, or visibility playback methods.
5. Only the registry disposes registry-owned sessions.
6. Active, attached, pinned, and transferring sessions cannot be evicted.
7. New sessions start paused and muted.
8. Only the active lease can request playback and audio focus.
9. Global unmute never raises the volume of a dormant or preloaded session.

## 6. Lease Contract

A lease contains:

- `postId`;
- surface identifier;
- opaque lease token;
- session generation;
- read-only session/controller view required for rendering;
- commands routed through the registry: activate, play, pause, seek, retry, and release.

Every mutating command validates both token and generation. A stale lease becomes a no-op and cannot pause, seek, release, or dispose the current owner.

Lease release is idempotent. A route teardown, delayed callback, or duplicate `dispose` cannot release a newer lease.

## 7. Transfer Protocol

For a Feed to Profile to Postingan transfer:

1. The destination requests a lease for the same `postId`.
2. The registry marks the session as transferring and pins it.
3. The source receives a dormant notification and disables playback visibility callbacks.
4. The source records or supplies its frozen frame.
5. Pending source playback operations are invalidated by generation.
6. The destination lease becomes active at the same timestamp.
7. The transfer pin is removed after the destination acknowledges attachment.
8. The source stays dormant until it becomes active again or detaches.

If transfer fails, the registry either restores the source lease or leaves both surfaces on a thumbnail. It must never create a hidden second controller as fallback.

## 8. Capacity and Eviction

The initial hard limit is four registry-owned social sessions:

- one active session;
- one previous candidate;
- up to two forward candidates.

LRU eviction applies only to sessions that are dormant, detached, unpinned, and not transferring. On memory pressure, preload sessions are removed first. The active session is paused when the application enters background but is not immediately evicted.

The limit is configuration, not a UI preference. It may be reduced after device telemetry, especially on low-memory Android devices.

## 9. Feature Flags

Migration uses independent startup-stable flags:

- `social_video_registry_observe`;
- `social_video_registry_profile`;
- `social_video_registry_post`;
- `social_video_registry_feed`;
- `social_video_registry_preload`.

Flags are evaluated before a surface creates its first video session and remain fixed for that surface lifetime. Runtime flag changes cannot migrate a live session between legacy and registry ownership.

If an active ownership flag is disabled, the entire affected flow uses its legacy path. Mixed ownership within one route is forbidden.

## 10. Migration Stages

### Stage A: Instrumentation

- assign diagnostic session IDs to social controllers;
- record create, initialize, attach, activate, transfer, pause, release, and dispose events;
- record live controller count by `postId` and surface;
- detect duplicate social controllers and stale callbacks;
- keep all existing ownership unchanged.

### Stage B: Passive Registry

- register legacy session observations by `postId`;
- report collisions and lifetime overlap;
- expose debug/test snapshots;
- do not call player methods and do not dispose controllers.

Stages A and B form the first implementation package and are safe to ship for measurement.

### Stage C: Profile to Postingan

- replace `PostVideoWarmHandoff` ownership with a registry lease;
- retain one-candidate `onTapDown` prewarm and scroll cancellation;
- make Profile dormant during Postingan playback.

### Stage D: Postingan to Fullscreen

- adapt `PostVideoCoordinator` to registry leases;
- preserve scoped fullscreen preload, retry, mute, pause, edge-back, comment drawer, and timestamp return behavior.

### Stage E: Main Feed

- move Feed active and preload sessions into the registry;
- replace controller maps only after device validation of Stages C and D;
- preserve the existing adaptive preload and quality-selection policies unchanged.

### Stage F: Legacy Removal

- remove superseded handoff and ownership paths;
- retain rollback flags for at least one additional release;
- remove flags only after Android and iOS soak tests show no regression.

## 11. Observability and Privacy

Diagnostic events contain technical identifiers and performance values only:

- hashed or internal `postId`;
- generated session ID;
- surface type;
- state transition;
- controller count;
- timestamps and durations;
- network tier and quality preference;
- error class without media URL query parameters.

Signed media URLs, access tokens, captions, usernames, and user-entered content must not be logged.

Release telemetry is sampled and bounded. Debug builds may retain a short in-memory ring buffer for developer inspection.

## 12. Failure and Rollback Behavior

- Registry observation failure must never block legacy playback.
- Active registry failure renders a frozen frame or thumbnail with retry.
- A failed transfer cannot silently create another controller.
- App background pauses and mutes all registry-owned sessions.
- Logout, account change, and app teardown dispose all registry-owned sessions.
- Expired URLs use the existing resolve/retry mechanism while preserving the lease generation contract.
- Feature-flag rollback occurs only on the next clean route/session start.

## 13. Verification Strategy

### Unit tests

- one session per `postId`;
- one active lease per session;
- stale token and generation rejection;
- idempotent release and dispose;
- transfer success, cancellation, and source restoration;
- LRU protection and four-session hard limit;
- active-only audio permission;
- background pause behavior;
- passive registry never mutates a legacy session.

### Widget and integration tests

- Profile prewarm cancellation on scroll;
- Profile to Postingan timestamp preservation;
- Postingan to fullscreen handoff and return;
- dormant surface ignores visibility and user playback commands;
- rapid tap, rapid back, route replacement, comment drawer, and app lifecycle races;
- expired URL retry without duplicate controller creation.

### Device verification

- current and older supported iOS devices;
- low-memory and modern Android devices;
- Wi-Fi, stable 4G, weak mobile data, and Data Saver;
- 15 to 20 minute repeated navigation and swipe soak tests;
- memory, native player count, startup time, buffering, frame stalls, and background audio.

## 14. Acceptance Criteria for the First Package

The first package is complete when:

1. Existing playback behavior is unchanged with observation enabled or disabled.
2. Every social controller lifecycle can be attributed to a session ID, `postId`, and surface.
3. Duplicate controllers for the same `postId` are detected and measured.
4. The passive registry never invokes play, pause, seek, volume, retry, or dispose.
5. Logs redact signed URL data and user content.
6. Instrumentation has bounded memory and negligible release overhead.
7. Existing Feed, Profile, Postingan, fullscreen, mute, preload, and stall-recovery tests continue to pass.
8. The feature flag can disable all new observation behavior on the next clean app/session start.

## 15. Explicit Non-Goals for the First Package

- no ownership transfer;
- no replacement of `PostVideoWarmHandoff`;
- no changes to Feed preload policy;
- no changes to video quality selection;
- no changes to comment drawer or gesture behavior;
- no changes to product media players;
- no controller-count reduction yet.

The first package exists to establish trustworthy evidence before ownership migration begins.

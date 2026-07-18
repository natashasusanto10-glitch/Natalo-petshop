# Postingan Full-Page Zoom Transition Design

## Status

Approved in discussion on 2026-07-18.

## Summary

Replace the current generic origin-expansion behavior for Profile-to-Postingan
navigation with a dedicated full-page zoom transition. The transition treats
the entire Postingan page as one composited surface, follows native back input
on each platform, and returns to the thumbnail for the post currently visible
in Postingan.

The existing `+`-to-composer origin transition remains separate and retains
its current behavior.

## Problem

The current route captures the tapped grid tile, keeps that snapshot fixed at
the source, and reveals the live destination page through a growing clip. This
causes the Profile page, Postingan app bar, media, and other destination chrome
to appear as overlapping fragments during the transition.

Additional contributors are:

- Postingan initially lays out at index zero and corrects to a nonzero target
  after the first frame.
- Snapshot capture through `RenderRepaintBoundary.toImage` is awaited before
  navigation starts.
- Destination image fades and video initialization can run during the route
  animation.
- One generic route currently serves two incompatible interactions: a page
  reveal from `+` and a full-page zoom from a post thumbnail.
- Opening Postingan explicitly triggers haptic feedback in three entry paths.

## Goals

- Make the entire Postingan page move as one coherent surface.
- Open from the tapped thumbnail without clipped or duplicated destination
  chrome.
- Return to the thumbnail for the post currently visible in Postingan when
  that post still exists and has a valid source target; never animate back to
  the originally tapped post as a substitute.
- Use an interactive left-edge back gesture on iOS.
- Use Android system back and Predictive Back input on Android, including
  left- and right-edge system gestures.
- Preserve current photo, carousel, video, pagination, like, comment, share,
  caption, and video-session behavior.
- Remove haptic feedback only from the action that opens Postingan.
- Keep the route responsive at 60 Hz and suitable for 120 Hz devices.

## Non-goals

- Rebuilding the Postingan screen layout.
- Changing feed ranking, post ordering, API contracts, or backend data.
- Changing the `+` composer transition.
- Copying private Instagram implementation details pixel-for-pixel.
- Removing haptics from like, comment, share, menu, mute, retry, or
  double-tap-like actions.
- Introducing a new global navigation or feed state store.

## Chosen Approach

Create a dedicated `PostPageZoomRoute` and a route-scoped
`PostDetailTransitionSession`.

The route animates a single `RepaintBoundary` containing the complete
destination page. The source Profile remains mounted beneath the non-opaque
route so it can be revealed during an interactive back gesture. A clean media
proxy bridges the first and last portion of the transition; the full
destination is transformed rather than exposed through a moving window.

This was chosen over:

1. Adding another mode to the generic origin route. That would keep the `+`
   and Postingan behaviors coupled and repeat the regression risk.
2. Replacing the interaction with a standard fade or slide. That would be
   stable but would not meet the approved full-page zoom behavior.

## Architecture

### `PostPageZoomRoute`

Owns only navigation and visual transition state:

- Forward full-page zoom.
- Non-interactive reverse zoom.
- iOS interactive edge-back preview, cancellation, and commit.
- Android Predictive Back preview, cancellation, and commit.
- Fallback close when a valid destination thumbnail cannot be prepared.
- Repeated-open and repeated-pop protection.

It must not fetch posts, change profile filters directly, or own feed data.

### `PostDetailTransitionSession`

A route-scoped coordinator created by the source Profile screen and shared by
the source, route, and `MemberPostDetailScreen`.

Its conceptual contract is:

- Report the currently dominant post.
- Report pages loaded by Postingan pagination.
- Ask the source Profile to prepare the current post's grid tile.
- Freeze the current post ID, thumbnail proxy, and target rectangle when a
  back interaction begins.
- Resume target tracking after a canceled interaction.
- Dispose all listeners when the route completes.

The session prevents the route from reaching into source screen state and
avoids a new global singleton.

### Source Profile adapter

Each source screen owns its own data and scroll mechanics and exposes a small
adapter to the session:

- Merge a scoped pagination page, deduplicated by post ID.
- Prepare a given post in the appropriate grid and tab.
- Resolve a prepared tile rectangle from its stable key.
- Suppress or restore the target tile while the proxy overlaps it.

The three supported sources are:

- Own Profile (`member_screen.dart`).
- Public Profile (`public_profile_screen.dart`).
- Postingan Saya (`member_posts_screen.dart`).

### Destination readiness

`MemberPostDetailScreen` must expose readiness for the selected initial post.
Before its first build, it computes the existing estimated offset and supplies
that value through `ScrollController.initialScrollOffset`. The destination is
then laid out with opacity zero while the clean source proxy remains visible.
After layout, a zero-duration key-based correction runs until the target top is
within one logical pixel of its anchor.

The readiness stage is bounded to three end-of-frame passes or 75 ms,
whichever comes first. If it misses that bound, the route abandons geometry
zoom for that opening and uses a 160 ms crossfade only after the destination is
stable. It must never expose index zero and visibly jump to the target.

The current visible jump from index zero followed by post-frame
`jumpTo`/`ensureVisible` is not permitted during the transition.

## Active Post and Return Target

### Selecting the active post

Every Postingan item reports visibility. The active candidate is the item with
the largest visible area. To avoid oscillation at item boundaries:

- Prefer a candidate that is at least 55% visible.
- Switch only when it exceeds the current item's visible fraction by at least
  10 percentage points.
- When no item reaches 55% after scrolling settles, choose the item whose
  media center is closest to the viewport center.
- Notify the session only when the active post ID changes.

While a fling is still active and no candidate reaches 55%, retain the current
active post. Compute candidates at most once per frame and, where practical,
measure only the current item and its immediate neighbors instead of adding an
independent continuously firing detector to every list item.

### Preparing post B behind the destination

When the user opens post A and scrolls to post B:

1. Postingan reports B to the transition session.
2. Any newly loaded pagination page is forwarded to the source adapter; the
   source merges it without a duplicate network request.
3. While Postingan fully covers the screen, the source silently positions its
   grid so B is fully visible below pinned chrome and above bottom navigation.
4. Lazy grids first jump to an index-derived row using the shared profile grid
   geometry, then verify the exact rectangle after the tile is built.
5. Async preparation uses a generation token so a late result for A cannot
   replace a newer result for B.

Pagination loaders must preserve the originating source scope so B normally
remains representable in the same grid. If legacy mixed-scope pagination has
already exposed a B that cannot exist in the origin tab, selecting the source's
`Semua` scope is an explicit compatibility fallback; the resulting tab remains
visible after pop so the user can see B rather than returning to an unrelated
tile.

Any source refresh performed after route completion must merge with the
session's loaded extent until B is retained. It must not immediately replace
the source with only its first page and make the just-returned B disappear.

The compatibility switch to `Semua` is not restored after pop: remaining on
`Semua` is the explicit fallback UX because it is the only source grid that can
truthfully display B. Normal scoped pagination must not trigger this fallback.

### Freezing the target

At the first back-progress event, or before a non-interactive back animation,
the session freezes:

- Active post ID B.
- Latest valid B tile rectangle.
- B thumbnail or video poster proxy.
- Viewport and text-direction geometry.

No scroll, pagination completion, or visibility callback may retarget the
ongoing gesture. A canceled gesture unfreezes the session only after the page
has settled back to fullscreen.

## Forward Animation

The approved target duration is approximately 300 ms. Timing can be tuned from
device traces, but the ordering is fixed:

1. Resolve the source tile rectangle and clean cached media proxy. Do not await
   `toImage` on the tap path.
2. Lay out Postingan at the correct initial post while the proxy still covers
   the source.
3. Transform the complete destination surface from the source geometry to the
   fullscreen viewport using translation and uniform scale.
4. Interpolate the clipping bounds without non-uniformly stretching the
   destination surface.
5. Crossfade the clean proxy into the complete destination during the first
   portion of the flight.
6. Settle the surface at scale `1.0`, offset zero, and corner radius zero.
7. Unlock interactions and allow video playback only after the route reaches
   the completed state.

All geometry uses logical pixels in the root Navigator overlay coordinate
space. The application surface keeps its native fullscreen aspect ratio and
uses a uniform width-derived scale. Its top-left is translated between the
source and fullscreen top-left positions. An independent `RRect` clip tweens
from the source tile bounds to the fullscreen application bounds, so the
surface is never non-uniformly stretched. The proxy uses `BoxFit.cover` inside
the same animated clip.

Proxy selection is synchronous and never blocks the first motion:

1. Reuse an already-resolved image stream or video poster retained by the
   visible source tile.
2. Otherwise use an image provider only when its frame is already available
   from memory cache.
3. Otherwise use the deterministic theme placeholder for both ends of the
   first flight and let destination media appear after completion.

System status and navigation indicators remain platform-owned and are not
scaled as part of the application surface. Their overlay style must not flash
or switch midway through the route.

The open curve should be a non-bouncy emphasized deceleration. The existing
`Cubic(0.05, 0.7, 0.1, 1.0)` is an acceptable initial value; structural
correctness takes priority over further curve tuning.

## Reverse Animation

### Header back, Android 3-button back, and non-predictive system back

- Freeze the prepared target B.
- Animate the full surface to B over approximately 250-280 ms.
- Crossfade to B's clean proxy near the terminal portion.
- Reveal the already-positioned source Profile beneath it.
- Restore the real B tile and dispose the route after the proxy reaches B.

### iOS interactive edge back

- Recognize only the logical leading-edge gesture using iOS route semantics;
  this is the physical left edge for the app's current left-to-right locale.
- While the finger is down, use linear gesture progress rather than an easing
  curve.
- Translate the full surface with the finger, scale it from `1.0` toward an
  approximate preview minimum of `0.92`, and increase corner radius from zero
  toward approximately 28-32 logical pixels.
- Keep the prepared Profile visible beneath the surface.
- On cancel, spring the exact current transform back to fullscreen with no
  visual restart.
- On commit, continue from the exact current transform to B over approximately
  180-240 ms.

The commit threshold should initially match the existing route behavior: about
25% horizontal completion or a fling near 800 logical pixels per second. It
must be tuned from device testing rather than changed to hide rendering bugs.

### Android Predictive Back

- Do not install the iOS pointer recognizer on Android.
- The dedicated PageRoute participates in Flutter's predictive-route hooks and
  exposes an ahead-of-time pop disposition compatible with `PopScope`.
- Consume Flutter Predictive Back progress from the system and respect the
  reported left or right swipe edge. Do not stack a second global handler or a
  generic Material transition builder around the custom route.
- Drive the same coherent surface preview with system progress.
- Follow system cancellation progress back to fullscreen.
- On commit, continue to the frozen B target without restarting geometry.
- When Predictive Back is unavailable, run the non-interactive reverse path.

The route handles Predictive Back only while it is the current top route and
its synchronous pop disposition allows it. A modal sheet above Postingan owns
the first back event; the custom route must not observe or animate that event.

The repository currently uses Flutter 3.41.9 locally and already enables
`android:enableOnBackInvokedCallback`. Implementation must keep CI and the
declared Flutter constraint on a version that supports the required
Predictive Back APIs; at minimum, it must not claim compatibility with the
current `>=3.7.0` lower bound while using newer APIs.

## Haptics

Remove navigation-entry feedback from all three origin flows:

- Own Profile.
- Public Profile.
- Postingan Saya.

Disable default tile feedback where an `InkWell` could still emit platform
feedback. Do not add haptics at gesture start, cancel, or commit. Existing
action haptics inside Postingan remain unchanged.

## Media Rules

- Photo and carousel use the same cached image provider for the grid proxy and
  the first destination frame.
- Destination image shimmer or fade must not compete with the route flight.
- Video uses its thumbnail/poster throughout the route flight.
- The existing warm video handoff remains the only playback session passed to
  Postingan; the transition must not create another controller.
- Playback starts or resumes only after forward completion.
- A reverse transition pauses the active video before moving the surface.
- Backgrounding the app during a gesture must leave the route in a terminal
  open or closed state with no ghost audio.

## Fallback and Error Handling

Never animate to the original post A or a stale rectangle when B is the active
post.

Use a short fade plus mild centered scale when any of these is true:

- B was deleted or removed.
- The source route was disposed.
- The source tab cannot be prepared.
- A paginated B cannot be merged.
- The B tile remains unbuilt or offscreen after bounded preparation.
- Its measured rectangle is empty, outside the viewport, or belongs to an old
  layout generation.
- Device metrics change during the transition.

A failed thumbnail image may still use a valid B tile rectangle with the
standard placeholder proxy. Before disposing the session, it may assign a
`pendingReturnPostId` to the source adapter. The source screen, not the disposed
session, owns that bounded best-effort positioning after a fallback pop.

If a comment sheet or another modal is above Postingan, the first system back
closes that modal. The Postingan transition handles back only when it is the
top route and its pop disposition allows it.

If the application backgrounds or device metrics change during an interactive
gesture, cancel the gesture and restore the stable fullscreen `open` state.
Pause media while inactive and remeasure targets after resume; never auto-close
the route because of rotation, resizing, or lifecycle interruption.

### Source tile suppression

- During opening, attach the proxy first, then suppress A only while the proxy
  would otherwise duplicate it. Restore A after Postingan fully covers the
  source.
- During interactive preview, keep B visible in the revealed Profile.
- Suppress B only in the terminal portion when the closing surface/proxy
  overlaps B.
- At terminal completion, crossfade the proxy to the real B tile, restore B,
  and only then remove the route overlay.
- Cancellation and all fallback paths restore any suppressed tile before
  returning to `open` or completing the pop.

## Performance and Accessibility

### Performance requirements

- Animate compositor-friendly transform, opacity, and corner-radius state.
- Keep the destination child outside animation rebuilds.
- Isolate destination and source grids with `RepaintBoundary`.
- Avoid network calls, image decoding, `toImage`, and heavy layout work on the
  animation critical path.
- Keep tap-to-first-motion below 50 ms on supported test devices.
- Keep combined build and raster time below 16.7 ms at 60 Hz and target 8.3 ms
  at 120 Hz.
- Do not paint active background video or run unrelated source animations
  while Postingan is fullscreen.

### Reduced motion

When system animation reduction is requested, replace the geometry zoom with
a short crossfade/mild scale while preserving navigation, active-B targeting,
and Predictive Back correctness.

### Accessibility

- Route semantics remain scoped to Postingan while it is active.
- Background Profile content is not focusable during the foreground route.
- Repeated navigation input is ignored until the transition reaches a stable
  state.

## State Machine

The route has these terminal and transitional states:

- `preparingOpen`
- `opening`
- `open`
- `interactiveBack`
- `settlingOpenAfterCancel`
- `closingToTarget`
- `closingFallback`
- `closed`

Only `open` accepts a new back interaction. Only `interactiveBack` can commit
or cancel. Cancellation must return to `open` before target tracking resumes.
All completion, interruption, route disposal, and application lifecycle paths
must end in `open` or `closed`; no partially dragged state may persist.

## Verification Strategy

### Unit and widget tests

- Geometry at forward and reverse progress 0%, 25%, 50%, 75%, and 100%.
- The full destination remains one transformed subtree; destination chrome is
  not revealed as separately clipped fragments.
- Initial nonzero post index is positioned before forward visibility.
- Active A changes to B using visibility thresholds and hysteresis.
- A to B reverse ends at B's key for all three origin screens.
- B from a second or third pagination page is merged into the source without a
  duplicate fetch.
- An obsolete async prepare result cannot replace a newer target.
- Gesture start freezes B; gesture cancel resumes tracking only after settle.
- iOS commit, iOS cancel, Android Predictive Back from both edges, Android
  cancel, and Android 3-button back.
- Missing/deleted/offscreen B uses fallback and never targets A.
- Rapid repeated taps push only one route.
- Opening emits no haptic channel call; existing Postingan actions still do.
- Route status listeners, controllers, image proxies, and session listeners
  are disposed exactly once.

### Golden tests

Capture representative intermediate frames for:

- Light and dark themes.
- Photo, carousel, and video poster.
- Forward zoom.
- iOS interactive preview.
- Reverse terminal morph to B.

### Device and integration checks

- iOS left-edge drag: slow, cancel, threshold commit, and fast fling.
- Android gesture navigation from left and right edges.
- Android 3-button navigation.
- 60 Hz and 120 Hz performance traces.
- App background and foreground during opening and interactive back.
- Scroll from A to a paginated B and immediately begin back.
- Comment sheet open above Postingan, then back twice.

## Acceptance Criteria

- No overlapping Profile and Postingan chrome during forward or reverse.
- No black frame, duplicate thumbnail, aspect-ratio stretch, or first-frame
  index jump.
- A user viewing an existing, resolvable B returns to B. An unavailable B uses
  fallback and is never replaced by an animation to A.
- The source Profile is already positioned at B when an interactive preview
  reveals it.
- Gesture cancellation returns smoothly to the exact fullscreen state.
- Android uses system Predictive Back input rather than the iOS recognizer.
- No haptic occurs when opening Postingan.
- Existing Postingan action haptics and video ownership remain correct.
- Missing target data always produces a safe fallback and a completed pop.
- Focused tests pass and device traces meet the stated frame budgets.

## Implementation Sequence

1. Remove entry haptics and add their regression tests.
2. Make the initial Postingan index ready before first visible paint.
3. Add the route-scoped transition session and active-post reporting.
4. Synchronize pagination and prepare B in each source adapter.
5. Implement non-interactive full-page forward and reverse zoom.
6. Add iOS interactive back commit and cancellation.
7. Add Android Predictive Back progress, commit, cancellation, and fallback.
8. Add media readiness, lifecycle, reduced-motion, and missing-target paths.
9. Run focused tests, golden checks, and physical-device performance traces.
10. Tune timing and curves only after geometry and ownership are verified.

## Expected File Boundaries

New focused units should hold the transition instead of growing the existing
generic route:

- A Postingan-specific page route and surface transition widget.
- A route-scoped transition session and source adapter contract.
- Focused transition geometry/state-machine tests.

Existing integrations are expected in:

- `member_post_detail_screen.dart`
- `member_screen.dart`
- `public_profile_screen.dart`
- `member_posts_screen.dart`

`origin_expansion_route.dart` should remain the composer/`+` route and should
not absorb Postingan-specific pagination, active-post, or platform gesture
logic.

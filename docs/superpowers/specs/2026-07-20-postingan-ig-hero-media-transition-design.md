# Postingan transition: IG-style hero-media + chrome fade

Status: approved by user (2026-07-20), pending implementation plan.
Supersedes the rendering approach in `2026-07-18-postingan-full-page-zoom-transition-design.md`
(the "one-surface" zoom). That spec's plumbing — session, registry, adapters,
gesture state machine — is retained; only how the transition is DRAWN changes.

## Problem

The shipped `PostPageZoomRoute` scales the ENTIRE destination page (header,
avatar, caption, action row, and media) as one surface from the source grid
tile to fullscreen. This reads as "the page is zooming in", not "the photo is
growing into the feed" — the Instagram reference the user is matching against.
In IG, only the tapped media animates from the grid cell to its slot in the
detail layout; the surrounding chrome (username, caption, actions) is already
laid out at its final position and simply fades in.

Additionally, closing a video post has an independent, now-fixed bug (frame
swapped for a reloading thumbnail on close) whose underlying fragility —
different phases rendering the video through different widget structures —
this redesign must not reintroduce. The new architecture is required to keep
the video surface structurally continuous across the whole flight (see
"Video" below), which removes that class of bug at the root rather than
patching around it a second time.

## Goals

- Only the primary media (photo, carousel first frame, or video frame)
  animates in size/position between the grid tile and its slot in the
  destination layout.
- Chrome (header, caption, action row) is laid out at its FINAL position for
  the entire flight and only fades in/out (opacity), never scales or moves.
- Video shows a paused frame throughout the flight; real playback starts only
  once the surface has landed (`open` phase). The frame is drawn through the
  coordinator's SINGLE controller (one texture id) at every phase and in both
  the hero and chrome media layers — so the hero→chrome handoff is a crossfade
  between two views of the SAME texture, never a controller reinit and never a
  thumbnail (once the controller has visual output). This is the invariant
  that prevents the close-glitch, NOT literal widget-instance identity (the
  hero and chrome layers are necessarily different tree positions).
- Interactive back (iOS edge swipe, Android Predictive Back) mirrors forward:
  linear finger-progress drives the hero shrinking back to the tile AND the
  chrome fading out simultaneously.
- All existing guarantees are preserved: freeze-before-flight, reverse targets
  the currently visible post (not the originally tapped one), fallback ladder
  on readiness timeout / freeze failure, no haptic on open, cross-origin
  parity (Own Profile / Public Profile / Postingan Saya).

## Non-goals

- Feed → Detail Produk morph, tap-video → fullscreen nav, and comment-sheet
  drag are explicitly OUT of scope for this spec. Each gets its own
  spec/plan/implementation cycle later.
- No change to which three origins use this route (Own Profile, Public
  Profile, Postingan Saya); Saved Posts and the composer remain untouched.
- No change to the underlying readiness/freeze/target-tracking contracts in
  `PostDetailTransitionSession` — this spec only changes what is rendered.

## Architecture

### What is reused unchanged

- `PostDetailTransitionSession`, `PostTransitionTileRegistry`,
  `PostTransitionSourceTile`, and all three source adapters
  (`ProfilePostSourceAdapter` usages in `member_screen.dart`,
  `public_profile_screen.dart`, `member_posts_screen.dart` via
  `post_gallery_opener.dart`).
- The `PostPageZoomPhase` 8-state machine and its legality map in
  `post_page_zoom_route.dart` (`preparingOpen` → `opening` → `open` →
  `interactiveBack` → `settlingOpenAfterCancel` / `closingToTarget` /
  `closingFallback` → `closed`).
- The iOS leading-edge `RawGestureDetector` and the Android
  `_PostPageZoomPredictiveBackObserver`, including the commit/cancel velocity
  and progress thresholds.
- The freeze/target/pending-return contract on the session (`freeze()`,
  `assignPendingReturnTarget()`, `resumeTrackingAfterCanceledBack()`) and the
  destination's bounded readiness stage in `member_post_detail_screen.dart`
  (`_completeTransitionReadiness` and friends) — readiness still measures the
  destination against the fullscreen viewport, unchanged from the current
  (fixed) `preparingOpen` behavior.

### What changes

**Geometry resolver** (`post_page_zoom_geometry.dart`, rewritten). Replaces
`resolvePostPageZoomFrame` (one frame for the whole page) with two independent
pure functions:

- `resolveHeroFrame({fromRect, toRect, fromRadius, toRadius, progress})` —
  tweens offset/size/corner-radius of the MEDIA rect only, linear in
  `progress` (0 = source tile, 1 = destination media slot). No viewport-scale
  term; the hero's target is the destination's actual media slot rect, not
  the fullscreen rect.
- `resolveChromeOpacity(progress)` — linear 0→1 (per user decision: chrome
  fade tracks flight progress directly, no separate curve/delay).

**Aspect-ratio handling (important — this is what makes it read as IG, not a
stretch).** The source tile is 1:1 (square grid cell showing a center-crop);
the destination media slot is a different aspect (video is clamped ~4:5, photos
vary). The hero rect therefore changes aspect over the flight. The media inside
the hero is painted `BoxFit.cover` so it is never stretched — as the rect's
aspect tweens 1:1 → slot, the visible crop re-frames smoothly (the same image,
progressively revealing more of its true framing). This matches IG's
"crop opens up as it grows" feel closely enough without an explicit crop-window
tween. Pixel-exact preservation of the grid's center-crop as an independent
animated crop window is deliberately OUT of scope (materially more work for a
subtle difference); if the cover-fit re-framing is judged wrong on-device we
revisit it as a follow-up, not a blocker.

Both are pure functions with the same "no notion of direction" property the
current resolver has, so a reverse flight is just `progress` animating 1→0.

**Transition widget** (`post_page_zoom_transition.dart`, rewritten). Becomes
two independently-positioned layers instead of one transformed surface:

1. **Chrome layer** — the destination screen laid out at its natural
   fullscreen size from the first frame, with its primary-media slot rendered
   transparent while a hero covers it (the destination already knows which
   element is the primary media via its existing per-post media key — see
   "Destination screen changes"). The ENTIRE destination is wrapped in a
   single `Opacity` driven by `resolveChromeOpacity(progress)`; because the
   media slot is transparent anyway, fading the whole subtree needs no
   "everything-except-the-media" carve-out (transparent × opacity is still
   transparent). This is simpler and cheaper than isolating the chrome.
2. **Hero layer** — a `Transform`/`ClipRRect`-positioned box drawing the
   clean media proxy (photo / carousel-first-frame / paused-video controller)
   with `BoxFit.cover`, positioned via `resolveHeroFrame`. Stacked ABOVE the
   chrome layer.

**Hero `toRect` resolution timing.** The hero's `toRect` (destination media
slot rect) is resolved ONCE per flight and frozen for that flight, not
re-measured per tick: for a forward open, it is measured from the target
post's media key after the destination has laid out and readiness has aligned
the scroll (the list is static during `opening`, so the rect is stable); for a
reverse close, the roles swap (`fromRect` = the current media slot, `toRect` =
the frozen target tile). Freezing the endpoints mirrors the existing
freeze-before-flight contract and avoids jitter from any incidental relayout.

**Handoff (hero → real destination media).** Over the final ~15% of the
flight (reusing the existing `postPageZoomCrossfadeProgressThreshold`-style
threshold, mirrored to trigger near the END instead of the start), the hero
layer's opacity ramps 1→0 while the destination's real media slot — until now
transparent — ramps 0→1 at the exact same rect (by construction, since the
hero's `toRect` IS that slot's rect). This is a crossfade between two already
pixel-aligned surfaces, not a resize, so there is no visible pop even if the
proxy and the final decoded asset differ slightly.

**Video.** The hero draws the video through the coordinator's single live
controller (`VideoPlayer(controller)` with `BoxFit.cover`), NOT a thumbnail
asset. After landing, the chrome's real media slot draws that same controller.
Because both bind one controller (one texture id, coordinator-owned), the
hero→chrome handoff crossfade is between two views of the SAME texture — there
is no reinit and no thumbnail at any phase once the controller has visual
output. This is the structural guarantee the video-close-glitch requires; it
does NOT depend on the hero and chrome sharing a literal `VideoPlayer` Element
(they can't — different tree positions), only on sharing the controller.
Playback start stays gated on phase reaching `open` (existing
`session.setPlaybackAllowed` timing); during the flight the frame drawn is
whatever the paused controller holds (its last decoded frame), consistent with
the existing close-time fix (`postDetailShowsVideoSurface`, which is decoupled
from `playbackAllowed`).

**Interactive back (both iOS and Android Predictive Back).** The existing
`resolvePostPageBackPreview`/`PostPageBackSurface` machinery in
`post_page_zoom_back_gesture.dart` is retargeted: instead of resolving one
whole-surface frame, it resolves a `PostPageBackFrame` for the hero rect via
`resolveHeroFrame` (progress 1→0 as the finger drags toward the tile) and a
chrome opacity via `resolveChromeOpacity`. Commit/cancel continue from the
"exact current transform" exactly as today (`lerpPostPageBackFrame`,
`_commitFromFrame`) — only the geometry the interpolation operates over
changes, not the continuity guarantee itself.

**Fallback ladder (readiness timeout, freeze failure).** Unchanged in
trigger conditions. Its RENDER simplifies: since chrome is never
geometry-animated in this design, a fallback only needs to crossfade the
media layer (hero proxy → destination media) while chrome simply appears at
its resting opacity — there is no separate "whole surface" fallback
transition to reconcile.

### Destination screen changes

`member_post_detail_screen.dart` needs to expose, per post, the laid-out rect
of its primary media widget — the target for the hero's `toRect`. It already
tracks a per-post key on the media element (`_postMediaKeys`, used today for
readiness/positioning); this spec reuses that same key rather than adding a
new one. The screen also needs a route-driven flag (via the existing
`PostDetailTransitionSession` phase/generation plumbing) to render that one
media slot as transparent while a hero is actively covering it, and opaque
otherwise — this is the only new piece of state the destination screen needs.

### Data flow (forward open, happy path)

1. Source screen freezes the tapped tile, creates the session, pushes
   `PostPageZoomRoute` (unchanged).
2. `preparingOpen`: destination mounts full-size, transparent media slot,
   chrome at opacity 0 (matches `resolveChromeOpacity(0) == 0`); hero renders
   at the tile's rect (matches `resolveHeroFrame(progress: 0)`). Visually
   identical to the grid — no flash (this preserves the fix already shipped
   for the previous architecture).
3. Once destination readiness resolves (unchanged contract), phase moves to
   `opening`; `progress` animates 0→1. Hero rect tweens tile→media-slot;
   chrome opacity tweens 0→1; media-slot crossfade triggers in the final
   portion.
4. `open`: hero is gone (fully crossfaded out), destination's real media is
   the only thing at that rect, chrome fully opaque, playback allowed.

### Data flow (reverse / close, happy path)

Mirrors forward exactly: media-slot crossfades back to the hero proxy first
(so there is a live hero surface again before the shrink starts), then
`progress` animates 1→0 (or is driven directly by drag progress for the
interactive path), shrinking the hero to the current target tile's rect while
chrome fades to 0, ending with the tile visible in the grid beneath the
now-transparent, then popped, route.

## Reduced motion / accessibility

The shipped route already routes `MediaQuery.disableAnimations ||
accessibleNavigation` away from the geometry zoom into a short crossfade
(`_reducedMotion` / `_CrossfadeZoomTransition`). This is PRESERVED: under
reduced motion there is no hero geometry tween — the media slot and chrome
both simply crossfade in place at their final rects (hero opacity 0→1 at the
destination slot, chrome opacity 0→1), and the reverse is the mirror. The
`resolveHeroFrame` geometry path is skipped entirely in this mode. This must
be an explicit render branch, not an emergent side effect, and gets its own
test.

## Error handling

- Readiness timeout / no usable destination surface: falls back to a media-
  only crossfade at the hero's current rect (media slot never resolved, so
  the hero simply fades in place); chrome renders at its resting opacity
  immediately since it was never part of the geometry animation.
- Close when the target (visible post B) tile is off-screen or unresolved in
  the grid (B paginated in but grid not scrolled to it): the hero has no valid
  `toRect` to shrink to, so this takes the existing fallback-close path (fade
  + mild scale, never targeting a bogus rect), same as today. The
  pending-return machinery still repositions the grid after the pop.
- Freeze failure (no usable source geometry, e.g. tile scrolled far
  off-screen or reparented): existing fallback-close path is unchanged; it
  already never references source-tile geometry.
- Backgrounding/metrics change mid-interactive-back: existing interruption
  handling (`_handleInterruption`, pause + cancel) is unchanged; it operates
  on phase/session state, not on which geometry function is in use.

## Testing

- `post_page_zoom_geometry_test.dart` (rewritten): pure-function tests for
  `resolveHeroFrame` (endpoints, monotonicity, corner-radius tween) and
  `resolveChromeOpacity` (0 at progress 0, 1 at progress 1, linear).
- `post_page_zoom_transition_test.dart` (new/rewritten): widget tests
  asserting the two-layer structure — hero positioned/sized per progress,
  chrome opacity per progress, media-slot transparency before/after the
  crossfade threshold.
- `post_page_zoom_route_test.dart`: existing phase-legality and gesture tests
  are retained as-is (they don't assert on render internals beyond the
  `_findsCrossfade`/`_findsFallbackCloseTransition` helpers, which get updated
  to the new widget names); add new assertions that the hero and chrome
  layers both exist during `opening`/`interactiveBack`/`closingToTarget`.
- New regression (video-close-glitch, the user's explicit priority): across
  `preparingOpen` → `opening` → `open` → `interactiveBack` → `closingToTarget`,
  a video post NEVER renders the thumbnail surface once the controller has
  visual output, and the controller is never reinitialized (assert on
  controller/texture identity via the coordinator, and on
  `postDetailShowsVideoSurface`-style state — NOT on `VideoPlayer` widget
  identity, which legitimately differs between the hero and chrome layers).
- New regression: interactive-back progress at various drag values produces a
  hero rect and chrome opacity that mirror the forward animation at the same
  progress — asserted on the GEOMETRY (hero rect) and CHROME OPACITY only. The
  media-slot↔hero crossfade is mirrored in timing (final ~15% forward = first
  ~15% reverse), so it is checked separately, not as part of the same-progress
  equality.
- Goldens (`post_page_zoom_golden_test.dart`): regenerated for the two-layer
  look at representative progress values (0, 0.5, 1) for photo/carousel/video,
  light/dark, plus the iOS interactive-preview and reverse-terminal frames.
- Cross-origin parity test (`post_zoom_cross_origin_test.dart`): unchanged
  assertions, still must pass unmodified (proves the origin-facing contract
  didn't change).

## Open questions

None outstanding — video timing (paused-hero, autoplay-on-landing), back
gesture symmetry, and the video-close-glitch structural requirement were all
confirmed with the user during design.

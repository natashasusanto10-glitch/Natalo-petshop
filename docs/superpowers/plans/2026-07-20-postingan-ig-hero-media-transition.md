# Postingan IG hero-media transition — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the one-surface page zoom for Profile→Postingan with an IG-style transition where only the media animates (true shared element: uniform content scale + an opening clip window) while the page chrome fades in at its final position.

**Architecture:** Two independently-positioned layers inside `PostPageZoomRoute` — a full-size chrome layer (destination screen, media slot transparent) faded by opacity, and a hero layer above it drawing the media via a uniform-scale + animated-clip resolver. A crossfade in the last ~15% of the flight hands the hero off to the destination's real media slot. All existing session/registry/adapter/state-machine/gesture plumbing is reused; only rendering + the geometry resolver change.

**Tech Stack:** Flutter/Dart, `flutter_test` widget + golden tests, existing `PostDetailTransitionSession` / `PostVideoCoordinator` infrastructure.

## Global Constraints

- Worktree only: `C:\Users\USER\Desktop\natalopetshopflutter\.worktrees\postingan-full-page-zoom`, branch `codex/postingan-full-page-zoom`. Never the shared main checkout.
- TDD per step: write failing test → run (confirm RED) → minimal impl → run (GREEN) → commit. Focused analyzer + `dart format` + `git diff --check` clean before each commit.
- Media is NEVER non-uniformly scaled (no stretch): width and height always scale by one factor.
- Video: the surface is drawn through the coordinator's single controller at every phase; never a thumbnail once the controller has visual output; playback starts only at phase `open`. Do NOT reintroduce a `playbackAllowed` gate on what is DRAWN (keep `postDetailShowsVideoSurface` decoupled).
- Chrome fade is linear in progress (`resolveChromeOpacity`), no separate curve.
- Preserve every existing invariant: freeze-before-flight, reverse targets the visible post B, no entry haptic, cross-origin parity (3 origins), reduced-motion crossfade path, fallback ladder.
- The three origins using the route (`member_screen.dart`, `public_profile_screen.dart`, `member_posts_screen.dart` via `post_gallery_opener.dart`) and Saved Posts / composer are unchanged in wiring.
- Media aspect for a post = `resolvePostinganMediaAspectRatio(width:, height:, type:)` from `lib/features/feed/layout/postingan_media_aspect_ratio.dart` (video min 9/16, photo min 3/4, max 1.91) — the exact value the detail slot renders at.

---

## File structure

- `flutter_app/lib/features/feed/transition/post_page_zoom_geometry.dart` — REWRITE. Pure resolver: `PostPageHeroFrame`, `resolveHeroFrame(...)`, `resolveChromeOpacity(...)`. Keep `postPageZoomCrossfadeProgressThreshold`.
- `flutter_app/lib/features/feed/transition/post_page_zoom_transition.dart` — REWRITE. `PostPageZoomTransition` becomes the two-layer (chrome + hero) widget.
- `flutter_app/lib/features/feed/transition/post_page_zoom_back_gesture.dart` — MODIFY. Interactive back preview/commit resolve a hero frame + chrome opacity instead of the iOS card-shrink surface.
- `flutter_app/lib/features/feed/transition/post_page_zoom_route.dart` — MODIFY. All phase render paths (`_buildPhaseContent`, interactive preview/commit, fallback) rebuilt around the two layers; reduced-motion branch preserved.
- `flutter_app/lib/features/feed/transition/post_detail_transition_session.dart` — MODIFY. Add destination-media-slot suppression signal + expose the resolved slot rect / mediaAspect the route needs (see Task 3 for exact API).
- `flutter_app/lib/screens/member_post_detail_screen.dart` — MODIFY. Publish per-post `slotRect` (via existing `_postMediaKeys`) + `mediaAspect`; render the target media slot transparent while suppressed.
- Tests: `post_page_zoom_geometry_test.dart`, `post_page_zoom_transition_test.dart`, `post_page_zoom_route_test.dart`, `post_page_zoom_golden_test.dart`, `post_page_zoom_verification_test.dart`, `post_zoom_cross_origin_test.dart`, `member_post_detail_video_surface_test.dart` (all under `flutter_app/test/...`).

---

## Task 1: Hero geometry resolver (pure)

**Files:**
- Modify (rewrite): `flutter_app/lib/features/feed/transition/post_page_zoom_geometry.dart`
- Test (rewrite): `flutter_app/test/features/feed/transition/post_page_zoom_geometry_test.dart`

**Interfaces:**
- Produces:
  - `class PostPageHeroFrame { final double contentScale; final Offset contentOffset; final RRect clip; ... }` (value type, `==`/`hashCode`).
  - `PostPageHeroFrame resolveHeroFrame({required Rect tileRect, required Rect slotRect, required double mediaAspect, required double tileRadius, required double slotRadius, required double progress})`.
  - `double resolveChromeOpacity(double progress)`.
  - `const double postPageZoomCrossfadeProgressThreshold` (retained, value `0.35`; used as `1 - threshold` for the end-of-flight handoff by callers).
- The media surface is conceptually painted at intrinsic size `Size(mediaAspect, 1.0)` (aspect-only; absolute size is arbitrary because scale is derived). `contentScale`/`contentOffset` map that surface into overlay coordinates. `clip` is the visible window.

Endpoint contract (the two guarantees):
- `progress == 0`: the media, scaled by `contentScale` and placed at `contentOffset`, covers `tileRect` exactly as `BoxFit.cover` would (cover-scale = `max(tileRect.width / mediaAspect, tileRect.height / 1.0)` in surface units, centered on `tileRect.center`); `clip == RRect.fromRectAndRadius(tileRect, tileRadius)`.
- `progress == 1`: same but covering `slotRect`; `clip == RRect.fromRectAndRadius(slotRect, slotRadius)`.
- Between: `contentScale` linear between the two cover-scales; `contentOffset` linear between the two centered offsets; `clip` = `RRect.lerp(tileClip, slotClip, progress)`.

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/transition/post_page_zoom_geometry.dart';

void main() {
  const tile = Rect.fromLTWH(30, 100, 120, 120); // 1:1 grid cell
  const slot = Rect.fromLTWH(0, 80, 400, 500);   // 4:5 detail slot

  // Helper: the on-screen rect the media content occupies for a frame,
  // computed from contentScale/contentOffset over the intrinsic surface
  // Size(mediaAspect, 1).
  Rect contentRect(PostPageHeroFrame f, double mediaAspect) => Rect.fromLTWH(
        f.contentOffset.dx,
        f.contentOffset.dy,
        mediaAspect * f.contentScale,
        1.0 * f.contentScale,
      );

  bool coversTightly(Rect content, Rect target) =>
      content.left <= target.left + 0.5 &&
      content.top <= target.top + 0.5 &&
      content.right >= target.right - 0.5 &&
      content.bottom >= target.bottom - 0.5 &&
      // exactly one dimension matches (cover touches on the tight axis)
      ((content.width - target.width).abs() < 0.5 ||
          (content.height - target.height).abs() < 0.5);

  group('resolveHeroFrame endpoints', () {
    for (final aspect in <double>[4 / 5, 1.91, 1.0]) {
      test('progress 0 covers the tile (aspect $aspect)', () {
        final f = resolveHeroFrame(
          tileRect: tile, slotRect: slot, mediaAspect: aspect,
          tileRadius: 4, slotRadius: 0, progress: 0,
        );
        expect(f.clip.outerRect, tile);
        expect(coversTightly(contentRect(f, aspect), tile), isTrue);
      });
      test('progress 1 fills the slot (aspect $aspect)', () {
        final f = resolveHeroFrame(
          tileRect: tile, slotRect: slot, mediaAspect: aspect,
          tileRadius: 4, slotRadius: 0, progress: 1,
        );
        expect(f.clip.outerRect, slot);
        expect(coversTightly(contentRect(f, aspect), slot), isTrue);
      });
    }
  });

  test('contentScale is monotonic and uniform across the flight', () {
    double? prev;
    for (var p = 0.0; p <= 1.0; p += 0.1) {
      final f = resolveHeroFrame(
        tileRect: tile, slotRect: slot, mediaAspect: 4 / 5,
        tileRadius: 4, slotRadius: 0, progress: p,
      );
      if (prev != null) expect(f.contentScale, greaterThanOrEqualTo(prev));
      prev = f.contentScale;
    }
  });

  test('resolveChromeOpacity is linear 0..1', () {
    expect(resolveChromeOpacity(0), 0);
    expect(resolveChromeOpacity(1), 1);
    expect(resolveChromeOpacity(0.5), closeTo(0.5, 1e-9));
  });
}
```

- [ ] **Step 2: Run tests, confirm they fail**

Run: `flutter test test/features/feed/transition/post_page_zoom_geometry_test.dart`
Expected: FAIL — `resolveHeroFrame` / `PostPageHeroFrame` undefined.

- [ ] **Step 3: Implement the resolver**

```dart
import 'dart:ui' show lerpDouble;
import 'package:flutter/widgets.dart';

const double postPageZoomCrossfadeProgressThreshold = 0.35;

@immutable
class PostPageHeroFrame {
  const PostPageHeroFrame({
    required this.contentScale,
    required this.contentOffset,
    required this.clip,
  });
  final double contentScale;
  final Offset contentOffset;
  final RRect clip;

  @override
  bool operator ==(Object other) =>
      other is PostPageHeroFrame &&
      other.contentScale == contentScale &&
      other.contentOffset == contentOffset &&
      other.clip == clip;

  @override
  int get hashCode => Object.hash(contentScale, contentOffset, clip);
}

// Cover a target rect with an intrinsic surface Size(mediaAspect, 1):
// returns (scale, topLeft-offset) so the scaled surface is centered on and
// fully covers `target`.
(double, Offset) _cover(Rect target, double mediaAspect) {
  final scale = (target.width / mediaAspect) > target.height
      ? target.width / mediaAspect
      : target.height;
  final w = mediaAspect * scale;
  final h = scale;
  final offset = Offset(
    target.center.dx - w / 2,
    target.center.dy - h / 2,
  );
  return (scale, offset);
}

PostPageHeroFrame resolveHeroFrame({
  required Rect tileRect,
  required Rect slotRect,
  required double mediaAspect,
  required double tileRadius,
  required double slotRadius,
  required double progress,
}) {
  final t = progress.clamp(0.0, 1.0);
  final (s0, o0) = _cover(tileRect, mediaAspect);
  final (s1, o1) = _cover(slotRect, mediaAspect);
  final tileClip = RRect.fromRectAndRadius(tileRect, Radius.circular(tileRadius));
  final slotClip = RRect.fromRectAndRadius(slotRect, Radius.circular(slotRadius));
  return PostPageHeroFrame(
    contentScale: lerpDouble(s0, s1, t)!,
    contentOffset: Offset.lerp(o0, o1, t)!,
    clip: RRect.lerp(tileClip, slotClip, t)!,
  );
}

double resolveChromeOpacity(double progress) => progress.clamp(0.0, 1.0);
```

- [ ] **Step 4: Run tests, confirm GREEN**

Run: `flutter test test/features/feed/transition/post_page_zoom_geometry_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyzer + format + commit**

```bash
cd flutter_app && flutter analyze lib/features/feed/transition/post_page_zoom_geometry.dart test/features/feed/transition/post_page_zoom_geometry_test.dart && dart format lib/features/feed/transition/post_page_zoom_geometry.dart test/features/feed/transition/post_page_zoom_geometry_test.dart
cd .. && git add flutter_app/lib/features/feed/transition/post_page_zoom_geometry.dart flutter_app/test/features/feed/transition/post_page_zoom_geometry_test.dart
git commit -m "feat(postingan): hero-media geometry resolver (uniform scale + clip window)"
```

---

## Task 2: Two-layer transition widget

**Files:**
- Modify (rewrite): `flutter_app/lib/features/feed/transition/post_page_zoom_transition.dart`
- Test (rewrite): `flutter_app/test/features/feed/transition/post_page_zoom_transition_test.dart`

**Interfaces:**
- Consumes: `resolveHeroFrame`, `resolveChromeOpacity`, `PostPageHeroFrame`, `postPageZoomCrossfadeProgressThreshold` (Task 1).
- Produces: `class PostPageZoomTransition extends StatelessWidget` with fields:
  `Animation<double> progress`, `Rect tileRect`, `Rect slotRect`, `double mediaAspect`, `double tileRadius`, `double slotRadius`, `Widget chromeChild` (destination, media slot already transparent), `Widget heroMediaChild` (the media surface content: Image/carousel-frame/VideoPlayer, painted `BoxFit.cover`, sized to fill via the transform). Optional `bool reverseHandoff` (default false; when true the media-slot↔hero crossfade windows are mirrored for reverse).
- Layers, bottom→top: `Opacity(opacity: resolveChromeOpacity(progress.value), child: RepaintBoundary(chromeChild))` then the hero built from `resolveHeroFrame(...)` as `ClipRRect(clip) > Transform.translate(contentOffset) > Transform.scale(contentScale, alignment: topLeft) > SizedBox(mediaAspect × k, 1 × k) > heroMediaChild`, wrapped in `Opacity` for the handoff (hero opacity ramps 1→0 as `progress` passes `1 - (1 - postPageZoomCrossfadeProgressThreshold)` near the end — i.e. over the final `postPageZoomCrossfadeProgressThreshold` fraction).
- `heroMediaChild` is passed as the `AnimatedBuilder.child` so it is built once (perf).

- [ ] **Step 1: Write the failing widget tests**

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/transition/post_page_zoom_transition.dart';

Widget _host(Widget child) =>
    Directionality(textDirection: TextDirection.ltr, child: child);

void main() {
  testWidgets('renders chrome + hero; chrome opacity tracks progress',
      (tester) async {
    final ctrl = AnimationController(vsync: const TestVSync());
    addTearDown(ctrl.dispose);
    ctrl.value = 0.0;
    await tester.pumpWidget(_host(PostPageZoomTransition(
      progress: ctrl,
      tileRect: const Rect.fromLTWH(30, 100, 120, 120),
      slotRect: const Rect.fromLTWH(0, 80, 400, 500),
      mediaAspect: 4 / 5,
      tileRadius: 4,
      slotRadius: 0,
      chromeChild: const Text('chrome'),
      heroMediaChild: const ColoredBox(color: Color(0xFF00FF00)),
    )));
    // chrome present but fully transparent at progress 0
    final op0 = tester.widget<Opacity>(find.ancestor(
      of: find.text('chrome'), matching: find.byType(Opacity)).first);
    expect(op0.opacity, 0.0);

    ctrl.value = 1.0;
    await tester.pump();
    final op1 = tester.widget<Opacity>(find.ancestor(
      of: find.text('chrome'), matching: find.byType(Opacity)).first);
    expect(op1.opacity, 1.0);
  });

  testWidgets('hero media on-screen rect covers the tile at progress 0 and '
      'the slot at progress 1', (tester) async {
    final ctrl = AnimationController(vsync: const TestVSync());
    addTearDown(ctrl.dispose);
    const heroKey = Key('hero-media');
    Widget build() => _host(PostPageZoomTransition(
          progress: ctrl,
          tileRect: const Rect.fromLTWH(30, 100, 120, 120),
          slotRect: const Rect.fromLTWH(0, 80, 400, 500),
          mediaAspect: 4 / 5, tileRadius: 4, slotRadius: 0,
          chromeChild: const SizedBox.expand(),
          heroMediaChild: const ColoredBox(key: heroKey, color: Color(0xFF00FF00)),
        ));
    ctrl.value = 0.0;
    await tester.pumpWidget(build());
    // The clipped hero fully covers the tile (its visible rect contains it).
    final r0 = tester.getRect(find.byKey(heroKey));
    expect(r0.left, lessThanOrEqualTo(30.5));
    expect(r0.right, greaterThanOrEqualTo(149.5));
  });
}
```

- [ ] **Step 2: Run, confirm RED** (`PostPageZoomTransition` new signature undefined / old signature mismatch).

Run: `flutter test test/features/feed/transition/post_page_zoom_transition_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement the two-layer widget**

Build `PostPageZoomTransition` per the Interfaces block: an `AnimatedBuilder(animation: progress, child: heroMediaChild)` whose builder computes `frame = resolveHeroFrame(...)` and `chromeOpacity = resolveChromeOpacity(progress.value)`, returning a `Stack(fit: expand)` of the chrome `Opacity` layer and the hero layer (clip→translate→scale→sized→`child`), with the hero wrapped in an `Opacity` computed from the handoff window (`heroOpacity = 1 - ((progress - (1 - postPageZoomCrossfadeProgressThreshold)) / postPageZoomCrossfadeProgressThreshold).clamp(0,1)`; when `reverseHandoff`, mirror to the first fraction). Chrome layer wraps `RepaintBoundary(chromeChild)`.

- [ ] **Step 4: Run, confirm GREEN.**

Run: `flutter test test/features/feed/transition/post_page_zoom_transition_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyzer + format + commit**

```bash
cd flutter_app && flutter analyze lib/features/feed/transition/post_page_zoom_transition.dart test/features/feed/transition/post_page_zoom_transition_test.dart && dart format lib/features/feed/transition/post_page_zoom_transition.dart test/features/feed/transition/post_page_zoom_transition_test.dart
cd .. && git add flutter_app/lib/features/feed/transition/post_page_zoom_transition.dart flutter_app/test/features/feed/transition/post_page_zoom_transition_test.dart
git commit -m "feat(postingan): two-layer hero+chrome transition widget"
```

---

## Task 3: Destination media-slot exposure + suppression

**Files:**
- Modify: `flutter_app/lib/features/feed/transition/post_detail_transition_session.dart`
- Modify: `flutter_app/lib/screens/member_post_detail_screen.dart` (media slot ~line 2183; `_PostFeedItem`/`_PostMediaSurface`)
- Test: `flutter_app/test/screens/member_post_detail_transition_test.dart` (add cases)

**Interfaces:**
- Produces on the session: `void setDestinationMediaSuppressed(bool suppressed)` + `bool get destinationMediaSuppressed` + it notifies listeners (mirror the existing `setFrozenTileSuppressed` at line 304). This tells the destination "a hero currently covers the active post's media; render that slot transparent."
- Produces on the destination: while `transitionSession.destinationMediaSuppressed` is true, the media slot for the ACTIVE post (the one the hero targets) renders fully transparent (an `Opacity(opacity: 0)` around the `_PostMediaSurface`, keyed by `widget.mediaKey` so its rect stays measurable). Non-active posts render normally.
- Reuses (no new API): per-post slot rect via `_postMediaKeys[i].currentContext.findRenderObject()`; `mediaAspect` via `resolvePostinganMediaAspectRatio(width:, height:, type:)`.

- [ ] **Step 1: Failing test** — pump `MemberPostDetailScreen` with a session, call `session.setDestinationMediaSuppressed(true)`, pump, assert the active post's `_PostMediaSurface` subtree is wrapped by an `Opacity` with `opacity == 0` while the media key's render box still has non-empty size (measurable). Set false → opacity 1.

- [ ] **Step 2: Run, confirm RED** (`setDestinationMediaSuppressed` undefined).

- [ ] **Step 3: Implement** — add the session field/setter/getter (copy the `setFrozenTileSuppressed` shape), listen to it in `member_post_detail_screen` (already listens via `_onTransitionSessionChanged`), and wrap the active post's `_PostMediaSurface` in `Opacity(opacity: suppressed && isActive ? 0 : 1, child: ...)` keeping the `mediaKey` subtree in place.

- [ ] **Step 4: Run, confirm GREEN.**

- [ ] **Step 5: Analyzer + format + commit** (`git commit -m "feat(postingan): destination media-slot suppression signal"`).

---

## Task 4: Route forward render (preparingOpen / opening / open)

**Files:**
- Modify: `flutter_app/lib/features/feed/transition/post_page_zoom_route.dart` (`_buildPhaseContent`, helpers `_tileRect`/`_activeProxy`; add `_slotRect`/`_mediaAspect` resolution frozen per flight)
- Test: `flutter_app/test/features/feed/transition/post_page_zoom_route_test.dart` (update existing bootstrap/forward tests, add new)

**Interfaces:**
- Consumes: `PostPageZoomTransition` (Task 2), session suppression (Task 3), `resolveHeroFrame`.
- The route resolves `slotRect` + `mediaAspect` once when leaving `preparingOpen` (destination laid out + readiness aligned); stores them for the flight. `preparingOpen` renders the transition at `progress 0` (hero over the tile, chrome opacity 0) — visually identical to the grid (preserves the shipped no-flash guarantee). Sets `setDestinationMediaSuppressed(true)` while the hero is live; clears it at the handoff completion (phase `open`).
- Video: the hero's `heroMediaChild` for a video is `VideoPlayer(coordinatorController)` (same controller the destination uses), `BoxFit.cover`; playback still gated to `open`.

- [ ] **Step 1: Update/After tests** — adapt the existing "preparingOpen holds…" and "destination bootstrap" tests to the new widget: assert `find.byType(PostPageZoomTransition)` present in `preparingOpen` with controller value 0 and chrome opacity 0; assert destination laid out full-screen (unchanged readiness contract); add: after readiness resolves and animation settles to `open`, `session.destinationMediaSuppressed == false` and the hero opacity has reached 0 (handed off).

- [ ] **Step 2: Run, confirm RED.**

- [ ] **Step 3: Implement** the forward render paths in `_buildPhaseContent` using `PostPageZoomTransition`, freeze `slotRect`/`mediaAspect` on the `preparingOpen→opening` edge, drive `setDestinationMediaSuppressed` true during flight / false at `open`.

- [ ] **Step 4: Run, confirm GREEN** (full `post_page_zoom_route_test.dart`).

- [ ] **Step 5: Analyzer + format + commit** (`"feat(postingan): forward render via hero+chrome layers"`).

---

## Task 5: Route reverse render (non-interactive close)

**Files:**
- Modify: `flutter_app/lib/features/feed/transition/post_page_zoom_route.dart` (`_performClose`, `closingToTarget`/`closingFallback` render)
- Test: `flutter_app/test/features/feed/transition/post_page_zoom_route_test.dart`

**Interfaces:**
- Reverse mirrors forward: on close, re-suppress the destination media slot and re-show the hero (media-slot→hero crossfade first via `reverseHandoff: true`), then animate `progress` 1→0 shrinking the hero to the frozen target tile while chrome fades to 0. Endpoints per Task 1 with roles swapped (`slotRect` = current active slot, `tileRect` = frozen target tile).
- Off-screen / unresolved target tile → existing fallback-close path (unchanged), no bogus rect.

- [ ] **Step 1: Failing tests** — from `open`, `requestClose()`; assert phase `closingToTarget`, `PostPageZoomTransition` present with `reverseHandoff: true`, controller animating 1→0, and at completion the route pops (`closed`). Assert fallback path still taken when the target tile is unresolved.

- [ ] **Step 2: Run, confirm RED.**
- [ ] **Step 3: Implement** the reverse render.
- [ ] **Step 4: Run, confirm GREEN.**
- [ ] **Step 5: Analyzer + format + commit** (`"feat(postingan): reverse close via hero shrink + chrome fade"`).

---

## Task 6: Interactive back retarget (iOS edge + Android Predictive Back)

**Files:**
- Modify: `flutter_app/lib/features/feed/transition/post_page_zoom_back_gesture.dart` — this is a full RETARGET, not an addition. The card-shrink preview is being replaced everywhere it was used, so its now-dead code must be deleted rather than left alongside the new one:
  - DELETE: `kPostPageBackPreviewMinScale`, `kPostPageBackPreviewCornerRadius`, `kPostPageBackPreviewTranslateFraction` (only consumed by the resolver below), `PostPageBackFrame`, `resolvePostPageBackPreview`, `lerpPostPageBackFrame`, `PostPageBackSurface`, `_RectRadiusClipper`.
  - KEEP (still used, unrelated to the render swap): `kPostPageBackGestureEdgeWidth`, `kPostPageBackCommitProgressThreshold`, `kPostPageBackCommitVelocity`, `kPostPageBackCommitDuration`, `kPostPageBackCancelDuration`, `kPostPageBackCommitSuppressThreshold`.
  - ADD: a `lerpPostPageHeroFrame(PostPageHeroFrame from, PostPageHeroFrame to, double t)` helper (mirrors the deleted `lerpPostPageBackFrame`'s "continues from exact current transform" contract, but over `contentScale`/`contentOffset`/`clip`) and a `PostPageHeroSurface` widget that renders a hero frame (structurally replacing `PostPageBackSurface`: same "no opaque backdrop, source visible around it" behavior, built from `PostPageZoomTransition`'s hero-layer render logic rather than duplicating it — extract that rendering into a shared function Task 2's widget also calls, so there is exactly one hero-paint implementation).
- Modify: `flutter_app/lib/features/feed/transition/post_page_zoom_transition.dart` — extract the hero-layer paint (clip → translate → scale → sized → child) from Task 2's `PostPageZoomTransition.build` into a standalone function (e.g. `Widget paintPostPageHero(PostPageHeroFrame frame, double mediaAspect, Widget child)`); `PostPageZoomTransition` and the new `PostPageHeroSurface` (above) both call it. `post_page_zoom_transition_test.dart` from Task 2 must still pass unmodified after this extraction (behavior-preserving refactor).
- Modify: `flutter_app/lib/features/feed/transition/post_page_zoom_route.dart` (`_buildInteractivePreview`, `_buildInteractiveCommit`, `debugCurrentBackFrame`, commit/cancel continuity)
- Test: `flutter_app/test/features/feed/transition/post_page_zoom_route_test.dart`

**Interfaces:**
- During `interactiveBack`, the preview resolves a hero frame at `progress = 1 - drag` (drag 0→1 maps hero 1→0, i.e. shrinking toward the tile) plus `resolveChromeOpacity(1 - drag)`, instead of the iOS card-shrink surface. Commit continues from the exact current hero frame to the tile (progress→0); cancel springs back to progress 1. The existing thresholds (`kPostPageBackCommitProgressThreshold`, `kPostPageBackCommitVelocity`) and the `settlingOpenAfterCancel` / resume-tracking-once contract are unchanged.
- `debugCurrentBackFrame`/continuity: replace the `PostPageBackFrame`(rect+radius) interpolation with `PostPageHeroFrame` interpolation via the new `lerpPostPageHeroFrame` (lerp scale/offset/clip); keep "continues from exact current transform" (no restart) as the asserted guarantee.

- [ ] **Step 1: Update/failing tests** — the existing "iOS interactive edge back …" and Android Predictive Back tests: retarget assertions to hero-frame values (first-frame continuity = hero frame at release equals commit/cancel start), add chrome-opacity-tracks-drag assertion. Add symmetry test: hero frame + chrome opacity at drag `d` equal the forward frame at `progress = 1 - d` (geometry + opacity only; crossfade timing checked separately).

- [ ] **Step 2: Run, confirm RED.**
- [ ] **Step 3: Implement** the retarget.
- [ ] **Step 4: Run, confirm GREEN** (full route suite).
- [ ] **Step 5: Analyzer + format + commit** (`"feat(postingan): interactive back mirrors hero-media reverse"`).

---

## Task 7: Reduced-motion branch

**Files:**
- Modify: `flutter_app/lib/features/feed/transition/post_page_zoom_route.dart` (`_reducedMotion`, render branch)
- Test: `flutter_app/test/features/feed/transition/post_page_zoom_route_test.dart`

**Interfaces:**
- When `_reducedMotion(context)` (`MediaQuery.disableAnimations || accessibleNavigation`) OR `session.destinationReadiness == crossfadeFallback`: skip `resolveHeroFrame` geometry entirely — the media slot and chrome both crossfade in place at their FINAL rects (hero opacity 0→1 at the slot, chrome opacity 0→1), reverse mirrored.

- [ ] **Step 1: Failing test** — wrap the route in `MediaQuery(disableAnimations: true)`, open, assert NO hero geometry tween (hero frame stays at slot rect for all progress; only opacities change), and both chrome + media crossfade to full.
- [ ] **Step 2: Run, confirm RED.**
- [ ] **Step 3: Implement** the explicit reduced-motion render branch.
- [ ] **Step 4: Run, confirm GREEN.**
- [ ] **Step 5: Analyzer + format + commit** (`"feat(postingan): reduced-motion crossfade-in-place branch"`).

---

## Task 8: Goldens, video regression, verification, cross-origin parity

**Files:**
- Modify: `flutter_app/test/features/feed/transition/post_page_zoom_golden_test.dart` (regenerate for two-layer look)
- Modify: `flutter_app/test/features/feed/transition/post_page_zoom_verification_test.dart`
- Modify: `flutter_app/test/screens/member_post_detail_video_surface_test.dart` (extend)
- Verify unchanged: `flutter_app/test/screens/post_zoom_cross_origin_test.dart`

**Steps:**

- [ ] **Step 1: Video-no-thumbnail regression** — add a test asserting that across `preparingOpen → opening → open → interactiveBack → closingToTarget`, a video post never renders the thumbnail surface once the controller has visual output, and the coordinator controller is not reinitialized (assert on controller identity + `postDetailShowsVideoSurface`-style state, NOT `VideoPlayer` widget identity). Run, confirm it passes against the Task 4–6 implementation.
- [ ] **Step 2: Verification test** — update `post_page_zoom_verification_test.dart` so "destination built once" and "compositor-only primitives (Transform/Opacity/ClipRRect), no BackdropFilter/ImageFiltered/ShaderMask" assertions target the new two-layer widget. Run GREEN.
- [ ] **Step 3: Cross-origin parity** — run `post_zoom_cross_origin_test.dart` UNCHANGED; it must still pass (proves origin-facing contract intact). If it references removed render internals, update finders only, not assertions.
- [ ] **Step 4: Regenerate goldens** — `flutter test --update-goldens test/features/feed/transition/post_page_zoom_golden_test.dart` for photo/carousel/video × light/dark at progress 0 / 0.5 / 1, plus iOS interactive-preview and reverse-terminal frames. Note in the PR that goldens may need CI regeneration on a non-Windows raster backend.
- [ ] **Step 5: Full regression** — run the whole affected suite (transition dir + all `member_post_detail_*` + 3 origin screens + `saved_posts` + `public_profile_video_prewarm`). Expected: all green.
- [ ] **Step 6: Analyzer + format + commit** (`"test(postingan): goldens, video regression, verification, cross-origin for hero transition"`).

---

## Self-review notes

- Spec coverage: hero resolver (T1), two-layer widget (T2), destination slot exposure+suppression (T3), forward render + video controller-sharing + no-flash preparingOpen (T4), reverse close + off-screen-B fallback (T5), interactive back symmetry iOS+Android (T6), reduced-motion (T7), goldens+video-regression+verification+cross-origin (T8). All spec sections mapped.
- Type consistency: `PostPageHeroFrame`/`resolveHeroFrame`/`resolveChromeOpacity` names identical across T1→T2→T4→T6; `setDestinationMediaSuppressed`/`destinationMediaSuppressed` identical T3→T4→T5; `mediaAspect` sourced from `resolvePostinganMediaAspectRatio` everywhere.
- Known caveat carried from prior work: goldens can be Windows-vs-CI flaky (see [[flutter-golden-tests-flaky]] memory) — T8 Step 4 flags CI regen.

# Postingan Full-Page Zoom — Plan for Tasks 7–15 (v2)

Reconstructed 2026-07-20 from the approved spec
(`docs/superpowers/specs/2026-07-18-postingan-full-page-zoom-transition-design.md`)
and the Claude Code handoff task map; revised after an adversarial plan-vs-spec
gap review. Tasks 1–6 are complete and review-CLEAN on
`codex/postingan-full-page-zoom` (rebased onto `origin/main`).

## Verified starting state (do not re-derive; trust and build on this)

- All Task 3–6 symbols exist and match: `PostDetailTransitionSession`,
  `PostDetailTransitionSourceAdapter`, `PostPageSourceTarget`,
  `PostPageFrozenTarget`, `PostPageMediaProxy`,
  `PostDetailDestinationReadiness` (`preparing`/`geometryReady`/
  `crossfadeFallback`), `PostDetailVisibilityTracker`,
  `PostTransitionTileRegistry`, `PostTransitionTileId`,
  `PostTransitionSourceTile`, `profileGridMainAxisOffsetForIndex`, and the
  Task-6 readiness wiring in `member_post_detail_screen.dart`
  (`transitionSession`, item/media keys, bounded readiness with
  `debugPostDetailReadinessClock`/`debugPostDetailReadinessFrameFuture`,
  active-B reporting, `playbackAllowed` gating).
- **No production code creates a `PostDetailTransitionSession` yet.** All three
  origins open `MemberPostDetailScreen` via `pushOriginExpansion`:
  `member_screen.dart:342`, `public_profile_screen.dart:584`,
  `member_posts_screen.dart:464`, and the shared mixin
  `lib/features/feed/widgets/post_gallery_opener.dart:83` (used by
  `saved_posts_screen.dart`). `feed_media_picker_screen.dart:274` also uses
  `pushOriginExpansion` — that is the composer path and MUST stay untouched.
- Origin grids use raw `GlobalKey` tiles today (member_screen `_tileKeys`
  scope-prefixed across 3 tabs; public_profile has TWO grids —
  a SliverGrid ~line 992 and a GridView ~line 1279 — plus
  `ProfilePostOriginKeyCache`; member_posts uses `GalleryPostTile` +
  `_tileKeys`). None wrap tiles in `PostTransitionSourceTile`; no
  `PostTransitionTileRegistry` is instantiated anywhere.
- `PostTransitionTileRegistry.resolve()` returns a FRESH disposable
  `PostPageSourceTarget` each call (live `PostPageMediaProxy` holding a cloned
  `ImageInfo`). Its doc-comment contract: the adapter must cache accepted
  snapshots and dispose rejected/stale snapshots including proxies. Ignoring
  this leaks `ImageInfo` per prepare.
- `PostDetailTransitionSession.tryAttachRoute()` (session.dart:155) is the
  intended single-route guard — returns false on second attach. Use it; do not
  invent a parallel bool.
- `reportActivePost` no-ops while frozen; `reportLoadedPage` INTENTIONALLY
  still merges pages while frozen (session.dart:183). That is correct: merging
  must not be suppressed; only RETARGETING is forbidden. Do not "fix"
  `reportLoadedPage` to no-op while frozen.
- Two DISTINCT generation axes exist; never conflate them:
  `PostDetailTransitionSession._preparationGeneration` (async prepare
  staleness) vs `PostTransitionTileRegistry.layoutGeneration` (layout epoch on
  `PostPageSourceTarget`). An obsolete prepare is rejected by the former; a
  stale rect is rejected by the latter.
- The destination (Task 6) already computes and publishes
  `session.destinationReadiness`. The route CONSUMES it; it must never
  re-implement readiness.

## Ground rules (apply to every task)

- Strict TDD: failing regression first, prove RED for the intended reason,
  smallest patch, prove GREEN, focused analyzer + `git diff --check`, then an
  independent read-only review of the task range. One commit per task (fix
  rounds may add commits).
- Flutter tests serial (`--no-pub --concurrency=1`); bounded pump loops; never
  unbounded `pumpAndSettle` for readiness/gesture tests. No wall-clock sleeps —
  use injected seams (pattern: the Task-6 debug clock/frame-future globals).
- Do NOT modify `origin_expansion_route.dart` or the composer flow
  (`feed_media_picker_screen.dart`). Saved Posts behavior must not change.
- No haptic on open/gesture-start/cancel/commit; in-Postingan action haptics
  stay. Tile-level: `enableFeedback: false` (or equivalent) wherever an
  `InkWell`/`GestureDetector` default could emit platform feedback.
- All geometry in root-overlay logical pixels; uniform width-derived scale;
  independent `RRect` clip tile-bounds → application-bounds; `BoxFit.cover`
  proxy; never non-uniform stretch.
- Destination child built once, outside per-tick rebuilds; `RepaintBoundary`
  isolation; no network/decode/`toImage` on the tap or animation path.
- Formatter discipline: never `dart format` whole legacy/CRLF files; audit and
  drop formatter churn before commit.

---

## Task 7 — Pure zoom geometry + one-surface renderer

**Files**
- Create `flutter_app/lib/features/feed/transition/post_page_zoom_geometry.dart`
- Create `flutter_app/lib/features/feed/transition/post_page_zoom_transition.dart`
- Create `flutter_app/test/features/feed/transition/post_page_zoom_geometry_test.dart`

**Produces:** `PostPageZoomFrame` (value type: `offset`, `scale`, `clip`
RRect, `proxyOpacity`, `destinationOpacity`) resolved by a pure function
`resolvePostPageZoomFrame({required Rect tileRect, required Rect viewportRect,
required double tileCornerRadius, required double progress})`, plus
`PostPageZoomTransition` widget that renders ONE destination subtree.

**TDD steps**
1. RED: unit tests at progress 0, .25, .5, .75, 1 (forward) and the same
   values on the reverse interpolation:
   - `scale` is uniform and width-derived: `lerp(tileRect.width /
     viewportRect.width, 1.0)`; assert NO independent y-scale exists (the
     frame type must not even carry one).
   - `offset` translates the surface top-left from `tileRect.topLeft` to
     `viewportRect.topLeft`.
   - `clip` tweens tile bounds+radius → application bounds+0 INDEPENDENTLY of
     scale (assert clip at .5 ≠ the scaled surface bounds at .5 for a
     non-full-width tile → proves no derived stretch).
   - Endpoints exact: p=0 → (tile geometry, radius=tileCornerRadius);
     p=1 → (`Offset.zero`, 1.0, radius 0).
   - Proxy/destination crossfade: proxy fully opaque at p=0, destination fully
     opaque by an early-flight point (spec: "first portion of the flight");
     assert monotonicity.
2. GREEN: implement the pure resolver.
3. RED (widget): `PostPageZoomTransition` given a build-counting destination
   child + an `AnimationController`: drive ≥10 ticks; assert child built
   exactly once, wrapped in `RepaintBoundary`, transformed via
   `Transform`/`ClipRRect` only; proxy image uses `BoxFit.cover` inside the
   SAME animated clip.
4. RED (widget): the widget does not emit any `SystemChrome`/overlay-style
   change across ticks (status bar is platform-owned; single
   `AnnotatedRegion` if any, constant across the flight — repo gotcha:
   hero-blue status-bar pattern).
5. GREEN, focused analyzer, commit `feat(postingan): add zoom geometry and
   one-surface renderer`.

## Task 8 — Dedicated non-interactive `PostPageZoomRoute` + state machine

**Files**
- Create `flutter_app/lib/features/feed/transition/post_page_zoom_route.dart`
- Create `flutter_app/test/features/feed/transition/post_page_zoom_route_test.dart`

**Produces**
- `PostPageZoomPhase` enum with EXACTLY the spec's 8 states: `preparingOpen`,
  `opening`, `open`, `interactiveBack`, `settlingOpenAfterCancel`,
  `closingToTarget`, `closingFallback`, `closed`.
- `PostPageZoomRoute extends PageRoute` (non-opaque; `opaque=false`;
  `barrierColor` null) and
  `Future<void> pushPostPageZoom(BuildContext context, {required
  PostDetailTransitionSession session, required WidgetBuilder
  destinationBuilder})`.

**Ownership contract (the integration linchpin — implement exactly):**
- The SOURCE screen creates the session (initialPost + its adapter) and calls
  `pushPostPageZoom`.
- `pushPostPageZoom` calls `session.tryAttachRoute()` FIRST; if false, it
  returns without pushing (this is the repeated-tap guard — no ad-hoc bool).
- The route reads `session.openingTarget` for source geometry and consumes
  `session.destinationReadiness` to choose its opening mode:
  - `geometryReady` → full geometry zoom (Task 7 renderer).
  - `crossfadeFallback` → 160 ms crossfade only after the destination is
    stable (spec: Destination readiness §). While `preparing`, the clean
    proxy covers the screen; the route stays in `preparingOpen`.
- The SOURCE disposes the session only after awaiting `route.completed`.
  The route/destination never dispose it.

**TDD steps**
1. RED: state-machine legality table as a dedicated test group. Assert:
   only `open` accepts a new back interaction; only `interactiveBack` can
   commit/cancel; cancel → `settlingOpenAfterCancel` → `open` before target
   tracking resumes (`session.resumeTrackingAfterCanceledBack` called only at
   `open`); every disposal/lifecycle path ends `open` or `closed`; illegal
   transitions throw/no-op (pick one, assert it).
2. RED: forward ~300 ms, curve `Cubic(0.05, 0.7, 0.1, 1.0)` (spec initial
   value), no bounce (assert monotone non-overshooting progress); route
   non-opaque; source stays mounted beneath.
3. RED: source semantics/focus locked while route is topmost — mechanism:
   wrap the source-facing side with route semantics scoping so a
   `SemanticsTester` walk finds NO focusable node from the source page while
   phase ∈ {opening, open}. (PageRoute barrier semantics + `ExcludeSemantics`
   on the revealed source until `interactiveBack`.)
4. RED: repeated `pushPostPageZoom` with the same session pushes exactly one
   route (via `tryAttachRoute` false on second call).
5. RED: non-interactive reverse: freeze happens BEFORE the animation starts
   (`session.freeze()` at pop-request); surface animates to frozen B target
   ~250–280 ms; near-terminal crossfade to B's clean proxy; then
   `setTileSuppressed(B, false)` restore and route disposal — assert this
   ORDER with a call-recording fake adapter.
6. RED: fallback reverse: `session.freeze()` yields `usesFallback` (no usable
   geometry) → phase `closingFallback`, short fade + mild centered scale,
   `assignPendingReturnTarget()` called before pop completes; NEVER animates
   toward the opening A rect (assert no geometry targeting A's rect).
7. RED: proxy selection ladder is synchronous (spec Forward Animation §):
   with a fake adapter whose proxy has (a) a retained frame, (b) only a
   memory-cached provider, (c) nothing → assert the route never awaits before
   first motion and case (c) paints the deterministic placeholder. Assert no
   `toImage` call: seam `debugPostPageZoomOnSnapshotAttempt` (throwing hook)
   installed in tests.
8. GREEN incrementally. Route file must not import
   `origin_expansion_route.dart`.
9. Add debug seams for later tasks NOW (single review surface):
   `debugPostPageZoomGestureProgress` (inject drag progress/velocity) and
   `debugPostPageZoomPredictiveEvents` (inject predictive back start/progress/
   commit/cancel), both test-only globals defaulting to null.
10. Commit `feat(postingan): add the dedicated zoom route`.

*Note: Task 8 is unit/widget-tested with fake adapters + a stub source; real
producers arrive in Tasks 9–11.*

## Task 9 — Source-adapter foundation + Own Profile wiring

Two stages in one task; stage A is shared groundwork for 10/11.

### Stage A — shared foundation (new file)
- Create `flutter_app/lib/features/feed/transition/profile_post_source_adapter.dart`
  (+ test): a reusable `ProfilePostSourceAdapter` base implementing
  `PostDetailTransitionSourceAdapter` over a `PostTransitionTileRegistry` +
  screen-supplied callbacks (`ensureVisible(post, generation)`,
  `mergeScopedPage(page)`, `currentScope`).
- MUST implement the registry disposal contract: cache the accepted
  `PostPageSourceTarget` snapshot; dispose rejected/stale snapshots including
  proxies. RED: a prepare that resolves twice disposes the loser exactly once
  (spy proxy); registry `layoutGeneration` mismatch → target rejected (drives
  fallback), and the stale snapshot is disposed.
- RED: `prepareTarget` honors its `generation` param — a late completion for
  an old generation returns without caching and disposes its snapshot.
- RED: `setTileSuppressed`/restore round-trips to the registry tile.
- RED: `setPendingReturnPostId` stores the id; the SOURCE screen consumes it
  after pop with bounded best-effort positioning (spec Fallback §: the source,
  not the disposed session, owns this). Consumption = scroll near the post's
  grid row via `profileGridMainAxisOffsetForIndex`, one bounded attempt, then
  clear.

### Stage B — Own Profile (`member_screen.dart`)
- Wrap grid tiles (all 3 scope tabs) in `PostTransitionSourceTile` feeding one
  `PostTransitionTileRegistry`; tile ids scope-prefixed like today's
  `_tileKeys`.
- Create the session at tap (initialPost + adapter), REPLACE the
  `pushOriginExpansion` call at `member_screen.dart:342` with
  `pushPostPageZoom` (delete the old call — do not leave a double-push), pass
  `transitionSession` into `MemberPostDetailScreen`, dispose the session after
  `route.completed`.
- `mergeScopedPage`: dedupe by post ID into the CURRENT scope's list without a
  duplicate network fetch (RED: loader call-count stays 0 on merge).
- `prepareTarget` positioning: B fully visible below pinned chrome and above
  bottom nav. RED asserts the resolved B tile rect satisfies
  `rect.top >= pinnedChromeBottom && rect.bottom <= viewportHeight -
  bottomNavHeight` using the shared grid geometry
  (`profileGridMainAxisOffsetForIndex` jump, then exact rect verify).
- Scope rule: normal scoped pagination NEVER switches tabs. `Semua` is chosen
  ONLY when B cannot exist in the origin tab (legacy mixed-scope pagination);
  the tab stays on `Semua` after pop. RED for both branches.
- Refresh-after-pop merges with the session's loaded extent until B is
  retained (RED: refresh completing after pop keeps B's tile resolvable).
- Entry haptic: RED that the tile's tap emits zero `haptic_feedback` channel
  calls AND the tile widget sets `enableFeedback: false`.
- A→B reverse integration test: open A, report B active, pop → reverse targets
  B's tile key rect, never A's (assert with rect equality against B's
  registry snapshot).
- Commit `feat(postingan): wire own profile through the zoom route`.

## Task 10 — Public Profile wiring (`public_profile_screen.dart`)

Reuse Stage A adapter. Specifics that differ from Task 9:
- TWO grids exist (SliverGrid ~line 992; GridView ~line 1279). Wire
  `PostTransitionSourceTile` into BOTH, sharing one registry with
  tile-id scoping per grid/tab; replace `pushOriginExpansion` at
  `public_profile_screen.dart:584` (delete old call).
- Viewer/tab lifecycle: RED that switching profile tabs mid-open (route
  covering) does not break B preparation — prepare re-resolves in the tab
  that owns B; if B's tab is not the visible one, prepare selects it
  (silently, while covered), per spec "Prepare a given post in the appropriate
  grid and tab".
- Same scope/`Semua`, refresh-retains-B, haptics + `enableFeedback:false`,
  A→B reverse, pendingReturnPostId-consumption REDs as Task 9.
- Commit `feat(postingan): wire public profile through the zoom route`.

## Task 11 — Postingan Saya wiring (`member_posts_screen.dart`)

- The tap path goes through the shared mixin `PostGalleryOpener`
  (`post_gallery_opener.dart:83`), which is ALSO used by
  `saved_posts_screen.dart`. Decision (fixed): parameterize the mixin —
  `openPostGallery` gains an optional
  `PostDetailTransitionSession Function()? transitionSessionFactory`
  (null → legacy `pushOriginExpansion`, exactly today's behavior). Only
  `member_posts_screen.dart` passes a factory. RED: Saved Posts still opens
  via the origin-expansion route (assert route type) with zero behavior
  change; member_posts opens via `PostPageZoomRoute`.
- Wrap `GalleryPostTile` usages in `PostTransitionSourceTile` (or embed the
  registry hook inside `GalleryPostTile` behind an optional param — keep
  Saved Posts on the null path).
- Same adapter/scope/refresh/haptic/A→B/pending-return REDs as Task 9.
- Cross-origin invariant test (this task closes the trio): all three origins
  push the SAME route type, none emits an entry haptic, and each returns to
  the visible B not A.
- Commit `feat(postingan): wire postingan saya through the zoom route`.

## Task 12 — iOS interactive leading-edge back

Extend `post_page_zoom_route.dart` (+route test). No new recognizer on
Android (guard by `defaultTargetPlatform`, RED-tested via
`debugDefaultTargetPlatformOverride`).

**TDD (all driven through `debugPostPageZoomGestureProgress` — no real
gesture arena in unit tests; one widget test may drive a real horizontal drag
from the leading edge on the iOS platform override as an integration smoke):**
1. RED: gesture accepted only from the logical leading edge (LTR: left) and
   only in phase `open`.
2. RED: at first progress event, `session.freeze()` is called exactly once;
   while `interactiveBack`, injected `reportActivePost`/`reportLoadedPage`
   calls do NOT change the frozen target (pages still merge — assert
   `loadedPosts` grew, frozen target unchanged). This is the spec's strongest
   freeze guarantee; do not weaken `reportLoadedPage`.
3. RED: progress mapping is LINEAR while finger down (no easing): surface
   translation follows injected progress exactly; scale lerps 1.0 → 0.92 and
   radius 0 → 30 at full drag extent (fixed test values within spec's
   28–32 band).
4. RED: cancel below threshold (progress .2, velocity 0) springs from the
   EXACT current transform (capture transform at release; assert the settle
   animation's first frame equals it — no restart) back to fullscreen; phase
   `settlingOpenAfterCancel` → `open`; only then
   `resumeTrackingAfterCanceledBack`.
5. RED: commit at ≥.25 progress OR velocity ≥800 px/s continues from the
   exact current transform to frozen B in ~180–240 ms (assert duration bounds
   and first-frame continuity), phase `closingToTarget`.
6. RED: no haptic channel call at start/cancel/commit.
7. RED: revealed source beneath shows B's tile visible and NOT suppressed
   during preview; B suppressed only in the terminal overlap portion
   (adapter spy order: suppress after commit passes the overlap threshold,
   restore at completion).
8. GREEN. Commit `feat(postingan): add ios interactive edge back`.

## Task 13 — Android system back + Predictive Back

Extend the route (+tests). Concrete APIs: implement Flutter's predictive-back
route participation (`PredictiveBackEvent`-driven, the framework's
`predictive back` route transition hooks) and expose an ahead-of-time pop
disposition via `Route.popDisposition` compatible with `PopScope`. Do NOT
install the iOS recognizer on Android; do NOT wrap in a generic Material
predictive builder.

**TDD (driven via `debugPostPageZoomPredictiveEvents`; REAL system gestures
are device-verify, user):**
1. RED: platform Android + predictive available: system progress (left edge)
   drives the SAME surface/state machine (`interactiveBack`); right-edge
   events respected (mirrored translation direction per reported swipe edge).
2. RED: system cancellation progress follows back to fullscreen; commit
   continues to frozen B without geometry restart (same first-frame
   continuity assertion as Task 12).
3. RED: 3-button / predictive-unavailable back runs the Task-8
   non-interactive reverse.
4. RED: modal precedence — with a modal sheet above Postingan, the first back
   pops the sheet; the route's phase stays `open` and its surface transform
   never moves (`popDisposition` defers while not topmost).
5. RED: iOS recognizer absent on Android (no leading-edge pointer recognizer
   attached under Android platform override).
6. GREEN. Commit `feat(postingan): add android predictive back`.

## Task 14 — Media, lifecycle, reduced motion, fallback hardening

Each bullet below is ONE focused RED (name given) — implement smallest patch
per RED:

Media
1. `photo-proxy-shares-provider`: grid proxy and destination first frame
   resolve the identical cached `ImageProvider` instance (photo + carousel).
2. `no-fade-during-flight`: destination image fade/shimmer is suppressed
   while phase ∈ {opening} (poster/proxy only crossfade).
3. `video-poster-through-flight`: video item renders poster (no
   `VideoPlayer` texture) until phase `open`.
4. `single-controller-through-transition`: with the warm-handoff fake
   platform, `createCount` stays 1 across open→transition→`open` (route never
   constructs a controller).
5. `playback-gate-follows-phase`: `session.setPlaybackAllowed(true)` only at
   forward completion; reverse start pauses active video BEFORE the surface
   moves (adapter/coordinator call order spy).

Lifecycle
6. `background-during-gesture-terminal`: `didChangeAppLifecycleState(paused)`
   during `interactiveBack` cancels the gesture, ends `open`, no ghost audio
   (playback stays paused).
7. `metrics-change-cancels-not-closes`: `didChangeMetrics` during a gesture
   → cancel to `open`, remeasure on resume; the route NEVER auto-closes from
   rotation/resize/lifecycle.

Reduced motion
8. `reduced-motion-crossfade`: with
   `MediaQuery(data: ...copyWith(disableAnimations: true))`, opening uses the
   short crossfade/mild-scale variant (no geometry zoom), while B targeting
   and pop disposition remain identical (A→B reverse still resolves B).

Fallback matrix (spec's trigger list; one RED each, all must end
`closingFallback` → `closed`, never target A, restore suppressed tiles):
9. `fallback-b-deleted` (B removed via `invalidatePost`).
10. `fallback-source-disposed` (adapter `mounted=false`).
11. `fallback-unpreparable-tab` (prepareTarget returns null).
12. `fallback-unmerged-paginated-b` (mergePage fails/scope mismatch).
13. `fallback-offscreen-or-empty-rect` (`hasUsableGeometry` false).
14. `fallback-stale-layout-generation` (registry generation bumped between
    prepare and freeze).
15. `fallback-restores-suppression-and-assigns-pending-return`: every
    fallback path calls `setTileSuppressed(id,false)` for anything suppressed
    and `assignPendingReturnTarget()` before `closed`.

Commit `fix(postingan): harden media, lifecycle, and fallback paths`.

## Task 15 — Full verification, goldens, performance, final review

Deterministic (this task, in-repo):
- Consolidated regression sweep: Tasks 7–14 suites + full Task 1–6 suites,
  serial; zero regressions.
- Goldens (light + dark): photo, carousel, video-poster ×
  forward-intermediate frame (p≈0.5), iOS interactive preview
  (progress≈0.5, scale .96, radius ~15), reverse terminal-B frame. Use the
  deterministic placeholder proxies; commit golden PNGs.
- Semantics: `SemanticsTester` — only foreground route focusable while open;
  background Profile excluded; reduced-motion variant keeps identical
  semantics.
- Static perf assertions: destination build-count 1 across a full
  open+close cycle; `debugPostPageZoomOnSnapshotAttempt` throwing seam active
  in every route test (proves no `toImage`); no `Image.network`/decode
  triggered during `opening` (instrumented `ImageProvider` spy).
- Analyzer: targeted files clean; full `flutter analyze` delta vs the known
  ~291 dependency-override baseline = 0 new issues. `git diff --check` clean.
- Independent full-branch review (fresh read-only reviewer) of Tasks 7–15;
  CLEAN verdict required.

Device-verify (USER, cannot be automated here — present as a checklist):
- iOS left-edge: slow drag, cancel, threshold commit, fast fling.
- Android gesture nav both edges; Android 3-button back.
- Background/foreground during opening and during interactive back.
- Scroll A→paginated B then immediately back.
- Comment sheet above Postingan, then back twice.
- Performance traces: tap→first-motion <50 ms; 60 Hz <16.7 ms; 120 Hz
  target <8.3 ms.

Only after the CLEAN review: present integration options. NO push/merge
without the user's instruction.

---

## Execution notes (subagent-driven)

- Order: 7 → 8 → 9 → {10, 11 may run in parallel AFTER 9 lands (they reuse
  Stage A; 11 also touches the shared mixin — keep 10 and 11 in separate
  files/commits, 11 owns `post_gallery_opener.dart`)} → 12 → 13 → 14 → 15.
  12 and 13 are sequential (same route file).
- Each task: implementer subagent gets this plan section + spec section
  references; a fresh read-only reviewer verifies the task range; fix rounds
  until CLEAN before the next task starts.
- Every new debug seam must be nulled in test `setUp`/`tearDown` (pattern from
  Task 6).
- If a subagent finds this plan contradicts the spec, the SPEC wins; stop and
  surface the conflict instead of improvising.

## Acceptance criteria (from spec — unchanged)

- Whole page moves as one surface; no overlapping chrome fragments.
- No black frame, duplicate thumbnail, aspect stretch, or first-frame index
  jump.
- Viewing A then B → reverse targets B when valid; never substitutes A.
- Unavailable B → terminal safe fallback.
- Source Profile already at B when interactive preview reveals it.
- iOS cancel resumes smoothly from the exact release transform.
- Android uses system Predictive Back, not the iOS recognizer / a global
  handler.
- Video stays poster during flight; no autoplay before `open`.
- No haptic on open; in-Postingan action haptics intact.
- `+`/composer transition unchanged; Saved Posts unchanged.

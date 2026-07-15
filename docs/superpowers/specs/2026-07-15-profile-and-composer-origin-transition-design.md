# Profile And Composer Origin Transition Design

## Goal

Make navigation feel anchored to the element the user touched:

- A Profile video tile expands into Postingan, and the visible video expands
  again into fullscreen playback.
- The Feed/Profile `+` control expands into the fullscreen post composer.
- Back/cancel reverses into the original tile or `+` control.

## Scope

- Flutter route transitions only.
- Preserve existing media picker, upload, draft, and backend flows.
- Reuse the current Profile video warm handoff and Postingan video
  coordinator. No additional video controller is created for a transition.

## Profile To Postingan

1. The tapped grid tile supplies a stable `GlobalKey`, preview URL, and rect.
2. The Profile route pushes Postingan with a transparent custom page route.
3. A cached thumbnail snapshot morphs from the tile rect to the media frame
   while Postingan fades in during the final portion of the transition.
4. The existing warm handoff remains the only playback session passed to
   Postingan.
5. Back from Postingan reverses to the original tile when it is visible. If
   the tile is unavailable, the route uses a normal fade reverse.

## Postingan To Fullscreen

This remains the existing `pushScaledVideoFeed` flow:

- 260ms ease-out entry from the inline media anchor.
- 220ms ease-in reverse to the last viewed inline video target.
- The scoped video coordinator owns the controller throughout fullscreen.

## Plus To Composer

1. Both Feed and Profile `+` controls expose a stable `GlobalKey`.
2. The post creation flow pushes a fullscreen route through a reusable origin
   transition helper.
3. Entry grows a light composer surface from the `+` rect over 240ms.
4. Explicit cancel or system back reverses over 220ms into the originating
   `+` rect.
5. If the source control is offscreen or disposed, reverse falls back to a
   fade and still completes navigation safely.

## Interaction Rules

- Transitions block repeated open actions until route push completes.
- No bottom sheet is used for the composer entry path.
- Media picker and draft navigation inside the composer keep their existing
  route behavior; only entry and final cancel use the origin transition.
- Android system back and iOS back gesture use the same reverse behavior.

## Verification

- Widget tests cover origin rect present and missing fallback paths.
- Verify one warm handoff/controller for Profile video navigation.
- Verify Feed and Profile `+` both enter and cancel without a stuck route.
- Run focused Flutter analysis and transition-related widget tests.

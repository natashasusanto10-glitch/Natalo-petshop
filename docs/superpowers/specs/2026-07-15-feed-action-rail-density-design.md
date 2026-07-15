# Feed Action Rail Density Design

## Scope

Adjust the action rail shared by Feed photo, carousel, video, and scoped
fullscreen. Do not change action behavior, icon artwork, counts, navigation,
caption layout, product overlays, or backend state.

## Layout

- Keep action icons at 30dp and their 54dp-wide touch target.
- Reduce vertical spacing between action items from 18dp to 10dp.
- Reduce counted item visual height from 60dp to 54dp.
- Keep non-counted item visual height at 44dp.
- Anchor the rail from the bottom.
- Align the lowest action (`More`) vertically with the `Disukai oleh` row.
- Stack Save, Share, Comment, and Like upward from that anchor.
- Preserve safe-area and bottom-navigation clearance.

## Responsive Behavior

The alignment uses the measured position of the shared social-proof row rather
than a device-specific fixed screen coordinate. On compact screens, caption
content may truncate or scroll using existing behavior; the rail must not
overlap the product overlay or bottom navigation.

## Interaction And Accessibility

- Preserve existing semantics, haptics, animations, and action throttling.
- Preserve a minimum 44dp interactive height for every action.
- Counts remain hidden at zero without changing item height.

## Scoped Fullscreen Back Control

- Remove the visible black circular background behind the back arrow.
- Render a 32dp white back arrow with a subtle shadow for contrast over bright
  video frames.
- Keep an invisible 48x48dp tap target around the arrow.
- Preserve the existing top safe-area inset on iOS and Android.
- Preserve edge-swipe back and its interactive transition.

## Acceptance Criteria

- The rail reads as one compact group comparable to Instagram Reels.
- The visual gap between adjacent actions is 10dp.
- The lowest `More` action aligns with `Disukai oleh`.
- Feed photo, carousel, video, and scoped fullscreen use the same geometry.
- No overlap occurs with caption, commerce overlays, safe areas, or navigation.
- Like, comment, share, save, and more actions retain current behavior.
- Scoped fullscreen shows a larger back arrow without a visible black circle.

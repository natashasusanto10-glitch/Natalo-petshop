# Feed Photo/Carousel Comment Drawer Instagram Parity Design

## Goal

Make Feed photo and carousel posts enter the same compact comment state as the working video path: the drawer pushes a clean, uncropped media preview upward while post chrome disappears and the author caption appears only inside the comment drawer.

## Approved Interaction

- The closed Feed remains a black full-screen canvas.
- Photo and carousel media use the source image ratio with `BoxFit.contain`; the app must not crop tall, square, or landscape media to a forced 4:5 frame.
- Tapping Comment opens the existing embedded drawer at its current initial extent and locks vertical Feed paging.
- Drawer extent and media geometry move together one-to-one while opening, dragging, snapping, closing, and responding to the keyboard.
- In compact mode, the media is centered between the top safe area and the drawer edge. Black letterboxing is expected.
- Only media remains above the drawer. Creator identity, caption, social proof, tagged-product UI, carousel indicator, action rail, heart animation layer, and Feed top chrome are removed with a short fade.
- The comment drawer continues to render the post author and caption as its first item, followed by comments and the existing composer.
- Closing restores Feed chrome only after the drawer lifecycle reaches closed, avoiding a mid-transition flash.
- A carousel keeps its selected page and remains horizontally swipeable; vertical Feed paging stays locked until the drawer closes.
- Existing drawer colors, initial extent, maximum extent, snap thresholds, comment data, and composer behavior remain unchanged.

## Architecture

### Shared linked-media frame

Extract the video path's linked rectangle animation into a reusable `FeedCommentMediaFrame`. Both video and photo surfaces consume the same inputs: open phase, sheet-extent listenable, keyboard inset, screen size, and child media. Photo additionally supplies the top safe-area inset for its compact preview.

### Media and overlay separation

`FeedReelsCommentSurface` receives media and optional post overlay as separate children. It animates only media geometry. The overlay is switched out as soon as drawer mounting starts and is switched back only after closing completes.

### Photo renderer

The photo `PageView` is the media child. It renders every slide with `BoxFit.contain` on black and keeps the existing page controller. Creator, caption, commerce, social proof, carousel dots, and actions form the separate overlay child.

### Feed chrome

The Feed-level plus, search, and cart controls fade while an overlay lock is active. They are already non-interactive under this lock; the visual state will now match the interaction state.

## State and Gesture Rules

- The existing `DraggableScrollableController` remains the source of truth for drawer extent.
- Media reads the extent through a `ValueListenable<double>` so drag frames do not rebuild comment data or cached images.
- The comment handle and comment list retain ownership of vertical drawer gestures.
- The carousel retains horizontal gesture ownership.
- The overlay is absent/ignored during the drawer lifecycle so it cannot intercept drawer or media gestures.
- Back, tap-outside, downward fling, and reaching the minimum extent use the existing close lifecycle.

## Edge Cases

- Missing image dimensions do not cause cropping because `BoxFit.contain` uses decoded image proportions.
- Keyboard height is subtracted from both sheet and media calculations.
- At maximum extent the preview can collapse to the remaining safe-area space without exposing Feed overlays.
- Reopening does not recreate the carousel controller or reset the selected slide.
- A failed comment fetch still leaves the compact media and drawer lifecycle usable.

## Verification

Widget tests must prove:

1. photo overlay content is absent after the drawer opens and returns after close;
2. photo widgets use `BoxFit.contain` and no forced 4:5 crop;
3. media bottom tracks drawer top after open and during drag;
4. compact media respects the top safe area;
5. carousel page remains selected across open/close;
6. repeated open/close and back handling remain stable;
7. existing video comment tests remain green except any separately documented pre-existing baseline failure.


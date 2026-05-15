"use client";

/**
 * Lightweight stand-in for a FeedVideoCard when the card is far enough
 * from the active position that mounting the real `<video>` element +
 * action sheet handlers would be wasted memory. Renders only the
 * thumbnail image at full-snap height so scroll position and snap
 * targets stay correct as the virtual window slides.
 */

type Props = {
  thumbnailUrl: string | null;
};

export function FeedPostPlaceholder({ thumbnailUrl }: Props) {
  return (
    <article
      // Match the article snap structure of <FeedVideoCard> so the parent's
      // scroll-snap-mandatory layout still resolves to evenly-spaced cards.
      className="relative min-h-full snap-start overflow-hidden bg-black"
      aria-hidden="true"
    >
      {thumbnailUrl && (
        // eslint-disable-next-line @next/next/no-img-element
        <img
          src={thumbnailUrl}
          alt=""
          loading="lazy"
          // `object-contain` matches the active card's video framing
          // (Instagram Reels style — no crop, thin letterbox bars). Without
          // matching, the user sees a visible jump when scrolling between
          // a placeholder and the real video card.
          className="absolute inset-0 h-full w-full object-contain"
          onError={(event) => {
            event.currentTarget.style.display = "none";
          }}
        />
      )}
      {/* Same dimming gradient as FeedVideoCard so the visual rhythm stays
          consistent while scrolling past. */}
      <div className="pointer-events-none absolute inset-0 bg-gradient-to-b from-black/35 via-black/5 to-black/82" />
    </article>
  );
}

"use client";

export const FEED_PLAYBACK_TEARDOWN_EVENT = "natalo:feed-playback-teardown";

type FeedPlaybackTeardownDetail = {
  reason: string;
};

export function teardownFeedPlaybackNow(reason: string) {
  if (typeof window === "undefined" || typeof document === "undefined") return;

  window.dispatchEvent(
    new CustomEvent<FeedPlaybackTeardownDetail>(FEED_PLAYBACK_TEARDOWN_EVENT, {
      detail: { reason },
    }),
  );

  document.querySelectorAll<HTMLElement>("[data-feed-loading-overlay]").forEach((node) => {
    node.style.display = "none";
  });

  document
    .querySelectorAll<HTMLVideoElement>("[data-feed-video], [data-feed-video-player] video")
    .forEach((video) => {
      try {
        video.pause();
        video.removeAttribute("autoplay");
        video.removeAttribute("src");
        video.preload = "none";
        video.load();
      } catch {
        // Best effort only. Navigation must never wait on media cleanup.
      }
    });
}

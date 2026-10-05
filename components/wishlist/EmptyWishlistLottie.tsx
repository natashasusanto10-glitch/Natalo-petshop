"use client";

import { useEffect, useRef, useState } from "react";
import type { AnimationItem } from "lottie-web";

const SOURCE = "/assets/lottie/wishlist-pets-cards-v1.json";
const STILL = "/assets/images/wishlist-pets-cards-v1.svg";

export function EmptyWishlistLottie() {
  const container = useRef<HTMLDivElement>(null);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    const abort = new AbortController();
    let animation: AnimationItem | undefined;
    let observer: IntersectionObserver | undefined;
    let inView = true;
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)");
    const sync = () => {
      if (!animation) return;
      if (reduced.matches) animation.goToAndStop(135, true);
      else if (document.hidden || !inView) animation.pause();
      else animation.play();
    };
    async function load() {
      try {
        const [player, response] = await Promise.all([import("lottie-web"), fetch(SOURCE, { signal: abort.signal, cache: "force-cache" })]);
        if (!response.ok) throw new Error("Wishlist animation unavailable");
        const animationData = await response.json();
        if (abort.signal.aborted || !container.current) return;
        animation = player.default.loadAnimation({ container: container.current, renderer: "svg", autoplay: false, loop: true, animationData });
        animation.addEventListener("DOMLoaded", () => { if (!abort.signal.aborted) { setReady(true); sync(); } });
        animation.addEventListener("data_failed", () => { if (!abort.signal.aborted) setReady(false); });
        observer = new IntersectionObserver(entries => { inView = entries[0]?.isIntersecting ?? false; sync(); });
        observer.observe(container.current);
      } catch {
        // Keep the matching static illustration visible when loading fails.
      }
    }
    reduced.addEventListener("change", sync);
    document.addEventListener("visibilitychange", sync);
    void load();
    return () => { abort.abort(); observer?.disconnect(); animation?.destroy(); reduced.removeEventListener("change", sync); document.removeEventListener("visibilitychange", sync); };
  }, []);

  return <div className="relative mx-auto mb-5 aspect-[640/460] w-full max-w-[280px]" aria-hidden="true">
    <div ref={container} className={`absolute inset-0 ${ready ? "" : "invisible"}`} />
    {!ready && <img src={STILL} alt="" width={640} height={460} className="h-full w-full object-contain" />}
  </div>;
}

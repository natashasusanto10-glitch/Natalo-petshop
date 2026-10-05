"use client";

import { useEffect, useRef, useState } from "react";
import type { AnimationItem } from "lottie-web";
import assets from "./shortcut-assets.json";

export type ShortcutArtwork = keyof typeof assets;

export function AnimatedShortcutIcon({ artwork }: { artwork: ShortcutArtwork }) {
  const host = useRef<HTMLDivElement>(null);
  const container = useRef<HTMLDivElement>(null);
  const [ready, setReady] = useState(false);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    setReady(false);
    setFailed(false);
    const node = host.current;
    if (!node) return;
    let disposed = false;
    let loading = false;
    let visible = false;
    let animation: AnimationItem | undefined;
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)");
    const sync = () => {
      if (!animation) return;
      if (visible && !reduce.matches && document.visibilityState === "visible") animation.play();
      else animation.pause();
    };
    const fail = (error: unknown) => {
      if (disposed) return;
      console.error(`Failed to load shortcut ${artwork}`, error);
      animation?.destroy();
      animation = undefined;
      setFailed(true);
    };
    const load = async () => {
      if (disposed || loading || animation || reduce.matches) return;
      loading = true;
      try {
        const module = await import("lottie-web");
        if (disposed || !container.current) return;
        animation = module.default.loadAnimation({
          container: container.current, renderer: "svg", loop: true, autoplay: false,
          // Async loading lets error/ready listeners attach before initialization.
          // Content-hashed URLs use the browser's immutable asset cache.
          path: assets[artwork].animation,
          assetsPath: "/assets/lottie/shortcuts/",
          rendererSettings: { preserveAspectRatio: "xMidYMid meet" },
        });
        animation.setSubframe(false);
        animation.addEventListener("DOMLoaded", () => {
          if (!disposed) { setReady(true); sync(); }
        });
        animation.addEventListener("data_failed", () => fail(new Error("Invalid Lottie data")));
        animation.addEventListener("error", event => fail(event));
        sync();
      } catch (error) { fail(error); }
    };
    let near = false;
    const preloadObserver = new IntersectionObserver(entries => {
      near = entries.some(entry => entry.isIntersecting);
      if (near) void load();
    }, { rootMargin: "180px" });
    const playbackObserver = new IntersectionObserver(entries => {
      visible = entries.some(entry => entry.isIntersecting);
      sync();
    });
    const motionChanged = () => { if (near && !reduce.matches) void load(); sync(); };
    preloadObserver.observe(node);
    playbackObserver.observe(node);
    reduce.addEventListener("change", motionChanged);
    document.addEventListener("visibilitychange", sync);
    return () => {
      disposed = true;
      preloadObserver.disconnect();
      playbackObserver.disconnect();
      reduce.removeEventListener("change", motionChanged);
      document.removeEventListener("visibilitychange", sync);
      animation?.destroy();
    };
  }, [artwork]);

  return (
    <div ref={host} aria-hidden="true" className="relative h-14 w-14 shrink-0 md:h-16 md:w-16" data-shortcut-artwork={artwork}>
      {/* A meaningful still is visible during loading, reduced motion and errors. */}
      <img src={assets[artwork].still} alt="" width={56} height={56} loading="lazy" decoding="async"
        className={`absolute inset-0 h-full w-full object-contain ${ready && !failed ? "motion-safe:invisible" : ""}`} />
      <div ref={container} className={`h-full w-full motion-reduce:invisible ${failed ? "invisible" : ""}`} />
    </div>
  );
}

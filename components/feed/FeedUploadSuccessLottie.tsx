"use client";

/**
 * Lottie success animation untuk upload video feed berhasil.
 * Tema Natalo Feed video upload success:
 * kamera/video, kucing, anjing, cloud upload, check hijau, paw/heart/sparkle.
 * Autoplay true, loop false, fallback image kalau Lottie gagal load.
 */
import Image from "next/image";
import { useEffect, useRef, useState } from "react";
import type { AnimationItem } from "lottie-web";

const FEED_LOTTIE_SRC = "/assets/lottie/feed_video_upload_success_natalo.json";
const FALLBACK_IMAGE_SRC =
  "/assets/images/feed_video_upload_success_fallback.png";

export function FeedUploadSuccessLottie() {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const animationRef = useRef<AnimationItem | null>(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let cancelled = false;

    async function loadAnimation() {
      try {
        const [lottie, response] = await Promise.all([
          import("lottie-web"),
          fetch(FEED_LOTTIE_SRC, { cache: "force-cache" }),
        ]);

        if (!response.ok) throw new Error("Feed upload success Lottie not found");
        const animationData = await response.json();
        if (cancelled || !containerRef.current) return;

        const animation = lottie.default.loadAnimation({
          container: containerRef.current,
          renderer: "svg",
          loop: false,
          autoplay: true,
          animationData,
          rendererSettings: {
            progressiveLoad: true,
            preserveAspectRatio: "xMidYMid meet",
          },
        });

        animationRef.current = animation;
        animation.addEventListener("data_failed", () => {
          if (!cancelled) setFailed(true);
        });
      } catch {
        if (!cancelled) setFailed(true);
      }
    }

    void loadAnimation();

    return () => {
      cancelled = true;
      animationRef.current?.destroy();
      animationRef.current = null;
    };
  }, []);

  return (
    <div
      className="relative mx-auto h-[240px] w-full max-w-[280px]"
      aria-hidden="true"
    >
      <div
        ref={containerRef}
        className={`h-full w-full ${failed ? "hidden" : ""}`}
      />
      {failed ? (
        <Image
          src={FALLBACK_IMAGE_SRC}
          alt=""
          fill
          sizes="280px"
          className="object-contain"
          priority={false}
        />
      ) : null}
    </div>
  );
}

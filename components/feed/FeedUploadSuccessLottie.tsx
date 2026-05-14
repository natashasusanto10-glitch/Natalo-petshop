"use client";

/**
 * Lottie success animation untuk upload video feed berhasil.
 * Spec section 7:
 * - Tema Natalo biru
 * - Autoplay true, loop false (max 1-2 kali)
 * - Fallback image kalau Lottie gagal load
 *
 * Pakai existing pattern dari OrderCreatedSuccessLottie. Asset path:
 * /assets/lottie/feed_upload_success_cat_dog.json (perlu di-upload terpisah;
 * untuk MVP fallback ke order_created_success Lottie kalau file belum ada).
 */
import Image from "next/image";
import { useEffect, useRef, useState } from "react";
import type { AnimationItem } from "lottie-web";

const FEED_LOTTIE_SRC = "/assets/lottie/feed_upload_success_cat_dog.json";
// Fallback chain: kalau cat-dog Lottie belum ada, pakai order success.
const FALLBACK_LOTTIE_SRC = "/assets/lottie/order_created_success_natalo_blue.json";
const FALLBACK_IMAGE_SRC = "/assets/images/order_created_success_fallback.png";

export function FeedUploadSuccessLottie() {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const animationRef = useRef<AnimationItem | null>(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let cancelled = false;

    async function tryLoad(src: string) {
      const lottie = await import("lottie-web");
      const response = await fetch(src, { cache: "force-cache" });
      if (!response.ok) throw new Error(`Asset 404: ${src}`);
      const animationData = await response.json();
      if (cancelled || !containerRef.current) return null;
      return lottie.default.loadAnimation({
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
    }

    async function loadAnimation() {
      try {
        const anim = (await tryLoad(FEED_LOTTIE_SRC).catch(() => null)) ||
          (await tryLoad(FALLBACK_LOTTIE_SRC).catch(() => null));
        if (!anim) {
          if (!cancelled) setFailed(true);
          return;
        }
        animationRef.current = anim;
        anim.addEventListener("data_failed", () => {
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
      className="relative mx-auto h-[220px] w-full max-w-[280px]"
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

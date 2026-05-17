"use client";

/**
 * BlurhashCanvas — decode blurhash string ke <canvas> 32x32 sebagai LQIP
 * placeholder. Render dengan CSS image-rendering smooth jadi canvas
 * kecil di-scale up ke ukuran container tanpa pixelated.
 *
 * Performa:
 *   - Decode: ~1-3ms di main thread (32x32 = 1024 piksel × 4 channel)
 *   - Render: bg-blur effect murah, GPU compositor handle
 *   - Memory: ~4 KB ImageData per instance
 *
 * Usage:
 *   <BlurhashCanvas hash="LEHV6nWB2yk8pyo0adR*.7kCMdnj" className="..." />
 *
 * Hash null/invalid → render null, caller fallback ke bg solid.
 */
import { useEffect, useRef } from "react";
import { decode as blurhashDecode, isBlurhashValid } from "blurhash";

const CANVAS_W = 32;
const CANVAS_H = 32;

type Props = {
  hash: string | null | undefined;
  className?: string;
};

export function BlurhashCanvas({ hash, className }: Props) {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    if (!hash) return;
    // Validate dulu — blurhashDecode throw kalau format invalid (mis. hash
    // ke-corrupt di DB atau truncated). Cheaper than try/catch tiap mount.
    const check = isBlurhashValid(hash);
    if (!check.result) return;

    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    try {
      const pixels = blurhashDecode(hash, CANVAS_W, CANVAS_H);
      const imageData = ctx.createImageData(CANVAS_W, CANVAS_H);
      imageData.data.set(pixels);
      ctx.putImageData(imageData, 0, 0);
    } catch {
      // Decode error — diam saja. Caller fallback ke bg solid behind.
    }
  }, [hash]);

  if (!hash) return null;

  return (
    <canvas
      ref={canvasRef}
      width={CANVAS_W}
      height={CANVAS_H}
      // Scale up 32x32 ke container size pakai CSS. `image-rendering:
      // auto` (default) bikin browser interpolate smooth — blur naturally
      // dari upscaling. No need bg-blur filter.
      className={className}
      // Disable accessibility tree — pure decorative placeholder.
      aria-hidden="true"
    />
  );
}

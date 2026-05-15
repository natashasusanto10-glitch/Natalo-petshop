/**
 * Helpers untuk handle video file di client-side sebelum upload:
 * - Extract thumbnail frame via Canvas API (no server-side processing)
 * - Extract metadata (duration, width, height) via <video> element
 *
 * Browser support: modern (Chrome/Safari/Firefox 14+, iOS Safari 14+).
 * Cross-origin video → canvas tainted, tidak bisa toBlob. Karena user
 * upload file local (blob URL), seharusnya aman.
 */

export type VideoMetadata = {
  durationSec: number;
  width: number;
  height: number;
};

export type VideoThumbnailResult = {
  blob: Blob;
  usedFallback: boolean;
};

const DEFAULT_THUMBNAIL_TIMEOUT_MS = 30000;

/**
 * Render video ke <video> hidden, baca dimension + duration setelah
 * `loadedmetadata` fire.
 */
export function readVideoMetadata(file: File): Promise<VideoMetadata> {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const video = document.createElement("video");
    video.muted = true;
    video.preload = "metadata";

    const cleanup = () => {
      video.src = "";
      URL.revokeObjectURL(url);
    };

    const timeout = window.setTimeout(() => {
      cleanup();
      reject(new Error("Gagal baca metadata video (timeout)."));
    }, 15000);

    video.onloadedmetadata = () => {
      window.clearTimeout(timeout);
      const result: VideoMetadata = {
        durationSec: Number.isFinite(video.duration) ? video.duration : 0,
        width: video.videoWidth || 0,
        height: video.videoHeight || 0,
      };
      cleanup();
      resolve(result);
    };
    video.onerror = () => {
      window.clearTimeout(timeout);
      cleanup();
      reject(new Error("Video tidak bisa di-baca (format mungkin tidak didukung)."));
    };

    video.src = url;
  });
}

/**
 * Extract frame video pada `targetTimeSec` (default 1.0) → JPEG blob.
 * Dipakai sebagai thumbnail saat user upload video. Spec section 10.2:
 * "Setiap video wajib memiliki thumbnail/poster".
 *
 * Quality default 0.85 — balance antara size (target <100KB) + visual.
 */
export async function extractVideoThumbnail(
  file: File,
  options: {
    targetTimeSec?: number;
    maxWidth?: number;
    quality?: number;
    timeoutMs?: number;
  } = {},
): Promise<Blob> {
  const {
    targetTimeSec = 1.0,
    maxWidth = 480,
    quality = 0.82,
    timeoutMs = DEFAULT_THUMBNAIL_TIMEOUT_MS,
  } = options;

  return new Promise<Blob>((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const video = document.createElement("video");
    video.muted = true;
    video.playsInline = true;
    video.preload = "auto";
    video.crossOrigin = "anonymous";

    const cleanup = () => {
      video.src = "";
      URL.revokeObjectURL(url);
    };

    const timeout = window.setTimeout(() => {
      cleanup();
      reject(new Error("Gagal extract thumbnail (timeout)."));
    }, timeoutMs);

    function onSeeked() {
      try {
        const srcWidth = video.videoWidth;
        const srcHeight = video.videoHeight;
        if (!srcWidth || !srcHeight) {
          throw new Error("Dimensi video tidak terbaca.");
        }

        // Scale down kalau lebih besar dari maxWidth, preserve aspect.
        const scale = srcWidth > maxWidth ? maxWidth / srcWidth : 1;
        const targetWidth = Math.round(srcWidth * scale);
        const targetHeight = Math.round(srcHeight * scale);

        const canvas = document.createElement("canvas");
        canvas.width = targetWidth;
        canvas.height = targetHeight;
        const ctx = canvas.getContext("2d");
        if (!ctx) throw new Error("Canvas context tidak tersedia.");
        ctx.drawImage(video, 0, 0, targetWidth, targetHeight);

        canvas.toBlob(
          (blob) => {
            window.clearTimeout(timeout);
            cleanup();
            if (!blob) {
              reject(new Error("toBlob mengembalikan null."));
              return;
            }
            resolve(blob);
          },
          "image/jpeg",
          quality,
        );
      } catch (err) {
        window.clearTimeout(timeout);
        cleanup();
        reject(err instanceof Error ? err : new Error("Gagal extract thumbnail."));
      }
    }

    video.onloadedmetadata = () => {
      // Kalau video lebih pendek dari targetTime, skip ke 0 atau 0.5 * duration.
      const seek = Math.min(targetTimeSec, (video.duration || 1) * 0.5);
      video.currentTime = Math.max(0, seek);
    };
    video.onseeked = onSeeked;
    video.onerror = () => {
      window.clearTimeout(timeout);
      cleanup();
      reject(new Error("Video tidak bisa di-decode untuk thumbnail."));
    };

    video.src = url;
  });
}

export async function createFallbackVideoThumbnail(
  metadata?: Partial<VideoMetadata>,
): Promise<Blob> {
  const width = 360;
  const height = Math.max(
    360,
    Math.round(width / Math.max(0.55, Math.min(1.8, (metadata?.width ?? 9) / (metadata?.height ?? 16)))),
  );
  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  const ctx = canvas.getContext("2d");
  if (!ctx) {
    return new Blob([], { type: "image/jpeg" });
  }

  const gradient = ctx.createLinearGradient(0, 0, width, height);
  gradient.addColorStop(0, "#05070b");
  gradient.addColorStop(0.55, "#101827");
  gradient.addColorStop(1, "#1e5fbf");
  ctx.fillStyle = gradient;
  ctx.fillRect(0, 0, width, height);

  ctx.fillStyle = "rgba(255,255,255,0.13)";
  ctx.beginPath();
  ctx.arc(width * 0.82, height * 0.18, 74, 0, Math.PI * 2);
  ctx.fill();

  ctx.fillStyle = "rgba(255,255,255,0.9)";
  ctx.beginPath();
  ctx.moveTo(width / 2 - 28, height / 2 - 38);
  ctx.lineTo(width / 2 - 28, height / 2 + 38);
  ctx.lineTo(width / 2 + 42, height / 2);
  ctx.closePath();
  ctx.fill();

  return new Promise<Blob>((resolve) => {
    canvas.toBlob(
      (blob) => resolve(blob ?? new Blob([], { type: "image/jpeg" })),
      "image/jpeg",
      0.78,
    );
  });
}

export async function extractVideoThumbnailSafe(
  file: File,
  metadata: VideoMetadata,
  options: {
    targetTimeSec?: number;
    maxWidth?: number;
    quality?: number;
    timeoutMs?: number;
    onError?: (error: unknown) => void;
  } = {},
): Promise<VideoThumbnailResult> {
  try {
    const blob = await extractVideoThumbnail(file, options);
    return { blob, usedFallback: false };
  } catch (error) {
    options.onError?.(error);
    return {
      blob: await createFallbackVideoThumbnail(metadata),
      usedFallback: true,
    };
  }
}

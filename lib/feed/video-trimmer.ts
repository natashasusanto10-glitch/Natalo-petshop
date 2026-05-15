import { getFFmpeg, fetchVideoFile } from "./ffmpeg";
import { CompressionFailedError } from "./video-errors";

const TRIM_TIMEOUT_MS = 60_000;

/**
 * Cut a sub-range out of a source video WITHOUT re-encoding.
 *
 * `-c copy` tells ffmpeg to stream-copy both video and audio. No frame
 * decode, no x264, no quality loss — orders of magnitude faster than
 * the full transcode `compressVideo()` does. The result is the same
 * codec/format as the source (MP4 or MOV with H.264/HEVC inside),
 * which is exactly what Bunny Stream expects as input.
 *
 * Note: stream-copy can only cut on keyframe boundaries. ffmpeg's
 * `-ss` before `-i` does an inexact seek (much faster) to the nearest
 * keyframe, so the actual cut may be a few hundred ms different from
 * the user's slider position. Acceptable trade-off for 10x speed.
 */
export async function trimVideo(
  file: File,
  options: {
    trimStartSec: number;
    trimDurationSec: number;
    onProgress?: (pct: number) => void;
  },
): Promise<Blob> {
  const ffmpeg = await getFFmpeg();

  const ext =
    file.type === "video/quicktime"
      ? "mov"
      : file.type === "video/webm"
        ? "webm"
        : "mp4";
  const inputName = `input.${ext}`;
  const outputName = `trimmed-${Date.now()}.mp4`;

  function handleProgress({ progress }: { progress: number }) {
    if (!Number.isFinite(progress)) return;
    options.onProgress?.(Math.max(0, Math.min(100, Math.round(progress * 100))));
  }

  const timeoutPromise = new Promise<never>((_, reject) => {
    setTimeout(
      () =>
        reject(new CompressionFailedError("Memotong video terlalu lama (>60 detik).")),
      TRIM_TIMEOUT_MS,
    );
  });

  const trimPromise = (async () => {
    ffmpeg.on("progress", handleProgress);
    try {
      await ffmpeg.writeFile(inputName, await fetchVideoFile(file));
      await ffmpeg.exec([
        "-ss",
        String(Math.max(0, options.trimStartSec)),
        "-t",
        String(Math.max(0.1, options.trimDurationSec)),
        "-i",
        inputName,
        // No -c:v / -c:a / -crf / -preset — `-c copy` keeps original
        // streams. Bunny will do the heavy encoding.
        "-c",
        "copy",
        "-movflags",
        "+faststart",
        outputName,
      ]);
      const data = await ffmpeg.readFile(outputName);
      const bytes =
        typeof data === "string" ? new TextEncoder().encode(data) : new Uint8Array(data);
      return new Blob([bytes], { type: "video/mp4" });
    } finally {
      ffmpeg.off("progress", handleProgress);
      await Promise.allSettled([
        ffmpeg.deleteFile(inputName),
        ffmpeg.deleteFile(outputName),
      ]);
    }
  })();

  try {
    return await Promise.race([trimPromise, timeoutPromise]);
  } catch (err) {
    if (err instanceof CompressionFailedError) throw err;
    throw new CompressionFailedError(err instanceof Error ? err.message : undefined);
  }
}

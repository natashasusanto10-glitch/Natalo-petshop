import { getFFmpeg, fetchVideoFile } from "./ffmpeg";
import type { FeedVideoConfig } from "./video-config";
import { CompressionFailedError } from "./video-errors";

export type CompressOptions = {
  config: FeedVideoConfig;
  onProgress?: (progress: number) => void;
  trimStartSec?: number;
  trimDurationSec?: number;
};

// Hard timeout for the entire compress pipeline. ffmpeg.wasm on iOS
// WKWebView can hang indefinitely when it runs out of memory decoding
// large 4K HEVC clips — without a timeout the upload flow silently
// stalls and the user sees no error. 90s is enough for a typical 1080p
// 30s clip at preset=veryfast; anything longer is a sign the WASM
// sandbox is gone and we should fail loudly so the user can retry.
const COMPRESSION_TIMEOUT_MS = 90_000;

function getInputName(file: File) {
  const ext = file.name.split(".").pop()?.toLowerCase();
  if (ext && /^[a-z0-9]+$/.test(ext)) return `input.${ext}`;
  if (file.type === "video/quicktime") return "input.mov";
  if (file.type === "video/webm") return "input.webm";
  return "input.mp4";
}

export async function compressVideo(file: File, options: CompressOptions): Promise<File> {
  const { config, onProgress, trimStartSec, trimDurationSec } = options;
  const inputName = getInputName(file);
  const outputName = `output-${Date.now()}.mp4`;
  const ffmpeg = await getFFmpeg();

  const handleProgress = ({ progress }: { progress: number }) => {
    if (!Number.isFinite(progress)) return;
    onProgress?.(Math.max(0, Math.min(100, Math.round(progress * 100))));
  };

  // Race the actual compression against a timeout. Whichever finishes
  // first wins; on timeout we throw so runUpload can emit an error event
  // instead of leaving the upload stalled forever.
  const timeoutPromise = new Promise<never>((_, reject) => {
    setTimeout(() => {
      reject(
        new CompressionFailedError(
          "Kompres video terlalu lama (>90 detik). Coba video lebih pendek atau resolusi lebih rendah.",
        ),
      );
    }, COMPRESSION_TIMEOUT_MS);
  });

  const compressPromise = (async () => {
    ffmpeg.on("progress", handleProgress);
    try {
      await ffmpeg.writeFile(inputName, await fetchVideoFile(file));

      const trimArgs =
        Number.isFinite(trimStartSec) && Number.isFinite(trimDurationSec)
          ? [
              "-ss",
              String(Math.max(0, trimStartSec ?? 0)),
              "-t",
              String(Math.max(0.1, trimDurationSec ?? 0.1)),
            ]
          : [];

      await ffmpeg.exec([
        ...trimArgs,
        "-i",
        inputName,
        "-c:v",
        config.videoCodec,
        "-crf",
        String(config.crf),
        "-preset",
        config.preset,
        "-vf",
        `scale='if(gt(iw,ih),-2,${config.resolution})':'if(gt(iw,ih),${config.resolution},-2)'`,
        "-b:v",
        config.videoBitrate,
        "-maxrate",
        config.videoBitrate,
        "-bufsize",
        String(parseInt(config.videoBitrate, 10) * 2 || 3000) + "k",
        "-r",
        String(config.fps),
        "-c:a",
        config.audioCodec,
        "-b:a",
        config.audioBitrate,
        "-ac",
        "2",
        "-movflags",
        "+faststart",
        "-pix_fmt",
        "yuv420p",
        outputName,
      ]);

      const data = await ffmpeg.readFile(outputName);
      const bytes =
        typeof data === "string" ? new TextEncoder().encode(data) : new Uint8Array(data);

      return new File([bytes], `feed-video-${Date.now()}.mp4`, { type: "video/mp4" });
    } finally {
      ffmpeg.off("progress", handleProgress);
      await Promise.allSettled([
        ffmpeg.deleteFile(inputName),
        ffmpeg.deleteFile(outputName),
      ]);
    }
  })();

  try {
    return await Promise.race([compressPromise, timeoutPromise]);
  } catch (err) {
    if (err instanceof CompressionFailedError) throw err;
    throw new CompressionFailedError(err instanceof Error ? err.message : undefined);
  }
}

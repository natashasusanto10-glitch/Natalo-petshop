import { getFFmpeg, fetchVideoFile } from "./ffmpeg";
import type { FeedVideoConfig } from "./video-config";
import { CompressionFailedError } from "./video-errors";

export type CompressOptions = {
  config: FeedVideoConfig;
  onProgress?: (progress: number) => void;
};

function getInputName(file: File) {
  const ext = file.name.split(".").pop()?.toLowerCase();
  if (ext && /^[a-z0-9]+$/.test(ext)) return `input.${ext}`;
  if (file.type === "video/quicktime") return "input.mov";
  if (file.type === "video/webm") return "input.webm";
  return "input.mp4";
}

export async function compressVideo(file: File, options: CompressOptions): Promise<File> {
  const { config, onProgress } = options;
  const inputName = getInputName(file);
  const outputName = `output-${Date.now()}.mp4`;
  const ffmpeg = await getFFmpeg();

  const handleProgress = ({ progress }: { progress: number }) => {
    if (!Number.isFinite(progress)) return;
    onProgress?.(Math.max(0, Math.min(100, Math.round(progress * 100))));
  };

  try {
    ffmpeg.on("progress", handleProgress);
    await ffmpeg.writeFile(inputName, await fetchVideoFile(file));

    await ffmpeg.exec([
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
  } catch (err) {
    throw new CompressionFailedError(err instanceof Error ? err.message : undefined);
  } finally {
    ffmpeg.off("progress", handleProgress);
    await Promise.allSettled([ffmpeg.deleteFile(inputName), ffmpeg.deleteFile(outputName)]);
  }
}

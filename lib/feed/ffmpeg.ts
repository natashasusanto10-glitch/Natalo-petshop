import type { FFmpeg } from "@ffmpeg/ffmpeg";
import type { fetchFile as fetchFileType } from "@ffmpeg/util";
import { FFmpegNotSupportedError } from "./video-errors";

let ffmpegInstance: FFmpeg | null = null;
let loadingPromise: Promise<FFmpeg> | null = null;
let fetchFileImpl: typeof fetchFileType | null = null;

export async function getFFmpeg(): Promise<FFmpeg> {
  if (typeof window === "undefined") {
    throw new FFmpegNotSupportedError();
  }
  if (ffmpegInstance) return ffmpegInstance;
  if (loadingPromise) return loadingPromise;

  loadingPromise = (async () => {
    const [{ FFmpeg }, { toBlobURL, fetchFile }] = await Promise.all([
      import("@ffmpeg/ffmpeg"),
      import("@ffmpeg/util"),
    ]);
    fetchFileImpl = fetchFile;

    const ffmpeg = new FFmpeg();
    const baseURL = "https://unpkg.com/@ffmpeg/core@0.12.10/dist/umd";

    await ffmpeg.load({
      coreURL: await toBlobURL(`${baseURL}/ffmpeg-core.js`, "text/javascript"),
      wasmURL: await toBlobURL(`${baseURL}/ffmpeg-core.wasm`, "application/wasm"),
    });

    ffmpegInstance = ffmpeg;
    return ffmpeg;
  })();

  return loadingPromise;
}

export async function fetchVideoFile(file: File) {
  if (!fetchFileImpl) {
    await getFFmpeg();
  }
  if (!fetchFileImpl) throw new FFmpegNotSupportedError();
  return fetchFileImpl(file);
}

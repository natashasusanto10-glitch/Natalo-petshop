import type { FFmpeg } from "@ffmpeg/ffmpeg";
import type { fetchFile as fetchFileType } from "@ffmpeg/util";
import { FFmpegNotSupportedError } from "./video-errors";

let ffmpegInstance: FFmpeg | null = null;
let loadingPromise: Promise<FFmpeg> | null = null;
let loadingInstance: FFmpeg | null = null;
let loadGeneration = 0;
let fetchFileImpl: typeof fetchFileType | null = null;

export async function getFFmpeg(): Promise<FFmpeg> {
  if (typeof window === "undefined") {
    throw new FFmpegNotSupportedError();
  }
  if (ffmpegInstance) return ffmpegInstance;
  if (loadingPromise) return loadingPromise;

  const generation = loadGeneration;
  loadingPromise = (async () => {
    const [{ FFmpeg }, { toBlobURL, fetchFile }] = await Promise.all([
      import("@ffmpeg/ffmpeg"),
      import("@ffmpeg/util"),
    ]);
    if (generation !== loadGeneration)
      throw new Error("Persiapan kompresi dibatalkan. Coba kembali.");
    fetchFileImpl = fetchFile;

    const ffmpeg = new FFmpeg();
    loadingInstance = ffmpeg;
    const baseURL = "https://unpkg.com/@ffmpeg/core@0.12.10/dist/umd";

    const resources = await Promise.allSettled([
      toBlobURL(`${baseURL}/ffmpeg-core.js`, "text/javascript"),
      toBlobURL(`${baseURL}/ffmpeg-core.wasm`, "application/wasm"),
    ]);
    try {
      const failure = resources.find(
        (resource) => resource.status === "rejected"
      );
      if (failure?.status === "rejected") throw failure.reason;
      const [core, wasm] = resources;
      if (core.status !== "fulfilled" || wasm.status !== "fulfilled")
        throw new Error("Persiapan kompresi gagal. Coba kembali.");
      if (generation !== loadGeneration)
        throw new Error("Persiapan kompresi dibatalkan. Coba kembali.");
      await ffmpeg.load({ coreURL: core.value, wasmURL: wasm.value });
      if (generation !== loadGeneration)
        throw new Error("Persiapan kompresi dibatalkan. Coba kembali.");
    } catch (error) {
      ffmpeg.terminate();
      throw error;
    } finally {
      for (const resource of resources) {
        if (resource.status === "fulfilled")
          URL.revokeObjectURL(resource.value);
      }
    }

    ffmpegInstance = ffmpeg;
    loadingInstance = null;
    return ffmpeg;
  })().catch((error) => {
    if (generation === loadGeneration) {
      loadingInstance?.terminate();
      loadingInstance = null;
      loadingPromise = null;
      fetchFileImpl = null;
    }
    throw error;
  });

  return loadingPromise;
}

export async function fetchVideoFile(file: File) {
  if (!fetchFileImpl) {
    await getFFmpeg();
  }
  if (!fetchFileImpl) throw new FFmpegNotSupportedError();
  return fetchFileImpl(file);
}

export function resetFFmpeg() {
  loadGeneration++;
  (ffmpegInstance ?? loadingInstance)?.terminate();
  ffmpegInstance = null;
  loadingInstance = null;
  loadingPromise = null;
  fetchFileImpl = null;
}

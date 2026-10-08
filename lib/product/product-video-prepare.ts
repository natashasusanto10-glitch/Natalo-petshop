import { readVideoMetadata } from "@/lib/feed/video-thumbnail";
import { USER_VIDEO_CONFIG } from "@/lib/feed/video-config";

export const PRODUCT_VIDEO_MAX_BYTES = 200 * 1024 * 1024;
export const PRODUCT_VIDEO_MIN_SECONDS = 10;
export const PRODUCT_VIDEO_MAX_SECONDS = 60;

const TYPES = new Set(["video/mp4", "video/quicktime", "video/webm"]);

export function isProductVideoType(file: File): boolean {
  return TYPES.has(file.type);
}

class CopyNotSupportedError extends Error {}

/** Independent worker: product trimming must not reset a Feed encoding job. */
async function copyVideoRange(file: File, start: number, duration: number, onProgress?: (percent: number) => void): Promise<File> {
  let worker: import("@ffmpeg/ffmpeg").FFmpeg | undefined;
  const resources: string[] = [];
  const controller = new AbortController();
  let expired = false;
  let timer: ReturnType<typeof setTimeout> | undefined;
  const assertActive = () => { if (expired) throw new Error("Pemotongan video dibatalkan."); };
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(() => {
      expired = true;
      controller.abort();
      worker?.terminate();
      reject(new Error("Pemotongan video melewati 60 detik. Coba potong video di perangkat sebelum mengunggah."));
    }, 60_000);
  });
  const job = (async () => {
    const { FFmpeg } = await import("@ffmpeg/ffmpeg");
    assertActive();
    worker = new FFmpeg();
    const base = "https://unpkg.com/@ffmpeg/core@0.12.10/dist/umd";
    const loadResource = async (name: string) => {
      const response = await fetch(`${base}/${name}`, { signal: controller.signal });
      if (!response.ok) throw new Error("Mesin pemotongan video belum dapat dimuat. Coba kembali.");
      const blob = await response.blob();
      assertActive();
      const url = URL.createObjectURL(blob);
      resources.push(url);
      return url;
    };
    // allSettled ensures sibling resource loads finish before cleanup.
    const loaded = await Promise.allSettled([loadResource("ffmpeg-core.js"), loadResource("ffmpeg-core.wasm")]);
    assertActive();
    const [core, wasm] = loaded;
    if (core.status === "rejected") throw core.reason;
    if (wasm.status === "rejected") throw wasm.reason;
    await worker.load({ coreURL: core.value, wasmURL: wasm.value });
    assertActive();
    const extension = file.type === "video/webm" ? "webm" : file.type === "video/quicktime" ? "mov" : "mp4";
    const input = `input.${extension}`, output = `trimmed.${extension}`;
    const bytes = new Uint8Array(await file.arrayBuffer());
    assertActive();
    await worker.writeFile(input, bytes);
    worker.on("progress", ({ progress }) => {
      if (!expired && Number.isFinite(progress)) onProgress?.(Math.max(0, Math.min(99, Math.round(progress * 100))));
    });
    const exitCode = await worker.exec([
      "-ss", String(start), "-t", String(duration), "-i", input,
      "-map", "0:v:0", "-map", "0:a:0?", "-c", "copy",
      ...(extension === "webm" ? [] : ["-movflags", "+faststart"]), output,
    ]);
    assertActive();
    if (exitCode !== 0) throw new CopyNotSupportedError("Video tidak mendukung pemotongan cepat.");
    const data = await worker.readFile(output);
    assertActive();
    if (typeof data === "string") throw new CopyNotSupportedError("Hasil pemotongan tidak valid.");
    return new File([new Uint8Array(data)], `product-video.${extension}`, { type: file.type });
  })();
  try {
    return await Promise.race([job, timeout]);
  } finally {
    clearTimeout(timer);
    expired = true;
    controller.abort();
    worker?.terminate();
    resources.forEach(url => URL.revokeObjectURL(url));
  }
}

export async function prepareProductVideo(file: File, options: {
  trimStartSec: number; trimEndSec: number;
  onPhase?(phase: "check" | "trim" | "compress"): void;
  onProgress?(percent: number): void;
}): Promise<{ file: File; durationSec: number }> {
  if (!isProductVideoType(file)) throw new Error("Pilih video MP4, MOV, atau WebM.");
  if (file.size === 0 || file.size > PRODUCT_VIDEO_MAX_BYTES) throw new Error("Ukuran video harus lebih dari 0 dan maksimal 200 MB.");
  options.onPhase?.("check");
  const source = await readVideoMetadata(file);
  if (!Number.isFinite(source.durationSec) || source.durationSec <= 0 || source.width <= 0 || source.height <= 0) {
    throw new Error("Durasi atau dimensi video tidak dapat dibaca. Pilih video lain.");
  }
  const sourceFits = Math.max(source.width, source.height) <= 3840 && Math.min(source.width, source.height) <= 2160;
  const start = options.trimStartSec, end = options.trimEndSec;
  const duration = end - start;
  if (!Number.isFinite(start) || !Number.isFinite(end) || start < 0 || end > source.durationSec + .01 || duration < PRODUCT_VIDEO_MIN_SECONDS || duration > PRODUCT_VIDEO_MAX_SECONDS) {
    throw new Error("Pilih rentang video antara 10–60 detik.");
  }
  if (sourceFits && start === 0 && Math.abs(end - source.durationSec) <= .01) {
    return { file, durationSec: Math.round(source.durationSec) };
  }
  let output: File | undefined;
  if (sourceFits) {
    options.onPhase?.("trim");
    try {
      output = await copyVideoRange(file, start, duration, options.onProgress);
      const metadata = await readVideoMetadata(output);
      // Stream copy follows keyframes; reject ranges that exceed the product
      // duration limits or differ materially from the requested length.
      if (metadata.durationSec < PRODUCT_VIDEO_MIN_SECONDS || metadata.durationSec > PRODUCT_VIDEO_MAX_SECONDS || Math.abs(metadata.durationSec - duration) > .5) {
        output = undefined;
      }
    } catch (error) {
      if (!(error instanceof CopyNotSupportedError)) throw error;
    }
  }
  if (!output) {
    options.onPhase?.("compress");
    options.onProgress?.(0);
    const { compressVideo } = await import("@/lib/feed/video-compressor");
    output = await compressVideo(file, {
      config: { ...USER_VIDEO_CONFIG, videoBitrate: "1500k", minDuration: PRODUCT_VIDEO_MIN_SECONDS, maxFileSize: PRODUCT_VIDEO_MAX_BYTES },
      trimStartSec: start, trimDurationSec: duration, onProgress: options.onProgress,
    });
  }
  if (output.size === 0 || output.size > PRODUCT_VIDEO_MAX_BYTES) throw new Error("Hasil video tidak valid atau melebihi 200 MB.");
  const metadata = await readVideoMetadata(output);
  if (metadata.durationSec < PRODUCT_VIDEO_MIN_SECONDS || metadata.durationSec > PRODUCT_VIDEO_MAX_SECONDS) throw new Error("Durasi hasil video harus antara 10–60 detik. Sesuaikan rentang potong.");
  return { file: output, durationSec: Math.round(metadata.durationSec) };
}

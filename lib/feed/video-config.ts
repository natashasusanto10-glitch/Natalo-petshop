export type FeedVideoConfig = {
  minDuration: number;
  maxDuration: number;
  resolution: number;
  videoBitrate: string;
  fps: number;
  videoCodec: string;
  crf: number;
  preset: string;
  audioCodec: string;
  audioBitrate: string;
  targetFileSize: number;
  maxFileSize: number;
};

// 50 MB ceiling. iOS WKWebView's ffmpeg.wasm sandbox runs out of memory
// decoding the raw frames of a larger 4K HEVC clip from a recent iPhone
// (a 22s 4K MOV is ~42MB — already at the edge in real-world testing).
// Anything past this should be trimmed by the user or recorded at a
// lower iPhone setting (Settings → Camera → Record Video → 1080p HD).
export const MAX_SOURCE_VIDEO_SIZE = 50 * 1024 * 1024;

export const USER_VIDEO_CONFIG = {
  minDuration: 1,
  maxDuration: 45,
  resolution: 720,
  videoBitrate: "1500k",
  fps: 30,
  videoCodec: "libx264",
  // CRF 26 (was 23) — slight quality drop on motion, invisible on the
  // small viewport pet videos use. Combined with the faster preset this
  // halves encode time without blowing past the 5MB target file size.
  crf: 26,
  // "veryfast" (was "medium") — ffmpeg.wasm runs single-threaded on
  // iOS WKWebView when triggered from a non-isolated route (the /feed
  // background upload flow doesn't have COEP/COOP headers), so preset
  // choice is the biggest knob. Veryfast typically 3-4x faster than
  // medium with ~10-15% larger output, still well under 5MB target.
  preset: "veryfast",
  audioCodec: "aac",
  audioBitrate: "96k",
  targetFileSize: 5 * 1024 * 1024,
  maxFileSize: 10 * 1024 * 1024,
} satisfies FeedVideoConfig;

export const ADMIN_VIDEO_CONFIG = {
  minDuration: 1,
  maxDuration: 60,
  resolution: 1080,
  videoBitrate: "3000k",
  fps: 30,
  videoCodec: "libx264",
  crf: 22,
  preset: "medium",
  audioCodec: "aac",
  audioBitrate: "128k",
  targetFileSize: 15 * 1024 * 1024,
  maxFileSize: 25 * 1024 * 1024,
} satisfies FeedVideoConfig;

export function formatFileSize(bytes: number) {
  if (bytes >= 1024 * 1024) return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
  if (bytes >= 1024) return `${Math.round(bytes / 1024)} KB`;
  return `${bytes} B`;
}

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

// User video config — TARGET specs untuk feed video.
//
// CATATAN: setelah migrasi ke Bunny Stream, encoding settings di-handle
// server-side oleh Bunny dashboard. Config ini sekarang fungsinya:
//   1. Duration validation (min/max) — masih dipakai di client + server
//   2. Reference/target untuk Bunny dashboard encoder settings
//   3. Legacy fallback untuk FeedUploadProvider (background upload toast
//      yang masih pakai ffmpeg.wasm)
//
// Untuk apply settings ini ke Bunny:
//   Bunny Dashboard → Library → Encoding → Custom Encoding Profile:
//     Resolution: 720p (1280 width)
//     Video Codec: H.264 (Main profile)
//     Video Bitrate: 3000 kbps (target)
//     FPS Max: 30
//     Audio Codec: AAC
//     Audio Bitrate: 128 kbps
//     Optional 1080p variant: enable kalau mau quality boost
//
// Bunny default sebelumnya: 720p @ ~1.5-2 Mbps. Naikkan ke 3 Mbps untuk
// quality lebih sharp (sesuai rekomendasi Natalo Feed spec).
export const USER_VIDEO_CONFIG = {
  minDuration: 1,
  maxDuration: 45,
  resolution: 720,
  // Target 3 Mbps untuk Bunny encoder. Legacy ffmpeg.wasm config-nya
  // di-keep di "1500k" supaya FeedUploadProvider (background toast)
  // tidak overshoot 10MB file size target. Bunny dashboard handle
  // 3 Mbps untuk current FeedUploadClient flow.
  videoBitrate: "3000k",
  fps: 30,
  videoCodec: "libx264",
  crf: 22,
  preset: "veryfast",
  audioCodec: "aac",
  audioBitrate: "128k",
  // Target file size dengan 3 Mbps × 45s = ~16MB worst case.
  targetFileSize: 8 * 1024 * 1024,
  maxFileSize: 20 * 1024 * 1024,
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

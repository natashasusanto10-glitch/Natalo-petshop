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

export const MAX_SOURCE_VIDEO_SIZE = 200 * 1024 * 1024;

export const USER_VIDEO_CONFIG = {
  minDuration: 1,
  maxDuration: 45,
  resolution: 720,
  videoBitrate: "1500k",
  fps: 30,
  videoCodec: "libx264",
  crf: 23,
  preset: "medium",
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

import { bunnyMp4Url, signBunnyUrl } from "./bunny";

export type FeedVideoPlaybackUrls = {
  videoUrl: string | null;
  videoDataSaverUrl: string | null;
};

function safeBunnyGuid(value: string | null | undefined): string | null {
  const guid = value?.trim();
  if (!guid || !/^[A-Za-z0-9-]{1,128}$/.test(guid)) return null;
  return guid;
}

export function bunnyGuidFromConfiguredCdnUrl(
  url: string | null | undefined,
): string | null {
  if (!url) return null;
  const cdnHostname = process.env.BUNNY_CDN_HOSTNAME;
  if (!cdnHostname) return null;

  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return null;
  }

  if (parsed.hostname !== cdnHostname) return null;

  const parts = parsed.pathname.split("/").filter(Boolean);
  const first = parts[0];
  const second = parts[1];
  if (!first || !second) return null;

  const isCanonicalBunnyPath =
    second === "playlist.m3u8" || /^play_\d+p\.mp4$/.test(second);
  return isCanonicalBunnyPath ? safeBunnyGuid(first) : null;
}

export function buildFeedVideoPlaybackUrls(params: {
  videoUrl?: string | null;
  videoGuid?: string | null;
}): FeedVideoPlaybackUrls {
  const mp4FallbackEnabled = process.env.BUNNY_MP4_480_ENABLED === "true";
  const videoGuid =
    safeBunnyGuid(params.videoGuid) ??
    bunnyGuidFromConfiguredCdnUrl(params.videoUrl);
  const dataSaverUrl =
    mp4FallbackEnabled && videoGuid
      ? bunnyMp4Url(videoGuid, 480)
      : "";
  return {
    videoUrl: signBunnyUrl(params.videoUrl) ?? null,
    videoDataSaverUrl: dataSaverUrl ? signBunnyUrl(dataSaverUrl) ?? null : null,
  };
}

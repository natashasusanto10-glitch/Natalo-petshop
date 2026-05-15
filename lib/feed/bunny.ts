/**
 * Bunny Stream API client + URL helpers.
 *
 * Bunny Stream is the customer-facing video pipeline for the feed:
 *
 *   1. Server POSTs to Bunny "create video" endpoint → gets a GUID +
 *      empty placeholder slot in the library.
 *   2. Client uploads the raw video directly to Bunny with that GUID —
 *      bypassing our server, no client-side ffmpeg.wasm encoding.
 *   3. Bunny encodes HLS variants (auto-adaptive bitrate ladder) and
 *      fires a webhook to /api/feed/bunny/webhook when it's ready.
 *   4. Client / feed picks up the new ready state and plays back the
 *      .m3u8 playlist from Bunny's CDN (auto picks the best variant
 *      for the viewer's network).
 *
 * Three env vars drive this — set them in Vercel before deploy:
 *
 *   BUNNY_LIBRARY_ID         — numeric ID from the Stream dashboard
 *   BUNNY_API_KEY            — long alphanumeric, from Library Settings → API
 *   BUNNY_CDN_HOSTNAME       — vz-xxxxx.b-cdn.net, from Library Settings → Embed
 *
 * Optional:
 *   BUNNY_WEBHOOK_SECRET     — set in Library Settings → Webhook. The
 *                              webhook handler uses this to verify the
 *                              callback came from Bunny.
 */

const BUNNY_API_BASE = "https://video.bunnycdn.com";

export type BunnyConfig = {
  libraryId: string;
  apiKey: string;
  cdnHostname: string;
  webhookSecret: string | null;
};

export function getBunnyConfig(): BunnyConfig | null {
  const libraryId = process.env.BUNNY_LIBRARY_ID;
  const apiKey = process.env.BUNNY_API_KEY;
  const cdnHostname = process.env.BUNNY_CDN_HOSTNAME;
  if (!libraryId || !apiKey || !cdnHostname) return null;
  return {
    libraryId,
    apiKey,
    cdnHostname,
    webhookSecret: process.env.BUNNY_WEBHOOK_SECRET ?? null,
  };
}

export function isBunnyConfigured(): boolean {
  return getBunnyConfig() !== null;
}

/**
 * Create a video placeholder in the Bunny library. Returns the GUID
 * that the client uses to upload the raw file.
 *
 * Title is required by Bunny but only shown in their dashboard; we use
 * a synthetic name like `feed-{userId}-{timestamp}` so admins can
 * correlate from the Bunny dashboard back to a FeedPost if needed.
 */
export async function createBunnyVideo(params: {
  title: string;
}): Promise<{ guid: string } | null> {
  const cfg = getBunnyConfig();
  if (!cfg) return null;

  const res = await fetch(
    `${BUNNY_API_BASE}/library/${cfg.libraryId}/videos`,
    {
      method: "POST",
      headers: {
        AccessKey: cfg.apiKey,
        "Content-Type": "application/json",
        accept: "application/json",
      },
      body: JSON.stringify({ title: params.title.slice(0, 200) }),
    },
  );
  if (!res.ok) {
    const text = await res.text().catch(() => "");
    console.warn(`[bunny] createVideo failed: ${res.status} ${text}`);
    return null;
  }
  const data = (await res.json()) as { guid?: string };
  if (!data.guid) return null;
  return { guid: data.guid };
}

/**
 * Best-effort delete of a Bunny video. Called when a post is rejected or
 * hard-deleted so we don't pay for storage we'll never serve. Never throws —
 * if Bunny is unreachable, the storage GC cron picks it up later.
 */
export async function deleteBunnyVideo(guid: string): Promise<boolean> {
  const cfg = getBunnyConfig();
  if (!cfg || !guid) return false;
  try {
    const res = await fetch(
      `${BUNNY_API_BASE}/library/${cfg.libraryId}/videos/${guid}`,
      { method: "DELETE", headers: { AccessKey: cfg.apiKey } },
    );
    return res.ok;
  } catch (err) {
    console.warn("[bunny] deleteVideo failed:", err);
    return false;
  }
}

/**
 * Fetch the current status of a Bunny video. Useful for reconciling
 * when a webhook is missed (rare, but networks aren't perfect).
 */
export async function getBunnyVideo(guid: string) {
  const cfg = getBunnyConfig();
  if (!cfg) return null;
  try {
    const res = await fetch(
      `${BUNNY_API_BASE}/library/${cfg.libraryId}/videos/${guid}`,
      { headers: { AccessKey: cfg.apiKey, accept: "application/json" } },
    );
    if (!res.ok) return null;
    return (await res.json()) as {
      guid: string;
      title: string;
      status: number; // 0=Created, 1=Uploaded, 2=Processing, 3=Transcoding, 4=Ready, 5=Failed
      length: number; // seconds
      width: number;
      height: number;
      storageSize: number;
    };
  } catch {
    return null;
  }
}

/**
 * HLS playlist URL — what the client `<video>` element points its src at.
 * Bunny serves m3u8 with adaptive bitrate variants from this single URL.
 */
export function bunnyPlaylistUrl(guid: string): string {
  const cfg = getBunnyConfig();
  if (!cfg) return "";
  return `https://${cfg.cdnHostname}/${guid}/playlist.m3u8`;
}

/**
 * Auto-generated thumbnail URL — Bunny pulls a frame at ~10% of the clip
 * by default. Good enough as a placeholder before the video element
 * finishes its first paint.
 */
export function bunnyThumbnailUrl(guid: string): string {
  const cfg = getBunnyConfig();
  if (!cfg) return "";
  return `https://${cfg.cdnHostname}/${guid}/thumbnail.jpg`;
}

/**
 * The direct upload endpoint the client PUTs the raw video file to.
 * Bunny accepts a simple PUT with the API key — for the customer build
 * we wrap this with a short-lived proxy so the API key never leaves the
 * server (see /api/feed/bunny/upload-url).
 */
export function bunnyUploadUrl(guid: string): string {
  const cfg = getBunnyConfig();
  if (!cfg) return "";
  return `${BUNNY_API_BASE}/library/${cfg.libraryId}/videos/${guid}`;
}

/**
 * Bunny's webhook status codes — exported so the webhook handler can read
 * the numeric `Status` field semantically.
 */
export const BUNNY_VIDEO_STATUS = {
  CREATED: 0,
  UPLOADED: 1,
  PROCESSING: 2,
  TRANSCODING: 3,
  FINISHED: 4,
  ERROR: 5,
} as const;

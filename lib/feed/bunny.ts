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

import crypto from "node:crypto";

const BUNNY_API_BASE = "https://video.bunnycdn.com";

/**
 * Default expiry untuk signed URL — 6 jam. Cukup panjang supaya feed yang
 * di-cache di Flutter offline_cache_v1 (lihat feed_local_store.dart) tetap
 * playable saat user buka app offline. Trade-off: token expiry tidak ideal
 * untuk hotlink prevention murni (orang lain bisa hotlink selama 6 jam),
 * tapi praktis untuk UX feed. Kalau mau super-strict, turunkan ke 30 menit
 * via param expirySeconds.
 */
const SIGNED_URL_DEFAULT_EXPIRY_SEC = 6 * 60 * 60;

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
}): Promise<{ guid: string } | { error: string } | null> {
  const cfg = getBunnyConfig();
  if (!cfg) return null;

  let res: Response;
  try {
    res = await fetch(
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
  } catch (err) {
    const msg = err instanceof Error ? err.message : "network error";
    console.warn(`[bunny] createVideo fetch threw: ${msg}`);
    return { error: `network: ${msg}` };
  }
  if (!res.ok) {
    const text = await res.text().catch(() => "");
    console.warn(`[bunny] createVideo failed: ${res.status} ${text}`);
    return { error: `HTTP ${res.status}: ${text.slice(0, 200) || "no body"}` };
  }
  const data = (await res.json().catch(() => ({}))) as { guid?: string };
  if (!data.guid) return { error: "Response missing guid field" };
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
 * Progressive MP4 URL — single file that the browser streams via HTTP
 * range requests. Use this instead of HLS for short feed videos: one
 * cache key vs. dozens of HLS segments means the CDN warms up faster
 * (huge win when cache hit rate is low) and iOS Safari plays it
 * natively without any extra player code.
 *
 * Bunny generates these MP4 transcodes when "MP4 Fallback" is enabled
 * in the library settings. Available resolutions are reported in the
 * video meta's `availableResolutions` field (typically 240p/360p/480p/720p).
 * 720p is a safe default for portrait phone video — picture stays sharp,
 * file size stays small (~5-10 MB for a 15-second clip).
 *
 * ── Bunny encoding profile target (configured di dashboard, NOT di code) ──
 * 720p HD (1280×720) @ 30fps, bitrate 2500 kbps (2.5 Mbps).
 * Sweet spot match IG Reels / TikTok standard:
 *   - Quality bagus di phone screen, imperceptible artifact
 *   - File 30-detik ≈ 9.4 MB (vs 10.5 MB di 2800 kbps lama)
 *   - Bunny CDN egress saving ~10% per session
 *   - Initial buffer time ~1.0-1.2 detik di 4G Indonesia
 * Range valid 1.5-2.5 Mbps untuk 720p phone content. Lower → blocky di motion,
 * higher → diminishing returns (mata gak bedain di small screen).
 *
 * Untuk ubah: Bunny dashboard → Library Natalo → Settings → Encoding Profile
 * → 720p → field "Bitrate". Update note ini juga supaya consistent.
 */
export function bunnyMp4Url(
  guid: string,
  height: 240 | 360 | 480 | 720 | 1080 = 720,
): string {
  const cfg = getBunnyConfig();
  if (!cfg) return "";
  return `https://${cfg.cdnHostname}/${guid}/play_${height}p.mp4`;
}

/**
 * Best-effort: if a stored videoUrl points at a Bunny HLS playlist,
 * derive the equivalent MP4 URL. Used on the client so existing rows
 * (saved before the MP4 switch) still play via the faster MP4 path
 * without a DB migration. Returns null when the URL doesn't match the
 * Bunny HLS pattern so callers can fall back to the original src.
 */
export function bunnyHlsToMp4(
  hlsUrl: string | null | undefined,
  height: 240 | 360 | 480 | 720 | 1080 = 720,
): string | null {
  if (!hlsUrl) return null;
  const match = hlsUrl.match(/^(https?:\/\/[^/]+)\/([a-f0-9-]+)\/playlist\.m3u8(?:\?.*)?$/i);
  if (!match) return null;
  return `${match[1]}/${match[2]}/play_${height}p.mp4`;
}

/**
 * Rewrite kualitas dari Bunny MP4 URL existing tanpa harus ke DB.
 * Misal stored URL `https://vz-xxx.b-cdn.net/<guid>/play_720p.mp4` →
 * rewrite jadi `play_480p.mp4` saat user di 3G. Aman dipanggil dengan
 * URL yang bukan Bunny — balikin null supaya caller fallback ke
 * original src. Pattern match longgar supaya kompatibel dengan path
 * suffix (e.g., query params).
 */
export function rewriteBunnyMp4Quality(
  url: string | null | undefined,
  height: 240 | 360 | 480 | 720 | 1080,
): string | null {
  if (!url) return null;
  // Match URL pattern Bunny MP4: <origin>/<guid>/play_<NNN>p.mp4
  const match = url.match(/^(https?:\/\/[^/]+\/[a-f0-9-]+\/)play_\d{3,4}p\.mp4(\?.*)?$/i);
  if (!match) return null;
  const query = match[2] ?? "";
  return `${match[1]}play_${height}p.mp4${query}`;
}

/**
 * Convert Bunny MP4 URL → HLS playlist URL. Bunny generate HLS adaptive
 * stream (multi-bitrate manifest) di sebelah file MP4. Pakai HLS untuk
 * koneksi WiFi/stable supaya player otomatis switch quality mid-clip
 * (mis. 480p saat awal saat buffer kosong → 1080p setelah bandwidth
 * mature). MP4 progressive lebih baik di koneksi unstable atau short
 * clip yang tidak butuh adaptive.
 */
export function bunnyMp4ToHls(url: string | null | undefined): string | null {
  if (!url) return null;
  const match = url.match(/^(https?:\/\/[^/]+\/[a-f0-9-]+\/)play_\d{3,4}p\.mp4(\?.*)?$/i);
  if (!match) return null;
  const query = match[2] ?? "";
  return `${match[1]}playlist.m3u8${query}`;
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
 * Sign Bunny CDN URL dengan token authentication.
 *
 * Bunny CDN Token Authentication scheme (https://docs.bunny.net/docs/cdn-token-authentication):
 *   expires    = unixTimestamp + expirySeconds
 *   tokenInput = securityKey + url_path + expires
 *   token      = base64UrlSafe( SHA256(tokenInput) )
 *
 * Aktif HANYA kalau env `BUNNY_TOKEN_SECURITY_KEY` di-set. Tanpa env,
 * function return URL apa adanya — supaya deploy aman incremental: code
 * bisa di-deploy duluan tanpa break, baru aktifkan token authentication di
 * Bunny dashboard + env var. Reverse: kalau dashboard di-disable, signed
 * URL tetap bekerja (token diabaikan).
 *
 * Untuk HLS (`playlist.m3u8`), token harus berlaku untuk seluruh folder video,
 * bukan hanya file playlist utama. Player membuka child manifests dan segments
 * relatif seperti `480p/video.m3u8` dan `audio/audio.m3u8`; kalau token hanya
 * query-param di master playlist, request turunan akan 403. Jadi HLS memakai
 * path-based directory token (`/bcdn_token=.../<guid>/playlist.m3u8`) agar
 * semua request relatif mewarisi autentikasi yang sama.
 *
 * Hanya sign URL yang host-nya match `BUNNY_CDN_HOSTNAME` — URL eksternal
 * atau legacy UploadThing return as-is supaya tidak rusak.
 */
export function signBunnyUrl(
  url: string | null | undefined,
  expirySeconds: number = SIGNED_URL_DEFAULT_EXPIRY_SEC,
): string | null | undefined {
  if (!url) return url;
  const securityKey = process.env.BUNNY_TOKEN_SECURITY_KEY;
  if (!securityKey) return url;

  const cfg = getBunnyConfig();
  if (!cfg) return url;

  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return url;
  }
  if (parsed.hostname !== cfg.cdnHostname) return url;

  const expires = Math.floor(Date.now() / 1000) + expirySeconds;
  const isHlsPlaylist = parsed.pathname.endsWith("/playlist.m3u8");

  if (isHlsPlaylist) {
    const directoryPath = parsed.pathname.replace(/playlist\.m3u8$/, "");
    const tokenPathParam = `token_path=${directoryPath}`;
    const token = bunnyToken({
      securityKey,
      signaturePath: directoryPath,
      expires,
      parameterData: tokenPathParam,
    });
    const encodedTokenPath = encodeURIComponent(directoryPath);
    return `${parsed.protocol}//${parsed.host}/bcdn_token=${token}&token_path=${encodedTokenPath}&expires=${expires}${parsed.pathname}`;
  }

  const token = bunnyToken({
    securityKey,
    signaturePath: parsed.pathname,
    expires,
  });

  parsed.searchParams.set("token", token);
  parsed.searchParams.set("expires", String(expires));
  return parsed.toString();
}

function bunnyToken(params: {
  securityKey: string;
  signaturePath: string;
  expires: number;
  parameterData?: string;
}): string {
  const hashInput = `${params.securityKey}${params.signaturePath}${params.expires}${params.parameterData ?? ""}`;
  return crypto
    .createHash("sha256")
    .update(hashInput)
    .digest("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=/g, "");
}

/**
 * Pre-warm Bunny CDN edge cache untuk video yang baru selesai encoding.
 *
 * Bunny pakai pull-CDN — file dari origin baru di-cache di edge POP saat
 * ada request pertama. User pertama yang buka video baru selalu kena
 * cold-cache latency 2-5 detik (TTFB lambat). Pre-warm dari server
 * supaya edge POP terdekat ke server (biasanya Singapore region untuk
 * Vercel Asia) udah punya file sebelum user pertama.
 *
 * Strategi: GET first 256KB MP4 (cover moov atom + first segment) +
 * full thumbnail JPG. 256KB cukup untuk start playback instan — selebihnya
 * stream normal. Total bandwidth: ~280KB per pre-warm × N edges.
 *
 * Fire-and-forget: error di-swallow karena ini cuma optimasi, bukan
 * critical path. Webhook tetap return success walaupun pre-warm gagal.
 */
export async function preWarmBunnyAssets(guid: string): Promise<void> {
  const cfg = getBunnyConfig();
  if (!cfg) return;

  // Sign URL kalau token authentication aktif — kalau enggak, signBunnyUrl
  // return URL as-is. Tanpa signing, request bakal di-403 oleh Bunny kalau
  // hotlink/token protection on.
  //
  // Pre-warm HLS playlist + thumbnail. Playlist .m3u8 file kecil (~1-2KB)
  // tapi pre-warm membuat CDN edge cache playlist + initial TS segment
  // saat user pertama tap. Match webhook handler yang sekarang set
  // videoUrl ke HLS playlist (bukan MP4 lagi).
  const playlistUrl = signBunnyUrl(bunnyPlaylistUrl(guid)) ?? "";
  const thumbUrl = signBunnyUrl(bunnyThumbnailUrl(guid)) ?? "";
  if (!playlistUrl || !thumbUrl) return;

  // Full GET untuk playlist (kecil) + thumbnail (~20KB).
  // AbortController dengan timeout 8s supaya pre-warm tidak gantung webhook.
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 8_000);

  try {
    await Promise.allSettled([
      fetch(playlistUrl, { signal: controller.signal })
        .then((r) => r.arrayBuffer())
        .catch(() => {}),
      fetch(thumbUrl, { signal: controller.signal })
        .then((r) => r.arrayBuffer())
        .catch(() => {}),
    ]);
  } catch {
    // Swallow — pre-warm bukan critical path.
  } finally {
    clearTimeout(timeout);
  }
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
 * TUS upload credentials untuk Bunny Stream resumable upload.
 *
 * TUS protocol (tus.io) memungkinkan upload file besar resumable — kalau
 * koneksi putus di tengah, client lanjut dari byte terakhir yang sudah
 * diterima server, BUKAN restart dari 0. Critical untuk file 200MB di
 * koneksi mobile Indonesia yang sering signal drop.
 *
 * Bunny TUS endpoint: https://video.bunnycdn.com/tusupload
 *
 * Auth Bunny TUS: signature SHA256 dari concatenation:
 *   library_id + api_key + expiration_unix + video_guid
 * Plus header `AuthorizationExpire` (unix timestamp, valid window).
 * Window default 1 jam — cukup untuk upload 200MB di koneksi paling
 * pelan sekalipun (~30 menit di 3G).
 */
export type BunnyTusCredentials = {
  endpoint: string;
  videoId: string;
  libraryId: string;
  authSignature: string;
  authExpire: number;
};

export async function generateBunnyTusCredentials(
  guid: string,
  expiryWindowSec: number = 60 * 60, // 1 jam default
): Promise<BunnyTusCredentials | null> {
  const cfg = getBunnyConfig();
  if (!cfg) return null;

  const expire = Math.floor(Date.now() / 1000) + expiryWindowSec;

  // Bunny signature: SHA256(library_id + api_key + expiration_time + video_id)
  // Node 18+ punya crypto.subtle (Web Crypto API) — sama API persis dengan
  // browser, jadi tidak perlu node:crypto import.
  const message = `${cfg.libraryId}${cfg.apiKey}${expire}${guid}`;
  const buffer = new TextEncoder().encode(message);
  const hashBuffer = await crypto.subtle.digest("SHA-256", buffer);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  const authSignature = hashArray
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");

  return {
    endpoint: `${BUNNY_API_BASE}/tusupload`,
    videoId: guid,
    libraryId: cfg.libraryId,
    authSignature,
    authExpire: expire,
  };
}

/**
 * List videos di Bunny Stream library — paginated.
 * Dipakai oleh storage GC cron untuk identify orphan (video di Bunny tapi
 * tidak lagi di-reference oleh FeedPost aktif di DB).
 *
 * Bunny API: GET /library/{id}/videos?page=N&itemsPerPage=100
 *   returns { items: [...], totalItems: N, itemsPerPage: 100, ... }
 *
 * Helper return one page at a time — caller iterate sampai items.length=0.
 */
export async function listBunnyLibraryVideos(
  page: number = 1,
  itemsPerPage: number = 100,
): Promise<Array<{ guid: string; title: string; storageSize: number; dateUploaded: string }> | null> {
  const cfg = getBunnyConfig();
  if (!cfg) return null;
  try {
    const res = await fetch(
      `${BUNNY_API_BASE}/library/${cfg.libraryId}/videos?page=${page}&itemsPerPage=${itemsPerPage}&orderBy=date`,
      { headers: { AccessKey: cfg.apiKey, accept: "application/json" } },
    );
    if (!res.ok) {
      console.warn(`[bunny] listVideos failed: ${res.status}`);
      return null;
    }
    const data = (await res.json()) as {
      items?: Array<{
        guid: string;
        title: string;
        storageSize: number;
        dateUploaded: string;
      }>;
    };
    return data.items ?? [];
  } catch (err) {
    console.warn("[bunny] listVideos error:", err);
    return null;
  }
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

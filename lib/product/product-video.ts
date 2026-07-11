/**
 * Klien Bunny Stream untuk VIDEO PRODUK — library TERPISAH dari feed.
 *
 * Pemisahan library WAJIB: cron GC feed (lib/feed/bunny-gc.ts) menghapus
 * SEMUA video di library feed yang tidak direferensikan FeedPost aktif.
 * Kalau video produk berada di library yang sama, GC feed akan
 * menghapusnya. Karena itu modul ini pakai env sendiri dan TIDAK
 * mengimpor apa pun dari lib/feed.
 *
 * Env (set di Vercel):
 *   BUNNY_PRODUCT_LIBRARY_ID
 *   BUNNY_PRODUCT_API_KEY
 *   BUNNY_PRODUCT_CDN_HOSTNAME       (vz-xxxx.b-cdn.net)
 *   BUNNY_PRODUCT_WEBHOOK_SECRET     (opsional)
 */

const BUNNY_API_BASE = "https://video.bunnycdn.com";

export type ProductBunnyConfig = {
  libraryId: string;
  apiKey: string;
  cdnHostname: string;
  webhookSecret: string | null;
};

export function getProductBunnyConfig(): ProductBunnyConfig | null {
  const libraryId = process.env.BUNNY_PRODUCT_LIBRARY_ID;
  const apiKey = process.env.BUNNY_PRODUCT_API_KEY;
  const cdnHostname = process.env.BUNNY_PRODUCT_CDN_HOSTNAME;
  if (!libraryId || !apiKey || !cdnHostname) return null;
  return {
    libraryId,
    apiKey,
    cdnHostname,
    webhookSecret: process.env.BUNNY_PRODUCT_WEBHOOK_SECRET ?? null,
  };
}

export function isProductBunnyConfigured(): boolean {
  return getProductBunnyConfig() !== null;
}

export function webhookAuthorized(authorizationHeader: string | null): boolean {
  const cfg = getProductBunnyConfig();
  if (!cfg?.webhookSecret) return true; // tanpa secret, terima (hanya flip row by guid)
  return (authorizationHeader ?? "") === `Bearer ${cfg.webhookSecret}`;
}

export async function createProductVideo(params: {
  title: string;
}): Promise<{ guid: string } | { error: string } | null> {
  const cfg = getProductBunnyConfig();
  if (!cfg) return null;
  let res: Response;
  try {
    res = await fetch(`${BUNNY_API_BASE}/library/${cfg.libraryId}/videos`, {
      method: "POST",
      headers: {
        AccessKey: cfg.apiKey,
        "Content-Type": "application/json",
        accept: "application/json",
      },
      body: JSON.stringify({ title: params.title.slice(0, 200) }),
    });
  } catch (err) {
    const msg = err instanceof Error ? err.message : "network error";
    return { error: `network: ${msg}` };
  }
  if (!res.ok) {
    const text = await res.text().catch(() => "");
    return { error: `HTTP ${res.status}: ${text.slice(0, 200) || "no body"}` };
  }
  const data = (await res.json().catch(() => ({}))) as { guid?: string };
  if (!data.guid) return { error: "Response missing guid field" };
  return { guid: data.guid };
}

export async function deleteProductVideo(guid: string): Promise<boolean> {
  const cfg = getProductBunnyConfig();
  if (!cfg || !guid) return false;
  try {
    const res = await fetch(
      `${BUNNY_API_BASE}/library/${cfg.libraryId}/videos/${guid}`,
      { method: "DELETE", headers: { AccessKey: cfg.apiKey } },
    );
    return res.ok;
  } catch {
    return false;
  }
}

export async function getProductVideo(guid: string) {
  const cfg = getProductBunnyConfig();
  if (!cfg) return null;
  try {
    const res = await fetch(
      `${BUNNY_API_BASE}/library/${cfg.libraryId}/videos/${guid}`,
      { headers: { AccessKey: cfg.apiKey, accept: "application/json" } },
    );
    if (!res.ok) return null;
    return (await res.json()) as {
      guid: string;
      status: number;
      length: number;
      width: number;
      height: number;
      storageSize: number;
    };
  } catch {
    return null;
  }
}

export function productPlaylistUrl(guid: string): string {
  const cfg = getProductBunnyConfig();
  if (!cfg) return "";
  return `https://${cfg.cdnHostname}/${guid}/playlist.m3u8`;
}

export function productThumbnailUrl(guid: string): string {
  const cfg = getProductBunnyConfig();
  if (!cfg) return "";
  return `https://${cfg.cdnHostname}/${guid}/thumbnail.jpg`;
}

export function productMp4Url(
  guid: string,
  height: 240 | 360 | 480 | 720 | 1080 = 720,
): string {
  const cfg = getProductBunnyConfig();
  if (!cfg) return "";
  return `https://${cfg.cdnHostname}/${guid}/play_${height}p.mp4`;
}

export async function generateProductTusCredentials(
  guid: string,
  expiryWindowSec: number = 60 * 60,
): Promise<{
  endpoint: string;
  videoId: string;
  libraryId: string;
  authSignature: string;
  authExpire: number;
} | null> {
  const cfg = getProductBunnyConfig();
  if (!cfg) return null;
  const expire = Math.floor(Date.now() / 1000) + expiryWindowSec;
  // SHA256(library_id + api_key + expiration + video_id) — Web Crypto.
  const message = `${cfg.libraryId}${cfg.apiKey}${expire}${guid}`;
  const buffer = new TextEncoder().encode(message);
  const hashBuffer = await crypto.subtle.digest("SHA-256", buffer);
  const authSignature = Array.from(new Uint8Array(hashBuffer))
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

export async function listProductLibraryVideos(
  page: number = 1,
  itemsPerPage: number = 100,
): Promise<Array<{ guid: string; storageSize: number }> | null> {
  const cfg = getProductBunnyConfig();
  if (!cfg) return null;
  try {
    const res = await fetch(
      `${BUNNY_API_BASE}/library/${cfg.libraryId}/videos?page=${page}&itemsPerPage=${itemsPerPage}&orderBy=date`,
      { headers: { AccessKey: cfg.apiKey, accept: "application/json" } },
    );
    if (!res.ok) return null;
    const data = (await res.json()) as {
      items?: Array<{ guid: string; storageSize: number }>;
    };
    return (data.items ?? []).map((i) => ({
      guid: i.guid,
      storageSize: i.storageSize ?? 0,
    }));
  } catch {
    return null;
  }
}

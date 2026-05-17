/**
 * Server-side blurhash generation untuk Feed thumbnails.
 *
 * Pipeline:
 *   1. Fetch thumbnail dari Bunny CDN (~50-200 KB JPEG)
 *   2. Sharp resize ke 32x32 RGBA buffer (cukup detail untuk blurhash,
 *      hemat memory dan CPU)
 *   3. blurhash.encode() → string ~30 byte
 *   4. Caller simpan ke FeedPost.thumbnailBlurhash
 *
 * Client decode pakai blurhash.decode() → ImageData → drawn ke canvas.
 * Total payload tambahan per post: ~30 byte di JSON response.
 */
import { encode as blurhashEncode } from "blurhash";
import sharp from "sharp";

const BLURHASH_TARGET_WIDTH = 32;
const BLURHASH_TARGET_HEIGHT = 32;
// Komponen X dan Y di blurhash — angka 4x3 = 4 horizontal komponen, 3
// vertical. Lebih banyak = detail lebih, string lebih panjang.
// 4x3 sweet spot untuk thumbnail vertikal 9:16: ~32 char output.
const BLURHASH_COMPONENT_X = 4;
const BLURHASH_COMPONENT_Y = 3;

/**
 * Generate blurhash string dari URL thumbnail. Best-effort — return null
 * kalau fetch gagal atau decode error. Caller harus tolerate null.
 */
export async function generateBlurhashFromUrl(
  url: string,
): Promise<string | null> {
  try {
    const res = await fetch(url, {
      // Bunny thumbnail kadang slow respond di first request — kasih
      // timeout supaya tidak block webhook indefinite.
      signal: AbortSignal.timeout(10_000),
    });
    if (!res.ok) {
      console.warn(
        `[blurhash] fetch failed: ${res.status} ${res.statusText} (${url})`,
      );
      return null;
    }
    const buffer = Buffer.from(await res.arrayBuffer());

    // Resize ke 32x32 + ensure RGBA channel order untuk blurhash encode.
    // raw() returns Uint8Array dengan 4 byte per pixel (RGBA).
    const { data, info } = await sharp(buffer)
      .resize(BLURHASH_TARGET_WIDTH, BLURHASH_TARGET_HEIGHT, {
        fit: "cover",
      })
      .ensureAlpha()
      .raw()
      .toBuffer({ resolveWithObject: true });

    return blurhashEncode(
      new Uint8ClampedArray(data),
      info.width,
      info.height,
      BLURHASH_COMPONENT_X,
      BLURHASH_COMPONENT_Y,
    );
  } catch (err) {
    console.warn(
      `[blurhash] encode failed for ${url}:`,
      err instanceof Error ? err.message : err,
    );
    return null;
  }
}

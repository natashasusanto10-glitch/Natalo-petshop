/**
 * Fungsi murni untuk payload push publish-feed — tanpa import Prisma/env
 * supaya mudah diuji langsung (lihat pola lib/product/product-video-serialize.ts).
 */

export type FeedPushPayloadResult = {
  title: string;
  body: string;
  url: string;
  tag: string;
};

const FALLBACK_BODY = "Ada konten baru di Natalo 🎥";

/**
 * Potong string per CODE POINT, bukan per code unit. `String.prototype.slice`
 * bisa membelah emoji (surrogate pair, 2 code unit) tepat di tengah →
 * lone surrogate = teks tidak valid → Prisma menolak INSERT dengan
 * "unexpected end of hex escape" (BUG NYATA: judul feed diawali 🐱 dipotong
 * slice(0,60) → announcement.create gagal → push+lonceng mati senyap).
 * Array.from meng-iterate per code point sehingga emoji tak pernah terbelah.
 */
function truncateSafe(value: string, max: number): string {
  const points = Array.from(value);
  return points.length <= max ? value : points.slice(0, max).join("");
}

export function buildFeedPushPayload(
  postId: string,
  title: string,
  description: string | null,
): FeedPushPayloadResult {
  const truncatedTitle = truncateSafe(title, 60);
  const truncatedBody = description?.trim()
    ? truncateSafe(description.trim(), 120)
    : "";

  return {
    title: truncatedTitle,
    body: truncatedBody || FALLBACK_BODY,
    url: `/feed/${postId}`,
    tag: `feed-publish-${postId}`,
  };
}

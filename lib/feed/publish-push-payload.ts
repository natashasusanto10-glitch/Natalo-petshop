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

export function buildFeedPushPayload(
  postId: string,
  title: string,
  description: string | null,
): FeedPushPayloadResult {
  const truncatedTitle = title.slice(0, 60);
  const truncatedBody = description?.trim() ? description.trim().slice(0, 120) : "";

  return {
    title: truncatedTitle,
    body: truncatedBody || FALLBACK_BODY,
    url: `/feed/${postId}`,
    tag: `feed-publish-${postId}`,
  };
}

import type { Prisma } from "@prisma/client";

import { prisma } from "@/lib/prisma";
import { brandDisplayName, brandPhotoUrl } from "@/lib/social/brand-user";
import { buildShareVersion, stripEphemeralUrlQuery } from "./share-version";

/** The public visibility gate for browser share pages and their metadata. */
export const PUBLIC_SHARE_FEED_POST_WHERE = {
  status: "ACTIVE",
  deletedAt: null,
  encodingStatus: "ready",
  OR: [
    { videoUrl: { not: null }, thumbnailUrl: { not: null } },
    { kind: "PRODUCT_ONLY" },
    { kind: "PROMO", productId: { not: null } },
    { kind: "PHOTO_CAROUSEL" },
  ],
} satisfies Prisma.FeedPostWhereInput;

export type PublicShareFeedPost = {
  id: string;
  shareVersion: string;
  title: string;
  description: string | null;
  kind: string;
  posterUrl: string | null;
  durationSec: number | null;
  mediaCount: number;
  author: {
    displayName: string;
    photoUrl: string | null;
    username: string | null;
    isOfficial: boolean;
  };
};

export type PublicShareFeedPostRepository = Pick<typeof prisma, "feedPost">;

type FeedVersionInput = {
  id: string;
  title: string;
  description: string | null;
  thumbnailUrl: string | null;
  media?: readonly { url: string; thumbnailUrl: string | null }[];
  videoDurationSec: number | null;
  author: { role: string; name: string; profilePhotoUrl: string | null };
  authorRole: string;
};

type ShareVisibilityCheckedFeedPost = {
  status: string;
  deletedAt: Date | null;
  encodingStatus: string;
  kind: string;
  productId: string | null;
  videoUrl: string | null;
  thumbnailUrl: string | null;
};

function isPublicShareFeedPost(post: ShareVisibilityCheckedFeedPost) {
  if (
    post.status !== "ACTIVE" ||
    post.deletedAt !== null ||
    post.encodingStatus !== "ready"
  ) {
    return false;
  }

  if (post.kind === "PRODUCT_ONLY" || post.kind === "PHOTO_CAROUSEL") {
    return true;
  }

  if (post.kind === "PROMO") return post.productId !== null;

  return post.videoUrl !== null && post.thumbnailUrl !== null;
}

function selectFeedPreviewPoster(
  post: Pick<FeedVersionInput, "thumbnailUrl" | "media">,
) {
  return post.thumbnailUrl ?? post.media?.[0]?.thumbnailUrl ?? post.media?.[0]?.url ?? null;
}

/** Keep the share URL token aligned with the existing public Feed API. */
export function buildFeedShareVersion(post: FeedVersionInput) {
  const authorDisplayName = brandDisplayName(post.author.role, post.author.name);
  const authorPhoto = brandPhotoUrl(post.author.role, post.author.profilePhotoUrl);
  return buildShareVersion([
    post.id,
    post.title,
    post.description,
    stripEphemeralUrlQuery(selectFeedPreviewPoster(post)),
    post.videoDurationSec,
    authorDisplayName,
    stripEphemeralUrlQuery(authorPhoto),
    post.authorRole === "ADMIN",
  ]);
}

/**
 * Returns only public, preview-safe fields for `/feed/[id]`.
 *
 * This intentionally does not reuse a viewer/admin query and never signs the
 * media URL: a browser poster must be cacheable and cannot expose a private
 * playback URL.
 */
export async function getPublicShareFeedPost(
  id: string,
  repository: PublicShareFeedPostRepository = prisma,
): Promise<PublicShareFeedPost | null> {
  const post = await repository.feedPost.findFirst({
    where: { id, ...PUBLIC_SHARE_FEED_POST_WHERE },
    select: {
      id: true,
      title: true,
      description: true,
      kind: true,
      status: true,
      deletedAt: true,
      encodingStatus: true,
      productId: true,
      videoUrl: true,
      thumbnailUrl: true,
      videoDurationSec: true,
      authorRole: true,
      author: {
        select: {
          name: true,
          username: true,
          role: true,
          profilePhotoUrl: true,
        },
      },
      media: {
        orderBy: { sortOrder: "asc" },
        take: 1,
        select: { url: true, thumbnailUrl: true },
      },
      _count: { select: { media: true } },
    },
  });
  if (!post || !isPublicShareFeedPost(post)) return null;

  const authorPhoto = brandPhotoUrl(post.author.role, post.author.profilePhotoUrl);
  const posterUrl = selectFeedPreviewPoster(post);

  return {
    id: post.id,
    shareVersion: buildFeedShareVersion(post),
    title: post.title,
    description: post.description,
    kind: post.kind,
    posterUrl: posterUrl ? stripEphemeralUrlQuery(posterUrl) : null,
    durationSec: post.videoDurationSec,
    mediaCount: post._count.media,
    author: {
      displayName: brandDisplayName(post.author.role, post.author.name),
      photoUrl: authorPhoto ? stripEphemeralUrlQuery(authorPhoto) : null,
      username: post.author.username,
      isOfficial: post.authorRole === "ADMIN",
    },
  };
}

/**
 * Public shape Feed API — JSON-serializable, dipakai di server + client.
 *
 * Sumber kebenaran: prisma/schema.prisma (FeedPost, FeedComment, dll).
 * Tujuan file ini bukan duplikasi schema, tapi shape "trimmed" untuk
 * konsumsi UI: hanya field yang dipakai render, plus `viewerLiked` /
 * `viewerCanModerate` hints yang di-compute server-side.
 */
import type { FeedPostKind, FeedPostStatus, FeedPostTab } from "@prisma/client";

export type FeedPostAuthor = {
  id: string;
  name: string;
  role: "ADMIN" | "CUSTOMER";
};

export type FeedPostProduct = {
  id: string;
  slug: string;
  name: string;
  price: number;
  discountPrice: number | null;
  stock: number;
  imageUrl: string | null;
} | null;

export type FeedPostListItem = {
  id: string;
  kind: FeedPostKind;
  tab: FeedPostTab;
  status: FeedPostStatus;
  title: string;
  description: string | null;
  videoUrl: string | null;
  thumbnailUrl: string | null;
  videoDurationSec: number | null;
  videoWidth: number | null;
  videoHeight: number | null;
  product: FeedPostProduct;
  promo: {
    originalPrice: number;
    discountPrice: number;
    startsAt: string | null;
    endsAt: string | null;
  } | null;
  likeCount: number;
  commentCount: number;
  viewCount: number;
  author: FeedPostAuthor;
  publishedAt: string | null;
  createdAt: string;
  // Per-viewer state — server compute kalau session ada, false kalau anon.
  viewerLiked: boolean;
};

export type FeedListResponse = {
  items: FeedPostListItem[];
  nextCursor: string | null;
};

export type FeedCommentItem = {
  id: string;
  postId: string;
  parentCommentId: string | null;
  content: string;
  isAdminOfficial: boolean;
  isHidden: boolean;
  likeCount: number;
  createdAt: string;
  author: FeedPostAuthor;
  viewerLiked: boolean;
  // Server cuma fetch 1-level reply child sebagai "preview". UI bisa
  // expand untuk fetch full reply thread per comment.
  replies?: FeedCommentItem[];
  replyCount?: number;
};

export type FeedCommentsResponse = {
  items: FeedCommentItem[];
  nextCursor: string | null;
};

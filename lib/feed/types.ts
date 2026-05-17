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
  weightGram: number;
  isAvailable: boolean;
  imageUrl: string | null;
  // hasVariants — saat true, in-feed quick add tidak boleh skip variant
  // picker (user harus pilih size/warna/dll). Saat false, +1 cart langsung.
  hasVariants: boolean;
} | null;

// Shop the Look — non-nullable variant. Setiap item di taggedProducts
// pasti ada produknya (skip kalau product di-soft-delete). Position 0..2
// untuk urutan carousel di feed UI.
// promoPrice: discount per-product yang admin set di video PROMO. Kalau
// null, gunakan price normal (no discount badge per-product).
export type FeedPostTaggedProduct = {
  id: string;
  slug: string;
  name: string;
  price: number;
  discountPrice: number | null;
  stock: number;
  weightGram: number;
  isAvailable: boolean;
  imageUrl: string | null;
  position: number;
  promoPrice: number | null;
  // hasVariants — sama spt FeedPostProduct, gate quick-add path.
  hasVariants: boolean;
};

export type FeedPostListItem = {
  id: string;
  kind: FeedPostKind;
  tab: FeedPostTab;
  status: FeedPostStatus;
  title: string;
  description: string | null;
  videoUrl: string | null;
  thumbnailUrl: string | null;
  // Blurhash LQIP placeholder — di-decode di client jadi canvas 32x32
  // sebagai placeholder instan sebelum thumbnail real load. Null untuk
  // legacy post yang belum di-backfill — UI fallback ke bg-black solid.
  thumbnailBlurhash: string | null;
  videoDurationSec: number | null;
  videoWidth: number | null;
  videoHeight: number | null;
  product: FeedPostProduct;
  // Shop the Look — semua produk yang di-tag (admin max 5, user max 3).
  // Sorted by position ascending. `product` (single) tetap dipertahankan
  // untuk backward-compat — biasanya = taggedProducts[0] kalau ada.
  taggedProducts: FeedPostTaggedProduct[];
  promo: {
    originalPrice: number;
    discountPrice: number;
    startsAt: string | null;
    endsAt: string | null;
  } | null;
  likeCount: number;
  commentCount: number;
  viewCount: number;
  shareCount: number;
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

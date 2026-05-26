/**
 * Service layer untuk Review.
 *
 * Semua operasi yang mengubah review meng-update aggregate (avgRating,
 * reviewCount, ratingBreakdown) di Product secara atomik di transaksi yang sama.
 */

import { prisma } from "@/lib/prisma";
import type { Prisma, ReviewStatus } from "@prisma/client";

const EDIT_WINDOW_MS = 30 * 24 * 60 * 60 * 1000; // 30 hari

/**
 * Bonus loyalty point untuk user yang submit review LENGKAP.
 * "Lengkap" = rating + content >= 10 char + min 1 foto. Lihat
 * isCompleteReview() untuk detail rule.
 *
 * Award flow:
 *   - createReview: award kalau submission udah lengkap saat first save
 *   - editReview: award retroactive kalau user upgrade review jadi lengkap
 *     (dari minimal/incomplete jadi lengkap)
 *   - softDeleteReview: rollback point (delete CustomerPoint dengan
 *     source = REVIEW:{id})
 *
 * Idempotency: source format "REVIEW:{reviewId}" unique per review.
 * awardReviewPoints cek dulu sebelum create — kalau sudah ada entry,
 * skip (return false). Cegah double-award kalau code path call ulang
 * (mis. edit yang trigger re-award padahal udah awarded).
 *
 * Minimum panjang content 10 char = cegah spam "ok"/"a"/"good"/dst.
 * Cukup meaningful untuk dianggap real description.
 */
export const REVIEW_POINTS_BONUS = 5;
const REVIEW_MIN_CONTENT_LENGTH = 10;
const REVIEW_POINTS_SOURCE_PREFIX = "REVIEW:";

/**
 * Cek apakah review memenuhi kriteria "lengkap" untuk dapat bonus poin.
 * Return true kalau ALL TIGA terisi:
 *   - rating > 0 (selalu true kalau review valid karena validated 1-5)
 *   - content.trim().length >= 10 (deskripsi meaningful)
 *   - imageCount >= 1 (min 1 foto)
 */
export function isCompleteReview(input: {
  rating: number;
  content: string | null;
  imageCount: number;
}): boolean {
  if (input.rating <= 0) return false;
  if ((input.content?.trim().length ?? 0) < REVIEW_MIN_CONTENT_LENGTH) return false;
  if (input.imageCount < 1) return false;
  return true;
}

/**
 * Award bonus loyalty point untuk review LENGKAP.
 * Idempotent: kalau review.id sudah pernah dapat point, skip (return false).
 *
 * Harus dipanggil DI DALAM transaction (tx parameter) bersama dengan
 * review create/update — supaya atomic dengan operasi review-nya.
 *
 * @returns true kalau point baru di-award, false kalau sudah pernah / skip
 */
export async function awardReviewPoints(
  tx: Prisma.TransactionClient,
  reviewId: string,
  userId: string,
): Promise<boolean> {
  const source = `${REVIEW_POINTS_SOURCE_PREFIX}${reviewId}`;
  const existing = await tx.customerPoint.findFirst({
    where: { source },
    select: { id: true },
  });
  if (existing) return false; // already awarded — defensive guard

  await tx.customerPoint.create({
    data: {
      userId,
      points: REVIEW_POINTS_BONUS,
      source,
    },
  });
  return true;
}

/**
 * Rollback poin yang udah di-award untuk review tertentu.
 * Dipanggil saat review dihapus (soft-delete) supaya user tidak keep
 * poin untuk review yang sudah tidak ada.
 *
 * @returns jumlah CustomerPoint entry yang dihapus (0 atau 1 dalam normal flow)
 */
export async function rollbackReviewPoints(
  tx: Prisma.TransactionClient,
  reviewId: string,
): Promise<number> {
  const source = `${REVIEW_POINTS_SOURCE_PREFIX}${reviewId}`;
  const result = await tx.customerPoint.deleteMany({
    where: { source },
  });
  return result.count;
}

// ── Helpers ────────────────────────────────────────────────────

/**
 * Mask nama jadi format "Andi S." (first name + initial last name).
 * Single-word name (misal "Andi") tetap "Andi".
 */
export function maskName(name: string): string {
  const parts = name.trim().split(/\s+/);
  if (parts.length === 1) return parts[0];
  const last = parts[parts.length - 1];
  return `${parts[0]} ${(last[0] ?? "").toUpperCase()}.`;
}

export function canEdit(review: { createdAt: Date }): boolean {
  return Date.now() - review.createdAt.getTime() < EDIT_WINDOW_MS;
}

/**
 * Recompute & save aggregate di Product berdasarkan review VISIBLE.
 * Jalankan di dalam transaksi yang sudah berjalan (parameter tx).
 */
export async function recomputeProductAggregate(
  tx: Prisma.TransactionClient,
  productId: string
) {
  const reviews = await tx.review.findMany({
    where: { productId, status: "VISIBLE" },
    select: { rating: true },
  });

  const count = reviews.length;
  const sum = reviews.reduce((s, r) => s + r.rating, 0);
  const avg = count > 0 ? Number((sum / count).toFixed(1)) : 0;

  const breakdown: Record<string, number> = { 1: 0, 2: 0, 3: 0, 4: 0, 5: 0 };
  for (const r of reviews) breakdown[r.rating] = (breakdown[r.rating] ?? 0) + 1;

  await tx.product.update({
    where: { id: productId },
    data: {
      avgRating: avg,
      reviewCount: count,
      ratingBreakdown: breakdown,
    },
  });
}

// ── Create ─────────────────────────────────────────────────────

interface CreateReviewInput {
  userId: string;
  orderItemId: string;
  rating: number;
  title?: string | null;
  content?: string | null;
  imageUrls?: string[];
}

/**
 * Result type untuk createReview.
 * - review: data review yang baru dibuat (dengan images)
 * - pointsAwarded: 5 kalau review lengkap, 0 kalau belum lengkap
 *   (rating+content>=10char+min1foto). Flutter pakai untuk show snackbar
 *   conditional.
 */
export type CreateReviewResult = {
  review: Prisma.ReviewGetPayload<{ include: { images: true } }>;
  pointsAwarded: number;
};

export async function createReview(
  input: CreateReviewInput,
): Promise<CreateReviewResult> {
  const { userId, orderItemId, rating, title, content, imageUrls = [] } = input;

  if (!Number.isInteger(rating) || rating < 1 || rating > 5) {
    throw new Error("Rating harus antara 1–5.");
  }
  if (imageUrls.length > 5) {
    throw new Error("Maksimal 5 foto per review.");
  }

  return prisma.$transaction(async (tx) => {
    // Validasi: order item milik user, status order = DELIVERED
    const orderItem = await tx.orderItem.findUnique({
      where: { id: orderItemId },
      include: {
        order: { select: { userId: true, status: true } },
      },
    });

    if (!orderItem) throw new Error("Item pesanan tidak ditemukan.");
    if (orderItem.order.userId !== userId)
      throw new Error("Anda tidak berhak mereview item ini.");
    if (orderItem.order.status !== "DELIVERED")
      throw new Error("Hanya pesanan yang sudah selesai (Diterima) yang bisa direview.");

    // Cek tidak ada review aktif (VISIBLE/HIDDEN) untuk item yang sama
    const activeReview = await tx.review.findFirst({
      where: { orderItemId, status: { not: "DELETED" } },
    });
    if (activeReview)
      throw new Error("Item ini sudah pernah direview.");

    // Buat review + foto
    const review = await tx.review.create({
      data: {
        productId: orderItem.productId,
        variantId: orderItem.variantId,
        variantLabel: orderItem.variantLabel,
        userId,
        orderItemId,
        rating,
        title: title?.trim() || null,
        content: content?.trim() || null,
        status: "VISIBLE",
        images: imageUrls.length
          ? {
              create: imageUrls.map((url, i) => ({
                imageUrl: url,
                position: i,
              })),
            }
          : undefined,
      },
      include: { images: true },
    });

    await recomputeProductAggregate(tx, orderItem.productId);

    // Award 5 poin loyal kalau submission udah lengkap (rating + content
    // min 10 char + min 1 foto). Atomic dalam transaction yang sama supaya
    // review + point award sukses/gagal bersama.
    let pointsAwarded = 0;
    if (
      isCompleteReview({
        rating,
        content: content ?? null,
        imageCount: imageUrls.length,
      })
    ) {
      const awarded = await awardReviewPoints(tx, review.id, userId);
      if (awarded) pointsAwarded = REVIEW_POINTS_BONUS;
    }

    return { review, pointsAwarded };
  });
}

// ── Edit ───────────────────────────────────────────────────────

interface EditReviewInput {
  reviewId: string;
  userId: string;
  rating?: number;
  title?: string | null;
  content?: string | null;
  imageUrls?: string[];
}

export type EditReviewResult = {
  review: Prisma.ReviewGetPayload<{}>;
  /** Poin yang baru di-award via edit (retroactive). 0 kalau sudah pernah
   *  dapat sebelumnya atau masih belum lengkap. */
  pointsAwarded: number;
};

export async function editReview(input: EditReviewInput): Promise<EditReviewResult> {
  const { reviewId, userId, rating, title, content, imageUrls } = input;

  return prisma.$transaction(async (tx) => {
    const review = await tx.review.findUnique({ where: { id: reviewId } });
    if (!review) throw new Error("Review tidak ditemukan.");
    if (review.userId !== userId)
      throw new Error("Anda tidak berhak mengedit review ini.");
    if (review.status === "DELETED")
      throw new Error("Review sudah dihapus.");
    if (!canEdit(review))
      throw new Error("Review hanya bisa diedit dalam 30 hari setelah dibuat.");

    if (rating !== undefined) {
      if (!Number.isInteger(rating) || rating < 1 || rating > 5)
        throw new Error("Rating harus antara 1–5.");
    }
    if (imageUrls !== undefined && imageUrls.length > 5) {
      throw new Error("Maksimal 5 foto per review.");
    }

    // Update review fields
    const updated = await tx.review.update({
      where: { id: reviewId },
      data: {
        ...(rating !== undefined ? { rating } : {}),
        ...(title !== undefined ? { title: title?.trim() || null } : {}),
        ...(content !== undefined ? { content: content?.trim() || null } : {}),
      },
    });

    // Replace images kalau imageUrls dikirim (full replace)
    if (imageUrls !== undefined) {
      await tx.reviewImage.deleteMany({ where: { reviewId } });
      if (imageUrls.length > 0) {
        await tx.reviewImage.createMany({
          data: imageUrls.map((url, i) => ({
            reviewId,
            imageUrl: url,
            position: i,
          })),
        });
      }
    }

    // Re-aggregate kalau rating berubah atau status pindah
    if (rating !== undefined && rating !== review.rating) {
      await recomputeProductAggregate(tx, review.productId);
    }

    // Retroactive point award — kalau review sebelumnya belum lengkap
    // (dapat 0 poin saat create), lalu user edit jadi lengkap (tambah
    // foto/deskripsi), award 5 poin sekarang. awardReviewPoints
    // idempotent — kalau udah pernah award, skip.
    //
    // Hitung kelengkapan berdasarkan state SETELAH edit:
    //   - rating: dari input atau dari existing
    //   - content: dari input atau dari existing
    //   - imageCount: dari input length atau dari existing count
    const effectiveRating = rating !== undefined ? rating : review.rating;
    const effectiveContent =
      content !== undefined ? content : review.content;
    let effectiveImageCount: number;
    if (imageUrls !== undefined) {
      effectiveImageCount = imageUrls.length;
    } else {
      effectiveImageCount = await tx.reviewImage.count({ where: { reviewId } });
    }

    let pointsAwarded = 0;
    if (
      isCompleteReview({
        rating: effectiveRating,
        content: effectiveContent,
        imageCount: effectiveImageCount,
      })
    ) {
      const awarded = await awardReviewPoints(tx, reviewId, userId);
      if (awarded) pointsAwarded = REVIEW_POINTS_BONUS;
    }

    return { review: updated, pointsAwarded };
  });
}

// ── Soft delete ────────────────────────────────────────────────

export type DeleteReviewResult = {
  review: Prisma.ReviewGetPayload<{}>;
  /** Jumlah poin yang di-rollback (5 kalau ada, 0 kalau review sebelumnya
   *  belum pernah dapat poin). Flutter pakai untuk feedback. */
  pointsRolledBack: number;
};

export async function softDeleteReview(
  reviewId: string,
  userId: string,
): Promise<DeleteReviewResult> {
  return prisma.$transaction(async (tx) => {
    const review = await tx.review.findUnique({ where: { id: reviewId } });
    if (!review) throw new Error("Review tidak ditemukan.");
    if (review.userId !== userId)
      throw new Error("Anda tidak berhak menghapus review ini.");
    if (review.status === "DELETED") {
      return { review, pointsRolledBack: 0 };
    }

    const updated = await tx.review.update({
      where: { id: reviewId },
      data: { status: "DELETED" },
    });

    await recomputeProductAggregate(tx, review.productId);

    // Rollback poin yang pernah di-award untuk review ini (kalau ada).
    // Pattern: user submit review lengkap → dapat 5 poin → delete → poin
    // -5 lewat deleteMany (CustomerPoint entry source REVIEW:{id} dihapus).
    // Saldo poin user otomatis kurang via aggregate sum.
    const rollbackCount = await rollbackReviewPoints(tx, reviewId);
    const pointsRolledBack = rollbackCount > 0 ? REVIEW_POINTS_BONUS : 0;

    return { review: updated, pointsRolledBack };
  });
}

// ── Toggle helpful vote ────────────────────────────────────────

export async function toggleHelpful(reviewId: string, userId: string) {
  return prisma.$transaction(async (tx) => {
    const review = await tx.review.findUnique({ where: { id: reviewId } });
    if (!review) throw new Error("Review tidak ditemukan.");
    if (review.status !== "VISIBLE")
      throw new Error("Review tidak tersedia.");

    const existing = await tx.reviewVote.findUnique({
      where: { reviewId_userId: { reviewId, userId } },
    });

    if (existing) {
      await tx.reviewVote.delete({ where: { id: existing.id } });
      const updated = await tx.review.update({
        where: { id: reviewId },
        data: { helpfulCount: { decrement: 1 } },
      });
      return { voted: false, helpfulCount: updated.helpfulCount };
    } else {
      await tx.reviewVote.create({
        data: { reviewId, userId, isHelpful: true },
      });
      const updated = await tx.review.update({
        where: { id: reviewId },
        data: { helpfulCount: { increment: 1 } },
      });
      return { voted: true, helpfulCount: updated.helpfulCount };
    }
  });
}

// ── Admin: hide / unhide ───────────────────────────────────────

export async function setReviewStatus(
  reviewId: string,
  status: ReviewStatus,
  hiddenReason?: string
) {
  return prisma.$transaction(async (tx) => {
    const review = await tx.review.findUnique({ where: { id: reviewId } });
    if (!review) throw new Error("Review tidak ditemukan.");

    const updated = await tx.review.update({
      where: { id: reviewId },
      data: {
        status,
        hiddenReason: status === "HIDDEN" ? hiddenReason ?? null : null,
      },
    });

    if (review.status !== status) {
      await recomputeProductAggregate(tx, review.productId);
    }
    return updated;
  });
}

// ── Admin: reply ───────────────────────────────────────────────

export async function upsertAdminReply(
  reviewId: string,
  adminUserId: string,
  content: string
) {
  if (!content.trim()) throw new Error("Balasan tidak boleh kosong.");

  const admin = await prisma.user.findUnique({ where: { id: adminUserId } });
  if (!admin || admin.role !== "ADMIN") {
    throw new Error("Admin user tidak valid.");
  }

  return prisma.reviewReply.upsert({
    where: { reviewId },
    create: { reviewId, adminUserId, content: content.trim() },
    update: { content: content.trim(), adminUserId },
  });
}

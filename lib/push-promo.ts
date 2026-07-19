/**
 * Dispatch notifikasi promo (voucher & diskon produk) — pola sama dgn
 * lib/feed/publish-push.ts: SATU baris Announcement segment "all" (tampil di
 * lonceng semua user) + push batch ke resolveSegmentUserIds("all").
 *
 * Anti-dobel: klaim atomik promoNotifiedAt via updateMany(where null) SEBELUM
 * dispatch — route (kirim langsung) dan cron (kirim saat mulai) bisa menyentuh
 * baris yang sama; klaim menjamin push terkirim tepat sekali.
 *
 * Errors di-swallow — kegagalan push tak boleh menggagalkan pembuatan promo.
 */
import { prisma } from "@/lib/prisma";
import { sendPushToUser, type PushPayload } from "@/lib/push";
import { sendFcmToUser } from "@/lib/fcm";
import { resolveSegmentUserIds } from "@/lib/feed/publish-push";
import {
  buildVoucherPromoContent,
  buildDiscountPromoContent,
} from "@/lib/push-promo-content";

const BATCH_SIZE = 50;

/** Klaim atomik berhasil bila tepat 1 baris ter-update (promoNotifiedAt null→now). */
export function claimSucceeded(count: number): boolean {
  return count === 1;
}

async function dispatchBatch(userIds: string[], payload: PushPayload): Promise<void> {
  for (let i = 0; i < userIds.length; i += BATCH_SIZE) {
    const batch = userIds.slice(i, i + BATCH_SIZE);
    await Promise.allSettled(
      batch.flatMap((userId) => [
        sendPushToUser(userId, payload),
        sendFcmToUser(userId, payload),
      ]),
    );
  }
}

export async function sendVoucherPromoPush(voucherId: string): Promise<void> {
  try {
    const now = new Date();
    // Klaim atomik dulu — cegah route+cron dobel-kirim.
    const claim = await prisma.voucher.updateMany({
      where: { id: voucherId, promoNotifiedAt: null },
      data: { promoNotifiedAt: now },
    });
    if (!claimSucceeded(claim.count)) return;

    const v = await prisma.voucher.findUnique({
      where: { id: voucherId },
      select: {
        code: true,
        name: true,
        kind: true,
        discountPercent: true,
        discountAmount: true,
        isActive: true,
        startsAt: true,
        expiresAt: true,
      },
    });
    if (!v || !v.isActive) return;
    if (v.startsAt > now) return;
    if (v.expiresAt != null && v.expiresAt <= now) return;

    const { title, body, eventType } = buildVoucherPromoContent({
      code: v.code,
      name: v.name,
      kind: v.kind,
      discountPercent: v.discountPercent,
      discountAmount: v.discountAmount,
    });
    const url = "/member/vouchers";

    await prisma.announcement.create({
      data: {
        title,
        body,
        url,
        segment: "all",
        status: "PUBLISHED",
        type: "promo",
        eventType,
        thumbnailUrl: null,
        ctaLabel: "Lihat Voucher",
        publishedAt: now,
      },
    });

    const userIds = await resolveSegmentUserIds("all");
    if (userIds.length === 0) return;
    const payload: PushPayload = {
      title,
      body,
      url,
      tag: `voucher-promo-${voucherId}`,
      prefCategory: "promo",
      data: { type: eventType, voucherKind: v.kind },
    };
    await dispatchBatch(userIds, payload);
  } catch (err) {
    console.warn("[push-promo] voucher failed:", err);
  }
}

export async function sendProductDiscountPromoPush(discountId: string): Promise<void> {
  try {
    const now = new Date();
    const claim = await prisma.productDiscount.updateMany({
      where: { id: discountId, promoNotifiedAt: null },
      data: { promoNotifiedAt: now },
    });
    if (!claimSucceeded(claim.count)) return;

    const d = await prisma.productDiscount.findUnique({
      where: { id: discountId },
      select: {
        name: true,
        isActive: true,
        startsAt: true,
        endsAt: true,
        items: {
          where: { isItemActive: true },
          select: {
            discountedPrice: true,
            product: { select: { name: true, slug: true, imageUrl: true, price: true } },
            variant: { select: { price: true } },
          },
        },
      },
    });
    if (!d || !d.isActive) return;
    if (d.startsAt > now) return;
    if (d.endsAt <= now) return;
    if (d.items.length === 0) return;

    const { title, body, url, thumbnailUrl } = buildDiscountPromoContent(
      { name: d.name },
      d.items,
    );

    await prisma.announcement.create({
      data: {
        title,
        body,
        url,
        segment: "all",
        status: "PUBLISHED",
        type: "promo",
        eventType: "product_discount_published",
        thumbnailUrl,
        ctaLabel: "Lihat Promo",
        publishedAt: now,
      },
    });

    const userIds = await resolveSegmentUserIds("all");
    if (userIds.length === 0) return;
    const payload: PushPayload = {
      title,
      body,
      url,
      tag: `discount-promo-${discountId}`,
      prefCategory: "promo",
      imageUrl: thumbnailUrl,
      data: { type: "product_discount_published" },
    };
    await dispatchBatch(userIds, payload);
  } catch (err) {
    console.warn("[push-promo] discount failed:", err);
  }
}

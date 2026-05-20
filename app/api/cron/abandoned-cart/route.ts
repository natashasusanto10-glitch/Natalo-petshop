/**
 * GET /api/cron/abandoned-cart — Vercel cron (hourly)
 *
 * Cari CartItem yang sudah lebih dari 4 jam di cart dan belum di-checkout
 * (createdAt < now - 4h, notifiedAbandonedAt IS NULL). Group by userId,
 * send 1 push reminder per user dengan preview item teratas.
 *
 * Anti-spam:
 * - Skip item yang sudah pernah di-notify (notifiedAbandonedAt != null).
 * - Skip item lebih tua dari 7 hari (out-of-mind, bukan intent aktif).
 * - 1 push per user per cron run (bukan per item).
 * - Tag "abandoned-cart-{userId}" — push replace di device, tidak stack.
 *
 * Trigger:
 * - Schedule di vercel.json: "0 * * * *" (setiap jam tepat).
 * - Auth: Vercel auto-injects CRON_SECRET header — verify di handler.
 */
import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import {
  ABANDONED_CART_DELAY_MS,
  ABANDONED_CART_MAX_AGE_MS,
  sendAbandonedCartPush,
} from "@/lib/push-marketing";

export const dynamic = "force-dynamic";
export const maxDuration = 60;

export async function GET(request: NextRequest) {
  // Verify Vercel cron header — public route, but only Vercel infra
  // can set this header. Production safety.
  const authHeader = request.headers.get("authorization");
  const cronSecret = process.env.CRON_SECRET;
  if (cronSecret && authHeader !== `Bearer ${cronSecret}`) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const now = Date.now();
  const oldestEligible = new Date(now - ABANDONED_CART_MAX_AGE_MS);
  const newestEligible = new Date(now - ABANDONED_CART_DELAY_MS);

  // Fetch eligible cart items, grouped by userId.
  const items = await prisma.cartItem.findMany({
    where: {
      notifiedAbandonedAt: null,
      createdAt: {
        gte: oldestEligible,
        lte: newestEligible,
      },
    },
    select: {
      id: true,
      userId: true,
      name: true,
      imageUrl: true,
      createdAt: true,
    },
    orderBy: { createdAt: "asc" },
  });

  if (items.length === 0) {
    return NextResponse.json({
      ok: true,
      message: "No abandoned cart items eligible.",
      checked: 0,
      notified: 0,
    });
  }

  // Group by userId — 1 push per user dengan preview item teratas.
  const byUser = new Map<
    string,
    Array<{ id: string; name: string; imageUrl: string | null }>
  >();
  for (const item of items) {
    if (!byUser.has(item.userId)) byUser.set(item.userId, []);
    byUser.get(item.userId)!.push({
      id: item.id,
      name: item.name,
      imageUrl: item.imageUrl,
    });
  }

  let notified = 0;
  const failedUsers: string[] = [];

  // Dispatch parallel per user.
  await Promise.allSettled(
    Array.from(byUser.entries()).map(async ([userId, userItems]) => {
      const ok = await sendAbandonedCartPush(userId, userItems);
      if (ok) {
        notified += 1;
        // Mark all eligible items for this user as notified.
        await prisma.cartItem
          .updateMany({
            where: {
              id: { in: userItems.map((i) => i.id) },
            },
            data: {
              notifiedAbandonedAt: new Date(),
            },
          })
          .catch(() => {});
      } else {
        failedUsers.push(userId);
      }
    }),
  );

  return NextResponse.json({
    ok: true,
    checked: items.length,
    usersTotal: byUser.size,
    notified,
    failedUsers: failedUsers.length,
  });
}

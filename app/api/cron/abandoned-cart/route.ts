/**
 * GET /api/cron/abandoned-cart — Vercel cron (hourly)
 *
 * Cari CartItem yang sudah lebih dari 4 jam di cart dan belum di-checkout
 * (createdAt < now - 4h, notifiedAbandonedAt IS NULL). Group by userId,
 * send 1 push reminder per user dengan preview item teratas.
 *
 * Guardrail sebelum kirim (docs/superpowers/specs/2026-07-05-abandoned-cart-cron-guardrail-design.md):
 * 1. Skip item yang produk/variannya sudah tidak bisa dibeli (nonaktif,
 *    dihapus, atau stok habis) — dicek lewat getCartStockSnapshots(),
 *    fungsi yang sama dipakai GET /api/cart.
 * 2. Syarat 2-putaran-berturut: item yang baru pertama kali terlihat
 *    eligible ditandai `abandonedCandidateAt` dulu, BELUM dinotifikasi.
 *    Baru dinotifikasi di run berikutnya kalau masih eligible & belum
 *    disinkron ulang (row abandonedCandidateAt reset otomatis tiap kali
 *    PUT /api/cart replace-total membuat ulang row ini). Ini menambah
 *    jeda ~1 jam ke SEMUA notifikasi abandoned-cart secara sengaja —
 *    beri kesempatan row cart "hantu" (dari sync yang gagal) sembuh
 *    sendiri sebelum benar-benar dinotifikasi.
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
import { getCartStockSnapshots } from "@/lib/cart-stock-server";
import {
  filterAvailableAbandonedCartItems,
  splitAbandonedCartCandidates,
} from "@/lib/abandoned-cart-guardrail";
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
      productId: true,
      variantId: true,
      variantLabel: true,
      quantity: true,
      abandonedCandidateAt: true,
    },
    orderBy: { createdAt: "asc" },
  });

  if (items.length === 0) {
    return NextResponse.json({
      ok: true,
      message: "No abandoned cart items eligible.",
      checked: 0,
      skippedUnavailable: 0,
      markedAsCandidate: 0,
      usersTotal: 0,
      notified: 0,
      failedUsers: 0,
    });
  }

  // Guardrail 1 — buang item yang produk/variannya sudah tidak bisa dibeli.
  const snapshots = await getCartStockSnapshots(
    items.map((item) => ({
      productId: item.productId,
      variantId: item.variantId,
      variantLabel: item.variantLabel,
      name: item.name,
      quantity: item.quantity,
    })),
  );
  const availableItems = filterAvailableAbandonedCartItems(items, snapshots);
  const skippedUnavailable = items.length - availableItems.length;

  // Guardrail 2 — syarat 2-putaran-berturut sebelum benar-benar notify.
  const { toMark, toNotify } = splitAbandonedCartCandidates(availableItems);

  if (toMark.length > 0) {
    await prisma.cartItem
      .updateMany({
        where: { id: { in: toMark.map((item) => item.id) } },
        data: { abandonedCandidateAt: new Date() },
      })
      .catch(() => {});
  }

  if (toNotify.length === 0) {
    return NextResponse.json({
      ok: true,
      checked: items.length,
      skippedUnavailable,
      markedAsCandidate: toMark.length,
      usersTotal: 0,
      notified: 0,
      failedUsers: 0,
    });
  }

  // Group by userId — 1 push per user dengan preview item teratas.
  const byUser = new Map<
    string,
    Array<{ id: string; name: string; imageUrl: string | null }>
  >();
  for (const item of toNotify) {
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
    skippedUnavailable,
    markedAsCandidate: toMark.length,
    usersTotal: byUser.size,
    notified,
    failedUsers: failedUsers.length,
  });
}

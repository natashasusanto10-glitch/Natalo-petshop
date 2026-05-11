/**
 * POST /api/admin/push/broadcast
 *
 * Kirim push notification ke semua user yang punya PushSubscription
 * (Web Push atau APNs). Admin-only.
 *
 * Body:
 *   {
 *     title: string,
 *     body: string,
 *     url?: string,         // optional deep link (default "/")
 *     segment?: "all" | "members" | "active30d" | "test",
 *     dryRun?: boolean      // jika true, return recipient count tanpa kirim
 *   }
 *
 * Segments:
 *   - "all" (default): semua user yg punya push subscription
 *   - "members": user yg pernah complete order (paymentStatus=PAID)
 *   - "active30d": user yg punya order dalam 30 hari terakhir
 *   - "test": cuma kirim ke admin yg trigger broadcast (preview test)
 *
 * Response:
 *   { ok, recipientCount, sent, failed, elapsed_ms }
 *
 * Batching: kirim per 50 user paralel utk hindari memory spike + APNs
 * rate limit. APNs dapat handle 4000 connections/s, web-push dgn VAPID
 * tidak ada explicit rate tapi safer to batch.
 */
import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { sendPushToUser, type PushPayload } from "@/lib/push";
import { sendApnsToUser } from "@/lib/apns";
import { sendFcmToUser } from "@/lib/fcm";

const broadcastSchema = z.object({
  title: z.string().trim().min(1).max(60),
  body: z.string().trim().min(1).max(180),
  url: z.string().trim().optional().nullable(),
  segment: z.enum(["all", "members", "active30d", "test"]).default("all"),
  dryRun: z.boolean().default(false),
});

const BATCH_SIZE = 50;
export const maxDuration = 60;

export async function POST(request: NextRequest) {
  const session = await getSession("ADMIN");
  if (!session || session.role !== "ADMIN") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const json = await request.json().catch(() => null);
  const parsed = broadcastSchema.safeParse(json);
  if (!parsed.success) {
    return NextResponse.json(
      { error: "Bad request", details: parsed.error.flatten() },
      { status: 400 },
    );
  }

  const { title, body, url, segment, dryRun } = parsed.data;
  const startedAt = Date.now();

  // ── 1. Resolve userIds berdasarkan segment ─────────────────────
  let targetUserIds: string[] = [];

  if (segment === "test") {
    targetUserIds = [session.sub];
  } else if (segment === "all") {
    const rows = await prisma.pushSubscription.findMany({
      where: { userId: { not: null } },
      select: { userId: true },
      distinct: ["userId"],
    });
    targetUserIds = rows.map((r) => r.userId).filter((id): id is string => !!id);
  } else if (segment === "members" || segment === "active30d") {
    const since =
      segment === "active30d" ? new Date(Date.now() - 30 * 24 * 60 * 60 * 1000) : null;

    const orderUsers = await prisma.order.findMany({
      where: {
        userId: { not: null },
        paymentStatus: "PAID",
        ...(since ? { createdAt: { gte: since } } : {}),
      },
      select: { userId: true },
      distinct: ["userId"],
    });
    const orderUserIds = orderUsers
      .map((o) => o.userId)
      .filter((id): id is string => !!id);

    // Intersect dgn yg punya push subscription — yg gak subscribe tidak
    // bisa di-kirim, jadi exclude duluan.
    if (orderUserIds.length === 0) {
      targetUserIds = [];
    } else {
      const subRows = await prisma.pushSubscription.findMany({
        where: { userId: { in: orderUserIds } },
        select: { userId: true },
        distinct: ["userId"],
      });
      targetUserIds = subRows.map((r) => r.userId).filter((id): id is string => !!id);
    }
  }

  if (dryRun) {
    return NextResponse.json({
      ok: true,
      dryRun: true,
      segment,
      recipientCount: targetUserIds.length,
      elapsed_ms: Date.now() - startedAt,
    });
  }

  if (targetUserIds.length === 0) {
    return NextResponse.json({
      ok: true,
      recipientCount: 0,
      sent: 0,
      failed: 0,
      elapsed_ms: Date.now() - startedAt,
    });
  }

  // ── 2. Build payload ───────────────────────────────────────────
  const payload: PushPayload = {
    title,
    body,
    url: url?.trim() || "/",
    tag: `broadcast-${Date.now()}`, // unique per broadcast
  };

  // ── 3. Batch send ──────────────────────────────────────────────
  let sent = 0;
  let failed = 0;

  const CHANNELS_PER_USER = 3; // web + apns + fcm
  for (let i = 0; i < targetUserIds.length; i += BATCH_SIZE) {
    const batch = targetUserIds.slice(i, i + BATCH_SIZE);
    const results = await Promise.allSettled(
      batch.flatMap((userId) => [
        sendPushToUser(userId, payload),
        sendApnsToUser(userId, payload),
        sendFcmToUser(userId, payload),
      ]),
    );
    // Hitung per user (3 channel — anggap success kalau salah satu sukses).
    // User yg gak punya subscription di channel tertentu tetap "fulfilled"
    // dgn return undefined — channel resolver skip silently jika no subs.
    for (let j = 0; j < batch.length; j++) {
      const webResult = results[j * CHANNELS_PER_USER];
      const apnsResult = results[j * CHANNELS_PER_USER + 1];
      const fcmResult = results[j * CHANNELS_PER_USER + 2];
      const userOk =
        webResult.status === "fulfilled" ||
        apnsResult.status === "fulfilled" ||
        fcmResult.status === "fulfilled";
      if (userOk) sent++;
      else failed++;
    }
  }

  return NextResponse.json({
    ok: true,
    segment,
    recipientCount: targetUserIds.length,
    sent,
    failed,
    elapsed_ms: Date.now() - startedAt,
  });
}

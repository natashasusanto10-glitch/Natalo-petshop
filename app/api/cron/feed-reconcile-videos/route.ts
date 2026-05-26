/**
 * GET /api/cron/feed-reconcile-videos
 *
 * Vercel Cron — scheduled tiap 10 menit (lihat vercel.json). Scan post
 * yang stuck di state encoding non-terminal (uploading / processing)
 * dengan createdAt > 5 menit lalu, lalu reconcile vs Bunny Stream API.
 *
 * Kenapa cron ini perlu:
 *   - Bunny webhook bisa gagal kirim (network blip, Vercel cold start,
 *     deploy mid-flight). Tanpa fallback, post stuck PROCESSING selamanya.
 *   - User bingung — video udah upload tapi gak tayang.
 *
 * Logic per post (lihat lib/feed/reconcile.ts):
 *   - Bunny says READY → mark post ready + trigger pending-review notif
 *   - Bunny says ERROR → mark FAILED + notify user
 *   - Bunny null AND stuck > 60 min → mark FAILED ("upload gak selesai")
 *   - Bunny still processing AND stuck > 60 min → mark FAILED ("timeout")
 *   - Else: skip (masih tunggu)
 *
 * Throughput: take 50 post per run. Worst case 50 × 1s Bunny API call
 * = 50 detik (di bawah 60s function limit).
 *
 * Auth: CRON_SECRET via Authorization header — Vercel auto-inject untuk
 * cron-originated request.
 */

import { NextRequest, NextResponse } from "next/server";
import * as Sentry from "@sentry/nextjs";
import { prisma } from "@/lib/prisma";
import {
  reconcileFeedPost,
  type ReconcileResult,
} from "@/lib/feed/reconcile";

export const dynamic = "force-dynamic";
export const maxDuration = 60;

const BATCH_SIZE = 50;
// Minimum age sebelum post di-reconcile. Hindari race condition dengan
// webhook yang baru ke-fire — webhook biasanya nyampai dalam 1-3 menit
// setelah encoding mulai, kasih buffer 5 menit.
const RECONCILE_MIN_AGE_MINUTES = 5;
// Threshold "stuck too long" — kalau lewat ini AND Bunny gak balikin
// READY, mark FAILED. Bunny encoding video <60s biasanya selesai 1-3 menit.
// 60 menit = safe buffer untuk video panjang + retry attempts Bunny.
const STUCK_FAIL_THRESHOLD_MINUTES = 60;

function isAuthorized(request: NextRequest): boolean {
  const expected = process.env.CRON_SECRET;
  if (!expected) return false;
  const got = request.headers.get("authorization") ?? "";
  return got === `Bearer ${expected}`;
}

export async function GET(request: NextRequest) {
  if (!isAuthorized(request)) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const cutoff = new Date(
    Date.now() - RECONCILE_MIN_AGE_MINUTES * 60 * 1000,
  );

  const stuckPosts = await prisma.feedPost.findMany({
    where: {
      encodingStatus: { in: ["uploading", "processing"] },
      createdAt: { lt: cutoff },
      videoGuid: { not: null },
      deletedAt: null,
    },
    orderBy: { createdAt: "asc" },
    take: BATCH_SIZE,
    select: { id: true, createdAt: true },
  });

  const summary = {
    scanned: stuckPosts.length,
    ready: 0,
    failed: 0,
    skipped: 0,
    results: [] as ReconcileResult[],
  };

  for (const post of stuckPosts) {
    try {
      const result = await reconcileFeedPost(post.id, {
        failAfterStuckMinutes: STUCK_FAIL_THRESHOLD_MINUTES,
      });
      summary.results.push(result);
      if (result.action === "ready") summary.ready += 1;
      else if (result.action === "failed") summary.failed += 1;
      else summary.skipped += 1;

      // Sentry alert untuk post yang stuck >2× threshold — kemungkinan ada
      // problem sistemik (Bunny outage, network issue, dst). Tag dengan
      // postId supaya admin bisa drill down.
      const stuckMinutes =
        (Date.now() - post.createdAt.getTime()) / (1000 * 60);
      if (
        stuckMinutes >= STUCK_FAIL_THRESHOLD_MINUTES * 2 &&
        result.action !== "ready"
      ) {
        Sentry.captureMessage(
          `Feed post stuck ${Math.round(stuckMinutes)} menit — reconcile=${result.action}`,
          {
            level: "warning",
            tags: {
              source: "feed-reconcile-cron",
              postId: post.id,
              action: result.action,
            },
          },
        );
      }
    } catch (err) {
      summary.skipped += 1;
      Sentry.captureException(err, {
        tags: {
          source: "feed-reconcile-cron",
          postId: post.id,
        },
      });
    }
  }

  // Top-level alert kalau banyak post sekaligus failed di 1 run —
  // kemungkinan ada outage Bunny atau bug systemic.
  if (summary.failed >= 5) {
    Sentry.captureMessage(
      `Feed reconcile cron mark ${summary.failed} post FAILED dalam 1 run — investigate Bunny status?`,
      {
        level: "error",
        tags: { source: "feed-reconcile-cron" },
        extra: { summary },
      },
    );
  }

  return NextResponse.json({
    ok: true,
    summary: {
      scanned: summary.scanned,
      ready: summary.ready,
      failed: summary.failed,
      skipped: summary.skipped,
    },
    results: summary.results,
  });
}

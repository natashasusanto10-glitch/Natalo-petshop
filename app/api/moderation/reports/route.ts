/**
 * POST /api/moderation/reports
 *
 * User-facing report endpoint untuk UGC (User-Generated Content):
 *   - Feed post (kind=feed_post)
 *   - Feed comment (kind=feed_comment)
 *
 * Required by Google Play UGC policy — setiap app yang punya komen/feed/
 * review HARUS punya cara user laporkan konten yg melanggar. Flutter
 * client (lib/services/report_service.dart) udah call endpoint ini —
 * sebelumnya 404 silent → admin lihat 0 reports padahal user laporin.
 *
 * Body shape (dari Flutter):
 *   {
 *     targetKind: "feed_post" | "feed_comment" | "product_review" | "user",
 *     targetId: string,
 *     reason: "spam" | "hate_speech" | "violence" | "sexual" |
 *             "harassment" | "misinformation" | "copyright" |
 *             "illegal" | "other",
 *     note?: string (optional detail)
 *   }
 *
 * Anti-abuse:
 *   1. Login wajib (CUSTOMER role). Anonymous report bisa di-spam.
 *   2. Anti-duplicate: kalau reporterId × targetType × targetId udah ada
 *      report sebelumnya (status apapun), return 200 dengan
 *      alreadyReported=true. Cegah user spam tombol "Laporkan" ke
 *      konten yang sama berkali-kali.
 *   3. Rate limit: max 5 reports per user per 24 jam. Cegah abuse user
 *      yang mass-report konten siapapun yang dia gak suka.
 *   4. Target validation: cek target exist sebelum create report
 *      → cegah report ke ID random/garbage.
 *
 * product_review dan user kind sengaja di-skip (return 200 ok diam-diam)
 * supaya Flutter UX gak break tapi schema FeedReport (POST|COMMENT only)
 * gak tersentuh. Bisa di-extend kalau perlu.
 */
import { NextRequest, NextResponse } from "next/server";
import type { FeedReportReason } from "@prisma/client";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { assertSameOrigin } from "@/lib/csrf";

const MAX_NOTE_LENGTH = 500;
const RATE_LIMIT_PER_WINDOW = 5;
const RATE_LIMIT_WINDOW_MS = 24 * 60 * 60 * 1000;

/**
 * Mapping Flutter reason values ke schema enum FeedReportReason.
 * Schema cuma punya 5 enum value (SPAM/INAPPROPRIATE/MISLEADING/
 * COPYRIGHT/OTHER), Flutter punya 9 (lebih granular sesuai Google Play
 * policy). Fold ke schema enum untuk simplicity admin moderation.
 *
 * Detail asli dari Flutter (mis. "hate_speech") di-store di `detail`
 * field — admin tetap bisa lihat reason precise via detail.
 */
const REASON_MAP: Record<string, FeedReportReason> = {
  spam: "SPAM",
  hate_speech: "INAPPROPRIATE",
  violence: "INAPPROPRIATE",
  sexual: "INAPPROPRIATE",
  harassment: "INAPPROPRIATE",
  misinformation: "MISLEADING",
  copyright: "COPYRIGHT",
  illegal: "INAPPROPRIATE",
  other: "OTHER",
};

export async function POST(request: NextRequest) {
  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return csrfReject;

  const session = await getSession("CUSTOMER");
  if (!session || session.role !== "CUSTOMER") {
    return NextResponse.json(
      { error: "Silakan login member terlebih dahulu untuk melaporkan." },
      { status: 401 },
    );
  }

  const body = await request.json().catch(() => ({}));
  const targetKind = String(body.targetKind ?? "").trim().toLowerCase();
  const targetId = String(body.targetId ?? "").trim();
  const reasonRaw = String(body.reason ?? "").trim().toLowerCase();
  const note = body.note ? String(body.note).slice(0, MAX_NOTE_LENGTH).trim() : null;

  if (!targetId) {
    return NextResponse.json({ error: "Target ID kosong." }, { status: 400 });
  }
  const mappedReason = REASON_MAP[reasonRaw];
  if (!mappedReason) {
    return NextResponse.json(
      { error: `Reason tidak valid: ${reasonRaw}` },
      { status: 400 },
    );
  }

  // product_review dan user di-skip — return success supaya Flutter UX
  // gak break, tapi gak create row di FeedReport. Future: bikin
  // ReviewReport / UserReport model terpisah.
  if (targetKind === "product_review" || targetKind === "user") {
    console.log(
      `[moderation-reports] skipped ${targetKind} report by ${session.sub} target=${targetId} reason=${reasonRaw}`,
    );
    return NextResponse.json({ ok: true, skipped: true });
  }

  if (targetKind !== "feed_post" && targetKind !== "feed_comment") {
    return NextResponse.json(
      { error: `Target kind tidak valid: ${targetKind}` },
      { status: 400 },
    );
  }

  // Rate limit check — sebelum touch DB lebih banyak. Cegah user mass-report.
  const since = new Date(Date.now() - RATE_LIMIT_WINDOW_MS);
  const recentCount = await prisma.feedReport.count({
    where: {
      reporterId: session.sub,
      createdAt: { gte: since },
    },
  });
  if (recentCount >= RATE_LIMIT_PER_WINDOW) {
    return NextResponse.json(
      {
        error: `Kamu sudah melaporkan ${RATE_LIMIT_PER_WINDOW} konten dalam 24 jam terakhir. Coba lagi besok.`,
        rateLimited: true,
      },
      { status: 429 },
    );
  }

  // Validate target exist + bukan punya reporter sendiri (anti self-report).
  if (targetKind === "feed_post") {
    const post = await prisma.feedPost.findUnique({
      where: { id: targetId },
      select: { id: true, authorId: true, deletedAt: true },
    });
    if (!post || post.deletedAt) {
      return NextResponse.json(
        { error: "Postingan tidak ditemukan." },
        { status: 404 },
      );
    }
    if (post.authorId === session.sub) {
      return NextResponse.json(
        { error: "Tidak bisa melaporkan postingan sendiri." },
        { status: 400 },
      );
    }

    // Anti-duplicate: cek apakah user udah pernah report post yang sama.
    // Apapun status report sebelumnya (PENDING/RESOLVED/DISMISSED),
    // tolak duplicate supaya gak spam admin queue.
    const existing = await prisma.feedReport.findFirst({
      where: {
        reporterId: session.sub,
        targetType: "POST",
        postId: targetId,
      },
      select: { id: true, status: true, createdAt: true },
    });
    if (existing) {
      return NextResponse.json({
        ok: true,
        alreadyReported: true,
        reportId: existing.id,
        status: existing.status,
        message:
          "Kamu sudah melaporkan postingan ini sebelumnya. Tim kami sedang mereview.",
      });
    }

    const created = await prisma.feedReport.create({
      data: {
        reporterId: session.sub,
        targetType: "POST",
        postId: targetId,
        reason: mappedReason,
        // Store Flutter reason mentahnya di detail supaya admin lihat
        // granularity (mis. "hate_speech" vs "violence" yang sama-sama
        // mapped ke INAPPROPRIATE di enum).
        detail: [
          `flutter_reason: ${reasonRaw}`,
          note ? `note: ${note}` : null,
        ]
          .filter(Boolean)
          .join("\n"),
      },
      select: { id: true, status: true },
    });

    return NextResponse.json({
      ok: true,
      reportId: created.id,
      status: created.status,
      message: "Laporan diterima. Tim moderasi akan mereview.",
    });
  }

  // feed_comment branch
  const comment = await prisma.feedComment.findUnique({
    where: { id: targetId },
    select: { id: true, authorId: true },
  });
  if (!comment) {
    return NextResponse.json(
      { error: "Komentar tidak ditemukan." },
      { status: 404 },
    );
  }
  if (comment.authorId === session.sub) {
    return NextResponse.json(
      { error: "Tidak bisa melaporkan komentar sendiri." },
      { status: 400 },
    );
  }

  const existingCmt = await prisma.feedReport.findFirst({
    where: {
      reporterId: session.sub,
      targetType: "COMMENT",
      commentId: targetId,
    },
    select: { id: true, status: true },
  });
  if (existingCmt) {
    return NextResponse.json({
      ok: true,
      alreadyReported: true,
      reportId: existingCmt.id,
      status: existingCmt.status,
      message:
        "Kamu sudah melaporkan komentar ini sebelumnya. Tim kami sedang mereview.",
    });
  }

  const createdCmt = await prisma.feedReport.create({
    data: {
      reporterId: session.sub,
      targetType: "COMMENT",
      commentId: targetId,
      reason: mappedReason,
      detail: [
        `flutter_reason: ${reasonRaw}`,
        note ? `note: ${note}` : null,
      ]
        .filter(Boolean)
        .join("\n"),
    },
    select: { id: true, status: true },
  });

  return NextResponse.json({
    ok: true,
    reportId: createdCmt.id,
    status: createdCmt.status,
    message: "Laporan diterima. Tim moderasi akan mereview.",
  });
}

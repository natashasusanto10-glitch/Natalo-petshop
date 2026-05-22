/**
 * PATCH /api/admin/feed/reports/[id]
 *   Body: { action: "resolve" | "dismiss", note?: string }
 *
 * Admin action terhadap user report:
 * - resolve: report dianggap valid (admin sudah ambil tindakan terpisah
 *   via /api/admin/feed/posts/[id] atau /comments/[id]). Set status =
 *   RESOLVED + resolvedAt + resolvedById.
 * - dismiss: report dianggap tidak valid (no violation). Set status =
 *   DISMISSED + resolvedAt + resolvedById.
 *
 * Note: actual hide/delete dilakukan oleh endpoint moderation lain.
 * Endpoint ini hanya UPDATE STATUS report, supaya admin bisa clear
 * queue.
 *
 * Idempotent — kalau report sudah RESOLVED/DISMISSED, return 200 tanpa
 * mutate (defensive supaya tidak overwrite original resolvedAt).
 */
import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { assertSameOrigin } from "@/lib/csrf";
import { prisma } from "@/lib/prisma";

export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return csrfReject;

  const session = await getSession("ADMIN");
  if (!session || session.role !== "ADMIN") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { id: reportId } = await params;
  if (!reportId) {
    return NextResponse.json({ error: "Report ID required" }, { status: 400 });
  }

  const body = await request.json().catch(() => ({}));
  const action = String((body as { action?: unknown }).action ?? "");

  if (action !== "resolve" && action !== "dismiss") {
    return NextResponse.json(
      { error: "Action harus 'resolve' atau 'dismiss'." },
      { status: 400 },
    );
  }

  const report = await prisma.feedReport.findUnique({
    where: { id: reportId },
    select: { id: true, status: true },
  });
  if (!report) {
    return NextResponse.json({ error: "Report tidak ditemukan." }, { status: 404 });
  }

  // Idempotent — kalau sudah finalized, return current state.
  if (report.status !== "PENDING") {
    return NextResponse.json({
      ok: true,
      report: { id: report.id, status: report.status },
      idempotent: true,
    });
  }

  const updated = await prisma.feedReport.update({
    where: { id: reportId },
    data: {
      status: action === "resolve" ? "RESOLVED" : "DISMISSED",
      resolvedAt: new Date(),
      resolvedById: session.sub,
    },
    select: {
      id: true,
      status: true,
      resolvedAt: true,
      resolvedById: true,
    },
  });

  return NextResponse.json({ ok: true, report: updated });
}

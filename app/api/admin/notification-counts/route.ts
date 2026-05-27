import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";

/**
 * GET /api/admin/notification-counts
 *
 * Aggregate counter untuk badge bottom nav di flutter_admin.
 * Single round-trip biar hemat — dipanggil saat init HomeShell + saat
 * AppLifecycleState.resumed + auto-poll 60s.
 *
 * Returns:
 *   - ordersPending: order PENDING (belum diproses admin)
 *   - cancelRequests: order dgn cancellationRequestStatus = PENDING
 *   - feedPending: feed post status PENDING_REVIEW (non-deleted)
 *   - abuseFlagsOpen: abuse flag status OPEN
 *   - waitingPayment: order pay pending (info tambahan)
 *
 * Semua count parallel via Promise.all supaya cepat.
 */
export async function GET() {
  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const [
    ordersPending,
    cancelRequests,
    waitingPayment,
    feedPending,
    abuseFlagsOpen,
  ] = await Promise.all([
    prisma.order.count({ where: { status: "PENDING" } }),
    prisma.order.count({
      where: { cancellationRequestStatus: "PENDING" },
    }),
    prisma.order.count({
      where: {
        paymentStatus: { in: ["UNPAID", "PENDING"] },
        status: { notIn: ["CANCELLED", "REFUNDED"] },
      },
    }),
    prisma.feedPost.count({
      where: { status: "PENDING_REVIEW", deletedAt: null },
    }),
    prisma.abuseFlag.count({ where: { status: "OPEN" } }),
  ]);

  return NextResponse.json({
    ordersPending,
    cancelRequests,
    waitingPayment,
    feedPending,
    abuseFlagsOpen,
  });
}

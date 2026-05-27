import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { approveCancellationRequest } from "@/app/admin/(protected)/orders/[id]/actions";

/**
 * POST /api/admin/orders/[orderNumber]/cancellation/approve
 *
 * REST wrapper untuk server action `approveCancellationRequest`.
 * Dipakai flutter_admin order detail — admin tap "Setujui Pembatalan"
 * di banner cancellation request.
 *
 * Server action sendiri handle: requireAdmin, mark APPROVED, jalankan
 * markAsCancelled (refund + restore stock + voucher rollback + push),
 * audit log. Endpoint ini cuma resolve orderNumber → orderId lalu
 * delegate.
 */
export async function POST(
  _request: NextRequest,
  { params }: { params: Promise<{ orderNumber: string }> },
) {
  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { orderNumber } = await params;
  const order = await prisma.order.findUnique({
    where: { orderNumber },
    select: { id: true, cancellationRequestStatus: true },
  });
  if (!order) {
    return NextResponse.json(
      { error: "Order tidak ditemukan" },
      { status: 404 },
    );
  }
  if (order.cancellationRequestStatus !== "PENDING") {
    return NextResponse.json(
      { error: "Tidak ada permintaan pembatalan PENDING untuk order ini" },
      { status: 409 },
    );
  }

  try {
    await approveCancellationRequest(order.id);
    return NextResponse.json({ ok: true });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Approve gagal";
    return NextResponse.json({ error: message }, { status: 400 });
  }
}

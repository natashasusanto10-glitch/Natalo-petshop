import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { rejectCancellationRequest } from "@/app/admin/(protected)/orders/[id]/actions";

/**
 * POST /api/admin/orders/[orderNumber]/cancellation/reject
 *
 * Body: `{ rejectReason: string }` — wajib (min 1 char, max 500).
 *
 * Re-use server action `rejectCancellationRequest(orderId, formData)`.
 * Endpoint translate JSON body → FormData supaya signature kompatibel.
 */
export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ orderNumber: string }> },
) {
  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const body = (await request.json().catch(() => null)) as
    | { rejectReason?: string }
    | null;
  const rejectReason = body?.rejectReason?.trim() ?? "";
  if (!rejectReason) {
    return NextResponse.json(
      { error: "Alasan penolakan wajib diisi" },
      { status: 400 },
    );
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

  const formData = new FormData();
  formData.set("rejectReason", rejectReason);

  try {
    await rejectCancellationRequest(order.id, formData);
    return NextResponse.json({ ok: true });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Reject gagal";
    return NextResponse.json({ error: message }, { status: 400 });
  }
}

import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { markItemPartiallyOutOfStock } from "@/app/admin/(protected)/orders/[id]/actions";

/**
 * POST /api/admin/orders/[orderNumber]/items/[itemId]/out-of-stock
 *
 * Tandai sebagian / seluruh qty satu OrderItem sebagai stok kosong.
 * REST wrapper untuk `markItemPartiallyOutOfStock(orderId, formData)`.
 *
 * Body: { missingQty: number (>0, <= item.quantity), adminNote?: string }
 *
 * Auto-flow: create RefundCase + credit ke Saldo Refund + push notif user.
 * Amount auto-calc net-of-voucher (proportional ke productDiscount).
 */
export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ orderNumber: string; itemId: string }> },
) {
  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { orderNumber, itemId } = await params;
  const order = await prisma.order.findUnique({
    where: { orderNumber },
    select: { id: true },
  });
  if (!order) {
    return NextResponse.json(
      { error: "Order tidak ditemukan" },
      { status: 404 },
    );
  }

  const body = (await request.json().catch(() => null)) as
    | { missingQty?: number; adminNote?: string }
    | null;
  if (!body) {
    return NextResponse.json({ error: "Body invalid" }, { status: 400 });
  }

  const formData = new FormData();
  formData.set("itemId", itemId);
  formData.set("missingQty", String(body.missingQty ?? 0));
  if (body.adminNote) formData.set("adminNote", body.adminNote);

  try {
    await markItemPartiallyOutOfStock(order.id, formData);
    return NextResponse.json({ ok: true });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Gagal tandai kosong";
    return NextResponse.json({ error: message }, { status: 400 });
  }
}

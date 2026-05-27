import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { issueRefundToWallet } from "@/app/admin/(protected)/orders/[id]/actions";

/**
 * POST /api/admin/orders/[orderNumber]/refund-wallet
 *
 * Issue refund ke Saldo Refund user. REST wrapper untuk
 * `issueRefundToWallet(orderId, prevState, formData)`.
 *
 * Body: {
 *   amount: number (>0, <= 100jt),
 *   reason: "OUT_OF_STOCK" | "PARTIAL_CANCEL" | "RETURN_APPROVED" | "ORDER_CANCELLED" | "OTHER",
 *   itemId?: string (kosong / null = whole-order refund),
 *   adminNote?: string (max 500 char)
 * }
 *
 * Server action return RefundActionResult ({ok, message, amount?, timestamp?})
 * yang kita teruskan langsung supaya mobile bisa display banner success/error.
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
    | {
        amount?: number;
        reason?: string;
        itemId?: string | null;
        adminNote?: string;
      }
    | null;

  if (!body) {
    return NextResponse.json({ error: "Body invalid" }, { status: 400 });
  }

  const { orderNumber } = await params;
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

  const formData = new FormData();
  formData.set("amount", String(body.amount ?? 0));
  formData.set("reason", String(body.reason ?? ""));
  if (body.itemId) formData.set("itemId", body.itemId);
  if (body.adminNote) formData.set("adminNote", body.adminNote);

  try {
    const result = await issueRefundToWallet(
      order.id,
      { ok: false, message: "" },
      formData,
    );
    if (!result.ok) {
      return NextResponse.json({ error: result.message }, { status: 400 });
    }
    return NextResponse.json({
      ok: true,
      amount: result.amount,
      timestamp: result.timestamp,
      message: result.message,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Refund gagal";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}

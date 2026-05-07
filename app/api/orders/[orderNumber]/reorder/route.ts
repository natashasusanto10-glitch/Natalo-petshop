/**
 * POST /api/orders/[orderNumber]/reorder
 *   - Body kosong: reorder semua item
 *   - Body { itemId: "..." }: reorder satu item saja
 *
 * Hanya validasi & return hasil. Frontend yang merge ke localStorage cart.
 */

import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { validateReorder } from "@/lib/reorder";

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ orderNumber: string }> }
) {
  try {
    const session = await getSession("CUSTOMER");
    if (!session) {
      return NextResponse.json(
        { error: "Silakan login terlebih dahulu." },
        { status: 401 }
      );
    }

    const { orderNumber } = await params;
    const body = await request.json().catch(() => ({}));
    const onlyItemId =
      typeof body.itemId === "string" && body.itemId.length > 0
        ? body.itemId
        : undefined;

    const result = await validateReorder(orderNumber, session.sub, {
      onlyItemId,
    });

    return NextResponse.json(result);
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "Gagal memproses reorder.";
    const status = message.includes("tidak ditemukan") ? 404 : 500;
    return NextResponse.json({ error: message }, { status });
  }
}

import { NextRequest, NextResponse } from "next/server";
import { verifyStaffRequest } from "@/lib/chat/staff-auth";
import { getStaffOrderDetail } from "@/lib/chat/staff-order";

const NO_STORE = { "Cache-Control": "private, no-store" };

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ orderNumber: string }> },
) {
  const auth = await verifyStaffRequest(request);
  if (auth instanceof NextResponse) return auth;
  const { orderNumber } = await params;
  if (!orderNumber || orderNumber.length > 80) {
    return NextResponse.json({ error: "Nomor order tidak valid" }, { status: 400, headers: NO_STORE });
  }
  try {
    const result = await getStaffOrderDetail(orderNumber);
    if (!result) {
      return NextResponse.json({ error: "Order tidak ditemukan" }, { status: 404, headers: NO_STORE });
    }
    console.info(JSON.stringify({ event: "staff_order_opened", orderNumber, staffUid: auth.uid }));
    return NextResponse.json(result, { headers: NO_STORE });
  } catch (error) {
    console.error(JSON.stringify({
      event: "staff_order_open_failed",
      orderNumber,
      error: error instanceof Error ? error.message.slice(0, 300) : "unknown",
    }));
    return NextResponse.json({ error: "Gagal memuat order" }, { status: 500, headers: NO_STORE });
  }
}

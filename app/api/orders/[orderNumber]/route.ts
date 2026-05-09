import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { orderDetailInclude, serializeOrderDetail } from "@/lib/order-detail";

type Params = {
  params: Promise<{ orderNumber: string }>;
};

export async function GET(request: NextRequest, { params }: Params) {
  const { orderNumber } = await params;
  const token = request.nextUrl.searchParams.get("token");
  const session = await getSession("CUSTOMER");

  const order = await prisma.order.findUnique({
    where: { orderNumber },
    include: orderDetailInclude,
  });

  if (!order) {
    return NextResponse.json({ message: "Pesanan tidak ditemukan." }, { status: 404 });
  }

  const isOwner = Boolean(session?.sub && order.userId === session.sub);
  const hasValidToken = Boolean(token && order.trackingToken && token === order.trackingToken);

  if (!isOwner && !hasValidToken) {
    return NextResponse.json(
      { message: "Link pesanan tidak valid atau kamu belum login sebagai pemilik pesanan." },
      { status: 403 }
    );
  }

  return NextResponse.json({ order: serializeOrderDetail(order) });
}

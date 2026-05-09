import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { buildOrderDetailPath, createTrackingToken, isOrderContactMatch } from "@/lib/order-detail";

export async function GET(request: NextRequest) {
  const orderNumber = request.nextUrl.searchParams.get("order");
  const contact = request.nextUrl.searchParams.get("contact")?.trim() || request.nextUrl.searchParams.get("email")?.trim();

  if (!orderNumber || !contact) {
    return NextResponse.json({ message: "Nomor pesanan dan email/nomor HP wajib diisi." }, { status: 400 });
  }

  const order = await prisma.order.findUnique({
    where: { orderNumber },
    select: {
      id: true,
      orderNumber: true,
      customerEmail: true,
      customerPhone: true,
      trackingToken: true,
    },
  });

  if (!order) {
    return NextResponse.json({ message: "Pesanan tidak ditemukan." }, { status: 404 });
  }

  if (!isOrderContactMatch(order, contact)) {
    return NextResponse.json({ message: "Nomor pesanan tidak cocok dengan email atau nomor HP tersebut." }, { status: 404 });
  }

  const trackingToken = order.trackingToken ?? createTrackingToken();
  if (!order.trackingToken) {
    await prisma.order.update({
      where: { id: order.id },
      data: { trackingToken },
    });
  }

  return NextResponse.json({
    detailUrl: buildOrderDetailPath(order.orderNumber, trackingToken),
  });
}

import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { memberOrdersInclude, serializeMemberOrder } from "@/lib/member-orders";

export const dynamic = "force-dynamic";

export async function GET() {
  const session = await getSession("CUSTOMER");
  // getSession("CUSTOMER") sudah accept admin via privilege elevation
  // (lihat lib/auth.ts:64-77). Strict re-check session.role !== CUSTOMER
  // dihapus supaya admin (Natasha) bisa cek pesanan miliknya saat pakai
  // app customer-side.
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const orders = await prisma.order.findMany({
    where: { userId: session.sub },
    orderBy: { createdAt: "desc" },
    take: 50,
    include: memberOrdersInclude,
  });

  return NextResponse.json({
    orders: orders.map(serializeMemberOrder),
  });
}

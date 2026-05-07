/**
 * GET /api/me/reviewable-items
 * Return order items dari order DELIVERED yang BELUM ada review aktifnya.
 */
import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";

export async function GET() {
  const session = await getSession("CUSTOMER");
  if (!session) return NextResponse.json({ error: "Login dulu" }, { status: 401 });

  const items = await prisma.orderItem.findMany({
    where: {
      order: { userId: session.sub, status: "DELIVERED" },
      reviews: { none: { status: { not: "DELETED" } } },
    },
    include: {
      product: { select: { id: true, slug: true, imageUrl: true } },
      order: { select: { orderNumber: true, createdAt: true } },
    },
    orderBy: { order: { createdAt: "desc" } },
  });

  return NextResponse.json({ items });
}

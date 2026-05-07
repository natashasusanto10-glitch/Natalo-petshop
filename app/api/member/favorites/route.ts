import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";

// GET  — list productId yang difavoritkan
export async function GET() {
  const session = await getSession("CUSTOMER");
  if (!session || session.role !== "CUSTOMER") {
    return NextResponse.json([]);
  }

  const favorites = await prisma.favorite.findMany({
    where: { userId: session.sub },
    select: { productId: true },
  });

  return NextResponse.json(favorites.map((f) => f.productId));
}

// POST — tambah favorit { productId }
export async function POST(request: NextRequest) {
  const session = await getSession("CUSTOMER");
  if (!session || session.role !== "CUSTOMER") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { productId } = await request.json();
  if (!productId) return NextResponse.json({ error: "productId required" }, { status: 400 });

  await prisma.favorite.upsert({
    where: { userId_productId: { userId: session.sub, productId } },
    create: { userId: session.sub, productId },
    update: {},
  });

  return NextResponse.json({ ok: true });
}

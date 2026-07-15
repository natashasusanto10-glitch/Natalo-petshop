import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { cleanupWhere, compensateCreatedProduct } from "@/lib/product/admin-product-form";

export const dynamic = "force-dynamic";
export const maxDuration = 60;

function authorized(request: NextRequest): boolean {
  const secret = process.env.CRON_SECRET;
  return Boolean(secret && request.headers.get("authorization") === `Bearer ${secret}`);
}

export async function POST(request: NextRequest) {
  if (!authorized(request)) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  const stale = await prisma.product.findMany({ where: cleanupWhere(), select: { id: true } });
  let cleaned = 0;
  for (const product of stale) {
    if (await compensateCreatedProduct(product.id)) cleaned += 1;
  }
  return NextResponse.json({ cleaned });
}

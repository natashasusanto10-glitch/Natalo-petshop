import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";

export async function POST(
  _request: NextRequest,
  { params }: { params: Promise<{ slug: string }> },
) {
  const [{ slug }, session] = await Promise.all([params, getSession("CUSTOMER").catch(() => null)]);
  const product = await prisma.product.findUnique({
    where: { slug },
    select: { id: true, isActive: true },
  });

  if (!product?.isActive) {
    return NextResponse.json({ ok: false }, { status: 404 });
  }

  if (session?.sub) {
    try {
      await prisma.$executeRaw`
        INSERT INTO "user_product_views" ("id", "user_id", "product_id", "viewed_at", "created_at", "updated_at")
        VALUES (${crypto.randomUUID()}, ${session.sub}, ${product.id}, NOW(), NOW(), NOW())
        ON CONFLICT ("user_id", "product_id")
        DO UPDATE SET "viewed_at" = EXCLUDED."viewed_at", "updated_at" = NOW()
      `;
    } catch {
      return NextResponse.json({ ok: true, productId: product.id, stored: false });
    }
  }

  return NextResponse.json({ ok: true, productId: product.id, stored: Boolean(session?.sub) });
}

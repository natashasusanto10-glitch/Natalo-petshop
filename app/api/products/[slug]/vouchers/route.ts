import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { getProductBySlug } from "@/lib/products";
import { loadVisibleProductVouchers } from "@/lib/product-vouchers";
import { prisma } from "@/lib/prisma";

export async function GET(
  _request: NextRequest,
  { params }: { params: Promise<{ slug: string }> },
) {
  const { slug } = await params;
  const product =
    (await getProductBySlug(slug)) ??
    (await prisma.product.findUnique({ where: { id: slug }, select: { id: true } }));
  if (!product) {
    return NextResponse.json({ vouchers: [] }, { status: 404 });
  }

  const session = await getSession("CUSTOMER");
  const vouchers = await loadVisibleProductVouchers(session?.sub ?? null);

  return NextResponse.json({ vouchers });
}

import { NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";

export async function GET(
  _req: Request,
  { params }: { params: Promise<{ slug: string }> }
) {
  const { slug } = await params;
  const product = await prisma.product.findUnique({
    where: { slug },
    select: { avgRating: true, reviewCount: true, ratingBreakdown: true },
  });
  if (!product) return NextResponse.json({ error: "Not found" }, { status: 404 });

  return NextResponse.json({
    avgRating: product.avgRating,
    reviewCount: product.reviewCount,
    ratingBreakdown: product.ratingBreakdown,
  });
}

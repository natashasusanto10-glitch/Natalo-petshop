import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";
import type { Prisma } from "@prisma/client";

const MAX_LIMIT = 100;
const DEFAULT_LIMIT = 50;

export async function GET(request: NextRequest) {
  const session = await getSession("ADMIN");
  if (!session || session.role !== "ADMIN") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const sp = request.nextUrl.searchParams;
  const page = Math.max(1, parseInt(sp.get("page") || "1", 10));
  const limit = Math.min(
    MAX_LIMIT,
    Math.max(1, parseInt(sp.get("limit") || String(DEFAULT_LIMIT), 10))
  );
  const q = sp.get("q")?.trim() ?? "";
  const categorySlug = sp.get("category")?.trim() ?? "";
  const stockStatus = sp.get("stock_status")?.trim() ?? "";

  const where: Prisma.ProductWhereInput = { hasVariants: false };
  if (q) where.name = { contains: q, mode: "insensitive" };
  if (categorySlug) where.category = { slug: categorySlug };
  if (stockStatus === "empty") where.stock = 0;
  else if (stockStatus === "low") where.stock = { gt: 0, lte: 5 };

  const [products, total] = await Promise.all([
    prisma.product.findMany({
      where,
      orderBy: { createdAt: "desc" },
      skip: (page - 1) * limit,
      take: limit,
      select: {
        id: true,
        name: true,
        price: true,
        stock: true,
        imageUrl: true,
        category: { select: { name: true } },
      },
    }),
    prisma.product.count({ where }),
  ]);

  return NextResponse.json({
    products: products.map((p) => ({
      id: p.id,
      name: p.name,
      price: p.price,
      stock: p.stock,
      imageUrl: p.imageUrl,
      category: p.category?.name ?? "",
    })),
    total,
  });
}

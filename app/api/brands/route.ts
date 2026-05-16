import { NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";

// Cache 5 menit — list brand jarang berubah, beban DB rendah.
// stale-while-revalidate 1 jam supaya update brand admin cepat propagate
// tapi user request setelah window cache pertama tetap dapat versi cached.
export const revalidate = 300;

export async function GET() {
  const brands = await prisma.brand
    .findMany({
      where: {
        isActive: true,
        name: { not: "" },
      },
      orderBy: [{ position: "asc" }, { createdAt: "desc" }, { name: "asc" }],
      select: {
        id: true,
        name: true,
        slug: true,
        logoUrl: true,
        _count: {
          select: { products: { where: { isActive: true } } },
        },
      },
    })
    .catch(() => []);

  return NextResponse.json(
    {
      brands: brands.map((brand) => ({
        id: brand.id,
        name: brand.name,
        slug: brand.slug,
        logoUrl: brand.logoUrl,
        productCount: brand._count.products,
      })),
    },
    {
      headers: {
        "Cache-Control": "public, s-maxage=300, stale-while-revalidate=3600",
      },
    }
  );
}

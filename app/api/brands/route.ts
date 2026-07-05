import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";

// Cache 5 menit — list brand jarang berubah, beban DB rendah.
// stale-while-revalidate 1 jam supaya update brand admin cepat propagate
// tapi user request setelah window cache pertama tetap dapat versi cached.
export const revalidate = 300;

export async function GET(request: NextRequest) {
  // Scope opsional ke kategori aktif — dipakai Filter sheet halaman Produk
  // supaya brand yang tampil hanya brand yang benar-benar jual produk di
  // kategori itu (mis. "Makanan Anjing" tidak menampilkan brand aquarium).
  // Tanpa param ini (call site lama: all_brands_screen.dart, home "Brand
  // Favorit"), perilaku identik dengan sebelumnya — list global.
  const categorySlug = (request.nextUrl.searchParams.get("category") ?? "").trim();

  const brands = await prisma.brand
    .findMany({
      where: {
        isActive: true,
        name: { not: "" },
        ...(categorySlug
          ? {
              products: {
                some: {
                  isActive: true,
                  stock: { gt: 0 },
                  category: { slug: categorySlug },
                },
              },
            }
          : {}),
      },
      orderBy: [{ position: "asc" }, { createdAt: "desc" }, { name: "asc" }],
      select: {
        id: true,
        name: true,
        slug: true,
        logoUrl: true,
        // productCount HARUS cocok dengan apa yang user lihat ketika tap
        // brand → /products. Default filter customer app: isActive=true
        // AND stock>0 (lihat ProductCatalogFilter.inStockOnly default).
        // Tanpa stock filter: brand bisa tampilkan "82 produk" tapi user
        // tap → 0 produk (semuanya stok habis) → confusing UX.
        //
        // Kalau categorySlug ada, count juga di-scope ke kategori itu —
        // harus konsisten dengan where clause di atas.
        _count: {
          select: {
            products: {
              where: {
                isActive: true,
                stock: { gt: 0 },
                ...(categorySlug ? { category: { slug: categorySlug } } : {}),
              },
            },
          },
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

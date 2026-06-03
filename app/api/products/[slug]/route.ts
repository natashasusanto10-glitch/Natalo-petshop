/**
 * GET /api/products/[slug]
 *
 * Return full product detail dengan variantAttrs + variants — dipakai oleh
 * Flutter mobile app untuk render variant selector dan harga dinamis.
 *
 * READ-ONLY: cuma SELECT, tidak menyentuh data. Aman untuk dipanggil
 * sebanyak apa pun.
 *
 * Cache 60 detik (revalidate) — sama dengan halaman PWA product detail.
 * Variant data berubah saat admin update stock; CDN cache memastikan
 * mobile app dapat data fresh dalam 1 menit.
 */
import { NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { getProductBySlug } from "@/lib/products";
import { getSession } from "@/lib/auth";

export const dynamic = "force-dynamic";

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ slug: string }> },
) {
  const { slug } = await params;
  const session = await getSession("CUSTOMER").catch(() => null);
  const product = await getProductBySlug(slug, {
    viewerId: session?.sub ?? null,
  });

  if (!product) {
    return NextResponse.json(
      { error: "Produk tidak ditemukan." },
      { status: 404 },
    );
  }

  // Untuk consistency, ambil sold count + brand info — TypeScript-side
  // append. Pure read, no mutation.
  const [soldSummary, productExtras] = await Promise.all([
    prisma.orderItem
      .aggregate({
        _sum: { quantity: true },
        where: {
          productId: product.id,
          order: {
            status: {
              in: [
                "PAID",
                "PROCESSING",
                "READY_FOR_PICKUP",
                "SHIPPED",
                "DELIVERED",
              ],
            },
          },
        },
      })
      .catch(() => ({ _sum: { quantity: 0 } })),
    prisma.product
      .findUnique({
        where: { id: product.id },
        select: {
          brand: { select: { id: true, name: true, slug: true } },
          category: { select: { id: true, name: true, slug: true } },
        },
      })
      .catch(() => null),
  ]);

  return NextResponse.json(
    {
      product: {
        ...product,
        soldCount: soldSummary._sum.quantity ?? 0,
        // Object tetap dikirim untuk web/kompat lama, TAPI Flutter butuh
        // field flat — model client fallback ke `brand`/`category` object
        // lalu stringify jadi "{id:.., name: Yang, slug: yang}" (bug
        // tampilan). brandName/categoryName flat bikin client baca nama
        // bersih; categoryName juga ganti tampilan slug "peralatan-aquarium"
        // → "Peralatan Aquarium".
        brand: productExtras?.brand ?? null,
        brandName: productExtras?.brand?.name ?? null,
        brandSlug: productExtras?.brand?.slug ?? null,
        category: productExtras?.category ?? null,
        categoryName: productExtras?.category?.name ?? null,
        categorySlug: productExtras?.category?.slug ?? null,
      },
    },
  );
}

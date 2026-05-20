/**
 * GET /api/admin/discounts/promo-toko/eligible-products
 *
 * Query parameters:
 *  - q          : search string (nama produk)
 *  - categoryId : filter by category
 *  - excludeId  : promo yang sedang di-edit (include item-nya)
 *
 * Return produk eligible (TIDAK sedang di Promo Toko aktif/upcoming),
 * include varian-nya jika ada. Variant juga di-mark blocked kalau
 * sudah di promo lain.
 *
 * Refactor untuk schema ProductDiscountItem (per-variant tracking).
 */
import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";

export async function GET(request: NextRequest) {
  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const sp = request.nextUrl.searchParams;
  const q = sp.get("q")?.trim() ?? "";
  const categoryId = sp.get("categoryId")?.trim() ?? "";
  const excludeId = sp.get("excludeId")?.trim() ?? "";

  // Cari semua productId/variantId yang sedang di Promo Toko aktif/upcoming.
  // Exclude promo yang sedang di-edit (excludeId).
  const now = new Date();
  const blockedItems = await prisma.productDiscountItem.findMany({
    where: {
      discount: {
        isActive: true,
        endsAt: { gt: now },
        ...(excludeId ? { id: { not: excludeId } } : {}),
      },
    },
    select: { productId: true, variantId: true },
  });

  // Block keys: productId saja (kalau variantId=null = promo apply ke
  // seluruh produk) atau productId+variantId (kalau apply per varian).
  const blockedProductIds = new Set<string>();
  const blockedVariantKeys = new Set<string>();
  for (const item of blockedItems) {
    if (item.variantId === null) {
      blockedProductIds.add(item.productId);
    } else {
      blockedVariantKeys.add(`${item.productId}::${item.variantId}`);
    }
  }

  const where: {
    isActive: boolean;
    AND?: Array<{ name: { contains: string; mode: "insensitive" } }>;
    categoryId?: string;
    id?: { notIn: string[] };
  } = { isActive: true };
  // Token-based search: split query jadi tokens, semua harus appear di
  // name. Lebih lenient dari single substring match — "adult cat"
  // match "Pro Plan Adult Cat Chicken" karena setiap token ada.
  if (q) {
    const tokens = q
      .split(/\s+/)
      .map((t) => t.trim())
      .filter((t) => t.length >= 1);
    if (tokens.length > 0) {
      where.AND = tokens.map((t) => ({
        name: { contains: t, mode: "insensitive" as const },
      }));
    }
  }
  if (categoryId) where.categoryId = categoryId;
  if (blockedProductIds.size > 0) {
    where.id = { notIn: Array.from(blockedProductIds) };
  }

  const products = await prisma.product.findMany({
    where,
    orderBy: { name: "asc" },
    take: 200,
    select: {
      id: true,
      name: true,
      imageUrl: true,
      price: true,
      stock: true,
      hasVariants: true,
      category: { select: { name: true } },
      variants: {
        where: { deletedAt: null, isActive: true },
        orderBy: { createdAt: "asc" },
        select: {
          id: true,
          sku: true,
          price: true,
          stock: true,
          imageUrl: true,
          options: {
            select: {
              option: { select: { value: true } },
            },
          },
        },
      },
    },
  });

  // Mark blocked variants — kalau produk berVarian, varian individual
  // bisa di-block walaupun produk overall masih eligible.
  const result = products.map((p) => ({
    ...p,
    variants: p.variants.map((v) => ({
      ...v,
      // Variant label dari options.value join " / "
      label:
        v.options.map((o) => o.option.value).join(" / ") || v.sku || "Default",
      isBlocked: blockedVariantKeys.has(`${p.id}::${v.id}`),
      // Strip options dari output (sudah jadi label)
      options: undefined,
    })),
  }));

  return NextResponse.json({ products: result });
}

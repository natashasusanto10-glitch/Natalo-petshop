/**
 * GET /api/admin/debug/check-product-pricing?slug=...
 *
 * Comprehensive debug: tampilkan semua data yang dipakai untuk hitung
 * harga efektif satu produk, beserta hasil mapping yang dikirim ke
 * customer. Pakai untuk diagnose kenapa diskon tidak muncul.
 *
 * Output:
 *   - rawProduct        : data Product mentah dari DB
 *   - discountItems     : ProductDiscountItem yang match (after filter)
 *   - resolvedDiscount  : hasil resolveActiveDiscount()
 *   - mappedOutput      : output dari getProductBySlug() (yang dikirim ke customer)
 *   - serverNow         : server timestamp untuk debug TZ
 */
import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { getProductBySlug } from "@/lib/products";
import { resolveActiveDiscount } from "@/lib/product-pricing";

export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const slug = request.nextUrl.searchParams.get("slug")?.trim();
  if (!slug) {
    return NextResponse.json(
      { error: "Query parameter `slug` required" },
      { status: 400 },
    );
  }

  const now = new Date();

  // Raw product dari DB.
  const rawProduct = await prisma.product.findUnique({
    where: { slug },
    select: {
      id: true,
      name: true,
      slug: true,
      price: true,
      discountPrice: true,
      flashSaleEndsAt: true,
      hasVariants: true,
      isActive: true,
    },
  });
  if (!rawProduct) {
    return NextResponse.json(
      { error: `Product slug "${slug}" not found` },
      { status: 404 },
    );
  }

  // All ProductDiscountItem yang match — pakai filter yang sama dengan
  // customer-side pricing logic (active + within periode).
  const matchedItems = await prisma.productDiscountItem.findMany({
    where: {
      productId: rawProduct.id,
      isItemActive: true,
      discount: {
        isActive: true,
        startsAt: { lte: now },
        endsAt: { gt: now },
      },
    },
    include: {
      discount: {
        select: { id: true, name: true, startsAt: true, endsAt: true },
      },
      variant: { select: { id: true, sku: true } },
    },
  });

  // Test resolveActiveDiscount untuk single product (variantId=null).
  const promoItems = matchedItems
    .filter((it) => it.variantId === null)
    .map((it) => ({
      discountedPrice: it.discountedPrice,
      endsAt: it.discount.endsAt,
    }));
  const resolvedDiscount = resolveActiveDiscount(
    rawProduct.price,
    {
      discountPrice: rawProduct.discountPrice,
      endsAt: rawProduct.flashSaleEndsAt,
    },
    promoItems,
    now,
  );

  // Final mapped output yang dikirim ke customer.
  const mappedOutput = await getProductBySlug(slug);

  return NextResponse.json({
    serverNow: now.toISOString(),
    rawProduct: {
      ...rawProduct,
      flashSaleEndsAt: rawProduct.flashSaleEndsAt?.toISOString() ?? null,
      flashSaleActive:
        rawProduct.flashSaleEndsAt && rawProduct.flashSaleEndsAt > now,
    },
    matchedDiscountItems: matchedItems.map((it) => ({
      promoName: it.discount.name,
      promoId: it.discount.id,
      promoStart: it.discount.startsAt.toISOString(),
      promoEnd: it.discount.endsAt.toISOString(),
      variantId: it.variantId,
      variantSku: it.variant?.sku ?? null,
      discountedPrice: it.discountedPrice,
      isItemActive: it.isItemActive,
    })),
    matchedItemCount: matchedItems.length,
    resolvedDiscount,
    mappedOutput: mappedOutput
      ? {
          price: mappedOutput.price,
          discountPrice: mappedOutput.discountPrice,
          flashSaleEndsAt: mappedOutput.flashSaleEndsAt,
          hasVariants: mappedOutput.hasVariants,
        }
      : null,
    interpretation: buildInterpretation(rawProduct, resolvedDiscount, mappedOutput),
  });
}

function buildInterpretation(
  rawProduct: {
    price: number;
    discountPrice: number | null;
    flashSaleEndsAt: Date | null;
  },
  resolvedDiscount: ReturnType<typeof resolveActiveDiscount>,
  mappedOutput: { price: number; discountPrice: number | null } | null,
): string[] {
  const notes: string[] = [];

  if (rawProduct.flashSaleEndsAt && rawProduct.discountPrice) {
    notes.push(
      `Flash Sale aktif: harga ${rawProduct.price} → ${rawProduct.discountPrice} (sampai ${rawProduct.flashSaleEndsAt.toISOString()})`,
    );
  }

  if (!resolvedDiscount) {
    notes.push(
      "TIDAK ADA diskon aktif. Customer akan lihat harga normal saja.",
    );
  } else {
    notes.push(
      `Diskon resolved: source=${resolvedDiscount.source}, harga efektif=${resolvedDiscount.effectivePrice}`,
    );
  }

  if (mappedOutput) {
    if (
      mappedOutput.discountPrice &&
      mappedOutput.discountPrice < mappedOutput.price
    ) {
      notes.push(
        `Customer akan lihat: HARGA CORET Rp${mappedOutput.price.toLocaleString("id-ID")} → Rp${mappedOutput.discountPrice.toLocaleString("id-ID")}`,
      );
    } else {
      notes.push(
        `Customer TIDAK lihat coret harga (discountPrice=${mappedOutput.discountPrice})`,
      );
    }
  } else {
    notes.push(
      "getProductBySlug return null — produk tidak ditemukan via slug (mungkin cache atau bug)",
    );
  }

  return notes;
}

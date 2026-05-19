import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { getProductBySlug } from "@/lib/products";
import {
  loadPublicProductVoucherPreview,
  loadVisibleProductVouchers,
} from "@/lib/product-vouchers";
import { prisma } from "@/lib/prisma";

export async function GET(
  _request: NextRequest,
  { params }: { params: Promise<{ slug: string }> }
) {
  const { slug } = await params;
  const product =
    (await getProductBySlug(slug)) ??
    (await prisma.product.findUnique({
      where: { id: slug },
      select: {
        id: true,
        price: true,
        categoryId: true,
        category: { select: { slug: true } },
      },
    }));
  if (!product) {
    return NextResponse.json({ vouchers: [] }, { status: 404 });
  }

  const session = await getSession("CUSTOMER");
  const [publicVoucher, memberVouchers] = await Promise.all([
    loadPublicProductVoucherPreview({
      id: product.id,
      price: product.price,
      categoryId: product.categoryId ?? null,
      categorySlug:
        "categorySlug" in product
          ? product.categorySlug ?? null
          : "category" in product
          ? product.category?.slug ?? null
          : null,
    }),
    session ? loadVisibleProductVouchers(session.sub) : Promise.resolve([]),
  ]);

  const vouchers = [
    ...(publicVoucher ? [publicVoucher] : []),
    ...memberVouchers.filter((voucher) => voucher.id !== publicVoucher?.id),
  ];

  return NextResponse.json({ vouchers });
}

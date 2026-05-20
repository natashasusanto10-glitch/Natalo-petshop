import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { getProductBySlug } from "@/lib/products";
import {
  loadPublicProductVoucherPreview,
  loadPublicShippingVoucherPreview,
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
  const previewInput = {
    id: product.id,
    price: product.price,
    categoryId: product.categoryId ?? null,
    categorySlug:
      "categorySlug" in product
        ? product.categorySlug ?? null
        : "category" in product
        ? product.category?.slug ?? null
        : null,
  };
  const [publicVoucher, shippingVoucher, memberVouchers] = await Promise.all([
    loadPublicProductVoucherPreview(previewInput, {
      userId: session?.sub ?? null,
    }),
    loadPublicShippingVoucherPreview(previewInput, {
      userId: session?.sub ?? null,
    }),
    session ? loadVisibleProductVouchers(session.sub) : Promise.resolve([]),
  ]);

  const vouchers = [
    ...(publicVoucher ? [publicVoucher] : []),
    ...(shippingVoucher && shippingVoucher.id !== publicVoucher?.id
      ? [shippingVoucher]
      : []),
    ...memberVouchers.filter(
      (voucher) =>
        voucher.id !== publicVoucher?.id && voucher.id !== shippingVoucher?.id
    ),
  ];

  return NextResponse.json({ vouchers });
}

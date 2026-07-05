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
        brandId: true,
        category: { select: { slug: true } },
      },
    }));
  if (!product) {
    return NextResponse.json({ vouchers: [] }, { status: 404 });
  }

  const session = await getSession("CUSTOMER");
  // brandId WAJIB ikut — tanpa ini voucherMatchesProduct tidak pernah bisa
  // cocokkan voucher scoped-brand (mis. "Happy Dog") lewat endpoint ini,
  // beda dengan /api/products listing yang sudah include brandId.
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
    brandId: product.brandId ?? null,
  };
  const [publicVoucher, shippingVoucher, memberVouchers] = await Promise.all([
    loadPublicProductVoucherPreview(previewInput, {
      userId: session?.sub ?? null,
    }),
    loadPublicShippingVoucherPreview(previewInput, {
      userId: session?.sub ?? null,
    }),
    // previewInput diteruskan supaya voucher scoped (brand/kategori/produk)
    // difilter sesuai produk yang sedang dilihat — root cause fix voucher
    // brand X muncul di halaman produk brand lain.
    session
      ? loadVisibleProductVouchers(session.sub, previewInput)
      : Promise.resolve([]),
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

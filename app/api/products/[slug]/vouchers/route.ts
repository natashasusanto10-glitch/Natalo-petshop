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

  // Brand produk ini sendiri -- dipakai untuk label "Khusus {brand}" di
  // voucher manapun yang match lewat scope brand. Tidak perlu resolve
  // SEMUA eligibleBrandIds voucher (voucher bisa multi-brand) karena di
  // context halaman produk ini, brand yang relevan cuma satu: brand
  // produk yang sedang dilihat.
  const brandName = product.brandId
    ? (
        await prisma.brand.findUnique({
          where: { id: product.brandId },
          select: { name: true },
        })
      )?.name ?? null
    : null;

  const attachBrandName = <T extends { isBrandExclusive?: boolean }>(
    voucher: T
  ) => ({
    ...voucher,
    brandName: voucher.isBrandExclusive ? brandName : null,
  });

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
    ...(publicVoucher ? [attachBrandName(publicVoucher)] : []),
    ...(shippingVoucher && shippingVoucher.id !== publicVoucher?.id
      ? [attachBrandName(shippingVoucher)]
      : []),
    ...memberVouchers
      .filter(
        (voucher) =>
          voucher.id !== publicVoucher?.id && voucher.id !== shippingVoucher?.id
      )
      .map(attachBrandName),
  ];

  return NextResponse.json({ vouchers });
}

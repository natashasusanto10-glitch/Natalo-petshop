import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import {
  cartMatchesVoucherScope,
  voucherHasScope,
  type EligibilityProductInput,
} from "@/lib/voucher-eligibility";

export async function POST(request: NextRequest) {
  const { code, subtotal, productIds } = await request.json();

  if (!code || typeof subtotal !== "number") {
    return NextResponse.json({ valid: false, error: "Data tidak lengkap." }, { status: 400 });
  }

  const voucher = await prisma.voucher.findUnique({ where: { code: String(code).trim().toUpperCase() } });

  if (!voucher) {
    return NextResponse.json({ valid: false, error: "Kode voucher tidak ditemukan." });
  }

  if (!voucher.isActive) {
    return NextResponse.json({ valid: false, error: "Voucher sudah tidak aktif." });
  }

  const now = new Date();
  if (voucher.startsAt > now) {
    return NextResponse.json({ valid: false, error: "Voucher belum berlaku." });
  }

  if (voucher.expiresAt && voucher.expiresAt < now) {
    return NextResponse.json({ valid: false, error: "Voucher sudah kedaluwarsa." });
  }

  if (voucher.maxUsage !== null && voucher.usedCount >= voucher.maxUsage) {
    return NextResponse.json({ valid: false, error: "Voucher sudah mencapai batas penggunaan." });
  }

  if (subtotal < voucher.minimumOrder) {
    return NextResponse.json({
      valid: false,
      error: `Minimum belanja Rp${voucher.minimumOrder.toLocaleString("id-ID")} untuk menggunakan voucher ini.`,
    });
  }

  // Scope gate: kalau client kirim productIds dan voucher di-scope ke
  // brand/kategori/produk, tolak kalau tidak ada produk keranjang yang cocok.
  // Backward-compat: productIds tidak dikirim -> skip (permisif).
  if (Array.isArray(productIds) && voucherHasScope(voucher)) {
    const ids = (productIds as unknown[])
      .map((id) => String(id).trim())
      .filter(Boolean);
    const products = ids.length
      ? await prisma.product.findMany({
          where: { id: { in: ids } },
          select: {
            id: true,
            categoryId: true,
            brandId: true,
            category: { select: { slug: true } },
          },
        })
      : [];
    const cartProducts: EligibilityProductInput[] = products.map((p) => ({
      id: p.id,
      categoryId: p.categoryId ?? null,
      categorySlug: p.category?.slug ?? null,
      brandId: p.brandId ?? null,
    }));
    if (!cartMatchesVoucherScope(voucher, cartProducts)) {
      return NextResponse.json({
        valid: false,
        error: "Voucher tidak berlaku untuk produk di keranjang",
      });
    }
  }

  let discount = 0;
  if (voucher.discountPercent) discount += Math.floor((subtotal * voucher.discountPercent) / 100);
  if (voucher.discountAmount) discount += voucher.discountAmount;
  discount = Math.min(discount, subtotal);

  const parts: string[] = [];
  if (voucher.discountPercent) parts.push(`${voucher.discountPercent}%`);
  if (voucher.discountAmount) parts.push(`Rp${voucher.discountAmount.toLocaleString("id-ID")}`);

  return NextResponse.json({
    valid: true,
    discount,
    description: voucher.description || `Diskon ${parts.join(" + ")}`,
    code: voucher.code,
  });
}

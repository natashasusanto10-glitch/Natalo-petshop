/**
 * GET /api/cart/vouchers?subtotal=N&productIds=id1,id2,id3
 *
 * Return daftar voucher member Natalo (sourceType=CUSTOMER) untuk user
 * login + cart subtotal saat ini.
 *
 * `productIds` (opsional, comma-separated): id produk yang ADA di cart
 * saat ini. Kalau diberikan (termasuk string kosong = cart kosong),
 * voucher yang scoped ke produk/kategori/brand tertentu di-gate
 * `applicable=false` kalau tidak ada satupun productIds yang cocok --
 * lihat lib/voucher-list.ts untuk detail bug yang diperbaiki param ini.
 * Kalau parameter ini TIDAK dikirim sama sekali (app lama yang belum
 * update), behavior lama tetap jalan (permissive, tidak gate scope).
 *
 * Logic visibility ada di `lib/voucher-list.ts` (single source of truth).
 *
 * Response shape:
 *   { available: VoucherListItem[], unavailable: VoucherListItem[] }
 *
 * Guest dapat 401 — tidak boleh lihat voucher member.
 *
 * SELLER_MANUAL voucher TIDAK pernah muncul di endpoint ini (rahasia,
 * harus di-validate via /api/cart/vouchers/validate-private).
 */
import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { listUserVouchers } from "@/lib/voucher-list";
import { prisma } from "@/lib/prisma";
import type { EligibilityProductInput } from "@/lib/voucher-eligibility";

export async function GET(request: NextRequest) {
  const session = await getSession("CUSTOMER");
  if (!session) {
    return NextResponse.json(
      {
        error: "LOGIN_REQUIRED",
        message: "Login dulu untuk melihat voucher member.",
      },
      { status: 401 },
    );
  }

  const subtotalRaw = request.nextUrl.searchParams.get("subtotal");
  const subtotal = Math.max(0, parseInt(subtotalRaw ?? "0", 10) || 0);

  const productIdsRaw = request.nextUrl.searchParams.get("productIds");
  let cartProducts: EligibilityProductInput[] | undefined;
  if (productIdsRaw !== null) {
    const ids = productIdsRaw
      .split(",")
      .map((id) => id.trim())
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
    cartProducts = products.map((p) => ({
      id: p.id,
      categoryId: p.categoryId ?? null,
      categorySlug: p.category?.slug ?? null,
      brandId: p.brandId ?? null,
    }));
  }

  const { items } = await listUserVouchers({
    userId: session.sub,
    subtotal,
    cartProducts,
  });

  return NextResponse.json({
    available: items.filter((it) => it.applicable),
    unavailable: items.filter((it) => !it.applicable),
  });
}

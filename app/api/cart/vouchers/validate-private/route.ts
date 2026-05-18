/**
 * POST /api/cart/vouchers/validate-private
 *
 * Body: { code: string, subtotal: number }
 *
 * Validasi kode voucher SELLER_MANUAL (rahasia dari penjual). Kode harus
 * sourceType=SELLER_MANUAL — kalau user input kode CUSTOMER di sini, tolak
 * dgn pesan menjelaskan harus pilih lewat daftar voucher member.
 *
 * Wajib login. Guest tidak boleh memakai voucher apapun.
 */
import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { calcVoucherDiscount, voucherTypeOf } from "@/lib/voucher-helpers";

const bodySchema = z.object({
  code: z.string().trim().min(1),
  subtotal: z.number().int().nonnegative(),
});

export async function POST(request: NextRequest) {
  const session = await getSession("CUSTOMER");
  if (!session) {
    return NextResponse.json(
      {
        ok: false,
        error: "LOGIN_REQUIRED",
        message: "Login dulu untuk menggunakan voucher.",
      },
      { status: 401 },
    );
  }

  const json = await request.json().catch(() => null);
  const parsed = bodySchema.safeParse(json);
  if (!parsed.success) {
    return NextResponse.json(
      { ok: false, message: "Body tidak valid." },
      { status: 400 },
    );
  }

  const { code, subtotal } = parsed.data;
  const upperCode = code.trim().toUpperCase();
  const voucher = await prisma.voucher.findUnique({ where: { code: upperCode } });

  if (!voucher || !voucher.isActive) {
    return NextResponse.json({ ok: false, message: "Kode voucher tidak valid" });
  }

  if (
    voucher.sourceType !== "SELLER_MANUAL" ||
    voucherTypeOf(voucher) !== "PRIVATE_MANUAL_CODE"
  ) {
    return NextResponse.json({
      ok: false,
      message: "Kode voucher tidak valid atau tidak tersedia untuk akun ini",
    });
  }
  if (
    voucher.eligibleUserIds.length > 0 &&
    !voucher.eligibleUserIds.includes(session.sub)
  ) {
    return NextResponse.json({
      ok: false,
      message: "Kode voucher ini tidak tersedia untuk akun kamu",
    });
  }

  const now = new Date();
  if (voucher.expiresAt && voucher.expiresAt <= now) {
    return NextResponse.json({ ok: false, message: "Kode voucher sudah berakhir" });
  }
  if (voucher.startsAt > now) {
    return NextResponse.json({ ok: false, message: "Voucher belum berlaku" });
  }
  if (voucher.maxUsage !== null && voucher.usedCount >= voucher.maxUsage) {
    return NextResponse.json({
      ok: false,
      message: "Voucher sudah mencapai batas penggunaan",
    });
  }

  // Cek apakah user sudah pernah pakai kode private ini (di order
  // sebelumnya, slot manual ATAU customer). Batasnya mengikuti setting admin
  // `usageLimitPerUser`, default 1x per akun.
  const userUsedOrders = await prisma.order.findMany({
    where: {
      userId: session.sub,
      OR: [
        { voucherCode: upperCode },
        { productVoucherCode: upperCode },
        { shippingVoucherCode: upperCode },
        { loyaltyVoucherCode: upperCode },
        { manualVoucherCode: upperCode },
      ],
    },
    select: {
      createdAt: true,
      voucherCode: true,
      productVoucherCode: true,
      shippingVoucherCode: true,
      loyaltyVoucherCode: true,
      manualVoucherCode: true,
    },
  });
  if (isVoucherUsageLimitReached(voucher, userUsedOrders, now)) {
    return NextResponse.json({
      ok: false,
      message: "Kode voucher sudah pernah digunakan",
    });
  }

  if (subtotal < voucher.minimumOrder) {
    return NextResponse.json({
      ok: false,
      message: "Voucher tidak berlaku untuk pesanan ini",
    });
  }

  const discount = calcVoucherDiscount(subtotal, voucher);
  if (discount <= 0) {
    return NextResponse.json({
      ok: false,
      message: "Voucher tidak memberikan potongan untuk pesanan ini",
    });
  }

  return NextResponse.json({
    ok: true,
    voucher: {
      code: voucher.code,
      description: voucher.description ?? `Hemat ${discount}`,
      discount,
      minimumOrder: voucher.minimumOrder,
      expiresAt: voucher.expiresAt,
      sourceType: voucher.sourceType,
      type: voucher.type,
      visibility: voucher.visibility,
      discountScope: voucher.discountScope,
    },
  });
}

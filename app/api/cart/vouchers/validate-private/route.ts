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
import { calcVoucherDiscount } from "@/lib/voucher-helpers";

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

  if (voucher.sourceType !== "SELLER_MANUAL") {
    return NextResponse.json({
      ok: false,
      message:
        "Kode ini bukan voucher manual penjual. Pilih lewat daftar voucher member.",
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
    },
  });
}

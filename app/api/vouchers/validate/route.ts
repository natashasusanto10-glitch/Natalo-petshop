import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";

export async function POST(request: NextRequest) {
  const { code, subtotal } = await request.json();

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

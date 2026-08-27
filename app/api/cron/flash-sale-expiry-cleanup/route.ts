/**
 * GET /api/cron/flash-sale-expiry-cleanup — Vercel cron (tiap jam)
 *
 * Kosongkan `Product.discountPrice` untuk produk yang Flash Sale-nya sudah
 * lewat waktu. Lihat lib/product/flash-sale-expiry.ts untuk alasan lengkap
 * kenapa sisa ini berbahaya (bom waktu harga di halaman "Buat Flash Sale")
 * dan kenapa `flashSaleEndsAt` sengaja TIDAK ikut dikosongkan.
 *
 * Ini melengkapi POST /api/admin/flash-sale/end, yang sudah membersihkan
 * kedua kolom saat promo diakhiri manual. Yang belum tertutup sebelum ini
 * cuma jalur "dibiarkan habis sendiri" — dan justru itu jalur yang paling
 * sering dipakai.
 *
 * Aman dijalankan berulang: setelah `discountPrice` jadi null, produk yang
 * sama tidak lagi cocok dengan `expiredFlashSaleWhere()`.
 */
import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { expiredFlashSaleWhere } from "@/lib/product/flash-sale-expiry";

export const dynamic = "force-dynamic";
export const maxDuration = 60;

export async function GET(request: NextRequest) {
  // Vercel meng-inject header Authorization: Bearer $CRON_SECRET pada
  // pemanggilan cron — pola sama dengan cron route lain di repo ini.
  const cronSecret = process.env.CRON_SECRET;
  if (!cronSecret || request.headers.get("authorization") !== `Bearer ${cronSecret}`) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const where = expiredFlashSaleWhere();

  // Diambil dulu supaya yang dibersihkan tercatat di log fungsi Vercel —
  // ini menulis ke harga produk, jadi jejaknya harus bisa ditelusuri.
  const stale = await prisma.product.findMany({
    where,
    select: { id: true, name: true, price: true, discountPrice: true, flashSaleEndsAt: true },
  });

  if (stale.length === 0) return NextResponse.json({ found: 0, cleared: 0 });

  for (const p of stale) {
    console.log(
      `[flash-sale-expiry-cleanup] ${p.id} ${p.name}: buang discountPrice ${p.discountPrice} (harga ${p.price}, berakhir ${p.flashSaleEndsAt?.toISOString() ?? "tanpa tanggal"})`,
    );
  }

  const { count } = await prisma.product.updateMany({
    where,
    data: { discountPrice: null },
  });

  // Search index menyimpan harga efektif — biarkan tersinkron ulang, tapi
  // jangan sampai kegagalannya membatalkan pembersihan yang sudah terjadi.
  try {
    const { syncProduct } = await import("@/lib/search");
    for (const p of stale) await syncProduct(p.id).catch(() => {});
  } catch (error) {
    console.error("[flash-sale-expiry-cleanup] sync index gagal", error);
  }

  return NextResponse.json({
    found: stale.length,
    cleared: count,
    products: stale.map((p) => ({ id: p.id, name: p.name, discountPrice: p.discountPrice })),
  });
}

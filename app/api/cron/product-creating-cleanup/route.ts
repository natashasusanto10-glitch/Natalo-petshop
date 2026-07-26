/**
 * GET /api/cron/product-creating-cleanup — Vercel cron (hourly)
 *
 * Bersihkan produk yang stuck di creationState "creating" lebih dari 1 jam
 * (video upload gagal difinalisasi — browser ditutup/koneksi putus sebelum
 * POST /api/admin/products/[id]/finalize sempat jalan).
 *
 * Kenapa ini WAJIB ada: produk begini invisible di SEMUA tab
 * /admin/products (all/ready/out/archived) karena productIsVisibleWhere()
 * mensyaratkan creationState:"ready" tanpa pengecualian — admin tidak
 * punya cara menemukannya lewat UI. Tapi baris + variant + SKU-nya tetap
 * ada di DB, mengunci SKU tersebut selamanya (@unique di level DB).
 * Insiden nyata: produk "Whiskas Creamy Treats..." (2026-07-26) mengunci
 * SKU WHC_S/WHC_CL/WHC_TS/WHC_M/WHC_KS selama berjam-jam sampai
 * dibersihkan manual, karena route ini ada tapi TIDAK PERNAH didaftarkan
 * ke vercel.json crons — logic sudah ditulis, cuma tidak pernah dipicu.
 *
 * cleanupWhere() + compensateCreatedProduct() reuse dari
 * lib/product/admin-product-form.ts — sama persis dengan yang dipanggil
 * POST /api/admin/products/[id]/compensate (rollback saat create gagal),
 * jadi tidak ada logic baru: cuma menyalakan jadwal otomatisnya.
 */
import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { cleanupWhere, compensateCreatedProduct } from "@/lib/product/admin-product-form";

export const dynamic = "force-dynamic";
export const maxDuration = 60;

export async function GET(request: NextRequest) {
  // Vercel auto-injects header Authorization: Bearer $CRON_SECRET pada
  // cron invocation — pola sama dengan cron route lain di repo ini
  // (lihat app/api/cron/abandoned-cart/route.ts).
  const cronSecret = process.env.CRON_SECRET;
  if (!cronSecret || request.headers.get("authorization") !== `Bearer ${cronSecret}`) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const stale = await prisma.product.findMany({ where: cleanupWhere(), select: { id: true, name: true } });
  let cleaned = 0;
  const failed: string[] = [];
  for (const product of stale) {
    try {
      if (await compensateCreatedProduct(product.id)) cleaned += 1;
    } catch (error) {
      console.error(`[product-creating-cleanup] gagal bersihkan ${product.id} (${product.name})`, error);
      failed.push(product.id);
    }
  }
  return NextResponse.json({ found: stale.length, cleaned, failed });
}

import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import {
  LOW_STOCK_LIMIT,
  productStockWhere,
  variantStockWhere,
} from "@/lib/admin/stock-filters";

/**
 * GET /api/admin/dashboard-stats
 *
 * Stats untuk dashboard admin app (flutter_admin/ + web admin dashboard).
 *
 * Returns:
 * - `ordersToday` — count Order yang createdAt hari ini (timezone Asia/Jakarta)
 * - `omzetToday` — sum total dari Order PAID hari ini
 * - `pendingShipment` — count Order status=PAID atau PROCESSING (perlu dikirim)
 * - `lowStockCount` — jumlah item yang perlu di-restock: produk TANPA varian
 *   dengan stok <= 5, DITAMBAH varian aktif dengan stok <= 5.
 *
 *   Dulu ini menghitung `Product.stock <= 5` polos. Stok induk produk
 *   bervarian selalu 0 (form admin menulis 0 saat produk punya varian), jadi
 *   SETIAP produk bervarian ikut terhitung "menipis" — alarm palsu permanen di
 *   aplikasi admin. Bentuk responsnya tidak berubah, hanya angkanya jadi jujur.
 *
 * Dihitung di server-side dengan Prisma aggregations supaya cepat & akurat.
 */
export async function GET() {
  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json(
      { error: "Unauthorized — admin session required" },
      { status: 401 },
    );
  }

  // Asia/Jakarta = UTC+7. Hari ini = window 00:00–24:00 Jakarta time.
  // Untuk simplicity, kita pakai UTC offset langsung (tidak handle DST karena
  // Indonesia tidak ada DST).
  const now = new Date();
  const jakartaOffsetMs = 7 * 60 * 60 * 1000;
  const jakartaNow = new Date(now.getTime() + jakartaOffsetMs);
  const startOfDayJakarta = new Date(
    Date.UTC(
      jakartaNow.getUTCFullYear(),
      jakartaNow.getUTCMonth(),
      jakartaNow.getUTCDate(),
    ) -
      jakartaOffsetMs,
  );
  const endOfDayJakarta = new Date(
    startOfDayJakarta.getTime() + 24 * 60 * 60 * 1000,
  );

  const [
    ordersTodayCount,
    omzetTodayAgg,
    pendingShipCount,
    lowStockProductCount,
    lowStockVariantCount,
  ] = await Promise.all([
      prisma.order.count({
        where: {
          createdAt: { gte: startOfDayJakarta, lt: endOfDayJakarta },
        },
      }),
      prisma.order.aggregate({
        where: {
          createdAt: { gte: startOfDayJakarta, lt: endOfDayJakarta },
          status: { in: ["PAID", "PROCESSING", "SHIPPED", "DELIVERED"] },
        },
        _sum: { total: true },
      }),
      prisma.order.count({
        where: {
          status: { in: ["PAID", "PROCESSING"] },
        },
      }),
      // Produk TANPA varian yang stoknya menipis/habis. Produk bervarian
      // sengaja tidak diukur lewat stok induknya — nilainya selalu 0, jadi
      // dulu SETIAP produk bervarian ikut terhitung "menipis" dan angka ini
      // jadi alarm palsu permanen di aplikasi admin.
      prisma.product.count({
        where: { ...productStockWhere("semua"), stock: { lte: LOW_STOCK_LIMIT } },
      }),
      // Varian yang benar-benar menipis dihitung terpisah lalu dijumlahkan,
      // supaya sinyal aslinya tidak ikut hilang saat alarm palsunya dibuang.
      prisma.productVariant.count({
        where: { ...variantStockWhere("semua"), stock: { lte: LOW_STOCK_LIMIT } },
      }),
    ]);

  return NextResponse.json({
    ordersToday: ordersTodayCount,
    omzetToday: omzetTodayAgg._sum.total ?? 0,
    pendingShipment: pendingShipCount,
    // Dua himpunan yang saling lepas (produk tanpa varian vs varian), jadi
    // penjumlahannya tidak menghitung apa pun dua kali.
    lowStockCount: lowStockProductCount + lowStockVariantCount,
  });
}

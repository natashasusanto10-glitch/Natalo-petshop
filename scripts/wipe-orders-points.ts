/**
 * Hapus seluruh data Order + CustomerPoint (loyalty points). Dipakai
 * untuk bersihkan dummy data testing tanpa menghapus produk/user.
 *
 * Tabel yg dihapus (urut FK):
 *   1. Order        → cascade ke OrderItem → Review → ReviewImage/Reply/Vote
 *   2. CustomerPoint
 *
 * Tidak menyentuh: User, Address, Pet, Favorite, CartItem, Product,
 *                  Category, Brand, Voucher.
 *
 * Cara pakai:
 *   CONFIRM_WIPE=YES npx dotenv -e .env -- tsx scripts/wipe-orders-points.ts
 *
 *   atau via npm:
 *   CONFIRM_WIPE=YES npm run db:wipe-orders-points:prod
 *
 * Tanpa CONFIRM_WIPE=YES script akan refuse berjalan.
 */

import { PrismaClient } from "@prisma/client";

const prisma = new PrismaClient();

async function main() {
  if (process.env.CONFIRM_WIPE !== "YES") {
    console.error(
      "\n❌ Refused. Set CONFIRM_WIPE=YES untuk konfirmasi.\n",
    );
    process.exit(1);
  }

  const dbUrl = process.env.DATABASE_URL ?? "";
  const host = dbUrl.replace(/^postgres(?:ql)?:\/\/[^@]+@/, "").split("/")[0] || "(unknown)";
  console.log(`\n⚠ TARGET DB host: ${host}`);
  console.log("   Mulai wipe dalam 5 detik. Tekan Ctrl+C untuk batal.\n");
  await new Promise((r) => setTimeout(r, 5000));

  const [ordersBefore, pointsBefore] = await Promise.all([
    prisma.order.count(),
    prisma.customerPoint.count(),
  ]);

  console.log("Sebelum wipe:");
  console.log(`  Order:          ${ordersBefore}`);
  console.log(`  CustomerPoint:  ${pointsBefore}\n`);

  console.log("→ Hapus semua Order...");
  const ordersDeleted = await prisma.order.deleteMany({});
  console.log(`  ✓ ${ordersDeleted.count} order dihapus (cascade ke OrderItem & Review)`);

  console.log("→ Hapus semua CustomerPoint...");
  const pointsDeleted = await prisma.customerPoint.deleteMany({});
  console.log(`  ✓ ${pointsDeleted.count} loyalty points dihapus`);

  const [ordersAfter, pointsAfter] = await Promise.all([
    prisma.order.count(),
    prisma.customerPoint.count(),
  ]);

  console.log("\nSesudah wipe:");
  console.log(`  Order:          ${ordersAfter}`);
  console.log(`  CustomerPoint:  ${pointsAfter}`);

  if (ordersAfter > 0 || pointsAfter > 0) {
    console.warn("\n⚠ Masih ada sisa data.");
  } else {
    console.log("\n✅ Order & loyalty points bersih.");
  }
}

main()
  .catch((err) => {
    console.error("\n❌ Wipe gagal:", err);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });

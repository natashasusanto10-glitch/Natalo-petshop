/**
 * Hapus permanen seluruh data katalog dari database (FULL NUCLEAR).
 *
 * Tabel yg dihapus (urut FK):
 *   1. Order      → cascade ke OrderItem → Review → ReviewImage/Reply/Vote
 *   2. CartItem
 *   3. Favorite (otomatis cascade saat Product dihapus, tapi kita bersihkan
 *      eksplisit untuk safety kalau ada orphan)
 *   4. Product    → cascade ke ProductVariant → ProductVariantOption,
 *                   VariantAttribute → VariantOption, Favorite, Review
 *   5. Category, Brand
 *
 * Cara pakai:
 *   1. Pastikan .env.local punya DATABASE_URL yg menunjuk DB target
 *      (production / staging / local — sesuai yg mau di-wipe).
 *   2. Jalankan dengan flag konfirmasi:
 *
 *        CONFIRM_WIPE=YES npx dotenv -e .env.local -- tsx scripts/wipe-products.ts
 *
 *      atau via npm:
 *
 *        npm run db:wipe-products
 *
 *      Tanpa CONFIRM_WIPE=YES script akan refuse berjalan.
 *
 * Script ini bypass route handler /api/admin/products/reset supaya tidak
 * kena timeout serverless Vercel (60s limit). Koneksi langsung Prisma →
 * Postgres bisa selama yg dibutuhkan.
 */

import { PrismaClient } from "@prisma/client";

const prisma = new PrismaClient();

async function main() {
  if (process.env.CONFIRM_WIPE !== "YES") {
    console.error(
      "\n❌ Refused. Set CONFIRM_WIPE=YES untuk konfirmasi.\n" +
        '   Contoh: CONFIRM_WIPE=YES npx dotenv -e .env.local -- tsx scripts/wipe-products.ts\n',
    );
    process.exit(1);
  }

  const dbUrl = process.env.DATABASE_URL ?? "";
  // Tampilkan host saja supaya user lihat target DB tanpa expose password.
  const host = dbUrl.replace(/^postgres(?:ql)?:\/\/[^@]+@/, "").split("/")[0] || "(unknown)";
  console.log(`\n⚠ TARGET DB host: ${host}`);
  console.log("   Mulai wipe dalam 5 detik. Tekan Ctrl+C untuk batal.\n");
  await new Promise((r) => setTimeout(r, 5000));

  // ── Snapshot count sebelum ───────────────────────────────────
  const [productsBefore, ordersBefore, categoriesBefore, brandsBefore, cartBefore] =
    await Promise.all([
      prisma.product.count(),
      prisma.order.count(),
      prisma.category.count(),
      prisma.brand.count(),
      prisma.cartItem.count(),
    ]);

  console.log("Sebelum wipe:");
  console.log(`  Produk:    ${productsBefore}`);
  console.log(`  Order:     ${ordersBefore}`);
  console.log(`  Kategori:  ${categoriesBefore}`);
  console.log(`  Brand:     ${brandsBefore}`);
  console.log(`  CartItem:  ${cartBefore}\n`);

  // ── 1. Hapus semua Order (cascade ke OrderItem, Review, dll) ─
  console.log("→ Hapus semua Order...");
  const ordersDeleted = await prisma.order.deleteMany({});
  console.log(`  ✓ ${ordersDeleted.count} order dihapus (cascade ke OrderItem & Review)`);

  // ── 2. Hapus semua CartItem ──────────────────────────────────
  console.log("→ Hapus semua CartItem...");
  const cartDeleted = await prisma.cartItem.deleteMany({});
  console.log(`  ✓ ${cartDeleted.count} cart item dihapus`);

  // ── 3. Hapus semua Favorite (untuk amannya — Product cascade
  //       juga akan hapus, tapi eksplisit dulu) ───────────────
  console.log("→ Hapus semua Favorite...");
  const favoritesDeleted = await prisma.favorite.deleteMany({});
  console.log(`  ✓ ${favoritesDeleted.count} favorite dihapus`);

  // ── 4. Hapus semua Product (cascade ke variant, review, dll) ─
  console.log("→ Hapus semua Product...");
  const productsDeleted = await prisma.product.deleteMany({});
  console.log(`  ✓ ${productsDeleted.count} produk dihapus (cascade ke Variant & VariantAttribute)`);

  // ── 5. Hapus semua Category & Brand ──────────────────────────
  console.log("→ Hapus semua Category & Brand...");
  const categoriesDeleted = await prisma.category.deleteMany({});
  const brandsDeleted = await prisma.brand.deleteMany({});
  console.log(`  ✓ ${categoriesDeleted.count} kategori, ${brandsDeleted.count} brand dihapus`);

  // ── Verifikasi sisa ──────────────────────────────────────────
  const [productsAfter, ordersAfter, categoriesAfter, brandsAfter, cartAfter] =
    await Promise.all([
      prisma.product.count(),
      prisma.order.count(),
      prisma.category.count(),
      prisma.brand.count(),
      prisma.cartItem.count(),
    ]);

  console.log("\nSesudah wipe:");
  console.log(`  Produk:    ${productsAfter}`);
  console.log(`  Order:     ${ordersAfter}`);
  console.log(`  Kategori:  ${categoriesAfter}`);
  console.log(`  Brand:     ${brandsAfter}`);
  console.log(`  CartItem:  ${cartAfter}`);

  if (
    productsAfter > 0 ||
    ordersAfter > 0 ||
    categoriesAfter > 0 ||
    brandsAfter > 0 ||
    cartAfter > 0
  ) {
    console.warn("\n⚠ Masih ada sisa data. Cek FK constraint atau row yg gagal dihapus.");
  } else {
    console.log("\n✅ DB bersih. Buka /admin/products/import → klik Mulai Import untuk isi ulang.");
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

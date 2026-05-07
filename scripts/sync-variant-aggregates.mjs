/**
 * Backfill: sinkronisasi field aggregate di tabel Product berdasarkan variant aktif.
 *
 * Untuk setiap produk dengan hasVariants=true:
 *   - Product.price       = MIN(variant.price)        — harga termurah
 *   - Product.stock       = SUM(variant.stock)        — total stok semua varian
 *   - Product.weightGram  = berat varian termurah     — berat default
 *   - Product.discountPrice = null                    — clear (varian sudah punya harga sendiri)
 *
 * Cara pakai:
 *   node scripts/sync-variant-aggregates.mjs            (eksekusi)
 *   node scripts/sync-variant-aggregates.mjs --dry-run  (preview, tanpa nulis ke DB)
 *
 * Aman dijalankan kapan saja & berkali-kali (idempotent).
 */

import { createRequire } from "module";

const require = createRequire(import.meta.url);
const { PrismaClient } = require("@prisma/client");
const prisma = new PrismaClient();

const DRY_RUN = process.argv.includes("--dry-run");

async function main() {
  console.log("=".repeat(60));
  console.log("  Sync Product Aggregates dari Variant");
  console.log("=".repeat(60));
  if (DRY_RUN) console.log("🔍 DRY RUN — tidak ada yang ditulis ke database\n");

  // Ambil semua produk yang punya varian
  const products = await prisma.product.findMany({
    where: { hasVariants: true },
    include: {
      variants: {
        where: { deletedAt: null, isActive: true },
        select: { price: true, stock: true, weightGram: true },
      },
    },
  });

  console.log(`📦 ${products.length} produk dengan hasVariants=true ditemukan\n`);

  let synced = 0;
  let skippedNoVariant = 0;
  let unchanged = 0;
  const changes = [];

  for (const p of products) {
    if (p.variants.length === 0) {
      skippedNoVariant++;
      continue;
    }

    const prices = p.variants.map((v) => v.price);
    const minPrice = Math.min(...prices);
    const cheapest = p.variants.find((v) => v.price === minPrice);
    const totalStock = p.variants.reduce((s, v) => s + v.stock, 0);

    const newData = {
      price: minPrice,
      stock: totalStock,
      weightGram: cheapest.weightGram,
      discountPrice: null,
    };

    // Cek apakah ada perubahan
    const isChanged =
      p.price !== newData.price ||
      p.stock !== newData.stock ||
      p.weightGram !== newData.weightGram ||
      p.discountPrice !== null;

    if (!isChanged) {
      unchanged++;
      continue;
    }

    changes.push({
      id: p.id,
      name: p.name.slice(0, 50),
      variants: p.variants.length,
      old: { price: p.price, stock: p.stock, weightGram: p.weightGram, discountPrice: p.discountPrice },
      new: newData,
    });

    if (!DRY_RUN) {
      await prisma.product.update({ where: { id: p.id }, data: newData });
    }
    synced++;
  }

  // ── Print hasil ──────────────────────────────────────────────
  if (changes.length > 0) {
    console.log("Perubahan yang dilakukan:");
    console.log("─".repeat(60));
    for (const c of changes.slice(0, 20)) {
      console.log(`📝 ${c.name} (${c.variants} varian)`);
      console.log(
        `   harga  : ${c.old.price.toLocaleString("id-ID")} → ${c.new.price.toLocaleString("id-ID")}`
      );
      console.log(`   stok   : ${c.old.stock} → ${c.new.stock}`);
      console.log(`   berat  : ${c.old.weightGram}g → ${c.new.weightGram}g`);
    }
    if (changes.length > 20) {
      console.log(`   ... dan ${changes.length - 20} produk lainnya`);
    }
    console.log("");
  }

  console.log("=".repeat(60));
  console.log(`✅ Di-sync         : ${synced}`);
  console.log(`⏭️  Tidak berubah   : ${unchanged}`);
  if (skippedNoVariant > 0) {
    console.log(`⚠️  Tanpa varian aktif : ${skippedNoVariant} (hasVariants=true tapi tidak ada varian aktif)`);
  }
  console.log("=".repeat(60));

  if (skippedNoVariant > 0) {
    console.log("\n💡 Tip: produk dengan hasVariants=true tanpa varian aktif");
    console.log("    sebaiknya di-set hasVariants=false atau tambahkan variant aktif.");
  }
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());

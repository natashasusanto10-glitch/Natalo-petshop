/**
 * Backfill kolom Product.searchText untuk semua produk yang sudah ada.
 * Jalankan sekali setelah migration product_search_text_trgm di-deploy.
 *
 * searchText = name + brand + category + variant names + sku codes (lowercase).
 * Dipakai DB-fallback search dengan pg_trgm GIN index.
 *
 * Cara pakai:
 *   npm run search:backfill-text       # local (.env.local)
 *   npm run search:backfill-text:prod  # production (.env)
 */

import { createRequire } from "module";
import { buildProductSearchText } from "../lib/search-document.mjs";

const require = createRequire(import.meta.url);
const { PrismaClient } = require("@prisma/client");

const prisma = new PrismaClient();
const BATCH = 200;

async function main() {
  const dbUrl = process.env.DATABASE_URL ?? "";
  const host =
    dbUrl.replace(/^postgres(?:ql)?:\/\/[^@]+@/, "").split("/")[0] ?? "(unknown)";
  console.log(`Target DB host: ${host}`);

  const total = await prisma.product.count();
  console.log(`Total produk: ${total}\n`);

  let processed = 0;
  let updated = 0;
  let skipped = 0;
  let cursor = undefined;

  while (true) {
    const products = await prisma.product.findMany({
      take: BATCH,
      ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
      orderBy: { id: "asc" },
      include: {
        category: { select: { name: true } },
        brand: { select: { name: true } },
        variants: {
          where: { deletedAt: null, isActive: true },
          include: {
            options: { include: { option: { select: { value: true } } } },
          },
        },
      },
    });

    if (products.length === 0) break;

    for (const product of products) {
      const newText = buildProductSearchText(product);
      // Pakai raw SQL supaya script ini jalan tanpa harus regenerate Prisma
      // client (kolom searchText di schema ditambahkan migration baru).
      if (newText === (product.searchText ?? "")) {
        skipped++;
      } else {
        await prisma.$executeRaw`
          UPDATE "Product" SET "searchText" = ${newText} WHERE id = ${product.id}
        `;
        updated++;
      }
      processed++;
    }

    cursor = products[products.length - 1].id;
    console.log(`   [${processed}/${total}] updated=${updated} unchanged=${skipped}`);
  }

  console.log(`\nSelesai. Updated: ${updated}, unchanged: ${skipped}, total: ${processed}`);
}

main()
  .catch((e) => {
    console.error("Error:", e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());

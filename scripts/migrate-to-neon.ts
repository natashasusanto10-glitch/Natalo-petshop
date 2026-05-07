/**
 * One-shot migration: copy data from local Postgres → Neon production.
 * Usage: npx tsx scripts/migrate-to-neon.ts
 *
 * Reads `LOCAL_DATABASE_URL` for source. Falls back to localhost.
 * Reads `DATABASE_URL` (from .env) for destination = Neon.
 */
import { PrismaClient } from "@prisma/client";

const LOCAL_URL =
  process.env.LOCAL_DATABASE_URL ||
  "postgresql://postgres:postgres@localhost:5432/toko_pwa?schema=public";

const local = new PrismaClient({ datasources: { db: { url: LOCAL_URL } } });
const neon = new PrismaClient(); // pakai DATABASE_URL dari .env (= Neon)

async function copyTable<T extends { id: string }>(
  name: string,
  fetch: () => Promise<T[]>,
  upsert: (row: T) => Promise<unknown>,
) {
  const rows = await fetch();
  process.stdout.write(`${name}: ${rows.length} rows... `);
  let ok = 0;
  let fail = 0;
  for (const row of rows) {
    try {
      await upsert(row);
      ok++;
    } catch (e) {
      fail++;
      if (fail <= 3) {
        console.error(`\n  fail ${row.id}:`, (e as Error).message.slice(0, 100));
      }
    }
  }
  console.log(`done (ok=${ok}, fail=${fail})`);
}

async function main() {
  console.log("=== Migrate local Postgres → Neon ===\n");

  // 1. Category (no FK)
  await copyTable(
    "Category",
    () => local.category.findMany(),
    (r) => neon.category.upsert({ where: { id: r.id }, create: r, update: r }),
  );

  // 2. Brand
  await copyTable(
    "Brand",
    () => local.brand.findMany(),
    (r) => neon.brand.upsert({ where: { id: r.id }, create: r, update: r }),
  );

  // 3. Product (FK ke Category, Brand)
  await copyTable(
    "Product",
    () => local.product.findMany(),
    (r) => neon.product.upsert({ where: { id: r.id }, create: r as any, update: r as any }),
  );

  // 4. VariantAttribute (FK ke Product)
  await copyTable(
    "VariantAttribute",
    () => local.variantAttribute.findMany(),
    (r) => neon.variantAttribute.upsert({ where: { id: r.id }, create: r, update: r }),
  );

  // 5. VariantOption (FK ke VariantAttribute)
  await copyTable(
    "VariantOption",
    () => local.variantOption.findMany(),
    (r) => neon.variantOption.upsert({ where: { id: r.id }, create: r, update: r }),
  );

  // 6. ProductVariant (FK ke Product)
  await copyTable(
    "ProductVariant",
    () => local.productVariant.findMany(),
    (r) => neon.productVariant.upsert({ where: { id: r.id }, create: r, update: r }),
  );

  // 7. ProductVariantOption (FK ke ProductVariant + VariantOption)
  await copyTable(
    "ProductVariantOption",
    () => local.productVariantOption.findMany(),
    (r) => neon.productVariantOption.upsert({ where: { id: r.id }, create: r, update: r }),
  );

  console.log("\n=== Final Neon counts ===");
  console.log("Categories:", await neon.category.count());
  console.log("Brands:", await neon.brand.count());
  console.log("Products:", await neon.product.count());
  console.log("Variants:", await neon.productVariant.count());
}

main()
  .catch(console.error)
  .finally(async () => {
    await local.$disconnect();
    await neon.$disconnect();
  });

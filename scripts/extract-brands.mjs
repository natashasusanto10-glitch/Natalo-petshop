/**
 * Hybrid brand extraction:
 *   1. Buat semua brand di KNOWN_BRANDS sebagai master data
 *   2. Loop semua produk dengan brandId=null
 *   3. Match prefix nama → assign brandId + brandAutoAssigned=true
 *   4. Hasilnya admin tinggal review yang perlu koreksi via /admin/brands/review
 *
 * Cara pakai:
 *   node scripts/extract-brands.mjs            (eksekusi)
 *   node scripts/extract-brands.mjs --dry-run  (preview)
 *
 * Aman dijalankan berkali-kali (idempotent).
 */

import { createRequire } from "module";

const require = createRequire(import.meta.url);
const { PrismaClient } = require("@prisma/client");
const prisma = new PrismaClient();

const DRY_RUN = process.argv.includes("--dry-run");

// Daftar brand pet industry yang umum di pasar Indonesia.
// Diurutkan PALING PANJANG dulu agar match akurat
// (e.g., "Royal Canin" akan match sebelum sekedar "Royal").
const KNOWN_BRANDS = [
  "Nature Bridge",
  "Crystal Kitty",
  "Kitchen Flavor",
  "Animal & Co",
  "Sakkai Pro",
  "Healthy Pet",
  "Pet Expert",
  "Top Growth",
  "Dog Choize",
  "Royal Canin",
  "Happy Dog",
  "Pro Plan",
  "Nice Cat",
  "Nice Dog",
  "Supercat",
  "Liberator",
  "Vetauro",
  "Bravery",
  "Whiskas",
  "Friskies",
  "NexGard",
  "Bioline",
  "Beaphar",
  "Raffeed",
  "Nutrition",
  "Drontal",
  "M-PETS",
  "Hailong",
  "Kandila",
  "Hammy",
  "Hokky",
  "Wolly",
  "FURBO",
  "Cesar",
  "Inaba",
  "Anthel",
  "T-Bone",
  "Doris",
  "Angels",
  "Prama",
  "Malco",
  "Amara",
  "Adex",
  "Cleo",
  "Ciao",
  "Sobo",
  "Yang",
  "Pawfish",
  "Me-O",
];

function slugify(name) {
  return name
    .toLowerCase()
    .replace(/&/g, "and")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");
}

function findBrand(productName, sortedBrands) {
  const lower = productName.toLowerCase().trim();
  for (const brand of sortedBrands) {
    const brandLower = brand.toLowerCase();
    // Match: produk diawali brand + spasi/dash/tanda baca
    if (
      lower === brandLower ||
      lower.startsWith(brandLower + " ") ||
      lower.startsWith(brandLower + "-") ||
      lower.startsWith(brandLower + ".") ||
      lower.startsWith(brandLower + ",")
    ) {
      return brand;
    }
  }
  return null;
}

async function main() {
  console.log("=".repeat(60));
  console.log("  Hybrid Brand Extraction");
  console.log("=".repeat(60));
  if (DRY_RUN) console.log("🔍 DRY RUN — tidak ada yang ditulis ke database\n");

  // ── Step 1: Pastikan semua brand di KNOWN_BRANDS ada di tabel ─
  const sortedBrands = [...KNOWN_BRANDS].sort((a, b) => b.length - a.length);

  const brandMap = {};
  let createdBrands = 0;

  for (const name of KNOWN_BRANDS) {
    const slug = slugify(name);
    let brand = await prisma.brand.findUnique({ where: { slug } });
    if (!brand) {
      if (!DRY_RUN) {
        brand = await prisma.brand.create({ data: { name, slug } });
      } else {
        brand = { id: `(new)-${slug}`, name, slug };
      }
      createdBrands++;
    }
    brandMap[name] = brand.id;
  }
  console.log(`📦 Brand terdaftar: ${KNOWN_BRANDS.length} (baru dibuat: ${createdBrands})\n`);

  // ── Step 2: Match produk yang brandId=null ──────────────────
  const products = await prisma.product.findMany({
    where: { brandId: null },
    select: { id: true, name: true },
  });

  console.log(`🔎 Memproses ${products.length} produk tanpa brand...\n`);

  let matched = 0;
  let unmatched = 0;
  const matchSamples = [];
  const unmatchedSamples = [];

  for (const p of products) {
    const brandName = findBrand(p.name, sortedBrands);
    if (brandName) {
      matched++;
      if (matchSamples.length < 5) {
        matchSamples.push(`${brandName.padEnd(15)} → ${p.name.slice(0, 60)}`);
      }
      if (!DRY_RUN) {
        await prisma.product.update({
          where: { id: p.id },
          data: {
            brandId: brandMap[brandName],
            brandAutoAssigned: true,
          },
        });
      }
    } else {
      unmatched++;
      if (unmatchedSamples.length < 5) {
        unmatchedSamples.push(p.name.slice(0, 70));
      }
    }
  }

  // ── Print hasil ──────────────────────────────────────────────
  if (matchSamples.length > 0) {
    console.log("✅ Contoh produk yang di-auto-assign:");
    matchSamples.forEach((s) => console.log(`   ${s}`));
    console.log("");
  }
  if (unmatchedSamples.length > 0) {
    console.log("⚠️  Contoh produk yang TIDAK match (perlu manual):");
    unmatchedSamples.forEach((s) => console.log(`   ${s}`));
    console.log("");
  }

  console.log("=".repeat(60));
  console.log(`✅ Auto-assigned    : ${matched} produk (perlu admin review)`);
  console.log(`❓ Tanpa brand match : ${unmatched} produk (assign manual via admin)`);
  console.log("=".repeat(60));
  console.log("");
  console.log("Langkah selanjutnya:");
  console.log("  1. Buka /admin/brands/review untuk verify hasil auto-assign");
  console.log("  2. Buka /admin/products?brand=null untuk assign manual yang belum match");
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());

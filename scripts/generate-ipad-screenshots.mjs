// Generate iPad 13" App Store screenshots dari iPhone 6.7" screenshots
// yang sudah ada. Pakai sharp untuk composite iPhone PNG ke center
// iPad-sized canvas (2064×2752) dengan brand-blue letterbox margin.
//
// Apple accept letterboxed iPhone screenshots untuk iPad submission selama
// dimensi exact match. Solusi practical untuk app mobile-first yang build
// Universal (iPhone + iPad) tapi UI optimized untuk iPhone.
//
// Output: screenshots/appstore-ipad13/01-home.png ... 05-privacy.png
// Upload ke App Store Connect → Distribution → Previews and Screenshots
// → iPad 13" Display.
//
// Prerequisite: jalanin `node scripts/generate-appstore-screenshots.mjs` dulu
// untuk generate iPhone 6.7" screenshots (1290×2796).
//
// Run: node scripts/generate-ipad-screenshots.mjs

import sharp from "sharp";
import { mkdirSync, existsSync, readdirSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, "..");

// iPad 13" Display App Store screenshot spec:
// - Portrait: 2064 × 2752 px
// - Apple accept ini sebagai "13-inch iPad displays" requirement
const IPAD_WIDTH = 2064;
const IPAD_HEIGHT = 2752;

// Source iPhone screenshots (1290 × 2796)
const SRC_DIR = resolve(ROOT, "screenshots", "appstore-67");
const OUT_DIR = resolve(ROOT, "screenshots", "appstore-ipad13");

const BRAND_BLUE = "#1E5FBF";
const BRAND_BLUE_DARK = "#0F2D5C";

async function generateOne(filename) {
  const srcPath = resolve(SRC_DIR, filename);
  const outPath = resolve(OUT_DIR, filename);

  // Source iPhone screenshot dimensions
  const srcMeta = await sharp(srcPath).metadata();
  const srcWidth = srcMeta.width;
  const srcHeight = srcMeta.height;

  // Scale iPhone screenshot supaya muat di iPad portrait dengan margin
  // Hitung scale ratio dengan mempertahankan aspect ratio iPhone
  // Target: iPhone screenshot fit di vertical 95% dari iPad height
  const targetHeight = Math.round(IPAD_HEIGHT * 0.95);
  const scale = targetHeight / srcHeight;
  const scaledWidth = Math.round(srcWidth * scale);
  const scaledHeight = Math.round(srcHeight * scale);

  // Center position
  const left = Math.round((IPAD_WIDTH - scaledWidth) / 2);
  const top = Math.round((IPAD_HEIGHT - scaledHeight) / 2);

  // Resize iPhone screenshot
  const resizedBuffer = await sharp(srcPath)
    .resize(scaledWidth, scaledHeight, { fit: "fill" })
    .png()
    .toBuffer();

  // Create iPad canvas dengan gradient brand-blue background
  const bgSvg = Buffer.from(`<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${IPAD_WIDTH}" height="${IPAD_HEIGHT}" viewBox="0 0 ${IPAD_WIDTH} ${IPAD_HEIGHT}">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="${BRAND_BLUE_DARK}"/>
      <stop offset="100%" stop-color="${BRAND_BLUE}"/>
    </linearGradient>
  </defs>
  <rect width="${IPAD_WIDTH}" height="${IPAD_HEIGHT}" fill="url(#bg)"/>
</svg>
`);

  // Composite iPhone screenshot ke center iPad canvas
  await sharp(bgSvg)
    .composite([
      {
        input: resizedBuffer,
        top: top,
        left: left,
      },
    ])
    .png({ compressionLevel: 9 })
    .toFile(outPath);

  const outMeta = await sharp(outPath).metadata();
  console.log(
    `   ✓ ${filename}  ${outMeta.width}×${outMeta.height}  iPhone center @ ${left},${top}`,
  );
}

async function main() {
  if (!existsSync(SRC_DIR)) {
    console.error(`❌ Source dir not found: ${SRC_DIR}`);
    console.error(`   Run \`node scripts/generate-appstore-screenshots.mjs\` first.`);
    process.exit(1);
  }

  if (!existsSync(OUT_DIR)) mkdirSync(OUT_DIR, { recursive: true });

  const files = readdirSync(SRC_DIR).filter((f) => f.endsWith(".png"));

  console.log(`📦 Generating iPad 13" screenshots (2064×2752)`);
  console.log(`   Source: ${SRC_DIR} (${files.length} iPhone PNGs)`);
  console.log(`   Output: ${OUT_DIR}\n`);

  for (const filename of files) {
    await generateOne(filename);
  }

  console.log(`\n✅ Done. Upload PNG di folder ke App Store Connect:`);
  console.log(`   appstoreconnect.apple.com → Natalo Petshop → Distribution`);
  console.log(`   → iOS App 1.0 → Previews and Screenshots → iPad 13" Display`);
  console.log(`   Cukup upload 1 PNG aja (minimum Apple requirement untuk 13" iPad).`);
}

main().catch((err) => {
  console.error("❌ Generator failed:", err);
  process.exit(1);
});

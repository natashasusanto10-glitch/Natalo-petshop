// Generate splash source untuk Capacitor (iOS + Android native splash).
// Style: Netflix-inspired — solid brand bg + ONLY logo putih (no icon frame).
//
// Approach:
// 1. Read icon-512x512.png (yang punya bg biru terang + logo putih NL+paw)
// 2. Threshold: keep pixels yang dominan putih (R+G+B > ~720), drop biru bg
// 3. Composite hasil mask di tengah splash 2732×2732 brand blue
//
// Run: node scripts/generate-capacitor-splash.mjs

import sharp from "sharp";
import { mkdirSync, existsSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, "..");

const SOURCE_ICON = resolve(ROOT, "public/icons/icon-512x512.png");
const OUT_DIR = resolve(ROOT, "resources");
const SPLASH_SIZE = 2732;
const BG = { r: 30, g: 95, b: 191, alpha: 1 }; // #1E5FBF
const BG_DARK = { r: 15, g: 45, b: 92, alpha: 1 }; // #0F2D5C
const LOGO_RATIO = 0.55; // 55% — Netflix-style dominant

// Threshold untuk extract logo putih: pixel yang R+G+B-nya tinggi = bagian putih (logo)
// Pixel biru (R rendah, G & B tinggi tapi tidak terlalu) → drop ke transparent.
const WHITE_THRESHOLD = 720; // dari max 765 (255*3)

async function extractWhiteLogo(inputPath) {
  const img = sharp(inputPath).ensureAlpha();
  const { data, info } = await img.raw().toBuffer({ resolveWithObject: true });
  const { width, height, channels } = info;

  // Buffer baru: keep pixel kalau white-ish, kalau enggak set alpha=0
  const out = Buffer.alloc(data.length);
  for (let i = 0; i < data.length; i += channels) {
    const r = data[i];
    const g = data[i + 1];
    const b = data[i + 2];
    const a = channels === 4 ? data[i + 3] : 255;
    const sum = r + g + b;
    if (sum >= WHITE_THRESHOLD && a > 128) {
      // White-ish → keep as pure white
      out[i] = 255;
      out[i + 1] = 255;
      out[i + 2] = 255;
      out[i + 3] = 255;
    } else {
      // Drop ke transparent
      out[i] = 0;
      out[i + 1] = 0;
      out[i + 2] = 0;
      out[i + 3] = 0;
    }
  }

  return sharp(out, { raw: { width, height, channels: 4 } }).png().toBuffer();
}

async function generateOne(outName, bgColor) {
  const logoSize = Math.round(SPLASH_SIZE * LOGO_RATIO);

  // Extract white-only logo dari icon source
  const whiteLogo = await extractWhiteLogo(SOURCE_ICON);

  // Resize ke logoSize dengan fit:contain biar gak distorted
  const logoResized = await sharp(whiteLogo)
    .resize(logoSize, logoSize, {
      fit: "contain",
      background: { r: 0, g: 0, b: 0, alpha: 0 },
    })
    .png()
    .toBuffer();

  // Composite di canvas brand
  const out = resolve(OUT_DIR, outName);
  await sharp({
    create: {
      width: SPLASH_SIZE,
      height: SPLASH_SIZE,
      channels: 4,
      background: bgColor,
    },
  })
    .composite([{ input: logoResized, gravity: "center" }])
    .png({ compressionLevel: 9 })
    .toFile(out);

  console.log(`✓ ${outName}  ${SPLASH_SIZE}×${SPLASH_SIZE}  logo ${logoSize}px (${Math.round(LOGO_RATIO * 100)}%)`);
}

async function generate() {
  if (!existsSync(SOURCE_ICON)) {
    console.error(`❌ Source icon tidak ditemukan: ${SOURCE_ICON}`);
    process.exit(1);
  }
  if (!existsSync(OUT_DIR)) mkdirSync(OUT_DIR, { recursive: true });

  console.log(`📦 Generating Netflix-style splash (white logo only, no frame)...`);
  console.log(`   Source: ${SOURCE_ICON}`);
  console.log(`   Output: ${OUT_DIR}\n`);

  await generateOne("splash.png", BG);
  await generateOne("splash-dark.png", BG_DARK);

  console.log(`\n✅ Done. Run \`npm run cap:assets\` untuk generate per-device images.`);
}

generate().catch((err) => {
  console.error("❌ Generator gagal:", err);
  process.exit(1);
});

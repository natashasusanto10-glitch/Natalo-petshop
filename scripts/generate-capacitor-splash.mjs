// Generate splash source untuk Capacitor (iOS + Android native splash).
// Output: resources/splash.png (2732×2732) — brand blue + logo centered.
// CI workflow akan jalan `npm run cap:assets` yang generate semua ukuran
// per-device dari file ini ke ios/App/App/Assets.xcassets/Splash.imageset/.
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
const SPLASH_SIZE = 2732; // Capacitor recommended source resolution
const BG = { r: 30, g: 95, b: 191, alpha: 1 }; // #1E5FBF Natalo brand
const BG_DARK = { r: 15, g: 45, b: 92, alpha: 1 }; // natalo-800 #0F2D5C dark variant
const LOGO_RATIO = 0.45; // 45% dari canvas — logo dominant, "N" putih jelas terlihat
                          // Sebelumnya 30% kelihatan terlalu kecil di splash full-screen
                          // karena icon source punya bg biru yang blend dengan splash bg.

async function generateOne(outName, bgColor) {
  const logoSize = Math.round(SPLASH_SIZE * LOGO_RATIO);
  const logoBuffer = await sharp(SOURCE_ICON)
    .resize(logoSize, logoSize, { fit: "contain", background: { r: 0, g: 0, b: 0, alpha: 0 } })
    .png()
    .toBuffer();

  const out = resolve(OUT_DIR, outName);
  await sharp({
    create: {
      width: SPLASH_SIZE,
      height: SPLASH_SIZE,
      channels: 4,
      background: bgColor,
    },
  })
    .composite([{ input: logoBuffer, gravity: "center" }])
    .png({ compressionLevel: 9 })
    .toFile(out);

  console.log(`✓ ${outName}  ${SPLASH_SIZE}×${SPLASH_SIZE}`);
}

async function generate() {
  if (!existsSync(SOURCE_ICON)) {
    console.error(`❌ Source icon tidak ditemukan: ${SOURCE_ICON}`);
    process.exit(1);
  }
  if (!existsSync(OUT_DIR)) mkdirSync(OUT_DIR, { recursive: true });

  console.log(`📦 Generating Capacitor splash sources...`);
  console.log(`   Source icon: ${SOURCE_ICON}`);
  console.log(`   Output dir : ${OUT_DIR}\n`);

  await generateOne("splash.png", BG);
  await generateOne("splash-dark.png", BG_DARK);

  console.log(`\n✅ Done. Run \`npm run cap:assets\` di Mac/CI untuk generate per-device images.`);
}

generate().catch((err) => {
  console.error("❌ Generator gagal:", err);
  process.exit(1);
});

// Generate iOS PWA splash screens dari icon-512x512.png + brand color.
// Output: public/splash/*.png + log media query untuk dipakai di layout.tsx
//
// Run: node scripts/generate-ios-splash.mjs

import sharp from "sharp";
import { mkdirSync, existsSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, "..");

const SOURCE_ICON = resolve(ROOT, "public/icons/icon-512x512.png");
const OUT_DIR = resolve(ROOT, "public/splash");
const BG_COLOR = { r: 30, g: 95, b: 191, alpha: 1 }; // #1E5FBF (Natalo brand)

// iPhone splash sizes (portrait). Format: [width_px, height_px, deviceLabel, mediaQuery]
// Media query: device-width × device-height (CSS pt) + DPR
// Sumber resmi: https://developer.apple.com/design/human-interface-guidelines/foundations/layout/
const SPLASH_SIZES = [
  // iPhone 16 Pro Max (6.9") — 1320×2868, device-width 440pt
  [1320, 2868, "iphone-16-pro-max-portrait", "(device-width: 440px) and (device-height: 956px) and (-webkit-device-pixel-ratio: 3) and (orientation: portrait)"],
  // iPhone 16 Pro (6.3") — 1206×2622, device-width 402pt
  [1206, 2622, "iphone-16-pro-portrait", "(device-width: 402px) and (device-height: 874px) and (-webkit-device-pixel-ratio: 3) and (orientation: portrait)"],
  // iPhone 16 Plus / 15 Pro Max / 15 Plus (6.7") — 1290×2796, device-width 430pt
  [1290, 2796, "iphone-15-pro-max-portrait", "(device-width: 430px) and (device-height: 932px) and (-webkit-device-pixel-ratio: 3) and (orientation: portrait)"],
  // iPhone 16 / 15 / 14 Pro (6.1") — 1179×2556, device-width 393pt
  [1179, 2556, "iphone-15-portrait", "(device-width: 393px) and (device-height: 852px) and (-webkit-device-pixel-ratio: 3) and (orientation: portrait)"],
  // iPhone 14 Pro Max / 13 Pro Max / 14 Plus / 12 Pro Max (6.7") — 1284×2778
  [1284, 2778, "iphone-14-pro-max-portrait", "(device-width: 428px) and (device-height: 926px) and (-webkit-device-pixel-ratio: 3) and (orientation: portrait)"],
  // iPhone 14 / 13 / 13 Pro / 12 / 12 Pro (6.1") — 1170×2532
  [1170, 2532, "iphone-14-portrait", "(device-width: 390px) and (device-height: 844px) and (-webkit-device-pixel-ratio: 3) and (orientation: portrait)"],
  // iPhone 13 mini / 12 mini / 11 Pro / X / XS (5.4-5.8") — 1125×2436
  [1125, 2436, "iphone-12-mini-portrait", "(device-width: 375px) and (device-height: 812px) and (-webkit-device-pixel-ratio: 3) and (orientation: portrait)"],
  // iPhone 11 Pro Max / XS Max (6.5") — 1242×2688
  [1242, 2688, "iphone-xs-max-portrait", "(device-width: 414px) and (device-height: 896px) and (-webkit-device-pixel-ratio: 3) and (orientation: portrait)"],
  // iPhone 11 / XR (6.1" @2x) — 828×1792
  [828, 1792, "iphone-xr-portrait", "(device-width: 414px) and (device-height: 896px) and (-webkit-device-pixel-ratio: 2) and (orientation: portrait)"],
  // iPhone 8 Plus / 7 Plus / 6S Plus / 6 Plus (5.5") — 1242×2208
  [1242, 2208, "iphone-8-plus-portrait", "(device-width: 414px) and (device-height: 736px) and (-webkit-device-pixel-ratio: 3) and (orientation: portrait)"],
  // iPhone SE 2nd/3rd gen / 8 / 7 / 6S / 6 (4.7") — 750×1334
  [750, 1334, "iphone-se-portrait", "(device-width: 375px) and (device-height: 667px) and (-webkit-device-pixel-ratio: 2) and (orientation: portrait)"],
  // FALLBACK universal — tanpa media query, dipakai iOS kalau resolusi device tidak match satupun di atas.
  // 1290×2796 (iPhone 16 Plus size) — kompromi tengah, scale baik di smaller/larger devices.
  [1290, 2796, "fallback", null],
];

async function generate() {
  if (!existsSync(SOURCE_ICON)) {
    console.error(`❌ Source icon tidak ditemukan: ${SOURCE_ICON}`);
    process.exit(1);
  }
  if (!existsSync(OUT_DIR)) mkdirSync(OUT_DIR, { recursive: true });

  console.log(`📦 Generating ${SPLASH_SIZES.length} iOS splash images...`);
  console.log(`   Source: ${SOURCE_ICON}`);
  console.log(`   Output: ${OUT_DIR}`);
  console.log(`   BG: rgb(${BG_COLOR.r}, ${BG_COLOR.g}, ${BG_COLOR.b})\n`);

  const linkTags = [];

  for (const [width, height, label, mediaQuery] of SPLASH_SIZES) {
    // Logo size: 30% dari dimensi terkecil
    const logoSize = Math.round(Math.min(width, height) * 0.3);
    const logoBuffer = await sharp(SOURCE_ICON)
      .resize(logoSize, logoSize, { fit: "contain", background: { r: 0, g: 0, b: 0, alpha: 0 } })
      .png()
      .toBuffer();

    // Canvas brand color, logo di tengah
    const outFile = resolve(OUT_DIR, `${label}.png`);
    await sharp({
      create: {
        width,
        height,
        channels: 4,
        background: BG_COLOR,
      },
    })
      .composite([{ input: logoBuffer, gravity: "center" }])
      .png({ compressionLevel: 9 })
      .toFile(outFile);

    console.log(`✓ ${label}.png  ${width}×${height}`);

    if (mediaQuery) {
      linkTags.push(
        `<link rel="apple-touch-startup-image" href="/splash/${label}.png" media="${mediaQuery}" />`
      );
    } else {
      linkTags.push(
        `<link rel="apple-touch-startup-image" href="/splash/${label}.png" />`
      );
    }
  }

  console.log("\n📋 Copy meta tag berikut ke <head> di app/layout.tsx (atau sudah handled):\n");
  console.log(linkTags.join("\n"));
  console.log("\n✅ Done.");
}

generate().catch((err) => {
  console.error("❌ Generator gagal:", err);
  process.exit(1);
});
